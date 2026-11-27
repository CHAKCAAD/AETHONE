# Family Shield (parental control) — phase 1 + phase 2

Status: **phase 2 on branch `feature/family-shield-phase2`: method-channel API, real-state status,
loopback accept-gate PoC, signing-key rotation, settings export/import, emulator e2e. No UI (phase 3 not
approved); no real device used; not merged, not released.** Phase 1 below is unchanged history.

Phase-2 docs: [channel API](family-shield-channel.md) · [key rotation](signing-key-rotation.md) ·
[settings migration](settings-migration.md); security §5/§8, testing §5, release §4 updated.

## Phase 2 deliverables (2026-11-26, status updated 2026-11-27)

Three states only: **Implemented & Tested** (host/JVM/Zig tests and/or the CI x86_64 emulator — never a
real device) · **Implemented Not Fully Tested** · **Not Implemented**. Evidence: native-ci run
46006344077 @ `6eaddf5`, testing §5.

| # | Item | Status | Evidence / gap |
|---|---|---|---|
| 1 | Method channel `aethone/family_shield` (enable/disable, status, profiles, rules, PIN-session gating, events, export/import) | Implemented Not Fully Tested | ShieldAdmin JVM-tested; `ShieldChannel.handle` driven on the emulator; the Dart side of the channel never invoked (no UI) |
| 2 | VpnService + zeptun wiring: DNS NXDOMAIN, uid app blocking before the SOCKS dial, live snapshot swap + `zeptun_revalidate_flows`, batched events; shielded start refused if the engine hook is missing | Implemented & Tested | emulator: NXDOMAIN, uid block/release, live swap, cached fake IP refused, revalidation ≤ 1 s, fail-closed start; event batching JVM-only |
| 3 | Status from real state: Protected / Degraded / Inactive / Validation failed + reasons | Implemented & Tested | JVM (all states/reasons) + emulator (inactive → protected with the guarded stub only); Degraded with real cores not exercised on the emulator |
| 4 | Loopback SOCKS accept gate (getConnectionOwnerUid + own-process socket match, fail-closed) | Implemented Not Fully Tested | PoC passes on the emulator for the test stub (uid 2000/0 reset, own process + zeptun admitted); **not wired to the real cores 1819–1822** → they stay `local-socks-exposed`, never Protected |
| 5 | IPv6 capture validated by an engine counter (zeptun counter 7) | Implemented & Tested | emulator: v6 address on TUN, v6 TCP flow reached the tunnel, counter 7 = 815 |
| 6 | Per-app exclusion audit per app | Implemented Not Fully Tested | JVM-tested; emulator shows the whole-device case only |
| 7 | u32 counters: all count events (none count bytes); wrap test (Zig) + wrap-safe 64-bit Kotlin totals | Implemented & Tested | Zig wrap test + Kotlin; counters read back on the emulator |
| 8 | Signing-key rotation prep (secrets-only, least privilege, old-cert gate, docs) | Implemented & Tested | CI `release-signing` job signed with the owner's new key (run 46006344077: success) |
| 9 | Settings export/import + migration plan | Implemented Not Fully Tested | export JVM + emulator (2 profiles, no PIN); import via the picker not tested |
| 10 | Tests wired into native-ci.yml fail-closed | Implemented & Tested | ShieldPhase2Test gate, `shield-e2e` (35/35 PASS), `release-signing`, new Android seccomp gate in `elf-inspect` |
| — | Android seccomp safety of zeptun (no legacy `poll`/`open` syscalls) | Implemented & Tested | fix in the zeptun patch; `scripts/check_android_seccomp.py` gate; e2e ran without SIGSYS |

Real-device testing: **none** (see testing §4).

Read next: [architecture](family-shield-architecture.md) · [security](family-shield-security.md) ·
[content sources](family-shield-content-sources.md) · [testing](family-shield-testing.md) ·
[release](family-shield-release.md).

## What it is

An independent filtering layer inside AETHONE's tunnel mode. It answers blocked domain names with
NXDOMAIN, rejects blocked flows (TCP RST / ICMP unreachable) before any tunnel dial, blocks apps by
owner uid, and re-checks open connections when rules change. Rules come from age profiles (Toddler
3–7 allowlist-only, Child 8–12, Teen 13–15, Older teen 16–17, Custom — product presets, not an official
rating), a parent block/allow list, app restrictions and category lists. Mandatory security (malware,
phishing) is always on while the shield is on. Everything is stored and decided on the device.

