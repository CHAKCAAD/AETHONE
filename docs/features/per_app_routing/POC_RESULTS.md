# Per-App Routing — Stage 2 PoC Results

Date: 2026-11-18. Branch `fix/owner-round-2`, HEAD `5502d34` + the uncommitted Stage-2
working tree (nothing committed or pushed — see §Build). Evidence statuses use the
agreed vocabulary: **Implemented / Automated-tested / Device-tested / Not tested /
Unsupported**; test rows use **Pass / Fail / Blocked / Not tested**.

## Where the evidence comes from

- **Host engine fixtures** (`native/zeptun/src/tests/route_tests.zig`, new): the REAL
  engine (external device, userspace stack, SOCKS5 handler, mobile preset) driven with
  a flow-owner judge that routes by ORIGINAL source port — the host stand-in for "which
  app opened this flow". Distinguishable exits per route: one recording SOCKS5 server
  per socks5 route (counts handshakes + relayed bytes, echoes payloads) and a plain
  echo server for the direct route. This is the engine-level equivalent of the device
  exit-IP test: WHICH exit each flow actually used is asserted, not assumed.
- Environment: Zig 0.16.0 (x86_64-linux, the zeptun-required version), gcc 13,
  Linux sandbox. Full-suite result, repeated 3× for flake control:
  `Build Summary: 10/10 steps succeeded; 118/126 tests passed (8 skipped)`.
  Baseline before the change (pristine vendored tree = pin 08a1ab0): 109/117
  (8 skipped). The 8 skips are pre-existing platform skips (netns/Windows cases).
  Zero regressions: all 109 baseline tests still pass; 9 new tests added.
- **No physical Android device is available in this environment.** Every
  device-dependent check is reported **Not tested** — none is simulated, none is
  claimed. The Android build itself could not run here either (no Android SDK/NDK/
  Flutter toolchain in the sandbox; the repo's own precedent — `build_native.sh`'s
  "DELIVERED, NOT TESTED (no Android toolchain in the analysis environment)" —
  applies). The Kotlin was verified by full-file review against the exact zeptun
  JNI signatures; its first compile happens in CI or on the owner's machine.

## Test matrix

### Test 1 — UID attribution

| Aspect | Status | Evidence |
| --- | --- | --- |
| Flow-owner callback delivers the exact tuple at flow-open (proto, family, original local/remote endpoints) | **Pass (Automated-tested, host)** | `route_tests.zig` port-keyed judge; `verdict.zig` tests assert tuple fields + packing |
| Route number returned by the callback selects the assigned route | **Pass (Automated-tested, host)** | three-exits fixture: route 1 → recorder B, route 2 → direct echo, default → recorder A |
| Distinct apps get distinct routes | **Pass (Automated-tested, host)** | recorder B exactly 1 CONNECT, echo exactly the direct payload, recorder A ≥ 1 CONNECT |
| Unknown / failed attribution uses the DEFAULT route | **Pass (Automated-tested, host)** | out-of-range route number → `route_fallback` counter + the flow still exits via the default recorder |
| Real app resolves to its real UID on Android 10+ | **Not tested (no device)** | requires `getConnectionOwnerUid` on hardware — the resolver (`PerAppRouteResolver`) is implemented with bounded-wait + metrics but unmeasured |
| Shared-UID deterministic policy | Implemented, **Not tested** | code path exists (unanimous-only), needs a device with a shared-UID app pair |
| API 24–28 limitation | Implemented, **Not tested** | counted skip path; the limitation is reported, not queried |

### Test 2 — TCP

| Aspect | Status | Evidence |
| --- | --- | --- |
| Two independently routed apps complete independent data round trips | **Pass (Automated-tested, host)** | three-exits fixture: all payloads round-trip byte-identical |
| Each app's traffic verifiably exits through ITS assigned route (not the other's, not always the default) | **Pass (Automated-tested, host)** | recorder B bytes == 2×payload (route-1 flow only), echo bytes == 3×payload (direct + two relayed), recorder A ≥ 1 CONNECT |
| Route dials never consume pooled (default) connections | **Pass (Automated-tested, host)** | with `pool_size = 4` (mobile default), recorder B saw EXACTLY 1 CONNECT for the route-1 flow while the default flow could pool |
| Real-device HTTPS exit-IP verification (App A → engine exit, App B → device IP) | **Not tested (no device)** | adb procedure written (§Device procedure) |

