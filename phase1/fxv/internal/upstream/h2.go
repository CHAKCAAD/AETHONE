package upstream

// h2ProxySession — one TLS 1.3 + ALPN h2 MASQUE session, ADAPTED from
// the pinned upstream's cmd/proxy-demo/main.go (newH2ProxySession,
// runKeepAlive, OpenTunnel, UpdateToken, Close). The pool plumbing and
// the sessionFailureTracker are REMOVED (single-session policy: the
// controller owns exactly one session; failures surface to it directly).
//
// 2.0.0 — the reference's TLS posture on BOTH dial paths (internal/proxy/
// upstream_tls.go): the connection offers the pinned desktop-Firefox
// uTLS hello FIRST (on a direct dial the raw connection is wrapped with
// the reference's hello split too), and a handshake that fails that way
// is tried once more with Go's own hello — whichever passes sticks for
// the process. The DIRECT data plane no longer looks like a Go program
// to the network.

import (
        "context"
        "crypto/tls"
        "errors"
        "fmt"
        "io"
        "net"
        "net/http"
        "net/url"
        "strings"
        "sync"
        "sync/atomic"
        "time"

        utls "github.com/refraction-networking/utls"
        "golang.org/x/net/http2"

        vpnclient "firefox-vpn-client"
)

const (
        upstreamKeepAliveInterval   = 10 * time.Second
        upstreamKeepAlivePingTimeout = 5 * time.Second

        // firefoxHelloShare is how much of the dial budget the Firefox hello
        // may use, leaving the rest for Go's (the reference's rule: a network
        // that drops the Firefox hello silently still gets a connection
        // through Go's).
        firefoxHelloShare = 2
)

// upstreamGoTLSHello is set once the Firefox hello failed where Go's
// passed (the reference's upstreamGoTLS): every later upstream connection
// starts with Go's hello without another failure.
var upstreamGoTLSHello atomic.Bool

// ErrHTTP2Unavailable: the proxy did not negotiate HTTP/2.
var ErrHTTP2Unavailable = errors.New("proxy did not negotiate HTTP/2")

// Session is the single-upstream contract (OpenTunnel + live token
// swap + liveness + close).
type Session interface {
        OpenTunnel(authority string) (net.Conn, error)
        UpdateToken(token string) error
        IsAlive() bool
        Close() error
}

// H2ProxySession holds the TLS+h2 connection and its clientconn.
type H2ProxySession struct {
        raw       net.Conn
        cc        *http2.ClientConn
        proxyHost string
        token     string
        timeout   time.Duration
        tokenMu   sync.RWMutex
        closeOnce sync.Once
        closeErr  error

        alive         atomic.Bool
        stopKeepAlive context.CancelFunc
}

// proxyConnectHTTPError carries a non-2xx CONNECT answer.
type proxyConnectHTTPError struct {
        statusCode int
        status     string
        body       string
}

func (e *proxyConnectHTTPError) Error() string {
        if e.body == "" {
                return fmt.Sprintf("proxy CONNECT failed: %s", e.status)
        }
        return fmt.Sprintf("proxy CONNECT failed: %s: %s", e.status, e.body)
}

// RedactedError renders err for LOGGING with the proxy CONNECT answer
// body redacted unless verbose (ADAPTED from the demo's logErr — the
// SOCKS layer's always-on warn line must not carry the proxy's error
// page into core-log.txt; the body is arbitrary remote content).
func RedactedError(err error, verbose bool) string {
        if err == nil {
                return "<nil>"
        }
        if verbose {
                return err.Error()
        }
        var connectErr *proxyConnectHTTPError
        if errors.As(err, &connectErr) {
                sanitized := *connectErr
                if sanitized.body != "" {
                        sanitized.body = "<redacted; use -verbose>"
                }
                return sanitized.Error()
        }
        return err.Error()
}

// tunnelOpenTimeoutError marks a CONNECT that exceeded its open budget.
type tunnelOpenTimeoutError struct{ timeout time.Duration }

