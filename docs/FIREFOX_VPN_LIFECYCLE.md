# FIREFOX VPN lifecycle — state machine, start/stop, errors, recovery (Phase 1)

Status: **Phase 1, private branch `phase1/firefox-vpn` only.**

Three cooperating layers run in one session and never conflate responsibilities:

* the **Aether carrier** (Rust core, embedded through Dart FFI) — establishes the outer WARP tunnel and owns SOCKS5 `127.0.0.1:1819`;
* the **Dart-side Firefox engine supervisor**
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

## 2. The connection walk (`_connectFirefox`) — Firefox over WARP

Firefox VPN is no longer a direct/standalone protocol. It always runs as
an inner tunnel over an Aether/WARP carrier:

```text
selected Aether carrier protocol (default: WireGuard)
             |
             v
Aether WARP tunnel + SOCKS5 :1819
             |
     TCP CONNECT (H2) or UDP ASSOCIATE (H3)
             |
             v
Firefox VPN control plane + Fastly MASQUE session
             |
             v
Firefox SOCKS5 :1822
             |
             v
Android VpnService / zeptun (tunnel mode only)
```

The Firefox settings page persists `CoreSettings.firefoxLegProtocol`.
Supported choices are WireGuard (default), MASQUE, GOOL, GOOL Classic
and MIM. The Firefox H2/H3 selector is independent: H2 uses SOCKS5 TCP
CONNECT, while H3 carries QUIC datagrams through SOCKS5 UDP ASSOCIATE.

The ordered walk is:

1. **Stale-state cleanup and port checks** — stop the previous Firefox
   child, TUN/hold service and Aether job; require both 1819 and 1822 to
   be free.
2. **Platform and permission checks** — whole-device mode requests VPN
   permission and starts zeptun targeting 1822. The Android app UID is
   exempt from its own TUN, so the Aether/Firefox child processes can
   reach loopback. Proxy mode does not start a TUN.
3. **Aether outer carrier** — clear stale `AETHER_*` variables, then
   start the embedded core with the user's `firefoxLegProtocol` and
   normal Aether core settings. The core's SOCKS listener remains
   `127.0.0.1:1819`. Proxy mode starts the process-hold service.
4. **Carrier verification** — follow the Aether job until the 1819
   listener appears, then run the real end-to-end probe through 1819.
   A listener alone is not enough. A core exit or probe failure aborts
   the walk; Firefox is not allowed to fall back to direct internet.
5. **Firefox account and child** — load the same-account OAuth pair
   from the Keystore vault. Spawn the Go child with bare argv, empty
   environment, and `upstreamSocks=socks5://127.0.0.1:1819`. Its
   RemoteSettings/Guardian/token-refresh requests use the same carrier
   through the pinned Firefox uTLS control-plane transport. Its Fastly
   H2/H3 data-plane session uses the same SOCKS carrier too.
6. **Firefox listener and verification** — wait for the child's real
   `socksReady` event on 1822, then probe 1822 independently. Only this
   Firefox probe, with the Aether carrier still alive, can produce
   `Connected`.
7. **Steady state** — the normal session ticker probes Firefox traffic
   through 1822. Aether remains the outer carrier and is owned/cancelled
   by the same adapter job.

The separate account-login WebView (`--login`) and the pre-connect
location discovery role (`--discover`) run before a Firefox VPN
session exists; they retain their own process-scoped DNS path and are
not evidence that an active Firefox-over-WARP session is connected.

## 3. Shutdown and orphans

`stop()`: set `stopping` → close the child's stdin (the engine's
shutdown request: it refuses new work, drains live tunnels, closes the
listener and controller, emits `stopping`/`stopped`, exits 0) → await
exit bounded by `shutdownGrace` (3 s) → **kill** on expiry ("no orphan
survives a disconnect") → teardown streams → `stopped`. The adapter's
`_hardCleanup` stops the engine child FIRST, and a `disconnect()` during
the walk relies on the same path.

The adapter's `_hardCleanup` stops the Firefox child first, then stops the TUN/hold service, and finally cancels the Aether core job. Both listeners and both network layers are therefore torn down. Engine-side (`cmd/libfirefoxvpn`): shutdown watchers run for the WHOLE
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
* port already busy (`TestLifecyclePortBusy`); the outer Aether and inner Firefox listener are independently guarded,
* malformed config: public listener / bad version / no access token
  (`TestLifecycleBadConfig`, subtests),
* real Guardian + invalid token → honest failure, no token leak
  (`TestLifecycleRealGuardianRejectsFakeToken`),
* real Fastly h2 session with a fake pass → `socksReady`, engine-side
  exit probe HONESTLY fails (`TestLifecycleRealFastlySession`),
* stdin-EOF shutdown and bare-argv spawn on the Dart side
  (`test/firefox_engine_test.dart`, REAL host binary group).
