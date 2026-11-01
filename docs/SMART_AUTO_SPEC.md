# AETHONE — SMART AUTO: Official Specification Registration (v4.3)

**Document status:** requirements registration only (employer directive, post-v4.2
review — boundary correction against the pinned Aether source).
**Implementation status (unchanged):**

```
SMART AUTO — SPECIFICATION REQUIRED / NOT IMPLEMENTED / NOT TESTED
```

- **SPECIFICATION REQUIRED** — the algorithm must be designed in the NEXT phase on top
  of the factors and guarantees fixed here; nothing in this document is final
  algorithm design.
- **NOT IMPLEMENTED** — no code exists for SMART AUTO in any component: not in the
  AETHONE app, not in Aether core, Zeptun, or psiphon-tunnel-core. No implementation
  is permitted in this phase.
- **NOT TESTED** — no behavior to test; static analysis is impossible by definition.

SMART AUTO (automatic selection of the best usable protocol for the current network
conditions) is a **binding core requirement of AETHONE for Android**. It must not be
removed from the feature list or the development plan by any future bundle.

**Source anchor:** all line references are in the pinned Aether commit
`d58f9d568083129ce2c767c85054021eb3ee6a38` (byte-identity proof:
`evidence/protocol_surface_pinned_commit_v43.txt`).

---

## 1. Two independent concepts — never conflate them

| Concept | Values | Meaning | Pinned-source anchor |
|---|---|---|---|
| **Protocol Selection** | `AUTO` / `SMART` (to be specified); manual: **masque, wg, gool, gool-classic (submode), mim** | **WHICH transport profile** carries the traffic; AUTO/SMART = pick the best usable one automatically | `--protocol <name>  masque \| wg \| gool \| mim` (cli.rs L74); per-profile flags L56–L68; enum of exactly four members lib.rs L3444–3449 |
| **Scan Mode** | `turbo` / `balanced` / `thorough` / `verified` / `ironclad` | **HOW HARD** endpoints are scanned (intensity/depth), independent of protocol choice | `--scan <mode>` (cli.rs L101) + per-mode flags L102–109 |

The two axes are orthogonal: a scan mode never implies a protocol, and a protocol
selection (including AUTO) never implies a scan depth. UI and documentation must keep
the two separated.

## 2. Protocol set — reconciled with the pinned commit (correction item 3)

The pinned `Protocol` enum has **exactly four members** (lib.rs L3444–3449):
`Masque`, `WireGuard`, `WarpInWarp`, `MasqueInMasque`.

- **GOOL Classic is not a fifth protocol.** `--gool-classic` sets
  `AETHER_PROTOCOL=gool` + `AETHER_GOOL_MODE=classic` (cli.rs L644–647). GOOL =
  WireGuard inside MASQUE; GOOL Classic = WireGuard inside WireGuard — a **submode**
  of the WarpInWarp/GOOL family. The UI may show two cards; the backend maps both to
  one family with a different mode setting.
- **Tor and Psiphon are not base protocols.** They are **independent modes/layers**
  managed by Aether (Tor: cargo feature `tor`, tor.rs `Mode{Off,Chain,Reverse,Only}`
  L7–12; Psiphon: managed binary, psiphon.rs `Mode{Off,Chain,Reverse,Only}` L18–37).
  They never appear as `--protocol` values and never enter the protocol candidate set.

| # | Transport profile (candidate for AUTO evaluation) | Pinned-source surface | CLI attested | Backend runtime | UI | End-to-end testing |
|---|---|---|---|---|---|---|
| 1 | MASQUE (default) | `--masque` (cli.rs L56) | YES | `NOT TESTED` | frozen | `NOT TESTED` |
| 2 | WireGuard (WG) | `--wg/--wireguard/--warp` (L57) | YES | `NOT TESTED` | frozen | `NOT TESTED` |
| 3 | GOOL (WG in MASQUE) | `--gool/--wiw` (L59) | YES | `NOT TESTED` | frozen | `NOT TESTED` |
| 4 | GOOL Classic (WG in WG) — **submode of #3** | `--gool-classic` (L68; parser L644–647) | YES | `NOT TESTED` | frozen | `NOT TESTED` |
| 5 | MIM (MASQUE in MASQUE) | `--mim/--masque-in-masque` (L69) | YES | `NOT TESTED` | frozen | `NOT TESTED` |

"CLI attested" means the pinned source exposes the option — it is **not** a runtime
capability proof. The final binding candidate list must be re-confirmed against the
real capabilities of the fixed commit when implementation starts (CI build + device
tests, N2).

## 3. What SMART AUTO is NOT in the pinned core (correction item 7 — boundary)

- `select_protocol()` (lib.rs L3281–3337) is an **interactive numbered menu** that
  asks the user and returns a `Protocol`. It must **never** be described or documented
  as "Smart Auto", an auto-selector, or a ranking algorithm.
