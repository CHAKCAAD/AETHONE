package relay

// The stack decision-walk tests: direct passthrough, the 451 recovery
// ladder (doubled path → shared pool → personal relay), the
// connect-failure handoff, the relay-first window, the double-delivery
// guards, and the relay wire protocol itself — all against LOCAL
// servers and fakes (nothing here talks to Mozilla, a real relay, or
// the Internet; the network tags other suites carry are not needed).

import (
        "bytes"
        "errors"
        "fmt"
        "io"
        "net/http"
        "net/http/httptrace"
        "net/url"
        "strings"
        "sync/atomic"
        "testing"
)

// ---------------------------------------------------------------------------
// fakes
// ---------------------------------------------------------------------------

// fakeResponse is one canned answer of a fakeRT.
type fakeResponse struct {
        status int
        body   string
        err    error
}

// fakeRT is a direct-transport fake: it records every request and
// answers from the canned list (in order; the last one repeats).
type fakeRT struct {
        calls     []*http.Request
        answers   []fakeResponse
        last      fakeResponse
        connected bool // fire the GotConn trace before answering (mid-write)
}

func (f *fakeRT) RoundTrip(req *http.Request) (*http.Response, error) {
        f.calls = append(f.calls, req)
        if f.connected {
                // The httptrace hook viaDirect installs: prove the connection
                // was assigned before the error, so the stack must NOT retry.
                if tr := httptrace.ContextClientTrace(req.Context()); tr != nil && tr.GotConn != nil {
                        tr.GotConn(httptrace.GotConnInfo{})
                }
        }
        var a fakeResponse
        if len(f.answers) > 0 {
                a = f.answers[0]
                f.answers = f.answers[1:]
                f.last = a
        } else if f.last.status != 0 || f.last.err != nil {
                // The canned list ran out: keep answering like the last one
                // (a 451-ing direct route keeps 451-ing, a dead one stays dead).
                a = f.last
        } else {
                a = fakeResponse{status: 200, body: `{"from":"fake-default"}`}
        }
        if a.err != nil {
                return nil, a.err
        }
        return &http.Response{
                StatusCode: a.status,
                Status:     fmt.Sprintf("%d %s", a.status, http.StatusText(a.status)),
                Header:     make(http.Header),
                Body:       io.NopCloser(strings.NewReader(a.body)),
                Request:    req,
        }, nil
}

func (f *fakeRT) count() int { return len(f.calls) }

// plainBody is a request body WITHOUT GetBody (never replayable).
type plainBody struct{ r io.Reader }

func (b plainBody) Read(p []byte) (int, error) { return b.r.Read(p) }
func (b plainBody) Close() error               { return nil }

// newStack builds a stack around a fake direct transport with the
// given layers armed (nil disables them).
func newStack(direct http.RoundTripper, opts Options, personal *relayTransport, shared *sharedPool) *stack {
        normalized, err := opts.Normalize()
        if err != nil {
                panic("test options: " + err.Error())
        }
        if normalized.GuardianHost == "" {
                normalized.GuardianHost = "vpn.mozilla.org"
        }
        s := &stack{direct: direct, opts: normalized, personal: personal, shared: shared,
                logf: func(string, ...any) {}}
        return s
}

// guardianGet builds a production-shaped Guardian request.
func guardianGet(t *testing.T, path string) *http.Request {
        t.Helper()
        req, err := http.NewRequest(http.MethodGet, "https://vpn.mozilla.org"+path, nil)
        if err != nil {
                t.Fatal(err)
        }
        return req
}

// ---------------------------------------------------------------------------
// Options.Normalize
// ---------------------------------------------------------------------------

