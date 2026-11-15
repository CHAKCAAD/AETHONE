package dnsresolver

import (
        "bytes"
        "context"
        "crypto/tls"
        "fmt"
        "io"
        "net"
        "net/http"
        "net/url"
        "strings"
        "time"
)

const (
        defaultRequestTimeout = 8 * time.Second
        maxDNSMessageBytes    = 65535

        // systemAfter is how long the DoH servers have alone before the
        // system resolver is asked too (the reference's rule,
        // arman-vpn-client internal/resolver): where a network blocks
        // them they never answer, and its own DNS answers at once.
        systemAfter = time.Second
)

// Install applies a process-local resolver. Call it before starting any
// Firefox network operation. System mode deliberately leaves the original
// Bionic/host resolver untouched.
//
// 1.9.0 — the reference's racing posture: every configured DoH endpoint
// (the AUTO provider's three, or the one picked provider) is queried at
// once, the first answer that survives the block-page filter wins, and
// the system resolver joins the race after [systemAfter] — or at once
// when every endpoint has errored. A filtering network must block ALL
// of the endpoints AND answer its own DNS with real addresses to keep
// the names from resolving.
func Install(raw Config) (string, error) {
        cfg, err := raw.Validate()
        if err != nil {
                return "", err
        }
        if cfg.Mode == ModeSystem {
                return "android/system resolver (Bionic getaddrinfo)", nil
        }

        systemResolver := net.DefaultResolver
        endpoints := cfg.DoHEndpoints()
        targets := make([]dohTarget, 0, len(endpoints))
        for _, endpoint := range endpoints {
                client, err := newDoHHTTPClient(endpoint, cfg, systemResolver)
                if err != nil {
                        return "", err
                }
                targets = append(targets, dohTarget{endpoint: endpoint, client: client})
        }
        if len(targets) == 0 {
                return "", fmt.Errorf("DoH mode resolved to no endpoints")
        }
        exchange := &dohExchange{
                cfg:            cfg,
                targets:        targets,
                systemResolver: systemResolver,
                cache:          newDNSCache(256),
        }
        net.DefaultResolver = &net.Resolver{
                PreferGo:     true,
                StrictErrors: false,
                Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
                        if strings.HasPrefix(network, "udp") {
                                return newDoHPacketConn(ctx, exchange), nil
                        }
                        return newDoHStreamConn(ctx, exchange), nil
                },
        }
        if cfg.Provider == ProviderAuto {
                return "DoH auto (cloudflare+google+quad9 raced, system fallback)", nil
        }
        return fmt.Sprintf("DoH (%s)", cfg.Provider), nil
}

