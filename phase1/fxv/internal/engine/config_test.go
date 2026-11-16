package engine

import (
        "strings"
        "testing"
)

func cfgLine(t *testing.T, json string) Config {
        t.Helper()
        c, err := ReadConfigLine(strings.NewReader(json + "\n"))
        if err != nil {
                t.Fatalf("read: %v", err)
        }
        return c
}

func TestConfigVersionMismatch(t *testing.T) {
        c := cfgLine(t, `{"version":2,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"}}`)
        if _, err := c.Validate(); err == nil {
                t.Fatal("version 2 must be rejected")
        }
}

func TestConfigNotJSON(t *testing.T) {
        if _, err := ReadConfigLine(strings.NewReader("not json\n")); err == nil {
                t.Fatal("non-JSON config must fail")
        }
}

func TestSocksListenNotLoopback(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"0.0.0.0:1822","auth":{"accessToken":"a"}}`)
        _, err := c.Validate()
        if err == nil {
                t.Fatal("0.0.0.0 must be refused")
        }
        if !strings.Contains(err.Error(), detailSocksNotLoopback) {
                t.Fatalf("expected %s, got %v", detailSocksNotLoopback, err)
        }
}

func TestSocksListenLoopbackOK(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"}}`)
        if _, err := c.Validate(); err != nil {
                t.Fatalf("loopback listen must pass: %v", err)
        }
}

func TestGuardianNotHTTPS(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","guardian":"http://vpn.mozilla.org","auth":{"accessToken":"a"}}`)
        _, err := c.Validate()
        if err == nil {
                t.Fatal("http guardian must be refused")
        }
}

func TestGuardianDefault(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"}}`)
        v, err := c.Validate()
        if err != nil {
                t.Fatalf("validate: %v", err)
        }
        if v.Guardian != DefaultGuardian {
                t.Fatalf("guardian default = %q", v.Guardian)
        }
}

func TestTransportUnknown(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","transport":"quic","auth":{"accessToken":"a"}}`)
        if _, err := c.Validate(); err == nil {
                t.Fatal("quic transport must be refused")
        }
}

func TestTransportDefaultH2(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"}}`)
        v, err := c.Validate()
        if err != nil {
                t.Fatalf("validate: %v", err)
        }
        if v.Transport != "h2" {
                t.Fatalf("transport default = %q", v.Transport)
        }
}

func TestAuthAccessTokenMissing(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822"}`)
        _, err := c.Validate()
        if err == nil {
                t.Fatal("missing access token must be refused")
        }
        if !strings.Contains(err.Error(), detailAuthAccessTokenMiss) {
                t.Fatalf("expected %s, got %v", detailAuthAccessTokenMiss, err)
        }
}

func TestDefaultsFilled(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a","refreshToken":"r"}}`)
        v, err := c.Validate()
        if err != nil {
                t.Fatalf("validate: %v", err)
        }
        if v.UpstreamTimeoutMs != DefaultUpstreamMs {
                t.Fatalf("upstream timeout default = %d", v.UpstreamTimeoutMs)
        }
        if v.ExitCheckURL != DefaultExitCheckURL {
                t.Fatalf("exit check default = %q", v.ExitCheckURL)
        }
        if v.LogLevel != "normal" {
                t.Fatalf("log level default = %q", v.LogLevel)
        }
        // Stage 2: an omitted maxConns must fall back to the upstream
        // proxy-demo default (256), never the SOCKS server's 0=unlimited.
        if v.MaxConns != DefaultMaxConns {
                t.Fatalf("max conns default = %d, want %d", v.MaxConns, DefaultMaxConns)
        }
        if v.MaxConns != 256 {
                t.Fatalf("upstream defaultMaxConnections drifted: %d", v.MaxConns)
        }
}

func TestMaxConnsExplicitPreserved(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","maxConns":64,"auth":{"accessToken":"a"}}`)
        v, err := c.Validate()
        if err != nil {
                t.Fatalf("validate: %v", err)
        }
        if v.MaxConns != 64 {
                t.Fatalf("explicit max conns = %d, want 64", v.MaxConns)
        }
}

