# Family Shield — architecture (phase 1)

Status: core policy engine implemented (native + Kotlin); **not device tested**; no UI (phase 2).
Plan it implements: `family-shield-phase0` (owner-approved, 2026-11-26).

## 1. Where the shield sits

```
app DNS query ──TUN──▶ zeptun udp.zig ──▶ dns.answerShield
                                            ├─ name parsed (lower-case)
                                            ├─ shield.checkName ── BLOCK ─▶ NXDOMAIN, no SOA, no fake-IP slot, no upstream
                                            └─ allow ─▶ Table.resolve (fake IP)            (A, AAAA, HTTPS/SVCB, any qtype)
app TCP SYN / first UDP datagram ──▶ zeptun tcp.passiveOpen / udp.input
        name = fake-IP table name (or null for a real address)
        verdict = shield.checkFlow(name, dst, fake?, proto, port)        ◀── same snapshot (cached fake IPs can not bypass)
        ──JNI routeShield(…, verdict)──▶ HybridRouter.route
                     uid = getConnectionOwnerUid  (ONCE, only if shield / hybrid app rules / analytics need it)
                     FamilyShield.decide(verdict, uid)  ── adds level 3 (app restrictions)
                     RouteGate: blocked ─▶ ROUTE_REJECT (no HybridPolicy, no dial, no traffic meter)
                                allowed ─▶ HybridPolicy (unchanged) ─▶ TrafficMeter.onFlowOpen(uid)
        zeptun: verdict.block OR answer==reject ─▶ TCP RST / ICMP port-unreachable (never a SOCKS dial)
later UDP datagram to another peer on the same socket ─▶ checkFlow again (endpoint-independent NAT hole closed)
rule change ─▶ ShieldCompiler ─▶ Zeptun.nativeShieldSnapshot (validate + atomic swap) ─▶ nativeRevalidateFlows
        every worker: TCP conns + UDP sessions re-checked; blocked ─▶ tcp.abort(RST) / udp close; others untouched
```

* The shield is **independent** of HybridPolicy: it is evaluated first, in single-tunnel and in hybrid starts.
* **Trigger for the routed start:** `AethoneVpnService` starts zeptun through `nativeStartRouted(…, servers = "")`
  when Family Shield is on, even without hybrid routing or analytics (`routing != null || metered || shieldPlan.active`).
* Blocking never uses `addDisallowedApplication` / `addAllowedApplication` (those *bypass* the VPN).

## 2. Native (zeptun patch)

All native changes ride the existing `scripts/zeptun-hybrid-routing.patch` (applied by `build_native.sh`
and by the CI zig-test gate exactly like before). New file `src/flow/shield.zig`; hooks in
`stack/dns.zig`, `stack/tcp.zig`, `stack/udp.zig`, `engine.zig`, `flow/verdict.zig`, `handler/handler.zig`,
`ffi/ffi.zig`, `include/zeptun.h`, `jni/zeptun_jni.c`.

| Piece | What it does |
|---|---|
| `Snapshot.parse` | Full validation before use: magic/version/header length, exact total length, power-of-two bucket table larger than the entry count, SHA-256 over the file, every entry (normalized name, FNV-1a hash, known flags, reachable and unique by probing), bucket occupancy, CIDR sort order / host bits / prefix range. Anything off → refused. |
| matcher | Reversed-label walk over a hash table: the exact name's *self* bits, then the *sub* bits of every proper suffix cut at a dot (`example.com` never matches `notexample.com`). Exact / root / wildcard rules = self / self+sub / sub. IPv4 + IPv6 CIDR: binary search per prefix group, all containing prefixes collected. |
| `normalize` | lower-case ASCII, trailing dot dropped, non-ASCII labels → punycode (RFC 3492). No IDNA mapping (e.g. `ß`) — DNS wire names are already ASCII. |
| `State` | `std.atomic.Value(?*Loaded)`; readers pin with a seq-cst reader count for one lookup; `install` validates, copies, swaps, then frees the old snapshot once the reader count is observed at zero (or parks it until engine destroy). An invalid snapshot is refused and the previous one stays. |
| DNS hook | `dns.answerShield` after the name parse and **before** `t.resolve`: NXDOMAIN (rcode 3), zero answers, **no SOA** (nothing for resolvers to cache negatively), for every query type. |
| flow hook | TCP `passiveOpen` and UDP session open: verdict computed, passed to the route callback, enforced natively whatever the callback answers. UDP datagrams to a destination other than the one the session was judged for are checked per datagram. |
| revalidation | `zeptun_revalidate_flows` bumps `shield.epoch` and wakes every worker; each worker walks its TCP conns / UDP sessions on its next loop turn, aborts blocked ones (`tcp.abort(c, true)` = RST), asks the app layer (`revalidate` callback) for app restrictions, leaves allowed flows untouched. |
| C ABI | `zeptun_shield_validate`, `zeptun_set_shield_snapshot` (any time; NULL clears), `zeptun_set_shield_route_callback`, `zeptun_set_revalidate_callback`, `zeptun_revalidate_flows`, `zeptun_shield_counter`, `zeptun_shield_check`. |
| JNI | `nativeShieldSnapshot([B)I` (validate, keep as *pending*, swap into a running engine), `nativeShieldValidate([B)I`, `nativeRevalidateFlows()I`, `nativeShieldCounter(I)J`; callbacks `routeShield(II[BI[BILjava/lang/String;I)I` (preferred over `route`) and `revalidate(…)I`. A pending snapshot is installed **before** the engine thread starts (no unfiltered window); if it can not be installed the start fails. Start/stop/shield calls are serialised by one mutex. |

