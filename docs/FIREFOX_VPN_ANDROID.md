# FIREFOX VPN on Android — ABI matrix, build, packaging, paths and ports (Phase 1)

Status: **Phase 1, private branch `phase1/firefox-vpn` only** (engine
license UNRESOLVED — `fxv/ORIGIN.md`). The Android matrix below is the
entire Phase 1 deliverable surface: Linux/Windows desktop builds of the
engine are out of scope.

## 1. ABI matrix and toolchain pins

Build script: `phase1/scripts/build_engine.sh` (mirrored at
`/home/z/my-project/phase1/scripts/`). It replicates the PROVEN Phase 0
build matrix exactly; the pins are the phase-0 evidence values:

| Target | Mode | Toolchain |
|---|---|---|
| `arm64-v8a` | pure Go (`CGO_ENABLED=0`), Go's own linking | Go 1.25.0 |
| `armeabi-v7a` | cgo (`GOARM=7`), NDK clang `armv7a-linux-androideabi34-clang` | Android NDK 28.2.13676358 (r28c) |
| `x86_64` | cgo, NDK clang `x86_64-linux-android34-clang` | Android NDK 28.2.13676358 (r28c) |
| host `linux-amd64` | pure Go — NOT a deliverable; it exists so the Dart integration/lifecycle tests run the REAL engine binary on the host | Go 1.25.0 |

Every build uses `-trimpath`. Upstream source pinned to
`55ad91a2ccea1c93e69c82a08a7681e279884db5` (`replace` directive; the
script asserts it before building).

### Verified build outputs (SHA256, from `build/SHA256SUMS.txt`)

```
332c4abe3a1b94847ebc03c91eab557dbfdc7533ca76222474394a9e4d56b3b9  ./android/arm64-v8a/libfirefoxvpn.so
52dd9c0838e8597309ede9aaadb588b0ff11d1b1989955f6eb6efbc6028f7bc4  ./android/armeabi-v7a/libfirefoxvpn.so
e7d68e7285b31e751d49e72f32307789abf6296fd4af9b60f9a4cdd6eb21dfc0  ./android/x86_64/libfirefoxvpn.so
330cc2882f40c156bf432c202fbc985d6a75ba1b4dca351411fd0b115b18f110  ./host/libfirefoxvpn
```

Sizes: arm64-v8a 14,431,161 B · armeabi-v7a 14,275,252 B · x86_64
15,412,048 B · host 14,186,979 B.

**Determinism evidence**: after a source change that touched only a
`_test.go` file (never compiled into the binary), a full rebuild
reproduced all four hashes bit-identically. A checksum file never
contains its own hash (`SHA256SUMS.txt` is excluded from the listing and
written via `mktemp` outside the output tree — the earlier
self-referential first line was a bug, now fixed in the script).

### ELF / ABI verification (from the build log)

* `arm64-v8a`: `ELF 64-bit LSB pie executable, ARM aarch64 … interpreter
  /system/bin/linker64`, `FLAGS_1 PIE`, **no NEEDED entries** (pure Go).
* `armeabi-v7a`: `ELF 32-bit LSB pie executable, ARM, EABI5 … for Android
  34, built by NDK r28c (13676358) … interpreter /system/bin/linker`,
  `NEEDED liblog.so, libdl.so, libc.so`, `FLAGS_1 NOW PIE`.
* `x86_64`: `ELF 64-bit LSB pie executable, x86-64 … for Android 34,
  built by NDK r28c (13676358) … interpreter /system/bin/linker64`,
  `NEEDED liblog.so, libdl.so, libc.so`, `FLAGS_1 NOW PIE`.
* host: static ELF executable (no interpreter).
* Executable bit `-rwxr-xr-x` on every artifact (`stat` in the script).

## 2. The `libfirefoxvpn.so` naming convention

