# FIREFOX VPN — Phase B report (application-layer integration)

Branch `phase2/firefox-vpn-ui`, base `c148968` (the Phase 2 tip).
Delivered 2026-11-09. **Stopped at the end of Phase B; nothing pushed
publicly, no release, Phase C (whatever the owner decrees) awaits
explicit approval.**

The Phase B decree had three parts: (1) Firefox joins the
ProtocolPage through the STANDARD protocol path — no parallel channel;
(2) the error chain Go → JSON → Dart process manager → service/state →
UI is classified (DNS / network unavailable / timeout / TLS / session
rejected / token exchange / invalid token response / server rejection /
unknown), type-based on the Go side, real HTTP status codes, no token
ever in a user-visible message; (3) the OAuth response is validated
(both tokens present, string-typed, non-empty, non-blank — no invented
token format).

## A. Repository state (verified before any change)

* Private repo `CHAKCAAD/aethonepriv`, branch `phase2/firefox-vpn-ui`:
  local HEAD = `origin/phase2/firefox-vpn-ui` = **`c148968`** ("phase-2
  … the login doc, the phase-2 report, the engine/security/android
  updates"), working tree clean. No commits beyond `c148968` existed on
  any branch.
* The public repo `CHAKCAAD/AETHONE` was NOT touched (read-only
  throughout; the decree).
* **A1 (the 2026-11-08 real-device login fix — ARM64 engine built with
  CGO) is NOT versioned in this repo.** The `fxv` engine tree (upstream
  pin `55ad91a2…` + `cmd/libfirefoxvpn`) lives outside the app repo
  ("outside the app repo (private)", per the Phase 2 report) and was
  not present in this workspace either. What IS versioned: the
  `device-acceptance` branch (`19918c1`, the DA layer — the standalone
  test package `com.chakcaad.aethone.da`, the redacted DA log, the
  https-only origin gates; 280/280 green at its time). The Nov-8
  logcat (owner-supplied) then showed the SAME exchange step failing
  with a DNS-class chain on a pure-Go-resolver signature (`[::1]:53`) —
  whether that build carried the A1 CGO config cannot be judged without
  the engine tree; recorded as open item G1. The A1 build config itself
  is now written into the patch README (§F) so it cannot be lost again.

## B. UI changes (Part 1 — Firefox joins the ProtocolPage)

All through the standard path — the same enum, the same single-knob
selection, the same persistence, the same engine walk:

* `lib/core/design_tokens.dart` — new `protoCardTopFirefox` (725 = the
  Tor card's 594 + 116 + 15, the family cards' own rhythm) and
  `protoPageContentH` (1005): the page's content column grows by the
  Firefox card's slot and scrolls. The DEVICE frame constant
  (`refHeight` 874, the pattern composition's anchor) is UNTOUCHED;
  the scan section shifts +131 with its own rhythm (heading 736 → 867,
  pills 776 → 907).
* `lib/features/home/protocol_sheet/protocol_sheet.dart` — the
  `_FirefoxAccountCard`: the third full-width card after Tor, the
  FamilyCard chrome (h116 r21) as a single-member card. The main block
  (glyph + «فایرفاکس») mirrors the family cards exactly; the right zone
  carries a **read-only account-state chip** fed by the SAME
  `ConnectionStore.firefoxAccount` surface the Firefox settings page
  uses («حساب فایرفاکس متصل است / متصل نیست»; `unknown` renders as the
  signed-out wording, the settings page's convention). The card's ONLY
  action is the standard selection tap — commit `firefoxOnly` + pulse +
  auto-pop. No new service, no new process, no login shortcut (signing
  in stays on the existing login screen / settings page).
* Nothing else on the page moved: the tile grid, the family cards, the
  segments and the pills keep their token positions (the regression
  tests pin them).
* The card logo renders through the existing `ProtocolGlyph` /
  `AppAssets.protocolIcon(firefoxOnly)` mapping — the app's own icon
  set (Shield Tick), the SAME documented stopgap the Firefox settings
  pill has used since Phase 2 (open item G2: the owner's Firefox
  artwork has not been delivered; no emoji, no invented icon, no
  material icon, no placeholder box).

Selection semantics (all pre-existing, now proven for Firefox by
tests): single knob — selecting `firefoxOnly` releases any family
member; a plain tile releases it back; the selection alone NEVER claims
a connection (the state machine stays `disconnected` until the
engine's own effective events — asserted in the new tests).

## C. Error-classification changes (Part 2 — the full chain)

Contract first (documented BEFORE the change, extended additively):
the `failed` event keeps every 1.1.0 field; `failCode` additionally
carries the granular classes; OPTIONAL `httpStatus` (the REAL status
code) and `retryable` fields join; the raw Go chain stays out of the
UI forever. Docs updated: `FIREFOX_VPN_LOGIN.md` §3 (error semantics),
`FIREFOX_VPN_ENGINE.md` (the event list).

* **Go (engine side) — `docs/phaseb-engine-patch/`**: the complete,
  test-verified classifier + token guard (`fferr` package), with the
  placement checklist for the engine rebuild session. Discrimination
  is TYPE-BASED (`errors.As` on `*net.DNSError`, TLS/x509 verification
  errors, `net.Error.Timeout()`, `*net.OpError`, `context.DeadlineExceeded`)
  — never string matching. HTTP failures carry the real status (401/403
  → `sessionRejected`; 4xx → `serverRejection` non-retryable; 5xx →
  retryable). The base test replays the owner's EXACT 2026-11-08 chain
  over a real `[::1]:53` refusal → `dnsError`, retryable=true. NOT
  applied to the engine binary (the `fxv` tree is absent — §F/G).
* **Dart (applied, green):**
  * `lib/connection/firefox/firefox_errors.dart` (new) —
    `FirefoxErrors.classify` (new classes + the legacy `exchangeFailed`
    → `tokenExchange`, flagged `legacy`; unknown/empty codes → the
    generic class, never a throw), `diagnostic` (static, value-free
    English for the failure-details sheet), `invalidPairReason` (the
    Part 3 guard), `redactLine` (hex/base64ish token runs masked).
  * `firefox_protocol.dart` — the event parser reads the new fields
    tolerantly (wrong-typed extras degrade, never throw; the token
    fields' reads are hardened the same way — a hostile response
    cannot crash the process managers).
  * `firefox_login.dart` / `firefox_engine.dart` — every diagnostics
    line goes through `redactLine`; the outcome carries
    `httpStatus`/`retryable` through.
  * `platform_engine_adapter.dart` — the classified failure seam: the
    raw chain goes to the redacted diagnostics log ONLY; the store gets
    `firefoxTransport:<class>` + the static diagnostic (the old seam
    put the raw engine message into the user-visible details sheet);
    the quota case keeps its own code with a de-interpolated message.
  * `firefox_login_screen.dart` — `_failureText` maps by CLASS to the
    localized static text (8 new keys × 5 locales); unknown codes get
    the generic text; the engine's `message` is never rendered. The
    app-level `loginTimeout`/`sessionTokenInvalid` keep their existing
    specific texts.

## D. OAuth response validation (Part 3)

* **Engine side (the patch)**: `fferr.ValidateTokenResponse` — success
  requires BOTH `access_token` and `refresh_token` present as JSON
  strings, non-empty, non-blank (Unicode whitespace); every violation
  is its own typed `GuardError` with a static, value-free reason
  (missing / null / wrong type / empty / blank); no token format is
  invented or checked. A rejected pair emits `invalidTokenResponse`
  through the same event shape, so Dart treats it like any other class.
* **Dart side (applied, defense in depth)**: the login client guards
  `loginCompleted` — a broken pair resolves the attempt as
  FAILED(`invalidTokenResponse`), never completed, and a clean child
  exit cannot mask it (proven by the fixture-child test); the engine
  guards `authRefreshed` the same way — a broken refresh NEVER
  overwrites the vault's live pair. Tokens still travel only on the
  stdin pipe; the pair only on the secret event; the redaction sets
  cover every diagnostics path (test-verified with sentinel values).

## E. The three commands — REAL results (2026-11-09, this workspace)

Toolchain: Flutter 3.47.9 stable (the project pin; fresh install),
Dart 3.13.7, Go 1.22.5 linux/amd64.

```
$ flutter analyze
Analyzing repo_priv... No issues found! (ran in 2.8s)

$ flutter test
02:00 +302 ~8: All tests passed!
  (302 passed, 8 skipped — the 8 are the REAL-host-binary tests in
  firefox_engine_test + firefox_login_test: the engine binary is not
  present in this workspace; the skip is each suite's own honest
  guard, unchanged. Baseline at c148968: 288 green in the Phase 2
  session (280 runnable here + those 8). Net +22: 19 new
  firefox_errors tests, 3 new ProtocolPage tests. NO existing test
  was deleted or disabled; two assertions were UPDATED with reasons —
  design_tokens_test refHeight stays 874 + gains the new tokens;
  the protocol_sheet pill test scrolls to the pills, which now sit
  below the fold of the grown page — same assertions otherwise.)

$ cd docs/phaseb-engine-patch/fferr && go vet ./... && go test ./... -count=1
vet: OK
ok  aethonepriv/docs/phaseb-engine-patch  2.021s
  (7/7 tests: the Nov-8 chain replay, real timeout, real self-signed
  TLS, real TCP refusal, the HTTP status matrix, the 8-case token
  guard + acceptance, no-leak sentinels, unknown fallbacks)
```

## F. Build (the experimental Debug APK) — BLOCKED in this workspace, honestly

No APK was built here, and no APK claim is made. The blockers, all
verified, not assumed:

1. **No engine binaries**: `jniLibs` are gitignored by design (M2) and
   the `fxv` engine tree + its build outputs are not in this
   workspace; an APK without `libfirefoxvpn.so` would be a false
   deliverable.
2. **No Android SDK/NDK** in this sandbox (Flutter alone was installed
   this session); the A1 CGO arm64 build needs NDK r28c's
   `aarch64-linux-android34-clang`.
3. The A1 fix itself is not versioned anywhere reachable (§A).

The rebuild recipe (for the session that has the `fxv` tree + NDK):
apply `docs/phaseb-engine-patch/` per its README (including the **A1
decree: arm64 with CGO_ENABLED=1 + the NDK clang CC** — a `CGO=0`
arm64 rebuild would regress the real login), `go vet && go test` in
the engine tree, the 3-ABI rebuild + ELF inspection + jniLibs
hash-verified deploy (the Phase 2 recipe), then the DA-pattern
`assembleDebug` with a distinct applicationId (the `com.chakcaad.aethone.da`
precedent on the `device-acceptance` branch), recording SHA256 + size
and verifying the ARM64 binary inside the archive.

## G. Open items (for the owner)

1. **The engine rebuild** (the C-side of Part 2/3): the `fxv` tree
   must reappear (owner's machine or a shared location) for the patch
   to be applied and the granular codes to reach real devices — until
   then the Dart side maps the legacy `exchangeFailed` safely (tested),
   and the open A1 question (did the Nov-8 DA build carry the CGO
   config?) stays unanswered without it.
2. **The Firefox protocol artwork** — the owner's own Firefox logo/SVG
   has never been delivered; the card uses the app's Shield Tick via
   the existing `protocolIcon` stopgap (one-line swap when the artwork
   lands, `AppAssets.protocolIcon`).
3. On-device verification of the new card + the classified failures
   (the DA branch's test ladder is the natural vehicle) — NOT TESTED
   here (no device).
4. The scan section now sits below the fold on 874-logical viewports
   (the page scrolls); if the owner prefers a compact page instead,
   that is a design decision to decree.
