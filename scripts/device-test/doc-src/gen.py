#!/usr/bin/env python3
"""Generates docs/family-shield-device-testing.md and scripts/device-test/results-template.csv
from one table of test rows (so the doc, the CSV and the counts never disagree).
Usage (repo root): python3 scripts/device-test/doc-src/gen.py ."""
import csv, io, os, sys

REPO = sys.argv[1]
S = "scripts/device-test"

R = "release"   # release-signed (or debug-signed fallback) com.chakcaad.aethone
DA = "DA"        # debuggable DA build with the hook
EITHER = "either"

sections = []  # (num, key, title, intro, rows, outro)

def sec(num, key, title, intro, rows, outro=""):
    sections.append((num, key, title, intro, rows, outro))

# ---------------------------------------------------------------- §1
sec(1, "ENV", "Setup and device identity", "", [
 ("DT-ENV-01", "Device facts", EITHER,
  "`check-device.sh`",
  "Writes model, Android version/SDK, security patch, ABI list, ROM (MIUI/HyperOS/One UI/ColorOS), page size, Private DNS, Always-on settings, StrongBox/fingerprint features, installed AETHONE builds. `qemu` is empty (a real device).",
  "`DT-ENV-01/*/device.txt`, ip dumps"),
 ("DT-ENV-02", "Install the release device-test APK", R,
  "Check the APK's SHA-256 against `SHA256SUMS.txt` from the artifact. Run `install.sh aethone-DEVICE-TEST-arm64-v8a-r<run>-release-NOT-A-RELEASE.apk`. If v1.0.2 is installed, this is DT-MIG-02, so do §9 first.",
  "`Success`; the signer SHA-256 matches `DEVICE_TEST_INFO.txt` and is **not** `EB:F3:9C:82:…` (the compromised key); `primaryCpuAbi=arm64-v8a`.",
  "`DT-ENV-02/*/apk.txt`, `install.txt`"),
 ("DT-ENV-03", "Install the DA device-test APK", DA,
  "`install.sh aethone-DEVICE-TEST-DA-debuggable-arm64-v8a-r<run>.apk`, then `hooks.sh probe` and `hooks.sh on`.",
  "Installs beside the release app (`com.chakcaad.aethone.da`, label \"AETHONE DA\"); `pkgFlags` has `DEBUGGABLE`; `hooks.sh on` prints `\"ok\":true`.",
  "`apk.txt`, hooks output in `shield-calls.log`"),
 ("DT-ENV-04", "Hooks are absent from the release build", R,
  "With only the release app as target: `PKG=com.chakcaad.aethone hooks.sh probe`; then `adb shell am broadcast -a com.chakcaad.aethone.SHIELD_TEST -n com.chakcaad.aethone/.shield.ShieldTestReceiver --es cmd status`.",
  "`hooks: UNAVAILABLE`; the broadcast is refused (`not exported` / permission denial in logcat) or nothing answers. No `RESULT` line from tag `AethoneShieldTest`.",
  "terminal output + `collect.sh DT-ENV-04`"),
 ("DT-ENV-05", "Only one VPN app active", EITHER,
  "Settings → Network → VPN: note every VPN app installed. Disconnect and disable Always-on for all except AETHONE during the tests.",
  "Only AETHONE (or AETHONE DA) has the VPN slot during a test.",
  "screenshot `DT-ENV-05-1.png`"),
])

# ---------------------------------------------------------------- §2
sec(2, "ABI", "Android ABI (ARM64, armeabi-v7a note)",
 "The device-test APK is **arm64-v8a only**. CI checks every arm64/armv7 library's ELF and seccomp "
 "safety; the x86_64 build also runs on the emulator. arm64 has no legacy `poll`/`open` syscalls. "
 "No arm64 binary has run on a device yet.", [
 ("DT-ABI-01", "Native engines load on arm64", R,
  "Connect once with MASQUE (any working protocol). `collect.sh DT-ABI-01`.",
  "logcat has `zeptun up on socks` and no `zeptun-load-failed`, `start-threw`, `UnsatisfiedLinkError`, `FATAL EXCEPTION`; `processes.txt` shows the app.",
  "`logcat-filtered.txt`, `logcat-crash.txt`"),
 ("DT-ABI-02", "No seccomp kill / native crash during the whole test day", EITHER,
  "At the end of the day: `collect.sh DT-ABI-02`, and `adb bugreport bugreport.zip` (contains tombstones without root).",
  "No `SIGSYS`, `seccomp`, `Fatal signal` lines for AETHONE processes in `logcat-app-and-crash-grep.txt`; no AETHONE tombstone in the bugreport (`FS/data/tombstones`).",
  "`logcat-app-and-crash-grep.txt`, `bugreport.zip`"),
 ("DT-ABI-03", "16 KB page-size devices", EITHER,
  "Read `page_size` in DT-ENV-01.",
  "Record the value. If it is 16384, DT-ABI-01 on this phone also proves 16 KB loading; if 4096, write \"16 KB not covered on device\".",
  "`device.txt`"),
 ("DT-ABI-04", "armeabi-v7a (32-bit) device", R,
  "Only if a 32-bit-only phone is available: install `aethone-armeabi-v7a-r<run>.apk` from the `aethone-apk-r<run>` artifact (or `aethone-apk-signed-r<run>`), repeat DT-ABI-01 and the DT-P-MASQUE rows.",
  "Same as DT-ABI-01. With no 32-bit device: `N/A — no armeabi-v7a device`.",
  "as DT-ABI-01"),
])