The binary is an **executable**, not a shared library. The `.so` name
exists solely because Android only unpacks `lib/<name>.so` entries into
`nativeLibraryDir` (the only directory an app can exec from). It is
never dlopen'd, has no JNI exports, and is spawned bare via
`dart:io Process.start` (fork/exec, same as `ProcessBuilder`). The
`jniLibs` copies in the worktree are hash-identical to the pinned build
outputs (verified per ABI), carry mode `0755`, and are git-ignored
(`/android/app/src/main/jniLibs/` in `.gitignore`) — binaries never
enter git history.

Packaging: `android/app/build.gradle.kts` sets
`packaging { jniLibs { useLegacyPackaging = true } }` (the M2 rule: the
packaged native libraries are COMPRESSED in the APK and the installer
EXTRACTS them into `nativeLibraryDir` — a real file with the exec bit,
which is where exec happens; in-APK loading cannot be exec'd). At
install time `nativeLibraryDir/libfirefoxvpn.so` is therefore a real
executable file. The debug APK packaging proof (assembleDebug, 286 s)
contains the engine in all three ABIs; AGP applies its standard
`llvm-strip` to every native lib during packaging (same treatment as
libaether/lyrebird/zeptun — the stripped ELF still execs and runs):

| ABI | in-APK (stripped) SHA256 |
|---|---|
| arm64-v8a | `c58a8ec3169788480f218ebd54e18935d0e699bd42e30d978b9131ec5fef6b36` |
| armeabi-v7a | `0a7789019ba9e33dbd0ff08d18c64b690207950c1dcad6c376d0492c128d346c` |
| x86_64 | `bb5adbcd3e176212853c0074be90d9c4f923d7124ddb062fbebcd227dde1ac5e` |

The unstripped pinned build hashes stay authoritative for the engine
build itself (`build/SHA256SUMS.txt`); the in-APK table above is the
packaging-level record (a deterministic transform of the pinned bits by
the same pinned NDK's llvm-strip).

## 3. Runtime paths and the port map

Paths (from the `aethone/engine` MethodChannel `paths`):

* binary: `<nativeLibraryDir>/libfirefoxvpn.so`
* session vault: `<filesDir>/firefox/session.vault` (Keystore-encrypted;
  `FIREFOX_VPN_SECURITY.md`)
* discovery cache: `<filesDir>/firefox/serverlist.json` (labeled cached
  data, 6 h TTL reporting; `FIREFOX_VPN_SERVER_DISCOVERY.md`)

Port map (the evidence-locked contract; `transport_modes.dart` +
`test/firefox_engine_test.dart` lock it):

| Port | Engine | Phase-1 status |
|---|---|---|
| 1819 | aether `--bind` (proxy) | untouched |
| 1820 | aether `--tor-bind` | untouched |
| 1821 | aether `--psiphon-bind` | untouched |
| **1822** | **Firefox VPN SOCKS5, `127.0.0.1` ONLY** | NEW (Phase 1) |

The engine itself refuses to bind anything non-loopback
(`socksListenNotLoopback`), and the adapter asserts `1822` free
(`TunnelProbe.isListenerReady`) at runtime before every connect — a
busy port fails with `firefoxPortBusy`, never a second listener.

## 4. Engine + APK build on Android

`flutter build apk --debug` (Flutter 3.47.9, pub cache
`tools/pubcache`, JDK 21.0.13, Gradle 9.8.2 via
`GRADLE_USER_HOME=/tmp/my-project/gradle_home`) assembles the app with
the three jniLibs ABIs packaged. Phase 1 ships no release APK publicly
(license UNRESOLVED); the debug APK is the private packaging proof only.
CI stays private-environment-only for the same reason; there is no
public artifact and no public release containing the engine.

## 5. Desktop platforms

Out of Phase 1 scope by decree (Android only). The adapter carries one
honest desktop guard: in Tunnel mode on Windows the whole-device tunnel
for Firefox VPN needs a direct internet leg zeptun's Windows routing
cannot exempt yet (the tunnel would loop back into itself) — proxy mode
works; the connect fails with `platformLimit` instead of pretending.
