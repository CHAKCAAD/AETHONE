package upstream

// h2ProxySession — one TLS 1.3 + ALPN h2 MASQUE session, ADAPTED from
// the pinned upstream's cmd/proxy-demo/main.go (newH2ProxySession,
// runKeepAlive, OpenTunnel, UpdateToken, Close). The pool plumbing and
// the sessionFailureTracker are REMOVED (single-session policy: the
// controller owns exactly one session; failures surface to it directly).

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

	"golang.org/x/net/http2"
)

const (
	upstreamKeepAliveInterval = 10 * time.Second
	upstreamKeepAlivePingTimeout = 5 * time.Second
)

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
	raw       *tls.Conn
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

// tunnelOpenTimeoutError marks a CONNECT that exceeded its open budget.
type tunnelOpenTimeoutError struct{ timeout time.Duration }

func (e *tunnelOpenTimeoutError) Error() string {
	return fmt.Sprintf("proxy CONNECT timed out after %s", e.timeout)
}
func (e *tunnelOpenTimeoutError) Timeout() bool   { return true }
func (e *tunnelOpenTimeoutError) Temporary() bool { return true }

// NewH2ProxySession dials the MASQUE proxy with TLS 1.2+ and the h2
// ALPN (ADAPTED from newH2ProxySession; keepalive retained).
func NewH2ProxySession(proxyURL *url.URL, token string, timeout time.Duration) (*H2ProxySession, error) {
	proxyHost := proxyURL.Host
	if proxyURL.Port() == "" {
		proxyHost = proxyURL.Hostname() + ":443"
	}

	dialer := &net.Dialer{Timeout: timeout}
	proxyTLS, err := tls.DialWithDialer(dialer, "tcp", proxyHost, &tls.Config{
		ServerName: proxyURL.Hostname(),
		MinVersion: tls.VersionTLS12,
		NextProtos: []string{"h2"},
	})
	if err != nil {
		return nil, err
	}

	if proxyTLS.ConnectionState().NegotiatedProtocol != "h2" {
		_ = proxyTLS.Close()
		return nil, ErrHTTP2Unavailable
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
