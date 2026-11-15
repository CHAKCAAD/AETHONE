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
        udpConn   net.PacketConn
        rt        *http3.Transport
        proxyHost string
        token     string
        timeout   time.Duration
        tokenMu   sync.RWMutex
        closeOnce sync.Once
        closeErr  error
}

// NewH3ProxySession dials the MASQUE proxy directly over QUIC.
func NewH3ProxySession(proxyURL *url.URL, token string, timeout time.Duration) (*H3ProxySession, error) {
	return newH3ProxySession(proxyURL, token, timeout, "")
}

// NewH3ProxySessionThroughSOCKS carries QUIC datagrams through the Aether
// SOCKS5 UDP association. The destination hostname is encoded in each SOCKS
// UDP frame, so its lookup happens at the outer Aether/WARP carrier.
func NewH3ProxySessionThroughSOCKS(proxyURL *url.URL, token string, timeout time.Duration, socksAddr string) (*H3ProxySession, error) {
	return newH3ProxySession(proxyURL, token, timeout, socksAddr)
}

func newH3ProxySession(proxyURL *url.URL, token string, timeout time.Duration, socksAddr string) (*H3ProxySession, error) {
	host := proxyURL.Hostname()
	portStr := proxyURL.Port()
	if portStr == "" {
		portStr = "443"
	}
	port, err := strconv.Atoi(portStr)
	if err != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("invalid proxy port %q", portStr)
	}
	proxyHost := net.JoinHostPort(host, portStr)

	ctx := context.Background()
	cancel := func() {}
	if timeout > 0 {
		ctx, cancel = context.WithTimeout(ctx, timeout)
	}
	defer cancel()

	tlsCfg := &tls.Config{
		ServerName: host,
		MinVersion: tls.VersionTLS13,
		NextProtos: []string{"h3"},
	}
	quicCfg := &quic.Config{
		KeepAlivePeriod:  30 * time.Second,
		InitialPacketSize: 1200,
	}

	var (
		conn    *quic.Conn
		udpConn net.PacketConn
		lastErr error
	)
	if socksAddr != "" {
		packetConn, packetErr := NewSOCKS5PacketConn(ctx, socksAddr)
		if packetErr != nil {
			return nil, packetErr
		}
		remote := &socks5DomainUDPAddr{host: host, port: port}
		conn, err = quic.Dial(ctx, packetConn, remote, tlsCfg, quicCfg)
		if err != nil {
			_ = packetConn.Close()
			return nil, fmt.Errorf("dial MASQUE through SOCKS5: %w", err)
		}
		udpConn = packetConn
	} else {
		ips, resolveErr := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
		if resolveErr != nil {
			return nil, fmt.Errorf("resolve %s: %w", host, resolveErr)
		}
		if len(ips) == 0 {
			return nil, fmt.Errorf("no addresses for %s", host)
		}

		var perAttempt time.Duration
		if timeout > 0 {
			perAttempt = timeout / time.Duration(len(ips))
			if perAttempt < 3*time.Second {
				perAttempt = 3 * time.Second
			}
		}
		for _, ip := range ips {
			packetConn, bindErr := net.ListenUDP("udp", &net.UDPAddr{Port: 0})
			if bindErr != nil {
				lastErr = bindErr
				continue
			}
			remote := &net.UDPAddr{IP: ip.AsSlice(), Port: port, Zone: ip.Zone()}
			attemptCtx := ctx
			attemptCancel := func() {}
			if perAttempt > 0 {
				attemptCtx, attemptCancel = context.WithTimeout(ctx, perAttempt)
			}
			candidate, dialErr := quic.Dial(attemptCtx, packetConn, remote, tlsCfg, quicCfg)
			attemptCancel()
			if dialErr != nil {
				_ = packetConn.Close()
				lastErr = fmt.Errorf("dial %s: %w", remote, dialErr)
				continue
			}
			conn = candidate
			udpConn = packetConn
			break
		}
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

// RemoteAddr reports the connected proxy address — the endpoint IP
// (and its family) the session is actually pinned to. The upstream's
// h3 session-established log carries conn.RemoteAddr() at this exact
// point; AETHONE routes the same fact through its own log line
// (stage 5 of the performance mission).
func (s *H3ProxySession) RemoteAddr() string {
        if s.conn == nil {
                return ""
        }
        return s.conn.RemoteAddr().String()
}

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
