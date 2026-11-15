package main

// The --dns-probe role tests: the resolver identity the binary was
// compiled with, the per-domain JSON shape, and (network-tagged) a real
// resolution through the host resolver — the HOST evidence only (the
// Android per-ABI evidence needs a device/emulator and is honestly
// recorded as such, never inferred from here).

import (
	"encoding/json"
	"io"
	"net"
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
	// 1.9.0 — the empty default is the reference's AUTO racing posture.
	if err != nil || defaultConfig.Mode != "doh" || defaultConfig.Provider != "auto" {
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

// --- 1.8.0: the through-carrier probe (the arman pattern) ------------------

// fakeCarrierSOCKS accepts SOCKS5 CONNECTs BY HOSTNAME and answers
// success — the evidence that the probe dials the control-plane domains
// through the carrier with REMOTE DNS (socks5h semantics).
func fakeCarrierSOCKS(t *testing.T, conns int) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	ready := make(chan struct{}, 1)
	go func() {
		ready <- struct{}{}
		for i := 0; i < conns; i++ {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go serveOneCarrierConnect(conn)
		}
	}()
	<-ready
	return listener.Addr().String()
}

func serveOneCarrierConnect(conn net.Conn) {
	defer func() { _ = conn.Close() }()
	var greeting [3]byte
	if _, err := io.ReadFull(conn, greeting[:]); err != nil {
		return
	}
	if greeting != [3]byte{5, 1, 0} {
		return
	}
	if _, err := conn.Write([]byte{5, 0}); err != nil {
		return
	}
	var head [4]byte
	if _, err := io.ReadFull(conn, head[:]); err != nil {
		return
	}
	if head[0] != 5 || head[1] != 1 || head[2] != 0 {
		return
	}
	var addr []byte
	switch head[3] {
	case 3: // domain — the REMOTE-DNS dial the carrier must carry
		var n [1]byte
		if _, err := io.ReadFull(conn, n[:]); err != nil {
			return
		}
		addr = make([]byte, int(n[0])+2)
		if _, err := io.ReadFull(conn, addr); err != nil {
			return
		}
	case 1: // IPv4
		addr = make([]byte, 4+2)
		if _, err := io.ReadFull(conn, addr); err != nil {
			return
		}
	default:
		return
	}
	// reply: succeeded, bnd 127.0.0.1:0
	if _, err := conn.Write([]byte{5, 0, 0, 1, 127, 0, 0, 1, 0, 0}); err != nil {
		return
	}
	// hold the connection open until the probe closes it
	buf := make([]byte, 64)
	for {
		if _, err := conn.Read(buf); err != nil {
			return
		}
	}
}

func TestDNSProbeViaCarrier(t *testing.T) {
	addr := fakeCarrierSOCKS(t, len(dnsProbeDomains))
	s := startEngine(t, "--dns-probe")
	defer s.kill()
	s.send(`{"dns":{"mode":"system"},"upstreamSocks":"socks5://` + addr + `"}`)
	s.closeStdin()
	var summary map[string]any
	sawDomains := 0
	deadline := time.After(30 * time.Second)
	for summary == nil {
		select {
		case ev := <-s.events:
			switch ev["event"] {
			case "dnsProbe":
				sawDomains++
				if ev["via"] != "carrier" {
					t.Fatalf("via = %v, want carrier", ev["via"])
				}
				if ev["resolver"] == "" || ev["domain"] == "" {
					t.Fatalf("probe event shape: %v", ev)
				}
				if errText, _ := ev["error"].(string); errText != "" {
					t.Fatalf("carrier probe error: %v", ev)
				}
			case "dnsProbeSummary":
				summary = ev
			}
		case <-deadline:
			t.Fatal("timeout waiting for the carrier probe summary")
		}
	}
	if sawDomains != len(dnsProbeDomains) {
		t.Fatalf("probed %d domains, want %d", sawDomains, len(dnsProbeDomains))
	}
	if summary["via"] != "carrier" {
		t.Fatalf("summary via = %v", summary["via"])
	}
	if ok, _ := summary["ok"].(bool); !ok {
		t.Fatalf("summary not ok: %v", summary)
	}
	if code := s.waitExit(t, 5*time.Second); code != 0 {
		t.Fatalf("exit = %d", code)
	}
}

func TestDNSProbeCarrierConfigGates(t *testing.T) {
	// The carrier seam enforces the same loopback socks5:// shape the
	// webview-proxy role does (the shared reader's gate).
	for _, line := range []string{
		`{"dns":{"mode":"system"},"upstreamSocks":"socks5://10.0.0.5:1080"}`,
		`{"dns":{"mode":"system"},"upstreamSocks":"http://127.0.0.1:1819"}`,
		`{"dns":{"mode":"system"},"upstreamSocks":"socks5://127.0.0.1"}`,
	} {
		s := startEngine(t, "--dns-probe")
		s.send(line)
		s.closeStdin()
		// The role exits 1 on the invalid configuration BEFORE any
		// probe (stderr carries the reason; no summary is emitted).
		if code := s.waitExit(t, 10*time.Second); code != 1 {
			t.Fatalf("line %q: exit = %d, want 1", line, code)
		}
	}
}
