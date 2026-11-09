package fferr

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// TestNov8ChainReplay — THE Phase B Part 2 base case.
//
// Replays the EXACT failure recorded on the owner's device (logcat
// 2026-11-08 21:57:43.997, build aethone/da):
//
//	engine failed (exchangeFailed): oauth token request: Post
//	"https://api.accounts.firefox.com/v1/oauth/token": dial tcp: lookup
//	api.accounts.firefox.com on [::1]:53: read udp [::1]:37265->[::1]:53:
//	read: connection refused
//
// Reproduction is REAL end-to-end at the network layer: a PreferGo
// resolver whose Dial talks to [::1]:53 (nothing listens there — the
// kernel really refuses), wrapped by the *net.OpError{dial tcp} step the
// stdlib dialer performs, then by *url.Error{Post} at the client layer.
// Only the host lookup itself is forced through the localhost resolver —
// exactly the state the binary saw on Android (no /etc/resolv.conf →
// Go's defaultDNS at 127.0.0.1:53 / [::1]:53).
// ---------------------------------------------------------------------------
func TestNov8ChainReplay(t *testing.T) {
	// Precondition: nothing listens on loopback :53, like Android.
	if c, err := net.DialTimeout("tcp", "[::1]:53", 200*time.Millisecond); err == nil {
		c.Close()
		t.Skip("something listens on [::1]:53 in this environment; cannot replay refusal")
	}

	resolver := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			// Always the device's dead resolver: [::1]:53.
			return net.Dial(network, "[::1]:53")
		},
	}

	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				host, _, err := net.SplitHostPort(addr)
				if err != nil {
					return nil, err
				}
				addrs, lerr := resolver.LookupHost(ctx, host)
				if lerr != nil {
					// The dialer's genuine wrapping step for a failed
					// lookup: *net.OpError{Op:"dial", Net:"tcp"}.
					return nil, &net.OpError{
						Op:  "dial",
						Net: "tcp",
						Err: lerr,
					}
				}
				return (&net.Dialer{}).DialContext(ctx, network,
					net.JoinHostPort(addrs[0], "443"))
			},
		},
	}

	_, err := client.Post(
		"https://api.accounts.firefox.com/v1/oauth/token",
		"application/json",
		strings.NewReader(`{}`),
	)
	if err == nil {
		t.Fatal("expected the replayed exchange to fail")
	}

	got := err.Error()
	// Structural replay of the 2026-11-08 record. The resolver-config
	// label (`on <server>:53`) is environment data: on the device it was
	// `[::1]:53` (Android without resolv.conf → Go defaultDNS); in this
	// sandbox it is the resolv.conf entry. What MUST match the record is
	// the pure-Go resolver shape, the real [::1]:53 socket target, and
	// the kernel's genuine ECONNREFUSED on it.
	shape := regexp.MustCompile(`^Post "https://api\.accounts\.firefox\.com/v1/oauth/token": dial tcp: lookup api\.accounts\.firefox\.com on [^:]+:53: read udp \[::1\]:\d+->\[::1\]:53: read: connection refused$`)
	if !shape.MatchString(got) {
		t.Fatalf("chain shape mismatch.\n got: %s", got)
	}
	t.Logf("replayed chain: %s", got)
	t.Log("provenance: upload/exchange-failed-raw.txt line 43649 (device label was `on [::1]:53`)")

	gotC := ClassifyTransport(err)
	if gotC.Code != CodeDNS {
		t.Fatalf("classification: got %s, want %s", gotC.Code, CodeDNS)
	}
	if gotC.Message != msg[CodeDNS] {
		t.Fatalf("UI message must be the static text, got %q", gotC.Message)
	}
	// Go's own DNSError semantics: a refused resolver socket is reported
	// with IsTemporary=true, so the classifier stays type-faithful and
	// marks it retryable (the login UI may offer "try again"; automatic
	// retries must still back off — that policy lives in Dart).
	if !gotC.Retryable {
		t.Fatal("refused-resolver DNS error carries IsTemporary; expected retryable=true")
	}
	if gotC.HTTPStatus != 0 {
		t.Fatalf("transport failure must carry no HTTP status, got %d", gotC.HTTPStatus)
	}
	if strings.Contains(gotC.Message, "api.accounts.firefox.com") || strings.Contains(gotC.Message, "[::1]") {
		t.Fatal("static UI message must not leak internals")
	}
	t.Logf("classified: code=%s retryable=%v message=%q", gotC.Code, gotC.Retryable, gotC.Message)
}

