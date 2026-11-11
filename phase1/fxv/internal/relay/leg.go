package relay

// The relay leg — the connection-level transport every relay request
// rides (personal and shared alike): a plain HTTP/1.1 transport whose
// TLS is optionally ECH-wrapped (ech.go), with two connection-routes
// that recover the relays some networks break, tried for read-only
// requests only (a request whose delivery state is ambiguous after a
// timeout must never be re-sent):
//
//      normal — the relay URL as given.
//      tls12  — the same URL over a TLS 1.2 handshake: some middleboxes
//               break the TLS 1.3 handshake to the relay host while 1.2
//               passes.
//      edge   — workers.dev relays only: connect to chatgpt.com's address
//               (a Cloudflare name that stays reachable) while the relay's
//               own name stays in SNI's place is NOT what happens — the
//               HTTP Host carries the relay, the connection and TLS go to
//               the edge name; Cloudflare's edge serves the worker the
//               Host names. The relay's TLS name and path are unchanged.
//
// A route that worked is remembered for RelayFirstFor so later
// requests go straight to it.

import (
        "context"
        "crypto/tls"
        "errors"
        "io"
        "net"
        "net/http"
        "net/url"
        "strings"
        "sync"
        "syscall"
        "time"
)

const (
        // legAttemptWait bounds one route when more remain.
        legAttemptWait = 3 * time.Second
        // legEdgeAddress is the reachable Cloudflare-fronted name the
        // workers.dev edge route connects to.
        legEdgeAddress = "chatgpt.com"
)

// legDialTimeout bounds each relay TCP connection.
const legDialTimeout = 20 * time.Second

// dialRelay is the plain TCP dialer for relay hosts.
func dialRelay(ctx context.Context, network, address string) (net.Conn, error) {
        d := &net.Dialer{Timeout: legDialTimeout}
        return d.DialContext(ctx, network, address)
}

// newRelayLeg builds the route-falling-back transport for one relay
// URL (ECH modes come from opts; the manifest and health probes of the
// shared pool ride the same construction).
func newRelayLeg(relayURL *url.URL, opts Options) http.RoundTripper {
        primary := &http.Transport{
                Proxy:               nil,
                DialContext:         dialRelay,
                TLSClientConfig:     &tls.Config{MinVersion: tls.VersionTLS12},
                TLSHandshakeTimeout: legDialTimeout,
                // The relay leg is HTTP/1.1: the relay is not Mozilla's Fastly
                // edge, and 1.1 keeps a failed route's retry semantics simple.
                ForceAttemptHTTP2: false,
        }
        if opts.ECHMode != ECHModeOff {
                if d, err := newECHDialer(relayURL.Hostname(), opts, dialRelay); err == nil {
                        primary.DialTLSContext = d.DialTLSContext
                }
        }
        if opts.ECHMode == ECHModeRequire {
                // Fail closed: no plain fallback route below.
                return primary
        }

        tls12 := primary.Clone()
        tls12.DialTLSContext = func(ctx context.Context, network, address string) (net.Conn, error) {
                raw, err := dialRelay(ctx, network, address)
                if err != nil {
                        return nil, err
                }
                conn := tls.Client(raw, &tls.Config{
                        ServerName: relayURL.Hostname(),
                        MinVersion: tls.VersionTLS12,
                        MaxVersion: tls.VersionTLS12,
                })
                if err := conn.HandshakeContext(ctx); err != nil {
                        _ = raw.Close()
                        return nil, err
                }
                return conn, nil
        }

        leg := &relayLeg{primary: primary, tls12: tls12}
        if strings.HasSuffix(strings.ToLower(relayURL.Hostname()), ".workers.dev") {
                edgeBase := primary.Clone()
                edgeBase.DialTLSContext = func(ctx context.Context, network, address string) (net.Conn, error) {
                        raw, err := dialRelay(ctx, network, address)
                        if err != nil {
                                return nil, err
                        }
                        conn := tls.Client(raw, &tls.Config{
                                ServerName: relayURL.Hostname(),
                                MinVersion: tls.VersionTLS12,
                        })
                        if err := conn.HandshakeContext(ctx); err != nil {
                                _ = raw.Close()
                                return nil, err
                        }
                        return conn, nil
                }
                leg.edge = &edgeRouteTransport{base: edgeBase}
        }
        return leg
}

// edgeRouteTransport changes the connection URL to the edge address
// while the HTTP Host keeps naming the relay; responses stay attached
// to the original request so cookies and redirects resolve against
// the relay.
type edgeRouteTransport struct{ base http.RoundTripper }

