# M2 — Engine Wiring (هسته ↔ UI)

**Status:** DELIVERED (v4.18) — device-test round 1 fixes (v4.19, 2026-11-04).
**Scope:** the Android vertical slice of the implementation prompt (§ M2):
«برش عمودی Android؛ Aether تعبیه‌شده + zeptun از طریق JNI + VpnService + ماشین
حالت + ابزار تشخیص». No frozen pin changed (N1/N8) — the cores build from the
same sources at the same SHAs; only the packaging and the app-side seam grew.

## Architecture (B+ — embedded native cores, per-platform service management)

```
Flutter UI (ConnectionStore — state machine, prompt §8)
   │  EngineAdapter (typed events; the UI never parses log lines)
   ▼
PlatformEngineAdapter (Dart)
   ├─ dart:ffi ────────────► libaether.so   (Aether core, IN-PROCESS,
   │                          aether_core_start / aether_job_poll /
   │                          aether_job_cancel / aether_job_free — ffi.rs
   │                          at the frozen pin; polling API, no callbacks)
   ├─ MethodChannel ───────► MainActivity   (aethone/engine: paths,
   │   "aethone/engine"       prepareVpn, startVpn, stopVpn, vpnStatus,
   │                          zeptunCounters)
   │        ▲
   │        │ onTunnelEvent {up|down|revoked|permission}
   │  AethoneVpnService (VpnService, specialUse FGS)
   │        └─ JNI ───────► libzeptun-jni.so (dev.zeptun.Zeptun.nativeStart:
   │                          adopts the TUN fd, installs the protect
   │                          callback → VpnService.protect per socket)
   └─ TunnelProbe (dart:io) ► 127.0.0.1:1819/1820/1821 (the core's SOCKS5
                              listeners) — SOCKS5 CONNECT + cloudflare trace
```

### Why embedded (not a subprocess) — prompt §3 decision, unchanged
iOS forbids child processes; app-data is `noexec` on modern Android; and the
Aether C API exists exactly for embedding. `aether_core_start` runs the core
on its own tokio runtime threads inside the app process; Dart polls the job
registry — no callbacks, no log-line parsing.

## The connect sequence (and where each state comes from)

| Step | What happens | State (prompt §8) |
|---|---|---|
| 0 | User taps connect; the STORE owns intent | `starting` |
| 1 | Tunnel mode: `VpnService.prepare()` — if consent needed, the system dialog opens | `waitingForPermissions` |
| 2 | Consent granted/already granted → adapter reports progress | `connecting` |
| 3 | `aether_core_start(args)` — the embedded core registers/loads the WARP identity, scans endpoints and binds its SOCKS5 listener (1819; 1820 for AETHER→TOR; 1821 for AETHER→PSIPHON) | still `connecting` |
| 4 | Listener wait (TCP connect probe, 120 s budget — first-run registration is legitimately slow) | still `connecting` |
| 5 | Tunnel mode: foreground VpnService → TUN (172.19.0.1/30, MTU 1500, DNS 172.19.0.2, `addDisallowedApplication(self)`) → `Zeptun.nativeStart(fd, toml)` | still `connecting` |
| 6 | **End-to-end probe (§6.6):** SOCKS5 CONNECT www.cloudflare.com:80 (ATYP=domain — the CORE resolves it) + `GET /cdn-cgi/trace` → `loc=` (exit country), RTT (ping) | `connected` + real stats |
| 7 | Steady state: 5 s ticker — job liveness + zeptun counters + fresh probe; 2 consecutive probe failures ⇒ health-probe failure | `reconnecting` on probe failure |

Disconnect: stop ticker → `stopVpn` (service tears down zeptun + TUN) →
`aether_job_cancel` + `aether_job_free` → `disconnected`.

## Protocol → core arguments (evidence-locked)

Built by `AetherArguments.build` from the store's user choices; every mapping
cites `docs/CLI_REFERENCE.md` (cli.rs at the frozen pin) and
`transport_modes.dart` (phase-1 report table 11):

| UI protocol tile | Aether args | SOCKS port | Exit kind |
|---|---|---|---|
| MASQUE | `--protocol masque` | 1819 | WARP |
| WIREGUARD | `--protocol wg` | 1819 | WARP |
| GOOL | `--protocol gool` | 1819 | WARP |
| GOOL CLASSIC | `--protocol gool --gool-classic` | 1819 | WARP |
| MIM | `--protocol mim` | 1819 | WARP |
| AETHER → TOR | `--tor` | **1820** | Tor |
| TOR → AETHER | `--tor-reverse` | 1819 | WARP |
| TOR ONLY | `--tor-only` | 1819 | Tor |
| AETHER → PSIPHON | `--psiphon` | **1821** | Psiphon |
| PSIPHON → AETHER | `--psiphon-reverse` | 1819 | WARP |
| PSIPHON ONLY | `--psiphon-only` | 1819 | Psiphon |

