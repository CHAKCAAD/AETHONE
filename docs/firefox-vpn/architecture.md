# Firefox VPN in AETHONE — Architecture

> Status: source restored & committed on `phase2/firefox-vpn-ui`
> (private repo `CHAKCAAD/aethonepriv` only — upstream license
> UNRESOLVED, see `phase1/fxv/ORIGIN.md`).
> This document describes the architecture as implemented in the
> source. **No device test and no APK build has been performed by the
> agent** — device acceptance is the owner's next phase.

## 1. The chain

```text
Firefox Account Authentication
           |
           v
Flutter / Dart Application
           |
           v
Firefox Login Manager (WebView + WebChannel)
           |
           v
Go Child Process (libfirefoxvpn.so)
           |
           v
Pinned Firefox VPN Core (upstream 55ad91a2…)
           |
           v
Firefox / Mozilla Control Plane (api.accounts.firefox.com,
           firefox.settings.services.mozilla.com)
           |
           v
Server Discovery -> Existing AETHONE Connection Architecture
```

## 2. Process model (unchanged, non-negotiable)

The Go engine is an **independent child process** — never a Go-mobile
binding, never a JNI-loaded library:

```text
Flutter UI
    |
    v
Dart Repository / Service  (lib/connection/firefox/*)
    |
    v
Process Manager  (dart:io Process.start, includeParentEnvironment: false)
    |
    v
Android Native Executable  ($nativeLibraryDir/libfirefoxvpn.so)
    |
    v
Go Firefox Engine  (phase1/fxv, module aethone/fxv)
```

* The binary ships as `libfirefoxvpn.so` inside the APK's native
  libraries (`android/app/src/main/jniLibs/<abi>/`, packaged with
  `useLegacyPackaging = true` so it is **extracted to a real file**
  with the exec bit — `extractNativeLibs`).
* Dart spawns it via `Process.start` with the absolute path resolved
  from `nativeLibraryDir` (`lib/connection/firefox/firefox_engine.dart`;
  `FXV_ENGINE_BIN` env override exists for host-side tests).
* `includeParentEnvironment: false` — the parent environment is never
  inherited. See §5 for the full security invariant list.

## 3. The wire contract (Go ↔ Dart)

Verbatim from `phase1/fxv/internal/engine/contract.go`:

| Channel | Content |
|---|---|
| `stdin` | exactly ONE JSON line — `Config` for the tunnel role, `LoginConfig` for `--login`. Closing stdin = shutdown. |
| `stdout` | JSON-lines status events (`Event`), flushed per event |
| `stderr` | sanitized technical output only — never secrets |

`Event` fields: `event`, `message` (static English, omitempty),
`failCode`, `code` (the exit code the engine will use), `httpStatus`
(omitempty), `retryable` (*bool, omitempty).

Event names (the auth/session events): `loginCompleted`,
`authRefreshed`, `failed`.

Exit codes (mirrored by `FirefoxEngineExitCode` on the Dart side):

| Code | Meaning |
|---|---|
| 0 | clean — stdin closed / drained |
| 1 | startup or config failure |
| 2 | quota exhausted |
| 3 | renewal timeout (session dead, host decides) |
| 4 | internal error |

Engine roles (argv): `--login`, `--discover`, `--dns-probe`, plus the
default tunnel role (reads `Config` from stdin). `badConfig` detail
codes ride the message: `configVersionMismatch`,
`socksListenNotLoopback`, `guardianNotHttps`, `transportUnknown`,
`authAccessTokenMissing`, `configNotJSON`, `upstreamOverrideInvalid`.
Login-role rejections use their own fail codes (`sessionTokenInvalid`,
`loginModeUnsupported`).

The full error-code taxonomy lives in [error-codes.md](error-codes.md);
the OAuth pair contract in [oauth-contract.md](oauth-contract.md).

## 4. Dart-side components

| Component | Path |
|---|---|
| Engine child-process manager | `lib/connection/firefox/firefox_engine.dart` |
| WebChannel login client | `lib/connection/firefox/firefox_login.dart` + `firefox_web_channel.dart` |
| Protocol adapter (AETHONE architecture) | `lib/connection/firefox/firefox_protocol.dart` |
| Error mapping (Dart side) | `lib/connection/firefox/firefox_errors.dart` |
| Platform adapter (paths, vault crypto) | `lib/connection/platform_engine_adapter.dart` |
| Settings / account UI (read-only status) | `lib/features/settings/` |

The OAuth pair is stored ONLY as Android-Keystore AES/GCM ciphertext
(`firefoxEncrypt` / `firefoxDecrypt` methods on the engine bridge in
`MainActivity.kt`); plaintext exists in memory and on the engine's
private stdin pipe only. Details: `docs/FIREFOX_VPN_SECURITY.md`.

## 5. Security invariants (unchanged)

* Session/access/refresh tokens NEVER in argv.
* Secrets NEVER in the child environment; parent environment not
  inherited (`includeParentEnvironment: false`).
* Tokens enter the engine only through the private stdin pipe.
* Tokens never printed to stdout/stderr/UI error messages.
* Keystore vault: an invalid token pair never overwrites a valid one.
* Log redaction on both sides (`internal/redact` in Go, the Dart
  guards) — see [error-codes.md](error-codes.md) §5.

## 6. State separation

These states are DISTINCT and must never be conflated:

```text
Account Logged In  ≠  Protocol Selected  ≠  Engine Started  ≠
Engine Ready       ≠  VPN Connected      ≠  Traffic Verified
```

Login success (`loginCompleted`) is an AUTH event, not a connection
event. The UI shows "connected" only from a valid engine event.

## 7. DNS resolution

The engine resolves through **Android's Bionic system resolver**
(`getaddrinfo`) via CGO builds for every Android ABI — the A1 decree.
Full rationale and matrix: [dns-resolution.md](dns-resolution.md),
[android-abi-matrix.md](android-abi-matrix.md).

## 8. Provenance

Upstream pin, license status and adaptation record:
`phase1/fxv/ORIGIN.md`. Engine rebuild procedure: [build.md](build.md).
Owner's next-session APK recipe: [recovery-guide.md](recovery-guide.md)
(فارسی).