# ---------------------------------------------------------------- §3
sec(3, "LSN", "Local listeners 1819–1822 (Aether, Tor, Psiphon, Lantern)",
 "Requirement: **no other app and no adb shell may use these listeners.** Known state at `f6e4dbf`: the "
 "real cores bind their own sockets and are **not** behind `LoopbackGuard` (security §5 A, §8). The "
 "expected result for DT-LSN-02/03 is therefore `FAIL-KNOWN-GAP`; the device run confirms it and records "
 "the exact ports per protocol. Ports: 1819 = Aether main `--bind` (and plain Tor/Psiphon in the -ONLY "
 "modes), 1820 = Aether `--tor-bind`, 1821 = Aether `--psiphon-bind`, 1822 = Lantern sidecar.", [
 ("DT-LSN-01", "Which ports listen, per protocol, and on which address", R,
  "For MASQUE, TOR ONLY, AETHER→TOR, AETHER→PSIPHON, PSIPHON ONLY, LANTERN: connect, then `socks-probe.sh DT-LSN-01 <protocol>`.",
  "Every listening port is bound to `127.0.0.1` (`0100007F`) only. **No** `WILDCARD-BIND` (0.0.0.0 / ::). Ports listed per protocol match the table above.",
  "`socks-probe.txt`, `listeners-raw.txt` per protocol"),
 ("DT-LSN-02", "adb shell (uid 2000) cannot use a listener", R,
  "Same runs as DT-LSN-01 (the script sends a SOCKS5 greeting from uid 2000).",
  "Requirement: `foreign_uid2000=no-reply` on every listening port. **Expected today: `socks-reply` → FAIL-KNOWN-GAP.**",
  "`socks-probe.txt`"),
 ("DT-LSN-03", "Another app cannot use a listener", R,
  "Termux: `pkg install curl`; while connected run `curl -m 15 --socks5-hostname 127.0.0.1:1819 http://www.cloudflare.com/cdn-cgi/trace` (repeat for each listening port).",
  "Requirement: connection refused/reset, no trace output. **Expected today: the trace prints (warp=on or the Tor/Psiphon/Lantern exit) → FAIL-KNOWN-GAP.** Record which ports answered.",
  "Termux screenshot(s) `DT-LSN-03-*.png`"),
 ("DT-LSN-04", "Shield status reports the exposure", DA,
  "DA build, hooks on, `shield.sh setup`, connect MASQUE, `shield.sh status`.",
  "`state` is **not** `protected`; `reasons` contains `local-socks-exposed:<ports>` listing every port that answered in DT-LSN-02; `listeners[]` shows `guarded:false` for them.",
  "`shield-calls.log`, `collect.sh DT-LSN-04`"),
 ("DT-LSN-05", "Listeners close on disconnect", R,
  "Disconnect in the app; wait 10 s; `socks-probe.sh DT-LSN-05`.",
  "All four ports `listening=no`.",
  "`socks-probe.txt`"),
 ("DT-LSN-06", "Listeners after a core crash / app swipe-away", R,
  "Connected (LANTERN, then PSIPHON ONLY): swipe the app away from recents; wait 30 s; `socks-probe.sh DT-LSN-06`.",
  "Either the tunnel is still up (foreground service) and the ports are as in DT-LSN-01, or everything is closed. A port left listening with no tunnel is a FAIL.",
  "`socks-probe.txt`, `collect.sh`"),
 ("DT-LSN-07", "Not reachable from the LAN", R,
  "Phone on Wi-Fi and connected. From a second device on the same Wi-Fi: `nc -vz <phone-wifi-ip> 1819` (and 1820–1822). The phone IP is in `ip-addr.txt` (wlan0).",
  "Connection refused / timeout on every port.",
  "terminal output of the second device (text or photo)"),
])

# ---------------------------------------------------------------- §4
sec(4, "IP", "IPv4 and IPv6 (dual-stack, IPv6-only, leak checks)",
 "Important code fact: the TUN gets an IPv6 address and `::/0` **only while Family Shield is on** "
 "(`fdfe:dcba:9876::1/126`). With the shield off the TUN is IPv4-only. That is the v1.0.2 behaviour, "
 "and phase 1 named it bypass (B). DT-IP-03 measures what Android then does with an app's IPv6 traffic "
 "on a dual-stack network: fails, or leaks. The protocol does not assume either answer.\n\n"
 "Networks: (a) **dual-stack** Wi-Fi or mobile data (DT-ENV-01 `ip6-addr.txt` shows a global `2…`/`3…` "
 "address on wlan0/rmnet); (b) **IPv6-only**: a carrier APN set to `IPv6` only (Settings → Mobile network "
 "→ Access Point Names → APN protocol), or a router with IPv6-only + NAT64/DNS64. Android's 464XLAT "
 "(`v4-` interface) then provides IPv4. If neither is available, mark the row `N/A — no <kind> network` "
 "and say which networks you have.", [
 ("DT-IP-01", "Direct baseline per network", EITHER,
  "VPN off, Always-on off: `baseline.sh wifi-<name>` and `baseline.sh mobile-<operator>`.",
  "`direct_v4` filled; `direct_v6` filled on a dual-stack network (else `none` → IPv6 rows on this network are N/A).",
  "`baseline-*.txt`, `DT-IP-01/*`"),
 ("DT-IP-02", "IPv4 exit is the tunnel (shield off)", R,
  "Connect MASQUE. `leakwatch.sh DT-IP-02 60`.",
  "0 LEAK samples; `warp=on` in every sample (MASQUE exits through WARP).",
  "`samples.csv`, `summary.txt`"),
 ("DT-IP-03", "IPv6 with the shield OFF on a dual-stack network", R,
  "Dual-stack network, connect MASQUE, `collect.sh DT-IP-03`, `leakwatch.sh DT-IP-03 60`. In Chrome open `https://test-ipv6.com` and `https://ipleak.net` and take screenshots.",
  "Requirement: **no sample with `v6=` equal to `direct_v6`**, and the leak sites show no ISP IPv6 address. `ip6-route-table-all.txt` shows whether the VPN table has `::/0`. Any baseline IPv6 = FAIL (IPv6 leak with the shield off).",
  "`samples.csv`, `ip6-route*.txt`, screenshots"),
 ("DT-IP-04", "IPv6 captured with the shield ON", DA,
  "DA, `shield.sh setup`, connect MASQUE (reconnect after setup: enabling needs a reconnect). `collect.sh DT-IP-04`, `shield.sh status`.",
  "`ip-addr.txt`: tun has `fdfe:dcba:9876::1/126`; `ip6-route-table-all.txt`: `::/0` via the tun; status `ipv6Route:true`, no `ipv6-not-captured` reason.",
  "`ip*.txt`, `shield-status.json`"),
 ("DT-IP-05", "IPv6 traffic goes through the tunnel (shield ON)", DA,
  "Same session as DT-IP-04 on a dual-stack network: `leakwatch.sh DT-IP-05 60`, then `shield.sh status` twice, 30 s apart, while Chrome loads `https://ipv6.google.com`.",
  "0 LEAK samples; `ipv6Packets` grows between the two status reads; ipv6.google.com loads through the tunnel. If it doesn't load, record that and the error.",
  "`samples.csv`, `shield-calls.log`, screenshot"),
 ("DT-IP-06", "IPv6-only network (with 464XLAT/NAT64)", R,
  "IPv6-only network. Connect each of MASQUE, WIREGUARD, LANTERN, PSIPHON ONLY in turn; for each, record whether it connects and run `leakwatch.sh DT-IP-06-<proto> 30`. Repeat MASQUE with the app's IP version setting at v4, v6, dual.",
  "Each protocol either connects with 0 LEAK samples, or fails cleanly (app shows an error, no traffic leaves directly). Record which IP-version setting works. A direct-IPv6 sample = FAIL.",
  "per-protocol `samples.csv`, `collect.sh`"),
 ("DT-IP-07", "Dual-stack: IP version setting v4 / v6 / dual", R,
  "Dual-stack network, MASQUE, app setting IP version = v4, then v6, then dual. Connect each time and run `leakwatch.sh DT-IP-07-<v> 30`.",
  "Connect result recorded per setting; 0 LEAK samples in each.",
  "`samples.csv` ×3"),
 ("DT-IP-08", "Browser leak sites", R,
  "Connected (MASQUE, then LANTERN): Chrome → `https://ipleak.net`, `https://browserleaks.com/ip`, `https://dnsleaktest.com` (standard test).",
  "No ISP IPv4/IPv6 address; the DNS servers shown are not your ISP's resolvers (they belong to the exit network). Screenshot each.",
  "screenshots `DT-IP-08-*.png`"),
 ("DT-IP-09", "WebRTC leak", R,
  "Connected: Chrome → `https://browserleaks.com/webrtc`.",
  "No public ISP address in the WebRTC candidates (local `192.168.x`/mDNS names are fine).",
  "screenshot"),
])

