# Per-App Routing — PROGRESS

## Current phase

**Stage 2 (Core PoC): IMPLEMENTED — host-proven, awaiting the owner's review and the
device round.** Nothing committed or pushed (all changes live in the working tree).
Stage 3 must not start until the owner accepts the PoC evidence.

## Repository state

- Branch `fix/owner-round-2`, HEAD `5502d34` + uncommitted Stage-2 changes
  (17 modified files, 5 new files — inventory in POC_RESULTS.md §Build).
- Vendored `native/zeptun/` was byte-identical to pin 08a1ab0 before the patch
  (verified by full diff against a fresh clone of the pin).

## Key facts (Stage 2, verified)

1. Route table: optional `[routes]` section (parallel lists, TOML+JSON); route 0 =
   the default/global handler; entries 1..N positional. Absent section = old behavior.
2. Flow-owner callback: the EXISTING `zeptun_set_flow_callback`, return contract
   extended to `(route << 2) | action` (legacy 0..3 = default route — byte-compatible).
   Installed only on PoC starts (`nativeStart`'s new `flowCallback` flag).
3. Callback fires once per NEW flow (TCP SYN / first UDP / first DNS of a flow) —
   the UDP session lookup precedes the DNS branch so it is never per-packet.
4. Per-flow selection: Dial carries `upstream`/`strict` (TCP) and UdpState
   `bypass`/`ctrl.upstream` (UDP); warm pool serves the default route ONLY.
5. Live updates: `zeptun_update_routes` (new C symbol) validates fully, swaps the
   engine table under a lock; existing flows keep their exits; invalid docs rejected.
6. Direct + fake-IP DNS: the asking app's queries are forwarded to `dns.upstream`
   (system DNS on PoC starts); a direct flow still carrying a fake IP FAILS CLOSED
   (`route_direct_fake`), never silently tunneled.
7. Latent upstream bug fixed: `bypass` UDP under a socks5 handler used to
   SOCKS-frame raw datagrams (udpSend/flushTx/deliverBatch keyed off the global kind).
8. Kotlin: `PerAppRouteResolver` (bounded 50 ms query, deterministic shared-UID rule,
   metrics), adb-only `EXTRA_POC_ROUTES` start extra, token-guarded
   `PoCRoutesReceiver` (live update + stats dump). No Dart/UI changes.
9. Tests: `zig build test` — 118/126 (8 pre-existing skips), baseline 109/117 →
   zero regressions, 9 new tests incl. six engine-level per-flow fixtures with
   independently observable exits. JNI C compiles clean (-Wall -Wextra -Werror).

## Completed this stage

- [x] Mandatory prep: repo re-verified vs the Phase-1 audit; zeptun flow/handler/JNI/
      protect/DNS paths re-read from source (no stale assumptions used).
- [x] Zig: routes config + validation, verdict packing, engine route storage + atomic
      update, per-flow dial/UDP selection, pool isolation, fail-closed, DNS forward.
- [x] JNI bridge: flow-route callback + nativeUpdateRoutes (compile-checked).
- [x] Kotlin: resolver, service wiring, PoC instrumentation, manifest receiver.
- [x] Host test program green (3× repeat runs — no flakes).
- [x] Build path: `ZEPTUN_LOCAL_SRC` gate + `build_native_poc.sh` (default CI recipe
      untouched).
- [x] Docs: ARCHITECTURE §8, DECISIONS D10–D14, POC_RESULTS.md (honest statuses).

## Remaining (blocked on owner)

- [ ] Owner review of the Stage-2 evidence (POC_RESULTS.md).
- [ ] Device round: Tests 1–7 device items, performance measurements, regression
      (procedure in POC_RESULTS.md §Device procedure) — no device in this environment.
- [ ] Android compile of the Kotlin (no SDK here; CI or owner's machine).
- [ ] Decision: fork-pin the patched zeptun or upstream it (D14) — needed before any
      CI build of the PoC APK can ship.

## Known blockers

- No physical Android device (all device tests Not tested, honestly reported).
- No Android SDK/NDK in the analysis environment (Kotlin compile pending CI).
- `dns.upstream` fixed at start: a live update cannot INTRODUCE a direct route
  without one present at start (restart required) — documented D12.

## Next exact action

Owner: review `POC_RESULTS.md`. If the host evidence is accepted as sufficient for
Stage 2, run the device procedure (POC_RESULTS.md §Device procedure) on hardware with
a PoC APK built via `scripts/build_native_poc.sh`; record the device results back
into POC_RESULTS.md. Stage 3 (UI) starts only after the gate closes.
