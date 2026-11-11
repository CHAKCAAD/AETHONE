# fxv — ORIGIN and provenance

The AETHONE Firefox VPN engine layer. Rebuilt 2026-11-09 (the
2026-11-09 master-prompt session) from the documented contract after
the original workspace was lost; the engine source now lives IN THIS
REPOSITORY so it can never again depend on an agent's temporary
workspace.

## Upstream pin (exact)

```
repository : https://github.com/UjuiUjuMandan/firefox-vpn-client
commit     : c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1
subject    : chore: update pinned Firefox identity (#7)
date       : 2026-11-10
```

### Re-pin history

| Date | Pin | Delta vs. previous pin |
|---|---|---|
| 2026-11-06 | `55ad91a2ccea1c93e69c82a08a7681e279884db5` | the original provenance base (uTLS Firefox ClientHello fix) |
| 2026-11-11 | `c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1` | `firefox_identity.go` only: `defaultFirefoxVersion` "159.0" → "160.0"; upstream `README.md` added and upstream `.gitignore` extended (docs only). Verified by full-tree `git diff 55ad91a..c1c5d89` — **zero** other Go-code changes; the library surface used below (`FxaOAuthToken`, `FxaRefreshToken`, `FetchProxyPass`, `FetchServerList`, `NewControlPlaneTransport`, the Guardian sentinels) is byte-identical. Owner-ordered update, analysis in `docs/firefox-vpn/core-update-2026-11-11.md`. |

The pristine upstream copy is FETCHED, never committed
(`phase1/scripts/fetch_upstream.sh` verifies `git rev-parse HEAD` against
the pin and writes `phase1/firefox-vpn-client.SHA256SUMS`; the directory
itself is gitignored). `go.mod`'s `replace` directive binds the module to
that local copy. **Re-fetching with a different commit is forbidden** —
the pin is the provenance base of every adapted piece below. Changing
the pin itself is an owner decision recorded in the re-pin history above.

## LICENSE STATUS — UNRESOLVED (read this before distributing anything)

The upstream repository at the pinned commit contains **NO license
file, NO COPYING, NO NOTICE, and NO copyright/license headers in any
source file** (verified 2026-11-09 by direct inspection of the full
tree at the pin, and re-verified 2026-11-11 at `c1c5d89` — the delta
since `55ad91a` added only a README, a .gitignore entry and a version
constant, still no license). Absent a license, no redistribution, modification or
relicensing rights exist by default ("all rights reserved" is the
default copyright posture).

Consequences, per the standing decrees (docs/FIREFOX_VPN_SECURITY.md §6,
the master prompt §7.2):

* **the engine, its binaries and everything derived from the upstream
  stay in the PRIVATE repository** (`CHAKCAAD/aethonepriv`) — nothing is
  pushed to `CHAKCAAD/AETHONE`, no public release, no public artifact;
* the vendored upstream COPY is never committed to git (fetch + hash
  manifest only) — this repository's committed code is AETHONE's own
  layer plus the adapted pieces recorded below;
* **no license text is invented, no proprietary claim is made** — this
  file records the honest status instead;
* the owner's options: (a) obtain written permission from the upstream
  author, (b) choose a licensed alternative implementation, or (c) keep
  the engine private indefinitely. Until one is chosen the status is
  BLOCKED for any public distribution.

Credit where due: the upstream author's reverse-engineering of the
Mozilla VPN control/data planes is the foundation this engine wraps.
FoxyVPN (MIT) was consulted as an architectural REFERENCE ONLY (the
WebChannel bridge mapping on the Dart side); no FoxyVPN code is
included; its GPL sing-box fork was neither consulted nor included.
The Arman VPN project was not consulted and is not included (standing
prohibition).

## What is NEW AETHONE code (written for this engine)

| Piece | Files |
|---|---|
| The wire contract (Config/Event/LoginConfig, versions, codes) | `internal/engine/` |
| The classification guard (Phase B Part 2/3) | `internal/fferr/` (from `docs/phaseb-engine-patch/fferr`, applied here verbatim) |
| The redaction scrubber | `internal/redact/` |
| The discovery selection policy (REC/CatchAll/quarantine/country) | `internal/discovery/` |
| The entry point, orchestration, park loop, `--discover`, `--login`, `--dns-probe` roles | `cmd/libfirefoxvpn/` |
| The 60s runtime-stats evidence line (Stage 6; not upstream — the demo has no such loop) | `cmd/libfirefoxvpn/main.go` (`runtimeStatsLoop`, `formatRuntimeStats`) |
| The control-plane relay system (Guardian 451 recovery: doubled-path bypass, shared community pool, personal relay, ECH) — see § relay below | `internal/relay/` |
| The build/fetch scripts and this provenance record | `../scripts/`, this file |

