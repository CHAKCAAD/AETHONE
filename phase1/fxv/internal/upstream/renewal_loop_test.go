package upstream

// GUARDIAN-BOOTSTRAP STAGE 6 (renewal & lifecycle) — the renewal loop's
// REAL behavior, evidenced from the pinned engine contract
// (docs/performance/FIREFOX_GUARDIAN_PSIPHON_BOOTSTRAP_PROGRESS.md,
// mission §6):
//
//   * renewal fires BEFORE the pass expires (nextRenewalDelay targets
//     expiresAt − proxyPassRenewLead; a near-expiry pass renews at once);
//   * the renewal request traverses the INSTALLED control-plane
//     transport — the very seam Stage 5's RoutingRoundTripper occupies,
//     which is why an engine spawned with apiProxy renews THROUGH the
//     bootstrap route (a recording RoundTripper proves the traversal);
//   * a successful renewal ROTATES the pass on the LIVE session: the
//     fresh raw token is swapped in via Session.UpdateToken and the new
//     expiry (from the response's own exp claim — never a hardcoded
//     lifetime) is adopted, re-arming the loop;
//   * one failed renewal reports OnRenewalFail with the Stage-1 class
//     (the Guardian 451 region class included) and the pinned retry
//     delay (proxyPassRetryDelay, 30 s) — the loop keeps retrying;
//   * quota exhaustion and an over-stayed expiry are TERMINAL: the
//     loop parks the engine via Terminal() (TerminalQuota /
//     TerminalRenewalTimeout) instead of retrying forever.
//
// Test shape: white-box, in-package. The h2/h3 dialing (Start) is
// orthogonal to renewal, so the loop is driven against a fake Session
// installed through the controller's own setSession — everything else
// (timing, callbacks, classification, transport traversal, terminal
// outcomes) is the production code path. The Guardian double is an
// httptest server behind a recording control-plane transport installed
// with vpnclient.SetControlPlaneTransport (restored per test).
import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	vpnclient "firefox-vpn-client"
)

// renewFakeSession records the live-session token swap (rotation).
type renewFakeSession struct {
	mu     sync.Mutex
	tokens []string
	alive  bool
	closed bool
}

func (s *renewFakeSession) OpenTunnel(authority string) (net.Conn, error) {
	return nil, fmt.Errorf("not needed by the renewal loop tests")
}

func (s *renewFakeSession) UpdateToken(token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tokens = append(s.tokens, token)
	return nil
}

func (s *renewFakeSession) IsAlive() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.alive
}

func (s *renewFakeSession) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed = true
	return nil
}

// renewTransport is the recording control-plane transport: every
// request the pinned client makes — the initial pass AND every renewal —
// must traverse it (the Stage-5 RoutingRoundTripper's seat).
type renewTransport struct {
	mu    sync.Mutex
	inner http.RoundTripper
	hits  int
	paths []string
}

func (t *renewTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	t.mu.Lock()
	t.hits++
	t.paths = append(t.paths, req.Method+" "+req.URL.Path)
	t.mu.Unlock()
	return t.inner.RoundTrip(req)
}

// mintRenewalJWT builds a 3-part JWT whose claims carry the wanted exp
// (relative to now) and iat (now-1min) — the pin's parseJWTClaims only
// decodes claims (signature verification is Guardian's job), and the
// iat/exp window keeps the claim-time correction at zero.
func mintRenewalJWT(expiresIn time.Duration) string {
	payload, err := json.Marshal(map[string]any{
		"exp": time.Now().Add(expiresIn).Unix(),
		"iat": time.Now().Add(-time.Minute).Unix(),
	})
	if err != nil {
		panic(err) // a fixed map — test-only
	}
	return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
		base64.RawURLEncoding.EncodeToString(payload) +
		".shape-only-signature"
}

// renewGuardian is a scripted Guardian double: each /api/v1/fpn/token
// request consumes the next scripted answer.
type renewGuardian struct {
	mu      sync.Mutex
	answers []renewAnswer
}

type renewAnswer struct {
	status int
	body   string
}

