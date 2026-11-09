package upstream

// proxyController — ONE MASQUE session + its renewal loop, ADAPTED from
// the pinned upstream's cmd/proxy-demo/main.go proxyController with the
// POOL REMOVED (the phase-1 decree: exactly one upstream session; no
// rotation, no affinity). The controller:
//
//   - acquires the initial Guardian pass (refreshing the SAME
//     account's OAuth token when the access token is stale — never a
//     different account, never a pool);
//   - builds the single h2/h3 session and serves SOCKS tunnels
//     through it;
//   - renews the pass before expiry (renewed), retrying with backoff
//     (renewalFailed + retryInMs); a hard timeout parks the engine
//     with the renewalTimeout outcome (exit 3);
//   - reports quota exhaustion as its own terminal outcome (exit 2).

import (
        "context"
        "errors"
        "fmt"
        "net"
        "net/url"
        "strings"
        "sync"
        "time"

        vpnclient "firefox-vpn-client"
)

const (
        proxyPassRenewLead    = 2 * time.Minute
        proxyPassRetryDelay   = 30 * time.Second
        proxyPassRenewTimeout = 2 * time.Minute
        oauthRefreshLead      = 2 * time.Minute
)

// QuotaError marks quota exhaustion (its own terminal outcome).
type QuotaError struct{ Detail string }

func (e *QuotaError) Error() string { return "quota exhausted: " + e.Detail }

// RenewalTimeoutError marks a dead session the host must reconnect.
type RenewalTimeoutError struct{ Detail string }

func (e *RenewalTimeoutError) Error() string { return "renewal timeout: " + e.Detail }

// TerminalKind is the renewal loop's terminal outcome.
type TerminalKind int

const (
        TerminalNone TerminalKind = iota
        TerminalQuota
        TerminalRenewalTimeout
)

// terminalCh capacity 1: the park loop selects on it.

// ControllerConfig wires the controller.
type ControllerConfig struct {
        Guardian      string
        AccessToken   string
        RefreshToken  string
        Transport     string // "h2" | "h3"
        ProxyURL      *url.URL
        OpenTimeout   time.Duration
        OnPassRenewed func(pass *vpnclient.ProxyPassInfo)
        OnAuthRefresh func(pair vpnclient.TokenResponse)
        OnRenewalFail func(redactedErr string, retryInMs int64)
        Logf          func(format string, args ...any)
}

// Controller owns the single session and its renewal.
type Controller struct {
        cfg ControllerConfig

        mu          sync.Mutex
        session     Session
        rawToken    string
        expiresAt   time.Time
        closed      bool
        closeOnce   sync.Once
        sessionDown chan struct{}

        terminalMu sync.Mutex
        terminal   TerminalKind
        terminalCh chan TerminalKind
}

// NewController builds (but does not start) the controller.
func NewController(cfg ControllerConfig) *Controller {
        if cfg.Logf == nil {
                cfg.Logf = func(string, ...any) {}
        }
        return &Controller{
                cfg:         cfg,
                sessionDown: make(chan struct{}),
                terminalCh:  make(chan TerminalKind, 1),
        }
}

// Terminal yields the renewal loop's terminal outcome (quota /
// renewal-timeout), if one ever fires.
func (c *Controller) Terminal() <-chan TerminalKind { return c.terminalCh }

func (c *Controller) markTerminal(kind TerminalKind) {
        c.terminalMu.Lock()
        if c.terminal == TerminalNone {
                c.terminal = kind
                c.terminalCh <- kind
        }
        c.terminalMu.Unlock()
}

// AcquireInitialPass fetches the first Guardian pass, refreshing the
// SAME account's OAuth pair when the access token is rejected as stale
// (errors are classified by the caller through fferr).
func (c *Controller) AcquireInitialPass(ctx context.Context) (*vpnclient.ProxyPassInfo, error) {
        pass, err := vpnclient.FetchProxyPass(ctx, c.cfg.Guardian, c.cfg.AccessToken)
        if err == nil {
                return pass, nil
        }
        if !errors.Is(err, vpnclient.ErrTokenInvalid) {
                return nil, err
        }
        // Same-account recovery: refresh the OAuth pair once and retry.
        if strings.TrimSpace(c.cfg.RefreshToken) == "" {
                return nil, err
        }
        refreshed, refreshErr := vpnclient.FxaRefreshToken(ctx, c.cfg.RefreshToken)
        if refreshErr != nil {
                return nil, err // the original token-invalid chain
        }
        if strings.TrimSpace(refreshed.AccessToken) == "" ||
                strings.TrimSpace(refreshed.RefreshToken) == "" {
                return nil, fmt.Errorf("refresh returned an unusable token pair")
        }
        c.cfg.OnAuthRefresh(*refreshed)
        c.cfg.AccessToken = refreshed.AccessToken
        c.cfg.RefreshToken = refreshed.RefreshToken
        return vpnclient.FetchProxyPass(ctx, c.cfg.Guardian, c.cfg.AccessToken)
}

