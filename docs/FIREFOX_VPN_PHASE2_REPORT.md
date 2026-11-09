# FIREFOX VPN — Phase 2 report (private branch `phase2/firefox-vpn-ui`)

Scope delivered: the sign-in loop Phase 1 left to the controlled
injection — the FxA **WebChannel browser login** (Mozilla's own page in
an embedded WebView, the password never entering the app), the engine's
**`--login` role** (the session-token → OAuth-pair exchange through the
pinned upstream control plane), the account UI state (sign-in /
sign-out on the new Firefox settings page), the **exit-location picker**
(the live RemoteSettings list through the home wheel + the settings
page), and the **data-plane transport pick** (h2/h3). Still out of
scope by decree: Linux/Windows, public release, aether chaining.
**License UNRESOLVED — everything stays private; nothing pushed, no
public artifact. Stopped at the end of Phase 2; Phase 3 (whatever the
owner decrees next) awaits explicit approval.**

## 1. What changed

New (`lib/connection/firefox/`, 820 lines; `lib/features/settings/`,
~640 lines):

* `firefox_web_channel.dart` — the pure-Dart WebChannel bridge + the JS
  hook (ADAPTED from FoxyVPN's MIT `BrowserLoginScreen.kt`; Mozilla's
  message protocol; the `aethoneFxChannel` / `__aethoneFxReply` names).
* `firefox_login.dart` — `FirefoxLoginClient`: spawns the `--login`
  child (bare argv, empty env), the token on stdin only, the pair on
  the secret event only, clean cancel (stdin close → 3 s grace → kill).
* `firefox_login_screen.dart` — the in-app sign-in page (WebView,
  Mozilla-only navigation, status strip, cookie hygiene on success).
* `firefox_page.dart` — the Firefox settings page: account, exit
  location (live/cached labeled), transport.
* `test/firefox_login_test.dart` — 26 tests (bridge mapping, wire
  protocol, wheel policy, store surface, the REAL host binary).

Modified (additive, reversible): `firefox_protocol.dart` (+the login
events, `FirefoxLoginResult`, redaction rules), `engine.dart`
(+`EngineFirefoxLocations` event, +the firefox surface on
`EngineAdapter`/`EngineConfigSource`), `connection_store.dart`
(+`firefoxLocation`/`firefoxTransport`/`liveFirefoxCountries`/
`firefoxAccount` + the wheel routing + sign-out), `transport_modes.dart`
(+the firefox wheel branch, +`firefoxCountrySnapshot` — the phase-0
33-country seed), `platform_engine_adapter.dart` (+`firefoxWebChannelLogin`
and friends; the connect now feeds the location/transport picks),
`settings_persistence.dart` (+2 keys), `settings_screen.dart` (+the
Firefox pill row), `settings_controls.dart` (+`SettingActionButton`),
`app_strings.dart` (+26 keys × 5 locales fa/en/ru/zh/tk), `pubspec.yaml`
(+`webview_flutter 4.14.1`).

Outside the app repo (private): `fxv/cmd/libfirefoxvpn/login.go` +
`login_test.go` + `login_exchange_test.go`,
`fxv/internal/engine/login_config.go`, `fxv/internal/engine/events.go`
(+3 login events), `fxv/ORIGIN.md` (the Phase-2 provenance section),
`EngineVersion 1.1.0-phase2`, the rebuilt 3-ABI binaries +
`SHA256SUMS.txt`, the jniLibs re-deploy (hash-verified ≡ build).

## 2. Toolchain and pins

Identical to Phase 1 (recorded, reproducible): upstream core
`55ad91a2ccea1c93e69c82a08a7681e279884db5`, Go 1.25.0, NDK r28c
(28.2.13676358), Flutter 3.47.9, JDK 21.0.13+9 / Gradle 9.8.2. New pin:
`webview_flutter 4.14.1` (first-party, BSD-3-Clause — the only new app
dependency).

Rebuild: `phase1/scripts/build_engine.sh` — SHA256
`arm64-v8a 7954241b… · armeabi-v7a a6732e21… · x86_64 aa3c444f… ·
host aa383c39…`; jniLibs ≡ build per-ABI (hash compare).

## 3. Test matrix (honest labels only)

### Build
* 3-ABI `libfirefoxvpn.so` + host rebuild with the `--login` role,
  ELF/ABI verification, jniLibs ≡ build: **PASS**.
* Debug APK `assembleDebug` (7 m 30 s): **PASS** — the 3 engine ABIs
  carry the SAME Go BuildIDs as the pinned build (llvm-strip applies);
  the `webview_flutter_android` plugin is packaged.

