// cptransport tests — guardian-bootstrap Stage 5's routing proof set
// (mission §5-6): the allowlist precision (host + method + path —
// never the host alone), the FxA / Remote-Settings DIRECT guarantee,
// the redirect re-check, the doubled-leading-slash tolerance, and the
// end-to-end path through a REAL local HTTP CONNECT proxy with
// certificate verification left ON (the wrong-CA double proves the
// verification is actually enforcing, not just configured).
package cptransport

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// ---- fake legs ------------------------------------------------------------

// recordingRoundTripper answers with a marker header naming the leg.
type recordingRoundTripper struct {
	name  string
	seen  []*http.Request
	mutex sync.Mutex
}

func (r *recordingRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	r.mutex.Lock()
	r.seen = append(r.seen, req)
	r.mutex.Unlock()
	return &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 " + r.name,
		Header:     http.Header{"X-Leg": []string{r.name}},
		Body:       io.NopCloser(strings.NewReader(r.name)),
		Request:    req,
	}, nil
}

func (r *recordingRoundTripper) count() int {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	return len(r.seen)
}

func (r *recordingRoundTripper) requests() []*http.Request {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	out := make([]*http.Request, len(r.seen))
	copy(out, r.seen)
	return out
}

func mustRequest(t *testing.T, method, raw string) *http.Request {
	t.Helper()
	req, err := http.NewRequest(method, raw, nil)
	if err != nil {
		t.Fatalf("building %s %s: %v", method, raw, err)
	}
	return req
}

func legOf(t *testing.T, rt *RoutingRoundTripper, req *http.Request) string {
	t.Helper()
	resp, err := rt.RoundTrip(req)
	if err != nil {
		t.Fatalf("round trip %s %s: %v", req.Method, req.URL, err)
	}
	defer resp.Body.Close()
	return resp.Header.Get("X-Leg")
}

// ---- allowlist precision (mission §5-3) ------------------------------------