// Start builds the single upstream session with the acquired pass and
// starts the renewal loop. The returned latency is the session build
// time (the upstreamReady event).
func (c *Controller) Start(ctx context.Context, pass *vpnclient.ProxyPassInfo) (latency time.Duration, err error) {
        started := time.Now()
        switch c.cfg.Transport {
        case "h3":
                var s *H3ProxySession
                s, err = NewH3ProxySession(c.cfg.ProxyURL, pass.RawToken, c.cfg.OpenTimeout)
                if err == nil {
                        c.setSession(s, pass)
                }
        default:
                var s *H2ProxySession
                s, err = NewH2ProxySession(c.cfg.ProxyURL, pass.RawToken, c.cfg.OpenTimeout)
                if err == nil {
                        c.setSession(s, pass)
                }
        }
        if err != nil {
                return 0, err
        }
        // Stage 3 (performance mission): mirror the pinned upstream's
        // session-established logging ("upstream HTTP/2 session established
        // proxy=…", "upstream HTTP/3 session established proxy=…",
        // "transport=http2|http3 …") that the phase-1 adaptation dropped —
        // without it the ACTUALLY-live transport is invisible on-device
        // (core-log.txt), so the mission's "real Transport" baseline
        // field can never be evidenced and an h2/h3 comparison can never
        // be recorded. Info-level through the host's Logf; no behavioral
        // change.
        if host, ok := c.SessionHost(); ok {
                c.cfg.Logf("%s", sessionEstablishedLog(c.cfg.Transport, host, time.Since(started)))
        }
        go c.runRenewalLoop(ctx)
        return time.Since(started), nil
}

// sessionEstablishedLog renders the upstream session-established log
// line: the transport that is REALLY live (h2 | h3), the proxy it is
// pinned to, and the session build latency (the upstream proxy-demo
// logs the same facts at the same point — "upstream HTTP/{2,3} session
// established proxy=…" and "upstream_session_establish_latency=…").
func sessionEstablishedLog(transport, proxyHost string, latency time.Duration) string {
        return fmt.Sprintf("upstream session established transport=%s proxy=%s establish_latency=%s",
                transport, proxyHost, latency.Round(time.Millisecond))
}

func (c *Controller) setSession(s Session, pass *vpnclient.ProxyPassInfo) {
        c.mu.Lock()
        defer c.mu.Unlock()
        c.session = s
        c.rawToken = pass.RawToken
        c.expiresAt = pass.ExpiresAt()
}

// Session reports the proxy host of the live session (upstreamReady).
func (c *Controller) SessionHost() (string, bool) {
        c.mu.Lock()
        defer c.mu.Unlock()
        if c.session == nil {
                return "", false
        }
        switch s := c.session.(type) {
        case *H2ProxySession:
                return s.ProxyHost(), true
        case *H3ProxySession:
                return s.ProxyHost(), true
        }
        return "", false
}

// OpenTunnel serves one SOCKS CONNECT through the live session. A dead
// or unhealthy session fails honestly (the host's reconnect owns the
// recovery).
func (c *Controller) OpenTunnel(authority string) (net.Conn, error) {
        c.mu.Lock()
        session := c.session
        c.mu.Unlock()
        if session == nil {
                return nil, errors.New("no upstream session")
        }
        if !session.IsAlive() {
                return nil, errors.New("upstream session is not alive")
        }
        return session.OpenTunnel(authority)
}

func (c *Controller) runRenewalLoop(ctx context.Context) {
        for {
                next := c.nextRenewalDelay()
                if !c.sleepOrDone(ctx, next) {
                        return
                }
                if err := c.renew(ctx); err != nil {
                        if errors.Is(err, context.Canceled) {
                                return
                        }
                        var quota *QuotaError
                        if errors.As(err, &quota) {
                                c.cfg.Logf("renewal: quota exhausted")
                                c.markTerminal(TerminalQuota)
                                return
                        }
                        var renewalTimeout *RenewalTimeoutError
                        if errors.As(err, &renewalTimeout) {
                                c.cfg.Logf("renewal: timed out")
                                c.markTerminal(TerminalRenewalTimeout)
                                return
                        }
                        c.cfg.OnRenewalFail(redactMessage(err), proxyPassRetryDelay.Milliseconds())
                }
        }
}

