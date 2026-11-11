package engine

import (
	"bufio"
	"encoding/json"
	"io"
	"net"
	"net/url"
	"strings"
)

// maxConfigLine bounds the single stdin JSON line (1 MiB, the phase-1
// contract). The buffer carrying the tokens is dropped after the parse.
const maxConfigLine = 1 << 20

// AuthConfig is the same-account OAuth pair (the only secret carrier on
// the wire — stdin).
type AuthConfig struct {
	AccessToken  string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
	ExpiresAt    string `json:"expiresAt,omitempty"`
}

// Config is the tunnel-role stdin line (engine.Config v1). Zero-valued
// optional durations fall back to the upstream defaults.
type Config struct {
	Version            int        `json:"version"`
	SocksListen        string     `json:"socksListen"`
	Guardian           string     `json:"guardian"`
	Country            string     `json:"country"`
	Transport          string     `json:"transport"`
	UpstreamOverride   string     `json:"upstreamOverride"`
	UpstreamTimeoutMs  int64      `json:"upstreamTimeoutMs"`
	HandshakeTimeoutMs int64      `json:"handshakeTimeoutMs"`
	IdleTimeoutMs      int64      `json:"idleTimeoutMs"`
	MaxConns           int        `json:"maxConns"`
	ExitCheckURL       string     `json:"exitCheckUrl"`
	ExitTimeoutMs      int64      `json:"exitTimeoutMs"`
	LogLevel           string     `json:"logLevel"`
	Auth               AuthConfig `json:"auth"`

	// cfgLine is the raw buffer reference, dropped (nil-ed) after the
	// parse so the tokens do not linger in a second copy.
	cfgLine []byte `json:"-"`
}

// Defaults for the optional fields (the upstream proxy-demo values).
const (
	DefaultSocksListen   = "127.0.0.1:1822"
	DefaultGuardian      = "https://vpn.mozilla.org"
	DefaultUpstreamMs    = 20_000
	DefaultHandshakeMs   = 10_000
	DefaultExitCheckURL  = "https://www.cloudflare.com/cdn-cgi/trace"
	DefaultExitTimeoutMs = 10_000

	// DefaultMaxConns restores the upstream proxy-demo's
	// defaultMaxConnections (256). Stage 2 of the performance
	// mission found the adaptation had DROPPED it: a zero value
	// reached the SOCKS server, whose contract reads <= 0 as
	// UNLIMITED — every device flow then opened an h2 stream on the
	// single upstream ClientConn with no ceiling, and x/net/http2
	// blocks new streams indefinitely once the server's
	// SETTINGS_MAX_CONCURRENT_STREAMS is reached
	// (awaitOpenSlotForStreamLocked) — the mechanism behind the
	// 200ms→8000ms ping creep. 256 is the upstream author's own
	// shipped default, not a tuned guess; the host can still send
	// an explicit maxConns to override.
	DefaultMaxConns = 256
)

// ReadConfigLine reads exactly ONE JSON line from r (bounded by
// maxConfigLine) and parses it. The raw line buffer is dropped after the
// parse.
func ReadConfigLine(r io.Reader) (Config, error) {
	br := bufio.NewReader(io.LimitReader(r, maxConfigLine+1))
	line, err := br.ReadString('\n')
	if err != nil && err != io.EOF {
		return Config{}, &ConfigError{Detail: detailConfigNotJSON}
	}
	line = strings.TrimRight(line, "\r\n")
	if line == "" {
		return Config{}, &ConfigError{Detail: detailConfigNotJSON}
	}
	var cfg Config
	if err := json.Unmarshal([]byte(line), &cfg); err != nil {
		return Config{}, &ConfigError{Detail: detailConfigNotJSON}
	}
	cfg.cfgLine = nil // the token-carrying buffer is dropped
	return cfg, nil
}

// Validate applies the phase-1 rules and fills the defaults. It NEVER
// inspects or echoes the token values (only presence).
func (c Config) Validate() (Config, error) {
	if c.Version != ConfigVersion {
		return c, &ConfigError{Detail: detailConfigVersionMismatch}
	}
	if c.SocksListen == "" {
		c.SocksListen = DefaultSocksListen
	}
	if !isLoopbackListen(c.SocksListen) {
		return c, &ConfigError{Detail: detailSocksNotLoopback}
	}
	if c.Guardian == "" {
		c.Guardian = DefaultGuardian
	}
	if u, err := url.Parse(c.Guardian); err != nil || u.Scheme != "https" || u.Host == "" {
		return c, &ConfigError{Detail: detailGuardianNotHTTPS}
	}
	if c.Transport == "" {
		c.Transport = "h2"
	}
	if c.Transport != "h2" && c.Transport != "h3" {
		return c, &ConfigError{Detail: detailTransportUnknown}
	}
	if c.UpstreamOverride != "" {
		if _, _, err := net.SplitHostPort(c.UpstreamOverride); err != nil {
			return c, &ConfigError{Detail: detailUpstreamOverrideBad}
		}
	}
	if strings.TrimSpace(c.Auth.AccessToken) == "" {
		return c, &ConfigError{Detail: detailAuthAccessTokenMiss}
	}
	if c.UpstreamTimeoutMs == 0 {
		c.UpstreamTimeoutMs = DefaultUpstreamMs
	}
	if c.HandshakeTimeoutMs == 0 {
		c.HandshakeTimeoutMs = DefaultHandshakeMs
	}
	if c.MaxConns == 0 {
		c.MaxConns = DefaultMaxConns
	}
	if c.MaxConns < 0 {
		return c, &ConfigError{Detail: detailMaxConnsNegative}
	}
	if c.ExitCheckURL == "" {
		c.ExitCheckURL = DefaultExitCheckURL
	}
	if c.ExitTimeoutMs == 0 {
		c.ExitTimeoutMs = DefaultExitTimeoutMs
	}
	if c.LogLevel == "" {
		c.LogLevel = "normal"
	}
	return c, nil
}

// isLoopbackListen reports whether host:port binds a loopback address
// ONLY (the engine refuses anything reachable from the network).
func isLoopbackListen(addr string) bool {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return false
	}
	if host == "" {
		return false
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
