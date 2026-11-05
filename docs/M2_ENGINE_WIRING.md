# M2 — Engine Wiring (هسته ↔ UI)

**Status:** DELIVERED (v4.18) — device-test rounds 1–3 fixes (v4.19–v4.21) +
the v4.26 connection-logic round (generations, durable job id, bounded logs).
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

## Device-test round 4 fixes (v4.26 — the connection-logic round)

The owner's reports: «در حالت تونل وقتی وسط حالت در حال اتصال روی دکمه اتصال
کلیک میکنی تا اتصال قطع بشه فقط اتصال هسته اول قطع میشه و همچنان تونل برقراره»
+ «توی حالت متصل هم وقتی اتصال رو قطع میکنی همچنان تونل فعاله و باید اپ رو کلا
بندی تا اتصال تونل قطع بشه» + «حدود ۸۰ مگ داده تو ۱ ساعت استفاده به محل ذخیره
اضافه شده». Root causes found (all reproduced by code-trace + regression tests):

1. **The lost cancel (the «tunnel stays up» headline).** The walk's cancel
   detection was a boolean `_disconnecting` that the cancel's own `disconnect()`
   RESET when it finished — and `connect()` wiped it again. A cancel landing
   while the walk was parked in its own startup cleanup (or the permission
   round-trip) found the flag already reset when the walk resumed: it went on to
   `startVpn` + `coreStart` and CONNECTED ANYWAY, while the store (already
   `disconnected`) dropped the walk's emissions — a live tunnel with a
   «disconnected» UI that only a force-close could end. **Fix: monotonic walk
   GENERATIONS** — every user action bumps the counter; the walk captures it at
   start and is stale at every checkpoint, permanently. The stretch from the
   staleness check to `coreStart` is deliberately await-free, so a cancel can
   never land between them.
2. **Zombie walks.** The same reset bug let a cancelled walk keep polling for up
   to its full budget (120 s listener / 360 s tor probe): it "succeeded" against
   the NEXT session's listener (a premature/fake Connected), emitted late
   `failed(engineStartTimeout)` minutes after a clean cancel, and its
   failure-path `_hardCleanup` could STOP the next session's service and cancel
   its job. Also: `connect()`'s `if (_connecting) return` silently swallowed
   the reconnect-after-cancel while the store had already entered `starting`
   (the «hangs on در حال اتصال forever» bug). Both gone with the generations;
   `connect()` no longer early-returns.
3. **`starting → disconnecting` was illegal** in the transition table — a tap
   during the tunnel bring-up failed the machine into `failed(illegalTransition)`
   and wedged the UI there (the adapter's terminal `disconnected` then hit
   `failed → disconnected`, also illegal). The table now allows every walk state
   → `disconnecting`, exactly as the v4.19 cancel design documented.
4. **The orphaned core after reopening the app (the «force-close» bug).** The
   Rust job registry is process-scoped but the Dart isolate is not: after the
   activity/engine was recreated (swipe-away + reopen), the fresh adapter had NO
   job id — its disconnect cancelled NOTHING. The orphaned core kept the SOCKS
   port bound and the next connect died on «address already in use» until the
   app was force-closed. **Fix: a PROCESS-DURABLE job id** — the Kotlin
   companion remembers it (`setCoreJob`/`getCoreJob`/`clearCoreJob`), the
   resync ADOPTS it once a live listener proves the core alive, and the resumed
   session's disconnect actually cancels + frees the job (and its `_tick` now
   watches the core too).
5. **The resume window stopped the WRONG holder.** `_resumeSession` set
   `_activeMode` only AFTER its (up to 20 s) end-to-end probe — a disconnect
   during the probe ran `_hardCleanup` with the default `proxy` and called
   `stopCoreHold` instead of `stopVpn`: the VpnService — and with it the TUN —
   survived. The holder identity is now set BEFORE the probe, the resume is
   generation-guarded (a user action supersedes it), and a FAILED resume probe
   tears the zombie session down instead of leaving it for the next connect to
   fight.
6. **The late `down: destroy` after a clean disconnect** (the service's
   asynchronous onDestroy) flipped the UI to `failed(tunnelDown)` a moment
   after «قطع شد». The adapter now tracks the session it tore down itself and
   drops that expected event; a genuinely external down/revoked still surfaces.
7. **Platform hardening (Kotlin):** `stopVpn` is no longer a bare
   `stopService()` — `AethoneVpnService.requestStop` bumps a stop GENERATION,
   tells the live instance to tear zeptun + the TUN down synchronously, and
   then stops the service. A straggler `onStartCommand` (a start delivery that
   lands AFTER the stop was processed) now REFUSES to establish the TUN
   (`stale-start`) — the platform half of the lost-cancel bug.
8. **The ~80 MB/hour storage growth was the core-log capture.** The process
   stderr (aether `info` + zeptun + the chatty lyrebird/psiphon children) was
   dup2'd into an append-mode file capped only at ACTIVITY start — a tunnel
   session that keeps the process alive for hours grew it unbounded (and every
   activity recreation leaked another fd). **Fix: a pipe + reader thread with
   rotation** — `core-log.txt` rotates at 1 MiB keeping one previous rotation
   (≈2 MiB hard ceiling), installed exactly once per process; `readCoreLog`
   tails across both files; `clearCoreLog` is consumed by the reader (single
   writer, no sparse offsets).

