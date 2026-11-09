# FIREFOX VPN — Phase 1 report (private branch `phase1/firefox-vpn`)

Scope delivered: the independent Firefox VPN engine for Android — Go
engine wrapper, three-ABI Android builds, child-process management,
local SOCKS5 on 127.0.0.1:1822, server discovery wired into the AETHONE
connection architecture, full lifecycle management, and real-process
verification up to the boundary of what is provable without a live
entitlement. **Out of scope (by decree)**: UI/icons, Firefox login page,
WebChannel, account management UI, session UI storage, aether chaining,
Linux/Windows, public release. **Stopped at the end of Phase 1;
Phase 2 awaits the owner's explicit approval.**

## 1. What changed (the private worktree)

New (`lib/connection/firefox/`, 946 lines Dart + 1 Kotlin file):
`firefox_protocol.dart` (wire types), `firefox_engine.dart`
(child-process supervisor, 9-state machine),
`firefox_session_store.dart` (Keystore vault),
`firefox_discovery.dart` (location model + labeled cache),
`android/.../FirefoxKeystore.kt` (AES/GCM Keystore crypto),
`test/firefox_engine_test.dart` (20 tests).

Modified (additive, reversible): `MainActivity.kt` (+25: the
firefoxEncrypt/firefoxDecrypt channel methods),
`platform_engine_adapter.dart` (+355: the `_connectFirefox` walk, the
firefox branch, cleanup ordering),
`transport_modes.dart` (+30: `ExitKind.firefoxExit`, the `firefoxOnly`
mode, port 1822), `app_assets.dart` (+15: `ProtocolId.firefoxOnly`,
placeholder icon), `app_strings.dart` (+6: 5-language l10n),
`test/design_tokens_test.dart` (+17/−3: the 11→12 regression guard).

The engine module `phase1/fxv` (2,322 lines of Go incl. tests) and the
pinned pristine upstream copy live OUTSIDE the app repo (license
UNRESOLVED); `jniLibs/` binaries are git-ignored. Documentation: the
five `docs/FIREFOX_VPN_*.md` files carried with this report.

## 2. Toolchain and pins (all recorded, all reproducible)

| Piece | Pin |
|---|---|
| upstream core | `55ad91a2ccea1c93e69c82a08a7681e279884db5` (2026-11-06) |
| Go | 1.25.0 (`/tmp/my-project/fx0/go`) |
| Android NDK | r28c, 28.2.13676358 |
| Flutter | 3.47.9 (`tools/flutter`, pub cache `tools/pubcache`) |
| JDK / Gradle | 21.0.13+9 / 9.8.2 (`GRADLE_USER_HOME=/tmp/my-project/gradle_home`) |
| engine build | `phase1/scripts/build_engine.sh`; `-trimpath`; SHA256 in `build/SHA256SUMS.txt` |

Environment normalizations done this phase (record, no repo impact):
the Gradle SDK's `ndk/28.2.13676358` was an EMPTY STUB that broke the
`jni` CMake configure — the real NDK bits were moved into
`tools/android-sdk/ndk/28.2.13676358` (same pin, identical bits; the fxv
binaries are unaffected and `build_engine.sh` now points there); the
dev container is 4 GiB, so builds run with bounded heaps
(gradle 1536M / kotlin 1024M) — the repo's canonical
`gradle.properties` is unchanged.

## 3. Test matrix (honest labels only)

### Build
* three-ABI `libfirefoxvpn.so` + host build: **PASS** (arm64 pure Go
  PIE `/system/bin/linker64`, v7a/x86_64 NDK cgo `for Android 34`,
  `NEEDED liblog/libdl/libc`, all `-rwxr-xr-x`).
* SHA256 pinning + **rebuild determinism**: **PASS** — a full rebuild
  after a test-only source change reproduced all four hashes
  bit-identically; the old self-referential `SHA256SUMS.txt` entry was a
  script bug, fixed.
* ELF/ABI/readelf verification: **PASS** (per-ABI output in the build
  log; `FIREFOX_VPN_ANDROID.md`).
* jniLibs ≡ pinned build (per-ABI hash compare): **PASS**.
* debug APK packaging (`assembleDebug`, 286 s): **PASS** — engine
  present in all three ABIs, legacy packaging (compressed in APK,
  extracted to `nativeLibraryDir` at install); AGP's standard
  llvm-strip applies (in-APK hashes recorded in
  `FIREFOX_VPN_ANDROID.md`).

