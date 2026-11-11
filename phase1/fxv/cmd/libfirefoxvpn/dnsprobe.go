package main

// The --dns-probe role (the multi-architecture amendment's DNS
// evidence role, 2026-11-09): resolves the Firefox control-plane
// domains THROUGH THIS PROCESS — the same binary, the same child
// process shape the app runs — and reports the real result per domain
// as JSON lines on stdout. NO secrets, NO account data, NO VPN
// traffic: this is the Control-Plane DNS test, deliberately distinct
// from any data-plane validation.
//
// On every ABI the engine build routes name resolution through the
// platform resolver (Android Bionic via CGO; the host build through
// the host resolver), so running THIS role on a device/emulator of a
// given ABI is the honest per-architecture DNS evidence. A run on the
// Linux host proves the mechanism, NOT the Android behavior (recorded
// accordingly).

import (
        "context"
        "encoding/json"
        "fmt"
        "net"
        "os"
        "time"
)

// dnsProbeDomains — the control-plane domains the engine actually
// talks to (FxA token endpoint, RemoteSettings, Guardian).
var dnsProbeDomains = []string{
        "api.accounts.firefox.com",
        "firefox.settings.services.mozilla.com",
        "vpn.mozilla.org",
}

// dnsProbeEvent is one per-domain result (JSON line).
type dnsProbeEvent struct {
        Event      string   `json:"event"`
        Domain     string   `json:"domain"`
        Resolver   string   `json:"resolver"`
        Addresses  []string `json:"addresses,omitempty"`
        Error      string   `json:"error,omitempty"`
        ElapsedMs  int64    `json:"elapsedMs"`
}

func runDNSProbe() int {
        emit := json.NewEncoder(os.Stdout)
        resolver := resolverDescription()
        allOK := true
        for _, domain := range dnsProbeDomains {
                started := time.Now()
                ev := dnsProbeEvent{
                        Event:    "dnsProbe",
                        Domain:   domain,
                        Resolver: resolver,
                }
                ips, err := lookupDomain(domain)
                ev.ElapsedMs = time.Since(started).Milliseconds()
                if err != nil {
                        ev.Error = err.Error()
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
        summary := map[string]any{
                "event":    "dnsProbeSummary",
                "resolver": resolver,
                "ok":       allOK,
        }
        if err := emit.Encode(summary); err != nil {
                return 1
        }
        if !allOK {
                return 1
        }
        return 0
}

// lookupDomain resolves A/AAAA through the process's resolver (the
// platform resolver on CGO builds — Bionic's getaddrinfo on Android).
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

// resolverDescription names the resolver the binary is compiled to
// use (cgo → the platform's getaddrinfo; pure Go → Go's own resolver,
// which on Android is the KNOWN-BROKEN configuration the A1 fix
// exists to eliminate).
func resolverDescription() string {
        if resolverGoBuildCgoEnabled {
                return "cgo/platform (getaddrinfo)"
        }
        return "pure-Go resolver (NOT the sanctioned Android configuration)"
}
