# Per-App Routing — PROGRESS

## Current phase

**Stage 2.1 round 2 complete to the sandbox's disk/RAM limits.** The exact-pin
toolchain is installed and verified; zeptun, lyrebird and psiphon build PASS
(zeptun through the fixed wrapper; the Go stages via the script's exact commands
after the fail-fast aether abort); aether is RAM-blocked (deterministic OOM,
D18); the PoC debug APK (arm64-v8a, DA variant) is built, gated and DELIVERED.
Device round: Blocked (no device). Stage 3 (UI) must not start until the owner
accepts the evidence and the device gate closes.

## Repository state

- Working branch: `feature/per-app-routing-stage2-poc` (pushed to origin), cut
  from the audited baseline `5502d34` (fix/owner-round-2) + the Stage 2 commit
  `0583a34`; Stage 2.1 commits follow on top (see `git log`).
- Remote `fix/owner-round-2` had advanced to `d9bcd64` before the branch was cut
  — merging that line is a separate owner decision (likely conflicts in
  AethoneVpnService.kt).
- Vendored `native/zeptun/` = pin 08a1ab0 + the Stage 2 patch (never commit
  `.zig-cache`/`zig-out` inside it).

## Verified results (latest first — Stage 2.1 round 2, 2026-11-18)

1. Toolchain at the exact pins, all §4 checks green (Flutter 3.47.9 via the
   LOCAL_BUILD_FA git-clone method, commit == the official archive hash; JDK
   Temurin 17.0.21+9; SDK platform 36 / build-tools 36.0.0 / platform-tools;
   NDK r26d sha1-verified; Rust 1.99.1 + cargo-ndk 4.1.2; Go 1.26.3
   GOTOOLCHAIN=local; Zig 0.16.0 workflow-sha256-verified; cmake 3.31.6 +
   libclang 18.1.1 for the boring-sys host path).
2. Wrapper safety suite re-run: 0 FAIL ("ALL CHECKS PASSED").
3. Native build (arm64-v8a, API 29, taskset 2 CPUs, dedicated src-cache/out):
   - zeptun **Pass** — 3 exported files, both new symbols in both .so files,
     16 KiB alignment, export guard.
   - aether **Blocked (RAM)** — 3× kernel OOM on the same rustc unit (in-tree
     quiche, fat-LTO): ~3.44 GB anon RSS vs 3.95 GB total; scheduling-only
     mitigations exhausted; output-changing ones rejected (D18).
   - lyrebird **Pass** — proxy path: sum.golang.org h1 + official-Go-client
     signed-record verification + zip byte-identity; **real defect found (D17)**:
     the proxy path's `rm -rf` of Go's read-only module cache aborts the build
     after verification — proposed fix recorded, environment-level fallback used.
   - psiphon **Pass** — **byte-identical to the CI artifact** of run 44086964453
     (sha256 a26424ea…), a direct reproducibility proof.
4. PoC debug APK **delivered** — `AETHONE-PoC-Stage2.1-arm64-debug.apk`
   (73 988 586 B, sha256 53ff2a77…): package `com.chakcaad.aethone.da`, label
   AETHONE DA, arm64-v8a only, all 8 native libs present, in-APK
   libzeptun-jni.so exports `zeptun_update_routes`/`zeptun_set_flow_callback`/
   `JNI_OnLoad`, zipalign -P 16 PASS, apksigner (debug) PASS. jniLibs: 3 local
   builds + libaether.so from the project's own same-pin CI artifact (D18);
   final packaging assembled from gradle's own green intermediates (D19).
5. Device round: `adb devices -l` → none; Tests A–H **Blocked (no device)**.

## Remaining

- [ ] Owner review of POC_RESULTS.md (Stage 2 + both Stage 2.1 rounds).
- [ ] Device round Tests A–H on a real Android 10+ phone (procedures:
      POC_RESULTS.md §Device procedure; the APK is delivered).
- [ ] Decision: fix D17 upstream (chmod before rm) — first real proxy-path run.
- [ ] Decision: fork-pin the patched zeptun or upstream it (D14).
- [ ] Decision: merge/rebase onto the advanced fix/owner-round-2 (d9bcd64).
- [ ] (Owner host / ≥8 GB machine) canonical `flutter build apk --debug
      --target-platform android-arm64` — reproduces the delivered APK through
      gradle alone on a normal disk.

## Known blockers

- No physical Android device / adb in the build environment.
- aether cannot compile under 4 GB RAM (D18) — needs the owner host or CI.
- `dns.upstream` fixed at start: a live update cannot INTRODUCE a direct route
  without one present at start (restart required) — documented (D12).

## Next exact action

Owner: install `AETHONE-PoC-Stage2.1-arm64-debug.apk` (debug-signed, installs
beside the main app as AETHONE DA) on an Android 10+ arm64 device and run
POC_RESULTS.md §Device procedure (Tests A–H), recording results back into
POC_RESULTS.md with the five-state vocabulary. Stage 3 (UI) starts only after
the owner accepts the evidence.