### Process management (child process)
* spawn / bare argv / empty env, stdin-EOF shutdown, grace-then-kill,
  orphan prevention: **PASS** (Go lifecycle tests + Dart
  `FirefoxVpnEngine` group against the REAL host binary).
* unexpected exit mapped to outcome (`engineExited:<code>`): **PASS**.

### SOCKS5
* listener binds loopback only (non-loopback refused by validation):
  **PASS**.
* full SOCKS5 CONNECT data path through the engine (handshake, CONNECT,
  bidirectional relay) — proven against the LOCAL TLS harness
  (fake Guardian/Fastly with a test CA), honestly labeled:
  **PASS (local harness)**. Against the REAL Fastly MASQUE endpoint:
  REAL TLS+h2 session established and `socksReady` reported
  (`TestLifecycleRealFastlySession`); payload CONNECT through the real
  proxy requires a real entitlement — **BLOCKED** (below).

### Network (control plane + data plane)
* live RemoteSettings discovery through the engine (uTLS Firefox
  ClientHello): **PASS** (phase-0 live sample 35 records; re-proven by
  the lifecycle tests this phase).
* real Guardian with an invalid token → honest failure, no leak:
  **PASS** (`TestLifecycleRealGuardianRejectsFakeToken`).
* real Guardian with a VALID entitlement: **BLOCKED** — no Firefox
  account/entitlement exists in this environment; per the honesty
  decree this is recorded as BLOCKED, never simulated.

### Security
* tokens only on the stdin pipe; argv/env/stdout(other
  events)/stderr/logs/plain files NEVER: **PASS** (engine
  `internal/redact` + `carriesSecrets` routing + the bare-spawn test).
* Keystore vault at rest (AES/GCM, non-exportable key), corrupt vault →
  ABSENT + wipe: **PASS** (vault test group; on-device Keystore itself:
  **NOT TESTED** — no Android device in this environment).
* port map 1819/1820/1821 untouched, 1822 loopback-only + runtime
  busy-check: **PASS** (port-map tests + `firefoxPortBusy` walk).

### Lifecycle
* 9-state machine, cancel-during-start (22 s adversarial), port busy,
  bad config (3 subtests), quota exhaustion mapping, renewal timeout
  mapping, engine death while connected → health failure (store owns
  recovery): **PASS** (6 Go lifecycle tests + 20 Dart firefox tests;
  full AETHONE suite 262 tests green, `flutter analyze` clean).

### On-device (real Android)
* **NOT TESTED** — no device/emulator in this environment. The
  `useLegacyPackaging` extraction, `nativeLibraryDir` exec, VpnService
  tunnel path, and Zeptun compatibility are design-verified +
  code-reviewed and covered by the same contracts as the M2 engines,
  but Phase 1 records them as NOT TESTED until a device run exists.

## 4. Real-traffic verification (the 6-level ladder)

| Level | Status |
|---|---|
| 1 Process started | **PASS** (real binary, real wire) |
| 2 Listener ready | **PASS** (engine's own `socksReady` event) |
| 3 SOCKS5 handshake | **PASS** |
| 4 CONNECT | **PASS (local harness)** / real Fastly: session-level **PASS** |
| 5 Data transfer | **PASS (local harness)**; real Fastly payload — **BLOCKED** (needs entitlement) |
| 6 Exit IP verified through the tunnel | **BLOCKED** — requires a real entitlement; the engine's own exit probe HONESTLY failed in the real-Fastly test (`exitVerifyFailed`), exactly as designed |

No `Connected` state was ever declared from mock data: the adapter's
probe is the sole gate, and it never ran against a fake upstream in a
way that would count as connectivity.

## 5. Limitations and open items

1. Real entitlement testing (levels 5–6 + quota paths) is BLOCKED; the
   controlled-injection path (`FirefoxSessionInjector`) is ready for
   the owner's real session pair when provided.
2. On-device verification NOT TESTED (see matrix).
3. The phase-2 UI (location picker, login, tiles) is deliberately
   absent; the discovery model exposes everything it needs.
4. License UNRESOLVED: everything stays on the private branch /
   private mirrors; nothing pushed, no public artifact.

## 6. Phase-2 readiness

Ready: wire contract v1 (`ConfigVersion 1`, `EngineVersion
1.0.0-phase1`), the discovery model + labeled cache, the vault +
injection path, the adapter walk, the 12-mode transport table, the
l10n rows. Phase 2 (UI + login/WebChannel) can bind to
`FirefoxDiscovery.refresh()` / `FirefoxSessionStore` /
`_connectFirefox` without touching the engine contract.
