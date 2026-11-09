# FIREFOX VPN LOGIN — the FxA WebChannel sign-in flow (Phase 2)

Status: **Phase 2, private branch `phase2/firefox-vpn-ui` only.**
Upstream license UNRESOLVED — nothing derived from the engine may ship
publicly until the owner settles it (see `fxv/ORIGIN.md`).

## 1. What Phase 2 adds

Phase 1 left the session pair to a controlled injection
(`FirefoxSessionInjector`). Phase 2 closes the loop with the REAL
sign-in: the user signs in on **Mozilla's own page**, and the app never
sees the password.

```
accounts.firefox.com (context=fx_desktop_v3)  inside an in-app WebView
   │  WebChannel messages (Mozilla's page ↔ browser protocol)
   ▼
FirefoxWebChannelBridge (pure Dart, ADAPTED from FoxyVPN MIT)
   │  fxaccounts:login → the 64-hex FxA session token (the ONLY secret)
   ▼
FirefoxLoginClient — spawns the engine's `--login` role
   │  spawn: argv [libfirefoxvpn.so, --login], environment EMPTY
   │  stdin: ONE JSON line {version:1, mode:"webchannel", sessionToken}
   ▼
libfirefoxvpn --login (Go child, short-lived)
   ├─ vpnclient.FxaOAuthToken — the fxa-credentials grant, HAWK session
   │  auth, uTLS Firefox ClientHello, the Fastly anti-bot retry
   │  (the pinned upstream's audited path, unchanged)
   ├─ unverified session (errno 104/138 · 400/401 unconfirmed/unverified)
   │  → RETRIED inside the 300 s budget (loginRetry events)
   └─ stdin EOF = clean cancel (exit 0 — the user backed out)
   │  stdout: loginCompleted {accessToken, refreshToken, expiresIn}
   ▼
FirefoxSessionStore — the pair lands in the ANDROID KEYSTORE VAULT
   (AES/GCM, never a plain file, never logged)
   ▼
WebView cookies cleared (the browser session dies locally) → done
```

## 2. The pieces

