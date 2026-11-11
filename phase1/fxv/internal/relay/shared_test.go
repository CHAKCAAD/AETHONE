package relay

// The shared Guardian relay pool tests: manifest loading (filtering,
// dedup, the authoritative disabled list, the mirror fallback), the
// health probe, the recovery walk (bad-relay skipping, the sticky
// active relay, the non-idempotent stop) and the response validator —
// all against LOCAL servers (the manifest server and the relays are
// httptest instances; nothing talks to the real arman-org manifest).

import (
        "crypto/tls"
        "errors"
        "io"
        "net/http"
        "net/http/httptest"
        "net/url"
        "strings"
        "sync/atomic"
        "testing"
        "time"
)

// ---------------------------------------------------------------------------
// the shared test relay (also used by relay_test.go)
// ---------------------------------------------------------------------------

// testRelay is a local HTTPS relay speaking the documented wire
// protocol: ?health=1 answers the shared-pool health JSON; ?url=TARGET
// forwards (the answer callback writes the forwarded response, the
// helper stamps the X-Arman-Relay marker first). failHealth flips the
// health answer to a transport-level failure.
type testRelay struct {
        server     *httptest.Server
        URL        *url.URL
        answer     func(w http.ResponseWriter, r *http.Request)
        forwards   int32
        healths    int32
        failHealth int32
}

func newTestRelay(t *testing.T, answer func(w http.ResponseWriter, r *http.Request)) *testRelay {
        t.Helper()
        tr := &testRelay{answer: answer}
        mux := http.NewServeMux()
        mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
                q := r.URL.Query()
                if q.Get("health") == "1" {
                        atomic.AddInt32(&tr.healths, 1)
                        if atomic.LoadInt32(&tr.failHealth) == 1 {
                                w.WriteHeader(http.StatusInternalServerError)
                                return
                        }
                        w.Header().Set("Content-Type", "application/json")
                        w.Header().Set("Cache-Control", "no-store")
                        io.WriteString(w, `{"relay":"arman-vpn","version":1,"ready":true}`)
                        return
                }
                if q.Get("url") == "" {
                        w.WriteHeader(http.StatusOK)
                        io.WriteString(w, "your relay is ready")
                        return
                }
                atomic.AddInt32(&tr.forwards, 1)
                w.Header().Set("X-Arman-Relay", "1")
                tr.answer(w, r)
        })
        tr.server = httptest.NewTLSServer(mux)
        t.Cleanup(tr.server.Close)
        u, err := url.Parse(tr.server.URL)
        if err != nil {
                t.Fatal(err)
        }
        tr.URL = u
        return tr
}

// Transport returns a transport trusting the test relay's certificate
// (the production leg verifies against the system roots; the local
// test CA needs this pool).
func (tr *testRelay) Transport() *http.Transport {
        return &http.Transport{TLSClientConfig: &tls.Config{RootCAs: tlsRootsOf(tr.server)}}
}

// Close shuts the relay server down (idempotent; the t.Cleanup that
// newTestRelay registers also closes, so a test's own defer is safe).
func (tr *testRelay) Close() { tr.server.Close() }

// ---------------------------------------------------------------------------
// manifest fixtures
// ---------------------------------------------------------------------------

// manifestServer serves the given manifest body (plain HTTP: bootstrap
// traffic, not a control-plane request).
func manifestServer(t *testing.T, body string) *httptest.Server {
        t.Helper()
        s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                io.WriteString(w, body)
        }))
        t.Cleanup(s.Close)
        return s
}

// testPool builds a pool around a local manifest with a deterministic
// order (no shuffle) and a transport factory for the relays.
func testPool(t *testing.T, manifestURL string, transportFor func(*url.URL) (http.RoundTripper, error)) *sharedPool {
        t.Helper()
        p := newSharedPool(Options{SharedEnabled: true, GuardianHost: "vpn.mozilla.org"})
        p.manifestURLs = []string{manifestURL}
        p.shuffle = func(int, func(int, int)) {} // keep the manifest order
        p.transport = transportFor
        return p
}

