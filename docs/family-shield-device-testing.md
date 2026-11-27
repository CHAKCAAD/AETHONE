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

## 1. Setup and device identity

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-ENV-01 | Device facts | either | `check-device.sh` | Writes model, Android version/SDK, security patch, ABI list, ROM (MIUI/HyperOS/One UI/ColorOS), page size, Private DNS, Always-on settings, StrongBox/fingerprint features, installed AETHONE builds. `qemu` is empty (a real device). | `DT-ENV-01/*/device.txt`, ip dumps |
| DT-ENV-02 | Install the release device-test APK | release | Check the APK's SHA-256 against `SHA256SUMS.txt` from the artifact. Run `install.sh aethone-DEVICE-TEST-arm64-v8a-r<run>-release-NOT-A-RELEASE.apk`. If v1.0.2 is installed, this is DT-MIG-02, so do §9 first. | `Success`; the signer SHA-256 matches `DEVICE_TEST_INFO.txt` and is **not** `EB:F3:9C:82:…` (the compromised key); `primaryCpuAbi=arm64-v8a`. | `DT-ENV-02/*/apk.txt`, `install.txt` |
| DT-ENV-03 | Install the DA device-test APK | DA | `install.sh aethone-DEVICE-TEST-DA-debuggable-arm64-v8a-r<run>.apk`, then `hooks.sh probe` and `hooks.sh on`. | Installs beside the release app (`com.chakcaad.aethone.da`, label "AETHONE DA"); `pkgFlags` has `DEBUGGABLE`; `hooks.sh on` prints `"ok":true`. | `apk.txt`, hooks output in `shield-calls.log` |
| DT-ENV-04 | Hooks are absent from the release build | release | With only the release app as target: `PKG=com.chakcaad.aethone hooks.sh probe`; then `adb shell am broadcast -a com.chakcaad.aethone.SHIELD_TEST -n com.chakcaad.aethone/.shield.ShieldTestReceiver --es cmd status`. | `hooks: UNAVAILABLE`; the broadcast is refused (`not exported` / permission denial in logcat) or nothing answers. No `RESULT` line from tag `AethoneShieldTest`. | terminal output + `collect.sh DT-ENV-04` |
| DT-ENV-05 | Only one VPN app active | either | Settings → Network → VPN: note every VPN app installed. Disconnect and disable Always-on for all except AETHONE during the tests. | Only AETHONE (or AETHONE DA) has the VPN slot during a test. | screenshot `DT-ENV-05-1.png` |

## 2. Android ABI (ARM64, armeabi-v7a note)

The device-test APKs carry the AETHONE engines for **arm64-v8a only** (the DA APK also has two small Flutter-plugin libraries for other ABIs; CI records them in `abi-notes.txt`). CI checks every arm64/armv7 library's ELF and seccomp safety; the x86_64 build also runs on the emulator. arm64 has no legacy `poll`/`open` syscalls. No arm64 binary has run on a device yet.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-ABI-01 | Native engines load on arm64 | release | Connect once with MASQUE (any working protocol). `collect.sh DT-ABI-01`. | logcat has `zeptun up on socks` and no `zeptun-load-failed`, `start-threw`, `UnsatisfiedLinkError`, `FATAL EXCEPTION`; `processes.txt` shows the app. | `logcat-filtered.txt`, `logcat-crash.txt` |
| DT-ABI-02 | No seccomp kill / native crash during the whole test day | either | At the end of the day: `collect.sh DT-ABI-02`, and `adb bugreport bugreport.zip` (contains tombstones without root). | No `SIGSYS`, `seccomp`, `Fatal signal` lines for AETHONE processes in `logcat-app-and-crash-grep.txt`; no AETHONE tombstone in the bugreport (`FS/data/tombstones`). | `logcat-app-and-crash-grep.txt`, `bugreport.zip` |
| DT-ABI-03 | 16 KB page-size devices | either | Read `page_size` in DT-ENV-01. | Record the value. If it is 16384, DT-ABI-01 on this phone also proves 16 KB loading; if 4096, write "16 KB not covered on device". | `device.txt` |
| DT-ABI-04 | armeabi-v7a (32-bit) device | release | Only if a 32-bit-only phone is available: install `aethone-armeabi-v7a-r<run>.apk` from the `aethone-apk-r<run>` artifact (or `aethone-apk-signed-r<run>`), repeat DT-ABI-01 and the DT-P-MASQUE rows. | Same as DT-ABI-01. With no 32-bit device: `N/A — no armeabi-v7a device`. | as DT-ABI-01 |

## 3. Local listeners 1819–1822 (Aether, Tor, Psiphon, Lantern)

Requirement: **no other app and no adb shell may use these listeners.** Known state at `f6e4dbf`: the real cores bind their own sockets and are **not** behind `LoopbackGuard` (security §5 A, §8). The expected result for DT-LSN-02/03 is therefore `FAIL-KNOWN-GAP`; the device run confirms it and records the exact ports per protocol. Ports: 1819 = Aether main `--bind` (and plain Tor/Psiphon in the -ONLY modes), 1820 = Aether `--tor-bind`, 1821 = Aether `--psiphon-bind`, 1822 = Lantern sidecar.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-LSN-01 | Which ports listen, per protocol, and on which address | release | For MASQUE, TOR ONLY, AETHER→TOR, AETHER→PSIPHON, PSIPHON ONLY, LANTERN: connect, then `socks-probe.sh DT-LSN-01 <protocol>`. | Every listening port is bound to `127.0.0.1` (`0100007F`) only. **No** `WILDCARD-BIND` (0.0.0.0 / ::). Ports listed per protocol match the table above. | `socks-probe.txt`, `listeners-raw.txt` per protocol |
| DT-LSN-02 | adb shell (uid 2000) cannot use a listener | release | Same runs as DT-LSN-01 (the script sends a SOCKS5 greeting from uid 2000). | Requirement: `foreign_uid2000=no-reply` on every listening port. **Expected today: `socks-reply` → FAIL-KNOWN-GAP.** | `socks-probe.txt` |
| DT-LSN-03 | Another app cannot use a listener | release | Termux: `pkg install curl`; while connected run `curl -m 15 --socks5-hostname 127.0.0.1:1819 http://www.cloudflare.com/cdn-cgi/trace` (repeat for each listening port). | Requirement: connection refused/reset, no trace output. **Expected today: the trace prints (warp=on or the Tor/Psiphon/Lantern exit) → FAIL-KNOWN-GAP.** Record which ports answered. | Termux screenshot(s) `DT-LSN-03-*.png` |
| DT-LSN-04 | Shield status reports the exposure | DA | DA build, hooks on, `shield.sh setup`, connect MASQUE, `shield.sh status`. | `state` is **not** `protected`; `reasons` contains `local-socks-exposed:<ports>` listing every port that answered in DT-LSN-02; `listeners[]` shows `guarded:false` for them. | `shield-calls.log`, `collect.sh DT-LSN-04` |
| DT-LSN-05 | Listeners close on disconnect | release | Disconnect in the app; wait 10 s; `socks-probe.sh DT-LSN-05`. | All four ports `listening=no`. | `socks-probe.txt` |
| DT-LSN-06 | Listeners after a core crash / app swipe-away | release | Connected (LANTERN, then PSIPHON ONLY): swipe the app away from recents; wait 30 s; `socks-probe.sh DT-LSN-06`. | Either the tunnel is still up (foreground service) and the ports are as in DT-LSN-01, or everything is closed. A port left listening with no tunnel is a FAIL. | `socks-probe.txt`, `collect.sh` |
| DT-LSN-07 | Not reachable from the LAN | release | Phone on Wi-Fi and connected. From a second device on the same Wi-Fi: `nc -vz <phone-wifi-ip> 1819` (and 1820–1822). The phone IP is in `ip-addr.txt` (wlan0). | Connection refused / timeout on every port. | terminal output of the second device (text or photo) |

## 4. IPv4 and IPv6 (dual-stack, IPv6-only, leak checks)

Important code fact: the TUN gets an IPv6 address and `::/0` **only while Family Shield is on** (`fdfe:dcba:9876::1/126`). With the shield off the TUN is IPv4-only. That is the v1.0.2 behaviour, and phase 1 named it bypass (B). DT-IP-03 measures what Android then does with an app's IPv6 traffic on a dual-stack network: fails, or leaks. The protocol does not assume either answer.

Networks: (a) **dual-stack** Wi-Fi or mobile data (DT-ENV-01 `ip6-addr.txt` shows a global `2…`/`3…` address on wlan0/rmnet); (b) **IPv6-only**: a carrier APN set to `IPv6` only (Settings → Mobile network → Access Point Names → APN protocol), or a router with IPv6-only + NAT64/DNS64. Android's 464XLAT (`v4-` interface) then provides IPv4. If neither is available, mark the row `N/A — no <kind> network` and say which networks you have.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-IP-01 | Direct baseline per network | either | VPN off, Always-on off: `baseline.sh wifi-<name>` and `baseline.sh mobile-<operator>`. | `direct_v4` filled; `direct_v6` filled on a dual-stack network (else `none` → IPv6 rows on this network are N/A). | `baseline-*.txt`, `DT-IP-01/*` |
| DT-IP-02 | IPv4 exit is the tunnel (shield off) | release | Connect MASQUE. `leakwatch.sh DT-IP-02 60`. | 0 LEAK samples; `warp=on` in every sample (MASQUE exits through WARP). | `samples.csv`, `summary.txt` |
| DT-IP-03 | IPv6 with the shield OFF on a dual-stack network | release | Dual-stack network, connect MASQUE, `collect.sh DT-IP-03`, `leakwatch.sh DT-IP-03 60`. In Chrome open `https://test-ipv6.com` and `https://ipleak.net` and take screenshots. | Requirement: **no sample with `v6=` equal to `direct_v6`**, and the leak sites show no ISP IPv6 address. `ip6-route-table-all.txt` shows whether the VPN table has `::/0`. Any baseline IPv6 = FAIL (IPv6 leak with the shield off). | `samples.csv`, `ip6-route*.txt`, screenshots |
| DT-IP-04 | IPv6 captured with the shield ON | DA | DA, `shield.sh setup`, connect MASQUE (reconnect after setup: enabling needs a reconnect). `collect.sh DT-IP-04`, `shield.sh status`. | `ip-addr.txt`: tun has `fdfe:dcba:9876::1/126`; `ip6-route-table-all.txt`: `::/0` via the tun; status `ipv6Route:true`, no `ipv6-not-captured` reason. | `ip*.txt`, `shield-status.json` |
| DT-IP-05 | IPv6 traffic goes through the tunnel (shield ON) | DA | Same session as DT-IP-04 on a dual-stack network: `leakwatch.sh DT-IP-05 60`, then `shield.sh status` twice, 30 s apart, while Chrome loads `https://ipv6.google.com`. | 0 LEAK samples; `ipv6Packets` grows between the two status reads; ipv6.google.com loads through the tunnel. If it doesn't load, record that and the error. | `samples.csv`, `shield-calls.log`, screenshot |
| DT-IP-06 | IPv6-only network (with 464XLAT/NAT64) | release | IPv6-only network. Connect each of MASQUE, WIREGUARD, LANTERN, PSIPHON ONLY in turn; for each, record whether it connects and run `leakwatch.sh DT-IP-06-<proto> 30`. Repeat MASQUE with the app's IP version setting at v4, v6, dual. | Each protocol either connects with 0 LEAK samples, or fails cleanly (app shows an error, no traffic leaves directly). Record which IP-version setting works. A direct-IPv6 sample = FAIL. | per-protocol `samples.csv`, `collect.sh` |
| DT-IP-07 | Dual-stack: IP version setting v4 / v6 / dual | release | Dual-stack network, MASQUE, app setting IP version = v4, then v6, then dual. Connect each time and run `leakwatch.sh DT-IP-07-<v> 30`. | Connect result recorded per setting; 0 LEAK samples in each. | `samples.csv` ×3 |
| DT-IP-08 | Browser leak sites | release | Connected (MASQUE, then LANTERN): Chrome → `https://ipleak.net`, `https://browserleaks.com/ip`, `https://dnsleaktest.com` (standard test). | No ISP IPv4/IPv6 address; the DNS servers shown are not your ISP's resolvers (they belong to the exit network). Screenshot each. | screenshots `DT-IP-08-*.png` |
| DT-IP-09 | WebRTC leak | release | Connected: Chrome → `https://browserleaks.com/webrtc`. | No public ISP address in the WebRTC candidates (local `192.168.x`/mDNS names are fine). | screenshot |

