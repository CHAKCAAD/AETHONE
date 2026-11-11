package main

// --dns-probe resolves the Firefox control-plane domains through the
// resolver selected for this Firefox engine process. It does not validate
// Guardian entitlement or VPN data-plane traffic.

import (
        "context"
        "encoding/json"
        "fmt"
        "net"
        "os"
        "time"

        "aethone/fxv/internal/dnsresolver"
)

var dnsProbeDomains = []string{
        "api.accounts.firefox.com",
        "firefox.settings.services.mozilla.com",
        "vpn.mozilla.org",
}

type dnsProbeEvent struct {
        Event     string   `json:"event"`
        Domain    string   `json:"domain"`
        Resolver  string   `json:"resolver"`
        Addresses []string `json:"addresses,omitempty"`
        Error     string   `json:"error,omitempty"`
        ElapsedMs int64    `json:"elapsedMs"`
}

func runDNSProbe() int {
        config, err := readOptionalDNSConfig(os.Stdin)
        if err != nil {
                fmt.Fprintf(os.Stderr, "dns-probe: invalid DNS configuration: %v\n", err)
                return 1
        }
        resolver, err := dnsresolver.Install(config)
        if err != nil {
                fmt.Fprintf(os.Stderr, "dns-probe: DNS setup failed: %v\n", err)
                return 1
        }
        if config.Mode == dnsresolver.ModeSystem {
                resolver = resolverDescription()
        }
        emit := json.NewEncoder(os.Stdout)
        allOK := true
        for _, domain := range dnsProbeDomains {
                started := time.Now()
                ev := dnsProbeEvent{Event: "dnsProbe", Domain: domain, Resolver: resolver}
                ips, lookupErr := lookupDomain(domain)
                ev.ElapsedMs = time.Since(started).Milliseconds()
                if lookupErr != nil {
                        ev.Error = lookupErr.Error()
                        allOK = false
                } else {
                        for _, ip := range ips {
                                ev.Addresses = append(ev.Addresses, ip.String())
                        }
                        if len(ev.Addresses) == 0 {
                                ev.Error = "no addresses returned"
                                allOK = false
                        }
                }
                if err := emit.Encode(ev); err != nil {
                        fmt.Fprintf(os.Stderr, "dns-probe: emit failed: %v\n", err)
                        return 1
                }
        }
        if err := emit.Encode(map[string]any{"event":"dnsProbeSummary","resolver":resolver,"ok":allOK}); err != nil {
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

func resolverDescription() string {
        if resolverGoBuildCgoEnabled {
                return "cgo/platform (getaddrinfo)"
        }
        return "pure-Go resolver (NOT the sanctioned Android configuration)"
}
