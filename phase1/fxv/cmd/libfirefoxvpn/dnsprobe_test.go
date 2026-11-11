package main

// The --dns-probe role tests: the resolver identity the binary was
// compiled with, the per-domain JSON shape, and (network-tagged) a real
// resolution through the host resolver — the HOST evidence only (the
// Android per-ABI evidence needs a device/emulator and is honestly
// recorded as such, never inferred from here).

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestDNSProbeResolverIdentity(t *testing.T) {
	// The HOST test binary is pure Go on this build host — the identity
	// must say so honestly (never claim the Android cgo configuration).
	desc := resolverDescription()
	if resolverGoBuildCgoEnabled {
		if desc != "cgo/platform (getaddrinfo)" {
			t.Fatalf("cgo description = %q", desc)
		}
	} else {
		if desc != "pure-Go resolver (NOT the sanctioned Android configuration)" {
			t.Fatalf("pure-go description = %q", desc)
		}
	}
}

func TestDNSProbeRealResolution(t *testing.T) {
	if !networkAvailable() {
		t.Skip("network egress unavailable — the DNS probe cannot resolve here (honest skip, not a green)")
	}
	s := startEngine(t, "--dns-probe")
	defer s.kill()
	// The DNS probe accepts an optional JSON config on stdin. Close the
	// empty pipe explicitly so it observes EOF and selects System DNS;
	// otherwise the child waits forever for input and emits no summary.
	s.closeStdin()
	var summary map[string]any
	deadline := time.After(30 * time.Second)
	sawDomains := 0
	for summary == nil {
		select {
		case ev := <-s.events:
			switch ev["event"] {
			case "dnsProbe":
				sawDomains++
				if ev["domain"] == "" || ev["resolver"] == "" {
					t.Fatalf("probe event shape: %v", ev)
				}
				if errText, _ := ev["error"].(string); errText == "" {
					if _, ok := ev["addresses"]; !ok {
						t.Fatalf("no addresses on success: %v", ev)
					}
				}
			case "dnsProbeSummary":
				summary = ev
			}
		case <-deadline:
			t.Fatal("timeout waiting for the dns probe summary")
		}
	}
	if sawDomains != len(dnsProbeDomains) {
		t.Fatalf("probed %d domains, want %d", sawDomains, len(dnsProbeDomains))
	}
	if ok, _ := summary["ok"].(bool); !ok {
		t.Fatalf("summary not ok: %v", summary)
	}
	if code := s.waitExit(t, 5*time.Second); code != 0 {
		t.Fatalf("exit = %d", code)
	}
}

func TestDNSProbeEventsParseAsJSON(t *testing.T) {
	// The wire shape is JSON lines (the same parser discipline).
	raw := `{"event":"dnsProbe","domain":"example.com","resolver":"x","addresses":["1.2.3.4"],"elapsedMs":5}`
	var ev map[string]any
	if err := json.Unmarshal([]byte(raw), &ev); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if ev["domain"] != "example.com" {
		t.Fatalf("domain = %v", ev["domain"])
	}
}

func TestReadOptionalDNSConfig(t *testing.T) {
	defaultConfig, err := readOptionalDNSConfig(strings.NewReader(""))
	if err != nil || defaultConfig.Mode != "system" {
		t.Fatalf("empty stdin default: %+v, %v", defaultConfig, err)
	}
	doh, err := readOptionalDNSConfig(strings.NewReader(`{"dns":{"mode":"doh","provider":"google"}}`))
	if err != nil || doh.Mode != "doh" || doh.Provider != "google" {
		t.Fatalf("DoH envelope: %+v, %v", doh, err)
	}
	if _, err := readOptionalDNSConfig(strings.NewReader(`{"dns":{"mode":"doh","provider":"custom"}}`)); err == nil {
		t.Fatal("malformed custom DoH config must fail")
	}
}