func TestAllowlistRoutesOnlyTheExactGuardianEntry(t *testing.T) {
	direct := &recordingRoundTripper{name: "direct"}
	proxied := &recordingRoundTripper{name: "proxied"}
	allow, err := NewGuardianAllowlist("https://vpn.mozilla.org",
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist: %v", err)
	}
	rt := NewRoutingRoundTripper(direct, proxied, allow)

	cases := []struct {
		name   string
		method string
		url    string
		want   string
	}{
		{"the real entry", http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/token", "proxied"},
		{"doubled-leading-slash tolerance", http.MethodGet, "https://vpn.mozilla.org//api/v1/fpn/token", "proxied"},
		{"host case-insensitive", http.MethodGet, "https://VPN.Mozilla.Org/api/v1/fpn/token", "proxied"},
		{"explicit default port", http.MethodGet, "https://vpn.mozilla.org:443/api/v1/fpn/token", "proxied"},
		{"wrong method (POST)", http.MethodPost, "https://vpn.mozilla.org/api/v1/fpn/token", "direct"},
		{"wrong method (HEAD)", http.MethodHead, "https://vpn.mozilla.org/api/v1/fpn/token", "direct"},
		{"wrong path (status is NOT in the execution path)", http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/status", "direct"},
		{"wrong path (activate is NOT in the execution path)", http.MethodPost, "https://vpn.mozilla.org/api/v1/activate", "direct"},
		{"wrong path (prefix)", http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/token/extra", "direct"},
		{"FxA host always direct", http.MethodGet, "https://api.accounts.firefox.com/v1/account/keys", "direct"},
		{"Remote Settings host always direct", http.MethodGet, "https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/whats-new", "direct"},
		{"different port on the guardian host", http.MethodGet, "https://vpn.mozilla.org:8443/api/v1/fpn/token", "direct"},
		{"host substring does not match", http.MethodGet, "https://evil-vpn.mozilla.org.attacker.test/api/v1/fpn/token", "direct"},
		{"plain http on the guardian host (scheme/port mismatch)", http.MethodGet, "http://vpn.mozilla.org/api/v1/fpn/token", "direct"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := mustRequest(t, tc.method, tc.url)
			if got := legOf(t, rt, req); got != tc.want {
				t.Fatalf("%s %s rode the %q leg (want %q)", tc.method, tc.url, got, tc.want)
			}
		})
	}
}

func TestBootstrapAllowlistRoutesOnlyPinnedRemoteSettingsAndGuardian(t *testing.T) {
	direct := &recordingRoundTripper{name: "direct"}
	proxied := &recordingRoundTripper{name: "proxied"}
	allow, err := NewBootstrapAllowlist(
		"https://vpn.mozilla.org",
		"https://firefox.settings.services.mozilla.com",
	)
	if err != nil {
		t.Fatalf("bootstrap allowlist: %v", err)
	}
	rt := NewRoutingRoundTripper(direct, proxied, allow)
	cases := []struct {
		name, method, target, want string
	}{
		{"Guardian token", http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/token", "proxied"},
		{"Remote Settings server list", http.MethodGet, "https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/vpn-serverlist/records", "proxied"},
		{"other Remote Settings collection", http.MethodGet, "https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/whats-new/records", "direct"},
		{"Remote Settings wrong method", http.MethodPost, "https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/vpn-serverlist/records", "direct"},
		{"FxA remains direct", http.MethodGet, "https://api.accounts.firefox.com/v1/account/keys", "direct"},
		{"non-allowlisted Guardian path", http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/status", "direct"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := legOf(t, rt, mustRequest(t, tc.method, tc.target)); got != tc.want {
				t.Fatalf("%s %s rode %q (want %q)", tc.method, tc.target, got, tc.want)
			}
		})
	}
}

func TestBootstrapUnavailableMeansEverythingDirect(t *testing.T) {
	direct := &recordingRoundTripper{name: "direct"}
	allow, err := NewGuardianAllowlist("https://vpn.mozilla.org",
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist: %v", err)
	}
	rt := NewRoutingRoundTripper(direct, nil, allow) // proxied == nil
	req := mustRequest(t, http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/token")
	if got := legOf(t, rt, req); got != "direct" {
		t.Fatalf("with no proxied leg the allowlisted request rode %q (want direct)", got)
	}
}

func TestRedirectHopsAreRecheckedAgainstTheAllowlist(t *testing.T) {
	// A redirect away from the allowlisted entry must leave the proxy:
	// http.Client re-enters RoundTrip per hop, so the second hop rides
	// the direct leg (mission §5-5 — the redirect rule).
	direct := &recordingRoundTripper{name: "direct"}
	proxied := &recordingRoundTripper{name: "proxied"}
	allow, err := NewGuardianAllowlist("https://vpn.mozilla.org",
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist: %v", err)
	}
	rt := NewRoutingRoundTripper(direct, proxied, allow)

	client := &http.Client{Transport: redirectingTransport{inner: rt}}
	resp, err := client.Get("https://vpn.mozilla.org/api/v1/fpn/token")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	defer resp.Body.Close()

	proxiedSeen := proxied.count()
	directSeen := direct.count()
	if proxiedSeen != 1 {
		t.Fatalf("proxied leg saw %d requests (want exactly the 1 allowlisted hop)", proxiedSeen)
	}
	if directSeen != 1 {
		t.Fatalf("direct leg saw %d requests (want the 1 redirected hop)", directSeen)
	}
}

// redirectingTransport wraps the routing transport and turns the FIRST
// allowlisted response into a 302 to an FxA host, which the client
// then follows through the routing transport again (as real redirects
// behave — the client drives the hops).
type redirectingTransport struct {
	inner http.RoundTripper
}

func (r redirectingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	resp, err := r.inner.RoundTrip(req)
	if err != nil {
		return nil, err
	}
	if resp.Header.Get("X-Leg") == "proxied" && resp.StatusCode == http.StatusOK {
		resp.Body.Close()
		redirected := req.Clone(req.Context())
		redirected.URL = &*req.URL
		redirected.URL.Scheme = "https"
		redirected.URL.Host = "api.accounts.firefox.com"
		redirected.URL.Path = "/v1/account/profile"
		return &http.Response{
			StatusCode: http.StatusFound,
			Status:     "302 Found",
			Header:     http.Header{"Location": []string{redirected.URL.String()}},
			Body:       io.NopCloser(strings.NewReader("")),
			Request:    req,
		}, nil
	}
	return resp, nil
}

func TestNewGuardianAllowlistRejectsBadInput(t *testing.T) {
	if _, err := NewGuardianAllowlist("not a url at all"); err == nil {
		t.Fatal("a base without a host must be rejected")
	}
	if _, err := NewGuardianAllowlist("https://vpn.mozilla.org"); err == nil {
		t.Fatal("an empty entry set must be rejected")
	}
}

func TestAllowlistRedactedRendering(t *testing.T) {
	allow, err := NewGuardianAllowlist("https://vpn.mozilla.org",
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist: %v", err)
	}
	rendered := allow.Redacted()
	if !strings.Contains(rendered, "vpn.mozilla.org") ||
		!strings.Contains(rendered, "GET /api/v1/fpn/token") {
		t.Fatalf("rendering lost the facts: %q", rendered)
	}
}

// ---- proxy leg construction (the pinned configureAPIProxy pattern) ----------

func TestNewProxyRoundTripperSchemesAndValidation(t *testing.T) {
	for _, raw := range []string{
		"http://127.0.0.1:8080",
		"https://127.0.0.1:8080",
		"socks5://127.0.0.1:1080",
		"socks5h://localhost:9050",
		"socks5://127.0.0.1:1080", // socks5h semantics: hostname dials through the proxy
	} {
		if _, err := NewProxyRoundTripper(raw); err != nil {
			t.Fatalf("NewProxyRoundTripper(%q): %v", raw, err)
		}
	}
	for _, raw := range []string{
		"",
		"   ",
		"ftp://127.0.0.1:21",
		"http://", // missing host
		"://",
	} {
		if _, err := NewProxyRoundTripper(raw); err == nil {
			t.Fatalf("NewProxyRoundTripper(%q) must fail", raw)
		}
	}
}

func TestNewProxyRoundTripperKeepsTLSVerificationOn(t *testing.T) {
	// Mission §5-5: TLS verification must stay ON — no InsecureSkipVerify
	// anywhere, and the HTTP/1.1 pin of the pinned demo is preserved.
	for _, raw := range []string{"http://127.0.0.1:8080", "socks5://127.0.0.1:1080"} {
		rt, err := NewProxyRoundTripper(raw)
		if err != nil {
			t.Fatalf("NewProxyRoundTripper(%q): %v", raw, err)
		}
		tr, ok := rt.(*http.Transport)
		if !ok {
			t.Fatalf("%q produced %T (want *http.Transport)", raw, rt)
		}
		if tr.TLSClientConfig != nil && tr.TLSClientConfig.InsecureSkipVerify {
			t.Fatalf("%q disabled certificate verification — forbidden", raw)
		}
		if tr.TLSClientConfig != nil && tr.TLSClientConfig.MinVersion != 0 &&
			tr.TLSClientConfig.MinVersion < 0x0303 { // TLS 1.2
			t.Fatalf("%q allowed a TLS version below 1.2", raw)
		}
		if tr.ForceAttemptHTTP2 {
			t.Fatalf("%q enabled HTTP/2 — the pinned proxied path pins HTTP/1.1", raw)
		}
		if tr.TLSNextProto == nil || len(tr.TLSNextProto) != 0 {
			t.Fatalf("%q did not pin HTTP/1.1 (TLSNextProto must be a non-nil empty map)", raw)
		}
	}
}

// ---- the end-to-end path through a REAL local proxy -------------------------

// connectProxy is a minimal REAL HTTP proxy: an http.Server that
// answers CONNECT (for https targets — hijack + blind pipe) and
// absolute-form requests (for http targets — forwarded per request, so
// a pooled proxy connection can never be pinned to a stale target).
// Every target is recorded for the routing assertions.
type connectProxy struct {
	listener net.Listener
	server   *http.Server
	mu       sync.Mutex
	targets  []string
}

func startConnectProxy(t *testing.T) *connectProxy {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	cp := &connectProxy{listener: listener}
	cp.server = &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodConnect {
				cp.record(r.Host)
				hijacker, ok := w.(http.Hijacker)
				if !ok {
					http.Error(w, "no hijack", http.StatusInternalServerError)
					return
				}
				upstream, err := net.DialTimeout("tcp", r.Host, 10*time.Second)
				if err != nil {
					http.Error(w, "bad gateway", http.StatusBadGateway)
					return
				}
				clientConn, _, err := hijacker.Hijack()
				if err != nil {
					upstream.Close()
					return
				}
				fmt.Fprintf(clientConn, "HTTP/1.1 200 Connection Established\r\n\r\n")
				go func() {
					defer upstream.Close()
					defer clientConn.Close()
					pipe(clientConn, upstream)
				}()
				return
			}
			// Absolute-form request: the target rides r.URL/r.Host.
			target := r.Host
			if target == "" {
				target = r.URL.Host
			}
			cp.record(target)
			outReq := r.Clone(r.Context())
			outReq.RequestURI = "" // a client-side request must not carry it
			resp, err := proxyOutboundClient.Do(outReq)
			if err != nil {
				http.Error(w, "bad gateway: "+err.Error(), http.StatusBadGateway)
				return
			}
			defer resp.Body.Close()
			for k, vs := range resp.Header {
				for _, v := range vs {
					w.Header().Add(k, v)
				}
			}
			w.WriteHeader(resp.StatusCode)
			io.Copy(w, resp.Body)
		}),
	}
	go cp.server.Serve(listener)
	t.Cleanup(func() { cp.server.Close() })
	return cp
}

