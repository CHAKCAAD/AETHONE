# Settings export / import and the signing-key migration

Status: implemented natively (`shield/SettingsBackup.kt`, `shield/ShieldChannel.kt`, picker in
`MainActivity`), JVM-tested, export validated on the emulator (shield-e2e). **No Flutter screen yet**
(phase 3 not approved) — the API is `aethone/family_shield` → `settingsExport` / `settingsImport`.
Import through the picker is **not** emulator-tested (needs UI interaction); device test is the owner's.

## 1. Why it is needed

The release key is rotated (docs/signing-key-rotation.md). Android refuses to install an APK over an
installed app with a different signing certificate, so the first new-key release requires uninstall +
install, which deletes app data. Export/import carries the user's settings across.

## 2. File format (`aethone-settings-YYYYMMDD-HHMM.json`, version 1)

```json
{ "format": "aethone-settings", "version": 1, "createdAt": 1764160000000, "appVersion": "1.0.2",
  "note": "No PIN, recovery code, keys or event logs are included. …",
  "app": { "prefs": [ { "key": "aethone.settings.protocol", "type": "s", "value": "…" }, … ] },
  "familyShield": { "enabledAtExport": true, "activeProfileId": "p…", "logDomains": false, "retentionDays": 30,
    "profiles": [ { "id": "p…", "name": "…", "preset": "child", "categories": ["adult", …],
      "allowCategories": [], "unknownPolicy": "allow", "strict": { … },
      "rules": [ { "kind": "root", "value": "example.com", "action": "block", "note": null } ],
      "apps": [ "com.example.game" ] } ] } }
```

* **app.prefs**: every `aethone.settings.*` key the Flutter side persists (protocol, per-family
  locations, routing region, per-app tunneling mode + list, hybrid routing rules, core settings, kill
  switch, look, language). Typed (`s`/`b`/`l`/`i`/`f`), restored with the same type.
* **familyShield**: profiles, parent rules, app restrictions, logging options, active profile.

**Never exported:** parent PIN hash + salt, recovery-code hash, the Keystore pepper (it can not leave the
Android Keystore), admin sessions, protection events, profile history. Why the PIN can not travel: its
hash is peppered with a device-bound Keystore key, so it would not verify on the new install, and a
copied hash would only hand an attacker an offline guessing target (a 6-digit PIN has 10⁶ values).

## 3. Validation on import (fail-closed, nothing applied on error)

Size ≤ 2 MiB; strict JSON (no duplicate keys, bounded depth); `format` must match; `version` 1 (newer =
refused with `newer-version`); pref keys must start with `aethone.settings.` and use a safe charset,
values must match their type; ≤ 200 prefs, ≤ 16 profiles, ≤ 5000 rules per profile; presets/categories
must be known; mandatory security categories (malware, phishing) can not appear (they are always on);
every domain/CIDR rule is re-normalized exactly like a rule typed by the parent (IDN → punycode, CIDR
host bits refused); the active profile must exist. Error answers: `{ok:false, error:"invalid-file",
detail:<code>}`.

## 4. Who may import

* If a parent PIN is set on the **current** install, the call needs a live parent session `token` (a
  child can not replace the protection with a file).
* On a fresh install (no PIN) import is allowed; the imported shield is stored **disabled** and the
  answer says `pinRequired: true`. The parent sets a new PIN, then enables the shield.
* Answer includes `restartRequired: true`: Flutter caches preferences in memory, the app must be
  restarted to load the imported settings.

## 5. Migration plan for users (old-key install → new-key release)

1. **Notify** (release notes of the last old-key build, GitHub Release page, README): what changes and
   why (security: the old key was public), the new certificate SHA-256, the steps below.
2. **Update to the bridge build first** (the last build that still installs over the old one — it must be
   built before the key switch, i.e. from a branch that contains this export feature; owner decision
   whether to ship it signed by the old key one final time or skip it). Without it, users have no export
   and must reconfigure by hand.
3. **Export**: Settings › export (phase-3 screen) → choose a location outside the app (Downloads / Drive).
4. **Write down nothing secret**: the parent will set a new PIN on the new install.
5. **Uninstall** the old app (Family Shield parents: the child's device loses protection from this step
   until step 8 — do it together).
6. **Install** the new APK from GitHub Releases; verify the APK SHA-256 and
   `apksigner verify --print-certs` = the published new certificate SHA-256.
7. **Import** the file; restart the app.
8. Family Shield: set a new parent PIN, enable the shield, re-enable Android *Always-on VPN* + *Block
   connections without VPN* for AETHONE.

> Honest gap: step 2 needs a bridge build. If the owner decides never to sign with the old key again
> (strict reading of "compromised key must NOT sign new builds"), no build containing the export feature
> can be installed over v1.0.2, and the first migration is manual. The export then serves every later
> reinstall / device change.
