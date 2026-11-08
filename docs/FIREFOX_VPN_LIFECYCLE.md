# FIREFOX VPN lifecycle — state machine, start/stop, errors, recovery (Phase 1)

Status: **Phase 1, private branch `phase1/firefox-vpn` only.**

Two machines run side by side and never conflate responsibilities:

* the **Dart-side engine supervisor**
  (`lib/connection/firefox/firefox_engine.dart`,
  `FirefoxVpnEngine`) — owns the child process;
* the **connection walk**
  (`PlatformEngineAdapter._connectFirefox`) — owns the session states
  the store/UI consume. It reuses AETHONE's session generation (`gen`)
  and staleness machinery unchanged.

## 1. The engine state machine (9 states)

```
idle → starting → processStarted → socksReady → probing → connected
                    │ (any state)                       │
                    └────────────→ failed ←─────────────┘
connected/stopping → stopped      (stop() from any live state)
```

| State | Set by | Meaning |
|---|---|---|
| `idle` | constructor | never started |
| `starting` | `start()` | spawn requested |
| `processStarted` | `Process.start` resolved | the child exists (proves NOTHING about the listener — that is `socksReady`'s job, and only the engine's own event sets it) |
| `socksReady` | engine event `socksReady` | the SOCKS5 listener is REALLY bound on 127.0.0.1:1822 |
| `probing` | adapter `markProbing()` | the host's end-to-end probe is in flight |
| `connected` | adapter `markConnected()` | the host probe came through the tunnel — `Connected` is the probe's to declare, never the engine's |
| `stopping` | `stop()` | shutdown requested (stdin closed) |
| `stopped` | clean drain/exit | terminal |
| `failed` | engine `failed` event OR non-zero exit | terminal |

Rules: `isAlive` covers `processStarted..connected`; `start()` throws
`StateError` if a previous engine is still alive (exactly one process —
no pool, by decree); `stop()` is idempotent and safe when never started.

## 2. The connection walk (`_connectFirefox`)

The walk mirrors the aether skeleton with the engine swapped in, so the
store's state machine needed no changes:

1. **stale-state hygiene** — `_hardCleanup()` first (never start a
   second engine over a live one); `_stale(gen)` guards every step.
2. **platform guard** — Windows tunnel mode fails honestly
   (`platformLimit`, see the Android doc).
3. **port-conflict proof** — `1822` must be free (`firefoxPortBusy`).
4. **VPN permission** (tunnel mode only) BEFORE any engine work
   (`vpnPermissionDenied`).
5. **session** — load from the Keystore vault; no session → honest
   `firefoxNoSession` (never fake credentials).
6. **tunnel bring-up** (tunnel mode): `startVpn` + zeptun TUN first,
   `tcpOnly: true`, `socksStrict: false` (the Go SOCKS server reads its
   handshake strictly sequentially with `io.ReadFull`, so zeptun's
   pipelined greeting+request is safe — verified by the lifecycle
   tests); proxy mode takes the `startCoreHold` foreground hold instead.
7. **spawn** — bare argv, empty env; the config line goes on the stdin
   pipe; `authRefreshed` returns to the vault, never logged.
8. **wait for the engine's own `socksReady`** (bounded by
   `_firefoxStartBudget` 60 s; the live tests clock the whole sequence
   well under 2 s). NOT reached → `firefoxEngineStartTimeout`, or the
   engine's own words via `firefoxEngineFailed`
   (`firefoxQuotaExhausted` is its OWN error so the user picks another
   engine — never a silent fallback).
9. **end-to-end probe** — the SAME `TunnelProbe` as the aether family,
   through 127.0.0.1:1822; retries inside `readyBudget(firefoxOnly)`
   (90 s). The engine dying during the probe fails the walk with the
   engine's own reason. Probe through + tunnel alive → `Connected`:
   `markConnected()`, real stats only (`statsEvent(probe)`).
10. **steady state** — the same 5 s ticker (port-based probe; with no
    aether job id the core-liveness step is skipped by design). The
    engine dying while connected surfaces as `EngineHealthProbeFailed`
    → the store's reconnect logic owns the recovery (no fake
    `Connected`).

## 3. Shutdown and orphans

`stop()`: set `stopping` → close the child's stdin (the engine's
shutdown request: it refuses new work, drains live tunnels, closes the
listener and controller, emits `stopping`/`stopped`, exits 0) → await
exit bounded by `shutdownGrace` (3 s) → **kill** on expiry ("no orphan
survives a disconnect") → teardown streams → `stopped`. The adapter's
`_hardCleanup` stops the engine child FIRST, and a `disconnect()` during
the walk relies on the same path.

Engine-side (`cmd/libfirefoxvpn`): shutdown watchers run for the WHOLE
process lifetime — stdin EOF and SIGTERM/SIGINT both trigger the clean
stop; a host cancel DURING STARTUP aborts the walk cleanly
(`cancelledDuringStart`, exit 0 — a cancel is not a failure, so no
`failed` event is emitted and the host already knows why).

## 4. Exit-code mapping

| Exit | Meaning | Dart outcome |
|---|---|---|
| 0 | clean stop (stdin closed / drained) | `stopped` (cleanStop) |
| 1 | startup/config (`badConfig`, `discoveryFailed`, `noMatchForCountry`, `passFetchFailed`, `upstreamSessionFailed`, `socksListenFailed`) | `failed` with the engine's failCode |
| 2 | quota exhausted — user picks another engine (`firefoxQuotaExhausted`) | `failed` (quotaExhausted) |
| 3 | renewal timeout — session dead, the host/store decides reconnect | `failed` (renewalTimeout) |
| 4 | internal error | `failed` (internalError) |

An engine that exits without a terminal event is mapped from the exit
code (`engineExited:<code>`), so an unexpected death is never silent.

## 5. Edge cases covered by tests

* cancel during start (`TestLifecycleCancelDuringStart` — 22 s of
  adversarial cancelling),
* port already busy (`TestLifecyclePortBusy`),
* malformed config: public listener / bad version / no access token
  (`TestLifecycleBadConfig`, subtests),
* real Guardian + invalid token → honest failure, no token leak
  (`TestLifecycleRealGuardianRejectsFakeToken`),
* real Fastly h2 session with a fake pass → `socksReady`, engine-side
  exit probe HONESTLY fails (`TestLifecycleRealFastlySession`),
* stdin-EOF shutdown and bare-argv spawn on the Dart side
  (`test/firefox_engine_test.dart`, REAL host binary group).
