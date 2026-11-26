# Hybrid Per-Tunnel Routing (Android) — v1.1.0

Status: **implemented end to end (UI → store → channel → VpnService → patched zeptun → policy engine)**; **not yet verified with real traffic on a device** (see §10). Nothing in this document counts a feature as done because a control exists.

## 1. What it does

In a hybrid protocol (two tunnels inside one Aether process) the user decides, per app, per domain and per IP/CIDR, which of the protocol's two routes the traffic takes. Traffic without a rule keeps the protocol's default route — byte-for-byte the pre-1.1.0 path. Rules apply to new connections immediately while connected; no reconnect, no protocol switch.

## 2. Architecture audit (state before this change)

| Question | Finding (source) |
|---|---|
| Hybrid structure | Aether runs WARP and, in-process, Psiphon or Tor. Chain: `aether → warp → psiphon/tor`; reverse: the WARP tunnel is dialled through Psiphon/Tor (`aether/src/lib.rs` mode switch, `cli.rs` `--psiphon`, `--psiphon-reverse`, `--tor`, `--tor-reverse`). |
| How each tunnel reaches the engine | Each is a **local SOCKS5 listener**: main `--bind` 127.0.0.1:1819, `--tor-bind` 1820, `--psiphon-bind` 1821. |
| Independent ingress per tunnel? | **Yes, in all four hybrid modes, both listeners run at the same time.** Chain: 1819 = WARP, 1821/1820 = WARP→Psiphon/Tor. Reverse: 1821/1820 = plain Psiphon/Tor (the carrier, `psiphon::start_reverse` / `tor::start_reverse` bind their `--*-bind` listener), 1819 = Psiphon/Tor→WARP. |
| Tunnel 1 → tunnel 2 | Chain: Psiphon/Tor dial the core's own 1819 listener (`socks::dialable(listeners.socks…)`). Reverse: `AETHER_UPSTREAM` points WARP's own dials at the carrier's SOCKS. |
| Independent steering possible? | Yes — choose the SOCKS listener per connection. |
| Native origin/route capability | zeptun (Zig TUN stack, pinned 1.1.3 @ 08a1ab0) had a per-flow **verdict** callback (proxy/direct/drop/reject with the 5-tuple) but **one** SOCKS5 upstream. Android hands it the VpnService fd; app identity is not in the packets. |
| DNS | zeptun answers DNS locally with **fake-IP** (`[dns] fake_ip = true`, VPN DNS 172.19.0.2) and dials the SOCKS proxy **by name**; resolution happens at the exit. |
| IPv4/IPv6/TCP/UDP | The VpnService routes **IPv4 only** (`addRoute 0.0.0.0/0`, no `::/0`). Hybrid modes are TCP-only (`udp = false` in zeptun: UDP flows get ICMP unreachable; DNS is answered locally). |

## 3. Design

```
Flutter UI (HybridRoutingPage)                      lib/features/settings/hybrid_routing_page.dart
  ↓ ConnectionStore.setHybridRules (per profile)    lib/connection/connection_store.dart
  ↓ persistence (shared_preferences, JSON)          lib/connection/settings_persistence.dart
  ↓ policy document (HybridRouting.policyJson)      lib/connection/hybrid_routing.dart
  ↓ MethodChannel aethone/engine: startVpn{hybridRouting} / hybridRoutingUpdate / hybridRoutingStatus
AethoneVpnService → HybridRouter.install/update     android/…/routing/HybridRouter.kt
  ↓ Zeptun.nativeStartRouted(fd, toml, "127.0.0.1:1819")
patched zeptun: per new TCP/UDP flow → route callback(5-tuple, fake-IP name)
  ↓ JNI → Zeptun.route → HybridRouter.route → HybridPolicy.decide   (…/routing/HybridPolicy.kt)
  ↓ answer: 0 = default listener, 16+i = route server i, 3 = reject
zeptun dials the chosen SOCKS5 listener → WARP / Psiphon / Tor inside Aether
```

