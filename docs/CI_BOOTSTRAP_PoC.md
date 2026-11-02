# AETHONE — CI Bootstrap PoC (Phase 2, report v4 bundle — **v4.2**)

**Status of this document:** the CI code is complete, pinned and locally
validated (bash -n, YAML/JSON parse, actionlint 1.7.7 on the delivered
workflow, artifact-flow simulation under `set -euo pipefail` with the corrected
ARM64 evidence path, inspect_elf.sh v4 over the real upstream files, and a LIVE
end-to-end lyrebird pin proof), but it has **never been executed on GitHub
Actions**.
Running it requires pushing it to the AETHONE repository; the analysis
environment has no repository access. Everything below marked *NOT TESTED*
stays *NOT TESTED* until the run log exists (decision N2/N6 discipline). No
claim of CI success or real-device results is made. **Every ELF inspected in
this bundle is an UPSTREAM release artifact — inspection/simulation, not a
real AETHONE build.**

## 0b. v4.2 change log (employer review of v4.1, 2026-11-01)

1. **Workflow integrity made self-evident inside the package** (item 1) —
   `.github/workflows/native-ci.yml` ships at its canonical path; sha256
   `ce2ef44b4ad093bec0ad4ca6f5882a7f7f8dbfee57d6ebb39e186437b8c19dfd`;
   actionlint 1.7.7 exit 0 on EXACTLY the file extracted from THIS ZIP;
   raw proof `evidence/zip_integrity_v42.txt`. (The v4.1 review could not see
   the file because a GUI re-packaging step dropped the hidden `.github`
   directory — beware of archivers that omit dot-files.) File content:
   **unchanged since v4**.
2. **SumDB method completed — official Go client** (item 2) — the curl lookup
   + h1 grep did NOT validate the record signature. Now: live explicit
   signed-record verification with the official Go client (go 1.26.3,
   `GOSUMDB=sum.golang.org`) + build-zip identity proof
   (`evidence/lyrebird_sumdb_goclient_verification.txt`), and the SAME
   mechanism added to `scripts/pt-build-pin.patch` **v4.2** (proxy path: fresh
   temp module + GOSUMDB + byte-identity of the build zip with the
   go-client-verified zip; fail-closed; local dirhash kept; pin
   `fc105a03c0e0` and pseudo-version UNTOUCHED — N8). `build_native.sh`
   `PT_PATCHED_SHA256` = `3fbee02f78a4613a1452c32037c78c9d3a51ea4cb84edd8c4ebe808c023c4b88`
   (patch v4.2 applied to the frozen pt-build.sh; `git apply` + `bash -n`
   clean — `evidence/validation_v42_changes.txt`). CI execution of the new
   code path: **NOT TESTED**.
3. **Bionic multi-RELRO wording corrected** (item 3) — the standard linker
   loop processes EVERY PT_GNU_RELRO separately; no general non-support claim
   is made (withdrawn). Documented instead: per-segment page-rounded
   over-protection and its overlap risk with writable data + the 16KiB
   app-compat extension hazards
   (`evidence/bionic_relro_runtime_position_v42.txt`). Runtime: **NOT TESTED**.
4. **Feature documentation added** (item 9, documentation only) —
   `docs/SMART_AUTO_SPEC.md` (SMART AUTO registered as a binding core
   requirement; `SPECIFICATION REQUIRED / NOT IMPLEMENTED / NOT TESTED`;
   Protocol Selection vs Scan Mode kept strictly separate; protocol set
   reconciled with the pinned commit via
   `evidence/protocol_surface_pinned_commit_v42.txt`) and
   `docs/FEATURE_MATRIX.md`.
5. **Docs/package alignment** (item 5) — this document and `README.md` now
   reference only files that actually exist in the package
   (`evidence/validation_v42_changes.txt` asserts reference existence).

Unchanged in v4.2: the workflow file, all pins (N1–N8), ABIs (N5), tool
versions, `rust-toolchain.toml`, `inspect_elf.sh`, all v4 evidence, and the
Flutter UI.

