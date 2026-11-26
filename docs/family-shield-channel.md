# Family Shield — method channel API (phase 2)

Channel: **`aethone/family_shield`** (registered in `MainActivity.configureFlutterEngine`, handler
`shield/ShieldChannel.kt` → `shield/ShieldAdmin.kt`). Native (Kotlin + SQLite + the zeptun snapshot) is
the source of truth; Flutter only calls in. All calls run off the main thread. No Flutter screen exists
yet (phase 3 not approved); answers carry **machine codes only** — the phase-3 UI maps them to localized
`AppStrings` texts (fa/en/ru/zh/tk). No user-visible string originates on the native side.

Answer shape: `{ok: true, …}` or `{ok: false, error: <code>[, detail]}`. Mutations answer
`changed: true` and are applied live by the channel: `applied: "ok"` (new snapshot validated +
atomically swapped in the running engine + `zeptun_revalidate_flows`, no tunnel restart),
`"not-running"` (takes effect at the next connect) or an error (`snapshot-rejected:rc=N`, previous
snapshot stays).

**Gated** (need `token`, a live 5-minute parent session from `pinVerify` / `pinRecover`):
`setEnabled, createProfile, switchProfile, deleteProfile, setCategory, setUnknownPolicy, setStrict,
resetToPreset, addRule, removeRule, restrictApp, setLogging, events, history, pinChange, setBiometric`
— without a valid token: `error: "session-required"`. `settingsImport` needs a token when a PIN is set.

| Method | Args | Answer |
|---|---|---|
| `status` | — | `state` (`protected` / `degraded` / `inactive` / `validation_failed`), `reasons[]`, `enabled`, `tunnelUp`, `engineHook`, `profile`, `generation`, counters `dnsBlocked flowBlocked flowsKilled snapshotSwaps snapshotRejected ipv6Packets` (64-bit wrap-safe totals), `ipv6Route`, `listeners[] {port, listening, guarded}`, `exclusions {mode, othersExcluded, apps[] {package, state}}` |
| `exclusionAudit` | — | per-app exclusion states (see security doc §5 C) |
| `pinState` | — | `set`, `biometric`, `lockedUntil`, `recoveryAvailable` |
| `pinSetup` | `pin` | `recoveryCode` (show once) · `pin-already-set`, `weak-pin:<why>` |
| `pinVerify` / `pinRecover` | `pin` / `code` | `token`, `expiresAt` · `wrong-pin` (+`attemptsBeforeLock`, `lockedUntil`), `locked`, `pin-not-set` |
| `pinChange` | `token, newPin` | new `recoveryCode` |
| `setBiometric` | `token, on` | (prompt UI is phase 3) |
| `endSession` | — | drops all sessions |
| `config` | — | `enabled, activeProfileId, logDomains, retentionDays, generation` |
| `setEnabled` | `token, enabled` | `restartRequired: true` (enabling needs a reconnect: IPv6 capture + DNS hijack are TUN-level; status says `reconnect-required` meanwhile). Refuses `pin-not-set`, `no-active-profile`. Disabling clears the engine snapshot live. |
| `setLogging` | `token, logDomains?, retentionDays?` | |
| `profiles` | — | `profiles[]`, `activeProfileId` |
| `createProfile` | `token, name, preset` (`toddler child teen older_teen custom`) | `profile` |
| `switchProfile` / `deleteProfile` | `token, id` | (delete refuses the active profile) |
| `resetToPreset` | `token, profileId, preset` | |
| `setCategory` | `token, profileId, category, on` | `mandatory-category` for malware/phishing |
| `setUnknownPolicy` | `token, profileId, policy` (`allow`/`block`) | |
| `setStrict` | `token, profileId, strict{enabled, blockDot, blockQuic, blockAltDns, blockDirectIp}` | |
| `rules` / `appRestrictions` | `profileId` | `rules[]` / `apps[]` |
| `addRule` | `token, profileId, kind` (`exact root wildcard cidr`), `value, action` (`block`/`allow`), `note?` | normalized `rule` |
| `removeRule` | `token, id` | |
| `restrictApp` | `token, profileId, package, on` | |
| `events` | `token, from?, to?` (ms, ≤ 400 days) | aggregated `{kind, level, category, app, domain?, count, first, last}` — never URLs; `domain` only with `logDomains` |
| `history` | `token, limit?` | profile switches |
| `flushEvents` | — | writes the pending batch |
| `settingsExport` | — | system picker → `{ok, bytes}` / `cancelled` |
| `settingsImport` | `token?` | system picker → `{ok, prefs, shieldImported, pinRequired, restartRequired}` / `invalid-file` + `detail` |

Status `reasons` codes: `shield-disabled`, `no-tunnel`, `reconnect-required`, `snapshot-invalid`,
`engine-hook-not-installed`, `shield-<start error>`, `ipv6-not-captured`, `per-app-exclusions:<n>`,
`local-socks-exposed:<ports>`, `private-dns-strict`, `app-blocking-unsupported`.
