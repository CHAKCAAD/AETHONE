# Per-App Routing — SESSION HANDOFF

Read this FIRST each session, then PROGRESS.md, then only the relevant doc sections.
This file is a pointer, not a report. Update it after every milestone.

## Identity

- Repo: `CHAKCAAD/AETHONE` (local: `/home/z/my-project/_aethone`)
- Active branch: `feature/per-app-routing-stage2-poc` (pushed to origin)
- Base: `fix/owner-round-2` @ `5502d34` (the audited baseline) + Stage 2 commit
  `0583a34` + Stage 2.1 commits (script fix, Kotlin fix, docs — see `git log`)
- Branch URL: https://github.com/CHAKCAAD/AETHONE/tree/feature/per-app-routing-stage2-poc
- NOTE: remote `fix/owner-round-2` advanced to `d9bcd64` (rounds 11–12, Firefox
  retirement v2.1.0). This branch does NOT include those. Merge/rebase = owner
  decision; expect conflicts in AethoneVpnService.kt.

## Stage status

Stage 2 (core PoC): implemented, host-proven. Stage 2.1 (validation & handoff):
**Partially Successful (environment-bounded)** — see POC_RESULTS.md §Stage 2.1.
Stage 3 (UI): FORBIDDEN until the owner accepts the evidence and the device gate closes.

## Last valid results

- Host engine suite: 118/126 (8 pre-existing skips), baseline 109/117, zero regressions.
- Kotlin compile (real config, JDK 17.0.21 + Flutter 3.47.9 + Gradle 9.8.2/AGP 9.4.0/
  Kotlin 2.4.0, compileSdk 36): BUILD SUCCESSFUL after fixing one real defect
  (`PerAppRouteResolver.kt:198` out-of-scope `pkg` — D16).
- Wrapper safety tests: `bash scripts/test_build_native_poc.sh` → 24/24 PASS.
- PoC native build (arm64-v8a, NDK r26d, Android 29): zeptun stage PASS —
  `zeptun_update_routes` + `zeptun_set_flow_callback` verified by `nm -D` in BOTH
  .so files; aether stage blocked (`cargo: command not found`) → no APK in sandbox.

## Key files / entry points

- Docs (all in `docs/features/per_app_routing/`): POC_RESULTS.md (evidence + device
  procedures), PROGRESS.md, DECISIONS.md (D1–D16), ARCHITECTURE.md (§8 = as built).
- Native patch: `native/zeptun/` (config.zig, engine.zig, verdict.zig, tcp/udp.zig,
  jni/zeptun_jni.c, tests/route_tests.zig). Do NOT commit `.zig-cache/` or `zig-out/`
  inside it (untracked build dirs live there).
- Kotlin: `PerAppRouteResolver.kt`, `PoCRoutes.kt`, `PoCRoutesReceiver.kt`,
  `AethoneVpnService.kt` (EXTRA_POC_ROUTES / flowRoute), `dev/zeptun/Zeptun.kt`.
- Build: `scripts/build_native_poc.sh` (fixed wrapper — D15 invariant) +
  `scripts/test_build_native_poc.sh`; `build_native.sh` ZEPTUN_LOCAL_SRC gate.

## Critical constraints

- Default supply chain untouched: `build_native.sh` without ZEPTUN_LOCAL_SRC builds
  the frozen pin; PoC APK must use the WRAPPER, never the plain script.
- Route 0 = default handler; routes 1..N positional per `[routes]` doc order.
- Direct + fake_ip requires `dns.upstream`; live update cannot INTRODUCE direct
  without a start-time upstream (D12). Unattributed/failed → DEFAULT route, never
  another app's route; dead assigned route → fail-closed (D6/D11).
- No per-route SOCKS5 credentials, no per-route UDP mode, no parallel engines (D9);
  IPv6 unchanged (D8). API 24–28: no attribution query, default route.
- Vendored tree diverges from pin 08a1ab0 — fork-pin decision (D14) still open.

## Done (Stage 2.1)

Branch cut from the audited baseline; Stage 2 changes committed+pushed (`0583a34`);
both wrapper safety defects confirmed+fixed+tested; Kotlin compile closed (one real
defect fixed); JNI signatures + Android binary symbols verified; zeptun stage of the
PoC build proven; docs updated (POC_RESULTS §Stage 2.1, PROGRESS, D15/D16,
ARCHITECTURE §8.7 addendum); this handoff created.

## Remaining / blockers

- Full 4-stage PoC build + APK: BLOCKED in the sandbox (needs Rust 1.99.1 +
  cargo-ndk 4.1.2 + Go 1.26.3; run on CI or the owner host).
- Device round Tests A–H: BLOCKED (no device/adb). Procedures: POC_RESULTS.md
  §Device procedure + §Stage 2.1 matrix. Emulator results do NOT count.
- Owner decisions pending: accept evidence / fork-pin (D14) / merge d9bcd64.

## Next exact command (on a full-toolchain host)

```sh
ANDROID_NDK_HOME=<r26d> ZIG=<zig-0.16.0> scripts/build_native_poc.sh \
  --abi arm64-v8a --rust-target aarch64-linux-android --goarch arm64 \
  --api-level 29 --src-cache .srccache --out out/arm64-v8a
```
then repeat for armeabi-v7a / x86_64, stage all outputs as jniLibs, assemble the DA
debug APK per the android-debug workflow, install on an Android 10+ device, and run
POC_RESULTS.md §Device procedure (Tests A–H). Record results back into POC_RESULTS.md
with the five-state vocabulary. Then update this file.
