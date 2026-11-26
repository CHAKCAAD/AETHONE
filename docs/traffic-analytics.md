# Traffic Analytics (Android)

Status: implemented on branch `feature/motion-phase3-lantern`, **not device
tested**, not released. Design research: `docs/traffic-analytics-design-research.md`.

## 1. Architecture

```
app socket ──TUN──▶ zeptun (patched)                         Android (Kotlin)                       Flutter
                    ├─ new TCP/UDP flow ──route cb──▶ HybridRouter.route ──▶ TrafficMeter.onFlowOpen
                    │                                  (policy + owner uid)    (uid→package, domain)
                    ├─ per-flow payload bytes ─meter cb─▶ Zeptun.meter ──────▶ TrafficMeter.onMeter
                    │   (every 2 s / 256 KiB, idle sweep,                      in-memory hour buckets
                    │    last report on close/shutdown)                        │ every 15 s, 1 transaction
                    └─ global counters 28/29 ◀── 1 s sampler ──────────────────┤
                                                                               ▼
                                                                  TrafficStore (SQLite) ◀─ trafficQuery ─ TrafficClient
                                                                                          ◀─ trafficLive ── (1 s poll on page)
```

No parallel capture exists: both events come from the engine that moves the
bytes, and the route recorded is the one zeptun **dialled** (`Conn.up.dial.route`),
not the one stored in settings.

### Single-tunnel vs hybrid
* Hybrid profile: unchanged routed start; the meter rides the same callbacks.
  Routes are the profile's tunnels (`psiphonChain`: `psiphon` = «WARP → Psiphon»,
  `warp` = «WARP»).
* Single-tunnel profile: when analytics is on, zeptun is started through
  `nativeStartRouted(…, servers = "")` with **no policy** — every flow
  answers route 0 (the same listener `nativeStart` uses) — only so the
  flow-open and meter callbacks run. The route id is the protocol id.
  Analytics off ⇒ the plain v1.0.2 `nativeStart`, no callbacks.
* A protocol change on the same tunnel target opens a new session under
  the new profile; history is never merged across profiles.

## 2. Measuring point