func TestOptionsNormalizePersonalURL(t *testing.T) {
        cases := []struct {
                name    string
                raw     string
                enabled bool
                want    string // "" means cleared/refused-by-shape
                wantErr bool
        }{
                {"empty stays empty", "", true, "", false},
                {"https with query kept", " https://r.example/?secret=s ", true, "https://r.example/?secret=s", false},
                {"http refused", "http://r.example/", true, "", true},
                {"credentials refused", "https://u:p@r.example/", true, "", true},
                {"fragment refused", "https://r.example/#f", true, "", true},
                {"disabled clears the in-use URL", "https://r.example/?secret=s", false, "", false},
                {"disabled garbage still refused", "http://r.example/", false, "", true},
        }
        for _, c := range cases {
                t.Run(c.name, func(t *testing.T) {
                        o := Options{PersonalRelay: c.raw, PersonalEnabled: c.enabled}
                        n, err := o.Normalize()
                        if c.wantErr {
                                if err == nil {
                                        t.Fatalf("expected a shape refusal for %q", c.raw)
                                }
                                return
                        }
                        if err != nil {
                                t.Fatalf("unexpected refusal: %v", err)
                        }
                        if n.PersonalRelay != c.want {
                                t.Fatalf("PersonalRelay = %q, want %q", n.PersonalRelay, c.want)
                        }
                })
        }
}

func TestOptionsNormalizeECH(t *testing.T) {
        if _, err := (Options{ECHMode: "sometimes"}).Normalize(); err == nil {
                t.Fatal("an unknown ECH mode must be refused")
        }
        n, err := (Options{}).Normalize()
        if err != nil {
                t.Fatal(err)
        }
        if n.ECHMode != ECHModeOn {
                t.Fatalf("empty ECH mode must default to on, got %q", n.ECHMode)
        }
        if _, err := (Options{ECHConfig: "bad name"}).Normalize(); err == nil {
                t.Fatal("an ECH config name with a space must be refused")
        }
        if _, err := (Options{ECHConfig: "name:!!!not-base64!!!"}).Normalize(); err == nil {
                t.Fatal("an ECH config key that is not base64 must be refused")
        }
        if _, err := (Options{ECHConfig: "cloudflare-ech.com"}).Normalize(); err != nil {
                t.Fatalf("a bare ECH config name must pass: %v", err)
        }
}

func TestOptionsNormalizeGuardianHostDefault(t *testing.T) {
        n, err := (Options{}).Normalize()
        if err != nil {
                t.Fatal(err)
        }
        if n.GuardianHost != "vpn.mozilla.org" {
                t.Fatalf("GuardianHost default = %q", n.GuardianHost)
        }
}

// ---------------------------------------------------------------------------
// the decision walk
// ---------------------------------------------------------------------------

func TestStackDirectPassthrough(t *testing.T) {
        direct := &fakeRT{answers: []fakeResponse{{status: 200, body: `{"ok":true}`}}}
        s := newStack(direct, Options{}, nil, nil)
        resp, err := s.RoundTrip(guardianGet(t, "/api/v1/fpn/token"))
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()
        if resp.StatusCode != 200 || direct.count() != 1 {
                t.Fatalf("status=%d directCalls=%d", resp.StatusCode, direct.count())
        }
}

func TestStack451DoubledPathRecovers(t *testing.T) {
        // The direct transport answers 451 for the literal path and 200 for
        // the doubled form — the free bypass needs no third party.
        direct := &fakeRT{}
        direct.answers = []fakeResponse{
                {status: 451, body: "unavailable_in_region"},
                {status: 200, body: `{"token":"t"}`},
        }
        s := newStack(direct, Options{}, nil, nil)
        resp, err := s.RoundTrip(guardianGet(t, "/api/v1/fpn/token"))
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()
        if resp.StatusCode != 200 {
                t.Fatalf("the doubled path must recover the 451, got %d", resp.StatusCode)
        }
        if direct.count() != 2 {
                t.Fatalf("exactly two direct calls expected, got %d", direct.count())
        }
        if p := direct.calls[1].URL.Path; p != "//api/v1/fpn/token" {
                t.Fatalf("the retry path = %q, want the doubled form", p)
        }
}

