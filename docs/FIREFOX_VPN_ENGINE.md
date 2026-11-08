# FIREFOX VPN ENGINE — architecture and process contract (Phase 1)

Status: **Phase 1, private branch `phase1/firefox-vpn` only.**
The engine's upstream license is UNRESOLVED (see `fxv/ORIGIN.md` and
`FIREFOX_VPN_SECURITY.md`): nothing derived from it may be pushed to a
public repository or shipped in a public artifact until the owner settles
the question.

## 1. What the engine is

`libfirefoxvpn` — a standalone Go executable packaged as
`android/app/src/main/jniLibs/<abi>/libfirefoxvpn.so`. The `.so` name is
ONLY the Android packaging convention (extractNativeLibs unpacks
`lib/*.so` into `nativeLibraryDir`, the only directory an app may exec
from). It is **not** a `System.loadLibrary` shared library: the AETHONE
Dart host runs it with `dart:io Process.start` (on Android the same
fork/exec `ProcessBuilder` uses), argv bare, environment empty.

Module: `aethone/fxv` (Go 1.25.0). Upstream core pinned to
`55ad91a2ccea1c93e69c82a08a7681e279884db5` (2026-11-06, "fix(fxa):
present Firefox ClientHello on the control plane") via a `replace`
directive to the vendored pristine copy at `phase1/firefox-vpn-client/`.
Provenance of every adapted piece: `fxv/ORIGIN.md`.

```
AETHONE app (Dart, PlatformEngineAdapter._connectFirefox)
   │  spawn (bare argv, empty env)
   │  stdin ── ONE JSON config line (the only secret carrier)
   │  stdout ─ JSON-lines status events
   │  stderr ─ redacted human logs
   ▼
libfirefoxvpn.so (Go child process, one per session)
   ├─ Control plane  : Guardian (vpn.mozilla.org) — proxy pass acquire/renew
   │                   (FxA same-account OAuth refresh only; no pools)
   ├─ Discovery      : live Mozilla RemoteSettings server list
   │                   (upstream uTLS Firefox ClientHello; `--discover` role)
   ├─ Data plane     : Fastly MASQUE proxy — h2 (TLS 1.3 + ALPN h2 over TCP,
   │                   default) or h3 (QUIC/HTTP-3, optional)
   └─ Local SOCKS5   : 127.0.0.1:1822 — CONNECT only, loopback only
```

## 2. The fxv module map

| Package | Role | Provenance |
|---|---|---|
| `cmd/libfirefoxvpn` | entry point, config parse, orchestration, park loop, `--discover` role | NEW |
| `internal/engine` | the wire contract: `Config` (stdin) + `Event` (stdout) + failure/exit codes | NEW |
| `internal/socks` | SOCKS5 server: handshake, replies, CONNECT relay, idle/close policy | ADAPTED from `cmd/proxy-demo/main.go` (socksServer, handshakeSOCKS5, readSOCKSAddr, writeSOCKSReply, mapUpstreamError, proxyBidirectional, copyConn, closeIdleConns) |
| `internal/upstream` | one MASQUE session + its controller: `h2.go`/`h3.go` (ADAPTED from newH2ProxySession/newH3ProxySession), `tunnel.go` (ADAPTED from tunnelWriteBuffer/tunnelConn), `controller.go` (ADAPTED from proxyController — single session, **pool removed**), `exitprobe.go` (ADAPTED from verifyExit/parseExitProbeResponse), `session.go` | mixed, see file headers |
| `internal/discovery` | selection policy on the live list (REC, CatchAll exclusion, quarantine exclusion, deterministic country match) | NEW policy on upstream `vpnclient.FetchServerList` |
| `internal/redact` | scrub secrets from error strings before they reach logs/events | NEW |

Deliberately NOT carried over from `cmd/proxy-demo` (policy, see
`ORIGIN.md`): the interactive login/credential prompt (Phase 2 account
UI), the session-token pool (forbidden — one account, no pools, no
rotation), the multi-upstream session pool with client affinity (Phase 1
runs exactly one upstream session), CLI flags/`-print-info`/state files,
and `vpnclient.SaveTokens/LoadTokens` plaintext token files (replaced by
the Android-Keystore vault on the Dart side).

## 3. Process contract

Fixed and versioned by `engine.ConfigVersion = 1` / `EngineVersion
"1.1.0-phase2"` (bump both on breaking change; the 1.1.0 bump is the
additive `--login` role — the tunnel contract is unchanged).

* **stdin** — exactly ONE JSON line (`engine.Config`), written by the host
  right after spawn. The line is bounded to 1 MiB (`readConfigLine`);
  after parsing, the buffer carrying the tokens is dropped. The host
  KEEPS the pipe open; **closing it is the shutdown request** (the
  engine drains, refuses new work, and exits 0).
* **stdout** — JSON-lines status events (`engine.Event`), flushed per
  event. The only events that ever carry secret material are
  `authRefreshed` (the tunnel role) and `loginCompleted` (the `--login`
  role) — the same-account OAuth pair on this private parent↔child
  pipe; the host routes both straight into the Keystore vault.
* **stderr** — human-readable, level-tagged logs, redacted by
  `internal/redact` (the access/refresh tokens are the scrub set).
* **Exit codes** — `0` clean stop (stdin closed / drained) · `1` startup
  or config failure · `2` quota exhausted · `3` renewal timeout (session
  dead, host decides reconnect) · `4` internal error.
* **`--discover` role** — `libfirefoxvpn.so --discover` fetches the live
  server list (upstream uTLS Firefox ClientHello) and prints the
  discovery JSON on stdout; no stdin, no secrets. The Dart-side
  `FirefoxDiscovery` uses it for the pre-connect location model.
* **`--login` role** (PHASE 2, `docs/FIREFOX_VPN_LOGIN.md`) —
  `libfirefoxvpn.so --login` exchanges a WebChannel-captured FxA session
  token (ONE JSON line on stdin, `engine.LoginConfig` v1) for the
  same-account OAuth pair through the pinned upstream's
  `vpnclient.FxaOAuthToken` (HAWK + uTLS + the anti-bot retry),
  retrying unverified sessions inside a 300 s budget and emitting the
  pair on the secret-carrying `loginCompleted` event. Short-lived
  child; stdin EOF = clean cancel (exit 0).

### Config (stdin line; `engine.Config`)

| Field | Rule |
|---|---|
| `version` | must equal `1` (`configVersionMismatch`) |
| `socksListen` | MUST be loopback (`socksListenNotLoopback` otherwise); default `127.0.0.1:1822` |
| `guardian` | default `https://vpn.mozilla.org`; must be https (`guardianNotHttps`) |
| `country` | `""`/`"REC"` = AUTO (recommended anycast); ISO-3166-1 alpha-2 or country name, case-insensitive; no match → `noMatchForCountry` with the available list |
| `transport` | `h2` (default) or `h3` (`transportUnknown` otherwise) |
| `upstreamOverride` | `host:port` — skip discovery, dial that MASQUE proxy (the `selected` event reports `selectionSource:"override"`); test/lifecycle harness use |
| `upstreamTimeoutMs` / `handshakeTimeoutMs` / `idleTimeoutMs` / `maxConns` | 0 → upstream defaults (20 s / 10 s / unlimited / 256) |
| `exitCheckUrl` / `exitTimeoutMs` | engine-side exit probe; default `https://www.cloudflare.com/cdn-cgi/trace`, 10 s |
| `logLevel` | `quiet` / `normal` / `verbose` (stderr) |
| `auth.accessToken` | required (`authAccessTokenMissing`) |
| `auth.refreshToken` | optional but expected for renewal |

### Event catalog (stdout; `engine.Event`)

`started` (version, pid) · `discoveryFetched` (countries, ms) · `selected`
(country/name, city code/name, hostname, port, selectionSource
`autoRec|country|override`, recommended) — **the configured country and
the city/hostname are distinct fields, never conflated** · `passAcquired`
/ `renewed` (passExpiresAt, quota) · `upstreamReady` (transport, proxy
host, latency) · `socksReady` (addr — the listener is really bound) ·
`exitVerified` (exitIp, exitCountry, configuredCountry, exitCountryMatches,
latency) / `exitVerifyFailed` — **the exit country is reported separately
from the configured country; a mismatch is recorded, never hidden** ·
`authRefreshed` (PRIVATE pair) · `renewalFailed` (error redacted,
retryInMs) · `quotaExhausted` (quotaLeft, quotaReset) · `stopping` /
`stopped` (reason) · `failed` (failCode, message, exit code) · `log`.

Failure codes: `badConfig`, `discoveryFailed`, `noMatchForCountry`,
`passFetchFailed`, `quotaExhausted`, `upstreamSessionFailed` (h2/h3
negotiation included), `socksListenFailed`, `renewalTimeout`,
`internalError`.

## 4. Data plane (upstream session)

One session at a time (`upstream.Controller`, single-session policy):

* **h2** (default): TCP + TLS 1.3 with the Firefox ClientHello (uTLS),
  `h2` ALPN, then MASQUE `CONNECT`-style proxying of the SOCKS client's
  target streams (ADAPTED `newH2ProxySession` + `tunnelConn`).
* **h3** (optional): QUIC + `h3` ALPN (ADAPTED `newH3ProxySession`);
  failure to negotiate → `upstreamSessionFailed` with the h3 reason.

The controller owns the renewal loop: it refreshes the Guardian proxy
pass before expiry and, on token refresh, emits `authRefreshed` (the
same account only — `AcquireInitialPass` does refresh/recovery, never a
different account). Renewal failure is retried with backoff
(`renewalFailed` + `retryInMs`); a hard timeout parks the engine with
exit code 3. Quota exhaustion is its own terminal event + exit code 2 —
the host surfaces it as `firefoxQuotaExhausted` so the user picks
another engine (never a silent fallback, never a rotation).

The engine-side exit probe (`VerifyExit` through the tunnel, Cloudflare
trace) is **non-fatal**: it reports `exitVerified`/`exitVerifyFailed`
events only. The host's own end-to-end probe through 127.0.0.1:1822 is
the sole gate to `Connected`.

## 5. How it is tested

`fxv/cmd/libfirefoxvpn/main_test.go` (and `upstream_test.go`,
`socks_test.go`, `discovery_test.go`, `engine/config_test.go`) — the
lifecycle tests spawn the REAL engine binary and speak the REAL wire
contract. Honesty rules baked into the tests: RemoteSettings discovery
is REAL; Guardian/Fastly are faked by LOCAL TLS servers where a fake is
used (a test CA is injected via `SSL_CERT_FILE`) and are NEVER a claim
of real Firefox VPN connectivity; the `realGuardian` scenario hits the
real Guardian with an INVALID token and asserts the honest failure; the
`realFastlySession` scenario establishes a REAL TLS+h2 session to a real
Fastly MASQUE host with a locally-issued pass and asserts the engine
reports `socksReady` while its own exit probe HONESTLY fails (the data
plane needs a real entitlement — Phase 1 records that as BLOCKED).

Related docs: `FIREFOX_VPN_ANDROID.md` (build/ABI/packaging/ports),
`FIREFOX_VPN_LIFECYCLE.md` (state machine), `FIREFOX_VPN_SECURITY.md`
(token handling), `FIREFOX_VPN_SERVER_DISCOVERY.md` (phase-0 policy).
