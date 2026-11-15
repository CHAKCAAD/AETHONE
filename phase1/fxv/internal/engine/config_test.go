package engine

import (
	"errors"
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

func TestConfigLineBound(t *testing.T) {
	// A config line beyond 1 MiB must fail (never an unbounded read).
	big := strings.Repeat("a", maxConfigLine+10)
	if _, err := ReadConfigLine(strings.NewReader(big)); err == nil {
		t.Fatal("oversized config line must fail")
	}
}

// ---- 1.4.0-warp: the WARP-carrier config gates ----------------------------

// validLine builds one minimal valid config JSON with the given
// carrier overrides (h2 so the transport/proxy pair never conflicts).
func validLine(api, upstream string) string {
	return `{"version":1,"socksListen":"127.0.0.1:1822","transport":"h2",` +
		`"apiProxy":"` + api + `","upstreamProxy":"` + upstream + `",` +
		`"auth":{"accessToken":"x"}}`
}

func TestCarrierURLsAccepted(t *testing.T) {
	for _, raw := range []string{
		`{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"x"},"apiProxy":"socks5://127.0.0.1:1819"}`,
		validLine("socks5://127.0.0.1:1819", ""),
		validLine("", "socks5h://127.0.0.1:1819"),
		validLine("socks5://127.0.0.1:1819", "socks5://127.0.0.1:1819"),
	} {
		cfg, err := ReadConfigLine(strings.NewReader(raw))
		if err != nil {
			t.Fatalf("ReadConfigLine(%s): %v", raw, err)
		}
		if _, err := cfg.Validate(); err != nil {
			t.Errorf("Validate(%s) = %v, want ok", raw, err)
		}
	}
}

func TestApiProxyInvalid(t *testing.T) {
	for _, api := range []string{
		"http://127.0.0.1:1819",       // wrong scheme
		"socks5://127.0.0.1",          // no port
		"socks5://127.0.0.1:1819/p",   // path
		"socks5://127.0.0.1:1819?x=1", // query
	} {
		cfg, err := ReadConfigLine(strings.NewReader(validLine(api, "")))
		if err != nil {
			t.Fatalf("ReadConfigLine: %v", err)
		}
		_, err = cfg.Validate()
		var cfgErr *ConfigError
		if !errors.As(err, &cfgErr) || cfgErr.DetailCode() != "apiProxyInvalid" {
			t.Errorf("Validate(apiProxy=%q) = %v, want apiProxyInvalid", api, err)
		}
	}
}

func TestUpstreamProxyInvalid(t *testing.T) {
	for _, up := range []string{
		"https://127.0.0.1:1819",
		"socks5://127.0.0.1",
		"127.0.0.1:1819",
	} {
		cfg, err := ReadConfigLine(strings.NewReader(validLine("", up)))
		if err != nil {
			t.Fatalf("ReadConfigLine: %v", err)
		}
		_, err = cfg.Validate()
		var cfgErr *ConfigError
		if !errors.As(err, &cfgErr) || cfgErr.DetailCode() != "upstreamProxyInvalid" {
			t.Errorf("Validate(upstreamProxy=%q) = %v, want upstreamProxyInvalid", up, err)
		}
	}
}

// h3 is QUIC/UDP; the SOCKS5 CONNECT carrier is TCP-only — the pair is
// refused, not silently coerced.
func TestH3OverUpstreamProxyRefused(t *testing.T) {
	raw := `{"version":1,"socksListen":"127.0.0.1:1822","transport":"h3",` +
		`"upstreamProxy":"socks5://127.0.0.1:1819","auth":{"accessToken":"x"}}`
	cfg, err := ReadConfigLine(strings.NewReader(raw))
	if err != nil {
		t.Fatalf("ReadConfigLine: %v", err)
	}
	_, err = cfg.Validate()
	var cfgErr *ConfigError
	if !errors.As(err, &cfgErr) || cfgErr.DetailCode() != "transportUnsupportedOverProxy" {
		t.Errorf("Validate(h3+upstreamProxy) = %v, want transportUnsupportedOverProxy", err)
	}
}

// apiProxy alone (control-plane-only routing) leaves h3 legal — the
// data plane is the UDP-constrained seam, not the control plane.
func TestH3WithApiProxyOnlyAllowed(t *testing.T) {
	raw := `{"version":1,"socksListen":"127.0.0.1:1822","transport":"h3",` +
		`"apiProxy":"socks5://127.0.0.1:1819","auth":{"accessToken":"x"}}`
	cfg, err := ReadConfigLine(strings.NewReader(raw))
	if err != nil {
		t.Fatalf("ReadConfigLine: %v", err)
	}
	if _, err := cfg.Validate(); err != nil {
		t.Errorf("Validate(h3+apiProxy) = %v, want ok", err)
	}
}