// ---------------------------------------------------------------------------
// TestTimeoutReal — real client timeout from a sleeping handler.
// ---------------------------------------------------------------------------
func TestTimeoutReal(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(2 * time.Second)
		w.WriteHeader(200)
	}))
	defer srv.Close()

	client := &http.Client{Timeout: 300 * time.Millisecond}
	_, err := client.Post(srv.URL+"/v1/oauth/token", "application/json", strings.NewReader(`{}`))
	if err == nil {
		t.Fatal("expected timeout error")
	}
	var netErr net.Error
	if !errors.As(err, &netErr) || !netErr.Timeout() {
		t.Fatalf("expected a net.Error with Timeout()==true, got: %v", err)
	}
	c := ClassifyTransport(err)
	if c.Code != CodeTimeout {
		t.Fatalf("got %s, want %s (%v)", c.Code, CodeTimeout, err)
	}
	if !c.Retryable {
		t.Fatal("timeout must be retryable")
	}
	t.Logf("timeout chain classified: %s | %q", c.Code, err.Error())
}

// ---------------------------------------------------------------------------
// TestTLSReal — real self-signed rejection from httptest.NewTLSServer.
// ---------------------------------------------------------------------------
func TestTLSReal(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))
	defer srv.Close()

	_, err := http.Post(srv.URL+"/v1/oauth/token", "application/json", strings.NewReader(`{}`))
	if err == nil {
		t.Fatal("expected TLS verification error")
	}
	if !strings.Contains(err.Error(), "x509") && !strings.Contains(err.Error(), "certificate") {
		t.Fatalf("expected a certificate error, got: %v", err)
	}
	c := ClassifyTransport(err)
	if c.Code != CodeTLS {
		t.Fatalf("got %s, want %s (%v)", c.Code, CodeTLS, err)
	}
	t.Logf("tls chain classified: %s | %q", c.Code, err.Error())
}

// ---------------------------------------------------------------------------
// TestNetworkRefusedReal — real TCP refusal via http client (no server).
// ---------------------------------------------------------------------------
func TestNetworkRefusedReal(t *testing.T) {
	// Port 1 on loopback: nothing there in this sandbox.
	_, err := http.Post("http://127.0.0.1:1/v1/oauth/token", "application/json", strings.NewReader(`{}`))
	if err == nil {
		t.Fatal("expected connection refused")
	}
	if !strings.Contains(err.Error(), "connection refused") {
		t.Fatalf("expected refusal, got: %v", err)
	}
	c := ClassifyTransport(err)
	if c.Code != CodeNetworkUnreach {
		t.Fatalf("got %s, want %s (%v)", c.Code, CodeNetworkUnreach, err)
	}
	t.Logf("refused dial classified: %s | %q", c.Code, err.Error())
}

// ---------------------------------------------------------------------------
// TestHTTPStatuses — real httptest statuses through ClassifyHTTP.
// ---------------------------------------------------------------------------
func TestHTTPStatuses(t *testing.T) {
	cases := []struct {
		status     int
		wantCode   Code
		wantRetry  bool
		wantStatus int
	}{
		{401, CodeSessionRejected, false, 401},
		{403, CodeSessionRejected, false, 403},
		{400, CodeServerRejection, false, 400},
		{503, CodeServerRejection, true, 503},
		{500, CodeServerRejection, true, 500},
	}
	for _, tc := range cases {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(tc.status)
		}))
		resp, err := http.Post(srv.URL+"/v1/oauth/token", "application/json", strings.NewReader(`{}`))
		if err != nil {
			t.Fatalf("status %d: unexpected transport error: %v", tc.status, err)
		}
		got := ClassifyHTTP(resp.StatusCode, nil)
		resp.Body.Close()
		srv.Close()
		if got.Code != tc.wantCode || got.Retryable != tc.wantRetry || got.HTTPStatus != tc.wantStatus {
			t.Fatalf("status %d: got %+v, want code=%s retry=%v status=%d",
				tc.status, got, tc.wantCode, tc.wantRetry, tc.wantStatus)
		}
		if got.Message == "" {
			t.Fatal("message must be static non-empty text")
		}
		t.Logf("http %d -> %s (retryable=%v, httpStatus=%d)", tc.status, got.Code, got.Retryable, got.HTTPStatus)
	}
}

