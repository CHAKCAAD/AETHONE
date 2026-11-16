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
        "io"
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
// 1.4.0 — the WARP carrier block: socks5:// carrier URLs on the tunnel
//
//      config line — "Firefox over Warp" (the control plane rides the
//      carrier with the uTLS Firefox ClientHello kept; the data plane
//      dials through it).
// 1.5.0 — the guardian-line merge (2026-11-15, the owner's round 2):
//
//      the single `upstreamSocks` seam replaces 1.4.0's apiProxy +
//      upstreamProxy pair (one loopback-only socks5:// URL routes BOTH
//      planes — TCP CONNECT for h2 AND UDP ASSOCIATE for h3, so the
//      transport pick is free again); the process-local `dns` block
//      (system | DoH) on the tunnel and login config lines; the
//      `--webview-proxy` role (the DNS-aware CONNECT proxy for the sign-in
//      WebView — the login-page fix); and the quota events now carry
//      `quotaMax` beside quotaLeft/quotaReset. A host that sends none of
//      the new fields keeps the exact 1.2.0 direct behavior.
// 1.6.0 — the direct DATA plane (2026-11-15, the owner's round 4:
//
//      «مراحل اولیهٔ اتصال … از تونل ایتر بگذره و بعد خود اتصال
//      مستقیم انجام بشه» — arman's relay posture): the optional
//      `dataPlaneDirect` flag on the tunnel config line. With
//      upstreamSocks set AND dataPlaneDirect true, the control plane
//      (RemoteSettings discovery, the Guardian pass, the OAuth refresh —
//      the initial connection stages) still rides the carrier, but the
//      h2/h3 data session dials the Fastly edge DIRECTLY. The flag
//      requires upstreamSocks (fail-fast: dataPlaneDirectWithoutCarrier);
//      a host that sends no flag keeps the exact 1.5.0 behavior.
// 1.7.0 — the remaining-data round (2026-11-15, the owner's round 5):
//
//      the `--usage` role (the account's Guardian quota WITHOUT minting
//      a pass — arman's fetchProxyUsage model: HEAD then GET on the token
//      endpoint, riding upstreamSocks when set, X-Quota-Unlimited read);
//      the usage event carries `quotaUnlimited` beside the quota trio;
//      the DoH provider defaults become IP-LITERAL endpoints (no poisoned
//      bootstrap lookup); and a failed h3 session build falls back to h2
//      ONCE, honestly logged (a dead h3 serves nobody — the pick is a
//      preference, not a death sentence). Additive only.
// 1.8.0 — the arman-pattern round (2026-11-16, the owner's round 8:
//      «از پروژه arman-vpn-client الگو بگیر» — the reference app's
//      DEFAULT sign-in is the direct email+password form driven by the
//      core; the browser page is the alternative):
//      the `--login` role's `password` mode — the config line carries
//      email+password (the stdin pipe ONLY, exactly like the session
//      token; the engine derives authPW immediately and the password is
//      never logged or echoed), the FxA password flow runs inside the
//      engine (FxaLogin → the optional email-2fa code → the OAuth mint),
//      and the new `loginNeedsCode` event asks the host for the emailed
//      code (the second stdin line). The granular FxA application codes
//      (noAccount / wrongPassword / tooManyAttempts / requestBlocked /
//      secondaryEmail / invalidEmail / unverifiedAccount / codeExpired /
//      codeAttemptsExhausted / emailCaseInvalid) map arman's SignInError
//      model. The `--dns-probe` role gains the SAME upstreamSocks seam
//      the other roles have: with a carrier the probe dials each
//      control-plane domain THROUGH the carrier BY HOSTNAME (remote DNS —
//      the engine's own control-plane posture), and the events and
//      summary carry `via: "carrier"` ("direct" otherwise). Additive
//      only; a host that sends none of the new fields keeps the exact
//      1.7.0 behavior.
// 1.9.0 — the resolver round (the reference's OWN posture, ported from
//      arman-vpn-client core/internal/resolver): the `auto` DNS provider
//      races Cloudflare + Google + Quad9 IP-literal DoH endpoints at
//      once (first valid answer wins), the system resolver joins after
//      1s (or at once when every endpoint failed) and its answer wins
//      only when real, and IsBlockPage answers (private space + Iran's
//      filtering page 10.10.34.34-36 / 2001:4188:2:600:10:10:34::/112)
//      are stripped from BOTH the system's and the servers' answers — a
//      fully poisoned answer never wins while another server can still
//      answer. The EMPTY dns block now defaults to this posture (the
//      reference's DefaultDNSServers + fallback_to_system), never the
//      poisonable system one; system stays an explicit pick. Additive
//      only; a host that sends a full dns block keeps its exact pick.
// 2.0.0 — the reference's network posture, COMPLETED (round 10, the
//      owner's retest of 1.9.0: «از پروژه arman-vpn-client الگو بگیر و
//      مشکل رو حل کن» held, but the direct walk still failed — the
//      pieces the reference carries that 1.9.0 missed):
//        * the HELLO SPLIT (network.hello_split, ported verbatim): the
//          TLS ClientHello of every connection whose TLS this process
//          owns — the direct control plane AND the direct h2 data plane
//          — goes out split across TCP segments (off/sni/first-byte/
//          record on the dns config line; the host's default pick sni),
//          so a network filtering by server name cannot read it;
//        * the ONE desktop-Firefox identity (the reference's
//          ApplyFirefoxHeaders): FxA, Guardian, Remote Settings and the
//          Fastly solver all present desktop Firefox (Windows on
//          Android) with Accept */* and Accept-Encoding identity — the
//          live-measured 406 fix; the old MozillaVPN/2.35.0 split
//          identity is gone;
//        * the GUARDIAN 451 recovery chain (region_recovery.go +
//          auto_relay.go, ported): the doubled leading slash retries
//          past the edge's region rule, then the reference's own shared
//          relay pool (arman-org/update-manifests + the jsDelivr
//          mirror, health-checked, X-Arman-Relay validated) carries
//          /api/v1/fpn requests;
//        * the CARRIER FALLBACK: a SOCKS control-plane dial whose
//          CONNECT is refused falls back to the direct dial (its own
//          budget, same pinned hello) — the round-4 carrier-first
//          decree keeps its order, a refused carrier no longer kills
//          the walk (the owner's firefoxtransport:networkUnavailable in
//          BOTH modes);
//        * the h2 DATA plane offers the Firefox uTLS hello first with
//          Go's as the fallback (the reference's upstream_tls posture),
//          hello-split on the direct dial;
//        * the resolver keeps the reference's serversDownFor window (a
//          minute after an all-endpoints failure the system joins at
//          once);
//        * the DNS probe is honest per-domain: a 15 s per-domain
//          budget, block-page-only answers labeled as the filtering
//          page they are, never a blank walk.
const EngineVersion = "2.0.0"

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
        EvLoginNeedsCode   = "loginNeedsCode" // 1.8.0 — the password mode's email-2fa step
        EvLoginCompleted   = "loginCompleted"
        EvUsage            = "usage"      // 1.7.0 — the --usage role's success
        EvUsageFailed      = "usageFailed" // 1.7.0 — the --usage role's failure
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

        // 1.8.0 — the password mode's granular FxA application codes
        // (arman's SignInError model; the errno seam maps onto these).
        ErrNoAccount             = "noAccount"
        ErrWrongPassword         = "wrongPassword"
        ErrTooManyAttempts       = "tooManyAttempts"
        ErrRequestBlocked        = "requestBlocked"
        ErrSecondaryEmail        = "secondaryEmail"
        ErrInvalidEmail          = "invalidEmail"
        ErrUnverifiedAccount     = "unverifiedAccount"
        ErrEmailCaseInvalid      = "emailCaseInvalid"
        ErrCodeExpired           = "codeExpired"
        ErrCodeAttemptsExhausted = "codeAttemptsExhausted"
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
        // 1.5.0 — the merged-carrier config details (badConfig family;
        // static English, never secrets).
        detailUpstreamSocksInvalid = "upstreamSocksInvalid"
        detailDNSConfigInvalid     = "dnsConfigInvalid"
        // 1.6.0 — the direct-data-plane detail (same family).
        detailDataPlaneDirectWithoutCarrier = "dataPlaneDirectWithoutCarrier"
)