Verdict passed to Kotlin (`u32`): bit 31 snapshot active, bits 0–7 block, 8–15 level, 16–23 category index + 1.

## 3. Snapshot format v1

Little endian. Header 128 bytes (magic `AETHSHLD`, version 1, flags, total length, generation,
enabled/mandatory/allow category masks, counts, profile id, 24 reserved zero bytes, SHA-256 at 96..128
computed with those 32 bytes zeroed), then entries (40 B), buckets (u32), IPv4 rules (24 B),
IPv6 rules (32 B), strings. Authoritative layout: top of `src/flow/shield.zig`; the builder is
`android/…/shield/ShieldSnapshot.kt`. A golden snapshot built by Kotlin is parsed by a Zig test with
identical verdicts (cross-language check).

Header flags: `unknown_block`, `strict_dot`, `strict_quic`, `strict_direct_ip`, `strict_alt_dns`.
Rule flags: `parent_block`, `parent_allow`.

## 4. Rule priority (final)

| # | Level | Evaluated | Overridable by allowlist |
|---|---|---|---|
| 1 | Mandatory security (Malware, Phishing) | native (DNS + flow) | never |
| 2 | Parent locked blocklist | native (DNS + flow) | never |
| — | Strict mode network rules (optional) | native (flow) | never |
| 3 | App restrictions (uid) | Kotlin, flow time only (Android 10+) | never |
| 4 | Age-based categories | native | **yes** |
| 5 | Parent allowlist (+ positive lists such as kids-safe) | native | — |
| 6 | Unknown-domain policy (per profile) | native | yes (allowlist-only mode) |

DNS time has no uid, so it applies 1, 2, 4, 5, 6; flow time adds 3. Because level 3 only ever *adds*
a block, DNS-time and flow-time decisions can not contradict each other.

## 5. Kotlin layer (`android/app/src/main/kotlin/com/chakcaad/aethone/shield/`)

| File | Role | JVM-tested |
|---|---|---|
| `ShieldCategories.kt` | category bits (format-stable), mandatory / positive lists | yes |
| `ShieldModel.kt` | config, profiles, rules, app restrictions, events, repository interface + in-memory impl | yes |
| `AgeProfiles.kt` | presets + `ProfileManager` (independent profiles, switching, history) | yes |
| `DomainNames.kt` | normalization (java.net.IDN), CIDR parsing | yes |
| `ShieldSnapshot.kt` | builder + full validating reader (same semantics as native) | yes |
| `ShieldCompiler.kt` | profile + rules + category DB → snapshot | yes |
| `ShieldDecision.kt` | app-layer decision (level 3) + `RouteGate` ordering | yes |
| `ShieldEvents.kt` | aggregated, batched protection events | yes |
| `ParentPin.kt` | PIN core | yes |
| `ContentSources.kt` | list registry, parsers, dedupe, validation, versioning, rollback | yes |
| `SocksAuth.kt` | local-listener auth audit + credential plumbing | yes |
| `ShieldStatus.kt` | Off / Protected / Degraded / Failed with reasons | yes |
| `ShieldStore.kt` | SQLite store in `noBackupFilesDir` + Keystore pepper | no (Android only) |
| `FamilyShield.kt` | runtime: start plan, live apply, decide, revalidate, events flush, status | no (Android only) |

`HybridRouter.route` now: one uid lookup shared by shield, hybrid policy and meter → shield first →
hybrid → meter (blocked flows are never metered, so they never count as tunnel traffic in Traffic
Analytics). `AethoneVpnService`: shield start plan before the TUN exists, IPv6 capture and DNS hijack
while the shield is on, restart only when the shield is toggled.

## 6. VpnService behaviour with the shield on

* `[dns] hijack = true` — UDP/53 to *any* address is answered by the shielded fake-IP resolver
  (apps with a hard-coded 8.8.8.8 are filtered too).
* IPv6: `addAddress("fdfe:dcba:9876::1", 126)`, `addRoute("::", 0)`, `addDnsServer("fdfe:dcba:9876::2")`
  (zeptun's own preset addresses; zeptun is built with IPv6). If the Builder refuses, the start continues
  but the status is **Degraded: ipv6-not-captured** (explicit warning in logcat and status).
* Shield off: byte-for-byte the previous start (IPv4-only TUN, no hijack, plain `nativeStart` unless
  hybrid/analytics need the routed start).
* Proxy mode: no TUN → the shield can not filter (status Off: `no-tunnel`).

## 7. Not in phase 1

Flutter screens, method-channel admin API, BiometricPrompt UI, list downloading/updating, device tests.
