# Platform & ABI Compatibility Matrix — Firefox VPN Engine

The multi-architecture amendment requires every supported Android ABI
to carry the same correct, testable Firefox VPN implementation. No
result may be generalized from one ABI to another.

## 1. The real project matrix

Extracted from the actual build configuration
(`phase1/scripts/build_engine.sh`, the `jniLibs` tree, and the app's
Gradle packaging — no `abiFilters` narrowing exists, the app ships all
three ABIs):

| OS | Arch | ABI | GOOS | GOARCH | CGO | Compiler (API 34) |
|---|---|---|---|---|---|---|
| Android | ARM64 | arm64-v8a | android | arm64 | **1** | `aarch64-linux-android34-clang` |
| Android | ARM32 | armeabi-v7a | android | arm (GOARM=7) | **1** | `armv7a-linux-androideabi34-clang` |
| Android | x86-64 | x86_64 | android | amd64 | **1** | `x86_64-linux-android34-clang` |
| Linux (host) | x86-64 | — | linux | amd64 | 0 | (pure Go — test vehicle ONLY) |

NDK pin: **28.2.13676358 (r28c)**, same for all Android ABIs.

Other platforms (desktop Linux/Windows targets of the AETHONE app
shell) have **no wired Firefox VPN transport** — no claim of support
is made for them, and the Android resolver settings are never
generalized to them. The host build exists solely so the Dart
integration/lifecycle tests and `--dns-probe` evidence run on the
development machine.

## 2. Per-ABI status (honest, per the corrective decree)

| ABI | Build (2026-11-09) | ELF inspection | Resolver selection | DNS runtime (device) | OAuth guard | Error contract |
|---|---|---|---|---|---|---|
| arm64-v8a | built · hash recorded | Bionic NEEDED + `getaddrinfo` verified | CGO → Bionic | **NOT RUN** (no device in agent env) | in source (shared) | in source (shared) |
| armeabi-v7a | built · hash recorded | Bionic NEEDED + `getaddrinfo` verified | CGO → Bionic | **NOT RUN** | in source (shared) | in source (shared) |
| x86_64 | built · hash recorded | Bionic NEEDED + `getaddrinfo` verified | CGO → Bionic | **NOT RUN** | in source (shared) | in source (shared) |
| host (linux/amd64) | built · hash recorded | n/a (pure Go, test vehicle) | Go resolver (host OS) | `--dns-probe` evidence recorded 2026-11-09 | in source | in source |

Notes:

* The Go source is ABI-shared — the classification (`fferr`), the
  OAuth guard (`fferr/token.go`), the JSON contract and the redaction
  are identical code paths in every binary; per-ABI divergence would
  require build-tagged code, and only `resolver_cgo.go` /
  `resolver_nocgo.go` are build-tagged (cgo vs host).
* **On-device DNS runtime tests per ABI are NOT RUN.** No emulator or
  device exists in the agent environment. This is the owner's
  device-acceptance phase. Host `--dns-probe` output is host evidence,
  NOT Android evidence.
* APK embeds all three ABIs (fat packaging, no splits configured).

## 3. Binary evidence (committed: `phase1/build/SHA256SUMS.txt`)

```text
a404bbbb67e58d153fe439fee3996ebb24458f0cd7263cc30ea6ce2bde980a2b  arm64-v8a/libfirefoxvpn.so
05e94c7480bfe1505095d3f8133826fab1025383fa0fbc9eb739c264dde9a323  armeabi-v7a/libfirefoxvpn.so
ec698230a4f551fb71bd7ff13151267221ca3a0423b080a4c9876ee68e639b13  x86_64/libfirefoxvpn.so
89ef32fd5e08725513ee4fb006d750fee5f911844a602463acf3c096fc3bf06f  host/libfirefoxvpn
```

Per-ABI ELF inspection logs: `phase1/build/android/<abi>/libfirefoxvpn.so.inspection.txt`.

## 4. Verification commands (owner, per ABI)

```bash
file     libfirefoxvpn.so                 # ELF <arch>, pie, dynamic
readelf -d libfirefoxvpn.so              # NEEDED: libc.so (Bionic), libdl…
readelf --dyn-syms libfirefoxvpn.so | grep -E 'getaddrinfo|freeaddrinfo|gai_strerror|res_search'
sha256sum libfirefoxvpn.so               # must match §3
```

None of these symbol checks alone proves on-device behavior — they are
strong build-configuration evidence only. Runtime proof happens on the
owner's device (control-plane DNS test through the engine child
process, no account data required — the `--dns-probe` role resolves
`api.accounts.firefox.com` and `firefox.settings.services.mozilla.com`
and reports the real result).