# ---------------------------------------------------------------- §5
PD = [("OFF", "off", "`adb shell settings put global private_dns_mode off`"),
      ("AUTO", "automatic", "`adb shell settings put global private_dns_mode opportunistic`"),
      ("STRICT", "strict hostname `dns.google`", "`adb shell settings put global private_dns_specifier dns.google` then `adb shell settings put global private_dns_mode hostname`")]
pd_rows = []
for code, name, cmd in PD:
    pd_rows.append((f"DT-PDNS-{code}-1", f"Private DNS {name}: shield off, MASQUE", R,
        f"{cmd} (or Settings → Network → Private DNS). Connect MASQUE. `collect.sh DT-PDNS-{code}-1`; `leakwatch.sh DT-PDNS-{code}-1 30`; in Chrome load 3 sites.",
        "Connects; sites load; 0 LEAK samples. Record `PrivateDnsConfig` of the VPN network from `dumpsys-connectivity.txt`.",
        "`dumpsys-connectivity.txt`, `samples.csv`"))
    pd_rows.append((f"DT-PDNS-{code}-2", f"Private DNS {name}: shield on (strict mode off)", DA,
        f"{cmd}. DA, `shield.sh setup`, reconnect. `dns-check.sh DT-PDNS-{code}-2`.",
        "dns-check PASS (allowed name → fake IP + HTTP; `example.com` → unknown host). Browsing works.",
        "`dns-check.txt`, `shield-status.txt`"))
    pd_rows.append((f"DT-PDNS-{code}-3", f"Private DNS {name}: shield strict mode on", DA,
        f"{cmd}. `shield.sh strict on dot quic altdns`, reconnect, `dns-check.sh DT-PDNS-{code}-3`, `shield.sh status`, browse 3 sites.",
        ("DNS keeps working (dns-check PASS, sites load). " +
         ("Status reasons contain `private-dns-strict` (the 853 block is dropped so device DNS is not cut)." if code == "STRICT"
          else "Status reasons do **not** contain `private-dns-strict`.")),
        "`dns-check.txt`, `shield-calls.log`"))
pd_rows.append(("DT-PDNS-BAD", "Private DNS strict with an unreachable hostname", DA,
    "`settings put global private_dns_specifier no-such-host.invalid` + mode `hostname`; shield on; connect MASQUE; `dns-check.sh DT-PDNS-BAD`.",
    "Record the result: Android marks the network \"Private DNS server cannot be accessed\". Whether the tunnel's fake-IP DNS still answers, and whether the shield still blocks `example.com`, is what this row records. Any **direct** DNS/HTTP = FAIL.",
    "`dns-check.txt`, screenshot of the notification"))
pd_rows.append(("DT-PDNS-RESET", "Restore Private DNS", EITHER,
    "`adb shell settings put global private_dns_mode opportunistic` (or the owner's previous value from DT-ENV-01).",
    "`settings get global private_dns_mode` = the value before the tests.", "terminal output"))
sec(5, "PDNS", "Private DNS: off / automatic / strict hostname",
 "Android sends Private DNS (DoT, port 853) per network. With a VPN up, apps resolve on the VPN "
 "network. The shield's strict mode can block 853, but drops that block when Private DNS is in strict "
 "hostname mode (security §5). Each mode is tested with the shield off, the shield on, and strict mode "
 "on.", pd_rows)

