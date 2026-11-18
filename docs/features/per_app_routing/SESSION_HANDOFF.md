# Per-App Routing — SESSION HANDOFF

Read this FIRST each session, then PROGRESS.md, then only the relevant doc sections.
This file is a pointer, not a report. Update it after every milestone.

## Identity

- Repo: `CHAKCAAD/AETHONE` (owner checkout: `/home/z/my-project/_aethone`;
  Stage 2.1 build worktree: `/home/z/my-project/aethone-stage21` on this host)
- Active branch: `feature/per-app-routing-stage2-poc` (pushed to origin)
- Base: `fix/owner-round-2` @ `5502d34` + Stage 2 `0583a34` + Stage 2.1 commits
  (script fix D15, Kotlin fix D16, docs, and the round-2 evidence — see `git log`)
- Branch URL: https://github.com/CHAKCAAD/AETHONE/tree/feature/per-app-routing-stage2-poc
- NOTE: remote `fix/owner-round-2` advanced to `d9bcd64` (rounds 11–12). This
  branch does NOT include those. Merge/rebase = owner decision.

## Stage status

Stage 2 (core PoC): implemented, host-proven. Stage 2.1 (validation & handoff):
round 4 closed — the device-test entry point FIXED (the round-0 procedure's
direct `am start-foreground-service` on the non-exported service was
impossible; replaced by the debug-only `PoCControlActivity`, D20),
automated-tested 24/24, manifest+dex verified in the DA debug APK and
absent from the release variant; the round-4 PoC debug APK is DELIVERED
(round-4 key); device round Blocked (no device). Stage 3 (UI): FORBIDDEN
until the owner accepts the evidence and the device gate closes.

## Last valid results

- Host engine suite: 118/126 (8 pre-existing skips), baseline 109/117, zero regressions.
- Kotlin compile (JDK 17.0.21 + Flutter 3.47.9 + Gradle 9.8.2/AGP 9.4.0/Kotlin 2.4.0):
  BUILD SUCCESSFUL (D16 closed).
- Wrapper safety suite: 0 FAIL (all checks green), re-verified in round 2.
- Native (arm64-v8a, API 29, NDK r26d, Zig 0.16.0, Go 1.26.3): zeptun PASS
  (new symbols in both .so); lyrebird PASS (sumdb + Go-client verified proxy
  path; D17 defect found + proposed fix); psiphon PASS — byte-identical to CI
  artifact 14329444462 (run 44086964453); aether BLOCKED — 3× OOM at ~3.44 GB
  anon RSS on the 3.95 GB host (fat-LTO quiche unit; D18).
- PoC APK (round 4, CURRENT DELIVERABLE): `AETHONE-PoC-Stage2.1-arm64-debug.apk`
  — 74 073 078 B, sha256
  `83bd544cc804c7592464cdde97b3715d799f353c7052472308b3dbafd5340e5e`, package
  `com.chakcaad.aethone.da`, arm64-v8a only, 8 native libs, in-APK
  libzeptun-jni.so exports the PoC symbols, zipalign -P 16 + apksigner PASS
  (round-4 debug keystore — each recycled sandbox needs a fresh key).
  Round-4 additions: `PoCControlActivity` in the merged manifest (exported,
  explicit-component-only) and in the dex; `AethoneVpnService`
  exported=false + BIND_VPN_SERVICE unchanged; receiver actions intact.
  `:app:testDebugUnitTest` 24/24 (PoCControlStartSpecTest). jniLibs = the
  round-3 APK's exact bytes (hash-verified re-staging); final zip = repack
  of gradle's own valid APK (D19 round-4 edition). Rounds 2/3 records stay
  in POC_RESULTS.md.

## Key files / entry points

- Docs (all in `docs/features/per_app_routing/`): POC_RESULTS.md (full evidence
  + device procedures), PROGRESS.md, DECISIONS.md (D1–D20), ARCHITECTURE.md (§8
  = as built).
- Native patch: `native/zeptun/` (config.zig, engine.zig, verdict.zig, tcp/udp.zig,
  jni/zeptun_jni.c, tests/route_tests.zig). Do NOT commit `.zig-cache/`/`zig-out`.