### Test 3 — UDP

| Aspect | Status | Evidence |
| --- | --- | --- |
| Direct-routed UDP flows exit RAW (no SOCKS framing) and round trip | **Pass (Automated-tested, host)** | UDP fixture: direct flow answered by the raw echo; recorder's `udp_associates` stayed 0 |
| Default-routed UDP flows exit via SOCKS5 UDP ASSOCIATE and round trip | **Pass (Automated-tested, host)** | same fixture: recorder A `udp_associates == 1`, framed echo returns to the app |
| Attribution measured SEPARATELY from default-fallback | **Pass (Automated-tested, host)** | native counters `route_assigned` (1) vs `route_fallback` (0) — a fallback is never counted as an attribution |
| Real-device UDP attribution success rate (netd/QUIC tuples) | **Not tested (no device)** | the counter pair above + resolver metrics dump exist precisely for this measurement |

### Test 4 — Route persistence across a live update

| Aspect | Status | Evidence |
| --- | --- | --- |
| Established flow keeps its route after `updateRoutes` | **Pass (Automated-tested, host)** | live-update fixture: after swapping route 1 socks5→direct, the established flow's further 4 000 bytes still traverse recorder B (`bytes_before + 2×more`) |
| New flows use the updated table | **Pass (Automated-tested, host)** | new route-1 flow exits DIRECT (echo), recorder B saw no new CONNECT |
| Update is atomic; invalid documents never partially replace the table | **Pass (Automated-tested, host)** | duplicate-id update rejected (`error.InvalidArgument`), `routeCount` unchanged, subsequent flows still resolve |
| `nativeUpdateRoutes` from Kotlin on a running tunnel | Implemented, **Not tested** | JNI path + receiver implemented; needs a device |

### Test 5 — Failure behavior

| Aspect | Status | Evidence |
| --- | --- | --- |
| Flows on a dead assigned route FAIL CLOSED (RST), no fallback to default/other routes | **Pass (Automated-tested, host)** | dead-route fixture: RST observed, default recorder saw 0 CONNECTs from that flow |
| Other apps unaffected | **Pass (Automated-tested, host)** | same fixture: a default-route app on the same engine round-trips afterwards |
| Failure observable through a controlled diagnostic | **Pass (Automated-tested, host)** | `tcp_connect_failed` (existing) + route counters; on-device: logcat `AethonePoC` + `POC_ROUTES_STATS` dump |
| Direct-routed flow with a fake-IP destination (DNS attribution failed) fails closed | **Pass (Automated-tested, host)** | fake-IP fixture: RST, `route_direct_fake == 1`, `tcp_opened == 0`, zero traffic to the default recorder |

### Test 6 — Loop prevention

| Aspect | Status | Evidence |
| --- | --- | --- |
| Direct-route sockets use the existing `protect()` integration (code path) | **Pass (Automated-tested, host — path executed, Android protect is a runtime no-op on host)** | direct fixtures run `protect.apply` on every dial (`openSocket` unchanged) |
| AETHONE's own process stays outside the TUN | Implemented (unchanged guards), **Not tested** on device | own-uid Builder disallow + protect are untouched by this change (audit §1.1); device check needed |
| Chain children cannot recursively enter the TUN | Implemented (unchanged), **Not tested** | children run under AETHONE's uid (excluded) — unchanged behavior |
| Routing loop through direct handler | **Pass (Automated-tested, host)** | direct flows terminate at the real echo; no re-entry into the engine (external-device output is the only ingress) |

### Test 7 — Regression

| Aspect | Status | Evidence |
| --- | --- | --- |
| All pre-existing zeptun unit/integration tests | **Pass (Automated-tested, host)** | 109/109 baseline tests green after the change (118/126 incl. 9 new; 8 pre-existing skips) |
| Steady-state TCP performs no heap allocation (memory regression guard) | **Pass (Automated-tested, host)** | pre-existing test green — the route lock/copies add zero steady-state allocation (flow-open only) |
| Config compatibility: no `[routes]` section → single-handler behavior | **Pass (Automated-tested, host)** | every pre-existing config test (TOML/JSON/presets) green; verdict tests prove legacy 0..3 returns decode identically |
| WARP / overlay / chain modes, Include/Exclude, DNS, VPN start/stop, Kill Switch | **Not tested (no Android build in environment)** | no Dart/Kotlin/config change touches those paths (the tunnel TOML is byte-identical on non-PoC starts); device regression round required |

