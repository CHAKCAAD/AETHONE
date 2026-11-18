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
2. Connect AETHONE DA NORMALLY through its UI once (engine up on 1819) and
   accept the VPN consent dialog — the PoC entry point refuses to start
   without the standing consent (round-4 correction; see §round 4 below).
3. Arm the PoC table through the round-4 debug-only entry point (the
   previously documented `am start-foreground-service` on
   `AethoneVpnService` was IMPOSSIBLE as written: the service is
   `exported=false` and the DA package id differs — see §round 4):
   `adb shell am start -n com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity \
      --ei port 1819 --es poc_routes '{"routes":[{"id":"engine","kind":"socks5"},{"id":"direct","kind":"direct"}],"assignments":{"org.mozilla.firefox":"direct"}}'`
   (logcat tag `AethonePoC` prints the validation/consent/start result and
   the token; `-W` additionally reports the activity result).
4. Test 2: in each app open an IP-echo page; the assigned app must show the device's
   real IP, the other the engine's exit. `POC_ROUTES_STATS` dumps attribution + latency.
5. Test 4: `adb shell am broadcast -a com.chakcaad.aethone.POC_UPDATE_ROUTES --es token <t> \
   --es routes '<updated json>'` — keep a download running in the assigned app, verify
   its exit is unchanged while new flows use the new table.
6. Test 5: assign an app to a dead route (`socks5` on a closed port), verify the app's
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

---

# Stage 2.1 round 2 — Full toolchain, native build & PoC APK (2026-11-18)

Branch `feature/per-app-routing-stage2-poc` @ `408f7f0` (worktree, not the owner's
checkout). Environment: the Debian 13 build sandbox — 2 vCPU, 3.9 GB RAM (no swap),
9.9 GB disk (~4 GB system/pre-existing). Every deviation below is disk/RAM-bounded
and documented; no pin, script, workflow, or product file was changed.

## Toolchain (brief §3/§4) — installed at exact pins, verified

| Tool | Version | Source & verification |
| --- | --- | --- |
| Flutter | 3.47.9 stable (framework `c197ca5199`, Dart 3.13.7) | git clone at the exact tag — the method `docs/LOCAL_BUILD_FA.md` itself prescribes; `c197ca5199` == the official `releases_linux.json` archive hash for 3.47.9. The 1.58 GB tarball does not fit the sandbox disk. |
| JDK | Temurin 17.0.21+9 | Adoptium release archive, sha256 verified |
| Android SDK | cmdline-tools + platform-tools (adb 37.0.1) + platforms;android-36 + build-tools;36.0.0 | sdkmanager (official repository), licenses accepted |
| NDK (cores) | r26d = 26.3.11579264 | official zip, Google-published sha1 verified; `source.properties` revision asserted |
| Rust | 1.99.1 (minimal) + aarch64-linux-android target | rustup, exact toolchain pin |
| cargo-ndk | 4.1.2 | `cargo install --version 4.1.2 --locked` (as CI) |
| Go | 1.26.3, GOTOOLCHAIN=local | go.dev archive, official sha256 verified |
| Zig | 0.16.0 | ziglang.org, sha256 = the workflow pin `70e49664…ba3d00` |
| cmake (boring-sys host req.) | 3.31.6 | official Kitware manylinux wheel, PyPI sha256 verified |
| libclang (bindgen host req.) | 18.1.1 | official PyPI wheel, sha256 verified, `LIBCLANG_PATH` set |

Full verification battery (all commands of brief §4, fresh shell): recorded in
`.toolchain/evidence/verify-toolchain.txt` on the build host. Deviations (documented):
tools live under `/home/z/my-project/.toolchain/` (the sandbox only persists that
tree; the brief's `~/.local/share/aethone/toolchains/` mapping is recorded in
`.toolchain/per-app-routing-stage2.env`), and `unzip` is absent system-wide — a
python-zipfile shim on PATH provided identical extraction for the pinned scripts.

## Native build (brief §5) — zeptun PASS, aether BLOCKED (RAM), Go stages PASS

