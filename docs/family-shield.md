# Family Shield (parental control) — phase 1

Status: **core policy engine implemented (native zeptun + Kotlin); no UI; not device tested; not released.**
Branch `feature/family-shield-phase1`. Plan: phase 0 report (owner-approved 2026-11-26).

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