// ---------------------------------------------------------------------------
// TestTokenGuard — Part 3 rules on real JSON payloads.
// ---------------------------------------------------------------------------
func TestTokenGuard(t *testing.T) {
	valid := `{"access_token":"AT-ok","refresh_token":"RT-ok","expires_in":300,"scope":"profile","token_type":"bearer"}`
	pair, err := ValidateTokenResponse([]byte(valid))
	if err != nil {
		t.Fatalf("valid payload rejected: %v", err)
	}
	if pair.AccessToken != "AT-ok" || pair.RefreshToken != "RT-ok" {
		t.Fatalf("pair mismatch: %+v", pair)
	}

	bad := []struct {
		name string
		body string
		want string
	}{
		{"missing refresh", `{"access_token":"AT-ok"}`, `field "refresh_token" is missing`},
		{"missing access", `{"refresh_token":"RT-ok"}`, `field "access_token" is missing`},
		{"access wrong type", `{"access_token":123,"refresh_token":"RT-ok"}`, `field "access_token" is not a JSON string`},
		{"refresh wrong type", `{"access_token":"AT","refresh_token":false}`, `field "refresh_token" is not a JSON string`},
		{"access null", `{"access_token":null,"refresh_token":"RT"}`, `field "access_token" is null`},
		{"access empty", `{"access_token":"","refresh_token":"RT"}`, `field "access_token" is empty`},
		{"refresh blank", `{"access_token":"AT","refresh_token":"   \t "}`, `field "refresh_token" is blank`},
		{"not json", `not-json{`, "body is not valid JSON"},
	}
	for _, tc := range bad {
		_, err := ValidateTokenResponse([]byte(tc.body))
		if err == nil {
			t.Fatalf("%s: expected rejection", tc.name)
		}
		var ge *GuardError
		if !errors.As(err, &ge) {
			t.Fatalf("%s: expected *GuardError, got %T", tc.name, err)
		}
		if !strings.Contains(err.Error(), tc.want) {
			t.Fatalf("%s: reason %q does not contain %q", tc.name, err.Error(), tc.want)
		}
		if ge.Classified().Code != CodeInvalidTokenResp {
			t.Fatalf("%s: classified code %s", tc.name, ge.Classified().Code)
		}
		t.Logf("%s -> %s (%s)", tc.name, CodeInvalidTokenResp, err.Error())
	}
}

// ---------------------------------------------------------------------------
// TestNoLeak — the secrecy rule: no token value may appear in any
// user-facing or classified payload. Sentinel values prove it.
// ---------------------------------------------------------------------------
func TestNoLeak(t *testing.T) {
	const (
		sentinelAccess  = "SENTINEL_ACCESS_9f3aQW"
		sentinelRefresh = "SENTINEL_REFRESH_7b2xZK"
		sentinelSession = "SENTINEL_SESSION_5c9yPL"
	)

	// A failing guard must not echo token values.
	_, err := ValidateTokenResponse([]byte(fmt.Sprintf(
		`{"access_token":%q,"refresh_token":""}`, sentinelAccess)))
	var ge *GuardError
	if !errors.As(err, &ge) {
		t.Fatal("expected GuardError")
	}
	cl := ge.Classified()
	for _, s := range []string{sentinelAccess, sentinelRefresh, sentinelSession} {
		if strings.Contains(cl.Message, s) || strings.Contains(err.Error(), s) {
			t.Fatalf("LEAK in guard failure: %q / %q", cl.Message, err.Error())
		}
	}

	// Redact strips secrets from the engine-stderr copy.
	raw := fmt.Sprintf("Post https://api.accounts.firefox.com/v1/oauth/token bearer=%s session=%s",
		sentinelAccess, sentinelSession)
	c := Classified{Code: CodeTokenExchange, Message: "x", Internal: raw}
	rc := c.Redact(sentinelAccess, sentinelRefresh, sentinelSession)
	if strings.Contains(rc.Internal, sentinelAccess) || strings.Contains(rc.Internal, sentinelSession) {
		t.Fatalf("Redact failed: %s", rc.Internal)
	}
	if !strings.Contains(rc.Internal, "[REDACTED]") {
		t.Fatal("Redact must leave [REDACTED] markers")
	}
	if c.Internal == rc.Internal {
		t.Fatal("Redact must not mutate the original")
	}

	// The replayed transport chain contains no tokens by construction.
	t.Log("no-leak assertions passed for guard, redact, and static messages")
}

// ---------------------------------------------------------------------------
// TestUnknownAndFallback — unknown errors and generic url.Error wrapping.
// ---------------------------------------------------------------------------
func TestUnknownAndFallback(t *testing.T) {
	c := ClassifyTransport(errors.New("mystery"))
	if c.Code != CodeUnknown {
		t.Fatalf("got %s, want unknown", c.Code)
	}
	// A plain *url.Error without any recognized inner type.
	uerr := &net.OpError{Op: "dial", Net: "tcp", Err: errors.New("odd")}
	c2 := ClassifyTransport(uerr)
	if c2.Code != CodeNetworkUnreach {
		t.Fatalf("OpError fallback: got %s, want networkUnavailable", c2.Code)
	}
	// InsecureSkipVerify client against the TLS server MUST succeed —
	// proves the TLS test failure really came from verification.
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer srv.Close()
	cli := &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}}
	resp, err := cli.Post(srv.URL+"/v1/oauth/token", "application/json", strings.NewReader(`{}`))
	if err != nil || resp.StatusCode != 200 {
		t.Fatalf("insecure client should pass: %v", err)
	}
	resp.Body.Close()
}