// newDoHHTTPClient builds the HTTP client for ONE DoH endpoint: an
// IP-literal endpoint dials its IP directly (no bootstrap lookup, no
// resolver dependency — a hostname endpoint's bootstrap would be answered
// by the poisoner on a DNS-poisoned network), and a hostname endpoint
// dials its configured bootstrap IPs, falling back to the system
// resolver's answers for it.
func newDoHHTTPClient(endpoint string, cfg Config, systemResolver *net.Resolver) (*http.Client, error) {
        parsed, err := url.Parse(endpoint)
        if err != nil {
                return nil, err
        }
        bootstrap := make([]net.IP, 0, len(cfg.BootstrapIPs))
        for _, raw := range cfg.BootstrapIPs {
                bootstrap = append(bootstrap, net.ParseIP(raw))
        }
        dialer := &net.Dialer{Timeout: defaultRequestTimeout, KeepAlive: 30 * time.Second}
        transport := &http.Transport{
                Proxy: nil, // environment/system proxies must not silently change DNS routing
                TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12},
                ForceAttemptHTTP2: true,
                MaxIdleConns: 4,
                MaxIdleConnsPerHost: 2,
                IdleConnTimeout: 30 * time.Second,
                DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
                        host, port, splitErr := net.SplitHostPort(address)
                        if splitErr != nil {
                                return nil, splitErr
                        }
                        // 1.7.0 — an IP-LITERAL endpoint dials straight
                        // to that IP: no bootstrap lookup, no resolver
                        // dependency (the whole point of the provider
                        // defaults being IPs — a hostname endpoint's
                        // bootstrap would be answered by the poisoner on
                        // a DNS-poisoned network).
                        if endpointIP := net.ParseIP(host); endpointIP != nil {
                                return dialer.DialContext(ctx, network, net.JoinHostPort(endpointIP.String(), port))
                        }
                        if !strings.EqualFold(host, parsed.Hostname()) {
                                return dialer.DialContext(ctx, network, address)
                        }
                        ips := bootstrap
                        if len(ips) == 0 {
                                resolved, resolveErr := systemResolver.LookupIPAddr(ctx, host)
                                if resolveErr != nil {
                                        return nil, fmt.Errorf("resolve DoH endpoint using Android system DNS: %w", resolveErr)
                                }
                                ips = make([]net.IP, 0, len(resolved))
                                for _, item := range resolved {
                                        ips = append(ips, item.IP)
                                }
                        }
                        if len(ips) == 0 {
                                return nil, fmt.Errorf("DoH endpoint has no bootstrap addresses")
                        }
                        var lastErr error
                        for _, ip := range ips {
                                conn, dialErr := dialer.DialContext(ctx, "tcp", net.JoinHostPort(ip.String(), port))
                                if dialErr == nil {
                                        // net/http still validates TLS against the hostname in
                                        // the request URL; only the TCP destination is pinned.
                                        return conn, nil
                                }
                                lastErr = dialErr
                        }
                        if lastErr == nil {
                                lastErr = fmt.Errorf("no usable DoH bootstrap address")
                        }
                        return nil, lastErr
                },
        }
        return &http.Client{
                Transport: transport,
                Timeout: defaultRequestTimeout,
                CheckRedirect: func(*http.Request, []*http.Request) error {
                        return http.ErrUseLastResponse
                },
        }, nil
}

// dohTarget is one racing DoH endpoint with its own pinned client.
type dohTarget struct {
        endpoint string
        client   *http.Client
}

type dohExchange struct {
        cfg            Config
        targets        []dohTarget
        systemResolver *net.Resolver
        cache          *dnsCache
}

func (d *dohExchange) exchange(ctx context.Context, query []byte) ([]byte, error) {
        if len(query) < 12 || len(query) > maxDNSMessageBytes {
                return nil, fmt.Errorf("invalid DNS query message length")
        }
        if cached, ok := d.cache.get(query); ok {
                return cached, nil
        }
        question, _, err := parseDNSQuestion(query)
        if err != nil {
                return nil, err
        }
        if d.cfg.UsesSystemDNS(question.name) {
                return buildSystemResponse(ctx, query, question, d.systemResolver)
        }
        response, err := d.race(ctx, query, question)
        if err != nil {
                return nil, err
        }
        d.cache.put(query, response)
        return response, nil
}