## What is ADAPTED from the upstream (per-file provenance)

Adapted from `cmd/proxy-demo/main.go` of the pinned commit:

| Adapted piece | Now lives in | Adaptation notes |
|---|---|---|
| `socksServer`, `handshakeSOCKS5`, `readSOCKSAddr`, `writeSOCKSReply`, `mapUpstreamError`, `proxyBidirectional`, `copyConn`, `closeIdleConns` | `internal/socks/server.go` | client-affinity opener REMOVED (single-session decree); logging through the injected level-tagged sink. Stage 6 restored the demo's level discipline: `logDebug`→sink-gated `Debugf` (verbose only), `logTarget`→`Server.logTarget` (`<redacted; use -verbose>` unless verbose, warn lines included), `logErr`→`upstream.RedactedError`; the Stage-2 live=N diagnostics ride Info |
| `tunnelWriteBuffer`, `tunnelConn`, `tunnelAddr` | `internal/upstream/tunnel.go` | behavior preserved verbatim |
| `newH2ProxySession`, keepalive, `OpenTunnel`, `roundTripWithOpenTimeout` | `internal/upstream/h2.go` | sessionFailureTracker REMOVED (no pool); Stage 6 added `RedactedError` (the demo's `logErr`, relocated next to its type) |
| `newH3ProxySession`, `OpenTunnel` | `internal/upstream/h3.go` | same; the 1200-byte InitialPacketSize floor kept |
| `proxyController` | `internal/upstream/controller.go` | the POOL IS REMOVED — exactly one session, one account, no rotation; renewal loop + quota/renewal-timeout terminals preserved |
| `verifyExit`, `parseExitProbeResponse`, `openTunnelContext` | `internal/upstream/exitprobe.go` | the probe request now presents the uTLS Firefox ClientHello (the anti-bot edge treats Go's ClientHello as a bot signature) |

Used as LIBRARIES through the pin (unmodified, via the `replace`):
`vpnclient.FxaOAuthToken` (the audited `fxa-credentials` exchange with
HAWK + uTLS + the Fastly anti-bot retry), `vpnclient.FxaRefreshToken`,
`vpnclient.FetchProxyPass` (Guardian; `ErrQuotaExceeded` /
`ErrTokenInvalid` semantics), `vpnclient.FetchServerList`
(RemoteSettings), and the control-plane transport
(`NewControlPlaneTransport` — the uTLS Firefox ClientHello on HTTP/2).

## Deliberately NOT carried over (policy)

From `cmd/proxy-demo`: the interactive login/credential prompt (Phase 2
account UI + WebChannel own that), the session-token pool (forbidden —
one account, no pools, no rotation), the multi-upstream session pool
with client affinity (one session), the CLI flags/`-print-info`/state
files, `vpnclient.SaveTokens/LoadTokens` plaintext token files (the
Android-Keystore vault on the Dart side replaces them), the password
login path (`FxaLogin` — the account password never transits AETHONE
code; the `--login` role takes the WebChannel-captured session token
only), and the `-api-proxy` machinery.

## The documented seams (recorded honestly)

1. **The FxA errno seam** — the pinned upstream does not export its
   `fxaAPIError` type, so the FxA application errno (and the
   Guardian sentinel's status) ride the error TEXT; `fxaErrno()` /
   `fxaHTTPStatus()` in `cmd/libfirefoxvpn/login.go` extract them.
   This is the ONE string-adjacent seam and it is deliberately NOT
   part of the Phase B transport classification (which is type-based
   through `errors.As` in `internal/fferr`, per the decree).
2. **The pair-guard seam** — the upstream's `FxaOAuthToken` returns
   the PARSED `TokenResponse` (the raw body is not reachable without
   forking the audited exchange), so the Part 3 guard applies to the
   parsed fields (`guardParsedPair`); JSON-string typing is guaranteed
   by the upstream's own unmarshal (a wrong-typed field fails there
   and arrives as an exchange error → `invalidTokenResponse`).

## The rebuild session's honest deltas vs. the lost Phase-1 tree

The lost tree's exact bytes are unrecoverable (never committed). This
rebuild follows the DOCUMENTED contract (docs/FIREFOX_VPN_ENGINE.md,
FIREFOX_VPN_LOGIN.md, FIREFOX_VPN_ANDROID.md, the phase reports and
the phaseb patch README) field-by-field: the event catalog, the config
rules, the failure/exit codes, the roles, the module layout, and the
provenance boundaries above. Additions THIS session, per the master
prompt and its multi-architecture amendment:

* `--dns-probe` — the per-ABI DNS evidence role (resolver identity +
  real resolution of the control-plane domains; no secrets);
* the clean-stop check at every walk stage boundary;
* `EngineVersion` 1.2.0-phaseb (the classified `failed` event + the
  pair guard, integrated from `docs/phaseb-engine-patch/`);
* all-ABI CGO enforcement in the build script (the A1 decree, now
  applied to arm64-v8a AND verified for armeabi-v7a/x86_64 — see
  `../scripts/build_engine.sh` and `../docs/BUILD.md`).

## 2026-11-09 amendment — the public integration branch (owner-authorized)

The standing rule above ("nothing is pushed to `CHAKCAAD/AETHONE`")
was written for the phase-1 containment. On 2026-11-09 the owner
issued the PHASE-2 decree: the completed Firefox work is transferred
to the PUBLIC repository's integration branch
`integration/firefox-vpn-debug` (merge `5562e60`, preserving every
original commit hash and order) so that GitHub Actions — never the
agent's constrained sandbox — builds the DA debug APK.

What changed, and what did NOT:

* the engine SOURCE now lives on that public integration branch — the
  owner's explicit instruction, superseding the phase-1 containment
  FOR THIS BRANCH ONLY;
* the public repository's default branch (`ci-bootstrap/v4.4`) is
  untouched: no merge, no release, no tag has been made, and none may
  be until the owner explicitly confirms after the device test;
* the delivery vehicle is expiring GitHub Actions artifacts
  (14-day retention), NOT GitHub Releases;
* the LICENSE status itself is UNCHANGED and UNRESOLVED: no license
  file exists at the upstream pin, so PUBLIC DISTRIBUTION (releases,
  default-branch promotion, anything that outlives the containment)
  remains BLOCKED until the owner resolves it — written permission
  from the upstream author, a licensed alternative, or indefinite
  private containment.


## 2026-11-12 amendment — § relay (the Arman VPN architectural reference)

The control-plane relay system (`internal/relay/`, contract 1.3.0-relay)
implements the Guardian HTTP 451 (`unavailable_in_region`) recovery the
owner ordered on 2026-11-12, modeled on the Arman VPN client's relay
system as documented in its v1.0.17 release
(github.com/armanlife/arman-vpn-client — "Mozilla has blocked access
from Iran to Guardian ... The app now automatically uses shared relays
when this error occurs. Your main VPN traffic continues through
Mozilla's tunnel").

PROVENANCE POSTURE — reference-only, the same posture the FoxyVPN (MIT)
consultation used:

* Arman's core is GPL-3.0. **NO Arman code is included in AETHONE.**
  `internal/relay/` is an original implementation of the documented
  BEHAVIOR and WIRE PROTOCOL (the `?url=` forwarding shape, the
  `X-Relay-Error` refusal header, the shared-pool `?health=1` JSON and
  `X-Arman-Relay: 1` forwarded marker, the TLS 1.2 / edge-route leg
  fallbacks, the ECH mode triad), written for AETHONE's engine contract
  (the stdin config seam and the pinned upstream's
  `SetControlPlaneTransport` export — the upstream pin itself is
  untouched, as always).
* The shared relay pool consumes the PUBLIC arman-org community
  manifest (raw.githubusercontent.com/arman-org/update-manifests —
  public JSON data, fetched read-only; its curation is that project's).
  AETHONE's health check accepts both community identities
  ("arman-vpn" and "aethone") so relays deployed from either guide
  serve either client.
* The reference server implementations shipped in
  `docs/firefox-vpn/relay/` (`worker.js`, `relay.php`) are likewise
  ORIGINAL code for the same protocol, written for this repository; the
  user-facing guide (`docs/firefox-vpn/relay.md`) is original Persian
  documentation.
* Honest deltas vs. the reference: (1) the reference bounds the first
  direct attempt with a 4s quick dial — the pinned upstream exports no
  dial-injection seam, so AETHONE keeps the upstream's own dial budget
  and relies on the 10-minute relay-first window to amortize it;
  (2) the reference resets relay state on network-change events —
  AETHONE relies on the window's expiry plus the relay-failure→direct
  retry; (3) the reference's shared pool carries Guardian requests with
  replayable bodies only, exactly as AETHONE's does — no divergence.

Design record: `docs/firefox-vpn/relay-2026-11-12.md`.