### Login exchange (Go, `--login` role)
* Config validation (version/mode/token-shape/clamps): **PASS**
  (spawned-binary tests, the engine's own words).
* The exchange against a LOCAL TLS fake FxA with **HAWK VERIFIED**
  (HKDF-SHA256 derivation + MAC over the normalized request — proving
  the vendored derivation ran against OUR token): success, the
  pinned client-id/scope/grant body: **PASS (local harness)**.
* Unverified-session retry (errno 104 → 138 → success), leaky-body
  **redaction**, timeout, in-flight **cancel**: **PASS (local
  harness)**.
* The REAL FxA endpoint with a FAKE token → honest
  `sessionRejected`/`exchangeFailed`, no leak (Go + Dart sides):
  **PASS** (a real-network honesty test — never a claim of login).
* argv/env carry nothing; stdin EOF during the call cancels cleanly; no
  orphan: **PASS** (both languages).

### WebChannel bridge (Dart)
* Command mapping (`fxa_status`, `can_link_account`, `login`,
  `oauth_login`), the token capture (both field names, uppercase
  normalized), malformed-token refusal, the dedup guard, the origin
  gate (JS + Dart sides), the hook script contracts, the
  `fx_desktop_v3` login URL, the pinned Firefox-on-Android UA:
  **PASS** (pure mapping, recorded message shapes).
* The REAL page handshake inside the REAL WebView: **NOT TESTED** —
  needs a device and a live accounts.firefox.com session (no
  device/emulator in this environment).

### Store / policy / persistence
* `selectLocation` routing, the sanitizing setters,
  `applyFirefoxLocations` (swap + labels + garbage refusal), the wheel
  list (AUTO + live/seed), the 33-country phase-0 seed (sorted, no
  `cz`, no pseudo-countries), persistence round-trip (keys
  `aethone.settings.firefoxLocation/firefoxTransport`): **PASS**.
* Full AETHONE suite: **288 tests green** (262 phase-1 + 26 phase-2),
  `flutter analyze` clean.

### On-device (real Android)
* **NOT TESTED** — no device/emulator here. The WebView page load, the
  real WebChannel capture, `nativeLibraryDir` exec of the `--login`
  role, and the end-to-end sign-in are design-verified + code-reviewed
  and covered by the same contracts, but Phase 2 records them as NOT
  TESTED until a device run exists.

### Real account login (the full loop)
* **BLOCKED** — no Firefox account/entitlement exists in this
  environment (the phase-1 boundary). The flow is proven up to it:
  capture (mapping) → stdin pipe (real binary) → exchange (real
  endpoint, honest rejection) → vault (real store). A real sign-in run
  remains the owner's device test.

## 4. Security verification (the phase-1 decree, extended)

* The session token NEVER appears in argv, env, logs, events, or files
  — only the WebView→Dart channel (in-process) and the child's stdin
  pipe: **PASS** (Go + Dart tests; the leaky-body harness proves the
  redaction path).
* The minted pair lands ONLY on `loginCompleted` (the
  secret-carrying event, `carriesSecrets`-routed, `logLine` redacted)
  and in the Keystore vault: **PASS**.
* The bridge ignores non-Mozilla origins on BOTH sides (the JS hook
  checks before posting; Dart re-checks before parsing): **PASS**.
* One login child at a time; the dismissed page cancels it; no orphan:
  **PASS**.
* The password never transits AETHONE code — the sign-in happens on
  Mozilla's own page (architectural guarantee, documented in
  `FIREFOX_VPN_LOGIN.md` §4).

## 5. Limitations and open items

1. The real-device login run (WebView + live page + real account):
   NOT TESTED / BLOCKED (above).
2. The Firefox protocol icon is the placeholder shield until the
   owner's own Firefox artwork lands (the auto-globe precedent).
3. Account management UI is sign-in/sign-out only (vault presence);
   profile/subscription display was deliberately not wrapped.
4. The FxA login page is served by Mozilla in whatever locale the
   account/browser negotiates — the AETHONE-side chrome is localized
   (5 languages); the page itself is Mozilla's.
5. License UNRESOLVED: the private branch is the only home; the new
   `webview_flutter` dependency is BSD-3-Clause (compatible), but the
   ENGINE-derived parts stay private regardless.

## 6. Phase-3 readiness

Ready for whatever the owner decrees: the login loop and the location
pick are complete; the remaining BLOCKED items all need a real device
and/or a real entitlement. Natural candidates: the on-device matrix
run (the NOT TESTED rows), the owner's real-account login + the
levels-5/6 traffic proof Phase 1 left BLOCKED, the Firefox artwork,
and (if the license settles) the release/APK policy decision.