## 0a. v4 change log (employer review of bundle v3, 2026-10-31)

1. **Final workflow at the canonical path** — `.github/workflows/native-ci.yml`
   ships in this bundle at its real path (fix #1); actionlint 1.7.7 exit 0 on
   exactly that file (`evidence/validation_log.txt`).
2. **Artifact-flow simulation corrected** — the ARM64 upstream evidence path is
   `aether-android-arm64.d` (v3 used the non-existent
   `aether-android-arm64-v8a.d`, the copies failed, the run continued and the
   summary claimed success). v4: whole validation under `set -euo pipefail`,
   inspection on the FINAL rearranged tree, log/manifest/summary from ONE run
   with asserted count consistency (fix #2).
3. **Lyrebird pin proof reworked (pin unchanged)** — see §"Lyrebird" row of
   §2 and `evidence/lyrebird_pin_independent_test.txt` (fix #3).
4. **Multi-PT_GNU_RELRO** — inspect_elf.sh v4 analyzes every RELRO segment
   independently; all 9 official artifacts carry exactly one segment, so all
   official results are bit-for-bit unchanged (fix #4, §5).

## 0. v3 change log (employer review of bundle v2, 2026-10-31)

1. **RELRO-16KB analysis corrected to the official two-case rule** — the v2
   unconditional formula produced FALSE-POSITIVE FAILs for the official
   Aether binaries. Both arm64 and x86_64 aether place `PT_GNU_RELRO` in its
   own LOAD → **RELRO-16KB PASS** (see §5). The definitive-incompatibility
   claim from v2 is withdrawn.
2. **Zeptun intermediates moved out of the artifact path** — ndk-build output
   now goes to `$SRC_CACHE/zeptun-build.tmp` (never inside the uploaded
   `$OUT`), is wiped before/after the build, and a whitelist guard asserts
   the artifact holds exactly the 6 expected outputs + `manifest.json`.
3. **Manifest/verdict semantics** — armv7 `kb16_load` N/A; `needed` `[]`;
   x86_64 Go executables `PASS_WITH_WARNINGS`; `runtime_16kb_env` recorded
   as NOT TESTED on every artifact (static ELF ≠ runtime proof).
4. **Actions pin evidence completed** — raw tag→SHA proof for all tag-pinned
   Actions; dtolnay/rust-toolchain durability analysis (moving `stable`
   branch, durable alternative `d124f86` = `refs/heads/1.99.1`). No pin
   changed (freeze directive).
5. **Both remaining `|| true` in build_native.sh converted to fail-closed
   checks** — the script now really contains zero `|| true` (the v2 claim
   was wrong while two remained).

## 1. What is in this bundle (v3)

| File | Purpose |
|---|---|
| `.github/workflows/native-ci.yml` | GitHub Actions workflow: 6 jobs (native-build per ABI → elf-inspect; runtime-smoke; cargo-test; go-test; status-summary with honest exit gate); every Action pinned to a full commit SHA with raw evidence |
| `rust-toolchain.toml` | Exact Rust pin (1.99.1) so local builds match CI |
| `scripts/build_native.sh` | Builds zeptun + aether + lyrebird + psiphon for ONE ABI at the frozen pins; verifies every expected output with `[ -f ]` before copying; intermediates outside the artifact path + whitelist guard; zero `|| true` (v3) |
| `scripts/pt-build-pin.patch` | Hardens Aether's frozen `pt-build.sh`: checkout failure aborts, HEAD must equal `fc105a03c0e0`, proxy pseudo-version must embed the pin (N8); **v4.2: proxy path additionally verifies the SIGNED sumdb record with the official Go client (GOSUMDB) and requires byte-identity of the build zip with the go-client-verified zip** |
| `scripts/inspect_elf.sh` | v3 inspection: archives per-member; ELF header/type/PT_INTERP/PT_DYNAMIC/DF_1_PIE; NEEDED allowlists (`[]` when empty); every PT_LOAD (offset/vaddr/memsz/flags/align) with raw-derived minimum; **PT_GNU_RELRO two-case 16KB analysis** (own-load vs shared-load); armv7 N/A for 16KB; PASS_WITH_WARNINGS verdicts; artifact-tree hygiene check |
| `docs/CI_BOOTSTRAP_PoC.md` | This document |
| `evidence/` | verification logs, regenerated real readelf evidence of the official v2.4.0 artifacts (`elf_inspection_log.txt`, `elf_manifest_official_v240.json`), `pins_summary.json`, `actions_pins_raw_evidence.txt`, `relro_two_case_analysis.txt`, `android_pagesizes_doc_excerpt.txt`, `diffs/` (v2→v3), `validation_log.txt` |

## 2. Exact pins and their evidence

| Tool / Source | Pin | Evidence |
|---|---|---|
| Aether | `d58f9d568083129ce2c767c85054021eb3ee6a38` (2.4.0) | git checkout proof, `evidence/verification_log2.txt` |
| Zeptun | `08a1ab05aab315b7872ed582c52b7c230930d05d` (1.1.3) | git checkout proof; build.zig + scripts/build_android.sh read at this SHA for the v2 path fix |
| Psiphon fork | `2956a96b56fe09b99e72a8eb4bed3e79d29e3543` | git checkout proof; ancestor of base `83aa73b9…` verified; diff vs base = 8 files +566/−3 |
| Lyrebird | `fc105a03c0e0` | pinned inside Aether's frozen `pt-build.sh`; **enforced** by `scripts/pt-build-pin.patch` v4.2: git path = hard abort + `HEAD == pin` + binary `vcs.revision` check; proxy path = pseudo-version assertion **and** the zip verified against sum.golang.org (H1 dirhash locally recomputed; any mismatch/unreachable sumdb = hard abort) **and** the signed record verified by the official Go client (fresh temp module, `GOSUMDB=sum.golang.org`) **and** byte-identity of the build zip with the go-client-verified zip. Rationale: a binary built from the .git-less proxy zip records NO main-module commit (`go version -m` cannot carry the pin there — proven end-to-end, `evidence/lyrebird_pin_independent_test.txt`). Signed-record proof (analysis environment): `evidence/lyrebird_sumdb_goclient_verification.txt`. Proof recorded in `manifest.json`. |
| Rust | `1.99.1` | blog.rust-lang.org (stable channel 2026-10-15); Aether ships no pin — CI pins it |
| Zig | `0.16.0` | zeptun README; tarball sha256 `70e49664…ba3d00` from ziglang.org index |
| Go | `1.26.3` + `GOTOOLCHAIN=local` | fork `go.mod` (`toolchain go1.26.3`); forbids silent switching |
| NDK | `26.3.11579264` (r26d) | Aether release.yml (`ndk-version: r26d`) + developer.android.com older releases |
| API level | `29` | aether `cargo ndk … --platform 29` **and** zeptun `Application.mk: APP_PLATFORM := android-29` |
| cargo-ndk | `4.1.2` | crates.io latest — pinned exactly (upstream installs unpinned) |
| GitHub Actions | full commit SHAs | `git ls-remote <repo> <tag>` raw output 2026-10-31 in `evidence/actions_pins_raw_evidence.txt`; SHA changes only via the N8 gate |
| JDK / Gradle / AGP / Build-Tools | `17.0.21+9` / `9.8.2` / `9.4.0` / `36.0.0` | adoptium / services.gradle.org / developer.android.com — packaging baseline, not used by this workflow yet |

The `--platform 29 vs 24` question is closed with primary evidence: zeptun's real
`Application.mk` says **android-29** while zeptun's wiki (same commit) still claims
android-24 — stale documentation that the phase-1 audit had copied. Both components
build at API 29. **API 29 as the native-build level does not by itself prove that
all app behaviours are correct on API 29 or higher** (employer note); `minSdk=24`
therefore remains **CANDIDATE** until proven per dependency.

## 3. Zeptun build paths (v2 fix, evidence-based)

Read at zeptun `08a1ab05`:

- `build.zig` step `android` installs
  `zig-out/android/jniLibs/<abi>/libzeptun.so` and
  `zig-out/android/prebuilt/<abi>/libzeptun.a` — `zig build android`
  unconditionally builds **all four** upstream ABIs (x86 included; the ABI
  list is hardcoded in build.zig). Zeptun's `ABIS` variable scopes **only**
  the ndk-build stage (`APP_ABI=` for `libzeptun-jni.so`).
- `scripts/build_android.sh` puts the ndk-build product under
  `$OUT/jniLibs/<abi>/libzeptun-jni.so` (`OUT` env var).

`build_native.sh` v2 therefore exports, with `[ -f ]` verification before
every copy and hard failure on any missing file:

| Artifact | Real source |
|---|---|
| `libzeptun.so` | `<zeptun-src>/zig-out/android/jniLibs/$ABI/` |
| `libzeptun.a` | `<zeptun-src>/zig-out/android/prebuilt/$ABI/` |
| `libzeptun-jni.so` | `$OUT/zeptun-build/jniLibs/$ABI/` |

**x86 containment (N5):** `zig-out` is wiped before every build (the source
cache persists it), only the requested ABI is copied out, and a guard fails
the build if any foreign ABI directory appears in the export tree. No x86
file can enter the three-ABI artifact bundle; the upstream `zig build
android` four-ABI behaviour is recorded here per the employer's directive.

## 4. What the CI run will and will NOT test

**Covered by CI (once it runs):** native build per ABI (arm64-v8a, armeabi-v7a,
x86_64 — no x86, per N5); static ELF/ABI inspection v3 (machine/class, PIE-exec
proof via PT_INTERP+DF_1_PIE, Go static proof via NEEDED-empty + no PT_INTERP +
no PT_DYNAMIC, NEEDED allowlists, every PT_LOAD p_align + congruence, RELRO
two-case 16KB analysis, artifact-tree hygiene; warned artifacts report
PASS_WITH_WARNINGS, never a silent PASS); status-summary reporting the REAL
job results.

**NOT covered by CI — stays BLOCKED / NOT TESTED:**
- real-device tests (connection, lifecycle, UDP, memory, battery) — N2: emulator cannot substitute
- runtime exec from `nativeLibraryDir` (N7) on a real device
- 16KB-page Android runtime environment (needs a 16KB-page emulator/device, run locally)
- `minSdk=24` proof — procedure: `readelf -Ws` undefined symbols vs bionic API-24 set, then load/exec at API 24
- `zipalign -c -P 16 -v 4 app-release.apk` — requires an APK/AAB which does not exist yet; the command is recorded per the official doc and runs when packaging exists
- Speed Test (N3) and per-mode gates P-T1..P-T3/P-TB, P-S1..P-S3/P-SC

## 5. 16KB findings on the official v2.4.0 artifacts (real readelf, evidence mode, inspector v3)

- **LOAD-16KB PASS** on arm64-v8a: aether min p_align 16384; psiphon/lyrebird
  65536. armv7 records N/A for the 16KB rule (4 KB architecture; its 4 KB
  ELF validity passes: min p_align 4096).
- **RELRO-16KB PASS — v2 verdict CORRECTED (was a false positive):** the v2
  inspector applied `(VirtAddr+MemSiz) % 16384 == 0` without checking how
  `PT_GNU_RELRO` is placed among the LOADs. Per the official Android doc the
  formula applies **only when RELRO shares its LOAD with subsequent writable
  data**; when RELRO is in its own LOAD the formula is NOT applicable — what
  matters is that every subsequent writable LOAD starts at/after
  `page_up(relro_end)`, outside the linker's mprotect range. Raw data
  (`evidence/relro_two_case_analysis.txt`):

  | | aether arm64 | aether x86_64 |
  |---|---|---|
  | RELRO vaddr / memsz | 0x118e140 / 0x93ec0 | 0x137a010 / 0x94ff0 |
  | RELRO end (mod 16384) | 0x1222000 (8192) | 0x140f000 (12288) |
  | covering LOAD | vaddr 0x118e140, memsz 0x93e40, RW | vaddr 0x137a010, memsz 0x94ab8, RW |
  | data before / after RELRO in LOAD | 0 / −128 (RELRO ends past the LOAD) | 0 / −1336 (RELRO ends past the LOAD) |
  | placement | **own-load** (LOAD contains only RELRO data) | **own-load** |
  | mprotect range [page_down, page_up) | [0x118c000, 0x1224000) | [0x1378000, 0x1410000) |
  | next writable LOAD | 0x1225f80 ≥ 0x1224000 ✓ | 0x1412ad0 ≥ 0x1410000 ✓ |
  | **kb16_relro** | **PASS** | **PASS** |

  The non-zero remainders (8192 / 12288) are expected and harmless in an
  own-LOAD layout: no writable byte lies inside the mprotect range. **The v2
  claim that Aether definitively violates the RELRO-16KB rule is withdrawn.**
  Runtime in a real 16 KB environment stays NOT TESTED (static analysis only).
- **x86_64 Go executables below 16KB (unchanged finding):** psiphon/lyrebird
  x86_64 LOAD p_align 4096 (GOOS=linux Go linker default) — recorded as
  `kb16_load=FAIL` (static ELF fact) with verdict **PASS_WITH_WARNINGS**
  (runtime NOT TESTED); `STRICT_16KB_X86_64_EXEC=1` hard-fails; fixing it
  changes the Go build → employer decision (N8). x86_64 is never skipped.
- **ZIP alignment is deliberately separate:** `zipalign -c -P 16 -v 4` runs
  on a real APK; status NOT TESTED until then.
- zeptun artifacts: MISSING in this evidence (not shipped upstream) — the CI
  run will produce and inspect them for the first time.

## 6. How to unblock (employer actions)

1. **Push this repository** (workflow + scripts + rust-toolchain.toml at the repo root) to GitHub → the first CI run produces the CI log requested for the next report.
2. **Re-confirm the full N8 upgrade-gate text** — it was truncated in transmission (ends at "API/…"); the freeze stands until the complete gate is on record.
3. **Psiphon credentials (N6):** request official PropagationChannelId/SponsorId; until then public-release status stays BLOCKED (placeholder `FFFFFFFFFFFFFFFF` is compiled into Aether's defaults — `psiphon.rs` L223-224, env overrides exist).
4. **Decide the open 16KB items (§5):** (a) x86_64 Go executables below 16 KB —
   accept PASS_WITH_WARNINGS or mandate the Go linker-flag change (N8 gate);
   (b) 16 KB runtime verification on an emulator/device once artifacts exist
   (static compliance is necessary, not sufficient).
5. **Decide the dtolnay/rust-toolchain pin strategy (§2, WARN):** keep `b725eda`
   (current `stable` HEAD — moving-ref durability risk) or switch to the
   durable per-version branch head `d124f86` (`refs/heads/1.99.1`, behaviorally
   identical with our explicit `toolchain: 1.99.1` input). No change made
   without employer approval (N8).
6. After CI artifacts exist: run the device-side tests and record them **separately** from CI results (N2).

## 7. Recorded deviations from upstream (deliberate, per employer decisions)

- Psiphon builds at the fork's `2956a96` (N1), not Aether's default pin `83aa73b` — Aether's `psiphon-build.sh` is bypassed for this component; the build environment is replicated exactly (CGO_ENABLED=0, GOOS=linux, `-mod=vendor`, `-trimpath`, `-ldflags "-s -w"`).
- Lyrebird builds through Aether's frozen `pt-build.sh` **plus** `scripts/pt-build-pin.patch` (fallback removed; pin verified pre-build and post-build). The patch is a recorded deviation required by N8.
- ABIs limited to the N5 three; upstream's zeptun `zig build android` still builds four inside the source tree — contained and recorded (§3).
- `cargo-ndk` and Rust pinned exactly where upstream floats on "latest".
- GitHub Actions pinned by commit SHA where upstream uses moving tags.
- `pt-build.sh` licensedir argument left empty (LICENSES/ collection is a packaging-phase concern, not needed for ELF inspection); recorded here for transparency.
