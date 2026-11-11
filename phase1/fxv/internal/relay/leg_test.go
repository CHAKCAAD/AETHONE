package relay

// The relay leg tests: the route order and its preference memory, the
// soft deadline that ends a hanging route (only while others remain),
// the never-re-send guards (a body that cannot be replayed, a request
// that carries one), the retryable-error set, the workers.dev edge
// route's URL/Host rewrite, and the shapes newRelayLeg builds.

import (
        "context"
        "errors"
        "fmt"
        "io"
        "net"
        "net/http"
        "net/url"
        "strings"
        "syscall"
        "testing"
        "time"
)

// ---------------------------------------------------------------------------
// fakes
// ---------------------------------------------------------------------------

// legFake is one route: it counts its calls, can hang, can fail.
type legFake struct {
        calls  int
        err    error
        hang   time.Duration
        status int
}

func (f *legFake) RoundTrip(req *http.Request) (*http.Response, error) {
        f.calls++
        if f.hang > 0 {
                select {
                case <-time.After(f.hang):
                case <-req.Context().Done():
                        return nil, req.Context().Err()
                }
        }
        if f.err != nil {
                return nil, f.err
        }
        if f.status == 0 {
                f.status = 200
        }
        return &http.Response{
                StatusCode: f.status,
                Status:     fmt.Sprintf("%d %s", f.status, http.StatusText(f.status)),
                Header:     make(http.Header),
                Body:       io.NopCloser(strings.NewReader(`{}`)),
                Request:    req,
        }, nil
}

// fakeNetTimeout is a net.Error that IS a timeout.
type fakeNetTimeout struct{}

func (fakeNetTimeout) Error() string   { return "fake i/o timeout" }
func (fakeNetTimeout) Timeout() bool   { return true }
func (fakeNetTimeout) Temporary() bool { return true }

// fakeNetError is a net.Error that is NOT a timeout.
type fakeNetError struct{}

func (fakeNetError) Error() string   { return "fake refused-ish error" }
func (fakeNetError) Timeout() bool   { return false }
func (fakeNetError) Temporary() bool { return false }

// recordingBase records the request an edgeRouteTransport rewrote.
type recordingBase struct {
        calls  int
        last   *http.Request
        status int
}

func (b *recordingBase) RoundTrip(req *http.Request) (*http.Response, error) {
        b.calls++
        b.last = req
        if b.status == 0 {
                b.status = 200
        }
        return &http.Response{
                StatusCode: b.status,
                Status:     fmt.Sprintf("%d %s", b.status, http.StatusText(b.status)),
                Header:     make(http.Header),
                Body:       io.NopCloser(strings.NewReader(`{}`)),
                Request:    req,
        }, nil
}

func legGet(t *testing.T) *http.Request {
        t.Helper()
        req, err := http.NewRequest(http.MethodGet, "https://relay.example/path", nil)
        if err != nil {
                t.Fatal(err)
        }
        return req
}

// ---------------------------------------------------------------------------
// the route walk
// ---------------------------------------------------------------------------

func TestLegPrimaryFirstAndPreferenceMemory(t *testing.T) {
        primary, tls12 := &legFake{}, &legFake{}
        leg := &relayLeg{primary: primary, tls12: tls12}

        if _, err := leg.RoundTrip(legGet(t)); err != nil {
                t.Fatal(err)
        }
        if primary.calls != 1 || tls12.calls != 0 {
                t.Fatalf("primary must serve alone: primary=%d tls12=%d", primary.calls, tls12.calls)
        }

        // The primary starts timing out; the TLS 1.2 route takes over and
        // is REMEMBERED as the preferred one.
        primary.err = fakeNetTimeout{}
        if _, err := leg.RoundTrip(legGet(t)); err != nil {
                t.Fatal(err)
        }
        if tls12.calls != 1 {
                t.Fatalf("the tls12 route must take over, calls=%d", tls12.calls)
        }

        primary.calls, tls12.calls = 0, 0
        primary.err = nil
        if _, err := leg.RoundTrip(legGet(t)); err != nil {
                t.Fatal(err)
        }
        if primary.calls != 0 || tls12.calls != 1 {
                t.Fatalf("the remembered route must go first: primary=%d tls12=%d", primary.calls, tls12.calls)
        }
}