* **Where the engine lives:** the decision is native (Kotlin, in the VpnService process) and is enforced by zeptun at dial time. Flutter only edits and stores rules; it never decides a route.
* **zeptun patch** (`scripts/zeptun-hybrid-routing.patch`, applied to the pinned tree by `scripts/build_native.sh` and by the CI zig-test gate; since 2026-11-26 it also carries the Traffic Analytics per-flow meter — see `docs/traffic-analytics.md`):
  * `handler.socks5.routes[0..4]` — extra SOCKS5 servers; `Dial.route` picks one per flow; the warm pool stays for route 0 only.
  * `zeptun_set_route_callback` / `zeptun_set_route_servers` (C ABI) and `Judge.askRoute` — answer decoding is **fail-closed**: any unknown answer, including "direct", rejects the flow; an out-of-range route index is refused, never defaulted.
  * TCP (`stack/tcp.zig`) and UDP (`stack/udp.zig`) ask the router once per new flow, passing the fake-IP domain when the destination is a fake address.
  * JNI: `nativeStartRouted(...)`; engine threads attach to the JVM once (detached on thread exit) and call `dev.zeptun.Zeptun.route(proto, family, src, sport, dst, dport, name)`.
* **Desktop** builds the pristine pin (`build_native_desktop.sh` resets the tree); Linux/Windows are out of scope.

## 4. Profiles (which routes exist)

| Protocol | Default route (unchanged) | Second route |
|---|---|---|
| AETHER → PSIPHON | WARP → Psiphon · 1821 | WARP · 1819 |
| PSIPHON → AETHER | Psiphon → WARP · 1819 | Psiphon · 1821 |
| AETHER → TOR | WARP → Tor · 1820 | WARP · 1819 |
| TOR → AETHER | Tor → WARP · 1819 | Tor · 1820 |

Psiphon in a chain cannot run without WARP, so it is labelled with its real chain («WARP → Psiphon»), never as a stand-alone Psiphon. Single-tunnel protocols (MASQUE, WireGuard, Gool, Gool Classic, MIM, AUTO, Tor only, Psiphon only, Lantern) have **no** profile: the section is hidden and the start carries no routing (`EXTRA_HYBRID_ROUTING` absent → plain `nativeStart`, identical to v1.0.2).

Rules are stored per profile (`ProtocolId.name`). Switching protocol switches rule sets; a single-tunnel protocol hides the section and keeps the hybrid rules for when the user comes back.

## 5. Policy engine

Priority (first match wins):

1. **App** — the flow's owner uid (from Android, §6) belongs to the rule's package. App rules beat every destination rule for that app.
2. **Exact domain** — `example.com` matches only `example.com` (case-insensitive, trailing dot ignored, IDN → punycode via `java.net.IDN`). `notexample.com` and `www.example.com` do not match.
3. **Wildcard domain** — `*.example.com` matches strict subdomains (`www.example.com`, `a.b.example.com`), **not** the apex. Longest suffix wins.
4. **IP / CIDR** — IPv4 and IPv6, single addresses or CIDR (host bits must be zero). Longest prefix wins; equal prefixes → the earlier rule.
5. **Default** — the protocol's own route.

Conflicts: identical values (same kind) are refused in the editor and, if they reach the engine anyway, the earlier rule wins and the later one is reported `duplicate`. Overlaps on different routes (a wildcard covering an exact domain, nested CIDRs) are shown to the user when saving; the more specific rule wins as above. Disabled rules are ignored.

Fail-closed: a rule naming a route the profile does not have **refuses** its traffic (reported `tunnel-unavailable`, shown in red) instead of re-routing it; an exception in the engine rejects the flow.

## 6. App identity (Android)

`ConnectivityManager.getConnectionOwnerUid(protocol, local, remote)` — the platform's socket-owner lookup, available to the active VPN app on **API 29+**. The 5-tuple comes straight from the TUN packet zeptun is about to proxy. The uid is compared by appId (`uid % 100000`) against the uids of the rule packages (`PackageManager.getApplicationInfo`), so work-profile copies match. On API < 29 app rules are unavailable and the UI says so; the engine then skips app rules. When the platform cannot attribute a flow (returns `INVALID_UID`, counted as `unattributed`) the flow falls through to domain/IP rules.

## 7. DNS and domain matching

