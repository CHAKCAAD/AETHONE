# Family Shield — testing (phase 1 + phase 2)

**No real device was used in any phase.** §1–§3 are host tests (Zig on Linux, Kotlin on the JVM);
§5 is the phase-2 emulator evidence from CI (x86_64 Android emulator, not a phone).

## 1. Zig (zeptun patch) — run by the CI zig-test gate on every patched tree

`flow/shield.zig`
* exact / root / wildcard rules, strict label boundary (`notexample.com`, `example.com.evil`, bare TLD)
* priority: mandatory > parent blocklist > categories > allowlist > unknown; allowlist never beats mandatory
* allowlist-only (unknown = block) profile, positive lists
* IDN → punycode normalization (`München.de`, `bücher`, `中国`), invalid names refused
* IPv4 + IPv6 CIDR (several prefix lengths, non-matching neighbours, fake addresses never CIDR-matched)
* strict mode (853, UDP/443, alternative DNS, direct IP) on and off
* invalid snapshots refused: short, truncated, bit-flip (checksum), magic, version, resealed bad entry
  hash, CIDR host bits, un-normalized names, unknown header flags
* atomic install: refused snapshot keeps the previous one; private copy; clear; swap counter
* verdict encoding; empty snapshot
* **cross-language golden**: a snapshot built by the Kotlin builder (hex embedded) parses with the same
  verdicts and the same SHA-256 as `ShieldSnapshotTest`

`flow/verdict.zig` — the shield-aware route callback wins over the plain one and receives the verdict;
revalidate callback keep/kill.

`stack/dns.zig` — NXDOMAIN (rcode 3, no answers, **no authority/SOA**) for A, AAAA, HTTPS (65),
SVCB (64), MX of a blocked name with forwarding enabled; no fake-IP slot taken; label boundary;
AAAA of an allowed name still gets a fake v6; no snapshot = unchanged behaviour.

`tests/shield_engine_tests.zig` (whole engine, external device, real loopback sockets)
* blocked TCP SYN → RST, no conn opened, nothing reaches the server
* blocked UDP → ICMP port unreachable, no session
* revalidation: after a rule change the newly blocked live flow gets a RST, the other flow keeps
  echoing data
* fake-IP DNS through the engine: NXDOMAIN for A/AAAA/HTTPS/SVCB; allowed name gets a fake IP; after the
  parent blocks that name, a SYN to the **cached** fake IP is reset at flow open (no dial)

Local result (2026-11-26, aarch64 sandbox, Zig 0.16.0, `zig test` of the targeted root with the mobile
feature set): 108 passed, 1 skipped (TUN inside a namespace, not permitted in the sandbox), 0 failed —
this includes the existing `tcp_sim` scenarios and the rest of the library's unit tests. The full
upstream gate (Debug, ReleaseSafe, mobile preset, C-ABI smoke, netns, TUN integration) runs in CI.

## 2. Kotlin JVM unit tests — `android/app/src/test/kotlin/com/chakcaad/aethone/shield/`

Run by CI step "Hybrid routing + Family Shield — Kotlin unit tests" (fail-closed: ≥ 4 suites / 30 tests).

| Suite | Covers |
|---|---|
| `ShieldPolicyTest` | mandatory priority, blocklist vs allowlist, allowlist overrides categories only, categories per preset, exact vs root list entries, unknown-domain policy (toddler allowlist-only, kids-safe), wildcard + label boundary, CIDR v4/v6 real vs fake, rule conflicts (block wins, reported), other profiles' rules ignored, **UID match by appId (work profile)**, **invalid / missing UID**, level order mandatory/blocklist > app > category/unknown, allowlist never opens a restricted app, inactive native snapshot fails closed, RouteGate (blocked flow never reaches hybrid policy nor the traffic meter; single-tunnel/hybrid answers untouched), verdict encoding = native |
| `ShieldSnapshotTest` | deterministic golden snapshot (SHA-256 shared with Zig), round trip, invalid snapshots rejected (8 kinds), compiler output validates and drops irrelevant bits, strict flags + Private DNS suppression |
| `ShieldCoreTest` | age presets (ranges, nesting, mandatory never in a preset), **profile switching keeps every profile's rules/apps/categories + history**, rule validation (IDN, CIDR host bits, bad input), names/CIDR, content sources (parsers, dedupe, truncation/shrink guards, versioning, rollback, licences, URLhaus absent), events (aggregation, domain opt-in, failing sink keeps batch), SOCKS auth plan, status reasons |
| `ParentPinTest` | PBKDF2 = RFC 7914 vector and = JDK `PBKDF2WithHmacSHA256`, 600 000 default, no default PIN, weak PINs refused, peppered hash, session expiry, **backoff** (5 free, 30 s doubling, persisted across instances), one-time recovery code, admin ops need a session, biometric session gating |