| Piece | File | Provenance |
|---|---|---|
| WebChannel bridge (pure Dart mapping + the JS hook) | `lib/connection/firefox/firefox_web_channel.dart` | ADAPTED from FoxyVPN's `BrowserLoginScreen.kt` (MIT, Copyright (c) 2026 Vauth) — WebView-free and unit-tested; the JS channel is `aethoneFxChannel`, the reply entry `window.__aethoneFxReply` |
| Login client (spawn/cancel/timeout, the `--login` contract) | `lib/connection/firefox/firefox_login.dart` | NEW (the phase-1 `FirefoxVpnEngine` spawn discipline, applied to the short-lived login child) |
| Login wire types (`loginStarted/loginRetry/loginCompleted`, failure codes, `FirefoxLoginResult`) | `lib/connection/firefox/firefox_protocol.dart` | NEW mirror of the Go `engine` package |
| The `--login` role itself | `fxv/cmd/libfirefoxvpn/login.go` + `fxv/internal/engine/login_config.go` | NEW (the exchange is the pinned upstream's `vpnclient.FxaOAuthToken`) |
| The login screen (WebView + status strip + cookie hygiene) | `lib/features/settings/firefox_login_screen.dart` | NEW |
| The firefox settings page (account + location + transport) | `lib/features/settings/firefox_page.dart` | NEW |

### Deliberately NOT implemented (recorded decisions)

* **PKCE authorization-code exchange** (the MIT reference's variant) —
  the pinned upstream's `fxa-credentials` grant is the audited, proven
  path at this pin; the exchange sits behind one function so a variant
  can slot in later without touching the contract.
* **`POST /session/destroy`** after the exchange — needs HAWK plumbing
  outside the vendored package; the Dart side clears the WebView cookies
  instead, which kills the browser session locally.
* **Email+password login inside the app** — the account owner's
  password must never transit AETHONE code; `mode:"password"` is a
  RESERVED, refused value (`loginModeUnsupported`).
* **Account management UI beyond sign-in/sign-out** (email display,
  subscription state, devices) — the vault deliberately stores only the
  pair; profile data would need an FxA profile endpoint round this
  phase did not wrap. `FirefoxAccountStatus` is vault presence, honestly
  labeled.

## 3. The wire contract (the `--login` role)

Versioned by `engine.LoginConfigVersion = 1`; the engine reports
`EngineVersion 1.1.0-phase2` in `loginStarted`.

* **stdin** — exactly ONE JSON line (`engine.LoginConfig`):
  `version` (must be 1), `mode` (`webchannel`; `password` reserved and
  refused), `sessionToken` (64 hex — validated BEFORE any network
  byte), `verifyTimeoutMs` (0 → 300 000, clamped 1 000–600 000),
  `retryDelayMs` (0 → 3 000). The buffer is dropped after the parse.
* **stdout** — `loginStarted` (mode, version, pid) →
  (`loginRetry` (attempt, retryInMs))* → `loginCompleted`
  (**accessToken/refreshToken/expiresIn** — the secret-carrying event,
  the twin of the tunnel role's `authRefreshed`; the host routes it
  straight into the Keystore vault) → `stopped`. Failures: `failed`
  with `failCode` ∈ `loginModeUnsupported · sessionTokenInvalid ·
  sessionRejected · loginTimeout · exchangeFailed` and exit code 1.
* **stdin EOF** — a CLEAN cancel (exit 0, `stopping`/`stopped`
  reason `cancelled`): the user backed out of the login page; a cancel
  is not a failure. The role aborts even an in-flight exchange call.
* **stderr** — redacted logs; the session token is in the redaction
  set (`internal/redact`), so no error can echo it.

### Error semantics

| failCode | Meaning | UI guidance |
|---|---|---|
| `sessionRejected` | FxA definitively refused the token (errno 102/110/108) | «نشست ورود پذیرفته نشد؛ دوباره وارد شوید» — sign in again |
| `loginTimeout` | the sign-in was not confirmed within the budget | retry |
| `exchangeFailed` | transport / anti-bot challenge failure (redacted) | retry, possibly on another network |
| `sessionTokenInvalid` | the captured token was not 64-hex (a bridge/papering bug) | sign in again |

PHASE B (Part 2, 2026-11-09) — the `failed` event's contract is extended
**additively** (EngineVersion 1.2.0-phaseb; the codes above stay valid
forever — the Dart mapper accepts both, see
`lib/connection/firefox/firefox_errors.dart` and the engine-side patch
`docs/phaseb-engine-patch/`):

* `failCode` may carry the granular transport classes — `dnsError` ·
  `networkUnavailable` · `timeout` · `tlsError` · `sessionRejected` ·
  `tokenExchange` · `invalidTokenResponse` · `serverRejection` ·
  `unknown` — classified by ERROR TYPE on the Go side (`errors.As`,
  never string matching);
* two OPTIONAL fields join the event: `httpStatus` (the REAL status
  code when a response arrived; 0/absent on transport failures) and
  `retryable` (the engine's retry hint);
* `message` remains the static English text; the raw Go chain goes to
  the engine's stderr log ONLY (redacted) — it NEVER reaches a
  user-visible surface (the Dart UI renders the per-class localized
  text, chosen by the class code alone);
* `loginCompleted` is only emitted for a WELL-FORMED pair (Part 3): both
  `accessToken` and `refreshToken` present as JSON strings, non-empty,
  non-blank — anything else is the `invalidTokenResponse` failure. The
  Dart side applies the same guard as defense in depth
  (`FirefoxErrors.invalidPairReason` — a broken pair is rejected, never
  vaulted, and a clean child exit cannot mask it).

## 4. Security rules (the phase-1 decree, extended)

1. The session token's ONLY carriers: (a) the WebView→Dart
   `JavaScriptChannel` message (in-process, never persisted), (b) the
   login child's stdin pipe. NEVER argv, environment, logs, events
   (other than the minted pair on `loginCompleted`), or a file.
2. The minted pair's ONLY carriers: the child's stdout pipe (the
   `loginCompleted` event) and the Android-Keystore-encrypted vault.
   `FirefoxEngineEvent.logLine` renders it as
   `access<redacted> refresh<redacted>`; `carriesSecrets` routes it away
   from every log sink (tested).
3. The spawn is BARE: `[binary, --login]`, empty environment,
   `includeParentEnvironment: false` — the same discipline as the
   tunnel engine (tested against the real host binary).
4. The bridge ignores every payload whose page host is not
   `accounts.firefox.com` / `*.firefox.com` — verified on BOTH sides
   (the JS hook checks before posting, the Dart mapping re-checks
   before parsing).
5. One login child at a time; the screen's dispose cancels it (stdin
   close → 3 s grace → kill): no orphan survives a dismissed page.
6. The login URL is fixed (`kFirefoxLoginUrl`,
   `context=fx_desktop_v3&service=sync&action=email`) — the FxA page
   only speaks the WebChannel in that context. The WebView UA is the
   pinned Firefox-on-Android identity (`159.0`, the same major the
   engine's control plane presents).
7. Non-Mozilla links leave the WebView (external browser) — the
   in-app page stays on Mozilla properties only.

## 5. How it is tested

`test/firefox_login_test.dart` (26 tests) + the Go side
(`fxv/cmd/libfirefoxvpn/login_test.go`, `login_exchange_test.go`):

* bridge mapping: every command, the token capture (both field names,
  uppercase-normalized), the malformed-token refusal, the dedup guard,
  the origin gate (both sides), the hook script's contracts — PASS.
* wire protocol: `loginStarted/loginRetry/loginCompleted` parsing,
  redaction, failure codes — PASS.
* wheel policy: firefoxOnly selectable, AUTO + live/seed list, the
  33-country phase-0 seed (sorted, no `cz`, no pseudo-countries) —
  PASS.
* store surface: `selectLocation` routing, the sanitizing setters,
  `applyFirefoxLocations` (swap + labels + garbage refusal) — PASS.
* REAL host binary: invalid token → the engine's own words; stdin
  close → clean cancel, no orphan; the REAL FxA endpoint with a FAKE
  token → honest `sessionRejected`/`exchangeFailed`, no leak — PASS.
* Go local harness: the HAWK header is VERIFIED against the session
  token (HKDF-SHA256 + MAC over the normalized request), the
  verify-retry loop, the leaky-body redaction, the timeout, the
  in-flight cancel — PASS.
* **NOT TESTED** (no device/browser/entitlement here): the real
  accounts.firefox.com page inside the real WebView, a real account's
  sign-in, and `loginCompleted` from a real entitlement. The pieces are
  proven up to that boundary and honestly labeled.

Related docs: `FIREFOX_VPN_ENGINE.md` (the tunnel contract),
`FIREFOX_VPN_SECURITY.md` (token handling),
`FIREFOX_VPN_PHASE2_REPORT.md` (the phase report).