func (e *tunnelOpenTimeoutError) Error() string {
        return fmt.Sprintf("proxy CONNECT timed out after %s", e.timeout)
}
func (e *tunnelOpenTimeoutError) Timeout() bool   { return true }
func (e *tunnelOpenTimeoutError) Temporary() bool { return true }

// ContextDialer is implemented by net.Dialer and SOCKS5Dialer.
type ContextDialer interface {
        DialContext(context.Context, string, string) (net.Conn, error)
}

// directFirefoxDialer is the DIRECT data-plane dialer: a plain TCP dial
// to the Fastly edge whose connection is wrapped with the reference's
// hello split before TLS.
type directFirefoxDialer struct{ timeout time.Duration }

func (d directFirefoxDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
        raw, err := (&net.Dialer{Timeout: d.timeout}).DialContext(ctx, network, address)
        if err != nil {
                return nil, err
        }
        return vpnclient.WrapHelloSplit(raw), nil
}

// NewH2ProxySession dials the MASQUE proxy directly with TLS 1.2+ and h2.
func NewH2ProxySession(proxyURL *url.URL, token string, timeout time.Duration) (*H2ProxySession, error) {
        return newH2ProxySession(proxyURL, token, timeout, directFirefoxDialer{timeout: timeout})
}

// NewH2ProxySessionThroughSOCKS carries the Fastly MASQUE TCP session through
// the selected Aether SOCKS5 listener. The hostname is sent to SOCKS5 intact,
// so Aether performs the destination lookup inside the outer WARP tunnel.
func NewH2ProxySessionThroughSOCKS(proxyURL *url.URL, token string, timeout time.Duration, socksAddr string) (*H2ProxySession, error) {
        return newH2ProxySession(proxyURL, token, timeout, &SOCKS5Dialer{ProxyAddr: socksAddr})
}

func newH2ProxySession(proxyURL *url.URL, token string, timeout time.Duration, dialer ContextDialer) (*H2ProxySession, error) {
        proxyHost := proxyURL.Host
        if proxyURL.Port() == "" {
                proxyHost = net.JoinHostPort(proxyURL.Hostname(), "443")
        }
        dialCtx := context.Background()
        dialCancel := func() {}
        if timeout > 0 {
                dialCtx, dialCancel = context.WithTimeout(dialCtx, timeout)
        }
        defer dialCancel()

        proxyTLS, err := upstreamHandshake(dialCtx, dialer, proxyURL, proxyHost)
        if err != nil {
                return nil, err
        }

        transport := &http2.Transport{
                ReadIdleTimeout:  30 * time.Second,
                PingTimeout:      15 * time.Second,
                WriteByteTimeout: 30 * time.Second,
        }
        cc, err := transport.NewClientConn(proxyTLS)
        if err != nil {
                _ = proxyTLS.Close()
                return nil, err
        }

        ctx, cancel := context.WithCancel(context.Background())
        session := &H2ProxySession{
                raw:           proxyTLS,
                cc:            cc,
                proxyHost:     proxyHost,
                token:         token,
                timeout:       timeout,
                stopKeepAlive: cancel,
        }
        session.alive.Store(true)
        go session.runKeepAlive(ctx)

        return session, nil
}

// upstreamHandshakeError marks a failure of TLS itself, which another
// hello may get past; a failure to connect is not one (the reference's
// own rule).
type upstreamHandshakeError struct{ err error }

func (e *upstreamHandshakeError) Error() string { return e.err.Error() }
func (e *upstreamHandshakeError) Unwrap() error { return e.err }

