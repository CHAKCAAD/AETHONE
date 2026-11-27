# AETHONE real-device test helpers (adb)

These scripts support [docs/family-shield-device-testing.md](../../docs/family-shield-device-testing.md).
They collect evidence from the owner's phone over adb. They never root the phone, never uninstall
anything unless asked (`--allow-uninstall`), and never clear logcat.

Requirements: Android platform-tools (`adb`) and bash (Linux, macOS, or Git Bash on Windows). Optional:
`apksigner`/`aapt2` (Android build-tools) for signer checks on the host. Run them from the folder
where you want `aethone-device-evidence/` created (override with `EV_ROOT=`). With more than one
device attached, set `ANDROID_SERIAL`.

| Script | What it does |
|---|---|
| `check-device.sh` | DT-ENV-01: ABI, Android/SDK, ROM, page size, Private DNS, Always-on, battery buckets, installed AETHONE builds; warns on emulators |
| `install.sh <apk> [--allow-uninstall]` | Records the APK SHA-256 and signer, installs it, and reports a signature mismatch (old key → new key) without uninstalling |
| `hooks.sh on\|off\|probe` | Turns the **DA-build-only** debug hook on or off (`debug.aethone.shieldtest`). On a release build it reports UNAVAILABLE and does nothing |
| `shield.sh <cmd>` | Family Shield through the hook: `setup`, `status`, `block/allow <domain>`, `rules`, `unrule`, `restrict-app <pkg> on\|off`, `restrict-shell on\|off`, `category`, `unknown`, `strict`, `enable/disable`, `pin-state`, `pin-try`, `recover`, `export`, `import`, `import-nosession`, `admin <method> k=v…` |
| `baseline.sh [label]` | Direct egress (VPN **off**): IPv4/IPv6 addresses used to flag leaks |
| `collect.sh <ID> [note]` | Standard evidence snapshot (logcat filtered + crash, dumpsys connectivity/vpn_management, ip addr/route/rule v4+v6, listeners 1819–1822, processes, meminfo, settings, shield status) |
| `socks-probe.sh <ID> [label]` | Lists 1819–1822 listeners and their bind address, and checks whether uid 2000 gets a SOCKS5 reply |
| `dns-check.sh <ID> [--no-cache-test]` | Allowed → fake IP + HTTP; blocked → NXDOMAIN; cached fake IP refused after a live block |
| `appblock-check.sh <ID>` | Restricts and releases the shell uid through the shield and checks its traffic |
| `leakwatch.sh <ID> <seconds>` | Egress sampler (~every 2–25 s): TUNNEL / BLOCKED / LEAK per sample, CSV + summary |
| `doze.sh <ID> <min> [deep\|light\|standby-rare\|standby-restricted]` | Forces Doze/standby with the tunnel up, samples egress, and always restores |
| `matrix.sh [--list] [--only CODES] [--from CODE] [--quick]` | Guided run over every single-tunnel protocol and every hybrid × WARP-leg combination (CON, LSN, DNS, APP, LEAK, KS) |
| `bundle.sh` | Zips the evidence + `results.csv` + `RESULTS.md` (falls back to python, PowerShell or tar.gz) |
| `results-template.csv`, `RESULTS-TEMPLATE.md` | Templates the owner fills in (one CSV row per test ID; generated with the doc by `doc-src/gen.py`) |

## Typical session

```bash
./scripts/device-test/check-device.sh
./scripts/device-test/install.sh aethone-DEVICE-TEST-arm64-v8a-r<run>-release-NOT-A-RELEASE.apk
./scripts/device-test/install.sh aethone-DEVICE-TEST-DA-debuggable-arm64-v8a-r<run>.apk
./scripts/device-test/hooks.sh on
./scripts/device-test/baseline.sh wifi-home          # AETHONE disconnected, Always-on off
./scripts/device-test/shield.sh setup                # DA build: test PIN 583920 + profile + enable
# connect in the AETHONE DA app, then:
./scripts/device-test/dns-check.sh DT-DNS-01
./scripts/device-test/matrix.sh --quick              # walk the protocols
cp ./scripts/device-test/results-template.csv aethone-device-evidence/results.csv   # fill it
./scripts/device-test/bundle.sh
./scripts/device-test/hooks.sh off
```

## Notes

* **Release builds contain no reachable test hook.** `DeviceTestReceiver` is in the debug source set
  only. It is exported with `android.permission.DUMP`, which the adb shell holds and an ordinary app
  can only get through adb, and it is inert unless `debug.aethone.shieldtest=1`. CI fails the
  `device-test-apk` job if a release APK declares it.
* Probes run as the adb shell (uid 2000) with toybox `nc` and `ping`, over plain HTTP. Through the
  tunnel, names resolve to fake IPs (`198.18.0.0/15`, `fc00::/18`); that is expected.
* Values passed to `shield.sh` must not contain spaces (adb joins the arguments into one shell line).
* Some ROMs (certain MIUI/HyperOS builds) refuse `setprop` or `settings put` from adb until "USB debugging
  (Security settings)" is on. Record it as BLOCKED with the error text.
* `matrix.sh` writes automatic verdicts to `matrix-results.csv`. Check each one against its evidence
  folder before you copy it into `results.csv`. Nothing counts as device-tested without evidence.