Local result (2026-11-26, Temurin 17 + kotlinc 2.1.20 on the pure sources): 33 tests, 0 failures.
(The Android-only classes `ShieldStore`, `KeystorePepper`, `FamilyShield` are compiled by the APK build
but have no instrumentation tests in phase 1.)

## 3. Regression

Existing suites keep running unchanged in CI: `HybridPolicyTest` (hybrid routing), Flutter tests
(traffic analytics, kill switch / connection store, DNS-related Dart tests), the zeptun upstream gate
(single-tunnel paths, DNS, tcp_sim). With the shield **off** the VpnService start is unchanged: no
snapshot call, no IPv6 route, no hijack, the same `nativeStart` / `nativeStartRouted` choice as before.

## 4. Device acceptance list (real device — NOT run)

The full step-by-step protocol with pass/fail criteria, evidence and the adb helper scripts is
[family-shield-device-testing.md](family-shield-device-testing.md) (branch
`feature/family-shield-device-test`). The list below is its summary. It has still **not been run on a
real device**.

1. Shield off: every protocol connects exactly as v1.0.2 (single tunnel, hybrid, Lantern, Tor, Psiphon).
2. Shield on, single tunnel + hybrid: blocked domain → browser shows "site can't be reached" immediately;
   allowed domains load; hybrid rules still route as configured.
3. App restriction (Android 10+): the restricted app gets no network, others unaffected; added live →
   its open connections drop within a second.
4. Rule change while a page streams: only newly blocked flows stop.
5. IPv6-only site / IPv6 network: traffic goes through the TUN (or status shows `ipv6-not-captured`).
6. Strict mode with Private DNS off / automatic / hostname — DNS keeps working in all three.
7. Traffic Analytics: blocked flows are not counted; totals unchanged otherwise.
8. Kill switch / always-on behaviour unchanged.
9. PIN: lockout survives app kill; recovery code works once; backup/restore does not carry the PIN.
10. Snapshot sizes and RAM with real lists (unmeasured).

## 5. Phase 2 — emulator end-to-end (CI job `shield-e2e`) — passing evidence only