# ---------------------------------------------------------------- §6
sec(6, "DNS", "DNS filtering, DNS cache and fake IPs", "DA build, hooks on, `shield.sh setup`, then reconnect MASQUE.", [
 ("DT-DNS-01", "Allowed name gets a fake IP and works", DA,
  "`dns-check.sh DT-DNS-01` (it runs 01–05 in one go; record each line).",
  "`example.net` resolves to `198.18.x.x`/`198.19.x.x` (IPv4 fake range) and answers HTTP.", "`dns-check.txt`"),
 ("DT-DNS-02", "Blocked name → NXDOMAIN, no connection", DA,
  "(same run)", "`example.com` → `unknown-host`; no HTTP answer.", "`dns-check.txt`, `http-block.txt`"),
 ("DT-DNS-03", "Blocked after it was resolved: cached fake IP refused", DA,
  "(same run: `example.org` resolved and used, then blocked live, then the same fake IP is dialled)",
  "Before the block the fake IP answers HTTP; after `shield.sh block example.org` (answer `applied:ok`, no reconnect) the **same fake IP** gets no HTTP; a new lookup → `unknown-host`.",
  "`dns-check.txt`, `http-cache-after-block.txt`"),
 ("DT-DNS-04", "Open connection killed on block (revalidation)", DA,
  "Chrome: start a long download or video on `example.org` or another allowed site X; while it runs, `shield.sh block <X>`.",
  "The transfer stops within ~1–2 s; other tabs keep working. Shield status `flowsKilled` grows.",
  "`shield-calls.log` (status before/after), screen recording or screenshots"),
 ("DT-DNS-05", "App-level DNS cache (browser)", DA,
  "Chrome: open `https://example.org` (allowed). `shield.sh block example.org`. Reload in the same tab, then in a new tab.",
  "Both reloads fail (\"site can't be reached\" / connection reset), even though Chrome cached the address.",
  "screenshots"),
 ("DT-DNS-06", "Unblock restores access", DA,
  "`shield.sh rules` → id of the `example.org` rule → `shield.sh unrule <id>`; reload.", "Loads again without reconnecting.", "`shield-calls.log`"),
 ("DT-DNS-07", "Fake IPs after a tunnel restart", DA,
  "Resolve `example.net` (note the fake IP). Disconnect + reconnect. Dial the **old** fake IP: `adb shell \"printf 'GET / HTTP/1.0\\r\\nHost: example.net\\r\\n\\r\\n' | toybox nc -w 8 <old-ip> 80\"`.",
  "Either it reaches example.net or it fails. It must **never** reach a different site. Record which.",
  "terminal output"),
 ("DT-DNS-08", "Browser Secure DNS (DoH)", DA,
  "Chrome → Settings → Privacy → Use secure DNS → On (Cloudflare). Then open `https://example.com` (blocked). Repeat with `shield.sh strict on dot quic altdns` and `shield.sh category bypass on`.",
  "Record whether example.com loads in each case. With strict mode + bypass category it must not load. Default (no strict): record the result; known limit = DoH to unknown endpoints is not detectable (security §5).",
  "screenshots, `shield-calls.log`"),
 ("DT-DNS-09", "Hard-coded resolver on UDP/53", DA,
  "`adb shell \"toybox nslookup example.com 8.8.8.8\"` (if the ROM's toybox has nslookup) — or Termux `pkg install dnsutils; dig @8.8.8.8 example.com`.",
  "NXDOMAIN or no answer (DNS hijack is on while the shield is on). Never the real A record.",
  "terminal output"),
])

# ---------------------------------------------------------------- §7
sec(7, "AON", "Always-on VPN and Lockdown (\"Block connections without VPN\")",
 "Set Always-on by hand: Settings → Network & internet → VPN → gear next to AETHONE → **Always-on VPN** "
 "on, then **Block connections without VPN** on. (On Samsung: Connections → More connection settings → "
 "VPN; on Xiaomi: Connection & sharing → VPN.) The scripts only read these settings. Setting them over "
 "adb doesn't apply them on a running device. Take a baseline first (DT-IP-01). For every "
 "\"restart\" row, start `leakwatch.sh` **before** the action. A sample takes 1–25 s, so repeat each "
 "action 3 times.", [
 ("DT-AON-01", "Always-on starts the tunnel at boot", R,
  "Always-on on, lockdown off. Reboot. As soon as `adb devices` sees the phone: `leakwatch.sh DT-AON-01 120` and `collect.sh DT-AON-01`.",
  "The tunnel comes up without opening the app (notification shown); record seconds from boot to the first TUNNEL sample. Samples before it may be LEAK (lockdown is off): record how many.",
  "`samples.csv`, `collect.sh`"),
 ("DT-AON-02", "Lockdown at boot: nothing leaves before the tunnel", R,
  "Always-on **and** lockdown on. Reboot; start `leakwatch.sh DT-AON-02 180` as early as possible.",
  "0 LEAK samples; early samples are BLOCKED, then TUNNEL.", "`samples.csv`"),
 ("DT-AON-03", "Lockdown: restart from the app (disconnect → connect)", R,
  "Lockdown on, connected. Start `leakwatch.sh DT-AON-03 120`; in the app disconnect, wait 15 s, connect. Repeat 3×.",
  "0 LEAK samples; BLOCKED during the gap. Record whether the app's disconnect is allowed under Always-on and what it shows.",
  "`samples.csv`, screenshots"),
 ("DT-AON-04", "Lockdown: protocol switch", R,
  "Lockdown on. `leakwatch.sh DT-AON-04 180`; switch MASQUE → LANTERN → PSIPHON ONLY → MASQUE in the app.",
  "0 LEAK samples during every switch.", "`samples.csv`"),
 ("DT-AON-05", "Lockdown: force-stop / crash", R,
  "Lockdown on, connected. `leakwatch.sh DT-AON-05 120`; `adb shell am force-stop com.chakcaad.aethone`.",
  "0 LEAK samples. Record whether Always-on restarts the service by itself and after how long.",
  "`samples.csv`, `collect.sh DT-AON-05`"),
 ("DT-AON-06", "Lockdown: network handover", R,
  "Lockdown on, connected on Wi-Fi with mobile data on. `leakwatch.sh DT-AON-06 120`; turn Wi-Fi off, wait 30 s, on.",
  "0 LEAK samples; the tunnel recovers on each network (record time).", "`samples.csv`"),
 ("DT-AON-07", "Lockdown + per-app exclusion", R,
  "Lockdown on. App setting: per-app tunneling = disallow, list = Chrome. Reconnect. In Chrome open `http://ipv4.icanhazip.com`.",
  "Record the result. Android's documented behaviour: excluded apps get **no** network under lockdown. Chrome showing the direct ISP IP = FAIL (leak).",
  "screenshot, `collect.sh DT-AON-07`"),
 ("DT-AON-08", "Lockdown + shield re-enable (reconnect)", DA,
  "The DA app is the Always-on app, lockdown on. `shield.sh setup`, connect. Run `leakwatch.sh DT-AON-08 120`. During it: `shield.sh disable`, `shield.sh enable`, `shield.sh status` (expect `reconnect-required`), then reconnect in the app and run `shield.sh status`.",
  "0 LEAK samples; after the reconnect the status no longer lists `reconnect-required`, and `engineHook:true`. Fail-closed start with a broken profile is proven only on the emulator (testing §5); the device hook has no \"break\" command, so that part is N/A on device.",
  "`samples.csv`, `shield-calls.log`"),
 ("DT-AON-09", "The app's own Kill Switch toggle", R,
  "Settings → Connection → Kill Switch: try ON and OFF; repeat DT-AON-03 with lockdown **off**.",
  "Record the result. Code finding: the toggle is saved (`aethone.settings.killSwitch`), but no code in `lib/` or `android/` reads it at `f6e4dbf`. Expect the same behaviour ON and OFF; only Android lockdown blocks traffic during the gap. If ON prevents leaks, record it with evidence.",
  "`samples.csv` ×2"),
])