func (t *edgeRouteTransport) RoundTrip(req *http.Request) (*http.Response, error) {
        out := req.Clone(req.Context())
        u := *req.URL
        u.Host = legEdgeAddress
        out.URL, out.Host = &u, req.URL.Host
        resp, err := t.base.RoundTrip(out)
        if resp != nil {
                resp.Request = req
        }
        return resp, err
}

func (t *edgeRouteTransport) CloseIdleConnections() {
	if closer, ok := t.base.(interface{ CloseIdleConnections() }); ok {
		closer.CloseIdleConnections()
	}
}

// relayLeg tries the routes in order (the preferred one first when its
// memory is fresh).
type relayLeg struct {
        primary, tls12 http.RoundTripper
        edge           http.RoundTripper

        mu        sync.Mutex
        preferred string
        until     time.Time
}

func (l *relayLeg) preferredRoute() string {
        l.mu.Lock()
        defer l.mu.Unlock()
        if time.Now().Before(l.until) {
                return l.preferred
        }
        return ""
}

func (l *relayLeg) remember(route string) {
        l.mu.Lock()
        l.preferred, l.until = route, time.Now().Add(RelayFirstFor)
        l.mu.Unlock()
}

func (l *relayLeg) RoundTrip(req *http.Request) (*http.Response, error) {
        type route struct {
                name       string
                transport  http.RoundTripper
        }
        attempts := []route{{"", l.primary}, {"tls12", l.tls12}}
        if l.edge != nil {
                attempts = append(attempts, route{"edge", l.edge})
        }
        // A request that cannot be replayed, or that carries a body, takes
        // the first route only: a timeout after writing leaves the delivery
        // state unknown, so no second attempt is safe.
        if (req.Method != http.MethodGet && req.Method != http.MethodHead) ||
                (req.Body != nil && req.Body != http.NoBody) || !replayable(req) {
                return attempts[0].transport.RoundTrip(req)
        }
        if preferred := l.preferredRoute(); preferred != "" {
                for i := range attempts {
                        if attempts[i].name == preferred && i > 0 {
                                chosen := attempts[i]
                                copy(attempts[1:i+1], attempts[:i])
                                attempts[0] = chosen
                                break
                        }
                }
        }
        var lastErr error
        for i, attempt := range attempts {
                if req.Context().Err() != nil {
                        return nil, req.Context().Err()
                }
                resp, err, expired := l.try(req, attempt.transport, len(attempts)-i)
                if err == nil {
                        l.remember(attempt.name)
                        return resp, nil
                }
                lastErr = err
                if req.Context().Err() != nil || (!expired && !legRetryable(err)) {
                        break
                }
        }
        return nil, lastErr
}

// try runs one route under a soft deadline while more remain; expired
// reports that the deadline (not the server) ended the attempt.
func (l *relayLeg) try(req *http.Request, transport http.RoundTripper, remaining int) (*http.Response, error, bool) {
        if remaining == 1 {
                resp, err := transport.RoundTrip(req)
                return resp, err, false
        }
        wait := legAttemptWait
        if deadline, ok := req.Context().Deadline(); ok {
                if budget := time.Until(deadline) / time.Duration(remaining); budget < wait {
                        wait = budget
                }
        }
        ctx, cancel := context.WithCancel(req.Context())
        var expired bool
        timer := time.AfterFunc(wait, func() { expired = true; cancel() })
        resp, err := transport.RoundTrip(req.Clone(ctx))
        timer.Stop()
        if err == nil {
                // Stop the soft deadline without cutting a successful body.
                resp.Body = &cancelOnCloseBody{ReadCloser: resp.Body, cancel: cancel}
                return resp, nil, false
        }
        cancel()
        if resp != nil {
                resp.Body.Close()
        }
        return nil, err, expired
}

// legRetryable lists the errors worth another route.
func legRetryable(err error) bool {
        var timeout net.Error
        var dns *net.DNSError
        if errors.As(err, &dns) {
                return true
        }
        if errors.As(err, &timeout) && timeout.Timeout() {
                return true
        }
        return errors.Is(err, io.EOF) ||
                errors.Is(err, io.ErrUnexpectedEOF) ||
                errors.Is(err, syscall.ECONNRESET) ||
                errors.Is(err, syscall.ECONNABORTED) ||
                errors.Is(err, syscall.ECONNREFUSED) ||
                errors.Is(err, syscall.ENETUNREACH) ||
                errors.Is(err, syscall.EHOSTUNREACH)
}
