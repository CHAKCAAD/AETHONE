# Family Shield — security (phase 1)

Status: implemented as described below; **nothing here is device tested**.

## 1. Threat model (what the shield can and can not stop)

The shield filters traffic **that crosses AETHONE's TUN** while the tunnel is up. Without Device Owner /
MDM rights, Android lets the device user: turn the VPN off or start another VPN, force-stop or clear the
app, uninstall it, boot into safe mode, factory-reset. None of that can be prevented by a normal app.
Parents should enable Android's *Always-on VPN* + *Block connections without VPN* for AETHONE (manual
system setting; no public API sets it). Every honest limitation is reported as a status reason, never
hidden behind a green badge.

Not inspected, by design: TLS content, SNI, ECH, URLs (no interception). Filtering is per name / address.

## 2. Parent PIN (`ParentPin.kt`, `ShieldStore.kt`)

| Property | Implementation |
|---|---|
| KDF | PBKDF2-HMAC-SHA256 (RFC 8018), 16-byte `SecureRandom` salt, **600 000 iterations** (OWASP Password Storage Cheat Sheet, PBKDF2-HMAC-SHA256 — checked 2026-11-26; the phase-0 figure of 210 000 was wrong). Implemented on `Mac("HmacSHA256")`, so API 24/25 behave like 26+; unit-tested against the RFC 7914 vector and the JDK's `PBKDF2WithHmacSHA256`. Iterations are stored per state (upgradable). |
| Pepper | Post-hash: stored = HMAC-SHA256(Keystore key, PBKDF2(pin, salt)). The key is generated inside the Android Keystore (`KEY_ALGORITHM_HMAC_SHA256`, StrongBox when available, fallback otherwise) and never leaves it. A copied database is useless off the device — important because a 6-digit PIN has only 10⁶ values. |
| PIN rules | 6–12 digits; refused: one repeated digit, ascending/descending runs (`123456`, `987654`), a few well-known PINs. |
| No default PIN | Until `setup` runs, every admin operation is refused (`NotSet`). |
| Backoff | 5 free attempts, then 30 s, doubling per failure, cap 1 h. Counter + lock are persisted **before** answering (killing the app does not reset them). Recovery-code attempts share the counter. |
| Recovery | One-time 16-character code (Crockford-like alphabet, grouped 4-4-4-4) shown once at setup / PIN change; only its peppered hash is stored; consumed on use. Lost PIN and code → only "clear app data" (which also removes the shield — documented, not hidden). |
| Session | 5-minute random token (192 bits) after a successful PIN / recovery / biometric unlock; admin operations take it; `endSessions()` drops all. |
| Biometric | Core supports a biometric session only when the parent enabled it and the PIN is not locked out. The prompt itself is **not implemented in phase 1** (see §6). |
| Constant time | Hash comparisons use `MessageDigest.isEqual`. |

## 3. Storage and backup

* SQLite `family_shield.db` lives in `noBackupFilesDir` (never part of Auto Backup).
* `res/xml/backup_rules.xml` (Android 6–11) and `res/xml/data_extraction_rules.xml` (12+, cloud + device
  transfer) additionally exclude the shield database (and its WAL/SHM) and the `files/shield` directory.
  They only *exclude*; every other app file keeps its previous backup behaviour.
* The Keystore pepper key is never backed up by the platform; a restored copy of the DB (if one ever got
  out) would not verify.
* Flutter stores nothing of the shield (phase 1 has no Flutter part at all).

## 4. Privacy

* Protection events are aggregated per minute × kind × level × category × app; a **domain** is kept only
  when the parent opts in (`logDomains`, default off). No URLs ever (they are never seen). Default retention
  30 days; everything stays on the device.
* Batched writes every 15 s (no write per query / per flow).

## 5. Bypass paths