* The domain comes from zeptun's own **fake-IP table**: every A/AAAA query the device makes to the tunnel resolver gets a unique private address mapped to the queried name, so the domain→address link is exact (no shared-IP ambiguity), expires with zeptun's TTL/LRU, and concurrent lookups are serialised by the table lock. The proxy is then dialled by name — the real resolution happens at the chosen exit (no DNS leak through the device network).
* **Not visible:** apps that use their own encrypted DNS (DoH/DoT/DoQ) or hard-coded IPs reach real addresses; those flows have no domain, so only app and IP rules can route them. ECH/SNI are never inspected; there is no TLS interception.
* IP rules match only flows to real addresses (a fake-IP flow's real address is unknown to the device by design).

## 8. Leak and failure behaviour

* A routed flow is always dialled to a local SOCKS5 listener; the route code space has no "direct" answer (anything unexpected rejects).
* If the chosen tunnel is down, dials to its listener fail and the app sees a reset — the flow never falls back to the other tunnel or to the internet.
* The policy is installed **before** zeptun starts, so there is no window without rules; rule edits are swapped atomically; established flows keep their route.
* A change of profile or route servers restarts zeptun exactly like a port change (existing behaviour); rules alone never restart it.
* The existing kill switch / always-on behaviour is unchanged (the TUN still owns the default route; the app's own sockets stay excluded).
* IPv6: the VpnService routes no IPv6 (unchanged); IPv6 rules apply to IPv6 flows only when an IPv6 route exists. UDP: hybrid modes stay TCP-only; UDP flows get ICMP unreachable as before.

## 9. Data model and contracts

Rule (Dart `HybridRule`, Kotlin `HybridPolicy.Rule`): `{id, kind: app|domain|wildcard|cidr, value, tunnel, enabled, label?}`.

Policy document (`startVpn.hybridRouting`, `hybridRoutingUpdate.policy`):
```json
{"profile":"psiphonChain",
 "tunnels":[{"id":"psiphon","endpoint":"127.0.0.1:1821"},{"id":"warp","endpoint":"127.0.0.1:1819"}],
 "rules":[{"id":"…","kind":"app","value":"org.telegram.messenger","tunnel":"warp","enabled":true}]}
```
The first tunnel is the default (zeptun's configured server); the others become route servers 1..n.

Channel methods: `hybridRoutingUpdate(policy)` → `{ok, error, …status}`; `hybridRoutingStatus` → `{live, profile, tunnels, activeRules, rejected[{id,reason}], routed{tunnel:flows}, hits{ruleId:flows}, refused, unattributed, appRoutingSupported, error}`; `appIcon(package)` → PNG bytes.

Persistence key: `aethone.settings.hybridRules.v110` (profile → rule list).

## 10. Tests and results

| Layer | Tests | Result |
|---|---|---|
| zeptun patch (Zig) | `flow/verdict.zig`: route answer decoding (default, servers, never-direct, out-of-range), callback receives the fake-IP name; upstream suite incl. `tcp_sim` runs on the patched tree in the CI zig-test gate | see CI run for this commit |
| Policy engine (Kotlin, JVM) | `HybridPolicyTest`: package match, exact domain + boundary, wildcard apex rule, most-specific wildcard, IDN, IPv4, IPv6, CIDR longest prefix, priority app→exact→wildcard→IP, duplicate conflict, default route, disabled rules, unavailable tunnel fail-closed, input validation | see CI run (step «Hybrid routing — Kotlin policy unit tests») |
| Dart | `test/hybrid_routing_test.dart`: profiles only for hybrid protocols, ports, validation, overlaps, policy document, persistence per profile, single-tunnel never stores, UI visibility, add/switch/disable/delete, invalid-route display | see CI run (Flutter UI job) |
| Integration / acceptance on a device (Scenarios 1–7) | run by the owner on 2026-11-25 with the r126 arm64-v8a APK (commit b06160d); exit path checked with `cloudflare.com/cdn-cgi/trace` (`warp=on` / `warp=off`) | **passed (owner-reported, all 7)** |
| Emulator runtime smoke | existing job; currently failing on the emulator 37.2.13 pin drift (infra, unrelated) | not usable as evidence |

## 11. Known limitations

* Device-level traffic acceptance (Scenarios 1–7) passed on the owner's phone on 2026-11-25 (r126, b06160d). The first device build (r125) failed every hybrid connect with `zeptun-start-failed:rc=-1`: R8 had removed `Zeptun.route`, the JNI callback libzeptun-jni resolves by name. Fixed by `android/app/proguard-rules.pro` plus a CI dexdump gate on the release APK.
* Not covered by CI on this branch: the emulator runtime smoke and APK cold-start smoke fail on the emulator version pin (37.2.13), an infrastructure issue.
* App rules need Android 10+; unattributable flows fall back to destination rules.
* Domain rules cannot see DoH/DoT/hard-coded-IP traffic (§7).
* One JNI call per new flow (plus one binder call when app rules exist) on the engine thread; fine for normal use, untested under very high connection rates.
* Hybrid modes are TCP-only (existing); IPv6 is not routed into the TUN (existing).
* A user-overridden `AETHER_PSIPHON_BIND` / `AETHER_TOR_BIND` (expert env) would point routes at the wrong port; such flows fail closed.