## Performance measurements (task §4)

| Metric | Status | Notes |
| --- | --- | --- |
| UID resolution latency | Implemented (instrumented), **Not measured** | `PerAppRouteResolver` accumulates avg/max per-query latency; dump via `POC_ROUTES_STATS`. Device measurement required. |
| Callback timeout frequency | Implemented (instrumented), **Not measured** | `timeouts` counter in the same dump. |
| Route lookup latency | Design-bounded, not separately measured | spin-lock + ≤ 8-entry copy at flow-open only (nanosecond scale); never per-packet, never across the JNI callback. |
| TCP connect overhead | **Not measured** | host fixtures complete within existing timeouts; a device microbenchmark (connect with/without attribution) is the honest measure. |
| UDP attribution success rate | Implemented (instrumented), **Not measured** | `route_assigned` vs `route_fallback` + resolver counters exist exactly for this. |
| Memory of flow/route caches | Bounded by construction | flow tables unchanged (LRU, capped); route state = ≤ 8 entries + one ≤ 20-byte copy per open flow; steady-state no-heap regression test green. |

## Safety requirements check

- Bounded caches: flow tables unchanged (pre-existing caps); route table ≤ 8 entries.
- Bounded callback wait: 50 ms hard timeout, single executor thread (no unbounded
  thread creation; daemon thread, shut down with the tunnel).
- No per-packet JNI callback: session lookup precedes the DNS branch (udp.zig); TCP
  asks at SYN only. Asserted by the counters (`route_asked` == number of flows, not
  packets, in every fixture).
- No sensitive package/flow info in production logs: metrics are counts/latencies;
  the per-package line only exists on adb-driven PoC starts, bounded to 64 lines.
- Thread-safe route updates: mutex-disciplined swap (§8.2 of ARCHITECTURE.md).
- Safe during VPN stop/restart: resolver closed after the engine thread joins;
  callbacks cannot reach a destroyed service (GlobalRef deleted after join).
- Callbacks cannot corrupt newer flows: stateless queries + single-writer return.

## Known limitations (honest list)

1. **No device round has run** — every Android-runtime claim above its host evidence
   is marked Not tested. The completion gate's device items are unmet; the PoC is
   host-proven, not device-proven.
2. Per-route SOCKS5 username/password not supported (routes are cred-free; the chain
   children and aether listener are cred-free today).
3. Route entries reuse the global `udp_mode`; per-route UDP-over-TCP is future work.
4. A live update cannot INTRODUCE a direct route unless one existed at start
   (`dns.upstream` is fixed at start). Restart to add Direct later.
5. The Kotlin map swap and the native table swap are two calls — a flow opened in the
   window degrades to default (counted). A combined native call is a Stage-3 cleanup.
6. `getConnectionOwnerUid` UDP attribution for netd-originated DNS is expected to be
   best-effort (conntrack races) — measured, not assumed, once a device is available.
7. IPv6: unchanged pre-existing behavior (v4-only TUN); v6 bypasses the tunnel (D8).
8. Zeptun upstream divergence: the vendored tree now differs from pin 08a1ab0 by this
   patch. CI (default path) still builds the pin — the PoC APK needs
   `scripts/build_native_poc.sh` until the owner decides the fork-pin question (D14).

## Build and reproduction

Host engine tests (this environment, exact commands):

```sh
# Zig 0.16.0 on PATH (the only requirement — zeptun's own README pin)
cd native/zeptun
zig build test --summary all
# -> 10/10 steps succeeded; 118/126 tests passed (8 skipped)

zig build                 # host libzeptun.so builds clean
nm -D zig-out/lib/libzeptun.so | grep zeptun_update_routes   # new symbol exported

# JNI bridge compile check (with a jni.h on the include path)
gcc -std=c11 -Wall -Wextra -Werror -I include -I <jni-include-dir> \
    -c src/jni/zeptun_jni.c -o /tmp/zeptun_jni.o               # clean
```

