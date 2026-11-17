# Per-App Routing — DECISIONS (Phase One: Architecture Audit)

Decision log for the per-app routing feature. Phase One decisions are audit findings and
proposed-architecture choices; they take effect only after owner approval.

## D1 — Do not create a second VpnService

The single `AethoneVpnService` stays the only VPN entry point. All per-app capabilities are
implemented inside the existing TUN data plane (zeptun) and the existing Builder lists.
Evidence: task rule 3; current architecture has exactly one service
(`AndroidManifest.xml` line 41, `BIND_VPN_SERVICE`).

## D2 — Include/Exclude rides the Builder lists (already shipped, keep as-is)

`appMode=allow|disallow|all` semantics in `AethoneVpnService.kt` (lines 411–454) are the
correct use of `addAllowedApplication`/`addDisallowedApplication`. Phase 2B requires no
architectural change — the two lists are mutually exclusive, a degenerate allow-list falls
back to whole-device, uninstalled packages are skipped non-fatally. These lists gate tunnel
MEMBERSHIP only; they are never presented as per-app route assignment.

## D3 — Per-app route assignment requires a zeptun flow-owner callback (no alternative path)

Facts that force this:
- After the TUN, only zeptun sees the original 5-tuple (`FlowKey`, parse.zig 379–396).
- SOCKS5 requests carry no source metadata, so a downstream dispatcher cannot attribute flows.
- UID ownership is queryable only from Java/Kotlin (`ConnectivityManager.getConnectionOwnerUid`,
  API 29+; the calling VPN app may observe flows riding its own tunnel; INVALID_UID if not found).
Therefore: add a zeptun JNI callback at flow-open (same pattern as the existing `protect`
callback, zeptun_jni.c 15–37) that returns a route decision per flow; zeptun dials the
per-flow upstream. A "dispatcher proxy" alternative was evaluated and rejected as unable to
identify the originating app.

## D4 — Route targets must be live, discovered endpoints — never advertised if not running

Selectable routes are derived at runtime from the active engine state:
- Default route = the user's configured engine mode (aether listener 127.0.0.1:1819).
- Chain-child routes (tor 1820 / psiphon 1821) are selectable only while the corresponding
  chain mode family is the active mode.
- Direct = zeptun's `direct` handler (in-TUN direct, keeps fake-IP DNS semantics) — requires
  the multi-handler config from D5; the coarse disallow-list remains a separate, coarser tool.
No route is displayed unless its endpoint is verifiably up (task rule: never display a route
the backend cannot execute).

## D5 — zeptun config grows a route table; single-handler stays the default

Extend the TOML schema with an optional route table (default handler + per-UID overrides +
direct), leaving today's single-handler config valid and unchanged for all existing modes.
The mobile build keeps `auto_route` off; the system still owns TUN membership.

## D6 — App attribution policy: TCP verified, UDP best-effort, fail-open only to default

- TCP: query at flow-open (SYN-time) — reliable.
- UDP: conntrack-based, best-effort; unattributed flows fall back to the DEFAULT route
  (never to an arbitrary route), and the UI documents this.
- Attribution failures must never reroute to a different app's route.
- A failed/down assigned route must not silently fall back to another route: fail-closed for
  that app's new flows + visible status in the UI (task §6).

## D7 — Live route-map updates where possible; TUN restart only for membership changes

- Include/Exclude changes keep today's behavior (TUN re-establish; `liveAppsKey`).
- Per-app route-map changes target a live zeptun config update (new channel →
  `nativeUpdateRoutes`) so existing flows keep their routes and only new flows re-resolve.
  If the live path proves unreliable in PoC, the fallback is a full reconnect — decided at
  Stage 2 PoC, before UI work.

## D8 — IPv6 left exactly as-is; kill-switch reliance documented, not changed

The TUN is IPv4-only today (Builder 408–410). Adding v6 routes would change existing
behavior and is out of scope for this feature; documented as a known limitation (v6 traffic
of tunneled apps bypasses the VPN on v6-capable networks — pre-existing). Kill switch
remains the OS always-on/block-without-VPN mechanism the app points to today.

