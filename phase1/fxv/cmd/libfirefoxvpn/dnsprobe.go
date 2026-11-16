package main

// --dns-probe resolves the Firefox control-plane domains through the
// resolver selected for this Firefox engine process. It does not validate
// Guardian entitlement or VPN data-plane traffic.
//
// 1.8.0 (the owner's round 8 — the arman pattern: everything rides the
// core): the config line gains the SAME upstreamSocks seam the other
// roles have. With a carrier set the probe answers the question that
// actually matters on a blocked network — «can the app's control plane
// reach Mozilla the way it will?»: each domain is dialed THROUGH the
// carrier BY HOSTNAME on :443 (socks5h semantics — remote DNS at the
// WARP egress, exactly the engine's own control-plane posture). Every
// event and the summary carry `via: "carrier"` (a direct probe carries
// `via: "direct"`), so the host can label the evidence honestly.

import (
        "bufio"
        "context"
        "encoding/json"
        "fmt"
        "net"
        "os"
        "strings"
        "time"

        "aethone/fxv/internal/dnsresolver"
        "aethone/fxv/internal/upstream"
)

var dnsProbeDomains = []string{
        "api.accounts.firefox.com",
        "firefox.settings.services.mozilla.com",
        "vpn.mozilla.org",
}

// carrierProbeTimeout bounds ONE through-carrier dial (the tunnel's
// own latency + the remote resolution; the host's 60 s probe budget
// covers all three domains at this bound).
const carrierProbeTimeout = 8 * time.Second

// dnsProbeLookupTimeout bounds ONE domain's direct lookup: the raced
// endpoints each carry their own HTTP budget, and the system fallback
// joins at once once they are known down — the bound is the honest
// ceiling so a wedged resolver can no longer eat the host's whole
// budget and read as "setup failed" with no evidence at all.
const dnsProbeLookupTimeout = 15 * time.Second

type dnsProbeEvent struct {
        Event     string   `json:"event"`
        Domain    string   `json:"domain"`
        Resolver  string   `json:"resolver"`
        Via       string   `json:"via,omitempty"`
        Addresses []string `json:"addresses,omitempty"`
        Error     string   `json:"error,omitempty"`
        ElapsedMs int64    `json:"elapsedMs"`
}

func runDNSProbe() int {
        reader := bufio.NewReader(os.Stdin)
        cfg, err := readWebviewProxyConfigBuffered(reader)
        if err != nil {
                fmt.Fprintf(os.Stderr, "dns-probe: invalid configuration: %v\n", err)
                return 1
        }

        emit := json.NewEncoder(os.Stdout)
        if cfg.UpstreamSocks != "" {
                return runDNSProbeViaCarrier(emit, cfg)
        }

        resolver, err := dnsresolver.Install(cfg.DNS)
        if err != nil {
                fmt.Fprintf(os.Stderr, "dns-probe: DNS setup failed: %v\n", err)
                return 1
        }
        if cfg.DNS.Mode == dnsresolver.ModeSystem {
                resolver = resolverDescription()
        }
        allOK := true
        for _, domain := range dnsProbeDomains {
                started := time.Now()
                ev := dnsProbeEvent{Event: "dnsProbe", Domain: domain, Resolver: resolver, Via: "direct"}
                ips, lookupErr := lookupDomainBounded(domain)
                ev.ElapsedMs = time.Since(started).Milliseconds()
                if lookupErr != nil {
                        ev.Error = lookupErr.Error()
                        allOK = false
                } else {
                        real := make([]string, 0, len(ips))
                        for _, ip := range ips {
                                if dnsresolver.IsBlockPageIP(ip) {
                                        continue
                                }
                                real = append(real, ip.String())
                        }
                        // 2.0.0 — the honest answer: the resolver's last
                        // resort may be the filtering network's own block
                        // page (10.10.34.x and the v6 twin). Presenting
                        // that IP as a successful lookup was a lie the
                        // owner read as "the DNS works" while nothing
                        // connected.
                        if len(real) == 0 {
                                ev.Error = "the network's DNS answer is a filtering block page"
                                for _, ip := range ips {
                                        ev.Addresses = append(ev.Addresses, ip.String())
                                }
                                allOK = false
                        } else {
                                ev.Addresses = real
                        }
                }
                if err := emit.Encode(ev); err != nil {
                        fmt.Fprintf(os.Stderr, "dns-probe: emit failed: %v\n", err)
                        return 1
                }
        }
        if err := emit.Encode(map[string]any{"event": "dnsProbeSummary", "resolver": resolver, "via": "direct", "ok": allOK}); err != nil {
                return 1
        }
        if !allOK {
                return 1
        }
        return 0
}

