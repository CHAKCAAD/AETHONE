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

---

# Stage 2.1 decisions — 2026-11-18

## D15 — Wrapper cleanup invariant: own-only deletion, subprocess execution, preserved exit codes

The first PoC cut of `build_native_poc.sh` had two confirmed safety defects: `exec`
replaced the wrapper shell so its EXIT trap never ran (the scratch copy leaked on
every run), and the trap's `rm -rf "$POC_SRC_CACHE"` could delete a caller-supplied
pre-existing path whenever the script exited between trap installation and the exec
(a `cp` failure was the reachable case — reproduced with a sentinel file).

The fix (verified by `scripts/test_build_native_poc.sh`, 24 checks): the child
`build_native.sh` runs as a SUBPROCESS and the wrapper exits with the child's exact
status; cleanup only ever removes `POC_SCRATCH_DIR`, a directory the run itself
created via `mktemp` (fresh by construction — ownership provable); `POC_SRC_CACHE`,
when set, is honored solely as the parent into which that fresh scratch dir is placed
(created if missing, never deleted); INT/TERM chain into the cleanup. This
own-only-deletion invariant is binding for any future wrapper in this repo.

## D16 — Bounded per-package attribution logging iterates in-scope package names

The first real Kotlin compile caught `PerAppRouteResolver.kt:198` referencing a loop
variable out of scope (`Unresolved reference 'pkg'`). The corrected block iterates
the uid's package list inside its scope, preserving the documented semantics: one log
line per NEW package name, at most 64 lines, package names never printed to logcat
(privacy rule). No behavior beyond the logging block changed.

## D17 — pt-build.sh proxy-path defect: the verification cleanup kills the build (found in Stage 2.1 round 2)

The pin-hardened `pt-build.sh` (v4.2) proxy path — which the patch notes say was
never executed on CI, because GitHub runners reach gitlab and take the git path —
ends its official-Go-client sumdb verification with `rm -rf "$goverify"`. Go
deliberately makes the module cache READ-ONLY (directories r-x), so that rm fails
with "Permission denied" and `set -euo pipefail` aborts the whole build AFTER the
verification already succeeded. Reproduced deterministically in the Stage 2.1
round-2 sandbox (gitlab unreachable there → proxy path forced).

Proposed fix (NOT applied — build scripts are frozen for Stage 2.1):
`chmod -R u+w "$goverify" 2>/dev/null || true` before each `rm -rf "$goverify"`,
or `go clean -modcache` semantics for a disposable GOMODCACHE. The round-2 run
completed the lyrebird build by applying exactly this fallback at the ENVIRONMENT
level (a scoped PATH shim), leaving the pinned script byte-identical
(sha256 `3fbee02f…` verified before execution).

## D18 — Stage 2.1 round 2: aether is RAM-blocked in the 4 GB sandbox; the APK's libaether.so comes from the project's own same-pin CI artifact

The aether stage (aether @ d58f9d56, unchanged by the PoC) cannot compile in the
sandbox: the same rustc unit (the in-tree `quiche` crate, release profile
`lto=fat codegen-units=1`) was OOM-killed three times at ~3.42–3.45 GB anon RSS on
a 3.95 GB host, even with `CARGO_BUILD_JOBS=1` and `CMAKE_BUILD_PARALLEL_LEVEL=1`
(scheduling-only; output-identical). Output-changing mitigations (disabling LTO)
were explicitly rejected — the frozen recipe is not negotiable for the PoC evidence.

For the PoC APK, `libaether.so` was therefore taken from the project's OWN Actions
artifact of the SAME frozen recipe (run 44086964453, `ci-bootstrap/v4.4` @
`fbae94d`, native-arm64-v8a): manifest pins verified, hash matched, ELF/NDK-r26d
checks passed. Artifact-based native staging is the project's own APK architecture
(both CI workflows do it). The three other packaged cores are this round's local
builds; psiphon is byte-identical to the CI manifest (reproducibility proof).

## D19 — Stage 2.1 round 2: final APK packaging assembled from gradle's own intermediates (disk-bounded deviation)

The sandbox disk (9.9 GB, ~4 GB pre-existing) cannot hold AGP's final
merge→strip→package staging for a debug build whose engine artifacts alone are
395 MB + 248 MB unstripped. All compile/link/dex/resource/manifest tasks ran green
through gradle; the final zip was assembled from exactly those intermediates
(AGP's `.ap_` resources package, merged assets, all dex buckets as native
multidex, the 8 resolved native libs — engine + datastore libs `llvm-strip`-ed
with the pinned r28c tool, exactly what AGP's StripDebugSymbolsTask does),
zip-aligned (4-byte STORED entries; .so DEFLATED — legal for
`android:extractNativeLibs="true"`, which this app requires anyway because it
execs the Go binaries from nativeLibraryDir) and signed with the debug keystore
in the canonical zipalign-then-sign order. All of the project's own packaging
gates pass (§ round-2 POC_RESULTS). On a normal disk, plain
`flutter build apk --debug --target-platform android-arm64` reproduces this APK
through gradle alone.

## D20 — Stage 2.1 round 4: the device-test entry point is a debug-only `PoCControlActivity`, never an exported service

The round-0 device procedure told the owner to run
`adb shell am start-foreground-service -n com.chakcaad.aethone/.AethoneVpnService …`
— a command that could never work: the DA APK's application id is
`com.chakcaad.aethone.da`, the service is `exported=false` (an external am
start is a permission denial — correctly so, the VPN service must not be
startable by other UIDs), and `PoCRoutesReceiver` only drives live
updates/stats on a running PoC tunnel, not the initial session.

The fix is a dedicated debug-only activity, chosen over the alternatives on
purpose:

- **Not an exported `AethoneVpnService`**: opening the VPN service to other
  UIDs (or weakening `BIND_VPN_SERVICE`) is a production-security regression
  for a test convenience — rejected outright.
- **Not the receiver**: it is the live-update/stats surface with its own
  token contract; overloading it with session starts would blur the one
  responsibility it documents, and it holds no consent gate.
- **`PoCControlActivity` it is**: declared ONLY in
  `android/app/src/debug/AndroidManifest.xml`, implemented ONLY in
  `android/app/src/debug/kotlin` — the release/profile variants contain
  neither the component nor the class (AGP never compiles debug sources
  into them; verified on the built release APK's manifest and dex). The
  activity validates `port`/`poc_routes`(+`tcpOnly`/`socksStrict`) through
  the same `PoCRoutes.parse` authority the service uses, refuses to start
  without the standing VPN consent (`VpnService.prepare` == null — granted
  once through the app UI), then starts the service from the application's
  own UID with exactly the documented extras. Translucent + content-less +
  `noHistory`/`excludeFromRecents`: no UI trace, and `am start` puts the
  process in the foreground, which is what makes the foreground-service
  start legal on API 26+.

The token is now also readable in-process (read-only companion accessor
`AethoneVpnService.currentPocToken()`) so the entry point can log the start
result and the token under the existing `AethonePoC` tag — no IPC surface,
no guard weakened; the receiver's token check and the per-instance
regeneration are untouched. The launch contract is pinned by
`PoCControlStartSpecTest` (24/24): extra keys equal the service constants,
and the ADB component is `com.chakcaad.aethone.da/com.chakcaad.aethone.PoCControlActivity`.