- Kotlin: `PerAppRouteResolver.kt`, `PoCRoutes.kt`, `PoCRoutesReceiver.kt`,
  `AethoneVpnService.kt` (EXTRA_POC_ROUTES / flowRoute / currentPocToken),
  `dev/zeptun/Zeptun.kt`. Debug-only round-4 files:
  `android/app/src/debug/kotlin/…/PoCControlActivity.kt` +
  `PoCControlStartSpec.kt`, declared in `android/app/src/debug/AndroidManifest.xml`;
  tests: `android/app/src/testDebug/kotlin/…/PoCControlStartSpecTest.kt`
  (test-only deps junit + org.json in app/build.gradle.kts).
- Build: `scripts/build_native_poc.sh` (fixed wrapper — D15 invariant) +
  `scripts/test_build_native_poc.sh`; `build_native.sh` ZEPTUN_LOCAL_SRC gate.
- Build-host tooling (NOT in the repo, on the sandbox): `/home/z/my-project/.toolchain/`
  (`per-app-routing-stage2.env` = the exact-pin environment; `evidence/` = logs
  + hashes; reinstall scripts under `/home/z/my-project/scripts/stage21/`).

## Critical constraints

- Default supply chain untouched: `build_native.sh` without ZEPTUN_LOCAL_SRC builds
  the frozen pin; the PoC APK must use the WRAPPER, never the plain script.
- Route 0 = default handler; routes 1..N positional per `[routes]` doc order.
- Direct + fake_ip requires `dns.upstream`; live update cannot INTRODUCE direct
  without a start-time upstream (D12). Unattributed/failed → DEFAULT route;
  dead assigned route → fail-closed (D6/D11).
- No per-route SOCKS5 credentials, no per-route UDP mode, no parallel engines (D9);
  IPv6 unchanged (D8). API 24–28: no attribution query, default route.
- Vendored tree diverges from pin 08a1ab0 — fork-pin decision (D14) still open.
- aether needs >4 GB RAM to compile (D18); the sandbox is 3.95 GB.

## Done (Stage 2.1 round 4)

Device-test entry point fixed per the owner's task: debug-only
PoCControlActivity implemented (validation + consent gate + same-UID service
start + AethonePoC logging incl. the token); 24/24 unit tests; DA debug +
release variants built on the exact-pin toolchain and verified (activity in
the DA manifest/dex, absent from release; service posture and receiver
unchanged); gated PoC APK re-assembled and delivered (round-4 key); device
procedure corrected in POC_RESULTS.md; docs updated; committed+pushed.

## Done (Stage 2.1 round 3)

Sandbox recycle recovery: exact-pin toolchain reinstalled (Flutter 3.47.9 clone
@ tag c197ca5199, JDK 17.0.21+9, SDK 36/36.0.0, NDK r28c); worktree + env file
re-created; jniLibs re-staged hash-gated; full gradle build re-run (daemon
sized for the host via GRADLE_USER_HOME — env-level); APK re-assembled, all
gates PASS, re-delivered; docs updated; committed+pushed on the feature branch.

## Done (Stage 2.1 round 2)

Exact-pin toolchain installed + verified (all §4 checks); wrapper suite green;
zeptun/lyrebird/psiphon stages PASS (Go stages via the script's exact commands
after the aether abort — documented); D17 proxy-path defect found + fix proposed;
APK built from gradle's green intermediates, all project gates PASS, delivered;
docs updated; everything committed+pushed on the feature branch.

## Remaining / blockers

- Device round Tests A–H: BLOCKED (no device/adb in the environment). The APK
  is delivered for the owner's hardware round.
- aether compile on this host: BLOCKED (RAM, D18) — owner host or CI only.
- Owner decisions pending: accept evidence / fix D17 / fork-pin (D14) /
  merge d9bcd64.

## Next exact command (owner's device round)

Install the delivered round-4 APK (debug-signed — enable "install unknown
apps"), connect via the app UI ONCE (grants the VPN consent), then follow the
CORRECTED POC_RESULTS.md §Device procedure (Tests A–H) — the PoC session is
armed through the new entry point:

```sh
adb shell am start -n com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity \
  --ei port 1819 --es poc_routes '<route-start document>'
# then POC_UPDATE_ROUTES / POC_ROUTES_STATS with the token from: adb logcat -s AethonePoC
```

On a normal-disk host the canonical rebuild is:

```sh
# after staging jniLibs as in POC_RESULTS §round 2:
flutter build apk --debug --target-platform android-arm64
```
