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
round 2 closed to the sandbox's limits — toolchain exact, 3 of 4 native stages
PASS, PoC debug APK DELIVERED; aether RAM-blocked (D18); device round Blocked
(no device). Stage 3 (UI): FORBIDDEN until the owner accepts the evidence and
the device gate closes.

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
- PoC APK: `AETHONE-PoC-Stage2.1-arm64-debug.apk` — 73 988 586 B, sha256
  `53ff2a778900f24d0d76140658c1d29e2834e513f0a72709cf8e38339bdd080b`, package
  `com.chakcaad.aethone.da`, arm64-v8a only, 8 native libs, in-APK
  libzeptun-jni.so exports the PoC symbols, zipalign -P 16 + apksigner PASS.
  jniLibs = 3 local builds + libaether.so from the same-pin CI artifact (D18);
  final zip assembled from gradle's own green intermediates (D19).

## Key files / entry points

- Docs (all in `docs/features/per_app_routing/`): POC_RESULTS.md (full evidence
  + device procedures), PROGRESS.md, DECISIONS.md (D1–D19), ARCHITECTURE.md (§8
  = as built).
- Native patch: `native/zeptun/` (config.zig, engine.zig, verdict.zig, tcp/udp.zig,
  jni/zeptun_jni.c, tests/route_tests.zig). Do NOT commit `.zig-cache/`/`zig-out`.
- Kotlin: `PerAppRouteResolver.kt`, `PoCRoutes.kt`, `PoCRoutesReceiver.kt`,
  `AethoneVpnService.kt` (EXTRA_POC_ROUTES / flowRoute), `dev/zeptun/Zeptun.kt`.
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

Install the delivered APK (debug-signed — enable "install unknown apps"),
connect via adb, then follow POC_RESULTS.md §Device procedure (Tests A–H) and
record results back into POC_RESULTS.md with the five-state vocabulary. On a
normal-disk host the canonical rebuild is:

```sh
# after staging jniLibs as in POC_RESULTS §round 2:
flutter build apk --debug --target-platform android-arm64
```
