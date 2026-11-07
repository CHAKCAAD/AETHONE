# AETHONE — Linux Runtime & Tunnel Fix Report (v4.37/v4.38)

**Round:** v4.37 (runtime round) + v4.38 (psiphon data-path fix) · **Branch:** `ci-bootstrap/v4.4`
**Fix commit:** this round's code commit (see §13) · **Report commit:** the commit carrying this file
**Scope:** the owner's six-part decree «اصلاحات اساسی نسخه Linux» — Zeptun TUN privileges, the
Aether core's interactive-mode stall, the local socket resets, the WARP identity path, the
connection state machine, and the appended psiphon tunnel data-path defect («در همه نسخه‌ها»).
Android/Windows: regression-frozen, with ONE deliberate, psiphon-scoped exception each (§11).

---

## 1. The Zeptun error — exact cause

**Symptom (owner's report):** as a normal user, tunnel mode fails with

```
tunnelStartFailed: zeptun-start-failed:rc=-3 (permission denied)
```

running the whole app under sudo made the error disappear but moved the failure to an Aether
stdin stall (§2) and the WARP identity under `/root` (§5).

**Root cause (code-level, not guessed):** the desktop tunnel embeds zeptun in-process
(`libzeptun.so`, `create_from_toml` + `start`). On Linux, zeptun's bring-up performs, in order
(`native/zeptun` @ pin `08a1ab05`):

1. `open("/dev/net/tun")` + `ioctl(TUNSETIFF, IFF_TUN|IFF_NO_PI)` — needs `CAP_NET_ADMIN`;
2. netlink `RTM_NEWLINK` (MTU/txqueuelen/UP), `RTM_NEWADDR` (172.19.0.1/30),
   `RTM_NEWROUTE` (default → table 2022), `RTM_NEWRULE` ×4 (priorities 9000/9004/9005/9009,
   uid-exclusion + fwmark invert) — every one of them needs `CAP_NET_ADMIN`;
3. `resolvectl dns/domain/default-route` on systemd-resolved systems — needs root.

A normal desktop user has none of those privileges, so step 1 fails with `EPERM` →
`permission_denied` (`rc=-3`, `zeptun/src/errors.zig`), which the FFI surfaces verbatim. The
old workaround — sudo the WHOLE app — was both wrong by decree and the source of two more
defects (§2, §5).

## 2. Aether's interactive mode — exact cause

**Symptom:** with sudo, the zeptun error vanished but the VPN still never connected; the
core log showed Aether v2.4.0 sitting at

```
IP version to scan:
  [1] IPv4 (default) ...
MASQUE transport:
  [1] HTTP/3 (QUIC) (default ...) ...
Reconnect to it now without rescanning? [Y/n]:
```

and the Flutter side logged `SocketException: Connection reset by peer (OS Error 104),
address = 127.0.0.1`.

**Root cause:** Aether's prompts are guarded by environment variables, not flags
(`native/aether/aether/src/lib.rs` @ the frozen pin):

* `select_ip_version()` — prompts **iff `AETHER_IP` is unset**;
* `select_masque_transport()` — prompts **iff `AETHER_MASQUE_HTTP2` (and `AETHER_PEER`) unset**;
* `want_quick_reconnect()` — prompts **iff `AETHER_QUICK_RECONNECT` unset** (from the second
  connect on, once a last-connection gateway is cached);
* `select_scan_mode()` / `select_scan_mode_str()` — prompt iff `AETHER_SCAN` unset;
* `select_protocol()` + the chain-direction/carrier menus — iff `AETHER_PROTOCOL` unset.

Every guard funnels into `prompt_line()`:

```rust
if !std::io::stdin().is_terminal() { return None; }   // non-TTY → default answer
```

so a daemon-style launch never blocks. But the owner ran the app **from a terminal** (and
under sudo), where stdin IS a TTY — and on desktop the Aether core runs **in-process**
(`aether_core_start`, ffi.rs → `run_with`), sharing the app's stdin. The old argument
builder left `AETHER_IP` unset for the v4 default («pass nothing») and `AETHER_MASQUE_HTTP2`
unset on the HTTP/3 side (`--h2` only when chosen) — exactly the two prompts the owner's log
shows — so the core printed the question and **blocked on `read_line` before its listeners
ever served** (`Listeners::bind` at lib.rs L128 binds 1819 up-front; `listeners.serve()`
runs only inside `run_masque`/`run_wireguard`, after the prompts).

**The fix (v4.37, `lib/connection/platform_engine_adapter.dart` — evidence-locked, unit-tested):**
every prompt guard now has its explicit flag, for every mode:

| prompt | flag | value source |
| --- | --- | --- |
| IP version to scan | `-4` / `-6` / `--dual` (always one of them) | `CoreSettings.ipVersion` (UI «نسخه IP») |
| MASQUE transport | `--h2` / `--h3` (always one of them) | `CoreSettings.h2Transport` (UI «ترنسپورت») |
| quick reconnect | `--quick-reconnect` (always) | the pinned non-TTY default (verify-then-reuse the cached gateway) |
| scan mode | `--scan <turbo..ironclad>` (always) | the «سرعت اسکن» wheel (1..5) |
| protocol + chain menus | `--protocol …` + `--psiphon/--tor/…` (always) | the selected tile |

The values are the SAME ones the non-TTY defaults produced (`prompt_line → None` → default
arm), so behavior is unchanged on every platform — only the hidden stdin dependency is gone.
No `echo`-into-stdin, no pty faking: the core never reaches a prompt. A missing required
setting still fails honestly at argument-build time (the builder is pure and unit-tested;
`test/m2_engine_test.dart` pins all of the above, including the v4.38 additions).

**The socket resets (§2.5 of the decree):** with the core stalled at a prompt, 1819 was
bound-but-never-serving; the walk's probes and the chained children (psiphon's
`wait_for_proxy`) connected into the backlog and died — as resets when the failed job was
cancelled, as timeouts until then. The prompt fix removes the stall itself. On top, the
walk now classifies every probe error (`classifyProbeError`): a reset on 127.0.0.1 names
itself («the core exited or closed its listener just as the probe arrived — the core's own
exit reason, when it has one, is quoted separately»), a refusal names «not accepting yet»,
and the engineStartTimeout / data-path failure screens quote the LAST probe error instead
of an anonymous budget expiry.