// proxyOutboundClient is the fake proxy's own egress client (never
// proxied — it dials the recorded target directly). It must NOT follow
// redirects itself: redirect handling belongs to the END client, so
// the 302+Location passes through untouched and the re-routing proof
// (the redirected hop re-entering the RoutingRoundTripper) is real.
var proxyOutboundClient = &http.Client{
	Timeout:   10 * time.Second,
	Transport: &http.Transport{},
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		return http.ErrUseLastResponse
	},
}

func (cp *connectProxy) record(target string) {
	cp.mu.Lock()
	cp.targets = append(cp.targets, target)
	cp.mu.Unlock()
}

// makeTLSConfig builds the server-side TLS config from a parsed leaf.
func makeTLSConfig(leafCert *x509.Certificate, leafKey *rsa.PrivateKey) *tls.Config {
	return &tls.Config{
		Certificates: []tls.Certificate{{
			Certificate: [][]byte{leafCert.Raw},
			PrivateKey:  leafKey,
		}},
		MinVersion: tls.VersionTLS12,
	}
}

// pipe copies both directions until either side closes.
func pipe(a, b net.Conn) {
	done := make(chan struct{}, 2)
	go func() { io.Copy(b, a); done <- struct{}{} }()
	go func() { io.Copy(a, b); done <- struct{}{} }()
	<-done
}

