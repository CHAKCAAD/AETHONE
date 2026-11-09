package upstream

// h3ProxySession — one QUIC + ALPN h3 MASQUE session, ADAPTED from the
// pinned upstream's cmd/proxy-demo/main.go (newH3ProxySession,
// OpenTunnel, UpdateToken, Close). Failure to negotiate h3 surfaces as
// ErrHTTP3Unavailable — the controller reports upstreamSessionFailed
// with the h3 reason (the h2 default stays the proven path).

import (
        "context"
        "crypto/tls"
        "errors"
        "fmt"
        "io"
        "net"
        "net/http"
        "net/url"
        "strconv"
        "strings"
        "sync"
        "time"

        "github.com/quic-go/quic-go"
        "github.com/quic-go/quic-go/http3"
)

// ErrHTTP3Unavailable: the proxy did not negotiate HTTP/3.
var ErrHTTP3Unavailable = errors.New("proxy did not negotiate HTTP/3")

// H3ProxySession holds a single QUIC connection used for HTTP/3
// CONNECT tunnels.
type H3ProxySession struct {
        conn      *quic.Conn
        udpConn   *net.UDPConn
        rt        *http3.Transport
        proxyHost string
        token     string
        timeout   time.Duration
        tokenMu   sync.RWMutex
        closeOnce sync.Once
        closeErr  error
}

// NewH3ProxySession dials the MASQUE proxy over QUIC (ADAPTED; the
// InitialPacketSize 1200 below-RFC-floor start is retained so the
// handshake succeeds on low-MTU paths, with PMTU discovery growing it).
func NewH3ProxySession(proxyURL *url.URL, token string, timeout time.Duration) (*H3ProxySession, error) {
        host := proxyURL.Hostname()
        portStr := proxyURL.Port()
        if portStr == "" {
                portStr = "443"
        }
        port, err := strconv.Atoi(portStr)
        if err != nil {
                return nil, fmt.Errorf("invalid proxy port %q: %w", portStr, err)
        }
        proxyHost := net.JoinHostPort(host, portStr)

        ctx := context.Background()
        cancel := func() {}
        if timeout > 0 {
                ctx, cancel = context.WithTimeout(context.Background(), timeout)
        }
        defer cancel()

        ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
        if err != nil {
                return nil, fmt.Errorf("resolve %s: %w", host, err)
        }
        if len(ips) == 0 {
                return nil, fmt.Errorf("no addresses for %s", host)
        }

        tlsCfg := &tls.Config{
                ServerName: host,
                MinVersion: tls.VersionTLS13,
                NextProtos: []string{"h3"},
        }
        quicCfg := &quic.Config{
                KeepAlivePeriod:  30 * time.Second,
                InitialPacketSize: 1200,
        }

        var perAttempt time.Duration
        if timeout > 0 {
                perAttempt = timeout / time.Duration(len(ips))
                if perAttempt < 3*time.Second {
                        perAttempt = 3 * time.Second
                }
        }

        var (
                conn    *quic.Conn
                udpConn *net.UDPConn
                lastErr error
        )
        for _, ip := range ips {
                uc, err := net.ListenUDP("udp", &net.UDPAddr{Port: 0})
                if err != nil {
                        lastErr = err
                        continue
                }
                udpAddr := &net.UDPAddr{IP: ip.AsSlice(), Port: port, Zone: ip.Zone()}
                attemptCtx := ctx
                attemptCancel := func() {}
                if perAttempt > 0 {
                        attemptCtx, attemptCancel = context.WithTimeout(ctx, perAttempt)
                }
                c, err := quic.Dial(attemptCtx, uc, udpAddr, tlsCfg, quicCfg)
                attemptCancel()
                if err != nil {
                        _ = uc.Close()
                        lastErr = fmt.Errorf("dial %s: %w", udpAddr, err)
                        continue
                }
                conn = c
                udpConn = uc
                break
        }
        if conn == nil {
                return nil, lastErr
        }

        if conn.ConnectionState().TLS.NegotiatedProtocol != "h3" {
                _ = conn.CloseWithError(0, "")
                _ = udpConn.Close()
                return nil, ErrHTTP3Unavailable
        }

        rt := &http3.Transport{
                Dial: func(_ context.Context, addr string, tlsCfg *tls.Config, cfg *quic.Config) (*quic.Conn, error) {
                        return conn, nil
                },
        }

        return &H3ProxySession{
                conn:      conn,
                udpConn:   udpConn,
                rt:        rt,
                proxyHost: proxyHost,
                token:     token,
                timeout:   timeout,
        }, nil
}

// ProxyHost reports the dial target (the upstreamReady event).
func (s *H3ProxySession) ProxyHost() string { return s.proxyHost }

// OpenTunnel opens one CONNECT tunnel through the QUIC session
// (ADAPTED).
func (s *H3ProxySession) OpenTunnel(authority string) (net.Conn, error) {
        reqBody := NewTunnelWriteBuffer(DefaultTunnelWriteBufSize)
        resp, cancel, err := roundTripWithOpenTimeout(s.timeout, func(ctx context.Context) (*http.Response, error) {
                req, err := http.NewRequestWithContext(ctx, http.MethodConnect, "https://"+authority, reqBody)
                if err != nil {
                        return nil, err
                }
                req.Host = authority
                req.URL.Host = s.proxyHost
                req.Header.Set("Proxy-Authorization", "Bearer "+s.bearerToken())
                return s.rt.RoundTrip(req)
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
                name:    "h3-connect-stream",
                cancel:  cancel,
        }, nil
}

func (s *H3ProxySession) bearerToken() string {
        s.tokenMu.RLock()
        defer s.tokenMu.RUnlock()
        return s.token
}

// UpdateToken swaps the live proxy-pass bearer (renewal path).
func (s *H3ProxySession) UpdateToken(token string) error {
        if strings.TrimSpace(token) == "" {
                return fmt.Errorf("empty proxy session token")
        }
        s.tokenMu.Lock()
        s.token = token
        s.tokenMu.Unlock()
        return nil
}

// IsAlive: the QUIC connection is up (its context not done).
func (s *H3ProxySession) IsAlive() bool {
        if s.conn == nil {
                return false
        }
        return s.conn.Context().Err() == nil
}

// Close tears the QUIC session down.
func (s *H3ProxySession) Close() error {
        s.closeOnce.Do(func() {
                if s.rt != nil {
                        _ = s.rt.Close()
                }
                if s.conn != nil {
                        s.closeErr = s.conn.CloseWithError(0, "")
                }
                if s.udpConn != nil {
                        if closeErr := s.udpConn.Close(); s.closeErr == nil {
                                s.closeErr = closeErr
                        }
                }
        })
        return s.closeErr
}