func TestLegSoftDeadlineEndsHangingRoute(t *testing.T) {
        primary, tls12 := &legFake{hang: 5 * time.Second}, &legFake{}
        leg := &relayLeg{primary: primary, tls12: tls12}

        // A 900ms deadline over two routes budgets ~450ms for the hanging
        // primary: it must be cut off and the fast tls12 route must finish
        // well inside the deadline.
        ctx, cancel := context.WithTimeout(context.Background(), 900*time.Millisecond)
        defer cancel()
        req := legGet(t).WithContext(ctx)

        start := time.Now()
        if _, err := leg.RoundTrip(req); err != nil {
                t.Fatal(err)
        }
        if elapsed := time.Since(start); elapsed > 850*time.Millisecond {
                t.Fatalf("the soft deadline must cut the hanging route off, took %s", elapsed)
        }
        if tls12.calls != 1 {
                t.Fatalf("the next route must serve, calls=%d", tls12.calls)
        }
}

func TestLegNonReplayableTakesOneRoute(t *testing.T) {
        primary, tls12 := &legFake{err: fakeNetTimeout{}}, &legFake{}
        leg := &relayLeg{primary: primary, tls12: tls12}

        req := legGet(t)
        req.Method = http.MethodPost
        req.Body = io.NopCloser(strings.NewReader(`{}`))
        req.GetBody = nil // NOT replayable

        if _, err := leg.RoundTrip(req); err == nil {
                t.Fatal("the primary error must surface")
        }
        if tls12.calls != 0 {
                t.Fatalf("a non-replayable request must never take a second route, tls12=%d", tls12.calls)
        }
}

func TestLegBodyBearingGETTakesOneRoute(t *testing.T) {
        // A GET with a body has an ambiguous delivery state after a
        // timeout too (the write may have happened): one route only.
        primary, tls12 := &legFake{err: fakeNetTimeout{}}, &legFake{}
        leg := &relayLeg{primary: primary, tls12: tls12}

        req := legGet(t)
        req.Body = io.NopCloser(strings.NewReader(`{}`))
        req.GetBody = func() (io.ReadCloser, error) {
                return io.NopCloser(strings.NewReader(`{}`)), nil
        }

        if _, err := leg.RoundTrip(req); err == nil {
                t.Fatal("the primary error must surface")
        }
        if tls12.calls != 0 {
                t.Fatalf("a body-bearing GET must never take a second route, tls12=%d", tls12.calls)
        }
}

func TestLegStopsOnContextCancel(t *testing.T) {
        primary, tls12 := &legFake{err: fakeNetTimeout{}}, &legFake{err: fakeNetTimeout{}}
        leg := &relayLeg{primary: primary, tls12: tls12}

        ctx, cancel := context.WithCancel(context.Background())
        cancel()
        req := legGet(t).WithContext(ctx)
        if _, err := leg.RoundTrip(req); !errors.Is(err, context.Canceled) {
                t.Fatalf("a cancelled request must surface the cancellation, got %v", err)
        }
        if primary.calls+tls12.calls != 0 {
                t.Fatal("no route may be dialed for a cancelled request")
        }
}

// ---------------------------------------------------------------------------
// the retryable set
// ---------------------------------------------------------------------------

func TestLegRetryable(t *testing.T) {
        cases := []struct {
                name string
                err  error
                want bool
        }{
                {"dns error", &net.DNSError{Err: "no such host", Name: "relay.example", IsNotFound: true}, true},
                {"timeout", fakeNetTimeout{}, true},
                {"eof", io.EOF, true},
                {"unexpected eof", io.ErrUnexpectedEOF, true},
                {"connection reset", fmt.Errorf("write: %w", syscall.ECONNRESET), true},
                {"connection refused", fmt.Errorf("dial: %w", syscall.ECONNREFUSED), true},
                {"network unreachable", fmt.Errorf("dial: %w", syscall.ENETUNREACH), true},
                {"host unreachable", fmt.Errorf("dial: %w", syscall.EHOSTUNREACH), true},
                {"plain error", errors.New("something else"), false},
                {"non-timeout net error", fakeNetError{}, false},
                {"tls certificate error", fmt.Errorf("x509: certificate signed by unknown authority"), false},
        }
        for _, c := range cases {
                t.Run(c.name, func(t *testing.T) {
                        if got := legRetryable(c.err); got != c.want {
                                t.Fatalf("legRetryable = %t, want %t", got, c.want)
                        }
                })
        }
}