// runDNSProbeViaCarrier is the through-carrier model: each control-plane
// domain is dialed through the WARP carrier BY HOSTNAME on :443. A
// successful CONNECT proves the name resolved AND the endpoint answered
// remotely — the exact path the login, discovery, usage and tunnel
// control-plane walks take. The local resolver is deliberately NOT
// consulted (that is the point: a poisoned system DNS or a blocked DoH
// endpoint cannot fail this probe), so no addresses are reported.
func runDNSProbeViaCarrier(emit *json.Encoder, cfg webviewProxyConfig) int {
        proxyAddr := strings.TrimPrefix(cfg.UpstreamSocks, "socks5://")
        dialer := &upstream.SOCKS5Dialer{
                ProxyAddr: proxyAddr,
                Dialer:    net.Dialer{Timeout: carrierProbeTimeout},
        }
        resolver := "carrier (remote DNS through " + proxyAddr + ")"
        allOK := true
        for _, domain := range dnsProbeDomains {
                started := time.Now()
                ev := dnsProbeEvent{
                        Event: "dnsProbe", Domain: domain, Resolver: resolver, Via: "carrier",
                }
                ctx, cancel := context.WithTimeout(context.Background(), carrierProbeTimeout)
                conn, dialErr := dialer.DialContext(ctx, "tcp", net.JoinHostPort(domain, "443"))
                if dialErr == nil {
                        _ = conn.Close()
                }
                cancel()
                ev.ElapsedMs = time.Since(started).Milliseconds()
                if dialErr != nil {
                        ev.Error = dialErr.Error()
                        allOK = false
                }
                if err := emit.Encode(ev); err != nil {
                        fmt.Fprintf(os.Stderr, "dns-probe: emit failed: %v\n", err)
                        return 1
                }
        }
        if err := emit.Encode(map[string]any{"event": "dnsProbeSummary", "resolver": resolver, "via": "carrier", "ok": allOK}); err != nil {
                return 1
        }
        if !allOK {
                return 1
        }
        return 0
}

func lookupDomain(domain string) ([]net.IP, error) {
        var out []net.IP
        addrs, err := net.DefaultResolver.LookupIPAddr(context.Background(), domain)
        if err != nil {
                return nil, err
        }
        for _, addr := range addrs {
                out = append(out, addr.IP)
        }
        return out, nil
}

// lookupDomainBounded is lookupDomain under the probe's per-domain
// ceiling — a wedged resolver surfaces as this domain's error event,
// never as a silent stall that eats the whole walk.
func lookupDomainBounded(domain string) ([]net.IP, error) {
        ctx, cancel := context.WithTimeout(context.Background(), dnsProbeLookupTimeout)
        defer cancel()
        type outcome struct {
                ips []net.IP
                err error
        }
        ch := make(chan outcome, 1)
        go func() {
                ips, err := lookupDomain(domain)
                ch <- outcome{ips, err}
        }()
        select {
        case o := <-ch:
                return o.ips, o.err
        case <-ctx.Done():
                return nil, fmt.Errorf("lookup exceeded %s", dnsProbeLookupTimeout)
        }
}

func resolverDescription() string {
        if resolverGoBuildCgoEnabled {
                return "cgo/platform (getaddrinfo)"
        }
        return "pure-Go resolver (NOT the sanctioned Android configuration)"
}