* **Upload** = payload bytes zeptun wrote to the flow's SOCKS5 stream (app → tunnel listener).
* **Download** = payload bytes zeptun read from that stream (tunnel listener → app).
* These are the exact places zeptun increments its own `upstream_tx_bytes` /
  `upstream_rx_bytes` (`src/stack/tcp.zig`: dial early data, `onUpstreamSent`,
  dial leftover, `upstreamData`). They are **payload** bytes: no IP/TCP
  headers, no TLS/QUIC/WireGuard overhead of the tunnel itself, no SOCKS
  framing. Interface counters (Android's own data usage) will read higher.
* **Transport overhead / per-hop load is not measured** (Not Implemented):
  the hops of a chain live inside the Aether / Psiphon / Tor cores, beyond
  the SOCKS listener. Because each flow is counted once at the single
  app-side point, a WARP → Psiphon flow is never counted twice.

## 3. Attribution

* App: `ConnectivityManager.getConnectionOwnerUid` at flow open (API 29+),
  the same lookup app rules use (looked up once, shared). uid → first
  package of `PackageManager.getPackagesForUid`; a uid without packages is
  `uid:N`; unknown owner (Android < 10, socket gone, lookup error) is
  `~unattributed`.
* Domain: the fake-IP table's name for the destination (zeptun fake-IP DNS).
  No name ⇒ no domain row (never invented). Host name only.
* Flow key: `proto|src:sport>dst:dport` (TUN addresses), dropped on the
  flow's last report or after 30 min without one.

## 4. Storage (`traffic_analytics.db`, app-private)

| table | key | values |
|---|---|---|
| usage_hour | UTC hour, profile, route, app | up, down, flows |
| rate_hour | hour, profile, kind (total/route/app), key | peak_down, peak_up (B/s, 2-s windows), active_s |
| domain_day | local day, profile, route, app, domain | up, down |
| usage_day / rate_day | local day … | rollup of hours older than 45 days |
| session | id | profile, started, ended, up, down, unmeasured |

* Writes: one transaction every 15 s from the meter thread (UPDATE-then-
  INSERT; SQLite UPSERT needs API 30, minSdk is 24). Nothing per packet or
  per flow is written.
* Compaction at each tunnel start: hours > 45 days → days; everything older
  than the retention (30 / 90 / 365 days / forever; default 90) deleted.
* Persists across app kill and reboot (SQLite, WAL). Up to 15 s of the last
  session can be lost if the process is killed hard.
* `~unmeasured` (route ""): bytes the engine's global counters moved that no
  flow report carried — UDP, DNS, and bytes of flows a hard stop cut. Computed
  against the global counter as of 10 s ago so in-flight reports are never
  booked as unmeasured; never attributed to an app or route.

## 5. Native ⇄ Flutter contract (`aethone/engine` channel)

| method | args | result |
|---|---|---|
| `trafficQuery` | `query`: JSON `{from,to,bucketMs,tzOffsetMs,profile?,app?,route?,compareWith?,appSeries?}` | JSON: `series[{t,up,down,unmeasured}]`, `apps[{app,up,down,flows,routes}]`, `routes[{profile,route,up,down,flows,apps}]`, `up,down,unmeasuredUp,unmeasuredDown,flows,peakDown,peakUp,activeS,firstRecord`, `domains[]` (app/route scoped), `compare{…}`, `appChanges[]`, `appSeries{app:{t:bytes}}` |
| `trafficLive` | — | `{running,enabled,profile,routes,down[60],up[60],routeRates{id:[up,down]},appRates{…},openFlows,startedAt}` |
| `trafficConfig` | `enabled?,domains?,retentionDays?` | current config |
| `trafficClear` | — | true |
| `trafficLabels` | `apps[]` | `{package: label}` |
| `trafficExport` | `format` csv/json | opens the system save picker; `{ok}` |
| `startVpn` (+) | `analyticsProfile` | — |

zeptun JNI (patch): `Zeptun.meter(proto,family,src,sport,dst,dport,route,up,down,closed)`.

## 6. Export formats
* CSV: `granularity,bucket_start_utc_ms,profile,route,app,upload_bytes,download_bytes,flows` (day rows then hour rows).
* JSON: `{format:"aethone-traffic-analytics",version:1,usage:[…],sessions:[…]}`.
Export only through the user's own save picker; nothing leaves the phone otherwise.

## 7. Limits (honest)
* **TCP:** measured per flow.
* **UDP:** not measured per flow (hybrid routes refuse non-DNS UDP; single-
  tunnel UDP goes through zeptun's UDP handler, not metered per flow) —
  counted only in `~unmeasured`.
* **IPv6:** the TUN carries no IPv6 route today, so IPv6 traffic bypasses
  the tunnel and AETHONE never sees it; it is neither counted nor shown.
* **DNS:** answered locally by fake-IP; not counted per app.
* **Per-hop / transport overhead:** not measured.
* **Peak speed** is the max of 2-second windows (per app / route / total);
  **average speed** = bytes / active seconds.
* Per-app needs Android 10+.

## 8. Feature status

| Feature | Status |
|---|---|
| zeptun per-flow meter (TCP), close/shutdown flush, idle sweep | Implemented — zig unit test of the record; **not device tested** |
| Flow attribution (uid, package, domain, real route) | Implemented but not fully tested (needs device) |
| SQLite store, rollup, retention, sessions, export, clear | Implemented but not fully tested (no Android instrumentation run) |
| Dashboard, apps, app details, route details, history UI | Implemented; Dart unit tests + render harness with a test-only mock channel |
| Live traffic | Implemented but not device tested |
| Range compare + app changes | Implemented; logic unit tested |
| UDP per-flow, per-hop transport load | Not Implemented |
| ru / zh / tk strings for this module | Not Implemented (fall back to en) |
| Acceptance scenarios 1–7 (device) | Not run |

## 9. Tests run (2026-11-26)
* `flutter analyze` — clean.
* `flutter test test/traffic_analytics_test.dart` — 25/25 (units, windows,
  bucket fill, downsampling, reconciliation apps = routes = total, unattributed
  vs unmeasured, compare guards, live parsing).
* `test/zz_traffic_analytics_shots_test.dart` — renders the screens with a
  **test-only** mock channel (fixture numbers live in the test file only).
* zeptun `zig build test` on the patched tree — see §10 of the PR / CI.