// upstreamHandshake dials the Fastly edge and completes TLS offering h2:
// the pinned desktop-Firefox uTLS hello first (with its share of the
// budget), Go's own hello on that failure; whichever passes sticks for
// the process (the reference's dialUpstreamTLSFor, adapted to the shared
// dialer seam so the SOCKS-carried path gets the same posture).
func upstreamHandshake(ctx context.Context, dialer ContextDialer, proxyURL *url.URL, proxyHost string) (net.Conn, error) {
        name := proxyURL.Hostname()
        if upstreamGoTLSHello.Load() {
                return goHelloH2(ctx, dialer, proxyHost, name)
        }
        firstCtx, cancel := firefoxHelloContext(ctx)
        defer cancel()
        conn, err := firefoxHelloH2(firstCtx, dialer, proxyHost, name)
        var failed *upstreamHandshakeError
        if err == nil || ctx.Err() != nil || !errors.As(err, &failed) {
                return conn, err
        }
        conn, err = goHelloH2(ctx, dialer, proxyHost, name)
        if err == nil {
                upstreamGoTLSHello.Store(true)
        }
        return conn, err
}

// firefoxHelloContext limits ctx to its share of the time left.
func firefoxHelloContext(ctx context.Context) (context.Context, context.CancelFunc) {
        deadline, ok := ctx.Deadline()
        if !ok {
                return context.WithCancel(ctx)
        }
        return context.WithTimeout(ctx, time.Until(deadline)/firefoxHelloShare)
}

func firefoxHelloH2(ctx context.Context, dialer ContextDialer, proxyHost, name string) (net.Conn, error) {
        raw, err := dialer.DialContext(ctx, "tcp", proxyHost)
        if err != nil {
                return nil, err
        }
        conn := utls.UClient(raw, &utls.Config{
                ServerName: name,
                MinVersion: tls.VersionTLS12,
        }, utls.HelloFirefox_Auto)
        if err := conn.HandshakeContext(ctx); err != nil {
                _ = raw.Close()
                return nil, &upstreamHandshakeError{err}
        }
        if err := negotiatedH2(conn.ConnectionState().NegotiatedProtocol); err != nil {
                _ = conn.Close()
                return nil, err
        }
        return conn, nil
}

func goHelloH2(ctx context.Context, dialer ContextDialer, proxyHost, name string) (net.Conn, error) {
        raw, err := dialer.DialContext(ctx, "tcp", proxyHost)
        if err != nil {
                return nil, err
        }
        conn := tls.Client(raw, &tls.Config{
                ServerName: name,
                MinVersion: tls.VersionTLS12,
                NextProtos: []string{"h2"},
        })
        if err := conn.HandshakeContext(ctx); err != nil {
                _ = raw.Close()
                return nil, &upstreamHandshakeError{err}
        }
        if err := negotiatedH2(conn.ConnectionState().NegotiatedProtocol); err != nil {
                _ = conn.Close()
                return nil, err
        }
        return conn, nil
}

func negotiatedH2(got string) error {
        if got == "h2" {
                return nil
        }
        return ErrHTTP2Unavailable
}

// ProxyHost reports the dial target (the upstreamReady event).
func (s *H2ProxySession) ProxyHost() string { return s.proxyHost }

// RemoteAddr reports the connected proxy address — the endpoint IP
// (and its family) the session is actually pinned to. The upstream's
// session-established log carries the same fact for h3; AETHONE
// mirrors it for BOTH transports so the default h2 path records the
// real endpoint on-device too (stage 5 of the performance mission).
func (s *H2ProxySession) RemoteAddr() string {
        if s.raw == nil {
                return ""
        }
        return s.raw.RemoteAddr().String()
}

func (s *H2ProxySession) runKeepAlive(ctx context.Context) {
        ticker := time.NewTicker(upstreamKeepAliveInterval)
        defer ticker.Stop()

        for {
                select {
                case <-ctx.Done():
                        return
                case <-ticker.C:
                        pingCtx, cancel := context.WithTimeout(ctx, upstreamKeepAlivePingTimeout)
                        err := s.cc.Ping(pingCtx)
                        cancel()
                        if err == nil {
                                continue
                        }
                        if ctx.Err() != nil {
                                return
                        }
                        s.alive.Store(false)
                        return
                }
        }
}

// IsAlive reports whether this session can still carry new tunnels.
func (s *H2ProxySession) IsAlive() bool {
        if !s.alive.Load() {
                return false
        }
        return s.cc.CanTakeNewRequest()
}

