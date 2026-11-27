# Family Shield — real-device test protocol (owner's Android phone)

Branch `feature/family-shield-device-test` (from `feature/family-shield-phase2` @ `f6e4dbf`).
Helper scripts: [`scripts/device-test/`](../scripts/device-test/README.md).

**Read this first.**

* **Nothing in this file has been run on a real device.** It is a protocol for the owner. Every result
  comes from the owner's phone and the evidence bundle they send back. Hark has no device. A row is
  PASS only when its evidence is in the bundle.
* **Emulator results are not device results.** The CI `shield-e2e` job runs on an x86_64 Android 16
  emulator, with a SOCKS **test stub** in place of the real cores ([testing §5](family-shield-testing.md)).
  The results CSV keeps them in a separate `platform` column (`device` / `emulator`). An emulator row
  never closes a device row. `check-device.sh` warns when `ro.kernel.qemu=1` or the ABI is x86.
* **Some rows are expected to FAIL today.** They are known gaps, listed so the device result confirms
  them: the real cores' listeners on 1819–1822 are not guarded (security §5 A, §8). Do not mark an
  expected failure as PASS.
* **This is not a release.** The APKs from this branch are labelled `DEVICE-TEST … NOT-A-RELEASE`. Do not
  publish them or give them to anyone else.

Legend for results: `PASS` · `FAIL` · `FAIL-KNOWN-GAP` (expected failure, listed in §14) · `N/A` (the
build or the device cannot run this; give the reason) · `BLOCKED` (an earlier step failed) ·
`NOT-RUN`.

## 0. Builds, tools, conventions

### 0.1 The two APKs (CI artifact `aethone-device-test-arm64-r<run>-NOT-A-RELEASE`)

| File | Package | Signed by | Debuggable | Use it for |
|---|---|---|---|---|
| `aethone-DEVICE-TEST-arm64-v8a-r<run>-release-NOT-A-RELEASE.apk` | `com.chakcaad.aethone` | the **rotated release key** (from the `release-signing` job). If the secrets were missing in that run it is debug-signed, and `DEVICE_TEST_INFO.txt` says so | no | §2 ABI, §3 listeners, §4 IP, §5 Private DNS, §7 Always-on/Lockdown, §9 migration (install over v1.0.2), §10 Doze, the protocol matrix **without** shield checks |
| `aethone-DEVICE-TEST-DA-debuggable-arm64-v8a-r<run>.apk` | `com.chakcaad.aethone.da` (installs **beside** the release app) | CI debug key (a new key on every CI run) | yes | everything that needs Family Shield: §6 DNS, §8 PIN/Keystore, §9 export/import, the matrix DNS/APP checks |

Why two builds: **phase 2 has no Family Shield screen and no export/import screen** (phase 3 is not
approved). A release build therefore cannot turn the shield on, so DNS filtering and app blocking
can't be tested with it. The DA build carries a debug-only adb test hook, described next.

### 0.2 The debug test hook (DA build only)

* `DeviceTestReceiver` lives in `android/app/src/debug/` and is declared only in
  `src/debug/AndroidManifest.xml`. Release APKs don't contain it. The CI job `device-test-apk` reads the
  release APK's manifest and fails if it is there, or if `ShieldTestReceiver` is exported, or if the
  release APK is debuggable.
* Three locks, all required: (1) the sender must hold `android.permission.DUMP`. The adb shell holds it;
  an ordinary app can only get it through adb. (2) the property `debug.aethone.shieldtest=1`, which
  `hooks.sh on` sets and `hooks.sh off` or a reboot clears. (3) it exists only in the DA build.
* It calls the same admin API the method channel uses (`ShieldChannel.handle`, parent-session gated),
  and the same export/import code as the picker. It uses the fixed **test PIN `583920`** (the CI PIN).
  The DA build is for testing only.
* The release build keeps the existing CI-only `ShieldTestReceiver`. It is **not exported**, needs root
  to reach, and is inert without the property, so a non-rooted phone can't reach it. No hook was added
  to release builds.

### 0.3 Host tools

* Android **platform-tools** (`adb`) on PATH. Phone: Developer options → USB debugging on → authorize
  the computer.
* bash: Linux/macOS terminal, or **Git Bash** on Windows (the scripts set `MSYS_NO_PATHCONV`).
* Optional: Android build-tools (`apksigner`, `aapt2`) on PATH, so `install.sh` records the signer
  certificate on the host.
* Second device on the same Wi-Fi (for DT-LSN-07). Optional: Termux (F-Droid) on the phone, for a
  "foreign app" SOCKS client (DT-LSN-03).

### 0.4 Conventions

* Run the scripts from the folder where the evidence should go (default `./aethone-device-evidence/`).
  Every script writes `aethone-device-evidence/<TEST-ID>/<timestamp>/…`.
* `collect.sh <ID>` is the standard evidence snapshot: filtered logcat + crash buffer, `dumpsys
  connectivity`, `dumpsys vpn_management`, `ip addr/route/rule` (v4+v6, all tables), listeners 1819–1822
  (`netstat`/`ss`/`/proc/net/tcp*`), AETHONE processes, `meminfo`, settings (Private DNS, Always-on),
  Doze state, and shield status JSON (DA build with hooks on; release build: `N/A`).
* Probes run as the adb shell user (uid 2000). Shell traffic follows the VPN like an app's.
  Exit-IP probes are plain HTTP: `http://www.cloudflare.com/cdn-cgi/trace` (gives `ip=`, `loc=`,
  `warp=on|off`), `http://ipv4.icanhazip.com`, `http://ipv6.icanhazip.com`. Test names: `example.com`
  (blocked), `example.net` (allowed), `example.org` (cache test).
* **Before every network-dependent section:** with AETHONE disconnected and Always-on off, run
  `baseline.sh <network-label>` on that network (DT-IP-01). LEAK verdicts compare against it.
* Screenshots: name them `<TEST-ID>-<n>.png` and put them in that test's evidence folder.
* Write the date, time (with zone), network (Wi-Fi/mobile + operator) and the APK file name in every
  result row's notes.