// race is the reference's lookupWithSystem state machine (arman-vpn-client,
// internal/resolver), adapted to the wire-message seam:
//
//   - the endpoints' race (the first answer that survives the block-page
//     filter) wins whenever it succeeds — however slow;
//   - the system joins after [systemAfter] (or at once, once the
//     endpoints' race has failed) and its answer wins when it is real;
//   - a system BLOCK PAGE is held as the last resort: it is returned
//     only when the endpoints' race then fails (on a filtering network
//     only they can give the real address);
//   - a system failure (NXDOMAIN and the like) is ignored while the
//     endpoints are still racing.
func (d *dohExchange) race(ctx context.Context, query []byte, question dnsQuestion) ([]byte, error) {
        type sysAnswer struct {
                response []byte
                poisoned bool
                err      error
        }
        serversCh := make(chan serverOutcome, 1)
        go func() {
                response, err := d.raceEndpoints(ctx, query, question)
                serversCh <- serverOutcome{response: response, err: err}
        }()

        timer := time.NewTimer(systemAfter)
        defer timer.Stop()
        systemCh := make(chan sysAnswer, 1)
        asked := false
        askSystem := func() {
                if asked {
                        return
                }
                asked = true
                go func() {
                        response, poisoned, err := systemLookupResponse(ctx, query, question, d.systemResolver)
                        systemCh <- sysAnswer{response: response, poisoned: poisoned, err: err}
                }()
        }

        var serversErr error
        var blockPage []byte
        systemDone := false
        for {
                select {
                case a := <-serversCh:
                        serversCh = nil
                        if a.err == nil {
                                return a.response, nil
                        }
                        serversErr = a.err
                        if blockPage != nil {
                                return blockPage, nil
                        }
                        if systemDone {
                                return nil, serversErr
                        }
                        askSystem() // the servers are known failing: no wait
                case <-timer.C:
                        askSystem()
                case a := <-systemCh:
                        systemDone = true
                        if a.err != nil {
                                if serversErr != nil {
                                        return nil, serversErr
                                }
                                continue // a system failure never cancels the servers' race
                        }
                        if !a.poisoned {
                                return a.response, nil
                        }
                        if serversErr != nil {
                                return a.response, nil // best effort: everyone else failed
                        }
                        blockPage = a.response
                case <-ctx.Done():
                        if serversErr != nil {
                                return nil, serversErr
                        }
                        return nil, ctx.Err()
                }
        }
}

// serverOutcome is the endpoints' race terminal outcome.
type serverOutcome struct {
        response []byte
        err      error
}

// raceEndpoints queries every DoH endpoint at once; the first answer
// that survives the block-page filter wins (the reference's raceWith),
// and only when EVERY endpoint has failed does the race fail.
func (d *dohExchange) raceEndpoints(ctx context.Context, query []byte, question dnsQuestion) ([]byte, error) {
        type answer struct {
                response []byte
                err      error
        }
        answers := make(chan answer, len(d.targets))
        for i := range d.targets {
                target := d.targets[i]
                go func() {
                        response, err := d.queryDoH(ctx, target, query)
                        if err != nil {
                                answers <- answer{err: err}
                                return
                        }
                        filtered, usable, err := filterBlockPageAnswers(query, question, response)
                        if err != nil {
                                answers <- answer{err: err}
                                return
                        }
                        if !usable {
                                answers <- answer{err: fmt.Errorf("%s answered a filtering block page", target.endpoint)}
                                return
                        }
                        answers <- answer{response: filtered}
                }()
        }
        var lastErr error
        for i := 0; i < len(d.targets); i++ {
                a := <-answers
                if a.err == nil {
                        return a.response, nil
                }
                lastErr = a.err
        }
        if lastErr == nil {
                lastErr = fmt.Errorf("no DoH endpoints configured")
        }
        return nil, lastErr
}

// queryDoH sends ONE RFC 8484 POST to ONE endpoint and returns its raw
// DNS message (the transaction ID forced back to the query's).
func (d *dohExchange) queryDoH(ctx context.Context, target dohTarget, query []byte) ([]byte, error) {
        req, err := http.NewRequestWithContext(ctx, http.MethodPost, target.endpoint, bytes.NewReader(query))
        if err != nil {
                return nil, err
        }
        req.Header.Set("Content-Type", "application/dns-message")
        req.Header.Set("Accept", "application/dns-message")
        req.Header.Set("User-Agent", "AETHONE-Firefox-DNS/1")
        resp, err := target.client.Do(req)
        if err != nil {
                return nil, err
        }
        defer resp.Body.Close()
        if resp.StatusCode != http.StatusOK {
                return nil, fmt.Errorf("DoH server returned HTTP %d", resp.StatusCode)
        }
        response, err := io.ReadAll(io.LimitReader(resp.Body, maxDNSMessageBytes+1))
        if err != nil {
                return nil, err
        }
        if len(response) < 12 || len(response) > maxDNSMessageBytes {
                return nil, fmt.Errorf("DoH server returned a malformed or oversized DNS message")
        }
        response[0], response[1] = query[0], query[1]
        return response, nil
}