func TestMaxConnsNegativeRejected(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","maxConns":-1,"auth":{"accessToken":"a"}}`)
        _, err := c.Validate()
        if err == nil {
                t.Fatal("negative max conns must be refused")
        }
        if !strings.Contains(err.Error(), detailMaxConnsNegative) {
                t.Fatalf("expected %s, got %v", detailMaxConnsNegative, err)
        }
}

func TestIPv6LoopbackListen(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"[::1]:1822","auth":{"accessToken":"a"}}`)
        if _, err := c.Validate(); err != nil {
                t.Fatalf("ipv6 loopback listen must pass: %v", err)
        }
}

func TestUpstreamOverrideInvalid(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","upstreamOverride":"no-port-here","auth":{"accessToken":"a"}}`)
        if _, err := c.Validate(); err == nil {
                t.Fatal("a host without a port must be refused")
        }
}

func TestUpstreamSocksLoopbackAccepted(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","upstreamSocks":"socks5://127.0.0.1:1819","auth":{"accessToken":"a"}}`)
        v, err := c.Validate()
        if err != nil {
                t.Fatalf("loopback SOCKS upstream must pass: %v", err)
        }
        if v.UpstreamSocks != "socks5://127.0.0.1:1819" {
                t.Fatalf("upstream SOCKS = %q", v.UpstreamSocks)
        }
}

func TestUpstreamSocksRefusesNonLoopbackAndNonSocks(t *testing.T) {
        for _, value := range []string{
                "socks5://8.8.8.8:1080",
                "http://127.0.0.1:1819",
                "socks5://127.0.0.1",
                "socks5://user:pass@127.0.0.1:1819",
        } {
                c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","upstreamSocks":"`+value+`","auth":{"accessToken":"a"}}`)
                if _, err := c.Validate(); err == nil {
                        t.Fatalf("invalid upstream SOCKS %q must be refused", value)
                }
        }
}

func TestConfigLineBound(t *testing.T) {
        // A config line beyond 1 MiB must fail (never an unbounded read).
        big := strings.Repeat("a", maxConfigLine+10)
        if _, err := ReadConfigLine(strings.NewReader(big)); err == nil {
                t.Fatal("oversized config line must fail")
        }
}

// 2.1.0 — the DNS block is RETIRED from the tunnel config: an old host
// line still carrying `dns` must parse and validate fine (unknown fields
// are ignored), and no resolver policy is read from the line anymore.
func TestConfigDNSBlockRetiredButTolerated(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","dns":{"mode":"doh","provider":"custom","endpoint":"http://dns.example/dns-query"},"auth":{"accessToken":"a"}}`)
        if _, err := c.Validate(); err != nil {
                t.Fatalf("a legacy dns block must be tolerated (ignored), got %v", err)
        }
}

// 1.6.0 — the direct data plane is only meaningful WITH its carrier.
func TestDataPlaneDirectRequiresCarrier(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","dataPlaneDirect":true,"auth":{"accessToken":"a"}}`)
        _, err := c.Validate()
        if err == nil {
                t.Fatal("dataPlaneDirect without upstreamSocks must be refused (a carrier-less config is already fully direct)")
        }
        if !strings.Contains(err.Error(), detailDataPlaneDirectWithoutCarrier) {
                t.Fatalf("expected %s, got %v", detailDataPlaneDirectWithoutCarrier, err)
        }
}

func TestDataPlaneDirectWithCarrierAccepted(t *testing.T) {
        c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","upstreamSocks":"socks5://127.0.0.1:1819","dataPlaneDirect":true,"auth":{"accessToken":"a"}}`)
        v, err := c.Validate()
        if err != nil {
                t.Fatalf("dataPlaneDirect with a loopback carrier must pass: %v", err)
        }
        if !v.DataPlaneDirect {
                t.Fatal("dataPlaneDirect must survive the parse")
        }
        // The flag absent (the 1.5.0 host) keeps the carried data plane.
        legacy := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","upstreamSocks":"socks5://127.0.0.1:1819","auth":{"accessToken":"a"}}`)
        lv, err := legacy.Validate()
        if err != nil {
                t.Fatalf("the carrier-only 1.5.0 config must stay valid: %v", err)
        }
        if lv.DataPlaneDirect {
                t.Fatal("dataPlaneDirect must default to false")
        }
}