## 3. The Linux privilege fix — Polkit helper architecture (final)

**Design (owner's requirements 1.1–1.9):** the GUI stays a normal-user process; ONLY the
operations that genuinely need `CAP_NET_ADMIN` run elevated, authorized per-connection
through Polkit. No chmod 777, no permanent sudo, no whole-app root.

```
 Flutter GUI (uid=z)                         aethone-tunnel-helper (uid 0, via pkexec)
 ─────────────────────────────              ────────────────────────────────────────────
 connect walk (Dart)                        one-client daemon over a Unix socket in
   │ startVpn{port,session,tcpOnly,          XDG_RUNTIME_DIR/aethone/tunnel-helper.sock
   │           socksStrict}                   • SO_PEERCRED: the client uid must equal
   ▼                                            the socket-dir owner (non-root) — no
 engine_channel_linux.cc                       other local user can talk to it
   TunnelPrivilegeViaHelper() = !root        • closed command set: up / down / probe / bye
   └─ StartTunnelAsync (worker thread)       • up: TUNSETIFF aethone0 (IFF_TUN|IFF_NO_PI),
       1. EnsureHelperInstalled                MTU 1500 + txqueuelen 4096 + 172.19.0.1/30,
          pkexec /usr/bin/env <bundle>/          rp_filter 1→2, default→table 2022, rules
          aethone-tunnel-helper                 9000/9004/9005/9009 (uid-excluded, fwmark
          --self-install                        0x2022 inverted), resolvectl delegation —
          → /usr/libexec/aethone-tunnel-helper  a byte-faithful mirror of zeptun's own
            (0755 root:root) +                   route/linux.zig @ 08a1ab05 — then
            /usr/share/polkit-1/actions/         FAIL-CLOSED read-back verification
            com.chakcaad.aethone.tunnel-         (interface + all 4 rules + default route
            helper.policy (0644 root:root)        dumped back) before answering OK;
          ONE admin password, ever               the TUN fd is handed over with SCM_RIGHTS
          (auth_admin_keep keeps the              and the helper CLOSES ITS COPY — the
          per-connect prompts silent              unprivileged app owns the data plane
          inside the keep window)                 (Android's VpnService model)
       2. pkexec /usr/libexec/… --serve      • down / EOF (app exit or crash): rules →
          (one Polkit auth per connect)          route → resolved → interface removed;
       3. "up" ───────────────────────────►     every up first clears 9000..9009 for both
          ◄── OK + SCM_RIGHTS(tun fd)            families — self-healing after a crashed
       4. zeptun .fd mode on the received      pair (stale rules are at worst fall-through
          fd (configure=false, no route          to the main table, benign)
          section — the helper did the        • probe (requirement D): as uid 0 the helper
          privileged half)                       is NOT excluded by the uid rule, so it
       5. verifyTunnelPath(): "probe" ─────►    makes a REAL request through the tunnel
          ◄── OK <ms> HTTP answer …              (resolve www.cloudflare.com via the
       6. walk reports Connected ONLY          tunnel's delegated DNS → TUN → zeptun →
          after 5 passes                        SOCKS5 → the core → internet) and reports
                                              first-byte RTT + the answer's first bytes
```

**Why an installer step at all:** pkexec refuses to execute binaries from user-writable
directories (the app bundle). The helper therefore installs ITSELF (binary + embedded
Polkit action, root-owned, verified fail-closed) via ONE
`pkexec /usr/bin/env <bundle-helper> --self-install` — `/usr/bin/env` is a root-owned
system binary, so pkexec's path rule does not apply to it, and the admin password
authorizes exactly this bootstrap. Uninstall = delete those two files.

**Security posture (verified locally, §12):**
* `--serve` refuses to run unprivileged (`rc=2`, log line) — only pkexec can launch it;
* the socket lives in the user's `XDG_RUNTIME_DIR` (0700, user-owned); a root-owned socket
  dir is refused;
* the client is authenticated with kernel-set `SO_PEERCRED` and must be the socket-dir
  owner (non-root);
* exactly one client per serve (the listener closes after the first accept);
* the command set is closed (`up|down|probe|bye` — anything else is rejected and logged);
* the TUN fd leaves the privileged process immediately (SCM_RIGHTS) — the helper holds no
  data-plane socket;
* cancel semantics: the user dismissing the Polkit dialog (pkexec exit 126) surfaces as
  «the administrator permission was declined (polkit)…»; a disconnect during the dialog
  cancels the wait (stop-generation check) instead of hanging.

**Proxy mode:** untouched by all of this — the helper is only ever contacted from the
tunnel bring-up; proxy mode never calls `startVpn`/the helper and keeps running fully
unprivileged (the `TunnelPrivilegeViaHelper()` branch lives only in the `startVpn` handler).

## 4. Aether management changes (lifecycle, single-instance, readiness)

* **One core per session, no stragglers:** the walk's generation/session gates (v4.21/v4.26)
  + the platform straggler gates (`StopTunnel`'s stop-generation bump; the Kotlin twin in
  `AethoneVpnService.noteStart/requestStop`; the Linux async bring-up's `stale-start` checks
  before AND after the Polkit dialog) — a start superseded by a stop refuses to establish.
* **Env hygiene between jobs:** `clearAetherEnvironment()` wipes every `AETHER_*` variable
  before each `aether_core_start` (the in-process core's CLI parser only ever SETS vars, so
  session N+1 used to inherit session N's mode — the `engineClosed` bug).
* **Restart ordering:** `_hardCleanup()` + `_waitForPortFree()` run BEFORE the new coreStart
  (bind-race guard: the old job's abort is asynchronous on the Rust runtime).
* **Readiness is REAL, not "process exists":** the walk waits for the mode's SOCKS listener
  (`isListenerReady`), follows the core's own health while waiting (a job that dies fails
  the walk with the core's error, `error_value` JSON), then runs the end-to-end SOCKS probe
  through the mode's port, and — on the Linux helper path — the through-TUN probe (§3).
  A TCP accept alone is never "ready"; every probe failure is classified (§2).
* **The 9-step state machine (decree part 3), as implemented:**
  1. settings/session validation (mode, port map, per-family legs, env cleanup);
  2. VPN permission round (Android consent; desktop: no dialog up-front);
  3. TUN bring-up FIRST (`startVpn`) — Android VpnService+zeptun; Linux the Polkit helper
     path (pkexec → verified TUN → fd → zeptun .fd mode); Windows direct;
  4. tunnelUp completes ONLY on the platform's real `up` event (the helper's `up` means
     verified: interface + rules + route read back);
  5. Aether `aether_core_start` with the fully explicit non-interactive argument list (§2);
  6. listener wait following the core (the core is the authority);
  7. end-to-end SOCKS probe through the selected mode's port (classified errors);
  8. Linux helper path only: `verifyTunnelPath` — real traffic through TUN→zeptun→SOCKS→core
     →internet; failure fails the walk (`tunnelDataPathFailed`) and tears everything down;
  9. only then `VpnState.connected`.
  Every failure at any step runs the same `_hardCleanup()` (core job cancel + stopVpn +
  helper teardown) — no partial state survives a failed walk.

## 5. WARP identity — final storage path

* The data dir is `HomeDataDir()` (`desktop_shared/desktop_engine.cpp`):
  `$XDG_DATA_HOME/aethone`, else `$HOME/.local/share/aethone` — **the running user's** XDG
  path. The Dart walk passes `--config <filesDir>/aether/warp.toml`, so the WARP identity
  (`warp.toml` + the masque sibling), the psiphon state, the tor state and the last-connection
  cache all live under the normal user's home once the app runs unprivileged (§3) — the
  `/root/.local/share/aethone/...` sighting was purely the sudo workaround's side effect.
* The privileged helper never touches `HOME`/`XDG_*`: it is exec'd by pkexec for its own
  closed command set only, and the Aether core keeps running in the GUI process — so the
  identity path is identical in every run mode (helper tunnel, root tunnel, proxy).
* `/root/.local/share/aethone` (created by the owner's sudo run) is NOT deleted, moved or
  overwritten by anything in this round, per the decree. If the owner wants to reuse that
  identity, the file can be copied manually into `~/.local/share/aethone/aether/` — no code
  moves it automatically.

## 6. Zeptun lifecycle on Linux (start/stop/restart, crash)

* **start:** §3 (helper path as the normal user; direct path — identical netlink sequence
  inside zeptun itself — when run as root).
* **stop:** `stopVpn` → `StopTunnel()`: zeptun stop/destroy (idempotent) + `StopHelperPair()`
  (best-effort `down`, socket close, adopted fd close, detached reap with SIGKILL after 5 s)
  — the helper's EOF path performs the same teardown on app exit/crash.
* **restart:** `up` first clears 9000..9009 (both families) + the table-2022 route +
  the interface, then re-verifies — self-healing after any crashed previous pair; the
  bring-up worker serializes starts (`g_async_bringing`) so a straggler start can never
  stack a second helper/TUN.
* **crash of the GUI:** the helper sees EOF on its only client → tears down → exits. What
  survives at worst: nothing (rules are cleared on EOF); if the HELPER itself is SIGKILLed
  mid-session, the rules fall through to the main table (benign) and the next `up` clears
  them.

## 7. The appended defect — the psiphon tunnel data path (v4.38)

**Symptom (owner's addendum):** psiphon PROXY mode works; psiphon TUNNEL mode shows
Connected but exchanges no data — in EVERY app version (Android and desktop alike).

**Root cause (proven at the byte level, `scripts/psiphon_socks_pipeline_check.py`):**

* The psiphon family's SOCKS target is **psiphon-tunnel-core's own SOCKS server**
  (`psiphon/common/goptlib/socks.go`, vendored @ the frozen pin):
  - `psiphonChain` (AETHER→PSIPHon): aether binds 1821 and RAW-relays into psiphon's local
    proxy (`psiphon.rs run_chain` → `socks::forward`);
  - `psiphonOnly`: the main 1819 listener is handed to psiphon (`run_only` → `relay_to`).
* goptlib's accept path ends every stage with `socksFlushReadBuffer`, which treats ANY byte
  still buffered after a SOCKS message as a **fatal error** and closes the connection:
  ```go
  func socksFlushReadBuffer(r *bufio.Reader) error {
      if r.Buffered() > 0 { return fmt.Errorf("%d bytes left after SOCKS message", r.Buffered()) }
      return nil
  }
  ```
  (checked after the auth negotiation AND after the command read.)
* zeptun's SOCKS5 client — the ONLY thing that talks to that listener in tunnel mode —
  pipelines by default (`Socks5Config.pipeline = .auto` → on without username; POOLED
  connections are always `pipelined`): `encodeHandshake(pipeline=true)` writes greeting +
  request in one segment. Its `optimistic_data = true` default additionally rides the
  client's first payload on the request write (`sendWithEarly`).
* Consequence: **every TCP flow of the psiphon tunnel was rejected at the handshake**
  («N bytes left after SOCKS message»), while the walk's own probe — a strictly sequential
  SOCKS5 client connecting directly to 127.0.0.1:1821 — passed, so the UI showed Connected
  over a dead data path. Proxy mode never involves zeptun, hence worked.
* Why ONLY psiphon: aether's own listener (1819 for the plain WARP legs + the reverse
  modes) and tor's aether-served connector (1820) read the stream sequentially with
  exact-size reads — pipelined bytes simply wait in the kernel buffer. tor and every WARP
  leg are genuinely unaffected.

**The fix (v4.38, `socksStrict`):** the walk now sends
`socksStrict: overlay == psiphonChain || overlay == psiphonOnly` with `startVpn`; every
platform builder adds, in `[handler.socks5]`:

```toml
pipeline = false
optimistic_data = false
```

for exactly those two modes — a fully sequential SOCKS5 client (greeting → reply → request →
reply → data), which goptlib serves. Every other mode keeps the pipelined default. The
byte-level proof script (zeptun's own test-vector bytes × a faithful port of goptlib's
flush-check logic) is in-repo and now a CI gate: the pipelined and optimistic styles MUST be
rejected, the sequential style MUST be served.

**Android/Windows freeze note (part 4 of the decree):** the fix necessarily touches
`AethoneVpnService.kt` + `MainActivity.kt` (an additive intent extra + two TOML lines +
the restart-target identity) and `engine_channel_windows.cpp` (reads the same key), because
the defect lives in the shared zeptun configuration and the owner's addendum names «همه
نسخه‌ها». The change is strictly additive (`socksStrict` defaults to false; unknown keys are
ignored by older receivers) and scoped to the two psiphon-exit modes — every other mode's
configuration is byte-identical to before. NDK/ABI/Gradle/UI/pins: untouched.

## 8. Logs & diagnostics (decree 2.7)

Separable, timestamped, per component; no secrets (keys/tokens/WARP identity contents) are
ever logged:

* **aether core** — the captured core log (`<filesDir>/logs/…`, the Kotlin-budget capture):
  startup banner, identity readiness, scan/profile, listener announcements
  («[*] psiphon is ready; …»), job end states with the core's own error JSON.
* **zeptun** — in-process; its stats surface through `zeptunCounters` (the stats events);
  start failures carry the FFI rc + strerror verbatim.
* **the helper** — its own file `<filesDir>/logs/helper-log.txt` (stderr inherited through
  the pkexec spawn): every stage of §3's flow — install, serve, peer uid, up with the
  resolved note, verification, fd handoff, probe result with RTT, teardown, EOF reason.
* **the walk** — classified probe errors (§2), stage-named failures
  (`helper-install-failed:` / `helper-start-failed:` / `tunnel-privileged-setup-failed:` /
  `tunnelDataPathFailed` …), the through-TUN verification verdict, and the honest
  last-probe error quoted on budget timeouts.
* Session ids ride every platform→Dart event (stale events dropped), so a log line can
  always be attributed to the session that produced it.

## 9. What was REALLY executed this round (local, this machine)

| check | result |
| --- | --- |
| `flutter analyze` (whole repo, warnings fatal) | **PASS — 0 findings** |
| `flutter test` (full suite) | **PASS — 239 tests**, including the 3 new v4.38 tests (strict TOML lines; non-psiphon modes keep pipelining; the walk passes `socksStrict` exactly for psiphonChain/psiphonOnly with ports 1821/1819/1820/1819 asserted) |
| v4.37 arg tests (`-4`/`--h2`/`--h3`/`--quick-reconnect` explicit) | **PASS** (in the same suite; pinned in `test/m2_engine_test.dart`) |
| `g++ -std=c++17 -Wall -Wextra` full build of `linux/helper/aethone_tunnel_helper.cc` | **PASS — zero warnings**, binary runs *(g++; see the v4.38a note below — clang, the `flutter build linux` toolchain, additionally enables `-Wunused-const-variable` for C++ and failed the first CI run on 8 mirror-only constants)* |
| helper `--version` / closed command set | **PASS** (`aethone-tunnel-helper 1`; unknown flag → usage, rc=2) |
| helper `--serve` as a normal user | **PASS — refused** (`refusing to serve unprivileged (euid=1001)`, rc=2) |
| `g++ -fsyntax-only` of `desktop_shared/desktop_engine.cpp` against the real vendored `zeptun.h` | **PASS** |
| byte-level psiphon handshake proof (`scripts/psiphon_socks_pipeline_check.py`) | **PASS** — pipelined rejected («18 bytes left after SOCKS message»), optimistic rejected, sequential SERVED |

**v4.38a fixup (first CI run of this round, run 42278396584):** 13 of 16 legs green
on the first flight — including every test leg (flutter-ui with the handshake-contract
gate, zeptun @ pin, the psiphon fork, the aether crate), all three Android ABIs, both
windows legs and the linux desktop-native leg. The **linux bundle** leg — the only place
the helper is compiled by `flutter build linux` (CMake → clang, `-Wall -Werror` via
`apply_standard_settings`) — failed on 8 `-Wunused-const-variable` errors: clang enables
that check inside `-Wall` for C++; GCC does not (C-only there), so §9's g++ row was green
while the shipped build path was not. The eight are mirror-only members of the complete
route/linux.zig constant mirror (`kDnsAddrHost`, `RTM_GETLINK`, `RTM_DELADDR`,
`RTM_GETADDR`, `IFLA_IFNAME`, `RTA_DST`, `FRA_DST`, `RT_SCOPE_UNIVERSE`) — kept for audit
fidelity, never sent by this helper. Fix: `[[maybe_unused]]` (C++17, the helper target's
own `cxx_std_17`) on the six carrying statements — the mirror stays complete, the compiler
stays informed. Reproduced all 8 locally with `g++ -Wall -Wextra -Wunused-const-variable
-Werror` (GCC runs the check when asked explicitly), then green on the same set; link
green; `--version` prints; unprivileged `serve`/`--selftest` still refuse (rc=2).

**v4.38b fixup (run 42282415458, the v4.38a re-flight):** the helper now compiled
clean — and the bundle leg advanced to the NEXT never-compiled TU:
`linux/runner/engine_channel_linux.cc:331`,
`SetTunnelEventSink(TunnelEventSink, nullptr)` — a hard error («unexpected type
name 'TunnelEventSink': expected expression»). Root cause: the v4.37 code named the
runner's anonymous-namespace sink function exactly like the callback TYPE alias
`aethone::TunnelEventSink` (desktop_engine.h); inside `namespace aethone` the alias
hides the file-scope function, so the argument resolved to a type, not the function.
Every other TU was green in that run (14 green, this one failure + its two
dependents; desktop_engine.cpp and the helper compiled clean). Fix: the function is
now `OnTunnelEvent` (windows' twin is `Emit`; the trap is documented at both sites).
The round's local verification had never compiled this TU (no Flutter SDK/GTK dev
headers in the sandbox) — so this fixup also adds the missing gate:
`scripts/syntax_check_linux_runner.sh` — a full-TU `g++ -fsyntax-only -Wall -Wextra
-Werror` over the file against a signature-faithful stub of the pinned
flutter_linux.h (3.47.9) `Fl*` surface + the real glib/gio headers, catching every
name-resolution/hiding/overload/type error the real header would. Red-tested: the
pre-fix line fails the gate (g++: «expected primary-expression before ','»); the
fixed file passes with zero warnings. All runner↔engine calls verified against
desktop_engine.h's declarations (StartTunnel/StartTunnelAsync 4-arg,
VerifyTunnelPath → TunnelPathProbe, TunnelPrivilegeViaHelper, TunnelEvent fields,
the sink signature).

**v4.38c fixup (run 42287214107, the v4.38b re-flight):** both bundle legs GREEN
— the [[maybe_unused]] fix and the OnTunnelEvent rename held, and the linux
bundle leg built the helper + the runner for the first time. 14 of 16 legs
green; the next never-run layer failed: the NEW v4.37 selftest step died at its
first line, `B="$(tar -tzf … | head -1 | cut -d/ -f1)"` — «tar: stdout: write
error», exit 2 under `set -o pipefail`, before the selftest itself ever ran.
Root cause (reproduced locally against the REAL r84 bundle artifact, 23,658-byte
listing / 377 entries): `head -1` exits after the first line while tar keeps
streaming the listing; tar's next write hits the closed reader → EPIPE →
exit 141/2, and pipefail promotes it to the step's status. A size-independent
race (the listing is far below the 64 KB pipe buffer — the EPIPE lands on tar's
own stdio flush cadence), which is why the identical-shaped `find | head -1`
(single match) and `objdump --version | head -1` (tiny output) steps elsewhere
in the workflow have never tripped. The line was also unnecessary: the dist step
packs `-C build/linux/x64/release bundle`, so the top-level dir is the constant
`bundle` — the same hardcode the proven v4.36m smoke steps use. Fix: extract
first, `B="/tmp/bundle"` (workflow only; no shipped code touched). The fixed
step's logic verified locally against the real r84 tarball: extraction, helper
executable + policy present, `--version` prints — plus, per the honest record:
the smoke BOOT step after it has not run since the v4.38 runner changes (it
green in v4.36n; the only boot-path change since is the one-line sink
registration — a function-pointer store).

## 10. CI gates (this round's run — recorded after the push)

The workflow_dispatch run on this commit executes, all fail-closed:
* **flutter-ui job:** analyze (warnings fatal) + the 239-test suite + the new
  **psiphon handshake-contract gate** (the byte-level proof as a CI step);
* **helper selftest job (root):** the shipped `aethone-tunnel-helper --selftest` —
  bring-up of the REAL TUN + address + MTU/txqueuelen + table-2022 route + the four policy
  rules, fail-closed read-back verification, teardown, verification that teardown left
  nothing (no rules, no interface);
* **desktop-smoke job:** the bundle boots under Xvfb as the runner user, every bundled ELF
  resolves, the helper + Polkit action ship in the bundle, the helper's ISA floor re-proven
  post-tar, `aethone-tunnel-helper --version` runs;
* **the standing gates:** zig tests (zeptun @ the frozen pin), cargo tests (aether), go
  tests (psiphon-tunnel-core), Android per-ABI APKs, the x86-64-v1 ISA gate.
The run id and job results are recorded in the repo's run history for this commit
(see §13 for the commit; the CI table lands in the delivery message + can be pinned here
by a follow-up `git notes`-style evidence commit if the owner wants it in-tree).

## 11. NOT TESTED (honest limits — what needs the owner's desktop)

1. **The real Polkit prompt flow** (pkexec password dialog → helper install → per-connect
   auth on a real desktop with a polkit agent): no polkit daemon exists in this sandbox;
   CI exercises the same binary via sudo selftest, not the dialog.
2. **A real end-to-end connection** (helper probe through TUN → zeptun → SOCKS → aether →
   the internet) on a desktop with network + /dev/net/tun: the code path is CI-gated at the
   helper-selftest level (real TUN, real netlink) and the probe logic is compiled in, but
   no live gateway was dialed from this sandbox.
3. **The psiphon fix on real psiphon servers**: proven at the byte level + unit/walk level;
   a live psiphon tunnel (chain AND only) needs the owner's device/desktop round.
4. **Disconnect/reconnect cycles on Linux desktop** (TUN/rule cleanup between sessions):
   implemented (§6) and self-healing by design, but not exercised against a live desktop
   session here.
5. **Android/Windows device rounds** for the psiphon fix: the per-platform CI builds and
   unit tests pass; on-device verification is the owner's next round.

## 12. Changed files (this round)

```
desktop_shared/desktop_engine.cpp    v4.37 helper client + async bring-up + through-TUN
                                    verify + separable helper log; v4.38 strict TOML keys
desktop_shared/desktop_engine.h     the v4.37/v4.38 surface (StartTunnel/Async + socksStrict)
linux/helper/aethone_tunnel_helper.cc  NEW — the Polkit privilege helper (§3)
linux/helper/CMakeLists.txt         NEW — builds it with the runner's ISA floor
linux/packaging/com.chakcaad.aethone.tunnel-helper.policy  NEW — the Polkit action (fa/en)
linux/CMakeLists.txt                ship helper + policy in the bundle root
linux/runner/engine_channel_linux.cc  async startVpn (helper path), verifyTunnelPath,
                                    socksStrict; the tunnel event sink wiring
windows/runner/engine_channel_windows.cpp  reads socksStrict (same key, same builder)
android/.../MainActivity.kt         forwards the additive socksStrict extra
android/.../AethoneVpnService.kt    strict TOML lines + restart-target identity + log line
lib/connection/platform_engine_adapter.dart  v4.37 non-interactive args, Linux tunnelUp
                                    budget, classified probe errors, through-TUN gate;
                                    v4.38 socksStrict + the ZeptunConfigToml mirror
test/m2_engine_test.dart            v4.37 flag tests; v4.38 strict tests (TOML + walk)
scripts/psiphon_socks_pipeline_check.py  NEW — the byte-level proof (now a CI gate)
.github/workflows/native-ci.yml     helper selftest + bundle/policy/ISA gates + the
                                    psiphon handshake-contract step + the v4.38 scope line
LINUX_RUNTIME_AND_TUNNEL_FIX_REPORT.md  this report
```

## 13. The commit

The code + tests + CI + this report land as the round's commit(s) on `ci-bootstrap/v4.4`
(push + workflow_dispatch; run evidence per §10). The previous round's baseline:
`2e05d5a` (v4.36n, the ISA floor — see `LINUX_CPU_COMPATIBILITY_REPORT.md`).

**Acceptance against the decree's final 10:**
1. normal-user run — §3/§11.1 (code + posture verified; live dialog = owner round);
2. only the necessary TUN operations elevated — §3 (closed command set, SCM_RIGHTS);
3. Aether fully non-interactive — §2 (every prompt guard carries an explicit flag);
4. never waits on a hidden terminal choice — §2 (no prompt is reachable; no stdin tricks);
5. the local socket is stable — §2 (stall removed; failures classified and named);
6. Aether and zeptun managed correctly — §4/§6 (single instance, real readiness, cleanup);
7. Connected only after real traffic passes — §3 probe + §4 step 8 (Linux helper path);
8. disconnect/reconnect correct — §6 (idempotent teardown, self-healing bring-up);
9. proxy mode needs no root — §3 (the helper is never contacted outside tunnel mode);
10. Android/Windows zero regression — the freeze honored except the psiphon-scoped,
    additive exception the owner's addendum demands (§7); CI per-platform builds + tests
    green; device rounds pending (§11.5).


---

# v4.39 — the owner's device-report round (2026-11-07)

The r85 bundles (the first 16/16-green run, v4.38c) went to the owner's
devices. The report came back with five items; every one is root-caused,
fixed, and gated below. Zero frozen pins changed; the Android legs are
untouched (their CI commands are byte-identical; only the mipmap launcher
faces were regenerated from the owner's own mark).

## 14. The owner's five items and their root causes

### 14.1 «از ابتدا برنامه باید با دسترسی sudo اجرا بشه» — root-from-start

The v4.37 model elevated ONLY the TUN bring-up (the Polkit helper); the
GUI and the child cores ran as the normal user. The owner's decree: the
WHOLE app runs as root from launch — the TUN AND the engines it spawns in
the background, one privilege grant, no per-action prompts.

**Fix** — `ElevateAtStartup()` (desktop_shared/desktop_engine.cpp), the new
FIRST statement of `linux/runner/main.cc`:

* guards: already-root -> skip; `AETHONE_ELEVATION_ATTEMPT` set -> skip
  (the elevated side sets it; also the user's escape hatch); `CI` set ->
  skip (the smoke leg stays deterministic); no `XDG_CURRENT_DESKTOP` and no
  `DESKTOP_SESSION` -> skip (headless); no pkexec/env on PATH -> skip;
* spawn: `pkexec /usr/bin/env <SESSION=...>... AETHONE_ELEVATION_ATTEMPT=1
  <abs exe>` — /usr/bin/env is root-owned (pkexec's refusal to execute
  user-writable bundle paths does not apply; the same proven bootstrap the
  v4.37 helper install uses), the session vars (DISPLAY, WAYLAND_DISPLAY,
  XAUTHORITY, XDG_RUNTIME_DIR, XDG_SESSION_TYPE, XDG_CURRENT_DESKTOP,
  DESKTOP_SESSION, DBUS_SESSION_BUS_ADDRESS, LANG) pass through, and HOME /
  XDG_DATA_HOME deliberately re-root — the root instance's app data lives
  under /root, never inside the invoking user's directories;
* waits up to 300 s (the password prompt budget), then reports: elevated
  child ran to completion -> this process exits 0; declined (126) / no
  agent (127) / nonzero -> falls through IN PLACE as the unprivileged app,
  and the v4.37 helper path stays available for tunnels.

**Post-elevation, once root** — `EnsureDesktopIntegration()` (best effort,
idempotent, after the log capture so the outcome lands in the captured
core log): installs `aethone-icon.png` as
`/usr/share/icons/hicolor/256x256/apps/com.chakcaad.aethone.png` and writes
`/usr/share/applications/com.chakcaad.aethone.desktop` with
`Exec=<bundle>/aethone` — a moved bundle self-heals on its next root launch.

### 14.2 «آیکونش توی ترای سیستم کوچیک بشه» — close-to-tray, both desktops

**Linux** — `linux/runner/tray_controller_linux.cc`: `GtkStatusIcon`
carrying the owner's mark AS-IS (`aethone-tray.png` from the bundle root,
scaled to 24 px); the window's `delete-event` hides instead of destroying;
the menu is «نمایش AETHONE / خروج». A 3-second embed-grace timer un-hides
the window when the session has no system tray, and the verdict is
remembered (the next close quits directly — never a stranded hidden app).
A missing bundle face keeps the default close semantics.

**Windows** — `windows/runner/tray_icon_windows.cpp`: `Shell_NotifyIconW`
with the new `IDI_TRAY_ICON` resource (the mark AS-IS); `WM_CLOSE` in
`flutter_window.cpp` hides the window; the tray menu is Show/Exit in
Persian (`نمایش` / `خروج` as codepage-proof UTF-16 escapes — the runner
compiles without /utf-8); `TaskbarCreated` re-adds the icon after an
Explorer restart. A rejected `NIM_ADD` falls back to the default destroy.

### 14.3 The brand mark — one pipeline, two faces

`design/brand/aethone-logo.svg` (the owner's delivery, committed verbatim)
is rendered by `scripts/render_brand_icons.py` natively per size:

* the TRAY face — the mark exactly as-is (transparent): tray_icon.ico
  (16/24/32/48, embedded in aethone.exe) + aethone-tray.png (96);
* the APP face — the same mark on WHITE: app_icon.ico (16..256, replaces
  the template), aethone-icon.png (256), and the five Android mipmap
  ic_launcher.png faces (48/72/96/144/192).

Every corner pixel verified: tray faces fully transparent, app faces
opaque white. The outputs are committed (CI never re-renders); the script
is the derivation record.

### 14.4 Windows: `LoadLibrary zeptun.dll failed (126)`

Import-table analysis of the r85 `zeptun.dll` (objdump, the actual
artifact): every import is a system DLL (ADVAPI32, IPHLPAPI, KERNEL32,
WS2_32, fwpuclnt, ntdll) — nothing was missing. The DLL sat beside
`aethone.exe`. The 126 therefore came from the PATH argument:
`std::wstring(str.begin(), str.end())` widened byte-wise — garbage for any
non-ASCII install path (a Persian user name / extraction folder), so
`LoadLibraryExW` looked for a mangled filename and honestly reported "not
found".

**Fix** — the engine layer's Windows path handling is UTF-8 end-to-end
(`Utf8ToWide`/`WideToUtf8` via `MultiByteToWideChar(CP_UTF8)` at the exact
Win32 boundary): `GetModuleFileNameW`, `SHGetFolderPathW`,
`GetFileAttributesW`, `_wfopen/_wremove/_wrename` (the capture paths),
`_wmkdir`, `_wgetcwd`; the zeptun load converts once and retries with
`LOAD_WITH_ALTERED_SEARCH_PATH`; the failure string now carries the
absolute path it tried. The Dart side already opens `aether.dll` by the
exe-dir-relative name (the W loader handles it natively — unchanged).

**The same class on Linux** — POSIX paths are bytes; nothing to convert.
The CI regression gate: the desktop smoke leg now boots the same bundle
under `/tmp/باندل-آتون` with `XDG_DATA_HOME=/tmp/داده-آتون` and asserts the
core-log capture installs there.

### 14.5 «psiphon.exe باید در پس زمینه اجرا بشه» + the tor family

Three spawn sites launched console children (a console child of a GUI app
gets its own visible window on Windows):

* `aether/src/psiphon.rs` — psiphon.exe (the psiphon family connect);
* `aether/src/bridges.rs` — the lyrebird PT capability probe;
* `tor-ptmgr-0.46.0/src/ipc.rs` — arti's own PT child. THIS is the tor
  family's visible psiphon.exe the owner saw: arti (the tor engine) spawns
  the PT binary for bridged connects, and with the lyrebird PT registered
  for the tor modes, the PT child's console popped on every bridged tor
  connect — looking exactly like "psiphon.exe runs when I press tor".

**Fix** — `scripts/build_native_desktop.sh` patches all three sites with
`#[cfg(windows)] creation_flags(CREATE_NO_WINDOW)` (0x0800_0000). The
child cores keep their piped stdio; only the window goes away. The
patcher is fail-closed (the pristine text must match exactly once, or the
already-applied state exactly once) and its idempotency was proven locally
by three consecutive passes over the real pinned sources. A kill-on-close
Job Object in `windows/runner/main.cpp` now also reaps every child when
aethone.exe exits (any path — quit, crash, task-kill).

**Tor's protocol path itself** — audited, no defect found: the walk is
architecture-identical across families (transport_modes.dart maps every
mode to its listener; torChain -> --tor-bind 1820, torOnly -> --bind 1819
serving plain tor). The tor family's failures on the owner's Windows
device trace to the two classes fixed above (un-hidden PT children + the
ANSI path layer). No separate tor code path was added — none is needed.

## 15. What was REALLY executed this round (local, this machine)

* `g++ -fsyntax-only -Wall -Wextra -Werror` over the full TUs:
  desktop_engine.cpp (whole, Linux half), engine_channel_linux.cc,
  tray_controller_linux.cc (new GTK/pixbuf stub, real glib/gobject),
  tray_icon_windows.cpp (new Win32/shellapi stub — the MSVC-side
  pre-flight this sandbox cannot really compile);
* `render_brand_icons.py` executed; all nine outputs verified (sizes,
  modes, corner pixels; PIL reads every .ico/.png back);
* the hidden-child-cores patcher run three consecutive times over the
  REAL pinned sources (aether @ d58f9d56 + tor-ptmgr-0.46.0 downloaded
  from crates.io): APPLIED / ALREADY_APPLIED / ALREADY_APPLIED, exactly
  one patch site per file at the end;
* import-table dump of the r85 zeptun.dll/aether.dll/aethone.exe/
  lyrebird.exe/psiphon.exe/flutter_windows.dll (objdump) — the 126
  root-cause proof;
* `bash -n` over the modified build script; YAML load of the modified
  workflow (13 jobs, the smoke step list verified);
* CI guard added after the analysis: `ElevateAtStartup` skips when `CI`
  is set — the smoke leg boots deterministically (no pkexec attempt).

## 16. NOT TESTED (honest limits — what needs the owner's devices)

1. the live pkexec elevation round (the password prompt, the root
   instance's DISPLAY plumbing) — posture + guards verified, the dialog
   itself is an owner round; decline/headless/no-agent fallbacks verified
   by construction;
2. the tray embed on a real desktop session (X11 + a system tray; the
   grace timer's un-hide path) — CI boots headless Xvfb where
   GtkStatusIcon never embeds, so the CI leg exercises the FALLBACK, not
   the tray;
3. `ElevateAtStartup` under Wayland (the session vars pass; pkexec + a
   Wayland compositor's polkit agent is an owner round);
4. the CREATE_NO_WINDOW patch on a real Windows session (compiles are
   CI-gated; the visual proof — no console windows — is an owner round);
5. the tor family's device behavior after the round (the diagnosis is
   code-architected; the owner's «وقتی تور اور وارپ رو میزنم» observation
   is explained by the arti PT child + should vanish with the hidden
   spawns — verify on device).

## 17. The commit (v4.39)

The code + icons + build-script patches + CI gates + this section land as
`v4.39` on `ci-bootstrap/v4.4`. Baseline: `da60d05` (v4.38c, the SIGPIPE
fixup). Run evidence recorded below after the dispatch.

| file | this round |
|---|---|
| design/brand/aethone-logo.svg | NEW — the owner's mark, verbatim |
| scripts/render_brand_icons.py | NEW — the two-face pipeline |
| windows/runner/resources/{app_icon,tray_icon}.ico | regenerated (app: white bg; NEW tray) |
| windows/runner/{tray_icon_windows.cpp,.h} | NEW — the Windows tray |
| windows/runner/{flutter_window.cpp,main.cpp,resource.h,Runner.rc,CMakeLists.txt} | WM_CLOSE-to-tray, Job Object, IDI_TRAY_ICON, new source |
| linux/packaging/{aethone-icon,aethone-tray}.png | NEW — the bundle faces |
| linux/runner/{tray_controller_linux.cc,.h} | NEW — the GTK tray |
| linux/runner/{main.cc,my_application.cc,CMakeLists.txt}; linux/CMakeLists.txt | the elevation call; icon + tray wiring; new source; the two PNG faces installed into the bundle |
| desktop_shared/desktop_engine.{h,cpp} | the UTF-8/W path layer; ElevateAtStartup; EnsureDesktopIntegration |
| android/app/src/main/res/mipmap-*/ic_launcher.png | regenerated (the mark on white) |
| scripts/build_native_desktop.sh | the three CREATE_NO_WINDOW patches (fail-closed, idempotent) |
| scripts/syntax_check_linux_runner.sh | + the tray/engine/Win32 legs; new stubs (gtk, windows, shellapi) |
| .github/workflows/native-ci.yml | BUILD_INFO scope lines (both legs); smoke: the two icon assertions + the Persian-path boot |
| README.md / this report | the v4.39 records |