// poolRelayTransport adapts a testRelay into the pool's transport
// factory shape.
func poolRelayTransport(relay *testRelay) func(*url.URL) (http.RoundTripper, error) {
        base := relay.Transport()
        return func(*url.URL) (http.RoundTripper, error) { return base, nil }
}

func guardianFPNGet(t *testing.T, method string) *http.Request {
        t.Helper()
        req, err := http.NewRequest(method, "https://vpn.mozilla.org/api/v1/fpn/token", nil)
        if err != nil {
                t.Fatal(err)
        }
        return req
}

// ---------------------------------------------------------------------------
// manifest loading
// ---------------------------------------------------------------------------

func TestSharedManifestFiltersAndDedups(t *testing.T) {
        manifest := manifestServer(t, `{"relays":{"enabled":true,"urls":[
                "https://good.example/?secret=1",
                "http://plain.example/",
                "https://u:p@cred.example/",
                "https://good.example/?secret=1",
                "https://frag.example/#f",
                "https://param.example/?url=https://x",
                "https://param.example/?health=1"
        ]}}`)
        p := testPool(t, manifest.URL, poolRelayTransport(newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {})))
        p.load(t.Context())
        if len(p.urls) != 1 || p.urls[0] != "https://good.example/?secret=1" {
                t.Fatalf("candidates = %v, want exactly the one valid https URL", p.urls)
        }
}

func TestSharedManifestDisabledIsAuthoritative(t *testing.T) {
        on := manifestServer(t, `{"relays":{"enabled":true,"urls":["https://a.example/"]}}`)
        p := testPool(t, on.URL, poolRelayTransport(newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {})))
        p.load(t.Context())
        if len(p.urls) != 1 {
                t.Fatalf("the enabled list must load, got %v", p.urls)
        }

        off := manifestServer(t, `{"relays":{"enabled":false,"urls":["https://a.example/"]}}`)
        p.manifestURLs = []string{off.URL}
        p.refreshAt = time.Now().Add(-time.Minute) // force the next refresh
        p.load(t.Context())
        if len(p.urls) != 0 {
                t.Fatalf("a valid disabled manifest must CLEAR the pool, got %v", p.urls)
        }
}

func TestSharedManifestFallsToMirror(t *testing.T) {
        dead := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                panic("never reached — server closed below")
        }))
        deadURL := dead.URL
        dead.Close() // an unreachable primary

        mirror := manifestServer(t, `{"relays":{"enabled":true,"urls":["https://mirror.example/"]}}`)
        p := newSharedPool(Options{SharedEnabled: true, GuardianHost: "vpn.mozilla.org"})
        p.manifestURLs = []string{deadURL, mirror.URL}
        p.shuffle = func(int, func(int, int)) {}
        p.load(t.Context())
        if len(p.urls) != 1 || p.urls[0] != "https://mirror.example/" {
                t.Fatalf("the mirror must serve when the primary is unreachable, got %v", p.urls)
        }
        if d := time.Until(p.refreshAt); d < 9*time.Minute {
                t.Fatalf("a good manifest must hold for 10 minutes, refresh in %s", d)
        }
}

func TestSharedManifestBothFailKeepsOldList(t *testing.T) {
        good := manifestServer(t, `{"relays":{"enabled":true,"urls":["https://keep.example/"]}}`)
        p := testPool(t, good.URL, poolRelayTransport(newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {})))
        p.load(t.Context())
        if len(p.urls) != 1 {
                t.Fatalf("setup: the list must load, got %v", p.urls)
        }

        dead := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
        deadURL := dead.URL
        dead.Close()
        p.manifestURLs = []string{deadURL}
        p.refreshAt = time.Now().Add(-time.Minute)
        p.load(t.Context())
        if len(p.urls) != 1 || p.urls[0] != "https://keep.example/" {
                t.Fatalf("a failed refresh must keep the fetched list, got %v", p.urls)
        }
        if d := time.Until(p.refreshAt); d > 2*time.Minute {
                t.Fatalf("a failed refresh must retry after a minute, holds %s", d)
        }
}

// ---------------------------------------------------------------------------
// the health probe
// ---------------------------------------------------------------------------