// Event is one stdout JSON line. Only authRefreshed and loginCompleted
// ever carry secret material (the same-account OAuth pair) — the host
// routes both straight into its Keystore vault.
type Event struct {
        Name    string `json:"event"`
        Message string `json:"message,omitempty"`

        // failed
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

        // passAcquired / renewed / quotaExhausted / usage
        PassExpiresAt  string `json:"passExpiresAt,omitempty"`
        QuotaMax       string `json:"quotaMax,omitempty"`
        QuotaLeft      string `json:"quotaLeft,omitempty"`
        QuotaReset     string `json:"quotaReset,omitempty"`
        QuotaUnlimited bool   `json:"quotaUnlimited,omitempty"` // 1.7.0 — X-Quota-Unlimited (the usage role)

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

        // loginNeedsCode (1.8.0, the password mode): the account's email
        // (the user typed it — not a secret), the FxA verification method
        // ("email-2fa"), and the LAST step's failure when it re-asks
        // ("wrongCode" | "codeExpired" | "network" — a machine code; the
        // localized text is the host's). Attempt counts the code asks.
        Email              string `json:"email,omitempty"`
        VerificationMethod string `json:"verificationMethod,omitempty"`
        LastError          string `json:"lastError,omitempty"`

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

// NewEmitterToWriter wires the emitter to any io.Writer (the child roles'
// test seams; production uses NewEmitter/NewEmitterTo).
func NewEmitterToWriter(w io.Writer) *Emitter {
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