// ---------------------------------------------------------------------------
// the edge route
// ---------------------------------------------------------------------------

func TestEdgeRouteRewritesConnectionNotIdentity(t *testing.T) {
        base := &recordingBase{}
        edge := &edgeRouteTransport{base: base}

        req, _ := http.NewRequest(http.MethodGet, "https://my.worker.workers.dev/relay?secret=s", nil)
        resp, err := edge.RoundTrip(req)
        if err != nil {
                t.Fatal(err)
        }
        resp.Body.Close()

        if base.calls != 1 {
                t.Fatalf("the base transport must serve once, got %d", base.calls)
        }
        // The CONNECTION went to the edge address...
        if base.last.URL.Host != legEdgeAddress {
                t.Fatalf("the connection URL host = %q, want the edge address %q", base.last.URL.Host, legEdgeAddress)
        }
        // ...while the HTTP Host still names the relay (Cloudflare's edge
        // routes by Host), and the path/query ride unchanged.
        if base.last.Host != "my.worker.workers.dev" {
                t.Fatalf("the HTTP Host = %q, want the relay's own name", base.last.Host)
        }
        if base.last.URL.Path != "/relay" || base.last.URL.RawQuery != "secret=s" {
                t.Fatalf("path/query must ride unchanged, got %q ?%s", base.last.URL.Path, base.last.URL.RawQuery)
        }
        if resp.Request != req {
                t.Fatal("the response must stay attached to the original request")
        }
}

// ---------------------------------------------------------------------------
// the shapes newRelayLeg builds
// ---------------------------------------------------------------------------

func TestNewRelayLegShapes(t *testing.T) {
        // require mode: the primary alone — no fallback routes exist.
        plain, _ := url.Parse("https://relay.example/")
        if leg, ok := newRelayLeg(plain, Options{ECHMode: ECHModeRequire}).(*http.Transport); !ok || leg == nil {
                t.Fatal("require mode must return the bare primary transport (fail closed)")
        }

        // A non-workers.dev relay: two routes, no edge.
        if leg, ok := newRelayLeg(plain, Options{ECHMode: ECHModeOff}).(*relayLeg); !ok {
                t.Fatalf("off mode must return the route-walking leg, got %T", leg)
        } else if leg.edge != nil {
                t.Fatal("a non-workers.dev relay must not build the edge route")
        }

        // A workers.dev relay: the edge route exists.
        worker, _ := url.Parse("https://x.workers.dev/")
        if leg, ok := newRelayLeg(worker, Options{ECHMode: ECHModeOff}).(*relayLeg); !ok {
                t.Fatalf("off mode must return the route-walking leg, got %T", leg)
        } else if leg.edge == nil {
                t.Fatal("a workers.dev relay must build the edge route")
        }
}

// The ECH dialer installs a TLS dial on the primary: smoke-check that
// the mode plumbing wires the dialer (a real ECH handshake needs a real
// ECH server — ech_test.go covers the dialer's own walk).
func TestNewRelayLegECHDialerInstalled(t *testing.T) {
        plain, _ := url.Parse("https://relay.example/")
        leg, ok := newRelayLeg(plain, Options{ECHMode: ECHModeOn}).(*relayLeg)
        if !ok {
                t.Fatal("on mode must return the route-walking leg")
        }
        primary, ok := leg.primary.(*http.Transport)
        if !ok {
                t.Fatalf("the primary route must be a transport, got %T", leg.primary)
        }
        if primary.DialTLSContext == nil {
                t.Fatal("on mode must install the ECH dialer on the primary transport")
        }
        if primary.ForceAttemptHTTP2 {
                t.Fatal("the relay leg must stay HTTP/1.1")
        }
}