# ---------------------------------------------------------------- §8
sec(8, "KEY", "Keystore pepper and biometric",
 "The parent PIN is PBKDF2-HMAC-SHA256 (600 000 iterations), peppered with an HMAC key generated in the "
 "Android Keystore (StrongBox when available). **BiometricPrompt is not implemented** (security §6): "
 "only the core flag exists. Without root you can't read the database or the Keystore, so a copied "
 "database can't be checked on device. DA build, hooks on.", [
 ("DT-KEY-01", "PIN setup on device hardware", DA,
  "Fresh DA install (or clear its data). `shield.sh setup`.",
  "`setup` answers `ok:true` and returns a `recoveryCode` (write it down for DT-KEY-04). No Keystore exception in `logcat-filtered.txt`.",
  "`shield-calls.log`, `collect.sh DT-KEY-01`"),
 ("DT-KEY-02", "PIN verifies after force-stop and after reboot", DA,
  "`adb shell am force-stop com.chakcaad.aethone.da`; `shield.sh pin-try 583920`. Reboot, `hooks.sh on`, `shield.sh pin-try 583920`.",
  "Both answer with a `token`.", "`shield-calls.log`"),
 ("DT-KEY-03", "Backoff survives app kill", DA,
  "`shield.sh pin-try 111222` ×6; `adb shell am force-stop com.chakcaad.aethone.da`; `shield.sh pin-state`; `shield.sh pin-try 583920`.",
  "Attempts 1–5 `wrong-pin` with `attemptsBeforeLock` counting down; the 6th → locked with `lockedUntil` ≈ now+30 s; after force-stop `pin-state` still shows `lockedUntil`; the correct PIN before it expires → `locked`; after it expires → token.",
  "`shield-calls.log`"),
 ("DT-KEY-04", "Recovery code works once", DA,
  "`shield.sh recover <code from DT-KEY-01>` twice.",
  "First → token; second → refused.", "`shield-calls.log`"),
 ("DT-KEY-05", "Clear data removes PIN and key", DA,
  "`adb shell pm clear com.chakcaad.aethone.da`; `hooks.sh on`; `shield.sh pin-state`.",
  "`set:false`. A new `shield.sh setup` works (new Keystore key).", "`shield-calls.log`"),
 ("DT-KEY-06", "StrongBox vs TEE", DA,
  "Read `strongbox_feature` in DT-ENV-01.",
  "N/A for pass/fail: the app does not log which backing it got, and it can't be read without root. Record the feature flag only.",
  "`device.txt`"),
 ("DT-KEY-07", "Biometric unlock", DA,
  "—", "**N/A — BiometricPrompt UI not implemented** (security §6; `setBiometric` only stores a flag; `MainActivity` is still a `FlutterActivity`).", "—"),
 ("DT-KEY-08", "Gated call without a session", DA,
  "Run `adb shell am broadcast -a com.chakcaad.aethone.DEVICE_TEST -n com.chakcaad.aethone.da/com.chakcaad.aethone.shield.DeviceTestReceiver --es cmd admin --es method setEnabled --ez a.enabled false --ez nosession true` and read `adb logcat -d -s AethoneDeviceTest`.",
  "Answer `error: session-required`; shield stays enabled.", "logcat line"),
])

