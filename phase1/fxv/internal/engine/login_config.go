package engine

import (
        "encoding/hex"
        "encoding/json"
        "strings"

        "aethone/fxv/internal/dnsresolver"
)

// Login mode values. `webchannel` is the only implemented mode; the
// MIT reference's `password` variant is RESERVED and refused (the
// account password must never transit AETHONE code).
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

// LoginConfig is the --login-role stdin line (engine.LoginConfig v1).
type LoginConfig struct {
        Version         int    `json:"version"`
        Mode            string `json:"mode"`
        SessionToken    string `json:"sessionToken"`
        VerifyTimeoutMs int64  `json:"verifyTimeoutMs"`
        RetryDelayMs    int64  `json:"retryDelayMs"`
        DNS             dnsresolver.Config `json:"dns"`
}

// ParseLoginConfig validates the decoded login config. The token is
// checked for exact shape (64 lowercase/uppercase hex) before the
// engine performs any network operation.
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
        if cfg.Mode == LoginModePassword {
                return cfg, &ConfigError{Detail: "loginModeUnsupported"}
        }
        if cfg.Mode != LoginModeWebChannel {
                return cfg, &ConfigError{Detail: "loginModeUnsupported"}
        }
        if !isValidSessionToken(cfg.SessionToken) {
                return cfg, &ConfigError{Detail: "sessionTokenInvalid"}
        }
        var dnsErr error
        cfg.DNS, dnsErr = cfg.DNS.Validate()
        if dnsErr != nil {
                return cfg, &ConfigError{Detail: "dnsConfigInvalid"}
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