Regression tests (test/m2_engine_test.dart, `v4.26` group): the lost-cancel
window, the zombie walk (exactly ONE Connected; no late failure; no stopVpn
against the new session), the durable-job resume (job 42 cancelled + freed +
service stopped), the late `down: destroy` filter, and the resume-window holder
identity — plus the transition-table cancel legality in
test/connection_state_test.dart.

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

## Owner device-test round 5 — v4.28 «لوکیشن‌های واقعی و زنجیرهٔ خطا»

Three reports, three fixes (all landed in v4.28):

1. **«لوکیشن های سایفون و تور باید واقعی باشن نه فیک» — the REAL
   egress-location sets.** The wheel no longer invents lists:
   * **Psiphon** — the network announces its current egress set at connect
     time (`AvailableEgressRegions`); the pinned core renders it into the
     captured core log as `[*] psiphon can leave from: AT BE …`
     (psiphon.rs `note()`). The adapter harvests that line after every
     psiphon-family connect (and even after a failed one — the notice fires
     before establishment) and the store swaps the seed list for the
     network's own truth (`EngineEgressRegions` event → `livePsiphonRegions`,
     disk-cached across runs). The 40-country standing list remains the
     offline SEED only (Psiphon publishes no static list — verified against
     the tunnel-core sources).
   * **Tor** — the honest set is the countries with RUNNING exit relays:
     the Tor network's own metrics API (Onionoo) answers exactly that. The
     verified query (`details?type=relay&flag=exit&fields=country&running=true`,
     checked 2026-11-05: 2686 exit relays / 51 countries) is fetched
     fire-and-forget at app start (24 h TTL, disk-cached, silent failure
     keeps the cache/snapshot). The 51-country snapshot from that query is
     the offline seed; the tor-exit wheel now shows `[خودکار, …real
     countries]` — the FULL flag manifest is gone from the tor-exit modes.
     (The reverse modes still exit through WARP → full manifest + auto.)
   * **AUTO** — the whole pick chain (wheel → store → persistence →
     `_resolveCountryPick` → arg list) was re-audited end-to-end: `auto`
     correctly maps to NO pin flag (`--psiphon-region`/`--exit-loc` simply
     not passed; the env inventory is cleaned before every start), so the
     core's own egress choice runs. If auto failed on-device, the failure
     is in the engine/tunnel layer — which round 5's other fixes make
     visible instead of anonymous.

2. **«tunnel start failed start-threw:NoClassDefFoundError» — the anonymous
   retry face.** `NoClassDefFoundError` is what a POISONED class init looks
   like on the SECOND touch: the first `System.loadLibrary("zeptun-jni")`
   failure (an UnsatisfiedLinkError naming the real missing piece) was
   wrapped as `ExceptionInInitializerError`, and every retry after that
   degrades to a bare `NoClassDefFoundError` that names NOTHING. The APK
   itself was verified structurally sound (libzeptun-jni.so present for all
   ABIs, `dev/zeptun/Zeptun` in the dex, unobfuscated, 16 KB-aligned,
   DT_NEEDED = system libs only) — but the IN-APP load path was never
   exercised by CI (every prior gate runs the engines from /data/local/tmp).
   **Fixes:**
   * a **zeptun PRE-FLIGHT probe** (`Zeptun.nativeVersion()` before any TUN
     exists) with its own `zeptun-load-failed:` reason carrying the FULL
     throwable chain (`Class: message caused by Root: message`) plus the
     on-disk `nativeLibraryDir` listing in logcat — the next device report
     names the real missing piece;
   * `start-threw:` reasons now carry the full chain too (was: bare
     simpleName);
   * a **new CI leg `apk-smoke`**: installs the release APK on the pinned
     16 KB emulator, grants the VPN consent via `appops ACTIVATE_VPN`,
     cold-starts `AethoneVpnService` via `am start-foreground-service`, and
     asserts `zeptun up on socks` in logcat (fail-closed on
     `zeptun-load-failed` / `start-threw:` / `FATAL EXCEPTION`, with
     `establish-failed` reported as gate-infra, not engine). The blind spot
     is closed at the pipeline level — 11 legs total now.

3. **hevtun note (owner question: «اگه هسته زپتون استاندارد نیست با hevtun
   جایگزینش کنیم؟»)** — researched: hevtun = `heiher/hev-socks5-tunnel`
   (C, 2.1k stars, MIT, active) — the de-facto standard Android tun2socks
   (used by the v2rayNG family). It fills EXACTLY the role zeptun plays
   here (TUN ↔ SOCKS5 relay + fake-IP DNS + VpnService protect). Verdict:
   keep zeptun for now — the round-5 failure class is the load/diagnostic
   path, now gated in CI, not an engine defect — and record hev-socks5-
   tunnel as the designated drop-in replacement if device tests keep
   implicating the zeptun layer (its C ABI maps 1:1 onto the existing JNI
   seam).