## D9 — Multi-instance engines (parallel protocols) deferred to a separate milestone

Per-app targets like "Firefox→WARP while Telegram→Psiphon" with independent protocols need
multiple concurrent aether jobs (the FFI job registry supports ids, but the adapter, walk
state machine, and shared warp.toml assume a single session). Scope Phase 2C to
Default/Direct/child-chain routes; parallel protocols are Stage 4 with its own approval.

---

# Stage 2 (Core PoC) decisions — 2026-11-18, as implemented

## D10 — Reuse the existing flow callback; extend only the return-value contract

zeptun's C API already carried `zeptun_set_flow_callback` (`ZeptunFlow` tuple + verdict
enum). Rather than adding a second callback surface, the return value is re-packed as
`(route_number << 2) | action`: values 0..3 (every legacy caller) decode to their old
action on route 0 (default), so the ABI stays byte-compatible. Route numbers are
POSITIONAL (1..N against the `[routes]` document order) and the same document builds
both the native table and the Kotlin assignment map — the two sides cannot disagree.

## D11 — Attribution policy: bounded query, deterministic shared-UID rule, fail-open only to default

- API < 29: no query at all (counted skip) — every flow takes the default route.
- API ≥ 29: `getConnectionOwnerUid` on ONE bounded executor thread with
  `Future.get(50 ms)`. Timeout → default; the late result is DROPPED — it cannot
  corrupt a newer flow because each query is stateless and the synchronous return is
  the only writer of the decision. The zeptun engine thread is never blocked longer.
- Shared UIDs: only when EVERY package behind the uid carries the SAME assignment does
  that route win; mixed/unknown → default (deterministic, never an arbitrary pick).
- Unattributed / INVALID_UID / errors / unassigned package → default, counted.

## D12 — Direct routes need real DNS: forward the asking app's queries, fail closed on fake targets

- A direct-routed flow cannot dial a fake-IP destination (the fake range is unroutable
  and carries no hostname). The app's DNS query is itself a UDP flow: at the DNS
  interception point the flow-owner decision is consulted FIRST — a direct-routed
  app's query is redirected to `dns.upstream` (the system DNS, supplied on PoC starts)
  so the app receives REAL addresses. Default-routed apps keep fake answers.
- Config validation: any direct route + `dns.fake_ip` + no `dns.upstream` → rejected
  (initial and live updates; a live update cannot introduce direct without a start-time
  upstream).
- If a direct-routed flow still carries a fake IP (its DNS attribution failed), it
  FAILS CLOSED (RST/drop + `route_direct_fake` counter) — never silently tunneled via
  the default route (the user explicitly chose Direct; privacy rule).
- Documented PoC-scoped side effect: with `dns.upstream` set, non-A/AAAA queries are
  forwarded instead of answered with an empty NOERROR.

## D13 — Live route-table updates are safe and implemented; pools stay default-only

`zeptun_update_routes` validates the document in full, then atomically swaps the
engine-owned table under the route lock; readers copy entries under the same lock, so
the swapped-out table frees safely. Existing flows keep their established sockets; new
flows re-resolve; invalid documents never partially replace the table. The SOCKS5 warm
pool only ever serves the DEFAULT route (`d.upstream == null` gates at every pool
site) — pools cannot mix routes by construction, and a route dial failure never
perturbs the default pool (`proxyBusy` gated too).

## D14 — PoC supply chain: build from the vendored patched tree behind an explicit env gate

The APK's native build clones zeptun from the upstream pin; the vendored
`native/zeptun/` (byte-identical to the pin at audit, now carrying the PoC patch) is
a reference export. `scripts/build_native.sh` gains `ZEPTUN_LOCAL_SRC` (default
unset — the frozen path is untouched) and `scripts/build_native_poc.sh` wraps it for
PoC builds, copying the vendored tree to a scratch dir first. No pin changed, no
workflow changed, nothing committed or pushed — the owner decides if/when the patched
zeptun becomes a fork pin (the psiphon-fork precedent).