func (cp *connectProxy) targetCount() int {
	cp.mu.Lock()
	defer cp.mu.Unlock()
	return len(cp.targets)
}

func (cp *connectProxy) sawTarget(target string) bool {
	cp.mu.Lock()
	defer cp.mu.Unlock()
	for _, t := range cp.targets {
		if t == target {
			return true
		}
	}
	return false
}

func TestEndToEndGuardianThroughProxyEverythingElseDirect(t *testing.T) {
	// The mission's §5-6 core proof, at the transport layer, with a REAL
	// local proxy: the Guardian token request traverses the proxy; a
	// non-allowlisted path on the SAME host and a request to a DIFFERENT
	// host (the FxA/Remote-Settings shape) stay DIRECT.
	fakeGuardian := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"ok":true}`)
	}))
	defer fakeGuardian.Close()

	proxy := startConnectProxy(t)
	proxied, err := NewProxyRoundTripper("http://" + proxy.listener.Addr().String())
	if err != nil {
		t.Fatalf("proxy round tripper: %v", err)
	}
	allow, err := NewGuardianAllowlist(fakeGuardian.URL,
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist: %v", err)
	}
	rt := NewRoutingRoundTripper(&http.Transport{}, proxied, allow)
	client := &http.Client{Transport: rt, Timeout: 10 * time.Second}

	// 1. The Guardian token walk — through the proxy.
	resp, err := client.Get(fakeGuardian.URL + "/api/v1/fpn/token")
	if err != nil {
		t.Fatalf("guardian token get: %v", err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !strings.Contains(string(body), `"ok"`) {
		t.Fatalf("guardian token get = %d %q", resp.StatusCode, body)
	}
	guardianAddr := strings.TrimPrefix(fakeGuardian.URL, "http://")
	if !proxy.sawTarget(guardianAddr) {
		t.Fatalf("the allowlisted Guardian request never traversed the proxy (targets: %v)", proxy.targets)
	}
	through := proxy.targetCount()

	// 2. A non-allowlisted path on the SAME host — direct.
	resp, err = client.Get(fakeGuardian.URL + "/some/other/path")
	if err != nil {
		t.Fatalf("other path get: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("other path get = %d", resp.StatusCode)
	}
	if proxy.targetCount() != through {
		t.Fatalf("a non-allowlisted path traversed the proxy (targets: %v)", proxy.targets)
	}

	// 3. A different host (the FxA / Remote-Settings shape) — direct.
	fakeOther := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"fxa":true}`)
	}))
	defer fakeOther.Close()
	resp, err = client.Get(fakeOther.URL + "/v1/account/profile")
	if err != nil {
		t.Fatalf("other host get: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("other host get = %d", resp.StatusCode)
	}
	if proxy.targetCount() != through {
		t.Fatalf("a non-Guardian host traversed the proxy (targets: %v)", proxy.targets)
	}

	// 4. Redirect away from the allowlisted entry: only the FIRST hop
	// rides the proxy (each hop is re-checked — mission §5-5).
	redirectGuardian := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, fakeOther.URL+"/redirected", http.StatusFound)
	}))
	defer redirectGuardian.Close()
	allow2, err := NewGuardianAllowlist(redirectGuardian.URL,
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist2: %v", err)
	}
	rt2 := NewRoutingRoundTripper(&http.Transport{}, proxied, allow2)
	client2 := &http.Client{Transport: rt2, Timeout: 10 * time.Second}
	resp, err = client2.Get(redirectGuardian.URL + "/api/v1/fpn/token")
	if err != nil {
		t.Fatalf("redirected guardian get: %v", err)
	}
	resp.Body.Close()
	finalURL := resp.Request.URL.String()
	if !strings.Contains(finalURL, "/redirected") {
		t.Fatalf("the redirect was not followed (final %s)", finalURL)
	}
	// Exactly ONE new proxy traversal: the allowlisted first hop.
	if proxy.targetCount() != through+1 {
		t.Fatalf("redirect hops misrouted (targets: %v)", proxy.targets)
	}
}

