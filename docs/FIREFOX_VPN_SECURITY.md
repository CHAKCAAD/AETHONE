# FIREFOX VPN security — token handling, storage, redaction, isolation (Phase 1)

Status: **Phase 1, private branch `phase1/firefox-vpn` only.**

## 1. Single rule set (the phase-1 decrees)

1. Session tokens NEVER appear in argv, the process environment, stdout
   (other than the `authRefreshed` / `loginCompleted` private events),
   stderr, logs, or a plain file. The ONLY carriers are (a) the child's
   stdin pipe during a connect or a login exchange — one JSON line —
   and (b) the Android-Keystore-encrypted vault at rest. The PHASE-2
   WebChannel layer adds one in-process hop for the FxA session token
   (the WebView→Dart `JavaScriptChannel` message, never persisted);
   the account PASSWORD never transits AETHONE code at all (the sign-in
   happens on Mozilla's own page — docs/FIREFOX_VPN_LOGIN.md §4).
2. **Single account**: exactly one session, one child process, one
   upstream session. No token pools, no multi-account, no
   quota-dodging rotation — the upstream pool machinery was deliberately
   removed (see `fxv/ORIGIN.md`).
3. Quota exhaustion is reported honestly (`firefoxQuotaExhausted`, exit
   code 2) and the user picks another engine; it is never retried
   around.

## 2. Token flow (end to end)

```
Android Keystore (AES/GCM, non-exportable key "aethone_firefox_session_vault")
   │ FirefoxKeystore.decrypt (Kotlin, aethone/engine channel "firefoxDecrypt")
   ▼
FirefoxSessionStore.load() — plaintext in memory only
   │ FirefoxEngineConfig.toJson() — ONE JSON line
   ▼
child stdin (private pipe)  ──►  engine reads it, parses, DROPS the buffer
                                    (cfgLine = nil; 1 MiB read bound)
   ▲                                    │
   │ authRefreshed event (stdout —     │ Guardian/FxA renewal refreshes
   │ the only secret-carrying event;   │ the SAME account's pair;
   │ routed straight to vault.save(),  │ AcquireInitialPass never
   │ never logged)                     │ switches accounts
   └────────────────────────────────────┘
```

* Login flow (Phase 2): the captured FxA session token goes from the
  bridge straight into the `--login` child's stdin pipe; the minted
  pair arrives on `loginCompleted` and is vaulted by the same
  `FirefoxSessionStore.save()` (the adapter's `firefoxWebChannelLogin`
  routes it — never logged, tested). The WebView's cookies are cleared
  after the exchange, killing the browser session locally.
* Vault at rest: `<filesDir>/firefox/session.vault` —
  `IV(12) || AES/GCM ciphertext+tag`, key inside AndroidKeyStore (256
  bit, `PURPOSE_ENCRYPT|DECRYPT`, `BLOCK_MODE_GCM`, randomized IV
  required; `FirefoxKeystore.kt`). A Keystore reset makes old vaults
  undecryptable — the store treats that as ABSENT and wipes the file
  (honest, never a crash; tested in the vault group).
* Vault writes are atomic (tmp + rename); a failed persist never kills
  the running session (the in-memory pair carries it; the next refresh
  retries).
* `clear()` is the logout-grade wipe: vault file + in-memory copy.

## 3. Spawn isolation

`Process.start(binaryPath, const [], environment: const {},
includeParentEnvironment: false)` — bare argv, empty environment, no
parent-env inheritance: nothing secret or incidental can leak into
`/proc/<pid>/cmdline` or the child's environment, and the child's
`--discover` role also runs with `includeParentEnvironment: false`.
Tested: "argv carries NO config and NO secrets (bare spawn)" against
the REAL binary.

## 4. Redaction (both sides)

* Go: `internal/redact` scrubs the access/refresh tokens from every
  error string before it reaches an event or stderr; the engine never
  writes the tokens anywhere else.
* Dart: `FirefoxEngineEvent.logLine` renders events for logs —
  `authRefreshed` renders as "session tokens refreshed by the engine
  (stored; access<redacted> refresh<redacted>)"; the `carriesSecrets`
  event is routed to the store callback and NEVER to the log sink.
* The adapter surfaces only redacted stderr lines; nothing forwards raw
  bytes anywhere.

## 5. Network-facing posture

* The SOCKS listener is loopback-ONLY by validation
  (`socksListenNotLoopback` — the engine refuses to bind anything
  reachable from the network).
* Local port `1822` is asserted free before every connect
  (`firefoxPortBusy`); `1819/1820/1821` remain the aether family's —
  untouched, verified by the port-map tests.
* The control plane requires HTTPS (`guardianNotHttps`); the data plane
  is TLS 1.3 (h2) / QUIC (h3) with the Firefox ClientHello (uTLS).

## 6. License posture (UNRESOLVED)

Upstream `firefox-vpn-client` (pinned `c1c5d89`; still no license at
the re-pin, re-verified 2026-11-11) declares no license
that would allow redistribution or derivative works at the time of
writing. Until the AETHONE owner settles this:

* the wrapper module (`aethone/fxv`), the vendored upstream copy and
  every binary built from them stay in the PRIVATE development
  environment (`phase1/`, mirrored to `/home/z/my-project/phase1/`);
* nothing derived from the upstream code is pushed to any public
  repository (including CHAKCAAD/AETHONE) and no public release or
  artifact may contain the engine binary or derived code;
* the private branch `phase1/firefox-vpn` of the AETHONE worktree is
  the only place where the integration lives; `jniLibs/` is git-ignored
  so the binaries never enter git history;
* credit where due: the upstream author's reverse-engineering is the
  foundation of the wrapped data/control planes (`fxv/ORIGIN.md`).
  FoxyVPN (MIT) was consulted as an architectural reference only — no
  FoxyVPN code is included; its GPL sing-box fork was NOT consulted and
  is NOT included.
