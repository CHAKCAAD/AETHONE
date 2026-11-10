// Package engine — the AETHONE wire contract for the Firefox VPN engine
// (libfirefoxvpn). This package is NEW AETHONE code (Phase 1, rebuilt
// 2026-11-09); it defines and versions the child-process contract the
// Dart host speaks:
//
//      stdin  — exactly ONE JSON line (Config for the tunnel role,
//               LoginConfig for the --login role); closing stdin is the
//               shutdown / cancel request.
//      stdout — JSON-lines status events (Event), flushed per event.
//      stderr — human-readable, level-tagged, REDACTED logs
//               (internal/redact scrubs the token set).
//
// The JSON field names are the frozen 1.1.0-phase2 names the Dart parser
// (lib/connection/firefox/firefox_protocol.dart) reads; Phase B
// (1.2.0-phaseb) extends the `failed` event ADDITIVELY with the optional
// httpStatus / retryable fields and the granular fferr failCode classes.
// Nothing existing is ever renamed or removed.
package engine

import (
        "encoding/json"
        "fmt"
        "os"
        "sync"
)

// ConfigVersion is the tunnel-role config version (must equal 1).
const ConfigVersion = 1

// LoginConfigVersion is the --login-role config version (must equal 1).
const LoginConfigVersion = 1

// EngineVersion is reported in the `started` and `loginStarted` events.
// 1.1.0 — the additive `--login` role on the 1.0.0 tunnel contract.
// 1.2.0 — Phase B: the classified `failed` event (granular failCode
//
//      classes + optional httpStatus / retryable) and the OAuth pair
//      guard. Additive only; the 1.1.0 field names stay valid forever.
const EngineVersion = "1.2.0-phaseb"

// Event names (mirrored by FirefoxEngineEvents on the Dart side).
const (
        EvStarted          = "started"
        EvDiscoveryFetched = "discoveryFetched"
        EvSelected         = "selected"
        EvPassAcquired     = "passAcquired"
        EvRenewed          = "renewed"
        EvUpstreamReady    = "upstreamReady"
        EvSocksReady       = "socksReady"
        EvExitVerified     = "exitVerified"
        EvExitVerifyFailed = "exitVerifyFailed"
        EvAuthRefreshed    = "authRefreshed"
        EvRenewalFailed    = "renewalFailed"
        EvQuotaExhausted   = "quotaExhausted"
        EvLoginStarted     = "loginStarted"
        EvLoginRetry       = "loginRetry"
        EvLoginCompleted   = "loginCompleted"
        EvStopping         = "stopping"
        EvStopped          = "stopped"
        EvFailed           = "failed"
        EvLog              = "log"
)

// Failure codes (mirrored by FirefoxEngineFailure on the Dart side).
const (
        ErrBadConfig           = "badConfig"
        ErrDiscoveryFailed     = "discoveryFailed"
        ErrNoMatchForCountry   = "noMatchForCountry"
        ErrPassFetchFailed     = "passFetchFailed"
        ErrQuotaExhausted      = "quotaExhausted"
        ErrUpstreamSession     = "upstreamSessionFailed"
        ErrSocksListenFailed   = "socksListenFailed"
        ErrRenewalTimeout      = "renewalTimeout"
        ErrInternal            = "internalError"
        ErrLoginModeUnsupported = "loginModeUnsupported"
        ErrSessionTokenInvalid = "sessionTokenInvalid"
        ErrSessionRejected     = "sessionRejected"
        ErrLoginTimeout        = "loginTimeout"
        ErrExchangeFailed      = "exchangeFailed"
)

// Exit codes (mirrored by FirefoxEngineExitCode on the Dart side).
const (
        ExitClean    = 0 // stdin closed / drained
        ExitStartup  = 1 // startup or config failure
        ExitQuota    = 2 // quota exhausted
        ExitRenewal  = 3 // renewal timeout (session dead, host decides)
        ExitInternal = 4 // internal error
)

// Config validation failure detail codes (the failCode stays badConfig;
// the detail rides the message — static English, never secrets).
const (
        detailConfigVersionMismatch = "configVersionMismatch"
        detailSocksNotLoopback      = "socksListenNotLoopback"
        detailGuardianNotHTTPS      = "guardianNotHttps"
        detailTransportUnknown      = "transportUnknown"
        detailAuthAccessTokenMiss   = "authAccessTokenMissing"
        detailConfigNotJSON         = "configNotJSON"
        detailUpstreamOverrideBad   = "upstreamOverrideInvalid"
        detailMaxConnsNegative      = "maxConnsNegative"

        // guardian-bootstrap Stage 5 — the optional apiProxy leg's
        // validation details (badConfig rides the failCode as usual).
        detailAPIProxyInvalid     = "apiProxyInvalid"
        detailAPIProxyBadScheme   = "apiProxySchemeUnsupported"
        detailAPIProxyNotLoopback = "apiProxyNotLoopback"
        detailAPIProxyCredentials = "apiProxyCredentialsForbidden"
)