| Path | Status | Detail |
|---|---|---|
| (A) Local SOCKS listeners 127.0.0.1:1819–1822 | **Still open for the real cores — measured, reported, never Protected** (phase 2: accept-gate PoC proven on the emulator, see §8) | Loopback never crosses the TUN, so any app can dial a core's SOCKS listener. Phase-1 source audit stands: Aether 1819 and Tor-via-Aether 1820 always answer method `0x00`; Psiphon 1821 (goptlib) treats user/pass as PT args; Lantern 1822 not verified. Phase 2: `FamilyShield.probeListeners()` connects to each port at status time; a listening port that is not owned by a `LoopbackGuard` listener of this process is reported `local-socks-exposed:<ports>` and the state can not be Protected. |
| (B) IPv6 | **Implemented (not device tested)** | With the shield on the TUN gets `fdfe:dcba:9876::1/126` + `::/0` + a v6 DNS server; zeptun carries IPv6 (fake range `fc00::/18`, CIDR rules for real v6 addresses). If the Builder refuses → status `ipv6-not-captured` + logcat error (explicit). |
| (C) Per-app tunneling exclusions | **Audited per app (phase 2)** | `ExclusionAudit` mirrors the Builder code: `disallow` → each installed listed app `excluded-disallow-list` (no DNS / flow filtering at all); `allow` → listed apps `filtered`, **every other app** `excluded-not-in-allow-list`; uninstalled entries `not-installed` (no effect); an allow list with nothing installed falls back to the whole device (as the Builder does); AETHONE itself `self-excluded-loop-prevention` (its own sockets are `protect()`ed — its traffic is the tunnels' traffic). Any app other than AETHONE outside the TUN → Degraded `per-app-exclusions:<n>`. The lists are unchanged (owner rule). |
| DoT / DoQ (853), QUIC (UDP/443), alternative DNS, direct IPs | Strict mode (optional, default **off**) | `strict_dot`, `strict_quic`, `strict_alt_dns`, `strict_direct_ip` (the last stays off even in strict mode by default: it breaks apps that connect by IP). If Android Private DNS is in strict *hostname* mode the 853 block is dropped (it would cut the device's DNS) and the status says `private-dns-strict`. |
| Hard-coded resolvers on UDP/53 | Closed while the shield is on | `[dns] hijack = true`. |
| DoH by name | Category `bypass` (HaGeZi DoH/VPN/Proxy bypass, UT1 vpn/doh) | DoH with unknown endpoints / IPs can not be detected (no TLS inspection). |
| Cached fake IPs | Closed | Flow-time re-check of the fake-IP name. |
| UDP to a second peer on an allowed socket | Closed | Per-datagram check when the destination differs from the session's. |

## 6. BiometricPrompt and `FlutterFragmentActivity` — evaluated, not switched

`BiometricPrompt` (androidx.biometric) needs a `FragmentActivity`; `MainActivity` is a `FlutterActivity`.
Switching to `FlutterFragmentActivity` was evaluated and **not done in phase 1**:

* `MainActivity` uses `startActivityForResult` with `REQUEST_TRAFFIC_EXPORT = 4712` and the VPN consent
  request, handled in `onActivityResult`; `FragmentActivity` routes results through the fragment
  manager and validates request codes — behaviour that has to be re-tested on a device for the VPN
  consent flow and the export picker.
* It adds `androidx.biometric` (+ `androidx.fragment`) to a build that is not device tested in this phase.
* Phase 1 has no screen that would show a prompt.

Decision: keep `FlutterActivity`; do the switch together with the phase-2 PIN screen and verify consent
+ export on a device in the same round. The PIN core already exposes `biometricSession()`.

## 7. Package visibility

The existing `<queries>` LAUNCHER intent is enough: restricted apps are picked from launchable apps and
resolved with `getApplicationInfo`; owner uids come from `getConnectionOwnerUid`. **`QUERY_ALL_PACKAGES` is
not added** (not technically needed; packages without a launcher show as `uid:N`). App blocking needs
Android 10+ (owner uid lookup); below that the status says `app-blocking-unsupported` when restrictions exist.
Distribution is GitHub-only (no Play constraints, no Play Services dependency was added).

## 8. Phase 2 — loopback SOCKS accept gate (`LoopbackGuard.kt`)

Goal: admit only AETHONE itself to a local SOCKS listener; reject every other uid and every unknown
client (fail-closed); no port hiding, no random ports, no "loopback is safe".

Identification of the client of an accepted loopback TCP connection:
1. **Own-process socket match** — walk `/proc/self/fd`, keep `socket:[…]` links, `dup` each
   (`ParcelFileDescriptor.fromFd`) and compare `getsockname` = client address and `getpeername` =
   listener address. Recognises the in-process clients (zeptun's dial, Aether).
2. **`ConnectivityManager.getConnectionOwnerUid(IPPROTO_TCP, local, remote)`** (Android 10+, active VPN
   app), queried both ways (local = client/remote = listener, and the reverse). AOSP filters the answer to
   uids the VPN *applies to*: AETHONE excludes itself from its own VPN, so its own sockets come back as
   `INVALID_UID`; apps inside the VPN come back with their uid. It can name a foreign client, never confirm
   our own — so it is evidence, not the allow criterion.

Decision (pure, unit-tested): own-process match → allow; foreign uid → reject; INVALID_UID / our uid in
another process / walk failed / Android < 10 → reject (fail-closed). Rejected clients get an RST.

Where it applies today: the guard is a library + a guarded listener. It is proven on the emulator in
front of the CI SOCKS stub (zeptun → guarded listener admitted; shell uid 2000 and root rejected —
results in `family-shield-testing.md` §5). It does **not** protect the real cores yet, because each core
binds its own TCP listener on 127.0.0.1 and any front proxy would still leave that listener reachable
(that would be port hiding). Production wiring needs one of:
* **Aether (1819, 1820 Tor)** — an accept hook in the pinned Rust core (`socks.rs`) running the same
  own-process check natively (`/proc/self/fd` + `getsockname`/`getpeername` work in-process without
  Android APIs), or a Unix-domain listener in the app's private directory (unreachable by other uids by
  file permission + SELinux);
* **Psiphon (1821)** — psiphon-tunnel-core runs as a separate process: an in-process check can not see
  zeptun's socket; needs the client fd check against AETHONE's main pid (same uid → `/proc/<pid>/fd`
  readable) or a Unix-socket listener; not done;
* **Lantern (1822)** — Radiance listener (Go, separate process): same as Psiphon; not done.
Per-session random SOCKS credentials remain non-viable while none of the four listeners enforces RFC 1929
(phase-1 audit; no core was patched).
