# Per-App Routing — PROGRESS

## Current phase

**Stage 2.1 (Android validation & persistent handoff): done to the environment's
limit — see the verdict.** Stage 2 core PoC is implemented and host-proven; the
Stage 2.1 round added the script-safety fix, the first real Kotlin compile (one real
defect found + fixed), JNI verification, and the zeptun stage of the Android PoC
build. Stage 3 must not start until the owner accepts the evidence and the device
round closes the gate.

## Repository state

- Working branch: `feature/per-app-routing-stage2-poc` (remote: origin/CHAKCAAD/AETHONE)
  — created from the audited baseline `5502d34` (fix/owner-round-2) + the Stage 2
  working tree, commit `0583a34`; Stage 2.1 commits follow on top.
- Remote `fix/owner-round-2` has ADVANCED to `d9bcd64` (rounds 11–12: Firefox
  retirement v2.1.0, widget work). The PoC branch does NOT contain those rounds —
  merging them is a separate owner decision (likely conflicts in AethoneVpnService.kt).
- Vendored `native/zeptun/` = pin 08a1ab0 + the Stage 2 patch (untracked build caches
  `.zig-cache`/`zig-out` live inside it — never commit them).

## Verified results (latest first — Stage 2.1, 2026-11-18)

1. `build_native_poc.sh` safety: both owner-flagged defects CONFIRMED (exec kills the
   EXIT trap; the trap could `rm -rf` a caller-supplied `POC_SRC_CACHE`), FIXED
   (subprocess + preserved exit code; own-only `POC_SCRATCH_DIR` cleanup), and covered
   by `scripts/test_build_native_poc.sh` (24/24 green, toolchain-free).
2. Kotlin compile (real config: Gradle 9.8.2 wrapper, AGP 9.4.0, Kotlin 2.4.0,
   compileSdk 36, JDK Temurin 17.0.21, Flutter 3.47.9): first compile FAILED on a real
   Stage 2 defect (`PerAppRouteResolver.kt:198` — out-of-scope `pkg` reference in the
   bounded logging block); after a 6-line fix: **BUILD SUCCESSFUL** (all Stage 2
   classes emitted).
3. JNI: all five `external fun` signatures byte-match the `JNINativeMethod` table;
   `nm -D` on the ANDROID artifacts exports `zeptun_update_routes` +
   `zeptun_set_flow_callback` (both .so files).
4. Native PoC build via the wrapper: zeptun stage **Pass** (arm64-v8a, Android 29,
   NDK r26d, 16 KiB alignment, exactly 3 exported files); aether stage BLOCKED at
   `cargo: command not found` (no Rust/Go in the sandbox) → no APK here.
5. Stage 2 host suite (unchanged since): 118/126 (8 pre-existing skips), baseline
   109/117 — zero regressions.

## Remaining

- [ ] Owner review of POC_RESULTS.md (Stage 2 + Stage 2.1 sections).
- [ ] Full 4-stage PoC build + APK assembly on CI / owner host (needs Rust 1.99.1 +
      cargo-ndk 4.1.2 + Go 1.26.3; stage the PoC outputs as jniLibs per the
      android-debug recipe).
- [ ] Device round: Tests A–H (all Blocked — no device; procedures in POC_RESULTS.md
      §Device procedure and §Stage 2.1 device matrix), incl. resolver metrics.
- [ ] Decision: fork-pin the patched zeptun or upstream it (D14) — required before
      any production CI build of the PoC APK.
- [ ] Decision: merge/rebase onto the advanced fix/owner-round-2 (d9bcd64).

## Known blockers

- No physical Android device / adb in the analysis environment.
- No Rust/Go toolchains and insufficient disk/memory for the full 4-stage native
  build in the sandbox.
- `dns.upstream` fixed at start: a live update cannot INTRODUCE a direct route
  without one present at start (restart required) — documented (D12).

## Next exact action

Owner: review `POC_RESULTS.md`. To finish Stage 2.1 on hardware: build the PoC APK on
a machine with the full toolchain (`scripts/build_native_poc.sh` per ABI → stage
`<out>/<abi>/zeptun/*` + aether/lyrebird/psiphon outputs as jniLibs → the standard
android-debug recipe), install on an Android 10+ device, and run the §Device
procedure (Tests A–H), recording results back into POC_RESULTS.md. Stage 3 (UI)
starts only after the owner accepts the evidence.