// ---- TLS verification through the proxy (mission §5-5) -----------------------

// TestVerifiedTLSThroughTheProxy proves certificate verification stays
// ON on the proxied leg: a leaf signed by a test CA (trusted via
// SSL_CERT_FILE — the process's root pool) SUCCEEDS, and a server with
// an UNTRUSTED certificate FAILS with a certificate error. If any code
// had disabled verification, both halves would succeed.
func TestVerifiedTLSThroughTheProxy(t *testing.T) {
	caKey, caLeaf, _ := makeTestCA(t)
	trusted := startTLSServer(t, caKey, caLeaf, func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"token":"shape-only"}`)
	})
	untrusted := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"untrusted":true}`)
	}))
	defer untrusted.Close()

	proxy := startConnectProxy(t)
	proxied, err := NewProxyRoundTripper("http://" + proxy.listener.Addr().String())
	if err != nil {
		t.Fatalf("proxy round tripper: %v", err)
	}
	allow, err := NewGuardianAllowlist(trusted.URL,
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist: %v", err)
	}
	rt := NewRoutingRoundTripper(&http.Transport{}, proxied, allow)
	client := &http.Client{Transport: rt, Timeout: 10 * time.Second}

	// 1. The CA-trusted Guardian answers through the proxy.
	resp, err := client.Get(trusted.URL + "/api/v1/fpn/token")
	if err != nil {
		t.Fatalf("verified TLS through the proxy failed: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("trusted guardian = %d", resp.StatusCode)
	}
	if !proxy.sawTarget(strings.TrimPrefix(trusted.URL, "https://")) {
		t.Fatal("the trusted request did not traverse the proxy")
	}

	// 2. The SAME allowlisted shape against an UNTRUSTED certificate
	// must FAIL — verification is enforcing, not decorative.
	untrustedAllow, err := NewGuardianAllowlist(untrusted.URL,
		AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"})
	if err != nil {
		t.Fatalf("allowlist (untrusted): %v", err)
	}
	rtUntrusted := NewRoutingRoundTripper(&http.Transport{}, proxied, untrustedAllow)
	clientUntrusted := &http.Client{Transport: rtUntrusted, Timeout: 10 * time.Second}
	resp, err = clientUntrusted.Get(untrusted.URL + "/api/v1/fpn/token")
	if err == nil {
		resp.Body.Close()
		t.Fatal("an untrusted certificate was accepted through the proxied leg — verification is OFF somewhere")
	}
	if !strings.Contains(err.Error(), "certificate") && !strings.Contains(err.Error(), "x509") {
		t.Fatalf("the untrusted failure is not a certificate error: %v", err)
	}
}

// makeTestCA generates a self-signed test CA, registers it in the
// process's root pool through SSL_CERT_FILE (Linux: read at the FIRST
// root-pool load — this test binary performs no earlier verified TLS),
// and returns the key/leaf for signing server certificates.
func makeTestCA(t *testing.T) (caKey *rsa.PrivateKey, caLeaf *x509.Certificate, caPEM []byte) {
	t.Helper()
	caKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("ca key: %v", err)
	}
	caTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "cptransport-test-ca"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatalf("ca cert: %v", err)
	}
	caLeaf, err = x509.ParseCertificate(caDER)
	if err != nil {
		t.Fatalf("parse ca: %v", err)
	}
	caPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})

	caPath := filepath.Join(t.TempDir(), "ca.pem")
	if err := os.WriteFile(caPath, caPEM, 0o600); err != nil {
		t.Fatalf("write ca: %v", err)
	}
	t.Setenv("SSL_CERT_FILE", caPath)
	return caKey, caLeaf, caPEM
}

// startTLSServer runs an https httptest server whose leaf certificate
// is signed by the test CA for 127.0.0.1 (so default hostname
// verification passes too).
func startTLSServer(t *testing.T, caKey *rsa.PrivateKey, caLeaf *x509.Certificate, handler http.HandlerFunc) *httptest.Server {
	t.Helper()
	leafKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("leaf key: %v", err)
	}
	leafTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: "127.0.0.1"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
		DNSNames:     []string{"localhost"},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caLeaf, &leafKey.PublicKey, caKey)
	if err != nil {
		t.Fatalf("leaf cert: %v", err)
	}
	leafCert, err := x509.ParseCertificate(leafDER)
	if err != nil {
		t.Fatalf("parse leaf: %v", err)
	}
	server := httptest.NewUnstartedServer(handler)
	server.TLS = makeTLSConfig(leafCert, leafKey)
	server.StartTLS()
	t.Cleanup(server.Close)
	return server
}