// Event is one stdout JSON line. Only authRefreshed and loginCompleted
// ever carry secret material (the same-account OAuth pair) — the host
// routes both straight into its Keystore vault.
type Event struct {
        Name    string `json:"event"`
        Message string `json:"message,omitempty"`

        // failed (the engine/legacy codes or the fferr classes) and
        // renewalFailed (the failed attempt's fferr class — the 451
        // region class included; empty when it classifies as unknown)
        FailCode   string `json:"failCode,omitempty"`
        Code       int    `json:"code,omitempty"` // the exit code the engine will use
        HTTPStatus int    `json:"httpStatus,omitempty"`
        Retryable  *bool  `json:"retryable,omitempty"`

        // stopping / stopped
        Reason string `json:"reason,omitempty"`

        // started (pid), socksReady
        Addr string `json:"addr,omitempty"`
        PID  int    `json:"pid,omitempty"`

        // upstreamReady
        Transport string `json:"transport,omitempty"`
        ProxyHost string `json:"proxyHost,omitempty"`
        LatencyMs int64  `json:"latencyMs,omitempty"`

        // discoveryFetched
        Countries   []string `json:"countries,omitempty"`
        DiscoveryMs int64    `json:"discoveryMs,omitempty"`

        // selected
        Country          string `json:"country,omitempty"`
        CountryName      string `json:"countryName,omitempty"`
        CityCode         string `json:"cityCode,omitempty"`
        CityName         string `json:"cityName,omitempty"`
        Hostname         string `json:"hostname,omitempty"`
        Port             int    `json:"port,omitempty"`
        SelectionSource  string `json:"selectionSource,omitempty"`
        Recommended      bool   `json:"recommended"`

        // passAcquired / renewed / quotaExhausted
        PassExpiresAt string `json:"passExpiresAt,omitempty"`
        QuotaLeft     string `json:"quotaLeft,omitempty"`
        QuotaReset    string `json:"quotaReset,omitempty"`

        // exitVerified / exitVerifyFailed
        ExitIP             string `json:"exitIp,omitempty"`
        ExitCountry        string `json:"exitCountry,omitempty"`
        ConfiguredCountry  string `json:"configuredCountry,omitempty"`
        ExitCountryMatches *bool  `json:"exitCountryMatches,omitempty"`

        // renewalFailed / loginRetry
        RetryInMs int64 `json:"retryInMs,omitempty"`
        Attempt   int   `json:"attempt,omitempty"`

        // log
        Line string `json:"line,omitempty"`

        // loginStarted
        LoginMode string `json:"loginMode,omitempty"`

        // authRefreshed / loginCompleted (SECRET — never logged)
        AccessToken  string `json:"accessToken,omitempty"`
        RefreshToken string `json:"refreshToken,omitempty"`
        ExpiresIn    int    `json:"expiresIn,omitempty"`
        ObtainedAt   string `json:"obtainedAt,omitempty"`
}

// ConfigError is a startup/config validation failure carrying the
// badConfig detail code (never a secret).
type ConfigError struct{ Detail string }

func (e *ConfigError) Error() string { return "bad config: " + e.Detail }

// DetailCode returns the machine-readable detail (the failed event's
// message rides it; static English, never a secret).
func (e *ConfigError) DetailCode() string {
        if e.Detail == "" {
                return "badConfig"
        }
        return e.Detail
}

// Emitter serializes events to stdout, one JSON object per line,
// flushed per event (the host parses line-delimited JSON).
type Emitter struct {
        mu  sync.Mutex
        out *json.Encoder
}

// NewEmitter wires the emitter to os.Stdout.
func NewEmitter() *Emitter {
        return &Emitter{out: json.NewEncoder(os.Stdout)}
}

// NewEmitterTo wires the emitter to an arbitrary writer (tests).
func NewEmitterTo(w *os.File) *Emitter {
        return &Emitter{out: json.NewEncoder(w)}
}

// Emit writes one event; a write failure is fatal for the engine (the
// host pipe is gone) and is reported to stderr, never ignored silently.
func (e *Emitter) Emit(ev Event) error {
        e.mu.Lock()
        defer e.mu.Unlock()
        return e.out.Encode(ev)
}

// Log emits a `log` event (the level-tagged line is already redacted by
// the caller).
func (e *Emitter) Log(level, format string, args ...any) {
        _ = e.Emit(Event{
                Name: EvLog,
                Line: level + ": " + fmt.Sprintf(format, args...),
        })
}

// SecretPair is the same-account OAuth pair shape used by both the
// refresh path (authRefreshed) and the login path (loginCompleted).
type SecretPair struct {
        AccessToken  string
        RefreshToken string
        ExpiresIn    int
        ObtainedAt   string // RFC3339
}