# ---------------------------------------------------------------- §9
sec(9, "MIG", "Import / export and the signing-key migration (v1.0.2 old key → new key)",
 "Facts: v1.0.2 is signed with the **compromised** key (`EB:F3:9C:82:…:1C:79`); new builds use the "
 "rotated key with **no v3 lineage**, so they can't install over v1.0.2. v1.0.2 has **no** export "
 "feature (export was added in phase 2), and phase 2 has no export/import **screen**. So on device, "
 "export/import only works through the DA hook, which runs the same `exportText`/`importText` code as "
 "the picker. The old → new migration of a real user is therefore **manual** today, as "
 "docs/settings-migration.md §5 already states. Keep the v1.0.2 APK from its GitHub release.", [
 ("DT-MIG-01", "v1.0.2 baseline", R,
  "Install v1.0.2 (old key) from its GitHub Release; configure it the way you use it (protocol, locations, hybrid rules, per-app list, kill switch, language). Screenshot every settings page. `install.sh` records its signer.",
  "Signer = the compromised cert (expected for v1.0.2 only). Screenshots of all settings.",
  "`apk.txt`, screenshots `DT-MIG-01-*.png`"),
 ("DT-MIG-02", "New-key APK refuses to install over v1.0.2", R,
  "`install.sh aethone-DEVICE-TEST-arm64-v8a-r<run>-release-NOT-A-RELEASE.apk` (without `--allow-uninstall`).",
  "`INSTALL_FAILED_UPDATE_INCOMPATIBLE` (signatures do not match); v1.0.2 still installed and working. If it installs, the APK is not signed by the new key; check DEVICE_TEST_INFO.txt.",
  "`install.txt`"),
 ("DT-MIG-03", "v1.0.2 export", R,
  "Look for an export function in v1.0.2.",
  "**N/A — v1.0.2 has no settings export** (feature added in phase 2). This is the migration gap: no bridge build exists (owner decision pending, settings-migration.md §5).",
  "—"),
 ("DT-MIG-04", "Manual migration v1.0.2 → new key", R,
  "`install.sh <release apk> --allow-uninstall` (uninstalls v1.0.2 = data loss), re-enter the settings from the DT-MIG-01 screenshots, connect.",
  "New app installed, signer = new cert; the settings are reproducible by hand; it connects. Record the time it took and anything that could not be restored.",
  "`install.txt`, screenshots"),
 ("DT-MIG-05", "Export (DA hook = the picker's code path)", DA,
  "DA app configured (protocol, hybrid rules, per-app list) + `shield.sh setup` + `shield.sh block example.com`. `shield.sh export`.",
  "`ok:true`; `containsTestPin:false`; `profiles` ≥ 1; the pulled JSON has `\"format\":\"aethone-settings\"`, `\"version\":1`, no `pin`/`recovery`/`salt` keys; its sha256 is logged.",
  "`exports/aethone-settings-export.json`, `shield-calls.log`"),
 ("DT-MIG-06", "Uninstall → install → import (cross-signature)", DA,
  "Keep the exported file. `adb uninstall com.chakcaad.aethone.da`. Install a DA APK from a **different** CI run (different debug key = a real cross-signature reinstall), or the same file if you have only one. `hooks.sh on`; `shield.sh import exports/aethone-settings-export.json`; force-stop and reopen the app.",
  "Import answer `ok:true`, `shieldImported:true`, `pinRequired:true`, `restartRequired:true`; after the restart the app settings match DT-MIG-05; `shield.sh config` shows the shield **disabled** until a new PIN is set (`shield.sh setup`), then the `example.com` rule is present (`shield.sh rules`).",
  "`shield-calls.log`, screenshots"),
 ("DT-MIG-07", "Tampered / invalid file is refused, nothing applied", DA,
  "Copy the export, edit it: (a) change `\"version\":1` to `2`; (b) add `\"malware\"` to a profile's `categories`; (c) truncate the file. `shield.sh import <file>` each time; then `shield.sh rules`.",
  "(a) `invalid-file` / `newer-version`; (b) `invalid-file`; (c) `invalid-file`; rules unchanged after each.",
  "`shield-calls.log`, the three files"),
 ("DT-MIG-08", "Import needs the parent session when a PIN is set", DA,
  "PIN set (DT-MIG-06 done). `shield.sh import-nosession exports/aethone-settings-export.json`.",
  "`error: session-required`; nothing changed.", "`shield-calls.log`"),
 ("DT-MIG-09", "Export/import from the release build UI", R,
  "—", "**N/A — no Flutter export/import screen in phase 2** (`settingsExport`/`settingsImport` have no Dart caller). Re-test when the phase-3 screen exists.", "—"),
])

# ---------------------------------------------------------------- §10
sec(10, "DOZE", "Doze, App Standby, long run, vendor battery killers",
 "`doze.sh` forces the state over adb and always restores it (battery reset, `deviceidle unforce`, "
 "bucket active). Forced Doze is not the same as a real overnight idle; DT-DOZE-05 is the real one. "
 "Record the app's battery setting first: Settings → Apps → AETHONE → Battery (Unrestricted / "
 "Optimized / Restricted).", [
 ("DT-DOZE-01", "Battery settings recorded", R,
  "DT-ENV-01 `standby_bucket`, `doze_whitelisted`, `run_any_in_background`; screenshot of the app battery page; vendor pages from §10.1.",
  "Recorded (no pass/fail).", "`device.txt`, screenshots"),
 ("DT-DOZE-02", "Deep Doze 30 min, tunnel up (Optimized)", R,
  "Battery = Optimized. Connect MASQUE, screen off. `doze.sh DT-DOZE-02 30 deep`.",
  "Same pid before/after; after restore the egress is TUNNEL within 60 s; **no LEAK sample** in `during.txt`. Record if traffic was BLOCKED during idle (normal for Doze).",
  "`doze.txt`, `during.txt`, collect snapshot"),
 ("DT-DOZE-03", "Deep Doze 30 min (Unrestricted)", R,
  "Battery = Unrestricted. Repeat DT-DOZE-02 as `doze.sh DT-DOZE-03 30 deep`.", "As DT-DOZE-02.", "as above"),
 ("DT-DOZE-04", "App Standby rare / restricted", R,
  "`doze.sh DT-DOZE-04a 15 standby-rare`; `doze.sh DT-DOZE-04b 15 standby-restricted` (Android 12+).",
  "Tunnel survives or recovers by itself; no LEAK sample. If the restricted bucket kills it, record that.", "`doze.txt` ×2"),
 ("DT-DOZE-05", "Real overnight run (≥ 8 h)", R,
  "Evening: connect LANTERN (or the protocol used daily), `collect.sh DT-DOZE-05-start`, leave the phone unplugged, screen off. Morning: before touching the app, `collect.sh DT-DOZE-05-end`, `leakwatch.sh DT-DOZE-05 60`, `adb shell dumpsys batterystats com.chakcaad.aethone > batterystats.txt`.",
  "Tunnel still up (or the reason it stopped is in logcat); 0 LEAK samples; no crash; record battery % used overnight and the app's share.",
  "both snapshots, `samples.csv`, `batterystats.txt`"),
 ("DT-DOZE-06", "Long run with the shield on (≥ 4 h, DA)", DA,
  "`shield.sh setup`, connect, normal use for ≥ 4 h, `shield.sh status` every hour (or start/end).",
  "Counters grow and never go backwards; `snapshotRejected` = 0; no crash; RSS in `meminfo.txt` at start vs end recorded.",
  "`shield-calls.log`, `collect.sh` start/end"),
 ("DT-DOZE-07", "Network change during idle", R,
  "Connected, screen off 10 min, then switch Wi-Fi off/on with the screen still off (adb: `adb shell svc wifi disable` / `enable`) while `leakwatch.sh DT-DOZE-07 120` runs.",
  "0 LEAK samples; tunnel recovers.", "`samples.csv`"),
], outro="""### 10.1 Vendor ROM notes (record which ones apply to the test phone)

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
""")