Common args: `--bind 127.0.0.1:1819`, `--config <filesDir>/aether/warp.toml`,
`--log-level info`, `--scan <profile>`. Psiphon modes add `--psiphon-bin
<nativeLibraryDir>/liblyrebird.so` + `--psiphon-dir <filesDir>/aether/psiphon`.

* **Flag wheel country** → `--exit-loc <CC>` for WARP-exit modes (exitloc.rs
  allow-list), `--psiphon-region <cc>` for Psiphon-exit modes, nothing for Tor
  exits (pinning a Tor exit would be a lie).
* **«سرعت اسکن» 1..5** → `--scan ironclad|verified|thorough|balanced|turbo`
  (1 = deepest, 5 = fastest — the sheet ships 5).
* **«حالت اتصال»** → proxy = local SOCKS only (no VpnService); تونل = the
  full device tunnel.
* **AUTO/SMART**: SMART is NOT IMPLEMENTED in the pinned core
  (SMART_AUTO_SPEC.md) — AUTO connects with the selected protocol tile.

## Packaging (CI, android-apk job v4.18)

```
jniLibs/<abi>/libaether.so      ← native-build artifact aether/libaether.so
jniLibs/<abi>/liblyrebird.so    ← aether/pt/lyrebird (renamed: the installer
                                   extracts lib*.so with the exec bit)
jniLibs/<abi>/libpsiphon.so     ← aether/pt/psiphon-tunnel-core (v4.19 FIX:
                                   v4.18 shipped lyrebird in this slot —
                                   psiphon.rs BINARY_NAMES wants the
                                   psiphon-tunnel-core program, so psiphon
                                   modes could never come up on a device)
jniLibs/<abi>/libzeptun-jni.so  ← zeptun/libzeptun-jni.so (statically links
                                   the engine — libzeptun.so is NOT needed)
```

* Release APK: universal (arm64-v8a + armeabi-v7a + x86_64).
* Preview-debug APK: arm64-v8a ONLY (owner rule) — jniLibs are re-staged
  between the two builds.
* `extractNativeLibs=true` (Gradle `useLegacyPackaging`) — required so the
  exec'd Go binaries (lyrebird, psiphon-tunnel-core) are real executable
  files in `nativeLibraryDir`.
* build_native.sh v5 exports `libaether.so` (same cargo build, cdylib
  crate-type; NEEDED-guarded like the binary: never libc++_shared.so).

## Route-loop prevention (prompt §4 / T12)

1. `VpnService.Builder.addDisallowedApplication(own package)` — the app's own
   uid (Aether + zeptun + UI) never enters the tunnel.
2. zeptun's protect callback (installed by its own JNI bridge) calls
   `VpnService.protect(int)` for every upstream socket — second guard.
3. zeptun upstream is 127.0.0.1 (loopback never routes through the TUN).

## Honest gaps (documented, deliberate)

* **IPv6**: the TUN is IPv4-only this phase (`172.19.0.1/30`, `0.0.0.0/0`);
  on IPv6-capable networks v6 traffic does not enter the tunnel. Device
  testing decides whether zeptun's IPv6 (fake range fc00::/18) is enabled
  next round.
* **Kill switch / Always-on**: the OS-level lockdown integration (annex §kill
  switch) is not wired; the `killSwitch` preference is stored and shown only.
* **SMART auto** is not implemented in the pinned core (SPEC REQUIRED).
* **Aether log lines** are not forwarded as events yet (in-process the core
  logs to stderr → visible via `adb logcat`); `EngineLogLine` lands with the
  diagnostics step.
* **Byte counters in proxy mode** stay 0 (no counter source; ping/exit are
  real from the probe). Tunnel mode reads the real zeptun counters.
* **Engine restart while connected** (process death): the FGS is
  START_NOT_STICKY on purpose — a sticky restart would tunnel into a dead
  core (silent black hole). The tunnel dies with the process; the app resyncs
  (`vpnStatus` + probe) on next launch and the user reconnects.

## Device-test round 1 fixes (v4.19 — the owner's 10 reports, 2026-11-04)

