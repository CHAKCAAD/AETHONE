package engine

import (
        "encoding/hex"
        "encoding/json"
        "strings"

        "aethone/fxv/internal/dnsresolver"
)

// Login mode values. `webchannel` is the browser-exchange mode (the
// session token captured by the WebChannel bridge); `password` is the
// arman-vpn-client pattern (the owner's round 8): the DIRECT email+
// password sign-in the engine drives itself (FxaLogin → the optional
// emailed code → the OAuth mint). The password travels on the stdin
// pipe ONLY — never argv, never the environment, never a log line
// (deriveAuthPW happens inside the pinned upstream; this process holds
// the raw password only between the read and the first call).
const (
        LoginModeWebChannel = "webchannel"
        LoginModePassword   = "password"
)

// Login-config budget clamps (the phase-2 contract):
// verifyTimeoutMs 0 → 300 000, clamped 1 000–600 000;
// retryDelayMs 0 → 3 000.
const (
        DefaultVerifyTimeoutMs = 300_000
        MinVerifyTimeoutMs     = 1_000
        MaxVerifyTimeoutMs     = 600_000
        DefaultRetryDelayMs    = 3_000
)

// sessionTokenHexLen is the FxA session token length (64 hex chars =
// 32 bytes). The token is validated BEFORE any network byte.
const sessionTokenHexLen = 64

// Password-mode shape clamps (the arman posture): an email is at most
// 254 bytes (RFC 5321's practical ceiling) and must carry exactly one
// @; a password is 1..256 bytes of UTF-8 with no ASCII control
// characters. The bounds exist so a hostile host line can never make
// the engine buffer or echo unbounded material — they mirror what a
// person types into the form, nothing more.
const (
        maxEmailLen    = 254
        maxPasswordLen = 256
)

// LoginConfig is the --login-role stdin line (engine.LoginConfig v1).
// 1.8.0: the password mode fills Email+Password (SessionToken stays
// empty); the webchannel mode is byte-identical to 1.7.0.
type LoginConfig struct {
        Version         int                `json:"version"`
        Mode            string             `json:"mode"`
        SessionToken    string             `json:"sessionToken"`
        Email           string             `json:"email"`
        Password        string             `json:"password"`
        VerifyTimeoutMs int64              `json:"verifyTimeoutMs"`
        RetryDelayMs    int64              `json:"retryDelayMs"`
        DNS             dnsresolver.Config `json:"dns"`
        // UpstreamSocks (1.5.0, the owner's round 2): the OPTIONAL WARP
        // carrier the login screen brought up — the token exchange rides
        // it (the pinned Firefox uTLS ClientHello kept; the Fastly edge
        // sees the WARP egress, not the blocked region's). Empty keeps the
        // direct exchange.
        UpstreamSocks string `json:"upstreamSocks"`
}

// ParseLoginConfig validates the decoded login config. The token is
// checked for exact shape (64 lowercase/uppercase hex) before the
// engine performs any network operation; the password mode checks its
// own fields instead (the arman-pattern direct sign-in).
func ParseLoginConfig(raw []byte) (LoginConfig, error) {
        var cfg LoginConfig
        if err := jsonUnmarshalStrictEnough(raw, &cfg); err != nil {
                return cfg, &ConfigError{Detail: detailConfigNotJSON}
        }
        if cfg.Version != LoginConfigVersion {
                return cfg, &ConfigError{Detail: detailConfigVersionMismatch}
        }
        if cfg.Mode == "" {
                cfg.Mode = LoginModeWebChannel
        }
        switch cfg.Mode {
        case LoginModeWebChannel:
                if !isValidSessionToken(cfg.SessionToken) {
                        return cfg, &ConfigError{Detail: "sessionTokenInvalid"}
                }
        case LoginModePassword:
                if reason := passwordModeProblem(cfg.Email, cfg.Password); reason != "" {
                        return cfg, &ConfigError{Detail: reason}
                }
        default:
                return cfg, &ConfigError{Detail: "loginModeUnsupported"}
        }
        var dnsErr error
        cfg.DNS, dnsErr = cfg.DNS.Validate()
        if dnsErr != nil {
                return cfg, &ConfigError{Detail: detailDNSConfigInvalid}
        }
        if err := validateLoopbackSocksURL(cfg.UpstreamSocks); err != nil {
                return cfg, &ConfigError{Detail: detailUpstreamSocksInvalid}
        }
        if cfg.VerifyTimeoutMs == 0 {
                cfg.VerifyTimeoutMs = DefaultVerifyTimeoutMs
        }
        if cfg.VerifyTimeoutMs < MinVerifyTimeoutMs {
                cfg.VerifyTimeoutMs = MinVerifyTimeoutMs
        }
        if cfg.VerifyTimeoutMs > MaxVerifyTimeoutMs {
                cfg.VerifyTimeoutMs = MaxVerifyTimeoutMs
        }
        if cfg.RetryDelayMs == 0 {
                cfg.RetryDelayMs = DefaultRetryDelayMs
        }
        return cfg, nil
}

// passwordModeProblem validates the direct sign-in's credentials the
// way the form does (arman's email validator is contains-@; the bounds
// are the engine's own honesty). Returns "" when the pair is usable,
// else the static detail code for the failed event (never the values).
func passwordModeProblem(email, password string) string {
        if email != strings.TrimSpace(email) ||
                email == "" || len(email) > maxEmailLen ||
                strings.Count(email, "@") != 1 {
                return "passwordLoginEmailInvalid"
        }
        if password == "" || len(password) > maxPasswordLen {
                return "passwordLoginPasswordInvalid"
        }
        for _, r := range password {
                if r < 0x20 || r == 0x7f {
                        return "passwordLoginPasswordInvalid"
                }
        }
        return ""
}

// isValidSessionToken: exactly 64 hex characters, nothing else. No
// token VALUE is ever echoed by this check's failure path.
func isValidSessionToken(tok string) bool {
        if len(tok) != sessionTokenHexLen {
                return false
        }
        if _, err := hex.DecodeString(strings.ToLower(tok)); err != nil {
                return false
        }
        return true
}

// jsonUnmarshalStrictEnough is encoding/json's Unmarshal with the same
// tolerance the tunnel config has (unknown fields are ignored — the
// host may add fields; the engine's contract is additive).
func jsonUnmarshalStrictEnough(raw []byte, v any) error {
        return json.Unmarshal(raw, v)
}