# ---------------------------------------------------------------- §11/12 matrix
CHECKS = [
 ("CON", "connects", "Exit ≠ direct baseline (`egress.txt`); app shows connected; for WARP-exit modes `warp=on`, for Tor/Psiphon/Lantern exits `warp=off`."),
 ("LSN", "listeners vs foreign uid", "No `socks-reply` on any port (requirement). **Expected today: FAIL-KNOWN-GAP** on the ports this mode opens; record them."),
 ("DNS", "DNS filtering (DA)", "`dns-check.sh` PASS: `example.net` fake IP + HTTP; `example.com` unknown host, no HTTP."),
 ("APP", "app blocking (DA)", "`appblock-check.sh` PASS (uid 2000 refused while restricted, works after release) + the manual Chrome check."),
 ("LEAK", "no direct leak", "30 s sampling: 0 LEAK samples (v4 and v6)."),
 ("KS", "kill switch / disruption", "90 s sampling while airplane mode toggles: 0 LEAK samples (run once with lockdown **off** and once **on** for at least MASQUE, LANTERN, PSIPHON ONLY, AETHER→TOR; record whether the tunnel recovers by itself)."),
]
single = [
 ("AUTO", "AUTO / SMART", "SMART walk over MASQUE, WIREGUARD, GOOL, MIM, GOOL CLASSIC (scorecard); record which one it picked (logcat)", "1819"),
 ("MASQUE", "MASQUE", "Aether, WARP exit", "1819"),
 ("WG", "WIREGUARD", "Aether `--protocol wg`, WARP exit", "1819"),
 ("GOOL", "GOOL", "Aether `--protocol gool`, WARP exit", "1819"),
 ("GOOLC", "GOOL CLASSIC", "Aether `--protocol gool --gool-classic`, WARP exit", "1819"),
 ("MIM", "MIM", "Aether `--protocol mim`, WARP exit", "1819"),
 ("TORONLY", "TOR ONLY", "plain Tor on 1819 (TCP only — UDP refused by zeptun)", "1819"),
 ("PSIONLY", "PSIPHON ONLY", "plain Psiphon on 1819 (TCP only)", "1819"),
 ("LANTERN", "LANTERN", "Lantern sidecar `liblantern.so` (separate process), UDP carried", "1822"),
]
hyb = [
 ("TORCHAIN", "AETHER → TOR", "WARP → Tor (1820, default) / WARP (1819)", ["WG", "MASQUE", "GOOL", "GOOLC", "MIM"], "TCP only"),
 ("TORREV", "TOR → AETHER", "Tor → WARP (1819, default) / Tor (1820)", ["MASQUE", "GOOL", "MIM", "WG2MASQUE", "GOOLC2MASQUE"], "TCP only; WireGuard/GOOL Classic legs are mapped to MASQUE by the app"),
 ("PSICHAIN", "AETHER → PSIPHON", "WARP → Psiphon (1821, default) / WARP (1819)", ["WG", "MASQUE", "GOOL", "GOOLC", "MIM"], "TCP only"),
 ("PSIREV", "PSIPHON → AETHER", "Psiphon → WARP (1819, default) / Psiphon (1821)", ["MASQUE", "GOOL", "MIM", "WG2MASQUE", "GOOLC2MASQUE"], "TCP only; WireGuard/GOOL Classic legs are mapped to MASQUE"),
]
LEGNAME = {"WG": "WireGuard", "MASQUE": "MASQUE", "GOOL": "GOOL", "GOOLC": "GOOL Classic", "MIM": "MIM",
           "WG2MASQUE": "WireGuard (→ MASQUE)", "GOOLC2MASQUE": "GOOL Classic (→ MASQUE)"}

p_rows = []
for code, label, what, ports in single:
    for ck, cname, crit in CHECKS:
        b = DA if ck in ("DNS", "APP") else EITHER
        p_rows.append((f"DT-P-{code}-{ck}", f"{label}: {cname}", b, f"`matrix.sh --only {code}`", crit, f"`DT-P-{code}-{ck}/*`"))
h_rows = []
for code, label, routes, legs, note in hyb:
    for leg in legs:
        for ck, cname, crit in CHECKS:
            b = DA if ck in ("DNS", "APP") else EITHER
            h_rows.append((f"DT-H-{code}-{leg}-{ck}", f"{label}, WARP leg {LEGNAME[leg]}: {cname}", b,
                           f"`matrix.sh --only H-{code}-{leg}`", crit + (" Logcat shows the engine started with `--protocol masque`." if leg.endswith("2MASQUE") and ck == "CON" else ""),
                           f"`DT-H-{code}-{leg}-{ck}/*`"))