1. **#6 psiphon packaging FIXED**: `--psiphon-bin` now points at
   `libpsiphon.so` (= psiphon-tunnel-core, packaged per-ABI). v4.18 shipped
   `liblyrebird.so` in that slot — lyrebird is Tor's obfs4 PT, NOT the
   psiphon client, so psiphon modes could never run. Tor's arg surface was
   verified correct (`--tor`/`--tor-reverse`/`--tor-only`).
2. **#3 CANCEL during connecting**: the store's `disconnect()` while
   starting/waitingForPermissions/connecting is a CANCELLATION (the
   single-flight guard no longer blocks it); the platform walk checkpoints
   `_disconnecting` at every stage and goes silent (the cancel owns the
   terminal state); the preview adapter is cancellable too; every connect
   surface (hero logo, look-2 button, FAB) cancels on tap during the walk.
   A stale in-flight `connected` emission from the aborted walk is dropped
   (cancel-generation guard) instead of landing as a fake
   `failed(illegalTransition)`.
3. **#2 the app FOLLOWS the core**: while waiting for the listener, the
   adapter polls the core's job every second; a core that exits fails the
   walk immediately with `coreExited` + the CORE's own error text — no more
   generic 120 s `engineStartTimeout` when the core is already dead.
4. **#7 proxy survives the app being swiped away**: `CoreHoldService`
   (specialUse FGS, subtype `core-holder`) pins the process for the proxy
   session (`startCoreHold`/`stopCoreHold`/`coreHoldStatus` on the
   channel). Resync on app re-entry now recognizes BOTH holders — the VPN
   service (tunnel) and the core hold (proxy) — and walks
   starting → connecting → connected with a live probe, so the app shows
   the TRUE state instead of «در حال اتصال مجدد».
5. **#1 tunnel crash hardening**: every Java-level throwable in the tunnel
   leg (`startTunnel`, `Zeptun.nativeStop`, teardown) is converted into the
   honest `down` event (`tunnelStartFailed`) — the app survives to show
   the failure. Uncaught Java exceptions leave a breadcrumb at
   `filesDir/aethone-crash.txt` for the next device test. NOTE: a NATIVE
   crash (SIGSEGV/SIGABRT inside an embedded core) remains uncatchable by
   design — `adb logcat -b crash` from a repro is still the native truth.
6. **#8 settings persistence**: `shared_preferences` + `SettingsPersistence`
   — restore runs BEFORE the first frame; every change saves (debounced
   200 ms); invalid/stale values fall back to the defaults safely.
7. **#4 default protocol = WireGuard** (owner decree until the settings
   redesign ships; the AUTO tile still selects the core's own MASQUE).
8. **#5 wheel policy** (`LocationWheelPolicy`): selectable ONLY where the
   core honors the pin — psiphonOnly/psiphonChain (`--psiphon-region`) and
   the reverse modes (`--exit-loc`, WARP exit); tor-EXIT modes render a
   locked display (the pinned core has NO Tor exit-country control —
   `AETHER_TOR_COUNTRY` is a BridgeDB request country, not an exit pin).
   The psiphon-EXIT modes filter the wheel to the standing Psiphon egress
   regions (the live set is announced by the network itself as
   `AvailableEgressRegions` at connect time); a filter change re-anchors
   the wheel and commits the pick.
9. **#10 protocol page chrome**: the BACK and INFO (Telegram) tiles
   exchanged slots (RTL row: back = visual RIGHT, info = visual LEFT).
10. **#9 location display** (no code change — it is already real): the
    connected flag is the cloudflare-trace `loc=` measured THROUGH the
    tunnel; WARP egress for Iranian clients is genuinely inside IR most of
    the time, so an IR flag after a WARP-family connect is the honest
    reading. Verify with a psiphon/tor protocol (their exits are
    e.g. NL/DE/SE) — the roulette lands on the reported exit.

## Device-test round 2 fixes (v4.20 — owner reports, 2026-11-04)

The owner's round-2 reports, root-caused against the pinned sources:

