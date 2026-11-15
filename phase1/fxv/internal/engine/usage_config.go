package engine

import (
	"aethone/fxv/internal/dnsresolver"
)

// UsageConfig is the --usage-role stdin line (engine.UsageConfig v1,
// contract 1.7.0). It carries ONLY the account's access token (never the
// refresh token — the usage read never mints anything), the optional
// Guardian endpoint override, the optional WARP carrier, and the
// process-local DNS policy — the same fields the other pre-connect roles
// take.
type UsageConfig struct {
	Version       int                `json:"version"`
	Auth          AuthConfig         `json:"auth"`
	Guardian      string             `json:"guardian"`
	DNS           dnsresolver.Config `json:"dns"`
	UpstreamSocks string             `json:"upstreamSocks"`
}

// ParseUsageConfig validates the decoded usage config: the access token
// must be present (the vault's pair is checked host-side; an empty token
// is a badConfig, never a network walk), the DNS block and the carrier
// URL follow the same validation as the login role, and the optional
// Guardian override must be an absolute HTTPS URL (the tunnel config's
// own rule).
func ParseUsageConfig(raw []byte) (UsageConfig, error) {
	var cfg UsageConfig
	if err := jsonUnmarshalStrictEnough(raw, &cfg); err != nil {
		return cfg, &ConfigError{Detail: detailConfigNotJSON}
	}
	if cfg.Version != LoginConfigVersion {
		return cfg, &ConfigError{Detail: detailConfigVersionMismatch}
	}
	if cfg.Auth.AccessToken == "" {
		return cfg, &ConfigError{Detail: detailAuthAccessTokenMiss}
	}
	var dnsErr error
	cfg.DNS, dnsErr = cfg.DNS.Validate()
	if dnsErr != nil {
		return cfg, &ConfigError{Detail: detailDNSConfigInvalid}
	}
	if err := validateLoopbackSocksURL(cfg.UpstreamSocks); err != nil {
		return cfg, &ConfigError{Detail: detailUpstreamSocksInvalid}
	}
	if err := validateHTTPSURL(cfg.Guardian); err != nil {
		return cfg, &ConfigError{Detail: detailGuardianNotHTTPS}
	}
	return cfg, nil
}