Command (exactly the brief's reference, dedicated build root, `taskset -c 0,1`):

```sh
ANDROID_NDK_HOME=<r26d> ZIG=<zig-0.16.0> POC_SRC_CACHE=<srccache> \
  scripts/build_native_poc.sh --abi arm64-v8a --rust-target aarch64-linux-android \
  --goarch arm64 --api-level 29 --src-cache <dedicated>/srccache --out <dedicated>/out/arm64-v8a
```

| Stage | Status | Evidence |
| --- | --- | --- |
| [1/4] zeptun (vendored patch, wrapper) | **Pass** | fresh full run: ndk-build + `zig build android`; exported `libzeptun.so` (275 800 B), `libzeptun.a` (358 152 B), `libzeptun-jni.so` (281 848 B); export guard (exactly 3 files) passed; `nm -D` on BOTH .so: `zeptun_update_routes` + `zeptun_set_flow_callback` (+ `JNI_OnLoad` in the JNI bridge); ELF `ARM aarch64 … for Android 29, built by NDK r26d`, 16 KiB alignment. Two sandbox-side extract defects of the NDK (lost exec bits/symlinks; a missing `linux/aarch64` runtime subdir) were found and fixed in the extract script — the pinned build itself was untouched. |
| [2/4] aether @ d58f9d56 | **Blocked (environment — RAM)** | three kernel OOM kills of the SAME rustc unit (aether's in-tree `quiche v0.29.3`, release profile `lto=fat codegen-units=1`): dmesg `anon-rss ≈ 3.42–3.45 GB` while total RAM is 3.95 GB — the unit needs more memory than the host has, even effectively solo (attempt 3's OOM dump shows no competing clang/cmake). Scheduling-only mitigations applied and exhausted: `CARGO_BUILD_JOBS=1`, `CMAKE_BUILD_PARALLEL_LEVEL=1`. Output-changing mitigations (LTO off) were REJECTED as violations of the frozen recipe. All other aether-tree units compiled; boringssl's cmake completed; the failing unit is deterministic. CI (16 GB runners) builds this pin routinely — run 44086964453 (below) proves it. |
| [3/4] lyrebird @ fc105a03c0e0 | **Pass** (script-exact commands; see D17) | the fail-fast `build_native.sh` aborts at the aether stage, so stages 3–4 were run with the script's EXACT commands (same pins, same patched `pt-build.sh`, sha256 `3fbee02f…` verified, same env + guards). Proxy path (gitlab unreachable from the sandbox): zip verified against sum.golang.org (h1:uzPZpf45…), signed record verified by the official Go client (GOSUMDB), zip byte-identity proven; built with go1.26.3 → ARM aarch64 static ELF, sha256 `44cfb2f17016fad4863abd0ffeff17c8405e9c113401a70b9382bd1add7aa36e`. **Real defect found (D17)**: the patched pt-build.sh proxy path dies at `rm -rf "$goverify"` — Go's module cache is read-only, so under `set -e` the build aborts AFTER verification succeeded. This path never ran on CI (runners reach gitlab → git path). Proposed fix: `chmod -R u+w` before the rm. |
| [4/4] psiphon @ 2956a96b | **Pass** (script-exact commands) | pin checkout verified; `GOOS=linux GOARCH=arm64 CGO_ENABLED=0 GOFLAGS=-mod=vendor GOTOOLCHAIN=local go build -trimpath -ldflags "-s -w"` → sha256 `a26424ea1228a0cbe105afdcf5406b2dc7a32dfd07c1e942cc27e58a5bcc8660` — **byte-identical to the CI artifact of run 44086964453** (the frozen recipe's own manifest) — a strong reproducibility proof for this sandbox's Go build. |

## aether closure for the APK — the project's own CI artifact (documented deviation)

`libaether.so` (aether @ d58f9d56, unchanged by the PoC) was taken from the
project's OWN Actions artifact of the SAME frozen recipe — run `44086964453`
("AETHONE Native CI", branch `ci-bootstrap/v4.4` @ `fbae94d`, workflow_dispatch,
success, 2026-11-17): `native-arm64-v8a` artifact id `14329444462`. Verified
against its embedded `manifest.json` (pins aether `d58f9d56`, zeptun `08a1ab05`,
psiphon `2956a96b`, lyrebird `fc105a03c0e0` git-path-proven), file hash matches
the manifest (`6392090cfa10034bedd18db8811385e4f050cfcd2edea220213b403e6b28be7c`),
ELF ARM aarch64 for Android 29 built by NDK r26d, NEEDED = libdl/libm/libc only.
Artifact-based native staging is the project's own APK architecture (both CI
workflows assemble jniLibs from Actions artifacts).

## PoC debug APK (brief §6) — DELIVERED, all gates PASS

jniLibs staged per the frozen recipe (`android/app/src/main/jniLibs/arm64-v8a/`,
gitignored, no pre-existing files overwritten): `libzeptun-jni.so` + `liblyrebird.so`
+ `libpsiphon.so` (this round's local builds, hashes match sources) + `libaether.so`
(CI artifact above). Deviation (disk): the sandbox cannot hold gradle's final
merge→strip→package staging (the debug engine alone is 395 MB unstripped + a
248 MB Vulkan layer; AGP's staging peaks ~1.3 GB beyond the installed toolchain).
Every compile/link/dex/resource/manifest task is GREEN through gradle; the final
packaging was assembled from exactly those intermediates (AGP's own
`linked-resources-binary-format` .ap_ for manifest+resources, `mergeDebugAssets`
output, all dex buckets — native multidex, minSdk 24, the 8 resolved native libs,
`llvm-strip` from the pinned r28c — exactly what AGP's StripDebugSymbolsTask runs),
zip-aligned (4-byte STORED entries; .so DEFLATED, legal for
`android:extractNativeLibs="true"` which this app sets via `useLegacyPackaging`
because it execs the Go binaries) and signed with the project debug keystore —
the canonical zipalign-then-sign order.

| Gate (the project's own) | Result |
| --- | --- |
| Archive validity | PASS (`zipfile -t`) |
| `zipalign -c -P 16 -v 4` | **PASS** (pre- and post-sign) |
| `apksigner verify --print-certs` | **PASS** (debug keystore CN=Android Debug — test install only) |
| `aapt dump badging` | `package: name='com.chakcaad.aethone.da'` (DA variant, installs beside the main app), `application-label:'AETHONE DA'`, `native-code: 'arm64-v8a'` only, minSdk 24 / targetSdk 36 |
| Native libs in APK | all 8 present: libaether, liblyrebird, libpsiphon, libzeptun-jni, libflutter, libVkLayer_khronos_validation, libdartjni, libdatastore_shared_counter |
| **PoC symbols in the packaged binary** | `llvm-readelf --dyn-symbols` on the in-APK `libzeptun-jni.so`: `zeptun_update_routes`, `zeptun_set_flow_callback`, `JNI_OnLoad` all exported |
| APK | `AETHONE-PoC-Stage2.1-arm64-debug.apk` — 73 988 586 bytes, sha256 `53ff2a778900f24d0d76140658c1d29e2834e513f0a72709cf8e38339bdd080b` |

## Device round (brief §7) — NO DEVICE

`adb devices -l` → none attached (the sandbox has no device). Per the brief,
emulator results are NOT substituted. Tests A–H remain **Blocked (no device)** —
procedures unchanged (§Device procedure). The APK is delivered for the owner's
hardware round.

## Supply-chain rules honored

No pin, workflow, `build_native.sh` default path, or product file changed. The
wrapper safety suite re-run in this round: 0 FAIL (23 PASS lines, suite summary
"ALL CHECKS PASSED"). `pubspec.lock` (modified by `flutter pub get`) reverted to
the committed baseline after the build. No APK, keystore, or secret committed;
build logs stay out of the repo (distilled above + kept on the build host under
`.toolchain/evidence/`). The aether-stage toolchain pieces (rust/cargo, zig, the
r26d NDK) were removed after their stages closed, purely for disk — every piece
is re-downloadable from the recorded, checksum-verified sources.

## Stage 2.1 round-2 verdict

**Toolchain: complete and exact. Native: 3 of 4 stages Pass (zeptun, lyrebird,
psiphon — the last two via the script's exact commands after the fail-fast
aether abort); aether Blocked by sandbox RAM (deterministic OOM, evidence
recorded); its cdylib for the APK taken from the project's own same-pin CI
artifact. APK: built and gated (zipalign + apksigner + badging + in-APK PoC
symbols), delivered for the device round. Device tests: Blocked (no device).
Stage 3 remains gated on the owner's acceptance of the evidence.**

# Stage 2.1 round 3 — sandbox-recycle recovery & re-delivery (2026-11-18)

Between rounds 2 and 3 the build sandbox was recycled: the round-2 deliverable
APK (download area), `.toolchain/per-app-routing-stage2.env` + `evidence/`,
`scripts/stage21/` and the `aethone-stage21` worktree were lost; the pushed
branch (docs + hashes) and the round-1 zeptun export under `poc-out/`
survived. This round restores the deliverable from verified sources only.

## What was recovered, from where

| Piece | Source | Verification |
| --- | --- | --- |
| Toolchain | reinstalled at the exact pins: Flutter 3.47.9 (git clone @ tag, framework `c197ca5199` == the recorded archive hash), JDK Temurin 17.0.21+9 (release-metadata sha256), SDK platform-36/build-tools 36.0.0/platform-tools, NDK r28c `28.2.13676358` (= `flutter.ndkVersion`, for `:jni`'s cmake build + AGP's strip task) | fresh-install checks |
| `libzeptun-jni.so` | the SURVIVING local PoC export (`poc-out/arm64-v8a/zeptun/`) | sizes exact-match the round-2 record (275 800 / 358 152 / 281 848 B); `nm -D` PoC symbols; ELF `ARM aarch64 … for Android 29, built by NDK r26d`; staged sha256 `1a31fa211e149282a16d676450819da7ad3cc2eaaa27f6eec712a45a375f524c` |
| `libaether.so` / `libpsiphon.so` | the SAME CI artifact `native-arm64-v8a` id 14329444462 (run 44086964453) re-downloaded via the Actions API | all 7 files match the artifact's embedded `manifest.json` sha256s; libaether `6392090c…` == the round-2 record; psiphon `a26424ea…` == the round-2 LOCAL build (byte-identical — the round-2 reproducibility proof) |
| `liblyrebird.so` | CI artifact (git path) — **documented substitution** for the lost round-2 proxy-path local build (`44cfb2f1…`) | same pin `fc105a03c0e0`; the git-path binary carries the pin in `vcs.revision` (grep-proven in-binary); sha256 `5164d8f9…` per manifest |
| Gradle build | full `flutter build apk --debug --target-platform android-arm64` on the exact pins in the re-created `aethone-stage21` worktree | every compile/dex/resource/asset/jni task GREEN; gradle's own `packageDebug` produced a valid APK — the build was marked FAILED only by the post-build problems-report write on a full disk |

Environment-level deviations (no repo file touched): the daemon was sized for
this 3.9 GB host via `GRADLE_USER_HOME/gradle.properties` (`org.gradle.jvmargs=-Xmx2200m…`
beats the project file by Gradle's documented precedence — the repo's `-Xmx8G`
gets the daemon kernel-OOM-killed, dmesg-recorded); disk was reclaimed only
from re-downloadable caches (gradle transform cache, wrapper zip, the
go1.25.0 tree of the wrong version, the artifact zip after extraction).

## Final assembly (D19 method, round-3 edition) — ALL GATES PASS

gradle's valid APK repacked to the round-2 deliverable shape (arm64-v8a ONLY —
dropping the `:jni` module's `armeabi-v7a`/`x86_64` extras — and the old
signature files), then `zipalign -f -P 16 4`, then `apksigner` with the project
debug keystore.

| Gate | Result |
| --- | --- |
| Archive validity | PASS (`zipfile -t`, 900 entries) |
| `zipalign -c -P 16 -v 4` | **PASS** (pre- and post-sign) |
| `apksigner verify --print-certs` | **PASS** (CN=Android Debug — test install only; NEW debug key: the round-2 keystore was lost with the recycle, so the signature necessarily differs) |
| `aapt dump badging` | `package: name='com.chakcaad.aethone.da'`, `versionName='1.0.0-da'`, `application-label:'AETHONE DA'`, `native-code: 'arm64-v8a'` only, minSdk 24 / targetSdk 36 |
| Native libs in APK | all 8 present: libaether, liblyrebird, libpsiphon, libzeptun-jni, libflutter, libVkLayer_khronos_validation, libdartjni, libdatastore_shared_counter |
| **PoC symbols in the packaged binary** | `nm -D` on the in-APK `libzeptun-jni.so`: `zeptun_update_routes`, `zeptun_set_flow_callback`, `JNI_OnLoad` all EXPORTED |
| APK | `AETHONE-PoC-Stage2.1-arm64-debug.apk` — 74 068 982 bytes, sha256 `95e71815398d2753cf2c0de0b9ec31cbfaa7cff5fd4cde753f8c8b905b7dfd8f` |

### In-APK native-lib provenance (round 3)

- `libzeptun-jni.so` == the staged PoC build, **byte-identical** (`1a31fa21…`).
- `liblyrebird.so` / `libpsiphon.so` == `llvm-strip` (r28c) of the staged
  hash-verified inputs, **byte-identical** (`ed463246…` / `87545330…`).
- `libaether.so` = AGP's own `stripDebugDebugSymbols` output of the staged
  input `6392090c…`: same size, identical program headers and section list;
  the 257 differing bytes are confined to the ELF section-header tail.
- `libflutter.so` (38.8 MB) + `libVkLayer_khronos_validation.so` (15.2 MB) =
  AGP-stripped flutter debug-engine artifacts of the pinned engine
  `89c39edfdfae…` (the 395 MB + 248 MB unstripped originals never enter the
  APK — exactly the round-2 finding).

Differences from the round-2 APK (`53ff2a77…`, 73 988 586 B) are: the new
debug key, zip re-compression, and the lyrebird substitution above — every
component is provenance-verified against its recorded source hash.

## Device round (unchanged)

No device/adb in the environment; Tests A–H remain **Blocked (no device)**.
The re-delivered APK is for the owner's hardware round (procedures:
§Device procedure).

## Supply-chain rules honored

No pin, workflow, `build_native.sh` default path, or product file changed.
`pubspec.lock` reverted to the committed baseline after the build (same
pub-get drift as round 2: dev-only transitive `test_api`/`listen`). No APK,
keystore, or secret committed; build logs distilled above and kept on the
build host (`.toolchain/evidence/`, `.toolchain/round3/`). Assembly scripts:
`scripts/stage21/stage-jnilibs-round3.sh`, `scripts/stage21/repack_apk_round3.py`,
`scripts/stage21/assemble_final_apk_round3.sh` (build-host side, not the repo).

## Stage 2.1 round-3 verdict

**Deliverable restored: the PoC debug APK re-built from verified sources
(surviving PoC zeptun export + the project's own same-pin CI artifact + the
exact-pin Flutter/Gradle toolchain), re-gated end to end (zipalign, apksigner,
badging, in-APK PoC symbols) and re-delivered with a fresh debug signature.
Native-stage conclusions of round 2 stand unchanged (zeptun/lyrebird/psiphon
Pass, aether RAM-blocked with the CI-artifact closure). Device tests remain
Blocked (no device). Stage 3 remains gated on the owner's acceptance.**

# Stage 2.1 round 4 — the device-test entry point (2026-11-18)

The owner's task found a REAL defect in this document's device procedure: it
started `AethoneVpnService` directly through
`adb shell am start-foreground-service -n com.chakcaad.aethone/.AethoneVpnService`.
That command could never work as written, for three independent reasons:
(1) the DA debug APK's application id is `com.chakcaad.aethone.da`, not
`com.chakcaad.aethone`; (2) `AethoneVpnService` is `exported=false` — an
external `am` start from the shell uid is a permission denial by design (the
service must only ever be started by the app itself or bound by the system);
(3) `PoCRoutesReceiver` is the LIVE-update/stats surface only — it cannot
start the initial PoC route session. This round delivers the correct entry
point and rewrites §Device procedure accordingly.

## Implementation (D20 — see DECISIONS.md)

`PoCControlActivity` — a debug-only, adb-addressable, content-less
(translucent) activity that starts the service FROM THE APPLICATION'S OWN UID:

- **Source sets**: class + its pure input spec (`PoCControlStartSpec`) live in
  `android/app/src/debug/kotlin/` — the debug variant's source set. Declared
  ONLY in `android/app/src/debug/AndroidManifest.xml`. Neither the class nor
  the component exists in release/profile builds (verified below, and by
  construction: AGP never compiles `src/debug` into other variants).
- **Launch** (explicit component, no intent-filter — implicit resolution
  cannot reach it): `adb shell am start -n
  com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity --ei port
  1819 --es poc_routes '<json>' [--ez tcpOnly true] [--ez socksStrict true]`.
  Fully-qualified `android:name` makes the component suffix-safe; `am start
  -W` gets the activity result (ok = start delivered, canceled = rejected
  with the reason on logcat).
- **Contract**: `port` optional (default 1819, validated 1..65535 when
  present); `poc_routes` REQUIRED (the entry point exists only for
  route-instrumented starts — a plain tunnel is the app UI's job); the
  document is validated by the SAME `PoCRoutes.parse` the service start path
  and the update broadcast use (one parser, no second opinion). A malformed
  document is rejected BEFORE anything starts.
- **Consent gate**: `VpnService.prepare(this)` must return null (consent
  already standing, granted once through the app UI) — otherwise a clear
  failure is logged and NOTHING starts. The activity never raises the
  consent dialog itself.
- **Start**: `startForegroundService` with exactly the documented extras
  (`port`, `tcpOnly`, `socksStrict`, `poc_routes`) — no session stamp, no
  per-app pick: an external start, precisely like the adb command it
  replaces. The service's own already-running/restart semantics are
  untouched (a changed route document restarts the tunnel, as before).
- **Logging**: validation, consent, the actual start result and the live PoC
  token are logged under the existing `AethonePoC` tag (the token read is a
  new read-only in-process companion accessor `currentPocToken()` — no IPC
  surface, no guard weakened; the receiver's token check and the
  per-instance regeneration are untouched).
- **Untouched**: `AethoneVpnService` stays `exported=false` with
  `android.permission.BIND_VPN_SERVICE`; the routing algorithm, Zeptun,
  route numbering and default behavior are not modified;
  `POC_UPDATE_ROUTES`/`POC_ROUTES_STATS` keep their token protection.

## Automated tests (brief: "malformed and valid route-start documents")

`:app:testDebugUnitTest` — `PoCControlStartSpecTest` (JUnit 4, JVM; test-only
deps `junit:junit:4.13.2` + `org.json:json:20240303`, the real JVM artifact
behind Android's org.json — neither reaches any APK): **24/24 PASS**
(0 failures, 0 errors, 0 skipped, 0.079 s):

| Group | Cases |
| --- | --- |
| Valid documents | canonical 2-route document with an assignment (defaults: port 1819, flags false); explicit port + flags; port boundaries 1/65535; empty routes list; strict-flag socks5 entry |
| Spec-level rejections | absent `poc_routes`; blank `poc_routes`; port 0; port 65536; wrong-typed port extra (sentry −1) |
| Malformed documents | not-JSON; unknown kind; socks5 without server; server without port; non-numeric port; direct carrying a server; duplicate ids; empty/whitespace id; >8 routes; assignment to unknown route |
| Forwarding contract | spec extra keys == `AethoneVpnService.EXTRA_*`; spec default port == the service's; the ADB component string is the DA package + FQ class |

## Manifest / variant verification (all on the REAL builds)

| Check | Result |
| --- | --- |
| DA debug APK merged manifest (`aapt dump xmltree`) | `PoCControlActivity` PRESENT, `exported=0xffffffff` (true), no intent-filter |
| DA debug APK dex | `PoCControlActivity` + `PoCControlStartSpec` present |
| `AethoneVpnService` in the DA debug APK | `exported=0x0`, `android.permission.BIND_VPN_SERVICE` — unchanged, not weakened |
| `PoCRoutesReceiver` in the DA debug APK | exported, both actions (`POC_UPDATE_ROUTES`/`POC_ROUTES_STATS`) intact — the update/stats broadcasts continue to work as before |
| Release merged manifest (`processReleaseMainManifest`) | `PoCControlActivity`/`PoCControlStartSpec`: ZERO occurrences; `AethoneVpnService` still exported=false + BIND_VPN_SERVICE; receiver intact |
| Release APK (`assembleRelease`, `aapt` + dex scan) | package `com.chakcaad.aethone` (no DA suffix), activity absent from manifest AND from every dex bucket; `AethoneVpnService`/`PoCRoutesReceiver` present as always — no test-start entry point in the production variant |
| Component/launch command | the unit test pins `com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity`; the merged manifest confirms the component resolves in the DA package. The `adb shell am start` itself needs a device — with the environment's no-device rule, that execution is **Blocked (no device)** and is NOT claimed |

## Build (round 4)

Toolchain reinstalled at the exact pins after another sandbox recycle
(round-2/3 method): JDK Temurin 17.0.21+9 (Adoptium v3-API sha256 verified,
`8b9b611d…`), SDK platform-36 + build-tools 36.0.0 + cmdline-tools, Flutter
3.47.9 (git clone @ tag, framework `c197ca5199`), NDK r28c `28.2.13676358`
(= `flutter.ndkVersion`, for the `:jni` cmake build + AGP's strip task).
jniLibs re-staged from the hash-verified round-3 deliverable APK itself
(`95e71815…` re-verified before extraction; staged libzeptun-jni.so
byte-identical to the pinned PoC export `1a31fa21…`; aether/psiphon/lyrebird
staged as the exact in-APK bytes round 3 shipped — hashes recorded in
`.toolchain/round4/`).

Environment-level deviations (no repo file touched; same classes as
rounds 2/3): `GRADLE_USER_HOME` daemon sized `-Xmx2200m` for the 3.9 GB
host; a `GRADLE_USER_HOME/init.d` mirror prepend (Aliyun public proxies of
Maven Central/google/gradle-plugin-portal, canonical repos kept as
fallback) because repo.maven.apache.org 429-throttled the sandbox IP's
parallel resolution bursts; disk-bounded reclaims of re-derivable caches
only (gradle transforms, the round-2-precedent selective NDK extract —
this round additionally dropping the fat host-side debugger/analysis
tooling lldb/clangd/llvm-bolt etc. and non-arm32/x86 compiler-rt, 972 MB
final — plus the superseded local copy of the round-3 APK whose bytes are
hash-pinned here and staged as jniLibs); `assembleRelease` run with
`-x :app:extractReleaseNativeSymbolTables` (a Play-upload side artifact,
not an APK input — the release APK itself is complete and verified).
`pubspec.lock` reverted to the committed baseline after the builds (the
same pub-get drift as rounds 2/3).

## PoC debug APK (round 4) — DELIVERED, all gates PASS

Final assembly = the D19 method, round-4 edition: arm64-v8a-only repack of
gradle's own valid debug APK (dropping the `:jni` module's armeabi-v7a/
x86_64 extras and the old signature files), `zipalign -f -P 16 4`,
`apksigner` with the round-4 debug keystore (fresh key, same situation as
round 3 — gradle generated it for this build).

| Gate | Result |
| --- | --- |
| Archive validity | PASS (`zipfile -t`, 900 entries) |
| `zipalign -c -P 16 -v 4` | **PASS** (pre- and post-sign) |
| `apksigner verify --print-certs` | **PASS** (CN=Android Debug, round-4 key `e77479b4…`) |
| `aapt dump badging` | `com.chakcaad.aethone.da`, `versionName='1.0.0-da'`, label AETHONE DA, `native-code: 'arm64-v8a'` only, minSdk 24 / targetSdk 36 |
| Native libs | all 8 present (aether, lyrebird, psiphon, zeptun-jni, flutter, VkLayer, dartjni, datastore_counter) |
| **PoC symbols in the packaged binary** | `llvm-readelf --dyn-symbols` on the in-APK `libzeptun-jni.so`: `zeptun_update_routes`, `zeptun_set_flow_callback`, `JNI_OnLoad` all exported |
| **Round-4 entry-point gates** | `PoCControlActivity` in the final manifest (exported=true) AND in the dex; `AethoneVpnService` exported=false + BIND_VPN_SERVICE; receiver actions intact |
| APK | `AETHONE-PoC-Stage2.1-arm64-debug.apk` — 74 073 078 bytes, sha256 `83bd544cc804c7592464cdde97b3715d799f353c7052472308b3dbafd5340e5e` |

## Device round (unchanged)

No device/adb in the environment; Tests A–H remain **Blocked (no device)**.
The round-4 APK is for the owner's hardware round via the corrected
§Device procedure. Stage 3 remains gated on the owner's acceptance.

## Stage 2.1 round-4 verdict

**The device-test entry point is fixed and proven at every level this
environment can prove: the documented procedure no longer asks the owner to
run an impossible command; the debug-only activity is implemented,
automated-tested (24/24), manifest- and dex-verified present in the DA
debug APK and absent from the release variant; the VPN service's
non-exported posture and the receiver's token guard are byte-level
unchanged. A new gated PoC APK is delivered (round-4 key). Device tests
remain Blocked (no device) — the completion gate's device-dependent items
stay unmet and Stage 3 remains forbidden until the owner accepts the
evidence.**
