# M2 — Engine Wiring (هسته ↔ UI)

**Status:** DELIVERED (v4.18, 2026-11-03) — real-device test phase.
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
jniLibs/<abi>/libzeptun-jni.so  ← zeptun/libzeptun-jni.so (statically links
                                   the engine — libzeptun.so is NOT needed)
```

* Release APK: universal (arm64-v8a + armeabi-v7a + x86_64).
* Preview-debug APK: arm64-v8a ONLY (owner rule) — jniLibs are re-staged
  between the two builds.
* `extractNativeLibs=true` (Gradle `useLegacyPackaging`) — required so the
  lyrebird PT binary is a real executable file in `nativeLibraryDir`.
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