func TestStack451KeptWhenNothingRecovers(t *testing.T) {
        // No shared pool, no personal relay, a doubled path that also
        // answers 451: the ORIGINAL 451 must come back readable (the
        // upstream's GuardianHTTPError semantics depend on it).
        direct := &fakeRT{}
        direct.answers = []fakeResponse{
                {status: 451, body: "first 451"},
                {status: 451, body: "doubled 451"},
        }
        s := newStack(direct, Options{}, nil, nil)
        resp, err := s.RoundTrip(guardianGet(t, "/api/v1/fpn/token"))
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()
        if resp.StatusCode != http.StatusUnavailableForLegalReasons {
                t.Fatalf("status = %d, want the original 451", resp.StatusCode)
        }
        body, _ := io.ReadAll(resp.Body)
        if string(body) != "first 451" {
                t.Fatalf("the original 451 body must stay readable, got %q", body)
        }
}

func TestStack451PersonalRelayRecoversAndPrefers(t *testing.T) {
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                w.WriteHeader(200)
                io.WriteString(w, `{"token":"via-relay"}`)
        })
        defer relay.Close()

        // The direct side answers 451 for everything (both the literal and
        // the doubled path).
        direct := &fakeRT{answers: []fakeResponse{{status: 451, body: "region"}, {status: 451, body: "region"}}}
        personal := &relayTransport{relay: relay.URL, base: relay.Transport()}
        s := newStack(direct, Options{PersonalRelay: relay.URL.String(), PersonalEnabled: true}, personal, nil)

        resp, err := s.RoundTrip(guardianGet(t, "/api/v1/fpn/token"))
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()
        if resp.StatusCode != 200 {
                t.Fatalf("the personal relay must recover the 451, got %d", resp.StatusCode)
        }
        if got := atomic.LoadInt32(&relay.forwards); got != 1 {
                t.Fatalf("relay forwards = %d, want 1", got)
        }

        // The relay-first window: the second request must go to the relay
        // WITHOUT touching the (451-answering) direct route again.
        before := direct.count()
        resp2, err := s.RoundTrip(guardianGet(t, "/api/v1/fpn/status"))
        if err != nil {
                t.Fatal(err)
        }
        resp2.Body.Close()
        if direct.count() != before {
                t.Fatalf("the window must skip the direct route (calls %d → %d)", before, direct.count())
        }
        if got := atomic.LoadInt32(&relay.forwards); got != 2 {
                t.Fatalf("relay forwards = %d, want 2", got)
        }
}

func TestStackConnectFailureHandedToPersonal(t *testing.T) {
        // The direct route never opens (no GotConn, provably nothing sent):
        // the personal relay takes the request and the window opens.
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                io.WriteString(w, `{"list":[]}`)
        })
        defer relay.Close()

        direct := &fakeRT{}
        direct.answers = []fakeResponse{{err: errors.New("dial tcp: connection refused")}}
        personal := &relayTransport{relay: relay.URL, base: relay.Transport()}
        s := newStack(direct, Options{PersonalRelay: relay.URL.String(), PersonalEnabled: true}, personal, nil)

        resp, err := s.RoundTrip(guardianGet(t, "/api/v1/fpn/token"))
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()
        if resp.StatusCode != 200 {
                t.Fatalf("the personal relay must serve the unreachable direct route, got %d", resp.StatusCode)
        }
        if !s.relayFirst() {
                t.Fatal("the relay-first window must be armed after the handoff")
        }
}

