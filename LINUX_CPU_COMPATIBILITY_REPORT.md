# AETHONE — Linux CPU ISA Compatibility Report (x86-64-v1 floor)

**Round:** v4.36n · **Branch:** `ci-bootstrap/v4.4` · **Fix commit:** `4b283e7`
**Verification run:** #80 (run id 42253093789) — results filled in below after the run completed.
**Scope:** Linux desktop bundle x86-64 CPU compatibility (root cause + fix + gates), with the Windows x86_64 appendix audit. Android untouched (frozen round; regression-verified only).

---

## 1. The failure (the owner's report, run #78/#79 artifacts)

The run #78 Linux bundle (and — re-verified — the run #79 bundle) dies on an Intel Core
i3-3240 (Ivy Bridge: SSE4.2 + AVX, **no AVX2**, i.e. x86-64-v2-class CPU) with:

```
Fatal glibc error: CPU ISA level is lower than required
```

glibc prints this and aborts **before `main()` runs**, when the dynamic loader finds a
`GNU_PROPERTY_X86_ISA_1_*` requirement in the executable's `.note.gnu.property` that the
CPU cannot satisfy. On the CI runners (Azure Xeons, AVX2/AVX-512 capable) the same binary
boots fine — which is why every CI gate before this round was green while the owner's
machine could not start the app at all.

## 2. Root cause — found at the OBJECT level, not by guessing

### 2.1 What readelf said (the owner's finding, re-confirmed on the r79 artifact)

```
$ readelf --notes --wide bundle/aethone
  Properties: x86 ISA needed: x86-64-baseline, x86-64-v2, x86-64-v3
```

All eight other ELFs in the bundle (`libapp.so`, `libflutter_linux_gtk.so`, `libdartjni.so`,
`liburl_launcher_linux_plugin.so`, `libaether.so`, `libzeptun.so`, `lyrebird`, `psiphon`)
carry **no ISA note at all**.

### 2.2 What the machine code said

A full disassembly of `bundle/aethone` contains **zero** v3-class instructions:

* `%ymm` / `%zmm` register instructions (AVX2/AVX-512): **0**
* BMI1/BMI2 mnemonics (`lzcnt`, `andn`, `bextr`, `blsi`, `mulx`, `pdep`, `pext`, …): **0**
* FMA (`vfmadd*`/`vfmsub*`): **0**; `movbe`: **0**

So the v3 "requirement" is **pure ELF metadata** — no v3 code exists in the executable.

### 2.3 Where the metadata came from (the smoking gun)

`readelf -p .comment bundle/aethone` shows two producers: `GCC: (Ubuntu 15.2.0-16ubuntu1)`
(glibc's CRT, built with GCC) and `Ubuntu clang version 21.1.8` (the runner/plugin objects
compiled by the Flutter tool). The decisive evidence chain:

1. The r79 `Desktop bundle (linux)` job log shows the runner image is **`ubuntu-26.04`**
   and installs **`amd64v3`** packages (`ninja-build_1.13.2-1_amd64v3.deb`) — GitHub's
   `ubuntu-latest` pool had moved to the **amd64v3 architecture variant** of 26.04.
2. Ubuntu publishes that variant's glibc in the archive. Downloaded and inspected directly:
   * `libc6-dev_2.43-2ubuntu2_amd64v3.deb` → `/usr/lib/x86_64-linux-gnu/Scrt1.o` carries
     **`x86 ISA needed: x86-64-baseline, x86-64-v2, x86-64-v3`** (and, disassembled,
     contains **zero** v3 instructions — metadata-only there too).
   * `libc6-dev_2.43-2ubuntu2_amd64.deb` (plain amd64, **same glibc version**) →
     `Scrt1.o` carries **`x86 ISA needed: x86-64-baseline`** only.
   * `crti.o` / `crtn.o` carry **no ISA note in either build** — which is exactly why the
     shared libraries (cdylibs link crti/crtn but never Scrt1) came out clean.

**Root cause statement:** the Flutter Linux runner executable is linked by the default
compiler driver against the build image's C runtime startup object. On the amd64v3 variant
of the ubuntu-26.04 runner image, `Scrt1.o` carries a v3 GNU property that the linker merges
into `bundle/aethone`. glibc on the owner's Ivy Bridge machine enforces that property at
load time and kills the process. **No AETHONE source file, no compile flag of ours, and no
actual instruction in the binary is responsible** — the runner image's CRT is.

A latent gate bug made this invisible until now: `scripts/build_native_desktop.sh` (v4.36k)
and the workflow's informational check parsed the note with `grep -o 'x86 ISA needed:
[^ ,]*'`, which **truncates at the first comma** and would have missed exactly the
`baseline, v2, v3` note that shipped. Fixed in this round (whole-line parse).

## 3. The fix (four layers, defense in depth)

