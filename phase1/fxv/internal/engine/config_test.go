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

func TestConfigLineBound(t *testing.T) {
	// A config line beyond 1 MiB must fail (never an unbounded read).
	big := strings.Repeat("a", maxConfigLine+10)
	if _, err := ReadConfigLine(strings.NewReader(big)); err == nil {
		t.Fatal("oversized config line must fail")
	}
}

// ---- guardian-bootstrap Stage 5: the apiProxy leg's validation ----

func TestAPIProxyEmptyIsValid(t *testing.T) {
	// Absent apiProxy = the pre-Stage-5 behavior, byte-identical.
	c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"}}`)
	v, err := c.Validate()
	if err != nil {
		t.Fatalf("empty apiProxy must validate: %v", err)
	}
	if v.ApiProxy != "" {
		t.Fatalf("apiProxy = %q (want empty)", v.ApiProxy)
	}
}

func TestAPIProxyAcceptedLoopbackSchemes(t *testing.T) {
	for _, raw := range []string{
		`socks5://127.0.0.1:1080`,
		`socks5h://127.0.0.1:1080`,
		`http://127.0.0.1:8080`,
		`https://127.0.0.1:8080`,
		`socks5://localhost:1080`,
		`socks5://[::1]:1080`,
	} {
		c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","apiProxy":"`+raw+`","auth":{"accessToken":"a"}}`)
		if _, err := c.Validate(); err != nil {
			t.Fatalf("apiProxy %q must validate: %v", raw, err)
		}
	}
}

func TestAPIProxyRejected(t *testing.T) {
	cases := []struct {
		raw    string
		detail string
	}{
		{`socks5://10.0.0.1:1080`, detailAPIProxyNotLoopback},
		{`http://192.168.1.5:8080`, detailAPIProxyNotLoopback},
		{`socks5://vpn.example.com:1080`, detailAPIProxyNotLoopback},
		{`socks5://user:pass@127.0.0.1:1080`, detailAPIProxyCredentials},
		{`http://token@127.0.0.1:8080`, detailAPIProxyCredentials},
		{`ftp://127.0.0.1:21`, detailAPIProxyBadScheme},
		{`socks4://127.0.0.1:1080`, detailAPIProxyBadScheme},
		{`http://`, detailAPIProxyInvalid},
		{`socks5:`, detailAPIProxyInvalid},
	}
	for _, tc := range cases {
		c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","apiProxy":"`+tc.raw+`","auth":{"accessToken":"a"}}`)
		_, err := c.Validate()
		if err == nil {
			t.Fatalf("apiProxy %q must be rejected", tc.raw)
		}
		if !strings.Contains(err.Error(), tc.detail) {
			t.Fatalf("apiProxy %q: want detail %s, got %v", tc.raw, tc.detail, err)
		}
	}
}
