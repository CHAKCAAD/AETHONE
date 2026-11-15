package main

import (
	"bufio"
	"strings"
	"testing"
)

func br(line string) *bufio.Reader {
	return bufio.NewReader(strings.NewReader(line + "\n"))
}

// TestWebViewProxyConfigLine (1.5.0, the owner's round 2) — the
// --webview-proxy stdin line: the dns block alone (the historical
// shape), the dns + upstreamSocks pair, and the carrier gates
// (non-loopback, wrong scheme, userinfo, path — all refused).
func TestWebViewProxyConfigLine(t *testing.T) {
	t.Run("dns only keeps the historical shape", func(t *testing.T) {
		cfg, err := readWebviewProxyConfigBuffered(br(
			`{"dns":{"mode":"doh","provider":"cloudflare"}}`))
		if err != nil {
			t.Fatalf("dns-only line must parse: %v", err)
		}
		if cfg.DNS.Mode != "doh" || cfg.UpstreamSocks != "" {
			t.Fatalf("cfg = %+v", cfg)
		}
	})

	t.Run("empty line is the auto racing default + direct dial", func(t *testing.T) {
		cfg, err := readWebviewProxyConfigBuffered(br(""))
		if err != nil {
			t.Fatalf("empty line must parse: %v", err)
		}
		// 1.9.0 — the empty default is the reference's AUTO racing
		// posture, never the poisonable system one.
		if cfg.DNS.Mode != "doh" || cfg.DNS.Provider != "auto" || cfg.UpstreamSocks != "" {
			t.Fatalf("cfg = %+v", cfg)
		}
	})

	t.Run("the carrier rides along", func(t *testing.T) {
		cfg, err := readWebviewProxyConfigBuffered(br(
			`{"dns":{"mode":"system"},"upstreamSocks":"socks5://127.0.0.1:1819"}`))
		if err != nil {
			t.Fatalf("carrier line must parse: %v", err)
		}
		if cfg.UpstreamSocks != "socks5://127.0.0.1:1819" {
			t.Fatalf("carrier = %q", cfg.UpstreamSocks)
		}
	})

	for name, line := range map[string]string{
		"non-loopback host": `{"upstreamSocks":"socks5://10.0.0.5:1080"}`,
		"wrong scheme":      `{"upstreamSocks":"http://127.0.0.1:1819"}`,
		"userinfo":          `{"upstreamSocks":"socks5://u:p@127.0.0.1:1819"}`,
		"path":              `{"upstreamSocks":"socks5://127.0.0.1:1819/x"}`,
		"no port":           `{"upstreamSocks":"socks5://127.0.0.1"}`,
		"garbage dns mode":  `{"dns":{"mode":"magic"}}`,
		"not json":          `nonsense`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := readWebviewProxyConfigBuffered(br(line)); err == nil {
				t.Fatalf("%s must be refused", line)
			}
		})
	}
}
