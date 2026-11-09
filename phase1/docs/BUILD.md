# FIREFOX VPN ENGINE BUILD — phase1 (the A1 decree, all Android ABIs)

Status: **private branch `phase2/firefox-vpn-ui` only** (upstream
license UNRESOLVED — `fxv/ORIGIN.md`). Rebuilt and verified
2026-11-09.

## 1. Why A1 exists (the root cause)

The 2026-11-08 field build (logcat line 43649, package
`com.chakcaad.aethone.da`) failed the FxA login exchange with:

```
oauth token request: Post "https://api.accounts.firefox.com/v1/oauth/token":
dial tcp: lookup api.accounts.firefox.com on [::1]:53: read udp
[::1]:37265->[::1]:53: read: connection refused
```

Diagnosis: the ARM64 engine had been built **pure Go**
(`CGO_ENABLED=0`). Go's own resolver on Android consults the local
`/etc/resolv.conf`-shaped configuration, which on Android points at
`127.0.0.1:53` / `[::1]:53` — a resolver that does not exist outside
the OS's own resolver machinery. The fix (real-device verified
2026-11-08, extended to EVERY Android ABI by the 2026-11-09
multi-architecture amendment): build every Android ABI with **CGO +
the NDK clang toolchain**, which routes name resolution through
**Bionic's `getaddrinfo`** — the Android system resolver.

Pure Go is therefore FORBIDDEN for every Android target of this
engine: a pure-Go Android binary is the KNOWN-BROKEN configuration,
and `build_engine.sh` **refuses** `CGO_ENABLED=0` for any Android
target (fail-closed, not a warning). The Linux HOST build stays pure
Go — it is not a deliverable; it exists so the Dart
integration/lifecycle tests and the `--dns-probe` host evidence run on
the development machine.

## 2. Toolchain pins

| Tool | Pin |
|---|---|
| Go | 1.25.0 (`go version` asserted by the script) |
| Android NDK | **28.2.13676358 (r28c)** — `source.properties` verified |
| Compilers (API 34) | `aarch64-linux-android34-clang` · `armv7a-linux-androideabi34-clang` (GOARM=7) · `x86_64-linux-android34-clang` |
| Upstream core | `55ad91a2ccea1c93e69c82a08a7681e279884db5` (fetch-verified by `fetch_upstream.sh` + the SHA256 manifest) |

The NDK is located via `ANDROID_NDK_HOME` / `NDK_HOME` /
`ANDROID_HOME/ndk/<pin>` / `ANDROID_SDK_ROOT/ndk/<pin>`; a missing
compiler is a hard failure, never a silent fallback.

## 3. The build matrix (verified 2026-11-09, this session)

| Target | GOOS/GOARCH | CGO | Compiler | Status |
|---|---|---|---|---|
| `arm64-v8a` | android/arm64 | **1** | aarch64-linux-android34-clang | ✅ built + ELF-verified |
| `armeabi-v7a` | android/arm + GOARM=7 | **1** | armv7a-linux-androideabi34-clang | ✅ built + ELF-verified |
| `x86_64` | android/amd64 | **1** | x86_64-linux-android34-clang | ✅ built + ELF-verified |
| host | linux/amd64 | 0 | (pure Go) | ✅ built (test vehicle only) |

### The commands

```bash
# 1. fetch + verify the pinned upstream (once per worktree)
phase1/scripts/fetch_upstream.sh

# 2. build (any subset or all)
ANDROID_NDK_HOME=/path/to/ndk/28.2.13676358 \
phase1/scripts/build_engine.sh all          # arm64-v8a armeabi-v7a x86_64 host

# the ARM64 command the script runs, spelled out:
CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android34-clang" \
CGO_LDFLAGS="-Wl,-soname,libfirefoxvpn.so" \
go build -trimpath -o build/android/arm64-v8a/libfirefoxvpn.so ./cmd/libfirefoxvpn
```

Outputs land in `phase1/build/<abi>/libfirefoxvpn.so` (mode 0755) +
per-binary `<binary>.inspection.txt` evidence +
`phase1/build/SHA256SUMS.txt` (the manifest never contains its own
hash; the previous manifest is backed up, never silently overwritten).

## 4. ELF inspection (the A1 proof, per ABI)

The script runs and RECORDS this after every Android build:

```bash
file            libfirefoxvpn.so
readelf -h      libfirefoxvpn.so     # ELF class/machine, PIE
readelf -d      libfirefoxvpn.so     # NEEDED: liblog.so, libdl.so, libc.so
readelf --dyn-syms -W libfirefoxvpn.so | grep -E 'getaddrinfo|freeaddrinfo|gai_strerror|res_search'
readelf -n      libfirefoxvpn.so     # the GNU build id
```

**Verified evidence (this session, all three ABIs):** `NEEDED
liblog.so / libdl.so / libc.so` present (a CGO/Bionic build — the
pure-Go binary has NO NEEDED entries), and the resolver symbols
`getaddrinfo@LIBC`, `freeaddrinfo@LIBC`, `gai_strerror@LIBC` imported
as UND from LIBC — the binary asks BIONIC to resolve names. The
script FAILS the build if either evidence is missing (fail-closed).

Symbols prove the WIRING, not the on-device behavior: the runtime
proof is the `--dns-probe` role run on a device/emulator of each ABI
(see §6).

## 5. Deploying into the APK (jniLibs)

```
android/app/src/main/jniLibs/arm64-v8a/libfirefoxvpn.so
android/app/src/main/jniLibs/armeabi-v7a/libfirefoxvpn.so
android/app/src/main/jniLibs/x86_64/libfirefoxvpn.so
```

`jniLibs/` is gitignored (M2: binaries never enter git history);
deployment is hash-verified against `build/SHA256SUMS.txt`
(`sha256sum -c`) before every APK build. `useLegacyPackaging = true`
keeps the installer-extracted `nativeLibraryDir/libfirefoxvpn.so` a
REAL executable file (the only directory an app may exec from).

## 6. The DNS runtime evidence (per ABI — honest status)

`libfirefoxvpn.so --dns-probe` resolves
`api.accounts.firefox.com`, `firefox.settings.services.mozilla.com`
and `vpn.mozilla.org` THROUGH THE SAME CHILD PROCESS the app runs,
reporting per-domain results + the compiled-in resolver identity, with
NO secrets. Status:

| ABI | Build+ELF | DNS runtime on Android | Host-mechanism evidence |
|---|---|---|---|
| arm64-v8a | ✅ | **NOT RUN** (no device/emulator in this session) | n/a |
| armeabi-v7a | ✅ | **NOT RUN** | n/a |
| x86_64 | ✅ | **NOT RUN** | n/a |
| host (linux-amd64) | ✅ | n/a (not an Android target) | ✅ ran — all three domains resolved through the process, honestly labeled "pure-Go resolver (NOT the sanctioned Android configuration)" |

A host run is NOT Android evidence — the Android binaries carry the
CGO/Bionic wiring proof (§4) and the on-device `--dns-probe` runs are
recorded **NOT RUN until a device/emulator executes them** (the DA
build is the natural vehicle; run
`adb shell /path/to/libfirefoxvpn.so --dns-probe` per ABI).

## 7. Reproducing the verification

```bash
cd phase1/fxv
go vet ./...
go test ./... -count=1      # 85 tests (lifecycle tests spawn the REAL binary)
```