- `select_gool()` (lib.rs L3364–3380) is likewise an interactive sub-choice inside the
  GOOL family (default 1 = gool over masque, 2 = classic).
- No automatic protocol ranking, scoring, or switching logic exists anywhere in the
  pinned Aether source. SMART AUTO therefore belongs **entirely to the AETHONE app
  layer** and must be designed independently in a later phase, on top of the pinned
  core's attested surface — without modifying Aether, Zeptun, or any pin.

## 4. SMART AUTO algorithm — minimum factor set (design due next phase)

The algorithm specification must cover, at minimum:

1. **Real per-profile support capability** in the current application state (build
   flags — e.g. whether the shipped native library was built with the `tor` feature,
   credential availability, mode constraints) — never propose a profile the current
   build cannot actually use.
2. **Connection establishment success/failure** per profile attempt.
3. **TCP CONNECT latency** measured through the SOCKS5 path (N3 decision — native
   speed measurement through SOCKS5; no HTTP-proxy measurement substitution).
4. **HTTP TTFB** from the SAME active session used for the CONNECT measurement (no
   mixing of sessions between the two metrics).
5. **Connection stability and consecutive failures** (failure streaks must downgrade
   a profile's standing, not only single successes upgrade it).
6. **Compatibility of the profile with the selected Proxy or Tunnel mode** and with
   any user-selected Tor/Psiphon mode — including the Reverse-carrier rules of §5.
7. **Tor and Psiphon constraints**: they are modes/layers with their own session
   semantics; they stay outside the auto-selectable set until independently tested,
   and AUTO must not enable, disable, or re-shape them (§6).

## 5. Reverse-mode carrier compatibility (correction item 5 — binding for AUTO)

Pinned rule (`needs_udp_to_warp`, lib.rs L3007–3013; refusal blocks
lib.rs L203–218 and L229–244): Tor Reverse and Psiphon Reverse carry TCP only.

| Profile | Tor Reverse / Psiphon Reverse |
|---|---|
| WireGuard (direct) | **incompatible — refused by the core** |
| GOOL Classic | **incompatible — refused by the core** |
| MASQUE | compatible, **forced over HTTP/2** (`AETHER_MASQUE_HTTP2=1`, lib.rs L216/L242) |
| GOOL (non-classic) | compatible (rides the MASQUE outer hop) |
| MIM | compatible (`needs_udp_to_warp` = false) |

AUTO must never propose an incompatible combination. **No restriction may be
circumvented by hidden protocol switching, hidden mode switching, or a hidden
fallback to Direct.** A refused combination is reported as refused.

## 6. Mode-boundary rules for AUTO (binding)

1. Tor and Psiphon are **not** base protocols; AUTO treats them as independent
   modes/layers and must **not** auto-enable or auto-disable either.
2. AUTO must **not** switch between Chain, Reverse, and Only — the mode family is a
   user decision, not an AUTO variable.
3. If the user has explicitly selected a Chain mode (e.g. `AETHER → TOR`), the
   **carrier-selection policy for that mode is a separate design item**, to be
   specified only after that mode has passed its own independent tests.
4. For each Reverse mode, **only compatible carriers are allowed** (§5 table).
5. Every profile must **pass its own independent test** before it may enter the AUTO
   candidate list (N2 separation applies; no cluster-wide shortcuts).
6. Proxy vs Tunnel mode: automatic selection is **separately defined and separately
   evaluated** in each; a ranking produced in one mode must not be reused in the
   other.
7. Tor and Psiphon (and combined) modes are **excluded from the auto-selectable set**
   until their own independent tests exist and are recorded.

## 7. Required design guarantees (non-negotiable constraints for the algorithm)

1. Select only among **truly usable** options (usable = current build supports it AND
   the mode allows it AND it passes its readiness test).
2. On failure of the selected option, an **alternative usable option may be tried** —
   the fallback chain must be explicit and observable in status reporting.
3. **No simultaneous incompatible connections** to multiple sessions.
4. **Full stop of the previous session before any protocol change** — no overlapping
   tunnels.
5. **No hidden fallback to Direct** when a tunnel fails: a failed tunnel is reported
   as a failed tunnel, never silently downgraded to a direct connection.
6. **User's manual selection is preserved**: AUTO must never rewrite/override an
   explicit manual profile choice; AUTO is itself an explicit mode the user opts
   into.
7. **Real connection status only after a successful end-to-end test** — UI
   "connected" claims are emitted only after E2E verification through the live
   tunnel, not after handshake-internal milestones.

## 8. What this phase does NOT do

- No implementation in native code, Flutter UI, Aether, Zeptun, or
  psiphon-tunnel-core.
- No UI design changes (Figma/Flutter frozen; employer directive).
- No pin, commit, flag, ABI or tool-version changes (N1–N8 frozen).
- No new build command or flag applied anywhere (documentation-only revision).
- The algorithm design (weighting, thresholds, fallback ordering, hysteresis) is the
  explicit deliverable of the next phase, built on §4, §5, §6 and §7 above.