Priority: 1 mandatory security > 2 parent locked blocklist > 3 app restrictions > 4 age categories >
5 parent allowlist (overrides categories only) > 6 unknown-domain policy.

## Deliverables status (phase 1)

| # | Deliverable | Status |
|---|---|---|
| 1 | Native policy engine, evaluated before HybridPolicy and any dial; single uid lookup; shield triggers the routed start | Implemented; Zig engine tests + Kotlin RouteGate tests; **not device tested** |
| 2 | Zig domain matcher (reversed-label hash, exact/root/subdomain/wildcard, boundary, IDN/punycode, v4/v6 CIDR) | Implemented + tested (Zig; cross-checked against the Kotlin builder) |
| 3 | Binary snapshot (versioned, SHA-256), built in Kotlin, fully validated, atomic hot-swap, bad snapshot refused | Implemented + tested (both sides) |
| 4 | DNS hook (NXDOMAIN, no SOA, no fake IP, no upstream; A/AAAA/HTTPS/SVCB) + flow-time re-check of fake-IP names | Implemented + tested (unit + engine) |
| 5 | App blocking by uid (Android 10+), never via allowed/disallowed app lists | Implemented; decision logic unit-tested; uid path **not device tested** |
| 6 | Flow revalidation (`zeptun_revalidate_flows`, JNI, header, R8 keep + dexdump gate) | Implemented; engine test (RST for the newly blocked flow, other flow untouched); JNI part not device tested |
| 7 | PIN core (PBKDF2 600k + salt, Keystore pepper, backoff, recovery code, session token, no default PIN, backup exclusion) | Implemented; core unit-tested; Keystore pepper **not device tested**; BiometricPrompt UI not implemented (evaluated, see security §6) |
| 8 | Kotlin SQLite storage (config, profiles, rules, app restrictions, events, PIN state, history) | Implemented; SQLite class compiled only (no instrumentation test); logic tested through the in-memory repository |
| 9 | Unit tests (Zig + Kotlin) wired into CI | Done (zig-test gate runs the patched tree; android-apk job runs `routing.*` + `shield.*`, fail-closed) |
| 10 | CI results | see the CI section below |
| 11 | Docs | these six files |
| 12 | Limitations / unverified | below |

## Bypass paths

* (A) local SOCKS listeners 1819–1822: **open** — no pinned core enforces SOCKS auth (Aether, Tor
  served by Aether, Psiphon goptlib, Lantern not wired). Not labelled protected; status Degraded
  `local-socks-unauthenticated`; tunnels untouched.
* (B) IPv6: captured while the shield is on (`::/0` + TUN v6 address); explicit Degraded status if the
  Builder refuses.
* (C) per-app tunneling exclusions: status Degraded `per-app-exclusions`.
* Strict mode (optional, off by default): DoT/DoQ 853, QUIC UDP/443, alternative DNS on 53, optional
  direct-IP block; Private DNS hostname mode detected (853 block dropped, Degraded).

## Limitations / unverified (honest list)

* **No device or emulator test of anything in this phase.**
* No UI and no channel API yet: the shield can not be switched on from the app until phase 2 (so the
  shipped behaviour of a build from this branch is unchanged unless the store is edited).
* SOCKS auth bypass (A) open for every tunnel.
* Android negative-cache behaviour for NXDOMAIN-without-SOA not observed on a device.
* IPv6 capture: zeptun carries IPv6 in unit/engine tests; the Builder + real IPv6 networks not tested.
* Category lists are not downloaded yet (pipeline only); snapshot size / RAM with real lists unmeasured.
* Revalidation of flows opened before the shield learned their uid (flow cache bounded to 4096 /
  30 min) keeps unknown flows.
* Normalization: Zig punycode has no IDNA mapping (e.g. `ß`); the Kotlin builder uses `java.net.IDN`.
* UDP sessions under endpoint-independent NAT are judged per destination; DoH to unknown endpoints,
  ECH and in-app proxies are not detectable.
* Release key is committed to the repo today (see release doc §4) — must be rotated before a shield
  release.

## CI

Recorded in the final report of this phase (run URL and per-job conclusions).