hr_rows = []
RK = [("APP", "app rule: Chrome → second route", "Routing section → add app rule: Chrome → the second route. In Chrome open `http://www.cloudflare.com/cdn-cgi/trace`; from adb `http_get` (shell = default route) the same URL."),
      ("DOMAIN", "domain rule `www.cloudflare.com` → second route", "Add domain rule `www.cloudflare.com` → second route. Run `adb shell \"printf 'GET /cdn-cgi/trace HTTP/1.0\\r\\nHost: www.cloudflare.com\\r\\n\\r\\n' | toybox nc -w 8 www.cloudflare.com 80\"` and the same for `ipv4.icanhazip.com` (default route)."),
      ("WILDCARD", "wildcard rule `*.cloudflare.com` → second route", "As DOMAIN with `*.cloudflare.com`; also test the bare `cloudflare.com` (wildcard must not match the apex unless the app says so: record)."),
      ("CIDR", "CIDR rule → second route", "With the VPN off, note a real IPv4 of www.cloudflare.com (`adb shell ping -c1 www.cloudflare.com`, e.g. 104.16.x.x). Add CIDR rule `<that /24>` → second route. Connected: dial the IP literal with `Host: www.cloudflare.com`.")]
for code, label, routes, legs, note in hyb:
    for rk, rname, steps in RK:
        hr_rows.append((f"DT-HR-{code}-{rk}", f"{label} routing — {rname}", EITHER,
                        f"Connect {label} (leg MASQUE). {steps} Shield on (DA) for one of the four rule kinds: repeat `dns-check.sh` with the rule active.",
                        f"Traffic matching the rule exits through the second route, everything else through the default ({routes}). `warp=` in the trace tells the routes apart. No LEAK sample; disabling the rule moves the traffic back without reconnecting.",
                        "terminal output, screenshot, `collect.sh`"))

sec(11, "P", "Protocol matrix: single-tunnel protocols",
 "Single-tunnel protocols in the app (`lib/core/app_assets.dart` `ProtocolId`, `lib/connection/"
 "transport_modes.dart`, `hybrid_routing.dart` `profileOf` = null). Each gets the six checks below. "
 "`matrix.sh` walks them interactively; the DNS/APP checks need the DA build with hooks on (they are "
 "`N/A-NO-HOOK` on the release build). Run the matrix twice if time allows: release build (CON/LSN/LEAK/KS) "
 "and DA build (all six). Before it: `baseline.sh` on the same network.\n\n"
 "| Code | In the app | What runs | Listener(s) |\n|---|---|---|---|\n" +
 "\n".join(f"| {c} | {l} | {w} | {p} |" for c, l, w, p in single) +
 "\n\nChecks per protocol:\n\n| Check | Pass criterion |\n|---|---|\n" +
 "\n".join(f"| {ck} — {cn} | {cr} |" for ck, cn, cr in CHECKS), p_rows)
sec(12, "H", "Protocol matrix: hybrid protocols × WARP leg, and hybrid routing rules",
 "Hybrid protocols (`HybridRouting.profileOf` ≠ null) run two SOCKS listeners in one Aether process. "
 "The WARP leg is chosen per family in the Tor / Psiphon settings (`AetherLegProtocol`: WireGuard, "
 "MASQUE, GOOL, GOOL Classic, MIM). The CHAIN modes pass the leg as chosen. The REVERSE modes are TCP-only, "
 "so `protocolArgs` maps WireGuard and GOOL Classic to MASQUE; those two rows check that mapping. "
 "AUTO as the leg resolves to MASQUE (not a separate row). Tor bridges (auto/off/custom) and Psiphon "
 "fronting (auto/cdn/direct) are settings variants, not protocols. Test them only if a combination "
 "fails, and note which variant you used.\n\n"
 "| Code | In the app | Routes (default / second) | Legs tested | Note |\n|---|---|---|---|---|\n" +
 "\n".join(f"| {c} | {l} | {r} | {', '.join(LEGNAME[x] for x in legs)} | {n} |" for c, l, r, legs, n in hyb) +
 "\n\nThe six checks of §11 apply to every hybrid × leg combination (`matrix.sh --only H-<CODE>-<LEG>`). "
 "Then, with leg MASQUE, the routing-rule rows (DT-HR-*) check each rule kind (app, domain, wildcard, "
 "CIDR) sends traffic to the second route.", h_rows + hr_rows)

# ---------------------------------------------------------------- render
out = io.StringIO()
out.write(open(os.path.join(os.path.dirname(__file__), "head.md")).read().rstrip() + "\n\n")
counts = []
allrows = []
for num, key, title, intro, rows, outro in sections:
    out.write(f"## {num}. {title}\n\n")
    if intro:
        out.write(intro + "\n\n")
    out.write("| ID | Test | Build | Steps | Pass criteria | Evidence |\n|---|---|---|---|---|---|\n")
    for r in rows:
        out.write("| " + " | ".join(x.replace("|", "\\|").replace("\n", " ") for x in r) + " |\n")
        allrows.append((num, key) + r)
    out.write("\n")
    if outro:
        out.write(outro.rstrip() + "\n\n")
    counts.append((num, key, title, len(rows)))

tail = open(os.path.join(os.path.dirname(__file__), "tail.md")).read()
summary = "| § | Section | Tests |\n|---|---|---|\n" + "\n".join(f"| {n} | {t} | {c} |" for n, k, t, c in counts) + f"\n| | **Total** | **{sum(c for *_, c in counts)}** |\n"
out.write(tail.replace("@@COUNTS@@", summary))
open(os.path.join(REPO, "docs/family-shield-device-testing.md"), "w").write(out.getvalue())

# results template CSV
buf = io.StringIO()
w = csv.writer(buf, lineterminator="\n")
w.writerow(["test_id", "section", "title", "build", "platform(device|emulator)", "result(PASS|FAIL|FAIL-KNOWN-GAP|N/A|BLOCKED|NOT-RUN)", "date_time_tz", "network", "apk_file", "evidence_folder", "notes"])
for num, key, tid, title, build, *_ in allrows:
    w.writerow([tid, f"{num}-{key}", title, build, "device", "", "", "", "", "", ""])
open(os.path.join(REPO, S, "results-template.csv"), "w").write(buf.getvalue())
for n, k, t, c in counts:
    print(f"{n}\t{k}\t{c}\t{t}")
print("total", sum(c for *_, c in counts))
