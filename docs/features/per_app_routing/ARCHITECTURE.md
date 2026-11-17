# Per-App Routing — Phase One Architecture Report (Audit Only)

Status: **Phase One complete. No implementation. Awaiting owner approval.**
Scope: Android only. Repository `CHAKCAAD/AETHONE`, branch `fix/owner-round-2`, HEAD `5502d34`,
clean tree, audited 2026-11-18. No files were modified, no builds or tests were run.

---

## 1. Current Architecture

### 1.1 Android VPN layer

`AethoneVpnService` (`android/app/src/main/kotlin/com/chakcaad/aethone/AethoneVpnService.kt`)
is the single `VpnService` (manifest line 41, `BIND_VPN_SERVICE`, foreground `specialUse`).
`startTunnel` (line 347) builds the TUN: MTU 1500, address `172.19.0.1/30`, route `0.0.0.0/0`
(IPv4 only — no v6 address or route), DNS `172.19.0.2` (answered by zeptun's fake-IP DNS),
then applies per-app membership and hands the fd to zeptun:

- `appMode == "allow"` with a non-empty list → `addAllowedApplication` per package
  (the app's own uid is implicitly outside the allow-list);
- `appMode == "disallow"` → `addDisallowedApplication` per package, own package always
  appended;
- otherwise (`all`) → only the app itself is disallowed (loop prevention, lines 411–454).

Uninstalled/invisible packages throw per entry and are skipped non-fatally. Changing the
app mode/list while the TUN is up re-establishes it (the `liveAppsKey` comparison, lines
366–383 — an established TUN cannot be re-scoped). `VpnService.protect` is installed as
zeptun's upstream-socket guard (JNI callback, §1.2).

### 1.2 TUN data plane — zeptun (Zig)

`Zeptun.nativeStart(this, fd, toml)` (line 503) starts the userspace stack. Key facts from
`native/zeptun/src`:

- **One handler per config.** `config.zig` line 8 defines `HandlerKind = direct | socks5 |
  passthrough`; line 352 holds a single handler. The mobile TOML used today is exactly
  `preset="mobile"`, `[handler] kind="socks5"`, `server=127.0.0.1:<port>`, optional
  `udp=false` / `pipeline=false` / `optimistic_data=false`, `[dns] fake_ip=true`
  (AethoneVpnService lines 487–501). There is **no rule engine and no per-flow upstream
  selection**.
- **Flow table exists.** Flows are keyed by the full 5-tuple (`FlowKey` in
  `packet/parse.zig` lines 379–396: src/dst addr, ports, proto, v6 flag) in an LRU table
  (`flow/table.zig`) — per-flow state is available for attaching an owner/route.
- **Fake-IP DNS.** DNS is answered locally (`stack/dns.zig`); the hostname is preserved and
  carried to the SOCKS5 upstream at connect time — so a per-flow route decision also
  governs where each app's DNS-dependent connection exits; raw external-UDP:53 flows are
  ordinary UDP flows.
- **Direct handler exists** (`handler/direct.zig`) with an Android `protect` hook
  (`Protect.android_fn`) — in-TUN direct routing without any proxy is implementable.
- **JNI bridge precedent.** `src/jni/zeptun_jni.c` caches a `protect(I)Z` method and
  registers `protect_socket` as a C callback (lines 15–37, 60, 82) — the exact pattern a
  new flow-owner callback would follow.
- Desktop-only `--include-uid/--exclude-uid` flags exist (`cli/args.zig` lines 91–92) but
  belong to the route module that the mobile build drops; there is **no UID logic in the
  mobile data path**.

### 1.3 Engine layer — aether (Rust, in-process)

The aether core runs in-process via dart:ffi (`lib/connection/aether_ffi.dart`:
`aether_core_start(args_json)` → job id; poll/cancel/free; one active connection at a
time). `AetherArguments.build` (`platform_engine_adapter.dart` lines 92–175) assembles CLI
arguments: `--bind 127.0.0.1:1819` plus the selected mode — a WARP-leg protocol
(`--protocol …`) and optionally an overlay flag (`--tor`, `--tor-reverse`, `--tor-only`,
`--psiphon`, `--psiphon-reverse`, `--psiphon-only`). Local SOCKS5 endpoints:

| Port | Endpoint | Availability |
| --- | --- | --- |
| 1819 | aether core in the active mode | always while connected |
| 1820 | tor chain child (lyrebird PT) | tor overlay modes only |
| 1821 | psiphon chain child (goptlib, `socksStrict`) | psiphon overlay modes only |

The mode is a single CLI selection: selecting plain WARP does not run Psiphon at all, and
selecting `psiphonChain` makes 1819 itself ride over the psiphon child. There is no
multi-instance engine management today (single job, single walk state machine, shared
`warp.toml`).

### 1.4 Existing per-app capability (already shipped — v4.41/v4.42)

- Model: `AppTunnelMode` (all/allow/disallow) + `appTunnelApps` set
  (`lib/connection/app_tunnel.dart`, `connection_store.dart` lines 252–303).
- Persistence: SharedPreferences keys `aethone.settings.appTunnelMode/appTunnelApps`
  (`settings_persistence.dart` lines 62–64, 191–196, 399–401); corrupt values resolve to
  `all`.
- Plumbing: `startVpn` channel args `appTunnelMode`/`appTunnelApps` → intent extras →
  service Builder (`MainActivity.kt` lines 319–360; adapter call sites 1296–1300, 2700–2701).
- Picker UI: `lib/features/settings/routing_page.dart` per-app section + `_AppPickerList`
  (search included). App list via `installedApps()` (`MainActivity.kt` line 570):
  launchable apps, AETHONE excluded, label+package only (no icons transported).
- Package visibility: `<queries>` launcher-intent declaration (manifest lines 82–96) — all
  launchable apps visible without `QUERY_ALL_PACKAGES`.

### 1.5 Routing rules that exist today

Destination-based, engine-level: `--route-direct` / `--route-block` lists (aether
`cli.rs` line 324) fed from the routing page's expert section via `coreSettings`, plus the
routing-region country selector. Nothing in the stack associates traffic with an
application identity.

### 1.6 Settings, state, and lifecycle

`ConnectionStore` (ChangeNotifier) is the single source of user state, persisted via
SharedPreferences; the engine adapter owns connect/disconnect walks, probes, and the TUN
lifecycle. Kill switch is a persisted UI preference whose enforcement relies on the OS
always-on / block-without-VPN device setting (adapter header comment, line 16) — no in-app
enforcement hook exists.

---

## 2. Feasibility Assessment

### 2.1 The core question

Per-app **route assignment** (different apps → different routes) requires attributing each
TUN flow to an app identity. Membership (include/exclude) is already solved by the Builder
lists; those lists cannot express "app A via route 1, app B via route 2" — the task brief
states this correctly and the source confirms it.

### 2.2 Application identity: what Android actually offers

- `ConnectivityManager.getConnectionOwnerUid(protocol, local, remote)` — API 29+ (Android
  10). Returns the owner uid "if the connection is found and the app has permission to
  observe it (e.g., if it is associated with the calling VPN app's VpnService tunnel)",
  `INVALID_UID` otherwise. TCP and UDP are both accepted; TCP attribution is reliable at
  connect time, UDP attribution is conntrack-based and best-effort (short-lived entries).
- `/proc/net/tcp` parsing — blocked for untrusted apps on modern Android; not a path.
- `PackageManager` — app listing works today (launcher-intent queries, no restricted
  permission); uid↔package mapping is available on the same query.
- TUN packets carry **no** uid/mark metadata available to userspace.

**Conclusion:** flow→app attribution is feasible on API 29+ via `getConnectionOwnerUid`,
called from Kotlin, at flow-open time, using the exact 5-tuple zeptun already parses.

### 2.3 Why the current data plane cannot do it — and the only valid hook

- Only zeptun sees the original 5-tuple; only Kotlin can query ConnectivityManager.
  Therefore zeptun must call back into Kotlin per new flow and receive a route decision.
  The existing `protect` callback proves the JNI pattern.
- A "dispatcher proxy in the middle" (zeptun → local SOCKS5 multiplexer that picks the
  upstream) **cannot work**: SOCKS5 requests carry only the destination — the dispatcher's
  inbound sockets belong to zeptun, so owner-uid queries would return AETHONE's own uid for
  every flow. This option is rejected, not deferred.
- zeptun's config holds one handler, so per-flow upstream selection and a `direct`
  fallback need a route-table extension (default handler + per-uid overrides).

### 2.4 What routes can honestly exist

With one engine job in one mode, the honest per-app route set for Phase 2C is:

1. **Default** — the user's configured mode (listener 1819). Always selectable.
2. **Direct** — zeptun `direct` handler (in-TUN, fake-IP DNS preserved). Requires the
   route-table extension.
3. **Chain-child routes** — tor (1820) / psiphon (1821), selectable only while the active
   mode is the corresponding chain family (endpoint verifiably up).

Independent parallel protocols ("Firefox→WARP while Telegram→Psiphon" as separate engines)
require multiple concurrent aether jobs — the FFI job registry allows ids, but the adapter,
walk state machine, and shared `warp.toml` assume a single session. That is a separate,
larger backend milestone (deferred; D9).

### 2.5 Verdict table

| Capability | Verdict |
| --- | --- |
| Application Manager (list, search, icons) | Feasible — listing exists; icons need channel work |
| Include Selected Apps | **Already implemented** (v4.41) |
| Exclude Selected Apps | **Already implemented** (v4.41) |
| Per-app route assignment (single-engine routes) | Feasible — requires zeptun + Kotlin + Dart changes (§3–§5) |
| Parallel multi-protocol per-app routes | Not feasible with current engine management — deferred milestone |
| Live route-map updates without TUN restart | Feasible target; PoC-gated fallback to reconnect |
| Per-app routing on Android < 10 (API 24–28) | Not supported — degrade to default route |

---

## 3. Required Backend (zeptun, Zig) Changes

1. **Flow-owner JNI callback**: at TCP SYN / first UDP packet of a flow, call a new
   Kotlin method (e.g. `flowRoute(proto, srcAddr, srcPort, dstAddr, dstPort) → routeId`)
   following the `protect` callback pattern; cache the decision in the flow entry.
2. **Route table in config**: optional section — default handler + per-routeId handler map
   (socks5 endpoints and/or `direct`). Absent section = today's single-handler behavior
   (zero regression for existing modes).
3. **Per-flow dial override**: the socks5/direct dial path selects the handler by the
   flow's routeId; pooled/pipelined handshakes must key on (route, destination).
4. **Live route-map update**: a `nativeUpdateRoutes(json)` entry point that swaps the
   route table without restarting the TUN (existing flows keep their routes; new flows
   re-resolve).
5. **Failure semantics**: a route whose endpoint is down fails that flow closed (no
   silent fallback to another route); surfaced via existing stats/event bridge.
6. **Tests**: Zig unit tests for route-table parsing/selection; a fixture harness proving
   per-flow handler selection.

## 4. Required Android (Kotlin) Changes

1. **UID resolution service**: `getConnectionOwnerUid` on flow-open (API 29+ gate), with a
   small uid→package→routeId cache (LRU + TTL) fed from the persisted assignment map;
   INVALID_UID / API < 29 → default routeId. Called on a dedicated binder thread; never on
   the zeptun callback thread beyond a bounded wait.
2. **New channel surface** (MainActivity/EngineBridge): `appRoutes` map (package →
   routeId), `availableRoutes` (live endpoint discovery from the engine state), icon
   transport for the picker (base64 PNG at a bounded size, or `PackageInstaller`-safe
   drawable → PNG), and route-map push on change.
3. **Service wiring**: pass the initial route table with `startVpn`; forward live updates.
4. **Permissions**: none new. No `QUERY_ALL_PACKAGES` (launcher-intent queries already
   cover launchable apps).

## 5. Required Flutter/Dart Changes

1. **Store/persistence**: per-app route map (package → routeId) in `ConnectionStore` +
   SharedPreferences (separate keys — changing the default route must never overwrite
   assignments); prune/flag uninstalled packages; unknown routeId → default + visible
   notice; profile switching preserves assignments.
2. **Route catalog**: `availableRoutes` derived from the live engine state (D4) — the UI
   may only offer what the catalog says is running; unsupported routes render disabled
   with a reason.
3. **UI** (routing page, existing design system — IRANYekanX, existing palette/icons/
   animations, light/dark): per-app routing entry, assignment selector, default-route
   selector, save/apply status, empty/loading/error/permission states. No unrelated
   screens touched.
4. **Lifecycle**: membership changes keep the TUN-restart behavior; route-map changes push
   live updates and report backend-confirmed success only (task §4F).

---

## 6. Limitations and Risks

- **UDP attribution is best-effort** (conntrack races) — unattributed UDP falls to the
  default route; documented in UI, never silently rerouted to another app's route.
- **API 24–28** cannot attribute flows — feature degrades to default route on those
  devices (minSdk is 24).
- **Per-flow callback latency**: a binder call at every flow-open (~ms scale); mitigated
  by caching; PoC must measure connect-time impact.
- **IPv6 bypass (pre-existing)**: the TUN is v4-only; on v6-capable networks, v6 traffic
  of tunneled apps bypasses the VPN today. Out of scope; must be stated, not silently
  changed (D8).
- **Kill switch** relies on the OS always-on mechanism; unchanged by this feature.
- **Routing loops**: own-uid exclusion + `protect` remain the guards; the `direct` handler
  must use the same protect hook; child chains run under AETHONE's uid (already excluded).
- **Shared engine state**: Stage 4 (multi-instance) touches `warp.toml` sharing and the
  single-session walk — the highest-risk item and explicitly deferred.
- **Privacy**: package lists and per-flow attributions must not be logged beyond debug
  builds.

## 7. Recommended Implementation Approach (staged, approval-gated)

- **Stage 1 — Picker polish (2A/2B remainder)**: icons, empty/loading/error states.
  Small, no native changes.
- **Stage 2 — zeptun per-flow routing (PoC first)**: D3/D5/D6/D7 backend work + Kotlin
  UID service. PoC gate: on a device, two test apps verifiably exit through different
  routes (checked by exit-IP), TCP and UDP, with connect-time overhead measured and
  loop-safety re-verified.
- **Stage 3 — Product surface**: route catalog, assignment UI, persistence semantics,
  lifecycle wiring, automated tests (unit + widget) and the 12 acceptance criteria.
- **Stage 4 — (deferred, separate approval)**: multi-instance engines for parallel
  protocols.

**Approval request:** confirm this architecture (or amend), after which `SPEC.md` will be
authored from this report and Stage 1 begins.

---

## 8. Stage 2 — Implemented PoC Design (as built, 2026-11-18)

The owner approved Stage 2 (core PoC). What follows is the design AS IMPLEMENTED in the
working tree — every claim below maps to changed source under `native/zeptun/` and
`android/app/src/main/kotlin/`.

### 8.1 Route numbering and the flow-owner callback (extends the existing C API)

zeptun already exposed `zeptun_set_flow_callback` (a `ZeptunFlow` tuple + a 4-value
verdict) — unused by AETHONE until now. Stage 2 extends ONLY the return-value contract:

- `ret = (route_number << 2) | action` — legacy values 0..3 decode to their old action
  with route 0 (default), so every existing caller stays byte-compatible.
- Route 0 = the default = the existing global `[handler]` (the active engine mode).
  Routes 1..N = `[routes]` entries, numbered POSITIONALLY; the controller (Kotlin)
  builds both sides from the same document, so numbering can never disagree.
- The JNI bridge (`src/jni/zeptun_jni.c`) registers a `flowRoute(protocol, family,
  source[16], sourcePort, destination[16], destinationPort)` method lookup on the
  service object and installs the callback only when `nativeStart(..., flowCallback)`
  is asked to (PoC starts only — the normal path carries zero per-flow upcalls).
- The callback fires once per NEW flow (TCP SYN / first UDP packet / first DNS query
  of a flow); the session lookup runs BEFORE the DNS branch in `udp.zig` precisely so
  the callback never fires per-packet. The decision is cached on the flow: the Dial's
  `upstream`/`strict` (a value copy of the route entry, taken under the route lock —
  safe across live table swaps) or the UDP session's handler state.

### 8.2 Route table (config + live update)

- Document schema (TOML and JSON, parallel lists — the parser has no arrays of tables):
  `[routes] ids=[…] kinds=[…] servers=[…] strict=[…]`. Absent section = today's
  single-handler behavior, unchanged (`config.zig`, `config_json.zig`).
- Validation (`config.validateRoutes`, shared by create and update): unique non-empty
  ids, kinds ∈ {socks5, direct}, socks5 port ≠ 0, ≤ 8 entries, and **a direct route
  requires `dns.upstream` whenever `dns.fake_ip` is on** (§8.4).
- `zeptun_update_routes(handle, doc, len)` (new C entry point): parses the document,
  validates it IN FULL, then swaps the engine-owned table under a spin lock (house
  style — dns.Table's pattern) and frees the old one after the swap. Readers copy
  entries under the same lock, so nothing dangles. Invalid documents never partially
  replace the active table. Existing flows keep their established sockets; new flows
  re-resolve.
- Per-flow SOCKS5 credentials are NOT supported in route entries (out of PoC scope);
  a route entry's `strict` flag reuses the global pipeline/optimistic settings
  sequentially for goptlib-style upstreams.

### 8.3 Per-flow handler selection

- `Dial.upstream` / `Dial.strict` (TCP) and `UdpState.bypass`/`ctrl.upstream` (UDP):
  the resolved route rides the flow. `openFresh` dials `d.upstream orelse
  cfg.handler.socks5.server`; the handshake honors `strict` (no pipelining, no
  optimistic data).
- **Warm pool isolation:** the connection pool only ever holds connections to the
  DEFAULT server; route-assigned dials never take or refill pool slots (`d.upstream ==
  null` gates at every pool site). Pools cannot mix routes by construction.
- **Fail-closed semantics:** a route whose endpoint refuses/accepts nothing fails its
  flows (existing dial-failure abort path — RST/ICMP); no fallback to another route.
  An out-of-range/stale route number (table swapped mid-flight) degrades to the
  DEFAULT route and increments `route_fallback` — never to another app's route.

### 8.4 Direct routes and DNS (the fake-IP problem)

A direct-routed flow cannot dial a fake-IP destination (198.18.0.0/15 is unroutable
and carries no hostname). The PoC therefore:

1. **Forwards the DNS of direct-routed apps to the real resolver.** A DNS query is
   itself a UDP flow of the asking app: at the DNS interception point (`udp.zig`) the
   flow-owner decision is consulted FIRST; a direct-routed app's query is redirected
   to `dns.upstream` (the system DNS, passed by the service on PoC starts) instead of
   being fake-answered. Default-routed apps keep fake answers (hostname preserved to
   the SOCKS5 upstream) — `dns_fake_answers` distinguishes the two.
2. **Fails closed when a direct flow still carries a fake IP** (its DNS attribution
   failed): TCP gets a bare RST, UDP is dropped, `route_direct_fake` counts it. The
   flow is never silently tunneled through the default route — the user explicitly
   asked for Direct (privacy rule D6).
3. PoC-scoped side effect (documented, not silent): with `dns.upstream` set, non-A/AAAA
   queries are forwarded to the real resolver instead of receiving an empty NOERROR.

### 8.5 Latent upstream bug fixed (made reachable by this feature)

zeptun's pre-existing `bypass` (direct verdict) path under a SOCKS5 global handler
framed UDP datagrams with the SOCKS5 header on a RAW socket (`udpSend`/`flushTx`/
`deliverBatch` keyed the framing off the GLOBAL handler kind). Unreachable before
(no AETHONE caller used the flow callback); per-flow routing makes it reachable. Fixed
with a per-session `UdpState.bypass` flag — raw datagrams in both directions for
direct-routed UDP flows.

### 8.6 Kotlin (Android) side

- `PerAppRouteResolver` — `ConnectivityManager.getConnectionOwnerUid` on API 29+,
  single bounded executor thread, `Future.get(50ms)` timeout, late results dropped
  (the synchronous return is the only decision writer). API 24–28: counted skip,
  default route, no query. `INVALID_UID`/exceptions/missing packages → default.
  Shared UIDs: only unanimous assignments resolve; mixed → default. Metrics: calls,
  attributed, timeouts, errors, avg/max latency (dumped via the PoC receiver).
- `AethoneVpnService` — `EXTRA_POC_ROUTES` (adb-only JSON) builds the `[routes]`
  TOML + `dns.upstream`; the resolver goes live BEFORE `nativeStart` (the engine
  attributes flows immediately); the flow callback is installed only on PoC starts;
  `poc_routes` is part of the tunnel restart key (like the app set). `flowRoute(...)`
  is the JNI callback target. Teardown closes the resolver after `nativeStop` joins
  the engine thread — no callback can outlive the engine.
- `PoCRoutesReceiver` (manifest, exported, per-instance token printed at PoC start) —
  `POC_UPDATE_ROUTES` (live swap: native table first, then the Kotlin map; the
  in-between window degrades to default, counted) and `POC_ROUTES_STATS`.
- Dart/UI: **no changes** (Stage 3 owns the product surface).

### 8.7 Supply chain

The APK builds zeptun from the upstream pin (`Noisemux/zeptun@08a1ab0`), not the
vendored `native/zeptun/` reference export — so the PoC adds `ZEPTUN_LOCAL_SRC`, an
explicit env-gated local-source path in `scripts/build_native.sh` (default behavior
unchanged), plus `scripts/build_native_poc.sh` (wrapper that copies the vendored
patched tree to a scratch dir and invokes the recipe). No pin changes, no CI workflow
changes, nothing committed or pushed.