Source: native-ci run **46006344077** on `feature/family-shield-phase2` @ `6eaddf5`
(https://github.com/CHAKCAAD/AETHONE/actions/runs/46006344077), job
"Family Shield e2e (emulator: DNS, uid, loopback guard, IPv6, revalidation)" = **success**, artifact
`shield-e2e-evidence` (`results.txt`: **35 PASS, 0 FAIL**, no NOTE lines; no tombstone, no
`SIGSYS`/`seccomp` line in any captured logcat; the app pid stayed 3711 from tunnel start to the end).

Whole run: 23 jobs success, 1 skipped (publish, default branch only) on attempt 2. Attempt 1 had one
failure outside the shield: "APK cold-start smoke" stopped at `adb root` (`adb: unable to connect for root:
closed`, emulator infrastructure); its re-run (attempt 2, same commit) passed, and so did "Status summary".

Environment: Android 16 (API 36) `google_apis_ps16k` x86_64 system image, pinned emulator 37.3.10,
the packaged **release** APK (`aethone-ui-r140-release-universal.apk`) with the real x86_64
`libzeptun-jni.so`; adbd root (userdebug image) only to run clients as uid 2000 / 0. The app's
`ShieldTestReceiver` (not exported, inert unless `debug.aethone.shieldtest=1`) drives the admin API through
`ShieldChannel.handle` (the dispatcher the method channel calls) and hosts a SOCKS5 **test stub** on
127.0.0.1:1819 behind `LoopbackGuard`; zeptun tunnels the emulator's traffic into that stub, so the stub's
CONNECT log is the ground truth of what reached the tunnel. **No real core (Aether / Psiphon / Tor /
Lantern) runs in this job.**

### 5.1 Seccomp fix (root cause of the previous e2e failure)
Run 45870688624 died on the first routed TCP flow: `SIGSYS / SYS_SECCOMP` "disallowed x86_64 system call
7" (`poll`) in `zeptun_run` (tombstone_00). zig's `std.os.linux.poll/open` emit the legacy syscall on
x86_64, which Android's app seccomp filter admits only for 32-bit ABIs. The zeptun patch now routes every
Linux `poll` through `sys.ppollMs` (ppoll, null sigmask) and every `open` through `sys.openAt` (openat);
`epoll_wait` already maps to `epoll_pwait` in zig 0.16 and `eventfd` to `eventfd2`.
CI gate `scripts/check_android_seccomp.py` (job "ELF & ABI inspection") disassembles
`out/x86_64/zeptun/libzeptun.so` and `libzeptun-jni.so` and fails on any direct legacy syscall
(poll, select, epoll_wait, open, access, stat, lstat, pipe, dup2, fork, eventfd, …) after a fixture
self-test. Run 46006344077: self-test OK; each library 159 direct syscall sites, 0 denied, 1 site with a
non-constant number (a loop-invariant `nanosleep`, nr 35, reviewed). Locally the unfixed x86_64 build
is flagged (`poll` ×1, `open` ×5), the fixed one is clean; zeptun unit tests 123 passed / 8 skipped /
0 failed (aarch64 host, includes a `ppollMs` test).

### 5.2 Checks that passed on the emulator
| Area | Check (results.txt) |
|---|---|
| Admin API | PIN setup + session + 2 profiles + enable; a gated call without a parent session → `session-required` |
| Start | shielded tunnel up with the snapshot installed before the engine thread; status `engineHook:true` (zeptun counter 6 = 1); listener 1819 detected and guarded; IPv6 route + address accepted by the Builder |
| Engine stability | app pid unchanged after the first routed flow and at the end (no crash, no tombstone) |
| DNS | allowed name → fake IP → reaches the tunnel; `blocked.*` and `www.blocked.*` → NXDOMAIN, no CONNECT ever reached the stub; engine `dnsBlocked` = 6 at that point (10 at the end) |
| Loopback gate (stub only) | uid 2000 and uid 0 get no SOCKS reply (reset by the gate); in-process client admitted (own-process socket match); rejections logged; zeptun's own dials admitted (`allow:own-process`); `getConnectionOwnerUid` named uid 2000 |
| Fake-IP cache | cached fake IP 198.18.0.12 reaches the tunnel while allowed; live rule applied (atomic snapshot swap, no tunnel restart); the same cached IP refused at flow open after the block; no new CONNECT for that name |
| Revalidation | open flow to a newly blocked name aborted within 1 s (`zeptun_revalidate_flows`) |
| App blocking (uid) | restricted uid 2000 refused before any SOCKS dial, no CONNECT from it; after release its flows pass again |
| Profiles | switch to profile b applies (`applied:ok`); b's rule blocks, a's rule no longer applies; back on a, a's rules apply again |
| IPv6 | TUN carries `fdfe:dcba:9876::1/126`; an IPv6 TCP flow reached the engine and the tunnel; counter 7 = 815 IPv6 packets |
| Status | final `state: protected`, no reasons — **only because the sole listener is the guarded test stub on 1819; 1820–1822 not listening** |
| Export | export validates, carries 2 profiles and no PIN |
| Fail-closed | a broken shield start is refused and no TUN is established |

Counters at the end (`status-final.json`): dnsBlocked 10, flowBlocked 1, flowsKilled 4, snapshotSwaps 5,
snapshotRejected 0, ipv6Packets 815, generation 12.

### 5.3 What this evidence does NOT cover
* Any real device (phone/tablet), vendor ROM, Private DNS modes, Always-on / lockdown VPN, battery/Doze.
* The real cores' SOCKS listeners 1819–1822 (Aether/Psiphon/Tor/Lantern) — they bind their own sockets
  and are **not** behind `LoopbackGuard`; with any of them running, status stays degraded
  (`local-socks-exposed`), never Protected.
* The Dart side of the `aethone/family_shield` method channel (no UI in phase 2; only the Kotlin dispatcher
  was driven).
* Settings import through the file picker; per-app exclusion audit beyond the whole-device case; batched
  event delivery to a UI; Keystore pepper on real hardware; snapshot size/RAM with real lists.
* arm64 / armeabi-v7a at runtime (the emulator is x86_64; arm64 has no legacy `poll` syscall, armeabi-v7a
  is admitted by the 32-bit allowlist, and the same ppoll/openat code is compiled for both).
