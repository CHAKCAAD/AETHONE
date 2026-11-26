# Family Shield — testing (phase 1)

**Nothing in this phase was tested on a device or emulator.** Results below are host tests
(Zig on Linux, Kotlin on the JVM) plus the CI run recorded in `docs/family-shield.md`.

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

## 4. Device acceptance list (phase 2 — NOT run)

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
