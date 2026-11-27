## 13. Sending results back

1. Fill `aethone-device-evidence/results.csv` (copy of `scripts/device-test/results-template.csv`, one
   row per test ID above). Use the `platform` column: `device` for this phone. Never copy an emulator
   result into a device row. `matrix.sh` writes its automatic verdicts to `matrix-results.csv`. Check
   each one against its evidence folder before copying it.
2. Write a short `RESULTS.md` (template `scripts/device-test/RESULTS-TEMPLATE.md`): phone, Android,
   ROM, networks used, APK names + SHA-256, what failed, anything surprising.
3. `bundle.sh` → `aethone-device-evidence-<timestamp>.zip`. Send it. It contains this phone's IP
   addresses, Wi-Fi/operator names and logcat excerpts. Review it before sharing it anywhere public.

Test counts per section (generated from the tables above; the CSV template has the same rows):

@@COUNTS@@
## 14. Gaps: what this protocol can't prove, and expected failures

| Area | Status at `f6e4dbf` | Effect on the device run |
|---|---|---|
| Real-core listeners 1819–1822 | Not guarded; `LoopbackGuard` is proven only on the CI test stub (security §8) | DT-LSN-02/03 and every `*-LSN` matrix row: expected **FAIL-KNOWN-GAP**; shield state never `protected` with a core running |
| Family Shield UI / export-import UI | Not implemented (phase 3 not approved); the Dart side of `aethone/family_shield` is never called | Shield checks need the DA build + adb hook; DT-MIG-09 N/A; the hook exercises the Kotlin dispatcher, **not** the Dart channel |
| BiometricPrompt | Not implemented (security §6) | DT-KEY-07 N/A |
| Keystore backing (StrongBox vs TEE), copied-database check | Not logged by the app; needs root | DT-KEY-06 N/A for pass/fail |
| v1.0.2 → new key migration | v1.0.2 has no export; no bridge build exists | DT-MIG-03 N/A; migration is manual (DT-MIG-04) |
| App "Kill Switch" toggle | Saved, but no consumer found in `lib/` or `android/` (grep) | DT-AON-09 records the behaviour; only Android lockdown can stop traffic during gaps |
| IPv6 with the shield off | TUN is IPv4-only when the shield is off | DT-IP-03 decides on device whether Android fails or leaks app IPv6 traffic |
| Shielded fail-closed start | Emulator-proven via the CI-only `break` command; the device hook has no such command | Part of DT-AON-08 is N/A on device |
| Things needing root | Reading `family_shield.db`, `/data/tombstones` directly, `iptables`/`nft` rules of lockdown, killing a core process of the **release** build | Not part of this protocol. Tombstones come through `adb bugreport`. With the DA build you can kill a sidecar as its own uid: `adb shell run-as com.chakcaad.aethone.da kill <pid>` (pid from `processes.txt`; Lantern/Psiphon run as separate processes) |
| Snapshot size / RAM with real category lists | Not measured; content lists are not downloaded in phase 2 | DT-DOZE-06 records RSS only |
| Probe resolution | Each egress sample takes 1–25 s | A leak window shorter than a sample can be missed; the protocol repeats each action 3× |
| 32-bit (armeabi-v7a) | APK built and ELF-checked in CI; never run | DT-ABI-04 N/A without a 32-bit device |

## Appendix A. Emulator vs device: what each covers

| Item | CI emulator (`shield-e2e`, x86_64, Android 16, test stub on 1819) | This device protocol |
|---|---|---|
| CPU / ABI | x86_64 | arm64-v8a (armeabi-v7a optional) |
| Cores | none (SOCKS test stub) | real Aether / Tor / Psiphon / Lantern |
| DNS NXDOMAIN, cached fake IP, revalidation, uid block, profiles, IPv6 capture | PASS (35/35, run 46006344077) | §6, §4, matrix: to be run |
| Loopback guard | PASS on the stub only | real listeners: expected FAIL-KNOWN-GAP |
| Private DNS, Always-on, Lockdown, Doze, vendor ROM, real networks (IPv6-only, handover) | not covered | §5, §7, §10, §4 |
| Keystore pepper on real hardware | not covered | §8 |
| Export/import across uninstall + different signer | export only | §9 |

## Appendix B. Script reference

See [`scripts/device-test/README.md`](../scripts/device-test/README.md).
