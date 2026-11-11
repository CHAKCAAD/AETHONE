# Firefox VPN Engine — Reproducible Build

> Detailed historical build log with the full A1 evidence:
> `phase1/docs/BUILD.md`. This file is the standing procedure.
> **The agent has NOT rebuilt binaries in the corrective session —
> builds are the owner's phase.** The binaries listed in §6 were built
> 2026-11-09 (before the corrective order) and their hashes are
> committed in `phase1/build/SHA256SUMS.txt`.

## 1. Toolchain pins

| Tool | Pin |
|---|---|
| Go | 1.25.0 (asserted by the script) |
| Android NDK | **28.2.13676358 (r28c)** — `source.properties` verified |
| Compilers (API 34) | `aarch64-linux-android34-clang` · `armv7a-linux-androideabi34-clang` (GOARM=7) · `x86_64-linux-android34-clang` |
| Upstream core | `c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1` (re-pinned 2026-11-11, see [core-update-2026-11-11.md](core-update-2026-11-11.md)) |

The NDK is located via `ANDROID_NDK_HOME` / `NDK_HOME` /
`ANDROID_HOME/ndk/<pin>` / `ANDROID_SDK_ROOT/ndk/<pin>`. A missing
compiler is a **hard failure**, never a silent fallback.

## 2. Fetch the pinned upstream (never commit it)

```bash
phase1/scripts/fetch_upstream.sh
```

* clones `https://github.com/UjuiUjuMandan/firefox-vpn-client`
* checks out `c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1`
* asserts `git rev-parse HEAD` equals the pin
* writes `phase1/firefox-vpn-client.SHA256SUMS` (the tracked manifest)
* the vendored copy itself is **gitignored** — license UNRESOLVED
  (`phase1/fxv/ORIGIN.md`), so upstream code never enters git.

Re-fetching with a different commit is forbidden. Changing the pin
itself is an owner decision recorded in `fxv/ORIGIN.md`'s re-pin
history (last: 2026-11-11, `55ad91a2` -> `c1c5d89`,
`docs/firefox-vpn/core-update-2026-11-11.md`).

## 3. Build the engine

```bash
phase1/scripts/build_engine.sh [arm64-v8a|armeabi-v7a|x86_64|host|all]
```

What the script enforces (fail-closed):

1. `go` present, version asserted.
2. The pinned upstream is present and matches the SHA256 manifest.
3. For every **Android** target: `CGO_ENABLED=1` is forced; an explicit
   `CGO_ENABLED=0` in the environment is **refused** (the known-broken
   pure-Go Android configuration — see
   [dns-resolution.md](dns-resolution.md)).
4. The per-ABI NDK compiler exists and is executable.
5. Outputs land in `phase1/build/android/<abi>/libfirefoxvpn.so` and
   `phase1/build/host/libfirefoxvpn` — never overwriting without
   backup.
6. `phase1/build/SHA256SUMS.txt` records every binary.

The **host** build (linux/amd64, pure Go) is the Dart test vehicle
(`FXV_ENGINE_BIN`), not a deliverable.

## 4. ELF verification (after every build)

```bash
file      phase1/build/android/<abi>/libfirefoxvpn.so
readelf -d          phase1/build/android/<abi>/libfirefoxvpn.so
readelf --dyn-syms  phase1/build/android/<abi>/libfirefoxvpn.so
```

The script itself checks and fails on:

* **no NEEDED entries** → not a CGO/Bionic build (A1 violation);
* **`getaddrinfo` not imported** → the Bionic system resolver is not
  wired (A1 violation).

Symbols that must appear in `--dyn-syms`: `getaddrinfo`,
`freeaddrinfo`, `gai_strerror`, `res_search`. Recorded inspection
evidence: `phase1/build/android/<abi>/libfirefoxvpn.so.inspection.txt`.

## 5. Stage into the APK

```bash
cp phase1/build/android/<abi>/libfirefoxvpn.so \
   android/app/src/main/jniLibs/<abi>/libfirefoxvpn.so
```

`jniLibs/` is **gitignored by standing policy** — binaries enter the
APK at build time, never git. The four OTHER native cores
(libaether/liblyrebird/libpsiphon/libzeptun-jni) come from the native
CI builds or the official release APKs — see
[recovery-guide.md](recovery-guide.md).

## 6. Recorded binary evidence (2026-11-09 builds)

| Target | Size (B) | SHA256 |
|---|---|---|
| arm64-v8a | 14,445,672 | `a404bbbb67e58d153fe439fee3996ebb24458f0cd7263cc30ea6ce2bde980a2b` |
| armeabi-v7a | 14,264,000 | `05e94c7480bfe1505095d3f8133826fab1025383fa0fbc9eb739c264dde9a323` |
| x86_64 | 15,403,296 | `ec698230a4f551fb71bd7ff13151267221ca3a0423b080a4c9876ee68e639b13` |
| host | 14,188,599 | `89ef32fd5e08725513ee4fb006d750fee5f911844a602463acf3c096fc3bf06f` |

All three Android ABIs verified CGO + NDK r28c with Bionic evidence
(`.inspection.txt` files, committed). On-device runtime verification
per ABI: **NOT RUN** — no device/emulator in the agent environment;
the owner performs it in the device-acceptance phase.

## 7. Go tests (not part of the corrective session)

`go test ./...` / `go vet ./...` — recorded green (85/85) on
2026-11-09 in the prior session. Corrective session status:
**NOT RUN — OWNER REQUEST**.

Re-run 2026-11-11 on `update/firefox-vpn-core` (upstream re-pinned to
`c1c5d89`, Firefox identity 160.0): `go vet` PASS, `go test` **98/98
PASS** (7 packages), `go build` PASS, and the pinned upstream module's
own tests PASS — evidence table in
[core-update-2026-11-11.md](core-update-2026-11-11.md) §4.