Regression tests: test/egress_locations_test.dart (the psiphon-line parse
in five shapes incl. the word-boundary garbage case, the Onionoo document
parse incl. malformed documents, the sanitizer) + the v4.28 updates in
test/v419_device_test.dart (the tor-exit REAL set, live-set overrides,
autoEntry now reverse-only) and the store live-set application paths.

## Gate round — CI v4.29 «the cold start may actually start» (runs #51-#53)

Two independent fixes, both proven by the gate itself:

1. **adb elevation (eae13d6).** Runs #51/#52 died at the gate's FIRST adb
   call — «Error: Requires permission not exported from uid 10213», exit
   255 before the 120 s assert loop ever ran. AethoneVpnService is
   exported=false + BIND_VPN_SERVICE-guarded (correct for production), so
   the shell uid may not cold-start it. Fix, harness-side only: `adb
   root` on the pinned userdebug google_apis image + fail-closed uid==0
   verification. The app's security posture is untouched.

2. **the prepare() adoption (this commit).** Run #53 reached the REAL
   packaged path — the zeptun pre-flight loaded `libzeptun-jni` inside
   the release APK (NO `NoClassDefFoundError`, NO `zeptun-load-failed`:
   the owner's round-5 class is closed at the packaging level) — and then
   died honestly on `Builder.establish() == null` DESPITE `ACTIVATE_VPN:
   allow`. Root cause in AOSP Vpn.java: establish()'s FIRST gate is
   `Binder.getCallingUid() != mOwnerUID` — system-side in-memory state
   that only a `prepare()`/consent call adopts (→ prepareInternal); the
   appop is only the SECOND gate. The Dart walk always calls prepareVpn
   before startVpn (why real devices never see this), but a cold start
   that skips the walk — the gate, and any always-on/external start after
   a system_server boot — hits the un-adopted state. Fix: startTunnel()
   now calls `VpnService.prepare(this)` before establish(); with consent
   granted it is a silent system-side adoption and returns null (no
   dialog); when consent is genuinely missing it returns the dialog
   intent and the service refuses to establish honestly.

## Owner device-test round 6 — v4.30 «همگام‌سازی لوکیشن» (the sync round)

Owner report: «لوکیشن رو آمریکا انتخاب میکنی … بعد از اتصال لوکیشن میره روی
پرچم صربستان و به صربستان وصل میشه … در پروتکل‌های تور … بعد از اتصال
لوکیشن رو آیکونی که برای انتخاب خودکار لوکیشن در نظر گرفتیم نشون میده …
قسمت انتخاب لوکیشن در صفحه اصلی و قسمت انتخاب لوکیشن در تنظیمات تور و
سایفون باهم همگام نیستن» — and the decree: the two pickers must be ONE,
functionally AND visually (same flags, same corner rounding).

Root cause 1 — THE DEAD TAP COMMIT. The wheel's tap path delegated the
store write to the settle: `if (!_programmatic) _select(...)`. But the
ScrollEndNotification is dispatched synchronously inside the scroll
activity's end — while `_programmatic` is still true (the animateToPage
continuation that clears it runs a microtask later) — so a TAP never
committed. The wheel DISPLAYED the tapped flag while the store kept the
previous pick: a psiphon tap on آمریکا pinned the settings-era pick
(صربستان), and every later tap silently failed too («هرچقدر تغیر بدی
لوکیشن رو تغیر نمیده»). Fix: the tap handler commits
`_select(_codeAt(page))` directly — deterministic, ordering-free; the
320 ms spin is pure visual.

Root cause 2 — THE INDEX-0 FALLBACK. When the engine-reported exit was
not in the wheel's offered set (a Tor exit relay in a country outside
the snapshot when the live Onionoo refresh could not reach the network),
`_indexOf` fell back to defaultCode ('ir'), itself absent from the
family lists, clamped to index 0 — the AUTO globe. Fix: the connected
DISPLAY UNION — the reported exit joins `_codes` (sorted in) so the
roulette lands on the real flag; it never enters the store, and the new
DISCONNECT EDGE re-derives `_codes` from the offered set, re-anchors on
the remembered pick and re-centers unconditionally (what the wheel shows
while disconnected is ALWAYS what the next connect pins).

Root cause 3 — THE SETTINGS STRIPS. The psiphon strip offered the
standing SEED (not the live AvailableEgressRegions set) and the tor
strip offered the FULL flag manifest (countries Tor cannot exit from —
'ir' included). Both now render the exact lists the home wheel offers:
`[auto, ...livePsiphonRegions ?? seed]` and
`[auto, ...liveTorExitCountries ?? snapshot]`, with the home wheel's
flag look (the same 24 %-of-size ClipRRect and cover crop; the
selection ring follows the flag's rounding).

Regressions: home_screen_test (tap-commit, out-of-set exit shows its
real flag not AUTO, disconnect-edge re-anchor) + settings_subpages_test
(the strips mirror the LIVE sets — asserted on the widget's own codes,
no lazy-build vacuity).