func TestStackConnectedErrorIsNeverRetried(t *testing.T) {
        // A failure AFTER the connection was assigned may have delivered
        // bytes: the stack must return it as-is and never re-send.
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                t.Error("the relay must not see a possibly-delivered request")
        })
        defer relay.Close()

        direct := &fakeRT{connected: true}
        direct.answers = []fakeResponse{{err: errors.New("broken pipe: write: connection reset")}}
        personal := &relayTransport{relay: relay.URL, base: relay.Transport()}
        s := newStack(direct, Options{PersonalRelay: relay.URL.String(), PersonalEnabled: true}, personal, nil)

        resp, err := s.RoundTrip(guardianGet(t, "/api/v1/fpn/token"))
        if err == nil {
                resp.Body.Close()
                t.Fatal("the mid-write error must surface, not be swallowed")
        }
        if !strings.Contains(err.Error(), "broken pipe") {
                t.Fatalf("the original error must surface verbatim, got %v", err)
        }
        if got := atomic.LoadInt32(&relay.forwards); got != 0 {
                t.Fatalf("relay forwards = %d, want 0", got)
        }
}

func TestStackNonReplayableConnectFailureStaysError(t *testing.T) {
        // A body that cannot be re-obtained is never re-sent, even when the
        // connection provably never opened.
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                t.Error("a non-replayable request must not reach the relay")
        })
        defer relay.Close()

        direct := &fakeRT{}
        direct.answers = []fakeResponse{{err: errors.New("dial tcp: i/o timeout")}}
        personal := &relayTransport{relay: relay.URL, base: relay.Transport()}
        s := newStack(direct, Options{PersonalRelay: relay.URL.String(), PersonalEnabled: true}, personal, nil)

        req := guardianGet(t, "/api/v1/fpn/activate")
        req.Method = http.MethodPost
        req.Body = plainBody{r: strings.NewReader(`{"a":1}`)}
        req.GetBody = nil

        resp, err := s.RoundTrip(req)
        if err == nil {
                resp.Body.Close()
                t.Fatal("a non-replayable request must surface the direct error")
        }
        if got := atomic.LoadInt32(&relay.forwards); got != 0 {
                t.Fatalf("relay forwards = %d, want 0", got)
        }
}

func TestStackSharedPoolScopesToGuardian(t *testing.T) {
        // A 451 on a NON-Guardian control-plane host (Firefox Accounts)
        // must not wake the shared pool; only the personal relay may carry
        // it. With no personal relay configured the 451 passes through.
        direct := &fakeRT{}
        direct.answers = []fakeResponse{{status: 451, body: "region"}}
        s := newStack(direct, Options{SharedEnabled: true}, nil, newSharedPool(Options{SharedEnabled: true}))

        req, err := http.NewRequest(http.MethodGet, "https://api.accounts.firefox.com/v1/token", nil)
        if err != nil {
                t.Fatal(err)
        }
        resp, err := s.RoundTrip(req)
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()
        if resp.StatusCode != 451 {
                t.Fatalf("a non-Guardian 451 must pass through, got %d", resp.StatusCode)
        }
        // The doubled path IS tried (it is free and host-agnostic in the
        // reference; the origin of accounts.firefox.com simply answers).
        if direct.count() != 2 {
                t.Fatalf("direct calls = %d, want 2 (literal + doubled)", direct.count())
        }
}

// ---------------------------------------------------------------------------
// the relay wire protocol (relayTransport)
// ---------------------------------------------------------------------------

func TestRelayTransportForwardsAndReturns(t *testing.T) {
        var seen struct {
                url    string
                method string
                body   string
                secret string
        }
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                q := r.URL.Query()
                seen.url = q.Get("url")
                seen.secret = q.Get("secret")
                seen.method = r.Method
                b, _ := io.ReadAll(r.Body)
                seen.body = string(b)
                w.Header().Set("Content-Type", "application/json")
                io.WriteString(w, `{"answer":1}`)
        })
        defer relay.Close()

        u, _ := url.Parse(relay.URL.String() + "?secret=s3cret")
        req, err := http.NewRequest(http.MethodPost, "https://vpn.mozilla.org/api/v1/fpn/activate", strings.NewReader(`{"x":1}`))
        if err != nil {
                t.Fatal(err)
        }
        rt := &relayTransport{relay: u, base: relay.Transport()}
        resp, err := rt.RoundTrip(req)
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()

        if seen.url != "https://vpn.mozilla.org/api/v1/fpn/activate" {
                t.Fatalf("the target must ride the url parameter, got %q", seen.url)
        }
        if seen.method != http.MethodPost || seen.body != `{"x":1}` {
                t.Fatalf("method/body must forward as they are, got %s/%q", seen.method, seen.body)
        }
        if seen.secret != "s3cret" {
                t.Fatalf("the relay's own secret must survive next to the url parameter, got %q", seen.secret)
        }
        if resp.Request != req {
                t.Fatal("the response must stay attached to the ORIGINAL request (cookies, redirects)")
        }
        body, _ := io.ReadAll(resp.Body)
        if string(body) != `{"answer":1}` {
                t.Fatalf("the relay's answer body must pass through, got %q", body)
        }
}