## 5. Private DNS: off / automatic / strict hostname

Android sends Private DNS (DoT, port 853) per network. With a VPN up, apps resolve on the VPN network. The shield's strict mode can block 853, but drops that block when Private DNS is in strict hostname mode (security §5). Each mode is tested with the shield off, the shield on, and strict mode on.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-PDNS-OFF-1 | Private DNS off: shield off, MASQUE | release | `adb shell settings put global private_dns_mode off` (or Settings → Network → Private DNS). Connect MASQUE. `collect.sh DT-PDNS-OFF-1`; `leakwatch.sh DT-PDNS-OFF-1 30`; in Chrome load 3 sites. | Connects; sites load; 0 LEAK samples. Record `PrivateDnsConfig` of the VPN network from `dumpsys-connectivity.txt`. | `dumpsys-connectivity.txt`, `samples.csv` |
| DT-PDNS-OFF-2 | Private DNS off: shield on (strict mode off) | DA | `adb shell settings put global private_dns_mode off`. DA, `shield.sh setup`, reconnect. `dns-check.sh DT-PDNS-OFF-2`. | dns-check PASS (allowed name → fake IP + HTTP; `example.com` → unknown host). Browsing works. | `dns-check.txt`, `shield-status.txt` |
| DT-PDNS-OFF-3 | Private DNS off: shield strict mode on | DA | `adb shell settings put global private_dns_mode off`. `shield.sh strict on dot quic altdns`, reconnect, `dns-check.sh DT-PDNS-OFF-3`, `shield.sh status`, browse 3 sites. | DNS keeps working (dns-check PASS, sites load). Status reasons do **not** contain `private-dns-strict`. | `dns-check.txt`, `shield-calls.log` |
| DT-PDNS-AUTO-1 | Private DNS automatic: shield off, MASQUE | release | `adb shell settings put global private_dns_mode opportunistic` (or Settings → Network → Private DNS). Connect MASQUE. `collect.sh DT-PDNS-AUTO-1`; `leakwatch.sh DT-PDNS-AUTO-1 30`; in Chrome load 3 sites. | Connects; sites load; 0 LEAK samples. Record `PrivateDnsConfig` of the VPN network from `dumpsys-connectivity.txt`. | `dumpsys-connectivity.txt`, `samples.csv` |
| DT-PDNS-AUTO-2 | Private DNS automatic: shield on (strict mode off) | DA | `adb shell settings put global private_dns_mode opportunistic`. DA, `shield.sh setup`, reconnect. `dns-check.sh DT-PDNS-AUTO-2`. | dns-check PASS (allowed name → fake IP + HTTP; `example.com` → unknown host). Browsing works. | `dns-check.txt`, `shield-status.txt` |
| DT-PDNS-AUTO-3 | Private DNS automatic: shield strict mode on | DA | `adb shell settings put global private_dns_mode opportunistic`. `shield.sh strict on dot quic altdns`, reconnect, `dns-check.sh DT-PDNS-AUTO-3`, `shield.sh status`, browse 3 sites. | DNS keeps working (dns-check PASS, sites load). Status reasons do **not** contain `private-dns-strict`. | `dns-check.txt`, `shield-calls.log` |
| DT-PDNS-STRICT-1 | Private DNS strict hostname `dns.google`: shield off, MASQUE | release | `adb shell settings put global private_dns_specifier dns.google` then `adb shell settings put global private_dns_mode hostname` (or Settings → Network → Private DNS). Connect MASQUE. `collect.sh DT-PDNS-STRICT-1`; `leakwatch.sh DT-PDNS-STRICT-1 30`; in Chrome load 3 sites. | Connects; sites load; 0 LEAK samples. Record `PrivateDnsConfig` of the VPN network from `dumpsys-connectivity.txt`. | `dumpsys-connectivity.txt`, `samples.csv` |
| DT-PDNS-STRICT-2 | Private DNS strict hostname `dns.google`: shield on (strict mode off) | DA | `adb shell settings put global private_dns_specifier dns.google` then `adb shell settings put global private_dns_mode hostname`. DA, `shield.sh setup`, reconnect. `dns-check.sh DT-PDNS-STRICT-2`. | dns-check PASS (allowed name → fake IP + HTTP; `example.com` → unknown host). Browsing works. | `dns-check.txt`, `shield-status.txt` |
| DT-PDNS-STRICT-3 | Private DNS strict hostname `dns.google`: shield strict mode on | DA | `adb shell settings put global private_dns_specifier dns.google` then `adb shell settings put global private_dns_mode hostname`. `shield.sh strict on dot quic altdns`, reconnect, `dns-check.sh DT-PDNS-STRICT-3`, `shield.sh status`, browse 3 sites. | DNS keeps working (dns-check PASS, sites load). Status reasons contain `private-dns-strict` (the 853 block is dropped so device DNS is not cut). | `dns-check.txt`, `shield-calls.log` |
| DT-PDNS-BAD | Private DNS strict with an unreachable hostname | DA | `settings put global private_dns_specifier no-such-host.invalid` + mode `hostname`; shield on; connect MASQUE; `dns-check.sh DT-PDNS-BAD`. | Record the result: Android marks the network "Private DNS server cannot be accessed". Whether the tunnel's fake-IP DNS still answers, and whether the shield still blocks `example.com`, is what this row records. Any **direct** DNS/HTTP = FAIL. | `dns-check.txt`, screenshot of the notification |
| DT-PDNS-RESET | Restore Private DNS | either | `adb shell settings put global private_dns_mode opportunistic` (or the owner's previous value from DT-ENV-01). | `settings get global private_dns_mode` = the value before the tests. | terminal output |

## 6. DNS filtering, DNS cache and fake IPs

DA build, hooks on, `shield.sh setup`, then reconnect MASQUE.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-DNS-01 | Allowed name gets a fake IP and works | DA | `dns-check.sh DT-DNS-01` (it runs 01–05 in one go; record each line). | `example.net` resolves to `198.18.x.x`/`198.19.x.x` (IPv4 fake range) and answers HTTP. | `dns-check.txt` |
| DT-DNS-02 | Blocked name → NXDOMAIN, no connection | DA | (same run) | `example.com` → `unknown-host`; no HTTP answer. | `dns-check.txt`, `http-block.txt` |
| DT-DNS-03 | Blocked after it was resolved: cached fake IP refused | DA | (same run: `example.org` resolved and used, then blocked live, then the same fake IP is dialled) | Before the block the fake IP answers HTTP; after `shield.sh block example.org` (answer `applied:ok`, no reconnect) the **same fake IP** gets no HTTP; a new lookup → `unknown-host`. | `dns-check.txt`, `http-cache-after-block.txt` |
| DT-DNS-04 | Open connection killed on block (revalidation) | DA | Chrome: start a long download or video on `example.org` or another allowed site X; while it runs, `shield.sh block <X>`. | The transfer stops within ~1–2 s; other tabs keep working. Shield status `flowsKilled` grows. | `shield-calls.log` (status before/after), screen recording or screenshots |
| DT-DNS-05 | App-level DNS cache (browser) | DA | Chrome: open `https://example.org` (allowed). `shield.sh block example.org`. Reload in the same tab, then in a new tab. | Both reloads fail ("site can't be reached" / connection reset), even though Chrome cached the address. | screenshots |
| DT-DNS-06 | Unblock restores access | DA | `shield.sh rules` → id of the `example.org` rule → `shield.sh unrule <id>`; reload. | Loads again without reconnecting. | `shield-calls.log` |
| DT-DNS-07 | Fake IPs after a tunnel restart | DA | Resolve `example.net` (note the fake IP). Disconnect + reconnect. Dial the **old** fake IP: `adb shell "printf 'GET / HTTP/1.0\r\nHost: example.net\r\n\r\n' \| toybox nc -w 8 <old-ip> 80"`. | Either it reaches example.net or it fails. It must **never** reach a different site. Record which. | terminal output |
| DT-DNS-08 | Browser Secure DNS (DoH) | DA | Chrome → Settings → Privacy → Use secure DNS → On (Cloudflare). Then open `https://example.com` (blocked). Repeat with `shield.sh strict on dot quic altdns` and `shield.sh category bypass on`. | Record whether example.com loads in each case. With strict mode + bypass category it must not load. Default (no strict): record the result; known limit = DoH to unknown endpoints is not detectable (security §5). | screenshots, `shield-calls.log` |
| DT-DNS-09 | Hard-coded resolver on UDP/53 | DA | `adb shell "toybox nslookup example.com 8.8.8.8"` (if the ROM's toybox has nslookup) — or Termux `pkg install dnsutils; dig @8.8.8.8 example.com`. | NXDOMAIN or no answer (DNS hijack is on while the shield is on). Never the real A record. | terminal output |

## 7. Always-on VPN and Lockdown ("Block connections without VPN")

Set Always-on by hand: Settings → Network & internet → VPN → gear next to AETHONE → **Always-on VPN** on, then **Block connections without VPN** on. (On Samsung: Connections → More connection settings → VPN; on Xiaomi: Connection & sharing → VPN.) The scripts only read these settings. Setting them over adb doesn't apply them on a running device. Take a baseline first (DT-IP-01). For every "restart" row, start `leakwatch.sh` **before** the action. A sample takes 1–25 s, so repeat each action 3 times.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-AON-01 | Always-on starts the tunnel at boot | release | Always-on on, lockdown off. Reboot. As soon as `adb devices` sees the phone: `leakwatch.sh DT-AON-01 120` and `collect.sh DT-AON-01`. | The tunnel comes up without opening the app (notification shown); record seconds from boot to the first TUNNEL sample. Samples before it may be LEAK (lockdown is off): record how many. | `samples.csv`, `collect.sh` |
| DT-AON-02 | Lockdown at boot: nothing leaves before the tunnel | release | Always-on **and** lockdown on. Reboot; start `leakwatch.sh DT-AON-02 180` as early as possible. | 0 LEAK samples; early samples are BLOCKED, then TUNNEL. | `samples.csv` |
| DT-AON-03 | Lockdown: restart from the app (disconnect → connect) | release | Lockdown on, connected. Start `leakwatch.sh DT-AON-03 120`; in the app disconnect, wait 15 s, connect. Repeat 3×. | 0 LEAK samples; BLOCKED during the gap. Record whether the app's disconnect is allowed under Always-on and what it shows. | `samples.csv`, screenshots |
| DT-AON-04 | Lockdown: protocol switch | release | Lockdown on. `leakwatch.sh DT-AON-04 180`; switch MASQUE → LANTERN → PSIPHON ONLY → MASQUE in the app. | 0 LEAK samples during every switch. | `samples.csv` |
| DT-AON-05 | Lockdown: force-stop / crash | release | Lockdown on, connected. `leakwatch.sh DT-AON-05 120`; `adb shell am force-stop com.chakcaad.aethone`. | 0 LEAK samples. Record whether Always-on restarts the service by itself and after how long. | `samples.csv`, `collect.sh DT-AON-05` |
| DT-AON-06 | Lockdown: network handover | release | Lockdown on, connected on Wi-Fi with mobile data on. `leakwatch.sh DT-AON-06 120`; turn Wi-Fi off, wait 30 s, on. | 0 LEAK samples; the tunnel recovers on each network (record time). | `samples.csv` |
| DT-AON-07 | Lockdown + per-app exclusion | release | Lockdown on. App setting: per-app tunneling = disallow, list = Chrome. Reconnect. In Chrome open `http://ipv4.icanhazip.com`. | Record the result. Android's documented behaviour: excluded apps get **no** network under lockdown. Chrome showing the direct ISP IP = FAIL (leak). | screenshot, `collect.sh DT-AON-07` |
| DT-AON-08 | Lockdown + shield re-enable (reconnect) | DA | The DA app is the Always-on app, lockdown on. `shield.sh setup`, connect. Run `leakwatch.sh DT-AON-08 120`. During it: `shield.sh disable`, `shield.sh enable`, `shield.sh status` (expect `reconnect-required`), then reconnect in the app and run `shield.sh status`. | 0 LEAK samples; after the reconnect the status no longer lists `reconnect-required`, and `engineHook:true`. Fail-closed start with a broken profile is proven only on the emulator (testing §5); the device hook has no "break" command, so that part is N/A on device. | `samples.csv`, `shield-calls.log` |
| DT-AON-09 | The app's own Kill Switch toggle | release | Settings → Connection → Kill Switch: try ON and OFF; repeat DT-AON-03 with lockdown **off**. | Record the result. Code finding: the toggle is saved (`aethone.settings.killSwitch`), but no code in `lib/` or `android/` reads it at `f6e4dbf`. Expect the same behaviour ON and OFF; only Android lockdown blocks traffic during the gap. If ON prevents leaks, record it with evidence. | `samples.csv` ×2 |

## 8. Keystore pepper and biometric

The parent PIN is PBKDF2-HMAC-SHA256 (600 000 iterations), peppered with an HMAC key generated in the Android Keystore (StrongBox when available). **BiometricPrompt is not implemented** (security §6): only the core flag exists. Without root you can't read the database or the Keystore, so a copied database can't be checked on device. DA build, hooks on.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-KEY-01 | PIN setup on device hardware | DA | Fresh DA install (or clear its data). `shield.sh setup`. | `setup` answers `ok:true` and returns a `recoveryCode` (write it down for DT-KEY-04). No Keystore exception in `logcat-filtered.txt`. | `shield-calls.log`, `collect.sh DT-KEY-01` |
| DT-KEY-02 | PIN verifies after force-stop and after reboot | DA | `adb shell am force-stop com.chakcaad.aethone.da`; `shield.sh pin-try 583920`. Reboot, `hooks.sh on`, `shield.sh pin-try 583920`. | Both answer with a `token`. | `shield-calls.log` |
| DT-KEY-03 | Backoff survives app kill | DA | `shield.sh pin-try 111222` ×6; `adb shell am force-stop com.chakcaad.aethone.da`; `shield.sh pin-state`; `shield.sh pin-try 583920`. | Attempts 1–5 `wrong-pin` with `attemptsBeforeLock` counting down; the 6th → locked with `lockedUntil` ≈ now+30 s; after force-stop `pin-state` still shows `lockedUntil`; the correct PIN before it expires → `locked`; after it expires → token. | `shield-calls.log` |
| DT-KEY-04 | Recovery code works once | DA | `shield.sh recover <code from DT-KEY-01>` twice. | First → token; second → refused. | `shield-calls.log` |
| DT-KEY-05 | Clear data removes PIN and key | DA | `adb shell pm clear com.chakcaad.aethone.da`; `hooks.sh on`; `shield.sh pin-state`. | `set:false`. A new `shield.sh setup` works (new Keystore key). | `shield-calls.log` |
| DT-KEY-06 | StrongBox vs TEE | DA | Read `strongbox_feature` in DT-ENV-01. | N/A for pass/fail: the app does not log which backing it got, and it can't be read without root. Record the feature flag only. | `device.txt` |
| DT-KEY-07 | Biometric unlock | DA | — | **N/A — BiometricPrompt UI not implemented** (security §6; `setBiometric` only stores a flag; `MainActivity` is still a `FlutterActivity`). | — |
| DT-KEY-08 | Gated call without a session | DA | Run `adb shell am broadcast -a com.chakcaad.aethone.DEVICE_TEST -n com.chakcaad.aethone.da/com.chakcaad.aethone.shield.DeviceTestReceiver --es cmd admin --es method setEnabled --ez a.enabled false --ez nosession true` and read `adb logcat -d -s AethoneDeviceTest`. | Answer `error: session-required`; shield stays enabled. | logcat line |

## 9. Import / export and the signing-key migration (v1.0.2 old key → new key)

Facts: v1.0.2 is signed with the **compromised** key (`EB:F3:9C:82:…:1C:79`); new builds use the rotated key with **no v3 lineage**, so they can't install over v1.0.2. v1.0.2 has **no** export feature (export was added in phase 2), and phase 2 has no export/import **screen**. So on device, export/import only works through the DA hook, which runs the same `exportText`/`importText` code as the picker. The old → new migration of a real user is therefore **manual** today, as docs/settings-migration.md §5 already states. Keep the v1.0.2 APK from its GitHub release.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-MIG-01 | v1.0.2 baseline | release | Install v1.0.2 (old key) from its GitHub Release; configure it the way you use it (protocol, locations, hybrid rules, per-app list, kill switch, language). Screenshot every settings page. `install.sh` records its signer. | Signer = the compromised cert (expected for v1.0.2 only). Screenshots of all settings. | `apk.txt`, screenshots `DT-MIG-01-*.png` |
| DT-MIG-02 | New-key APK refuses to install over v1.0.2 | release | `install.sh aethone-DEVICE-TEST-arm64-v8a-r<run>-release-NOT-A-RELEASE.apk` (without `--allow-uninstall`). | `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (signatures do not match); v1.0.2 still installed and working. If it installs, the APK is not signed by the new key; check DEVICE_TEST_INFO.txt. | `install.txt` |
| DT-MIG-03 | v1.0.2 export | release | Look for an export function in v1.0.2. | **N/A — v1.0.2 has no settings export** (feature added in phase 2). This is the migration gap: no bridge build exists (owner decision pending, settings-migration.md §5). | — |
| DT-MIG-04 | Manual migration v1.0.2 → new key | release | `install.sh <release apk> --allow-uninstall` (uninstalls v1.0.2 = data loss), re-enter the settings from the DT-MIG-01 screenshots, connect. | New app installed, signer = new cert; the settings are reproducible by hand; it connects. Record the time it took and anything that could not be restored. | `install.txt`, screenshots |
| DT-MIG-05 | Export (DA hook = the picker's code path) | DA | DA app configured (protocol, hybrid rules, per-app list) + `shield.sh setup` + `shield.sh block example.com`. `shield.sh export`. | `ok:true`; `containsTestPin:false`; `profiles` ≥ 1; the pulled JSON has `"format":"aethone-settings"`, `"version":1`, no `pin`/`recovery`/`salt` keys; its sha256 is logged. | `exports/aethone-settings-export.json`, `shield-calls.log` |
| DT-MIG-06 | Uninstall → install → import (cross-signature) | DA | Keep the exported file. `adb uninstall com.chakcaad.aethone.da`. Install a DA APK from a **different** CI run (different debug key = a real cross-signature reinstall), or the same file if you have only one. `hooks.sh on`; `shield.sh import exports/aethone-settings-export.json`; force-stop and reopen the app. | Import answer `ok:true`, `shieldImported:true`, `pinRequired:true`, `restartRequired:true`; after the restart the app settings match DT-MIG-05; `shield.sh config` shows the shield **disabled** until a new PIN is set (`shield.sh setup`), then the `example.com` rule is present (`shield.sh rules`). | `shield-calls.log`, screenshots |
| DT-MIG-07 | Tampered / invalid file is refused, nothing applied | DA | Copy the export, edit it: (a) change `"version":1` to `2`; (b) add `"malware"` to a profile's `categories`; (c) truncate the file. `shield.sh import <file>` each time; then `shield.sh rules`. | (a) `invalid-file` / `newer-version`; (b) `invalid-file`; (c) `invalid-file`; rules unchanged after each. | `shield-calls.log`, the three files |
| DT-MIG-08 | Import needs the parent session when a PIN is set | DA | PIN set (DT-MIG-06 done). `shield.sh import-nosession exports/aethone-settings-export.json`. | `error: session-required`; nothing changed. | `shield-calls.log` |
| DT-MIG-09 | Export/import from the release build UI | release | — | **N/A — no Flutter export/import screen in phase 2** (`settingsExport`/`settingsImport` have no Dart caller). Re-test when the phase-3 screen exists. | — |

## 10. Doze, App Standby, long run, vendor battery killers

`doze.sh` forces the state over adb and always restores it (battery reset, `deviceidle unforce`, bucket active). Forced Doze is not the same as a real overnight idle; DT-DOZE-05 is the real one. Record the app's battery setting first: Settings → Apps → AETHONE → Battery (Unrestricted / Optimized / Restricted).

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-DOZE-01 | Battery settings recorded | release | DT-ENV-01 `standby_bucket`, `doze_whitelisted`, `run_any_in_background`; screenshot of the app battery page; vendor pages from §10.1. | Recorded (no pass/fail). | `device.txt`, screenshots |
| DT-DOZE-02 | Deep Doze 30 min, tunnel up (Optimized) | release | Battery = Optimized. Connect MASQUE, screen off. `doze.sh DT-DOZE-02 30 deep`. | Same pid before/after; after restore the egress is TUNNEL within 60 s; **no LEAK sample** in `during.txt`. Record if traffic was BLOCKED during idle (normal for Doze). | `doze.txt`, `during.txt`, collect snapshot |
| DT-DOZE-03 | Deep Doze 30 min (Unrestricted) | release | Battery = Unrestricted. Repeat DT-DOZE-02 as `doze.sh DT-DOZE-03 30 deep`. | As DT-DOZE-02. | as above |
| DT-DOZE-04 | App Standby rare / restricted | release | `doze.sh DT-DOZE-04a 15 standby-rare`; `doze.sh DT-DOZE-04b 15 standby-restricted` (Android 12+). | Tunnel survives or recovers by itself; no LEAK sample. If the restricted bucket kills it, record that. | `doze.txt` ×2 |
| DT-DOZE-05 | Real overnight run (≥ 8 h) | release | Evening: connect LANTERN (or the protocol used daily), `collect.sh DT-DOZE-05-start`, leave the phone unplugged, screen off. Morning: before touching the app, `collect.sh DT-DOZE-05-end`, `leakwatch.sh DT-DOZE-05 60`, `adb shell dumpsys batterystats com.chakcaad.aethone > batterystats.txt`. | Tunnel still up (or the reason it stopped is in logcat); 0 LEAK samples; no crash; record battery % used overnight and the app's share. | both snapshots, `samples.csv`, `batterystats.txt` |
| DT-DOZE-06 | Long run with the shield on (≥ 4 h, DA) | DA | `shield.sh setup`, connect, normal use for ≥ 4 h, `shield.sh status` every hour (or start/end). | Counters grow and never go backwards; `snapshotRejected` = 0; no crash; RSS in `meminfo.txt` at start vs end recorded. | `shield-calls.log`, `collect.sh` start/end |
| DT-DOZE-07 | Network change during idle | release | Connected, screen off 10 min, then switch Wi-Fi off/on with the screen still off (adb: `adb shell svc wifi disable` / `enable`) while `leakwatch.sh DT-DOZE-07 120` runs. | 0 LEAK samples; tunnel recovers. | `samples.csv` |

### 10.1 Vendor ROM notes (record which ones apply to the test phone)

* **Xiaomi / Redmi / POCO (MIUI, HyperOS):** Security app → Permissions → **Autostart** → AETHONE on;
  Settings → Apps → AETHONE → **Battery saver → No restrictions**; in Recents, long-press AETHONE →
  **lock** (padlock) so "clean all" does not kill it; disable "MIUI optimization" only for the test session if
  adb `setprop`/`settings` writes are refused (Developer options, bottom). MIUI may refuse
  `adb install` until "Install via USB" is enabled (needs a Mi account sign-in). Some MIUI builds kill VPN
  services when the screen locks with "Battery saver" on; test with it on and off.
* **Samsung (One UI):** Settings → Battery → Background usage limits → remove AETHONE from **Sleeping
  / Deep sleeping apps** and add it to **Never sleeping apps**; Apps → AETHONE → Battery → **Unrestricted**.
  "Put unused apps to sleep" and Adaptive battery can still move it, so re-check after a few days. Samsung
  "Auto optimize daily" restarts the phone at night. Turn it off during DT-DOZE-05, or record it.
* **OPPO / OnePlus / realme (ColorOS / OxygenOS):** Battery → App battery management → AETHONE →
  allow background activity + auto launch.
* **Huawei / Honor (EMUI / MagicOS):** App launch → AETHONE → manage manually (all three on).
* Reference for each vendor's background-killing behaviour: https://dontkillmyapp.com (read the page for
  the exact phone model). It is a community source; the device result is what counts.

## 11. Protocol matrix: single-tunnel protocols

Single-tunnel protocols in the app (`lib/core/app_assets.dart` `ProtocolId`, `lib/connection/transport_modes.dart`, `hybrid_routing.dart` `profileOf` = null). Each gets the six checks below. `matrix.sh` walks them interactively; the DNS/APP checks need the DA build with hooks on (they are `N/A-NO-HOOK` on the release build). Run the matrix twice if time allows: release build (CON/LSN/LEAK/KS) and DA build (all six). Before it: `baseline.sh` on the same network.

| Code | In the app | What runs | Listener(s) |
|---|---|---|---|
| AUTO | AUTO / SMART | SMART walk over MASQUE, WIREGUARD, GOOL, MIM, GOOL CLASSIC (scorecard); record which one it picked (logcat) | 1819 |
| MASQUE | MASQUE | Aether, WARP exit | 1819 |
| WG | WIREGUARD | Aether `--protocol wg`, WARP exit | 1819 |
| GOOL | GOOL | Aether `--protocol gool`, WARP exit | 1819 |
| GOOLC | GOOL CLASSIC | Aether `--protocol gool --gool-classic`, WARP exit | 1819 |
| MIM | MIM | Aether `--protocol mim`, WARP exit | 1819 |
| TORONLY | TOR ONLY | plain Tor on 1819 (TCP only — UDP refused by zeptun) | 1819 |
| PSIONLY | PSIPHON ONLY | plain Psiphon on 1819 (TCP only) | 1819 |
| LANTERN | LANTERN | Lantern sidecar `liblantern.so` (separate process), UDP carried | 1822 |

Checks per protocol:

| Check | Pass criterion |
|---|---|
| CON — connects | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. |
| LSN — listeners vs foreign uid | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. |
| DNS — DNS filtering (DA) | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. |
| APP — app blocking (DA) | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. |
| LEAK — no direct leak | 30 s sampling: 0 LEAK samples (v4 and v6). |
| KS — kill switch / disruption | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). |

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-P-AUTO-CON | AUTO / SMART: connects | either | `matrix.sh --only AUTO` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-AUTO-CON/*` |
| DT-P-AUTO-LSN | AUTO / SMART: listeners vs foreign uid | either | `matrix.sh --only AUTO` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-AUTO-LSN/*` |
| DT-P-AUTO-DNS | AUTO / SMART: DNS filtering (DA) | DA | `matrix.sh --only AUTO` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-AUTO-DNS/*` |
| DT-P-AUTO-APP | AUTO / SMART: app blocking (DA) | DA | `matrix.sh --only AUTO` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-AUTO-APP/*` |
| DT-P-AUTO-LEAK | AUTO / SMART: no direct leak | either | `matrix.sh --only AUTO` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-AUTO-LEAK/*` |
| DT-P-AUTO-KS | AUTO / SMART: kill switch / disruption | either | `matrix.sh --only AUTO` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-AUTO-KS/*` |
| DT-P-MASQUE-CON | MASQUE: connects | either | `matrix.sh --only MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-MASQUE-CON/*` |
| DT-P-MASQUE-LSN | MASQUE: listeners vs foreign uid | either | `matrix.sh --only MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-MASQUE-LSN/*` |
| DT-P-MASQUE-DNS | MASQUE: DNS filtering (DA) | DA | `matrix.sh --only MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-MASQUE-DNS/*` |
| DT-P-MASQUE-APP | MASQUE: app blocking (DA) | DA | `matrix.sh --only MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-MASQUE-APP/*` |
| DT-P-MASQUE-LEAK | MASQUE: no direct leak | either | `matrix.sh --only MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-MASQUE-LEAK/*` |
| DT-P-MASQUE-KS | MASQUE: kill switch / disruption | either | `matrix.sh --only MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-MASQUE-KS/*` |
| DT-P-WG-CON | WIREGUARD: connects | either | `matrix.sh --only WG` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-WG-CON/*` |
| DT-P-WG-LSN | WIREGUARD: listeners vs foreign uid | either | `matrix.sh --only WG` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-WG-LSN/*` |
| DT-P-WG-DNS | WIREGUARD: DNS filtering (DA) | DA | `matrix.sh --only WG` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-WG-DNS/*` |
| DT-P-WG-APP | WIREGUARD: app blocking (DA) | DA | `matrix.sh --only WG` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-WG-APP/*` |
| DT-P-WG-LEAK | WIREGUARD: no direct leak | either | `matrix.sh --only WG` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-WG-LEAK/*` |
| DT-P-WG-KS | WIREGUARD: kill switch / disruption | either | `matrix.sh --only WG` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-WG-KS/*` |
| DT-P-GOOL-CON | GOOL: connects | either | `matrix.sh --only GOOL` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-GOOL-CON/*` |
| DT-P-GOOL-LSN | GOOL: listeners vs foreign uid | either | `matrix.sh --only GOOL` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-GOOL-LSN/*` |
| DT-P-GOOL-DNS | GOOL: DNS filtering (DA) | DA | `matrix.sh --only GOOL` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-GOOL-DNS/*` |
| DT-P-GOOL-APP | GOOL: app blocking (DA) | DA | `matrix.sh --only GOOL` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-GOOL-APP/*` |
| DT-P-GOOL-LEAK | GOOL: no direct leak | either | `matrix.sh --only GOOL` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-GOOL-LEAK/*` |
| DT-P-GOOL-KS | GOOL: kill switch / disruption | either | `matrix.sh --only GOOL` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-GOOL-KS/*` |
| DT-P-GOOLC-CON | GOOL CLASSIC: connects | either | `matrix.sh --only GOOLC` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-GOOLC-CON/*` |
| DT-P-GOOLC-LSN | GOOL CLASSIC: listeners vs foreign uid | either | `matrix.sh --only GOOLC` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-GOOLC-LSN/*` |
| DT-P-GOOLC-DNS | GOOL CLASSIC: DNS filtering (DA) | DA | `matrix.sh --only GOOLC` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-GOOLC-DNS/*` |
| DT-P-GOOLC-APP | GOOL CLASSIC: app blocking (DA) | DA | `matrix.sh --only GOOLC` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-GOOLC-APP/*` |
| DT-P-GOOLC-LEAK | GOOL CLASSIC: no direct leak | either | `matrix.sh --only GOOLC` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-GOOLC-LEAK/*` |
| DT-P-GOOLC-KS | GOOL CLASSIC: kill switch / disruption | either | `matrix.sh --only GOOLC` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-GOOLC-KS/*` |
| DT-P-MIM-CON | MIM: connects | either | `matrix.sh --only MIM` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-MIM-CON/*` |
| DT-P-MIM-LSN | MIM: listeners vs foreign uid | either | `matrix.sh --only MIM` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-MIM-LSN/*` |
| DT-P-MIM-DNS | MIM: DNS filtering (DA) | DA | `matrix.sh --only MIM` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-MIM-DNS/*` |
| DT-P-MIM-APP | MIM: app blocking (DA) | DA | `matrix.sh --only MIM` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-MIM-APP/*` |
| DT-P-MIM-LEAK | MIM: no direct leak | either | `matrix.sh --only MIM` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-MIM-LEAK/*` |
| DT-P-MIM-KS | MIM: kill switch / disruption | either | `matrix.sh --only MIM` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-MIM-KS/*` |
| DT-P-TORONLY-CON | TOR ONLY: connects | either | `matrix.sh --only TORONLY` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-TORONLY-CON/*` |
| DT-P-TORONLY-LSN | TOR ONLY: listeners vs foreign uid | either | `matrix.sh --only TORONLY` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-TORONLY-LSN/*` |
| DT-P-TORONLY-DNS | TOR ONLY: DNS filtering (DA) | DA | `matrix.sh --only TORONLY` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-TORONLY-DNS/*` |
| DT-P-TORONLY-APP | TOR ONLY: app blocking (DA) | DA | `matrix.sh --only TORONLY` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-TORONLY-APP/*` |
| DT-P-TORONLY-LEAK | TOR ONLY: no direct leak | either | `matrix.sh --only TORONLY` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-TORONLY-LEAK/*` |
| DT-P-TORONLY-KS | TOR ONLY: kill switch / disruption | either | `matrix.sh --only TORONLY` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-TORONLY-KS/*` |
| DT-P-PSIONLY-CON | PSIPHON ONLY: connects | either | `matrix.sh --only PSIONLY` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-PSIONLY-CON/*` |
| DT-P-PSIONLY-LSN | PSIPHON ONLY: listeners vs foreign uid | either | `matrix.sh --only PSIONLY` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-PSIONLY-LSN/*` |
| DT-P-PSIONLY-DNS | PSIPHON ONLY: DNS filtering (DA) | DA | `matrix.sh --only PSIONLY` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-PSIONLY-DNS/*` |
| DT-P-PSIONLY-APP | PSIPHON ONLY: app blocking (DA) | DA | `matrix.sh --only PSIONLY` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-PSIONLY-APP/*` |
| DT-P-PSIONLY-LEAK | PSIPHON ONLY: no direct leak | either | `matrix.sh --only PSIONLY` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-PSIONLY-LEAK/*` |
| DT-P-PSIONLY-KS | PSIPHON ONLY: kill switch / disruption | either | `matrix.sh --only PSIONLY` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-PSIONLY-KS/*` |
| DT-P-LANTERN-CON | LANTERN: connects | either | `matrix.sh --only LANTERN` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-P-LANTERN-CON/*` |
| DT-P-LANTERN-LSN | LANTERN: listeners vs foreign uid | either | `matrix.sh --only LANTERN` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-P-LANTERN-LSN/*` |
| DT-P-LANTERN-DNS | LANTERN: DNS filtering (DA) | DA | `matrix.sh --only LANTERN` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-P-LANTERN-DNS/*` |
| DT-P-LANTERN-APP | LANTERN: app blocking (DA) | DA | `matrix.sh --only LANTERN` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-P-LANTERN-APP/*` |
| DT-P-LANTERN-LEAK | LANTERN: no direct leak | either | `matrix.sh --only LANTERN` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-P-LANTERN-LEAK/*` |
| DT-P-LANTERN-KS | LANTERN: kill switch / disruption | either | `matrix.sh --only LANTERN` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-P-LANTERN-KS/*` |

## 12. Protocol matrix: hybrid protocols × WARP leg, and hybrid routing rules

Hybrid protocols (`HybridRouting.profileOf` ≠ null) run two SOCKS listeners in one Aether process. The WARP leg is chosen per family in the Tor / Psiphon settings (`AetherLegProtocol`: WireGuard, MASQUE, GOOL, GOOL Classic, MIM). The CHAIN modes pass the leg as chosen. The REVERSE modes are TCP-only, so `protocolArgs` maps WireGuard and GOOL Classic to MASQUE; those two rows check that mapping. AUTO as the leg resolves to MASQUE (not a separate row). Tor bridges (auto/off/custom) and Psiphon fronting (auto/cdn/direct) are settings variants, not protocols. Test them only if a combination fails, and note which variant you used.

| Code | In the app | Routes (default / second) | Legs tested | Note |
|---|---|---|---|---|
| TORCHAIN | AETHER → TOR | WARP → Tor (1820, default) / WARP (1819) | WireGuard, MASQUE, GOOL, GOOL Classic, MIM | TCP only |
| TORREV | TOR → AETHER | Tor → WARP (1819, default) / Tor (1820) | MASQUE, GOOL, MIM, WireGuard (→ MASQUE), GOOL Classic (→ MASQUE) | TCP only; WireGuard/GOOL Classic legs are mapped to MASQUE by the app |
| PSICHAIN | AETHER → PSIPHON | WARP → Psiphon (1821, default) / WARP (1819) | WireGuard, MASQUE, GOOL, GOOL Classic, MIM | TCP only |
| PSIREV | PSIPHON → AETHER | Psiphon → WARP (1819, default) / Psiphon (1821) | MASQUE, GOOL, MIM, WireGuard (→ MASQUE), GOOL Classic (→ MASQUE) | TCP only; WireGuard/GOOL Classic legs are mapped to MASQUE |

The six checks of §11 apply to every hybrid × leg combination (`matrix.sh --only H-<CODE>-<LEG>`). Then, with leg MASQUE, the routing-rule rows (DT-HR-*) check each rule kind (app, domain, wildcard, CIDR) sends traffic to the second route.

| ID | Test | Build | Steps | Pass criteria | Evidence |
|---|---|---|---|---|---|
| DT-H-TORCHAIN-WG-CON | AETHER → TOR, WARP leg WireGuard: connects | either | `matrix.sh --only H-TORCHAIN-WG` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORCHAIN-WG-CON/*` |
| DT-H-TORCHAIN-WG-LSN | AETHER → TOR, WARP leg WireGuard: listeners vs foreign uid | either | `matrix.sh --only H-TORCHAIN-WG` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORCHAIN-WG-LSN/*` |
| DT-H-TORCHAIN-WG-DNS | AETHER → TOR, WARP leg WireGuard: DNS filtering (DA) | DA | `matrix.sh --only H-TORCHAIN-WG` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORCHAIN-WG-DNS/*` |
| DT-H-TORCHAIN-WG-APP | AETHER → TOR, WARP leg WireGuard: app blocking (DA) | DA | `matrix.sh --only H-TORCHAIN-WG` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORCHAIN-WG-APP/*` |
| DT-H-TORCHAIN-WG-LEAK | AETHER → TOR, WARP leg WireGuard: no direct leak | either | `matrix.sh --only H-TORCHAIN-WG` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORCHAIN-WG-LEAK/*` |
| DT-H-TORCHAIN-WG-KS | AETHER → TOR, WARP leg WireGuard: kill switch / disruption | either | `matrix.sh --only H-TORCHAIN-WG` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORCHAIN-WG-KS/*` |
| DT-H-TORCHAIN-MASQUE-CON | AETHER → TOR, WARP leg MASQUE: connects | either | `matrix.sh --only H-TORCHAIN-MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORCHAIN-MASQUE-CON/*` |
| DT-H-TORCHAIN-MASQUE-LSN | AETHER → TOR, WARP leg MASQUE: listeners vs foreign uid | either | `matrix.sh --only H-TORCHAIN-MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORCHAIN-MASQUE-LSN/*` |
| DT-H-TORCHAIN-MASQUE-DNS | AETHER → TOR, WARP leg MASQUE: DNS filtering (DA) | DA | `matrix.sh --only H-TORCHAIN-MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORCHAIN-MASQUE-DNS/*` |
| DT-H-TORCHAIN-MASQUE-APP | AETHER → TOR, WARP leg MASQUE: app blocking (DA) | DA | `matrix.sh --only H-TORCHAIN-MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORCHAIN-MASQUE-APP/*` |
| DT-H-TORCHAIN-MASQUE-LEAK | AETHER → TOR, WARP leg MASQUE: no direct leak | either | `matrix.sh --only H-TORCHAIN-MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORCHAIN-MASQUE-LEAK/*` |
| DT-H-TORCHAIN-MASQUE-KS | AETHER → TOR, WARP leg MASQUE: kill switch / disruption | either | `matrix.sh --only H-TORCHAIN-MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORCHAIN-MASQUE-KS/*` |
| DT-H-TORCHAIN-GOOL-CON | AETHER → TOR, WARP leg GOOL: connects | either | `matrix.sh --only H-TORCHAIN-GOOL` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORCHAIN-GOOL-CON/*` |
| DT-H-TORCHAIN-GOOL-LSN | AETHER → TOR, WARP leg GOOL: listeners vs foreign uid | either | `matrix.sh --only H-TORCHAIN-GOOL` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORCHAIN-GOOL-LSN/*` |
| DT-H-TORCHAIN-GOOL-DNS | AETHER → TOR, WARP leg GOOL: DNS filtering (DA) | DA | `matrix.sh --only H-TORCHAIN-GOOL` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORCHAIN-GOOL-DNS/*` |
| DT-H-TORCHAIN-GOOL-APP | AETHER → TOR, WARP leg GOOL: app blocking (DA) | DA | `matrix.sh --only H-TORCHAIN-GOOL` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORCHAIN-GOOL-APP/*` |
| DT-H-TORCHAIN-GOOL-LEAK | AETHER → TOR, WARP leg GOOL: no direct leak | either | `matrix.sh --only H-TORCHAIN-GOOL` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORCHAIN-GOOL-LEAK/*` |
| DT-H-TORCHAIN-GOOL-KS | AETHER → TOR, WARP leg GOOL: kill switch / disruption | either | `matrix.sh --only H-TORCHAIN-GOOL` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORCHAIN-GOOL-KS/*` |
| DT-H-TORCHAIN-GOOLC-CON | AETHER → TOR, WARP leg GOOL Classic: connects | either | `matrix.sh --only H-TORCHAIN-GOOLC` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORCHAIN-GOOLC-CON/*` |
| DT-H-TORCHAIN-GOOLC-LSN | AETHER → TOR, WARP leg GOOL Classic: listeners vs foreign uid | either | `matrix.sh --only H-TORCHAIN-GOOLC` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORCHAIN-GOOLC-LSN/*` |
| DT-H-TORCHAIN-GOOLC-DNS | AETHER → TOR, WARP leg GOOL Classic: DNS filtering (DA) | DA | `matrix.sh --only H-TORCHAIN-GOOLC` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORCHAIN-GOOLC-DNS/*` |
| DT-H-TORCHAIN-GOOLC-APP | AETHER → TOR, WARP leg GOOL Classic: app blocking (DA) | DA | `matrix.sh --only H-TORCHAIN-GOOLC` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORCHAIN-GOOLC-APP/*` |
| DT-H-TORCHAIN-GOOLC-LEAK | AETHER → TOR, WARP leg GOOL Classic: no direct leak | either | `matrix.sh --only H-TORCHAIN-GOOLC` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORCHAIN-GOOLC-LEAK/*` |
| DT-H-TORCHAIN-GOOLC-KS | AETHER → TOR, WARP leg GOOL Classic: kill switch / disruption | either | `matrix.sh --only H-TORCHAIN-GOOLC` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORCHAIN-GOOLC-KS/*` |
| DT-H-TORCHAIN-MIM-CON | AETHER → TOR, WARP leg MIM: connects | either | `matrix.sh --only H-TORCHAIN-MIM` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORCHAIN-MIM-CON/*` |
| DT-H-TORCHAIN-MIM-LSN | AETHER → TOR, WARP leg MIM: listeners vs foreign uid | either | `matrix.sh --only H-TORCHAIN-MIM` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORCHAIN-MIM-LSN/*` |
| DT-H-TORCHAIN-MIM-DNS | AETHER → TOR, WARP leg MIM: DNS filtering (DA) | DA | `matrix.sh --only H-TORCHAIN-MIM` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORCHAIN-MIM-DNS/*` |
| DT-H-TORCHAIN-MIM-APP | AETHER → TOR, WARP leg MIM: app blocking (DA) | DA | `matrix.sh --only H-TORCHAIN-MIM` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORCHAIN-MIM-APP/*` |
| DT-H-TORCHAIN-MIM-LEAK | AETHER → TOR, WARP leg MIM: no direct leak | either | `matrix.sh --only H-TORCHAIN-MIM` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORCHAIN-MIM-LEAK/*` |
| DT-H-TORCHAIN-MIM-KS | AETHER → TOR, WARP leg MIM: kill switch / disruption | either | `matrix.sh --only H-TORCHAIN-MIM` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORCHAIN-MIM-KS/*` |
| DT-H-TORREV-MASQUE-CON | TOR → AETHER, WARP leg MASQUE: connects | either | `matrix.sh --only H-TORREV-MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORREV-MASQUE-CON/*` |
| DT-H-TORREV-MASQUE-LSN | TOR → AETHER, WARP leg MASQUE: listeners vs foreign uid | either | `matrix.sh --only H-TORREV-MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORREV-MASQUE-LSN/*` |
| DT-H-TORREV-MASQUE-DNS | TOR → AETHER, WARP leg MASQUE: DNS filtering (DA) | DA | `matrix.sh --only H-TORREV-MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORREV-MASQUE-DNS/*` |
| DT-H-TORREV-MASQUE-APP | TOR → AETHER, WARP leg MASQUE: app blocking (DA) | DA | `matrix.sh --only H-TORREV-MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORREV-MASQUE-APP/*` |
| DT-H-TORREV-MASQUE-LEAK | TOR → AETHER, WARP leg MASQUE: no direct leak | either | `matrix.sh --only H-TORREV-MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORREV-MASQUE-LEAK/*` |
| DT-H-TORREV-MASQUE-KS | TOR → AETHER, WARP leg MASQUE: kill switch / disruption | either | `matrix.sh --only H-TORREV-MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORREV-MASQUE-KS/*` |
| DT-H-TORREV-GOOL-CON | TOR → AETHER, WARP leg GOOL: connects | either | `matrix.sh --only H-TORREV-GOOL` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORREV-GOOL-CON/*` |
| DT-H-TORREV-GOOL-LSN | TOR → AETHER, WARP leg GOOL: listeners vs foreign uid | either | `matrix.sh --only H-TORREV-GOOL` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORREV-GOOL-LSN/*` |
| DT-H-TORREV-GOOL-DNS | TOR → AETHER, WARP leg GOOL: DNS filtering (DA) | DA | `matrix.sh --only H-TORREV-GOOL` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORREV-GOOL-DNS/*` |
| DT-H-TORREV-GOOL-APP | TOR → AETHER, WARP leg GOOL: app blocking (DA) | DA | `matrix.sh --only H-TORREV-GOOL` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORREV-GOOL-APP/*` |
| DT-H-TORREV-GOOL-LEAK | TOR → AETHER, WARP leg GOOL: no direct leak | either | `matrix.sh --only H-TORREV-GOOL` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORREV-GOOL-LEAK/*` |
| DT-H-TORREV-GOOL-KS | TOR → AETHER, WARP leg GOOL: kill switch / disruption | either | `matrix.sh --only H-TORREV-GOOL` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORREV-GOOL-KS/*` |
| DT-H-TORREV-MIM-CON | TOR → AETHER, WARP leg MIM: connects | either | `matrix.sh --only H-TORREV-MIM` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-TORREV-MIM-CON/*` |
| DT-H-TORREV-MIM-LSN | TOR → AETHER, WARP leg MIM: listeners vs foreign uid | either | `matrix.sh --only H-TORREV-MIM` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORREV-MIM-LSN/*` |
| DT-H-TORREV-MIM-DNS | TOR → AETHER, WARP leg MIM: DNS filtering (DA) | DA | `matrix.sh --only H-TORREV-MIM` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORREV-MIM-DNS/*` |
| DT-H-TORREV-MIM-APP | TOR → AETHER, WARP leg MIM: app blocking (DA) | DA | `matrix.sh --only H-TORREV-MIM` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORREV-MIM-APP/*` |
| DT-H-TORREV-MIM-LEAK | TOR → AETHER, WARP leg MIM: no direct leak | either | `matrix.sh --only H-TORREV-MIM` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORREV-MIM-LEAK/*` |
| DT-H-TORREV-MIM-KS | TOR → AETHER, WARP leg MIM: kill switch / disruption | either | `matrix.sh --only H-TORREV-MIM` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORREV-MIM-KS/*` |
| DT-H-TORREV-WG2MASQUE-CON | TOR → AETHER, WARP leg WireGuard (→ MASQUE): connects | either | `matrix.sh --only H-TORREV-WG2MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. Logcat shows the engine started with `--protocol masque`. | `DT-H-TORREV-WG2MASQUE-CON/*` |
| DT-H-TORREV-WG2MASQUE-LSN | TOR → AETHER, WARP leg WireGuard (→ MASQUE): listeners vs foreign uid | either | `matrix.sh --only H-TORREV-WG2MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORREV-WG2MASQUE-LSN/*` |
| DT-H-TORREV-WG2MASQUE-DNS | TOR → AETHER, WARP leg WireGuard (→ MASQUE): DNS filtering (DA) | DA | `matrix.sh --only H-TORREV-WG2MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORREV-WG2MASQUE-DNS/*` |
| DT-H-TORREV-WG2MASQUE-APP | TOR → AETHER, WARP leg WireGuard (→ MASQUE): app blocking (DA) | DA | `matrix.sh --only H-TORREV-WG2MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORREV-WG2MASQUE-APP/*` |
| DT-H-TORREV-WG2MASQUE-LEAK | TOR → AETHER, WARP leg WireGuard (→ MASQUE): no direct leak | either | `matrix.sh --only H-TORREV-WG2MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORREV-WG2MASQUE-LEAK/*` |
| DT-H-TORREV-WG2MASQUE-KS | TOR → AETHER, WARP leg WireGuard (→ MASQUE): kill switch / disruption | either | `matrix.sh --only H-TORREV-WG2MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORREV-WG2MASQUE-KS/*` |
| DT-H-TORREV-GOOLC2MASQUE-CON | TOR → AETHER, WARP leg GOOL Classic (→ MASQUE): connects | either | `matrix.sh --only H-TORREV-GOOLC2MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. Logcat shows the engine started with `--protocol masque`. | `DT-H-TORREV-GOOLC2MASQUE-CON/*` |
| DT-H-TORREV-GOOLC2MASQUE-LSN | TOR → AETHER, WARP leg GOOL Classic (→ MASQUE): listeners vs foreign uid | either | `matrix.sh --only H-TORREV-GOOLC2MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-TORREV-GOOLC2MASQUE-LSN/*` |
| DT-H-TORREV-GOOLC2MASQUE-DNS | TOR → AETHER, WARP leg GOOL Classic (→ MASQUE): DNS filtering (DA) | DA | `matrix.sh --only H-TORREV-GOOLC2MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-TORREV-GOOLC2MASQUE-DNS/*` |
| DT-H-TORREV-GOOLC2MASQUE-APP | TOR → AETHER, WARP leg GOOL Classic (→ MASQUE): app blocking (DA) | DA | `matrix.sh --only H-TORREV-GOOLC2MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-TORREV-GOOLC2MASQUE-APP/*` |
| DT-H-TORREV-GOOLC2MASQUE-LEAK | TOR → AETHER, WARP leg GOOL Classic (→ MASQUE): no direct leak | either | `matrix.sh --only H-TORREV-GOOLC2MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-TORREV-GOOLC2MASQUE-LEAK/*` |
| DT-H-TORREV-GOOLC2MASQUE-KS | TOR → AETHER, WARP leg GOOL Classic (→ MASQUE): kill switch / disruption | either | `matrix.sh --only H-TORREV-GOOLC2MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-TORREV-GOOLC2MASQUE-KS/*` |
| DT-H-PSICHAIN-WG-CON | AETHER → PSIPHON, WARP leg WireGuard: connects | either | `matrix.sh --only H-PSICHAIN-WG` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSICHAIN-WG-CON/*` |
| DT-H-PSICHAIN-WG-LSN | AETHER → PSIPHON, WARP leg WireGuard: listeners vs foreign uid | either | `matrix.sh --only H-PSICHAIN-WG` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSICHAIN-WG-LSN/*` |
| DT-H-PSICHAIN-WG-DNS | AETHER → PSIPHON, WARP leg WireGuard: DNS filtering (DA) | DA | `matrix.sh --only H-PSICHAIN-WG` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSICHAIN-WG-DNS/*` |
| DT-H-PSICHAIN-WG-APP | AETHER → PSIPHON, WARP leg WireGuard: app blocking (DA) | DA | `matrix.sh --only H-PSICHAIN-WG` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSICHAIN-WG-APP/*` |
| DT-H-PSICHAIN-WG-LEAK | AETHER → PSIPHON, WARP leg WireGuard: no direct leak | either | `matrix.sh --only H-PSICHAIN-WG` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSICHAIN-WG-LEAK/*` |
| DT-H-PSICHAIN-WG-KS | AETHER → PSIPHON, WARP leg WireGuard: kill switch / disruption | either | `matrix.sh --only H-PSICHAIN-WG` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSICHAIN-WG-KS/*` |
| DT-H-PSICHAIN-MASQUE-CON | AETHER → PSIPHON, WARP leg MASQUE: connects | either | `matrix.sh --only H-PSICHAIN-MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSICHAIN-MASQUE-CON/*` |
| DT-H-PSICHAIN-MASQUE-LSN | AETHER → PSIPHON, WARP leg MASQUE: listeners vs foreign uid | either | `matrix.sh --only H-PSICHAIN-MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSICHAIN-MASQUE-LSN/*` |
| DT-H-PSICHAIN-MASQUE-DNS | AETHER → PSIPHON, WARP leg MASQUE: DNS filtering (DA) | DA | `matrix.sh --only H-PSICHAIN-MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSICHAIN-MASQUE-DNS/*` |
| DT-H-PSICHAIN-MASQUE-APP | AETHER → PSIPHON, WARP leg MASQUE: app blocking (DA) | DA | `matrix.sh --only H-PSICHAIN-MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSICHAIN-MASQUE-APP/*` |
| DT-H-PSICHAIN-MASQUE-LEAK | AETHER → PSIPHON, WARP leg MASQUE: no direct leak | either | `matrix.sh --only H-PSICHAIN-MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSICHAIN-MASQUE-LEAK/*` |
| DT-H-PSICHAIN-MASQUE-KS | AETHER → PSIPHON, WARP leg MASQUE: kill switch / disruption | either | `matrix.sh --only H-PSICHAIN-MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSICHAIN-MASQUE-KS/*` |
| DT-H-PSICHAIN-GOOL-CON | AETHER → PSIPHON, WARP leg GOOL: connects | either | `matrix.sh --only H-PSICHAIN-GOOL` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSICHAIN-GOOL-CON/*` |
| DT-H-PSICHAIN-GOOL-LSN | AETHER → PSIPHON, WARP leg GOOL: listeners vs foreign uid | either | `matrix.sh --only H-PSICHAIN-GOOL` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSICHAIN-GOOL-LSN/*` |
| DT-H-PSICHAIN-GOOL-DNS | AETHER → PSIPHON, WARP leg GOOL: DNS filtering (DA) | DA | `matrix.sh --only H-PSICHAIN-GOOL` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSICHAIN-GOOL-DNS/*` |
| DT-H-PSICHAIN-GOOL-APP | AETHER → PSIPHON, WARP leg GOOL: app blocking (DA) | DA | `matrix.sh --only H-PSICHAIN-GOOL` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSICHAIN-GOOL-APP/*` |
| DT-H-PSICHAIN-GOOL-LEAK | AETHER → PSIPHON, WARP leg GOOL: no direct leak | either | `matrix.sh --only H-PSICHAIN-GOOL` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSICHAIN-GOOL-LEAK/*` |
| DT-H-PSICHAIN-GOOL-KS | AETHER → PSIPHON, WARP leg GOOL: kill switch / disruption | either | `matrix.sh --only H-PSICHAIN-GOOL` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSICHAIN-GOOL-KS/*` |
| DT-H-PSICHAIN-GOOLC-CON | AETHER → PSIPHON, WARP leg GOOL Classic: connects | either | `matrix.sh --only H-PSICHAIN-GOOLC` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSICHAIN-GOOLC-CON/*` |
| DT-H-PSICHAIN-GOOLC-LSN | AETHER → PSIPHON, WARP leg GOOL Classic: listeners vs foreign uid | either | `matrix.sh --only H-PSICHAIN-GOOLC` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSICHAIN-GOOLC-LSN/*` |
| DT-H-PSICHAIN-GOOLC-DNS | AETHER → PSIPHON, WARP leg GOOL Classic: DNS filtering (DA) | DA | `matrix.sh --only H-PSICHAIN-GOOLC` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSICHAIN-GOOLC-DNS/*` |
| DT-H-PSICHAIN-GOOLC-APP | AETHER → PSIPHON, WARP leg GOOL Classic: app blocking (DA) | DA | `matrix.sh --only H-PSICHAIN-GOOLC` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSICHAIN-GOOLC-APP/*` |
| DT-H-PSICHAIN-GOOLC-LEAK | AETHER → PSIPHON, WARP leg GOOL Classic: no direct leak | either | `matrix.sh --only H-PSICHAIN-GOOLC` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSICHAIN-GOOLC-LEAK/*` |
| DT-H-PSICHAIN-GOOLC-KS | AETHER → PSIPHON, WARP leg GOOL Classic: kill switch / disruption | either | `matrix.sh --only H-PSICHAIN-GOOLC` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSICHAIN-GOOLC-KS/*` |
| DT-H-PSICHAIN-MIM-CON | AETHER → PSIPHON, WARP leg MIM: connects | either | `matrix.sh --only H-PSICHAIN-MIM` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSICHAIN-MIM-CON/*` |
| DT-H-PSICHAIN-MIM-LSN | AETHER → PSIPHON, WARP leg MIM: listeners vs foreign uid | either | `matrix.sh --only H-PSICHAIN-MIM` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSICHAIN-MIM-LSN/*` |
| DT-H-PSICHAIN-MIM-DNS | AETHER → PSIPHON, WARP leg MIM: DNS filtering (DA) | DA | `matrix.sh --only H-PSICHAIN-MIM` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSICHAIN-MIM-DNS/*` |
| DT-H-PSICHAIN-MIM-APP | AETHER → PSIPHON, WARP leg MIM: app blocking (DA) | DA | `matrix.sh --only H-PSICHAIN-MIM` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSICHAIN-MIM-APP/*` |
| DT-H-PSICHAIN-MIM-LEAK | AETHER → PSIPHON, WARP leg MIM: no direct leak | either | `matrix.sh --only H-PSICHAIN-MIM` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSICHAIN-MIM-LEAK/*` |
| DT-H-PSICHAIN-MIM-KS | AETHER → PSIPHON, WARP leg MIM: kill switch / disruption | either | `matrix.sh --only H-PSICHAIN-MIM` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSICHAIN-MIM-KS/*` |
| DT-H-PSIREV-MASQUE-CON | PSIPHON → AETHER, WARP leg MASQUE: connects | either | `matrix.sh --only H-PSIREV-MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSIREV-MASQUE-CON/*` |
| DT-H-PSIREV-MASQUE-LSN | PSIPHON → AETHER, WARP leg MASQUE: listeners vs foreign uid | either | `matrix.sh --only H-PSIREV-MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSIREV-MASQUE-LSN/*` |
| DT-H-PSIREV-MASQUE-DNS | PSIPHON → AETHER, WARP leg MASQUE: DNS filtering (DA) | DA | `matrix.sh --only H-PSIREV-MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSIREV-MASQUE-DNS/*` |
| DT-H-PSIREV-MASQUE-APP | PSIPHON → AETHER, WARP leg MASQUE: app blocking (DA) | DA | `matrix.sh --only H-PSIREV-MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSIREV-MASQUE-APP/*` |
| DT-H-PSIREV-MASQUE-LEAK | PSIPHON → AETHER, WARP leg MASQUE: no direct leak | either | `matrix.sh --only H-PSIREV-MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSIREV-MASQUE-LEAK/*` |
| DT-H-PSIREV-MASQUE-KS | PSIPHON → AETHER, WARP leg MASQUE: kill switch / disruption | either | `matrix.sh --only H-PSIREV-MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSIREV-MASQUE-KS/*` |
| DT-H-PSIREV-GOOL-CON | PSIPHON → AETHER, WARP leg GOOL: connects | either | `matrix.sh --only H-PSIREV-GOOL` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSIREV-GOOL-CON/*` |
| DT-H-PSIREV-GOOL-LSN | PSIPHON → AETHER, WARP leg GOOL: listeners vs foreign uid | either | `matrix.sh --only H-PSIREV-GOOL` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSIREV-GOOL-LSN/*` |
| DT-H-PSIREV-GOOL-DNS | PSIPHON → AETHER, WARP leg GOOL: DNS filtering (DA) | DA | `matrix.sh --only H-PSIREV-GOOL` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSIREV-GOOL-DNS/*` |
| DT-H-PSIREV-GOOL-APP | PSIPHON → AETHER, WARP leg GOOL: app blocking (DA) | DA | `matrix.sh --only H-PSIREV-GOOL` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSIREV-GOOL-APP/*` |
| DT-H-PSIREV-GOOL-LEAK | PSIPHON → AETHER, WARP leg GOOL: no direct leak | either | `matrix.sh --only H-PSIREV-GOOL` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSIREV-GOOL-LEAK/*` |
| DT-H-PSIREV-GOOL-KS | PSIPHON → AETHER, WARP leg GOOL: kill switch / disruption | either | `matrix.sh --only H-PSIREV-GOOL` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSIREV-GOOL-KS/*` |
| DT-H-PSIREV-MIM-CON | PSIPHON → AETHER, WARP leg MIM: connects | either | `matrix.sh --only H-PSIREV-MIM` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. | `DT-H-PSIREV-MIM-CON/*` |
| DT-H-PSIREV-MIM-LSN | PSIPHON → AETHER, WARP leg MIM: listeners vs foreign uid | either | `matrix.sh --only H-PSIREV-MIM` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSIREV-MIM-LSN/*` |
| DT-H-PSIREV-MIM-DNS | PSIPHON → AETHER, WARP leg MIM: DNS filtering (DA) | DA | `matrix.sh --only H-PSIREV-MIM` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSIREV-MIM-DNS/*` |
| DT-H-PSIREV-MIM-APP | PSIPHON → AETHER, WARP leg MIM: app blocking (DA) | DA | `matrix.sh --only H-PSIREV-MIM` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSIREV-MIM-APP/*` |
| DT-H-PSIREV-MIM-LEAK | PSIPHON → AETHER, WARP leg MIM: no direct leak | either | `matrix.sh --only H-PSIREV-MIM` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSIREV-MIM-LEAK/*` |
| DT-H-PSIREV-MIM-KS | PSIPHON → AETHER, WARP leg MIM: kill switch / disruption | either | `matrix.sh --only H-PSIREV-MIM` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSIREV-MIM-KS/*` |
| DT-H-PSIREV-WG2MASQUE-CON | PSIPHON → AETHER, WARP leg WireGuard (→ MASQUE): connects | either | `matrix.sh --only H-PSIREV-WG2MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. Logcat shows the engine started with `--protocol masque`. | `DT-H-PSIREV-WG2MASQUE-CON/*` |
| DT-H-PSIREV-WG2MASQUE-LSN | PSIPHON → AETHER, WARP leg WireGuard (→ MASQUE): listeners vs foreign uid | either | `matrix.sh --only H-PSIREV-WG2MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSIREV-WG2MASQUE-LSN/*` |
| DT-H-PSIREV-WG2MASQUE-DNS | PSIPHON → AETHER, WARP leg WireGuard (→ MASQUE): DNS filtering (DA) | DA | `matrix.sh --only H-PSIREV-WG2MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSIREV-WG2MASQUE-DNS/*` |
| DT-H-PSIREV-WG2MASQUE-APP | PSIPHON → AETHER, WARP leg WireGuard (→ MASQUE): app blocking (DA) | DA | `matrix.sh --only H-PSIREV-WG2MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSIREV-WG2MASQUE-APP/*` |
| DT-H-PSIREV-WG2MASQUE-LEAK | PSIPHON → AETHER, WARP leg WireGuard (→ MASQUE): no direct leak | either | `matrix.sh --only H-PSIREV-WG2MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSIREV-WG2MASQUE-LEAK/*` |
| DT-H-PSIREV-WG2MASQUE-KS | PSIPHON → AETHER, WARP leg WireGuard (→ MASQUE): kill switch / disruption | either | `matrix.sh --only H-PSIREV-WG2MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSIREV-WG2MASQUE-KS/*` |
| DT-H-PSIREV-GOOLC2MASQUE-CON | PSIPHON → AETHER, WARP leg GOOL Classic (→ MASQUE): connects | either | `matrix.sh --only H-PSIREV-GOOLC2MASQUE` | Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`. Logcat shows the engine started with `--protocol masque`. | `DT-H-PSIREV-GOOLC2MASQUE-CON/*` |
| DT-H-PSIREV-GOOLC2MASQUE-LSN | PSIPHON → AETHER, WARP leg GOOL Classic (→ MASQUE): listeners vs foreign uid | either | `matrix.sh --only H-PSIREV-GOOLC2MASQUE` | No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them. | `DT-H-PSIREV-GOOLC2MASQUE-LSN/*` |
| DT-H-PSIREV-GOOLC2MASQUE-DNS | PSIPHON → AETHER, WARP leg GOOL Classic (→ MASQUE): DNS filtering (DA) | DA | `matrix.sh --only H-PSIREV-GOOLC2MASQUE` | `dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP. | `DT-H-PSIREV-GOOLC2MASQUE-DNS/*` |
| DT-H-PSIREV-GOOLC2MASQUE-APP | PSIPHON → AETHER, WARP leg GOOL Classic (→ MASQUE): app blocking (DA) | DA | `matrix.sh --only H-PSIREV-GOOLC2MASQUE` | `appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check. | `DT-H-PSIREV-GOOLC2MASQUE-APP/*` |
| DT-H-PSIREV-GOOLC2MASQUE-LEAK | PSIPHON → AETHER, WARP leg GOOL Classic (→ MASQUE): no direct leak | either | `matrix.sh --only H-PSIREV-GOOLC2MASQUE` | 30 s sampling: 0 LEAK samples (v4 and v6). | `DT-H-PSIREV-GOOLC2MASQUE-LEAK/*` |
| DT-H-PSIREV-GOOLC2MASQUE-KS | PSIPHON → AETHER, WARP leg GOOL Classic (→ MASQUE): kill switch / disruption | either | `matrix.sh --only H-PSIREV-GOOLC2MASQUE` | 90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself). | `DT-H-PSIREV-GOOLC2MASQUE-KS/*` |
| DT-HR-TORCHAIN-APP | AETHER → TOR routing — app rule: Chrome → second route | either | Connect AETHER → TOR (leg MASQUE). Routing section → add app rule: Chrome → the second route. In Chrome open `http://www.cloudflare.com/cdn-cgi/trace`; from adb `http_get` (shell = default route) the same URL. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Tor (1820, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-TORCHAIN-DOMAIN | AETHER → TOR routing — domain rule `www.cloudflare.com` → second route | either | Connect AETHER → TOR (leg MASQUE). Add domain rule `www.cloudflare.com` → second route. Run `adb shell "printf 'GET /cdn-cgi/trace HTTP/1.0\r\nHost: www.cloudflare.com\r\n\r\n' \| toybox nc -w 8 www.cloudflare.com 80"` and the same for `ipv4.icanhazip.com` (default route). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Tor (1820, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-TORCHAIN-WILDCARD | AETHER → TOR routing — wildcard rule `*.cloudflare.com` → second route | either | Connect AETHER → TOR (leg MASQUE). As DOMAIN with `*.cloudflare.com`; also test the bare `cloudflare.com` (wildcard must not match the apex unless the app says so: record). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Tor (1820, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-TORCHAIN-CIDR | AETHER → TOR routing — CIDR rule → second route | either | Connect AETHER → TOR (leg MASQUE). With the VPN off, note a real IPv4 of www.cloudflare.com (`adb shell ping -c1 www.cloudflare.com`, e.g. 104.16.x.x). Add CIDR rule `<that /24>` → second route. Connected: dial the IP literal with `Host: www.cloudflare.com`. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Tor (1820, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-TORREV-APP | TOR → AETHER routing — app rule: Chrome → second route | either | Connect TOR → AETHER (leg MASQUE). Routing section → add app rule: Chrome → the second route. In Chrome open `http://www.cloudflare.com/cdn-cgi/trace`; from adb `http_get` (shell = default route) the same URL. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Tor → WARP (1819, default) / Tor (1820)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-TORREV-DOMAIN | TOR → AETHER routing — domain rule `www.cloudflare.com` → second route | either | Connect TOR → AETHER (leg MASQUE). Add domain rule `www.cloudflare.com` → second route. Run `adb shell "printf 'GET /cdn-cgi/trace HTTP/1.0\r\nHost: www.cloudflare.com\r\n\r\n' \| toybox nc -w 8 www.cloudflare.com 80"` and the same for `ipv4.icanhazip.com` (default route). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Tor → WARP (1819, default) / Tor (1820)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-TORREV-WILDCARD | TOR → AETHER routing — wildcard rule `*.cloudflare.com` → second route | either | Connect TOR → AETHER (leg MASQUE). As DOMAIN with `*.cloudflare.com`; also test the bare `cloudflare.com` (wildcard must not match the apex unless the app says so: record). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Tor → WARP (1819, default) / Tor (1820)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-TORREV-CIDR | TOR → AETHER routing — CIDR rule → second route | either | Connect TOR → AETHER (leg MASQUE). With the VPN off, note a real IPv4 of www.cloudflare.com (`adb shell ping -c1 www.cloudflare.com`, e.g. 104.16.x.x). Add CIDR rule `<that /24>` → second route. Connected: dial the IP literal with `Host: www.cloudflare.com`. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Tor → WARP (1819, default) / Tor (1820)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSICHAIN-APP | AETHER → PSIPHON routing — app rule: Chrome → second route | either | Connect AETHER → PSIPHON (leg MASQUE). Routing section → add app rule: Chrome → the second route. In Chrome open `http://www.cloudflare.com/cdn-cgi/trace`; from adb `http_get` (shell = default route) the same URL. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Psiphon (1821, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSICHAIN-DOMAIN | AETHER → PSIPHON routing — domain rule `www.cloudflare.com` → second route | either | Connect AETHER → PSIPHON (leg MASQUE). Add domain rule `www.cloudflare.com` → second route. Run `adb shell "printf 'GET /cdn-cgi/trace HTTP/1.0\r\nHost: www.cloudflare.com\r\n\r\n' \| toybox nc -w 8 www.cloudflare.com 80"` and the same for `ipv4.icanhazip.com` (default route). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Psiphon (1821, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSICHAIN-WILDCARD | AETHER → PSIPHON routing — wildcard rule `*.cloudflare.com` → second route | either | Connect AETHER → PSIPHON (leg MASQUE). As DOMAIN with `*.cloudflare.com`; also test the bare `cloudflare.com` (wildcard must not match the apex unless the app says so: record). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Psiphon (1821, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSICHAIN-CIDR | AETHER → PSIPHON routing — CIDR rule → second route | either | Connect AETHER → PSIPHON (leg MASQUE). With the VPN off, note a real IPv4 of www.cloudflare.com (`adb shell ping -c1 www.cloudflare.com`, e.g. 104.16.x.x). Add CIDR rule `<that /24>` → second route. Connected: dial the IP literal with `Host: www.cloudflare.com`. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (WARP → Psiphon (1821, default) / WARP (1819)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSIREV-APP | PSIPHON → AETHER routing — app rule: Chrome → second route | either | Connect PSIPHON → AETHER (leg MASQUE). Routing section → add app rule: Chrome → the second route. In Chrome open `http://www.cloudflare.com/cdn-cgi/trace`; from adb `http_get` (shell = default route) the same URL. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Psiphon → WARP (1819, default) / Psiphon (1821)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSIREV-DOMAIN | PSIPHON → AETHER routing — domain rule `www.cloudflare.com` → second route | either | Connect PSIPHON → AETHER (leg MASQUE). Add domain rule `www.cloudflare.com` → second route. Run `adb shell "printf 'GET /cdn-cgi/trace HTTP/1.0\r\nHost: www.cloudflare.com\r\n\r\n' \| toybox nc -w 8 www.cloudflare.com 80"` and the same for `ipv4.icanhazip.com` (default route). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Psiphon → WARP (1819, default) / Psiphon (1821)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSIREV-WILDCARD | PSIPHON → AETHER routing — wildcard rule `*.cloudflare.com` → second route | either | Connect PSIPHON → AETHER (leg MASQUE). As DOMAIN with `*.cloudflare.com`; also test the bare `cloudflare.com` (wildcard must not match the apex unless the app says so: record). Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Psiphon → WARP (1819, default) / Psiphon (1821)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |
| DT-HR-PSIREV-CIDR | PSIPHON → AETHER routing — CIDR rule → second route | either | Connect PSIPHON → AETHER (leg MASQUE). With the VPN off, note a real IPv4 of www.cloudflare.com (`adb shell ping -c1 www.cloudflare.com`, e.g. 104.16.x.x). Add CIDR rule `<that /24>` → second route. Connected: dial the IP literal with `Host: www.cloudflare.com`. Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active. | Traffic matching the rule exits through the second route, everything else through the default (Psiphon → WARP (1819, default) / Psiphon (1821)). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting. | terminal output, screenshot, `collect.sh` |

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

| § | Section | Tests |
|---|---|---|
| 1 | Setup and device identity | 5 |
| 2 | Android ABI (ARM64, armeabi-v7a note) | 4 |
| 3 | Local listeners 1819–1822 (Aether, Tor, Psiphon, Lantern) | 7 |
| 4 | IPv4 and IPv6 (dual-stack, IPv6-only, leak checks) | 9 |
| 5 | Private DNS: off / automatic / strict hostname | 11 |
| 6 | DNS filtering, DNS cache and fake IPs | 9 |
| 7 | Always-on VPN and Lockdown ("Block connections without VPN") | 9 |
| 8 | Keystore pepper and biometric | 8 |
| 9 | Import / export and the signing-key migration (v1.0.2 old key → new key) | 9 |
| 10 | Doze, App Standby, long run, vendor battery killers | 7 |
| 11 | Protocol matrix: single-tunnel protocols | 54 |
| 12 | Protocol matrix: hybrid protocols × WARP leg, and hybrid routing rules | 136 |
| | **Total** | **268** |

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