func (g *renewGuardian) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	g.mu.Lock()
	if len(g.answers) == 0 {
		g.mu.Unlock()
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"script exhausted"}`))
		return
	}
	next := g.answers[0]
	g.answers = g.answers[1:]
	g.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(next.status)
	_, _ = w.Write([]byte(next.body))
}

// installRenewalHarness wires a scripted Guardian behind a RECORDING
// control-plane transport (the same global seat the Stage-5
// RoutingRoundTripper takes in production) and restores the pinned uTLS
// transport afterwards. Returns the double's base URL.
func installRenewalHarness(t *testing.T, answers ...renewAnswer) (string, *renewTransport) {
	t.Helper()
	guardian := &renewGuardian{answers: answers}
	srv := httptest.NewTLSServer(guardian)
	t.Cleanup(srv.Close)
	transport := &renewTransport{inner: &http.Transport{
		// Test-only double (the guardianprobe_test.go precedent): the
		// local self-signed certificate is trusted; production TLS
		// verification is untouched.
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}}
	vpnclient.SetControlPlaneTransport(transport)
	t.Cleanup(func() {
		vpnclient.SetControlPlaneTransport(vpnclient.NewControlPlaneTransport())
	})
	return srv.URL, transport
}

func tokenAnswer(expiresIn time.Duration) renewAnswer {
	body, _ := json.Marshal(map[string]any{"token": mintRenewalJWT(expiresIn)})
	return renewAnswer{status: http.StatusOK, body: string(body)}
}

// renewLoopController builds the controller with recording callbacks.
func renewLoopController(t *testing.T, guardianURL string) (*Controller, *renewFakeSession, *renewCallbacks) {
	t.Helper()
	cb := &renewCallbacks{}
	controller := NewController(ControllerConfig{
		Guardian:      guardianURL,
		AccessToken:   "renewal-test-access",
		RefreshToken:  "",
		Transport:     "h2",
		OnPassRenewed: cb.passRenewed,
		OnRenewalFail: cb.renewalFail,
		Logf:          t.Logf,
	})
	session := &renewFakeSession{alive: true}
	return controller, session, cb
}

type renewCallbacks struct {
	mu      sync.Mutex
	renewed []time.Time
	fails   []renewFailRecord
}

type renewFailRecord struct {
	redacted  string
	failCode  string
	retryInMs int64
}

func (c *renewCallbacks) passRenewed(pass *vpnclient.ProxyPassInfo) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.renewed = append(c.renewed, pass.ExpiresAt())
}

func (c *renewCallbacks) renewalFail(redacted, failCode string, retryInMs int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.fails = append(c.fails, renewFailRecord{redacted: redacted, failCode: failCode, retryInMs: retryInMs})
}

// stopRenewalLoop cancels the loop's context FIRST, then waits for the
// goroutine to leave (a plain `defer cancel(); defer <-done` deadlocks:
// LIFO runs the wait before the cancel).
func stopRenewalLoop(t *testing.T, cancel context.CancelFunc, done <-chan struct{}) {
	t.Helper()
	cancel()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatalf("the renewal loop did not stop on cancel")
	}
}

func TestRenewalLoopRotatesThePassThroughTheInstalledTransport(t *testing.T) {
	// Script: the initial pass lives ~2 s (the loop renews immediately —
	// nextRenewalDelay targets expiry − 2 min lead), the renewal mints a
	// 1 h pass (the loop then sleeps; the test cancels).
	guardianURL, transport := installRenewalHarness(t,
		tokenAnswer(2*time.Second),
		tokenAnswer(time.Hour),
	)
	controller, session, cb := renewLoopController(t, guardianURL)

	pass, err := controller.AcquireInitialPass(context.Background())
	if err != nil {
		t.Fatalf("initial pass: %v", err)
	}
	controller.setSession(session, pass)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { controller.runRenewalLoop(ctx); close(done) }()
	defer stopRenewalLoop(t, cancel, done)

	// The renewal lands well inside this budget (the loop fires at once).
	deadline := time.Now().Add(10 * time.Second)
	for {
		cb.mu.Lock()
		renewed := len(cb.renewed)
		cb.mu.Unlock()
		if renewed >= 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the renewal never fired: renewed=%d", renewed)
		}
		time.Sleep(20 * time.Millisecond)
	}

	cb.mu.Lock()
	newExpiry := cb.renewed[0]
	cb.mu.Unlock()
	if remaining := time.Until(newExpiry); remaining < 30*time.Minute {
		t.Fatalf("the renewed pass did not adopt the fresh exp claim: %v left", remaining)
	}

	// The rotation reached the LIVE session (the bearer swap).
	session.mu.Lock()
	swaps := len(session.tokens)
	session.mu.Unlock()
	if swaps != 1 {
		t.Fatalf("UpdateToken calls on the live session = %d, want 1", swaps)
	}

	// BOTH requests (initial + renewal) traversed the installed
	// control-plane transport — the Stage-5 RoutingRoundTripper's seat.
	transport.mu.Lock()
	hits := transport.hits
	paths := append([]string(nil), transport.paths...)
	transport.mu.Unlock()
	if hits < 2 {
		t.Fatalf("control-plane transport hits = %d, want >= 2 (initial + renewal)", hits)
	}
	for _, p := range paths {
		if !strings.Contains(p, "GET /api/v1/fpn/token") {
			t.Fatalf("unexpected control-plane request: %q", p)
		}
	}

	// No terminal outcome, no failure callbacks — a healthy renewal.
	select {
	case kind := <-controller.Terminal():
		t.Fatalf("unexpected terminal outcome: %v", kind)
	default:
	}
	cb.mu.Lock()
	fails := len(cb.fails)
	cb.mu.Unlock()
	if fails != 0 {
		t.Fatalf("OnRenewalFail fired on a healthy renewal: %+v", cb.fails)
	}
}

func TestRenewalLoopFailureCarriesClassAndRetryDelay(t *testing.T) {
	// Script: a short-lived initial pass, then a REAL 451 region block on
	// the renewal — OnRenewalFail must carry the Stage-1 class and the
	// pinned 30 s retry delay, and the loop must stay alive (retrying,
	// not parking).
	guardianURL, _ := installRenewalHarness(t,
		tokenAnswer(2*time.Second),
		renewAnswer{status: http.StatusUnavailableForLegalReasons,
			body: `{"error":"unavailable_in_region"}`},
	)
	controller, session, cb := renewLoopController(t, guardianURL)

	pass, err := controller.AcquireInitialPass(context.Background())
	if err != nil {
		t.Fatalf("initial pass: %v", err)
	}
	controller.setSession(session, pass)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { controller.runRenewalLoop(ctx); close(done) }()
	defer stopRenewalLoop(t, cancel, done)

	deadline := time.Now().Add(10 * time.Second)
	for {
		cb.mu.Lock()
		fails := len(cb.fails)
		cb.mu.Unlock()
		if fails >= 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("OnRenewalFail never fired: fails=%d", fails)
		}
		time.Sleep(20 * time.Millisecond)
	}

	cb.mu.Lock()
	rec := cb.fails[0]
	cb.mu.Unlock()
	if rec.failCode != "guardianRegionUnavailable" {
		t.Fatalf("renewal failCode = %q, want guardianRegionUnavailable", rec.failCode)
	}
	if rec.retryInMs != (30 * time.Second).Milliseconds() {
		t.Fatalf("renewal retryInMs = %d, want %d (proxyPassRetryDelay)",
			rec.retryInMs, (30 * time.Second).Milliseconds())
	}
	if strings.TrimSpace(rec.redacted) == "" {
		t.Fatalf("the redacted failure text is empty")
	}

	// The loop is still running (retrying) — no terminal outcome.
	select {
	case kind := <-controller.Terminal():
		t.Fatalf("a 451 renewal failure parked the engine: %v", kind)
	default:
	}
}

func TestRenewalLoopQuotaExhaustionIsTerminal(t *testing.T) {
	// Script: a short-lived initial pass, then HTTP 429 on the renewal —
	// quota is its own TERMINAL outcome (no OnRenewalFail, no infinite
	// retry).
	guardianURL, _ := installRenewalHarness(t,
		tokenAnswer(2*time.Second),
		renewAnswer{status: http.StatusTooManyRequests, body: `{"error":"quota_exceeded"}`},
	)
	controller, session, cb := renewLoopController(t, guardianURL)

	pass, err := controller.AcquireInitialPass(context.Background())
	if err != nil {
		t.Fatalf("initial pass: %v", err)
	}
	controller.setSession(session, pass)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { controller.runRenewalLoop(ctx); close(done) }()
	defer stopRenewalLoop(t, cancel, done)

	select {
	case kind := <-controller.Terminal():
		if kind != TerminalQuota {
			t.Fatalf("terminal = %v, want TerminalQuota", kind)
		}
	case <-time.After(10 * time.Second):
		t.Fatalf("quota exhaustion never became terminal")
	}

	cb.mu.Lock()
	fails := len(cb.fails)
	cb.mu.Unlock()
	if fails != 0 {
		t.Fatalf("quota must not surface as OnRenewalFail: %+v", cb.fails)
	}
}

func TestRenewalLoopOverstayedExpiryIsTerminal(t *testing.T) {
	// A pass whose expiry is already > 2 min in the past (the pinned
	// proxyPassRenewTimeout budget): the renewal loop must park the
	// engine with TerminalRenewalTimeout — the host's signal to
	// reconnect — instead of retrying a dead session forever.
	guardianURL, _ := installRenewalHarness(t,
		tokenAnswer(-5*time.Minute),
	)
	controller, session, cb := renewLoopController(t, guardianURL)

	pass, err := controller.AcquireInitialPass(context.Background())
	if err != nil {
		t.Fatalf("initial pass: %v", err)
	}
	controller.setSession(session, pass)
	if overdue := time.Since(pass.ExpiresAt()); overdue < 2*time.Minute {
		t.Fatalf("test mint did not produce an overstayed pass: overdue=%v", overdue)
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { controller.runRenewalLoop(ctx); close(done) }()
	defer stopRenewalLoop(t, cancel, done)

	select {
	case kind := <-controller.Terminal():
		if kind != TerminalRenewalTimeout {
			t.Fatalf("terminal = %v, want TerminalRenewalTimeout", kind)
		}
	case <-time.After(10 * time.Second):
		t.Fatalf("the overstayed pass never became terminal")
	}

	cb.mu.Lock()
	fails := len(cb.fails)
	cb.mu.Unlock()
	if fails != 0 {
		t.Fatalf("the renewal-timeout must not surface as OnRenewalFail: %+v", cb.fails)
	}
}