func TestRelayTransportRefusalIsAnError(t *testing.T) {
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("X-Relay-Error", "host not allowed: evil.example")
                w.WriteHeader(403)
        })
        defer relay.Close()

        req, _ := http.NewRequest(http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/token", nil)
        rt := &relayTransport{relay: relay.URL, base: relay.Transport()}
        _, err := rt.RoundTrip(req)
        if err == nil {
                t.Fatal("a relay refusal (X-Relay-Error) must be an error, never a fake success")
        }
        if !strings.Contains(err.Error(), "refused") || !strings.Contains(err.Error(), "host not allowed") {
                t.Fatalf("the error must name the relay and the reason, got %v", err)
        }
}

// ---------------------------------------------------------------------------
// helpers around the request-shape utilities
// ---------------------------------------------------------------------------

func TestDoubledPathRequest(t *testing.T) {
        req := guardianGet(t, "/api/v1/fpn/token")
        d, ok := doubledPathRequest(req)
        if !ok || d == nil || d.URL.Path != "//api/v1/fpn/token" {
                t.Fatalf("doubled = %v %v", ok, d)
        }
        doubledTwice, ok := doubledPathRequest(d)
        if ok {
                t.Fatalf("an already-doubled path must not double again: %q", doubledTwice.URL.Path)
        }

        posted := guardianGet(t, "/api/v1/fpn/activate")
        posted.Method = http.MethodPost
        posted.Body = io.NopCloser(bytes.NewReader([]byte(`{}`)))
        posted.GetBody = nil
        if _, ok := doubledPathRequest(posted); ok {
                t.Fatal("a non-replayable body must refuse the doubled retry")
        }
}

func TestIsGuardianFPN(t *testing.T) {
        req := guardianGet(t, "/api/v1/fpn/token")
        if !isGuardianFPN(req, "vpn.mozilla.org") {
                t.Fatal("the production path must match")
        }
        if !isGuardianFPN(req, "VPN.Mozilla.ORG") {
                t.Fatal("the host match must be case-insensitive")
        }
        other, _ := http.NewRequest(http.MethodGet, "https://api.accounts.firefox.com/api/v1/fpn/token", nil)
        if isGuardianFPN(other, "vpn.mozilla.org") {
                t.Fatal("a non-Guardian host must not match")
        }
        sibling, _ := http.NewRequest(http.MethodGet, "https://vpn.mozilla.org/api/v1/other", nil)
        if isGuardianFPN(sibling, "vpn.mozilla.org") {
                t.Fatal("a non-fpn Guardian path must not match")
        }
}

func TestInstallRefusedAndRestored(t *testing.T) {
        // Invalid options install nothing but still return a usable
        // restore; a valid install restores cleanly. The global transport
        // seam makes a deeper assertion the vpnclient package's own business.
        restore := Install(Options{PersonalRelay: "http://not-https.example/"})
        if restore == nil {
                t.Fatal("a refused install must still return a restore")
        }
        restore()

        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {})
        defer relay.Close()
        restore = Install(Options{PersonalRelay: relay.URL.String(), PersonalEnabled: true})
        if restore == nil {
                t.Fatal("a valid install must return a restore")
        }
        restore()
}