func TestSharedHealthy(t *testing.T) {
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {})
        base := relay.Transport()
        p := newSharedPool(Options{SharedEnabled: true})

        if !p.healthy(t.Context(), relay.URL, base) {
                t.Fatal("the compliant health JSON must pass")
        }
        if got := atomic.LoadInt32(&relay.healths); got != 1 {
                t.Fatalf("healths = %d, want 1", got)
        }

        atomic.StoreInt32(&relay.failHealth, 1)
        if p.healthy(t.Context(), relay.URL, base) {
                t.Fatal("a non-200 health answer must fail")
        }
}

func TestSharedHealthyRejectsWrongPayload(t *testing.T) {
        bad := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                io.WriteString(w, `{"relay":"someone-else","version":1,"ready":true}`)
        }))
        t.Cleanup(bad.Close)
        u, _ := url.Parse(bad.URL)
        p := newSharedPool(Options{SharedEnabled: true})
        if p.healthy(t.Context(), u, tlsRootsTransport(bad)) {
                t.Fatal("a health answer naming another relay must fail")
        }
}

// ---------------------------------------------------------------------------
// the recovery walk
// ---------------------------------------------------------------------------

func TestSharedRecoverEndToEnd(t *testing.T) {
        relay := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                q := r.URL.Query()
                if q.Get("url") != "https://vpn.mozilla.org/api/v1/fpn/token" {
                        t.Errorf("the forwarded target = %q", q.Get("url"))
                }
                w.Header().Set("Content-Type", "application/json")
                io.WriteString(w, `{"token":"recovered"}`)
        })
        manifest := manifestServer(t, `{"relays":{"enabled":true,"urls":["`+relay.URL.String()+`"]}}`)
        p := testPool(t, manifest.URL, poolRelayTransport(relay))

        resp, err := p.Recover(guardianFPNGet(t, http.MethodGet))
        if err != nil {
                t.Fatal(err)
        }
        defer resp.Body.Close()
        if resp.StatusCode != 200 {
                t.Fatalf("the healthy relay must recover the request, got %d", resp.StatusCode)
        }
        if resp.Header.Get("X-Arman-Relay") != "1" {
                t.Fatal("the FORWARDED marker must ride the recovered response")
        }
        if got := atomic.LoadInt32(&relay.forwards); got != 1 {
                t.Fatalf("forwards = %d, want 1", got)
        }
        if p.active != relay.URL.String() {
                t.Fatalf("the winner must become the sticky active relay, got %q", p.active)
        }

        // The budget's cancel rides the body: closing it must not disturb a
        // second recovery through the same sticky relay.
        body, err := io.ReadAll(resp.Body)
        if err != nil || string(body) != `{"token":"recovered"}` {
                t.Fatalf("body = %q err=%v", body, err)
        }
}

func TestSharedRecoverSkipsBadAndPrefersActive(t *testing.T) {
        bad := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {})
        atomic.StoreInt32(&bad.failHealth, 1) // healthy() fails

        good := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                io.WriteString(w, `{"token":"ok"}`)
        })
        manifest := manifestServer(t, `{"relays":{"enabled":true,"urls":["`+bad.URL.String()+`","`+good.URL.String()+`"]}}`)
        p := testPool(t, manifest.URL, func(u *url.URL) (http.RoundTripper, error) {
                if u.Host == bad.URL.Host {
                        return bad.Transport(), nil
                }
                return good.Transport(), nil
        })

        resp, err := p.Recover(guardianFPNGet(t, http.MethodGet))
        if err != nil {
                t.Fatal(err)
        }
        resp.Body.Close()
        if got := atomic.LoadInt32(&bad.forwards); got != 0 {
                t.Fatalf("an unhealthy relay must never receive a forward, got %d", got)
        }

        // Second walk: the bad relay is still within its bad-for minute and
        // must be skipped without even a health probe.
        badHealths := atomic.LoadInt32(&bad.healths)
        resp2, err := p.Recover(guardianFPNGet(t, http.MethodGet))
        if err != nil {
                t.Fatal(err)
        }
        resp2.Body.Close()
        if got := atomic.LoadInt32(&good.forwards); got != 2 {
                t.Fatalf("the sticky active relay must serve again, forwards = %d", got)
        }
        if got := atomic.LoadInt32(&bad.healths); got != badHealths {
                t.Fatal("a relay inside its bad-for minute must not be re-probed")
        }
}

