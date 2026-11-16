package engine

// UsageConfig is the --usage-role stdin line (engine.UsageConfig v1,
// contract 1.7.0). It carries ONLY the account's access token (never the
// refresh token — the usage read never mints anything), the optional
// Guardian endpoint override, and the optional WARP carrier — the same
// fields the other pre-connect roles take. 2.1.0: the DNS block is gone
// from the contract (the platform resolver carries every role); an old
// host line still carrying `dns` parses fine (unknown fields are
// ignored).
type UsageConfig struct {
        Version       int        `json:"version"`
        Auth          AuthConfig `json:"auth"`
        Guardian      string     `json:"guardian"`
        UpstreamSocks string     `json:"upstreamSocks"`
}

// ParseUsageConfig validates the decoded usage config: the access token
// must be present (the vault's pair is checked host-side; an empty token
// is a badConfig, never a network walk), the carrier URL follows the same
// validation as the login role, and the optional Guardian override must
// be an absolute HTTPS URL (the tunnel config's own rule).
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
        if err := validateLoopbackSocksURL(cfg.UpstreamSocks); err != nil {
                return cfg, &ConfigError{Detail: detailUpstreamSocksInvalid}
        }
        if err := validateHTTPSURL(cfg.Guardian); err != nil {
                return cfg, &ConfigError{Detail: detailGuardianNotHTTPS}
        }
        return cfg, nil
}