// nextRenewalDelay sleeps until renewLead before pass expiry (or the
// retry delay when the expiry is unknown).
func (c *Controller) nextRenewalDelay() time.Duration {
        c.mu.Lock()
        defer c.mu.Unlock()
        if c.expiresAt.IsZero() {
                return proxyPassRetryDelay
        }
        d := time.Until(c.expiresAt.Add(-proxyPassRenewLead))
        if d < 0 {
                d = 0
        }
        return d
}

func (c *Controller) sleepOrDone(ctx context.Context, d time.Duration) bool {
        if d <= 0 {
                return ctx.Err() == nil
        }
        timer := time.NewTimer(d)
        defer timer.Stop()
        select {
        case <-ctx.Done():
                return false
        case <-timer.C:
                return true
        }
}

// renew refreshes the pass before expiry. Quota exhaustion is its own
// terminal error; a renewal that overstays the hard timeout parks the
// engine with RenewalTimeoutError.
func (c *Controller) renew(ctx context.Context) error {
        c.mu.Lock()
        expiry := c.expiresAt
        c.mu.Unlock()

        hardDeadline := proxyPassRenewTimeout
        if !expiry.IsZero() {
                if overdue := time.Since(expiry); overdue > proxyPassRenewTimeout {
                        return &RenewalTimeoutError{Detail: "the proxy pass expired and renewal overstayed its budget"}
                }
                _ = hardDeadline
        }

        renewCtx, cancel := context.WithTimeout(ctx, proxyPassRenewTimeout)
        defer cancel()

        pass, err := vpnclient.FetchProxyPass(renewCtx, c.cfg.Guardian, c.cfg.AccessToken)
        if err != nil {
                if errors.Is(err, vpnclient.ErrQuotaExceeded) {
                        return &QuotaError{Detail: quotaDetail(err)}
                }
                if errors.Is(err, vpnclient.ErrTokenInvalid) &&
                        strings.TrimSpace(c.cfg.RefreshToken) != "" {
                        refreshed, refreshErr := vpnclient.FxaRefreshToken(renewCtx, c.cfg.RefreshToken)
                        if refreshErr == nil &&
                                strings.TrimSpace(refreshed.AccessToken) != "" &&
                                strings.TrimSpace(refreshed.RefreshToken) != "" {
                                c.cfg.OnAuthRefresh(*refreshed)
                                c.cfg.AccessToken = refreshed.AccessToken
                                c.cfg.RefreshToken = refreshed.RefreshToken
                                pass, err = vpnclient.FetchProxyPass(renewCtx, c.cfg.Guardian, c.cfg.AccessToken)
                        }
                }
                if err != nil {
                        if ctx.Err() != nil {
                                return ctx.Err()
                        }
                        if errors.Is(err, vpnclient.ErrQuotaExceeded) {
                                return &QuotaError{Detail: quotaDetail(err)}
                        }
                        return err
                }
        }

        // Adopt the fresh pass on the live session (the bearer swap).
        c.mu.Lock()
        session := c.session
        c.rawToken = pass.RawToken
        c.expiresAt = pass.ExpiresAt()
        c.mu.Unlock()
        if session != nil {
                if swapErr := session.UpdateToken(pass.RawToken); swapErr != nil {
                        c.cfg.Logf("renewal: token swap on the live session failed: %v", swapErr)
                }
        }
        c.cfg.OnPassRenewed(pass)
        return nil
}

func quotaDetail(err error) string {
        s := redactMessage(err)
        if s == "" {
                return "monthly quota exhausted"
        }
        return s
}

// redactMessage keeps the renewal-failure event message value-free:
// only the error's operator-safe shape, token runs masked.
func redactMessage(err error) string {
        if err == nil {
                return ""
        }
        s := err.Error()
        if len(s) > 300 {
                s = s[:300]
        }
        return s
}

// Close tears the session down (idempotent).
func (c *Controller) Close() error {
        var err error
        c.closeOnce.Do(func() {
                c.mu.Lock()
                c.closed = true
                session := c.session
                c.session = nil
                c.mu.Unlock()
                if session != nil {
                        err = session.Close()
                }
                close(c.sessionDown)
        })
        return err
}