Android PoC native build (needs NDK r26d + Zig 0.16.0, e.g. on CI or the owner's host):

```sh
ANDROID_NDK_HOME=<ndk> ZIG=<zig-0.16.0> scripts/build_native_poc.sh \
  --abi arm64-v8a --rust-target aarch64-linux-android --goarch arm64 \
  --api-level 29 --src-cache .srccache --out out/arm64-v8a
# then package the APK exactly like the android-debug workflow, staging the
# PoC native outputs as jniLibs (the workflow recipe is unchanged).
```

## Device procedure (for the owner's hardware round — not executed here)

1. Build the PoC APK (above) and install two distinguishable test apps, e.g.
   Firefox (package `org.mozilla.firefox`) and a second browser.
2. Connect AETHONE normally (engine up on 1819), then arm the PoC table:
   `adb shell am start-foreground-service -n com.chakcaad.aethone/.AethoneVpnService \
      --ei port 1819 --es poc_routes '{"routes":[{"id":"engine","kind":"socks5"},{"id":"direct","kind":"direct"}],"assignments":{"org.mozilla.firefox":"direct"}}'`
   (logcat tag `AethonePoC` prints the token).
3. Test 2: in each app open an IP-echo page; the assigned app must show the device's
   real IP, the other the engine's exit. `POC_ROUTES_STATS` dumps attribution + latency.
4. Test 4: `adb shell am broadcast -a com.chakcaad.aethone.POC_UPDATE_ROUTES --es token <t> \
   --es routes '<updated json>'` — keep a download running in the assigned app, verify
   its exit is unchanged while new flows use the new table.
5. Test 5: assign an app to a dead route (`socks5` on a closed port), verify the app's
   connections fail fast while others keep working.

## Completion gate (task §10) — verdict

- Two real applications attributed correctly on Android 10+: **Not tested (no device)**.
- TCP per-app routing verified with independent exit observation: **host-proven
  (Automated-tested); device unproven**.
- UDP attribution measured + limits documented: instrumentation implemented,
  measurement **Not tested**.
- Existing VPN modes regression: host suite green; Android regression **Not tested**.
- Loop prevention: code-path verified on host; device **Not tested**.
- No critical leak / unintended fallback introduced: **host-proven** (fail-closed
  fixtures + counter coverage); device confirmation pending.

**Stage 2 status: PARTIALLY SUCCESSFUL — the architecture is proven end to end at the
engine level (per-flow handler selection, distinguishable exits, live updates,
fail-closed semantics, DNS handling, zero regressions on the 109-test baseline), but
the completion gate's device-dependent items remain unmet.** Stage 3 must not start
until the device round closes the gate (or the owner explicitly accepts the host
evidence as sufficient).

---

# Stage 2.1 — Android Validation & Persistent Handoff (2026-11-18)

Branch `feature/per-app-routing-stage2-poc` (created from the audited baseline
`5502d34` = Stage 2's working tree, commit `0583a34`). Remote `fix/owner-round-2`
had advanced to `d9bcd64` (rounds 11–12, Firefox retirement v2.1.0) BEFORE this
branch was cut — merging that line is a separate owner decision (see
SESSION_HANDOFF.md). Environment: the analysis sandbox — Zig 0.16.0, JDK (Temurin
17.0.21, the CI pin), Flutter 3.47.9 stable (dart 3.13.7, the CI pin), Android SDK
platforms;android-36 + build-tools;36.0.0, NDK r26d (26.3.11579264, selective
extract: no simpleperf/shader-tools/python/musl). 3.9 GB RAM / constrained disk —
deviations noted per item.

## Script safety audit (brief §4) — both defects CONFIRMED, FIXED, TESTED

Audited the committed wrapper (`0583a34`) against a stubbed child in a sandbox:

| Concern | Verdict | Evidence |
| --- | --- | --- |
| `exec` prevents the EXIT trap from running | **Confirmed** | old wrapper left `.zeptun_poc.*` in the repo root after a successful stubbed run (it also leaked two scratch dirs into the REAL repo root during a mis-wired demo attempt — live confirmation; both were removed) |
| Trap deletes a caller-supplied `POC_SRC_CACHE` | **Confirmed** | stubbed run with `POC_SRC_CACHE=<pre-existing dir + sentinel file>` and an unreadable file inside the vendored tree → `cp` fails → `set -e` exit → trap fires → the directory AND its sentinel were deleted (reproduced deterministically) |

Fix (small, independent, documented in the script header):
`build_native_poc.sh` now (1) runs `build_native.sh` as a CHILD and exits with the
child's exact status (`|| rc=$?`), so the trap runs on success AND failure; (2) only
ever removes `POC_SCRATCH_DIR` — a directory THIS run created via `mktemp` (fresh by
construction, ownership proven); (3) `POC_SRC_CACHE`, when set, is honored only as the
PARENT into which the fresh scratch dir is placed (`mkdir -p`, never deleted); (4)
INT/TERM traps chain into the cleanup.

Tests: `scripts/test_build_native_poc.sh` — self-contained (stubbed child, no Android
toolchain needed), **24/24 checks green**: success, failure (status 7 preserved),
caller-path survival (success + failure), missing parent created-then-kept, missing
vendored tree, SIGTERM mid-build (143 + cleanup), args/env forwarded, copy verified.
Re-run after any change to the wrapper.

## Kotlin compile in the real project configuration (brief §5.1) — PASS

First compile attempt of the Stage 2 Kotlin. Command: `./gradlew
:app:compileDebugKotlin` with the repo's wrapper (Gradle 9.8.2, AGP 9.4.0, Kotlin
2.4.0, compileSdk 36). Sandbox deviations (none change what is compiled): `--no-daemon
--no-parallel`, `-Dorg.gradle.jvmargs=-Xmx2g` (repo default asks 8G vs 3.9G sandbox
RAM), in-process Kotlin compiler, and a sandbox-only stub
`android-sdk/ndk/28.2.13676358/source.properties` satisfying AGP's configure-time NDK
revision check (`flutter.ndkVersion`; no NDK is needed by the compile task itself).

| Step | Result |
| --- | --- |
| First compile | **FAIL — real Stage 2 defect**: `PerAppRouteResolver.kt:198:46 Unresolved reference 'pkg'` (the bounded logging block referenced a loop variable out of scope) |
| Fix | 6-line change inside `resolve()`: the logging block now iterates the uid's package names within scope; semantics preserved (one log line per NEW package, ≤ 64 total, package names never printed) |
| After fix | **BUILD SUCCESSFUL** — classes emitted: `AethoneVpnService`, `PerAppRouteResolver`(+Companion), `PoCRoutes`(+Companion/Kt), `PoCRoutesReceiver`(+Companion), `dev.zeptun.Zeptun` |

This closes the Stage 2 "Kotlin compile pending" item: **Automated-tested** (real
configuration, JDK 17.0.21 + Flutter 3.47.9 exactly as CI pins them).

## JNI linkage verification (brief §5.2) — PASS (static + binary)

All five `external fun` declarations byte-match the `JNINativeMethod` table in
`zeptun_jni.c`:

| Kotlin (Zeptun.kt) | JNI descriptor (zeptun_jni.c) |
| --- | --- |
| `nativeStart(Any?, Int, String?, Boolean): Int` | `(Ljava/lang/Object;ILjava/lang/String;Z)I` |
| `nativeStop()` | `()V` |
| `nativeVersion(): String` | `()Ljava/lang/String;` |
| `nativeCounter(Int): Long` | `(I)J` |
| `nativeUpdateRoutes(String): Int` | `(Ljava/lang/String;)I` |

Binary level (the ANDROID build below, not the host lib): `nm -D` on
`libzeptun-jni.so` exports `JNI_OnLoad`, `zeptun_update_routes`,
`zeptun_set_flow_callback` (engine statically linked in); `libzeptun.so` exports
`zeptun_update_routes`, `zeptun_set_flow_callback`, `zeptun_start/stop/version(_string)`.

## Native PoC build (brief §5.3–5.5) — zeptun stage PASS; stages 2–4 BLOCKED (environment)

Exact base command of the brief (plus `taskset -c 0,1` — the first full-parallelism
attempt was killed by the sandbox's resource limits; 2 CPUs bound zig's in-process
parallelism and memory stayed at 3.3–3.5 GB free):

```sh
ANDROID_NDK_HOME=<r26d> ZIG=<zig-0.16.0> scripts/build_native_poc.sh \
  --abi arm64-v8a --rust-target aarch64-linux-android --goarch arm64 \
  --api-level 29 --src-cache <dedicated> --out <dedicated>
```

| Stage | Status | Evidence |
| --- | --- | --- |
| [1/4] zeptun (vendored patch, `ZEPTUN_LOCAL_SRC`) | **Pass (in-sandbox)** | ndk-build `[arm64-v8a] Compile: zeptun-jni <= zeptun_jni.c` → `libzeptun.so` (275 800 B) + `libzeptun.a` (358 152 B) + `libzeptun-jni.so` (281 848 B) in the dedicated out dir; ELF `ARM aarch64 … for Android 29, built by NDK r26d (11579264)`, 16 KiB LOAD alignment; export guard passed (exactly 3 files); intermediates wiped; **the fixed wrapper removed its scratch on the failed run** (real-run confirmation of §Script safety) |
| [2/4] aether | **Blocked (environment)** | pin `d58f9d56` cloned fine, then `cargo: command not found` (rc 127) — no Rust 1.99.1 / cargo-ndk 4.1.2 in this sandbox (with Go 1.26.3, the toolchains + boring-sys fetch exceed the sandbox's remaining disk/memory) |
| [3–4] lyrebird, psiphon | **Blocked (environment)** | not reached (would need Go 1.26.3) |
| APK assembly | **Not tested (environment)** | requires all four cores staged as jniLibs — must run on CI / the owner's host via the android-debug recipe with the PoC outputs staged (the recipe itself is unchanged) |

Other ABIs (armeabi-v7a, x86_64): not repeated — identical recipe, identical block
point; arm64-v8a is the device-relevant ABI for the validation round.

## Device validation matrix (brief §7) — NO DEVICE CONNECTED

`adb` is not present in this environment and no physical device is attached. Per the
brief, emulator results are NOT substituted for device results. Statuses:

| Test | Status |
| --- | --- |
| A — UID attribution (real apps, shared UID, invalid, timeouts, latency) | **Blocked (no device)** — procedure: §Device procedure step 2 + `POC_ROUTES_STATS` |
| B — TCP routing with independent exit-IP proof | **Blocked (no device)** — procedure: §Device procedure step 3 |
| C — UDP attribution (raw direct, SOCKS5 ASSOCIATE, success rate vs fallback) | **Blocked (no device, no controllable UDP endpoint)** |
| D — DNS (fake-IP default vs direct's `dns.upstream`, fail-closed leftovers) | **Blocked (no device)** |
| E — Live update (old flow keeps route, new flow new table, invalid rejected) | **Blocked (no device)** — procedure: §Device procedure step 4 |
| F — Failure isolation (dead route fails closed, others unaffected) | **Blocked (no device)** — procedure: §Device procedure step 5 |
| G — Loop prevention (own uid, protected sockets, chain children) | **Blocked (no device)** |
| H — Regression (WARP, overlays/chains, Include/Exclude, direct rules, DNS, start/stop, Kill Switch) | **Blocked (no device + no full APK here)** |

## Performance / resolver metrics (brief §8) — Not measured (no device)

The counters (`route_assigned`, `route_fallback`, `route_direct_fake`, resolver
calls/attributed/timeouts/errors/avg/max latency) are implemented and reachable via
`POC_ROUTES_STATS`; no honest measurement exists without hardware. No new
instrumentation was added (per the brief: propose first, keep the architecture).

## Supply-chain rules honored (brief §5 rules / §12 prohibitions)

No pin, workflow, or `build_native.sh` default path changed (`ZEPTUN_LOCAL_SRC` unset →
byte-identical CI recipe). No user cache deleted (dedicated `--src-cache`/`--out`).
No `flutter clean`, no Gradle cache purges of user state. `pubspec.lock` — modified as
a side effect of `flutter pub get` (a newer pub added a `listen` entry) — was REVERTED
to the committed baseline; nothing Dart-side changed. No APK, keystore, or secret is
committed; build logs stay out of the repo (excerpts above).

## Stage 2.1 verdict

**Partially Successful (environment-bounded).** Closed this round: script safety
(confirmed + fixed + 24-check suite + real-run confirmation), Kotlin compile in the
real configuration (one real defect found and fixed — the exact purpose of this
round), JNI static + binary symbol verification, the zeptun stage of the PoC native
build through the fixed wrapper with the new symbols present in the Android
artifacts, and the full evidence trail persisted on the
`feature/per-app-routing-stage2-poc` branch. Open: the aether/lyrebird/psiphon stages
and the APK (need Rust 1.99.1 + Go 1.26.3 — CI or the owner's host), and the entire
device round (Tests A–H). Stage 3 remains gated on the owner's review of the device
evidence.