// OpenTunnel opens one CONNECT tunnel through the session (ADAPTED).
func (s *H2ProxySession) OpenTunnel(authority string) (net.Conn, error) {
        reqBody := NewTunnelWriteBuffer(DefaultTunnelWriteBufSize)
        resp, cancel, err := roundTripWithOpenTimeout(s.timeout, func(ctx context.Context) (*http.Response, error) {
                req, err := http.NewRequestWithContext(ctx, http.MethodConnect, "http://"+authority, reqBody)
                if err != nil {
                        return nil, err
                }
                req.Host = authority
                req.URL.Host = s.proxyHost
                req.Header.Set("Proxy-Authorization", "Bearer "+s.bearerToken())
                return s.cc.RoundTrip(req)
        })
        if err != nil {
                reqBody.FailRead(io.ErrClosedPipe)
                return nil, err
        }
        if resp.StatusCode < 200 || resp.StatusCode > 299 {
                cancel()
                body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
                _ = resp.Body.Close()
                reqBody.FailRead(io.ErrClosedPipe)
                return nil, &proxyConnectHTTPError{
                        statusCode: resp.StatusCode,
                        status:     resp.Status,
                        body:       strings.TrimSpace(string(body)),
                }
        }

        return &TunnelConn{
                reader:  resp.Body,
                writer:  reqBody,
                reqBody: reqBody,
                name:    "h2-connect-stream",
                cancel:  cancel,
        }, nil
}

func (s *H2ProxySession) bearerToken() string {
        s.tokenMu.RLock()
        defer s.tokenMu.RUnlock()
        return s.token
}

// UpdateToken swaps the live proxy-pass bearer (renewal path).
func (s *H2ProxySession) UpdateToken(token string) error {
        if strings.TrimSpace(token) == "" {
                return fmt.Errorf("empty proxy session token")
        }
        s.tokenMu.Lock()
        s.token = token
        s.tokenMu.Unlock()
        return nil
}

// Close tears the session down.
func (s *H2ProxySession) Close() error {
        s.closeOnce.Do(func() {
                s.alive.Store(false)
                if s.stopKeepAlive != nil {
                        s.stopKeepAlive()
                }
                if s.cc != nil {
                        s.closeErr = s.cc.Close()
                }
                if s.raw != nil {
                        if closeErr := s.raw.Close(); s.closeErr == nil {
                                s.closeErr = closeErr
                        }
                }
        })
        return s.closeErr
}

// roundTripResult carries one async roundtrip outcome.
type roundTripResult struct {
        resp *http.Response
        err  error
}

// roundTripWithOpenTimeout bounds one CONNECT roundtrip (ADAPTED).
func roundTripWithOpenTimeout(timeout time.Duration, do func(context.Context) (*http.Response, error)) (*http.Response, context.CancelFunc, error) {
        ctx, cancel := context.WithCancel(context.Background())
        if timeout <= 0 {
                resp, err := do(ctx)
                if err != nil {
                        cancel()
                        return nil, nil, err
                }
                return resp, cancel, nil
        }

        resultCh := make(chan roundTripResult, 1)
        go func() {
                resp, err := do(ctx)
                resultCh <- roundTripResult{resp: resp, err: err}
        }()

        timer := time.NewTimer(timeout)
        select {
        case result := <-resultCh:
                if !timer.Stop() {
                        select {
                        case <-timer.C:
                        default:
                        }
                }
                if result.err != nil {
                        cancel()
                        return nil, nil, result.err
                }
                return result.resp, cancel, nil
        case <-timer.C:
                cancel()
                go func() {
                        cleanupTimer := time.NewTimer(timeout)
                        defer cleanupTimer.Stop()
                        select {
                        case result := <-resultCh:
                                if result.resp != nil && result.resp.Body != nil {
                                        _ = result.resp.Body.Close()
                                }
                        case <-cleanupTimer.C:
                        }
                }()
                return nil, nil, &tunnelOpenTimeoutError{timeout: timeout}
        }
}