| # | Layer | Change |
|---|-------|--------|
| 1 | **Baseline image** | `desktop-native` (linux leg), `desktop-bundle` (linux leg) and `desktop-smoke` pin **`ubuntu-24.04`** — the baseline amd64 LTS image — instead of the amd64v3 `ubuntu-latest` pool. This removes the tainted CRT from the link path *and* caps required glibc symbol versions at the 2.39 era. |
| 2 | **Codegen floor** | `linux/CMakeLists.txt` pins **`-march=x86-64 -mtune=generic`** via `add_compile_options()` placed *before* the `flutter/`, `runner/` and generated-plugin subdirectories, so it covers the runner executable, the url_launcher plugin and every future plugin/native asset. Flag order is last-wins: our floor lands *after* any env/image `-march`, verified empirically (with `CXXFLAGS=-march=x86-64-v3` the linked exe still reports baseline-only). Windows untouched: MSVC never sees GCC flags; MSVC x64 defaults to SSE2. |
| 3 | **Fail-closed ISA gate** (new CI step, linux bundle, between the Flutter build and the tar packaging) | `readelf --notes` over **every** ELF in the bundle (the 9 shipped today + any future file found by ELF magic), rejecting any `x86 ISA needed` level past v1; **full `ldd` resolution proof** for every dynamic ELF (one documented exception: `libdartjni.so` → `libjvm.so`, the dormant JNI native asset — the smoke boots prove startup never loads it); a report-only v3-instruction census for the audit trail. The gate also runs `bundle/aethone`'s floor check again in the smoke job **after the tar round-trip**. |
| 4 | **Toolchain flags kept** | zig `-Dcpu=baseline` (zeptun), Go `GOAMD64=v1` (lyrebird + psiphon), rustc default baseline (aether) — unchanged; **no global RUSTFLAGS** (aether's `.cargo/config.toml` pins `+crt-static` for windows-msvc; an env RUSTFLAGS would clobber it). The v4.36k note-truncation regex bug in `build_native_desktop.sh`'s own gate is fixed. |

**What was deliberately NOT done:** no stripping of `.note.gnu.property` to hide the note
(that would leave a v3-stamped-but-silent binary), no `continue-on-error`, no removal of
tests, no Android file touched.

## 4. Verification — run #80 (commit 4b283e7), all real executions

<!-- RESULTS -->

## 5. Windows x86_64 appendix — machine-code audit (llvm-objdump)

Windows has **no load-time ISA property**: a v3 instruction only faults
(`0xC000001D STATUS_ILLEGAL_INSTRUCTION`) when *executed*. So the audit is a real
disassembly of every PE in the bundle with per-component policy, derived from the
verified r79 dispatch analysis. The new `PE ISA audit` CI step (windows bundle leg,
llvm-objdump from the preinstalled LLVM 20.1.8) enforces it on every run:

| Component | v3 sites (r79) | Source of v3 code | Dispatch guard (verified) | CI policy |
|---|---|---|---|---|
| `data/app.so` | 0 | Dart AOT (`gen_snapshot`, baseline) | — | **zero tolerance** |
| `dartjni.dll` | 0 | native-assets clang baseline | — | **zero tolerance** |
| `zeptun.dll` | 37 × `tzcnt` only | LLVM `@ctz` encoding (REP+BSF) | instruction-level fallback: decodes as plain `bsf` on non-BMI CPUs, zero-guarded | **tzcnt-only** (any ymm/BMI/FMA fails) |
| `aethone.exe` | 102 | MSVC STL `__std_` helpers (prebuilt `libcpmt`) | `__isa_available` CPUID: `call init; cmp $0x2,%eax` diamond | **envelope ≤ 400 + guard shape required** |
| `url_launcher_windows_plugin.dll` | 32 | same MSVC STL helpers | rip-relative feature word: `mov (%rip),%eax … test $0x20,%al; je` | **envelope ≤ 200 + guard shape required** |
| `flutter_windows.dll` | 14 669 | Skia/Impeller (Google prebuilt) | SkCpu/Impeller runtime CPU dispatch | counted, reported |
| `aether.dll` | 17 260 | BoringSSL Perlasm kernels | `OPENSSL_ia32cap` CPUID dispatch | counted, reported |
| `wintun.dll` | 77 | WireGuard (prebuilt) | feature-bit tested paths (`testb $0x2, …; jne`) | counted, reported |
| `lyrebird.exe` | 108 908 | Go stdlib crypto asm | `internal/cpu` CPUID dispatch, `GOAMD64=v1` | counted, reported |
| `psiphon.exe` | 8 792 | Go stdlib crypto asm | same | counted, reported |

Guard spot-checks from the r79 audit (aethone.exe): the AVX2 `find_first_of` kernel at
`0x140013da0` is only called from `0x140013acd`, which is dominated by
`call 0x140014700` (isa probe) → `cmp $0x2,%eax; jne` → SSE4.2/scalar paths. On Ivy Bridge
the probe returns 1 (SSE4.2) and the AVX2 kernel is never entered. Unknown PEs fail the
audit (a new file without a policy is a gap, not an pass).

**Windows per-compiler flags:** MSVC components (runner, plugins, Google's engine) compile
with the MSVC default (SSE2, no `/arch`); GCC-style flags never leak into MSVC legs; zig
`-Dcpu=baseline` and Go `GOAMD64=v1` are the same flags as Linux; rustc stays on its
baseline default. No flag changes were needed on Windows — the audit gates the result.

## 6. Honest limits — what is and is NOT tested

* **No real pre-Haswell CPU exists in CI.** The Linux floor is proven statically (readelf
  property gate on every ELF) and dynamically on AVX2-capable CI hardware (Xvfb smoke);
  the owner's i3-3240 remains the real-device test.
* **Windows on no-AVX2 hardware: NOT TESTED.** The audit is static machine-code analysis
  plus verified dispatch guards. No pre-Haswell Windows machine was available.
* glibc symbol-version floor of the r80 Linux bundle (built on 24.04): see the run #80
  table in §4 — the app requires glibc ≥ the highest version listed there (Ubuntu 24.04+
  era); older distributions will fail on symbol versions before any ISA consideration.
* The v3 instruction census numbers (BoringSSL/Go/Skia kernels) are expected and safe:
  they sit behind CPUID dispatch and never execute on a v2-class CPU. They are recorded on
  every run as the audit trail for drift.