func TestSharedRecoverNonIdempotentStops(t *testing.T) {
        // A POST that left the relay without a usable answer may have been
        // delivered: the walk must STOP, never try the next relay.
        refusing := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("X-Relay-Error", "upstream request failed")
                w.WriteHeader(http.StatusBadGateway)
        })
        spare := newTestRelay(t, func(w http.ResponseWriter, r *http.Request) {
                t.Error("a second relay must not receive a possibly-delivered POST")
        })
        manifest := manifestServer(t, `{"relays":{"enabled":true,"urls":["`+refusing.URL.String()+`","`+spare.URL.String()+`"]}}`)
        p := testPool(t, manifest.URL, func(u *url.URL) (http.RoundTripper, error) {
                if u.Host == refusing.URL.Host {
                        return refusing.Transport(), nil
                }
                return spare.Transport(), nil
        })

        _, err := p.Recover(guardianFPNGet(t, http.MethodPost))
        if err == nil {
                t.Fatal("a failed POST recovery must surface an error")
        }
        if !strings.Contains(err.Error(), "no healthy shared relay") {
                t.Fatalf("the honest exhaustion error expected, got %v", err)
        }
        if got := atomic.LoadInt32(&spare.forwards); got != 0 {
                t.Fatalf("spare forwards = %d, want 0", got)
        }
}

func TestSharedRecoverScopesAndReplayability(t *testing.T) {
        p := newSharedPool(Options{SharedEnabled: true, GuardianHost: "vpn.mozilla.org"})

        other, _ := http.NewRequest(http.MethodGet, "https://api.accounts.firefox.com/v1/token", nil)
        if _, err := p.Recover(other); err == nil || !strings.Contains(err.Error(), "Guardian requests only") {
                t.Fatalf("a non-Guardian request must be refused, got %v", err)
        }

        posted := guardianFPNGet(t, http.MethodPost)
        posted.Body = io.NopCloser(strings.NewReader(`{}`))
        posted.GetBody = nil
        if _, err := p.Recover(posted); err == nil || !strings.Contains(err.Error(), "replayable") {
                t.Fatalf("a non-replayable body must be refused, got %v", err)
        }
}

// ---------------------------------------------------------------------------
// the response validator
// ---------------------------------------------------------------------------

func TestUsableSharedResponse(t *testing.T) {
        jsonBody := io.NopCloser(strings.NewReader(`{}`))
        mk := func(marker string, status int, ctype string) (*http.Request, *http.Response) {
                req, _ := http.NewRequest(http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/token", nil)
                h := make(http.Header)
                if marker != "" {
                        h.Set("X-Arman-Relay", marker)
                }
                h.Set("Content-Type", ctype)
                return req, &http.Response{StatusCode: status, Header: h, Body: jsonBody}
        }

        for _, c := range []struct {
                name                string
                marker              string
                status              int
                ctype               string
                want                bool
        }{{"forwarded 200 json", "1", 200, "application/json", true},
                {"forwarded 401 json", "1", 401, "application/json", true},
                {"forwarded 429 json", "1", 429, "application/json", true},
                {"forwarded 302 refused", "1", 302, "application/json", false},
                {"forwarded 200 html refused", "1", 200, "text/html", false},
                {"unmarked 200 refused", "", 200, "application/json", false},
        } {
                t.Run(c.name, func(t *testing.T) {
                        req, resp := mk(c.marker, c.status, c.ctype)
                        if got := usableSharedResponse(req, resp); got != c.want {
                                t.Fatalf("usable = %t, want %t", got, c.want)
                        }
                })
        }

        // nil response never crashes the validator.
        if usableSharedResponse(nil, nil) {
                t.Fatal("nil must not be usable")
        }
}

var _ = errors.New // keep errors imported for future assertions