1. **«سایفون روی وارپ… فقط پورت ۱۸۱۹ و وارپ کار میکرد» / «منظورم این بود اول
   وایرگارد وصل شه و بعد سایفون نه اینکه کلا وایرگارد به جاش وصل شه» —
   the selection was ONE flat knob, so the family cards and the protocol
   tiles REPLACED each other; a chain mode ran the core's default MASQUE leg
   and the leg tile could never ride along.**
   * FIX: the selection is now TWO independent knobs — `selectedProtocol`
     (the WARP leg, AUTO..MIM, cold default WireGuard) + `selectedChain`
     (the overlay: torChain…psiphonOnly, or null = plain). The engine
     combines them verbatim: `--protocol wg --psiphon` = WireGuard WARP
     first, Psiphon over it (lib.rs L222-227 — run_chain dials the held
     `--bind` listener). Reverse modes map the UDP-to-WARP legs
     (wireguard/goolClassic) to masque — the core REFUSES them on reverse
     (lib.rs L203-218/L229-244) and forces the H2 carrier regardless. Only
     modes pass `--protocol masque` so `select_protocol()`'s interactive
     menu can never hang a headless job.
   * Persistence round-trips BOTH knobs; a v4.19 install's persisted family
     member migrates into the overlay (the leg keeps its default).

2. **«تور وصل نمیشه، سایفون وصل نمیشه» — TWO device-blockers:**
   * **The walk's single 20 s end-to-end probe.** Aether binds its SOCKS
     listeners at START (lib.rs L128) — before the WARP tunnel or the inner
     protocol exists; a SOCKS greeting on an unserved listener simply HANGS
     (socks.rs L1931 test). The single probe therefore failed every mode
     whose data path legitimately bootstraps slower than 20 s (Psiphon
     ready timeout 180 s — psiphon.rs L15; Tor 75 s direct + up to 360 s per
     bridge — tor.rs L239-241). FIX: the walk now RETRIES the probe within a
     per-mode budget (`readyBudget`: psiphon 210 s, tor 360 s, plain 120 s)
     while still FOLLOWING the core — a job that dies fails the walk
     immediately with the core's own error.
   * **Tor had NO pluggable transport on Android.** bridges.rs
     `search_dirs()` scans desktop paths only (/usr/lib/tor/…, $HOME/…) and
     the packaged PT is renamed `liblyrebird.so` — the auto-bridge plan
     found no transport, so Tor could never bootstrap where direct
     connections are blocked. FIX: the tor family args now carry
     `--tor-pt <proto>=<nativeLibraryDir>/liblyrebird.so` for every protocol
     aether's own PT_BINARIES table attributes to lyrebird (obfs4, snowflake,
     webtunnel, meek_lite, obfs3, scramblesuit — bridges.rs L32-52) plus an
     explicit writable `--tor-dir`.

3. **«اپ هنوز هم در حالت تونل مشکل داره و وصل نمیشه» — the tunnel leg came
   up AFTER the core, i.e. after an up-to-120 s listener wait during which
   the user could background the app; a foreground-service start is only
   legal while the app is visible (ForegroundServiceStartNotAllowedException
   on 12+).** FIX: the walk starts the VpnService FIRST (right after the
   consent), then the core — zeptun tolerates a not-yet-serving SOCKS target
   exactly like the core tolerates early clients. The Kotlin service also
   restarts zeptun when the SOCKS target CHANGES between connects (the old
   service kept relaying into a dead port), and the platform's own down
   reason (establish-failed / start-threw:<Ex>) is carried into the failed
   event message.

4. **Failure visibility (new):** the failed state now NAMES its stage — the
   engine's own error code rides under the status pill («کد خطا: …»), and
   tapping it opens a details sheet (code + full message + copy) so the next
   device round can be diagnosed without adb. The protocol descriptions
   popup gained each mode's LOCAL SOCKS PORT (1819/1820/1821 — the owner
   tested 1820 while the psiphon chain serves 1821).

Note (owner port question): the ports are per-MODE — main WARP bind 1819,
`--tor-bind` 1820, `--psiphon-bind` 1821 (cli.rs L23/L239/L282). The
psiphon-over-warp exit lives on **1821**, not 1820.

## Device-test checklist (owner)

1. Install the **release** APK (`aethone-ui-r<run>-release.apk`).
2. Protocol sheet → pick a protocol; حالت اتصال → تونل (or پروکسی for a
   local-SOCKS-only test).
3. Connect → grant the VPN consent → expect `connecting` (scanning halo)
   → `connected` with a real ping/flag. First run can take up to ~2 minutes
   (WARP registration + scan).
4. Verify: another app loads a site; the exit flag matches the picked
   country (WARP modes); `adb logcat | grep -E "AethoneVpn|AethoneMain"`
   shows zeptun up / protect; disconnect revokes cleanly.
5. Psiphon/Tor tiles: expect longer connect times (bridge/ready timeouts are
   the core's own).
