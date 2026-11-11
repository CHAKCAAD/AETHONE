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

func TestRelayBlockValidAndAbsent(t *testing.T) {
	// No relay block at all: the zero value passes (the 1.2.0 behavior).
	c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"}}`)
	v, err := c.Validate()
	if err != nil {
		t.Fatalf("a config without a relay block must pass: %v", err)
	}
	if v.Relay != (RelayConfig{}) {
		t.Fatalf("the absent block must parse to the zero value, got %+v", v.Relay)
	}

	// A full, valid block.
	c = cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"},"relay":{"personal_url":"https://r.example/?secret=s","personal_enabled":true,"shared_enabled":true,"ech_mode":"require","ech_config":"cloudflare-ech.com"}}`)
	if _, err := c.Validate(); err != nil {
		t.Fatalf("a valid relay block must pass: %v", err)
	}
}

func TestRelayBlockURLShape(t *testing.T) {
	for _, bad := range []string{
		`http://r.example/`,              // not https
		`https://u:p@r.example/`,         // credentials
		`https://r.example/#frag`,        // fragment
		`https://r.example/?url=https:x`, // the wire protocol's own parameter
	} {
		c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"},"relay":{"personal_url":"`+bad+`"}}`)
		_, err := c.Validate()
		if err == nil || !strings.Contains(err.Error(), detailRelayURLInvalid) {
			t.Fatalf("%q must be refused as relayURLInvalid, got %v", bad, err)
		}
	}

	// Disabled-but-stored garbage is still refused (a stored address
	// should be a storable one).
	c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"},"relay":{"personal_url":"http://r.example/","personal_enabled":false}}`)
	if _, err := c.Validate(); err == nil || !strings.Contains(err.Error(), detailRelayURLInvalid) {
		t.Fatalf("a disabled garbage URL must still be refused, got %v", err)
	}
}

func TestRelayBlockECH(t *testing.T) {
	c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"},"relay":{"ech_mode":"sometimes"}}`)
	if _, err := c.Validate(); err == nil || !strings.Contains(err.Error(), detailRelayECHModeUnknown) {
		t.Fatalf("an unknown ECH mode must be refused, got %v", err)
	}

	for _, bad := range []string{"bad name", "x:!!!not-base64!!!"} {
		c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"},"relay":{"ech_config":"`+bad+`"}}`)
		if _, err := c.Validate(); err == nil || !strings.Contains(err.Error(), detailRelayECHConfigBad) {
			t.Fatalf("bad ECH config %q must be refused, got %v", bad, err)
		}
	}

	// The three legal shapes pass.
	for _, ok := range []string{"", "cloudflare-ech.com", "cloudflare-ech.com:AAEAAQ=="} {
		c := cfgLine(t, `{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"a"},"relay":{"ech_config":"`+ok+`"}}`)
		if _, err := c.Validate(); err != nil {
			t.Fatalf("ECH config %q must pass, got %v", ok, err)
		}
	}
}
