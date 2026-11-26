# Family Shield — release & distribution (GitHub only)

Phase 1 changed no release behaviour. Phase 2 changes signing (§4) — still no version bump, no release. This document is the release checklist for the first build that ships the shield.

## 1. Distribution

* GitHub Releases only (`CHAKCAAD/AETHONE`). No Google Play, so no Play policy constraints
  (`QUERY_ALL_PACKAGES` is still not used) and no Play Services dependency.
* Artifacts: **arm64-v8a APK** (primary), optional universal APK, `SHA256SUMS.txt`, release notes.
  (CI already produces `aethone-arm64-v8a-r<run>.apk`, the universal APK and `SHA256SUMS.txt`.)
* Release notes must state: what Family Shield does and does not do (security doc §1, §5), that it is
  not device-verified until the acceptance round is done, permissions used, and the privacy policy URL.

## 2. Permissions (unchanged by phase 1)

`INTERNET`, `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
`POST_NOTIFICATIONS`, VPN service binding (`BIND_VPN_SERVICE`). Family Shield adds **no permission**
(owner uids come from `getConnectionOwnerUid`, available to the active VPN app on Android 10+).

## 3. Privacy policy

Publish a privacy policy page (suggested: GitHub Pages, e.g. `https://chakcaad.github.io/AETHONE/privacy`)
**before** the first shield release and link it from the release notes. Content: everything is processed
and stored on the device; aggregated protection counts; domain names only with the parent's opt-in; no
URLs; nothing sent anywhere; how to delete (clear app data). *(Page not created in phase 1.)*

## 4. Signing key — rotated (phase 2)

Owner decision 2026-11-26: **full rotation; the compromised key never signs a new build.** Details,
owner commands, backup, history-purge plan and recovery: [signing-key-rotation.md](signing-key-rotation.md).

* The committed keystore and its passwords are **removed from the working tree** on
  `feature/family-shield-phase2` (history untouched until the owner-coordinated purge).
* Compromised certificate SHA-256 (never trust, CI fails on it):
  `EB:F3:9C:82:FD:46:D5:A4:46:91:AA:08:CE:9A:3A:B6:90:68:74:AE:9D:54:D6:E4:30:64:75:6F:38:6D:1C:79`.
* The release key comes **only** from the GitHub Actions secrets `AETHONE_KEYSTORE_B64`,
  `AETHONE_KEYSTORE_PASSWORD`, `AETHONE_KEY_ALIAS`, `AETHONE_KEY_PASSWORD`, exposed **only** to the
  `release-signing` job, which re-signs the release APKs, verifies them with `apksigner`, prints the new
  signer certificate SHA-256 and each APK SHA-256, and fails on the old or a debug certificate.
* Secrets absent → no release candidate (debug-signed build, `publish-release` refuses). No fallback key.
* No v3 lineage from the old key (clean break) → **existing installs can not update in place**; users
  migrate with settings export/import: [settings-migration.md](settings-migration.md).
* Release notes must publish the new certificate SHA-256 (from the `SIGNING.txt` of the signing job).

## 4b. Release-time verification (CI, every run)

`android-apk` signer gate: each APK's signer SHA-256 + APK SHA-256, fail on the compromised cert or if
the old keystore re-appears. `release-signing`: `apksigner verify --verbose --print-certs` (v2 required),
`zipalign -c -P 16`, new signer SHA-256 ≠ old, ≠ Android Debug, `SHA256SUMS.txt` of the signed APKs.

## 5. Sideloading warning (release notes)

Users install from outside a store: they must enable "install unknown apps" for their browser/file
manager, should download **only** from the GitHub Releases page, and must verify the SHA-256 before
installing. Family Shield cannot stop a device user from uninstalling or replacing the app.

## 6. How to verify the SHA-256

* Linux/macOS: `sha256sum aethone-arm64-v8a-rNNN.apk` (macOS: `shasum -a 256 …`) and compare with
  `SHA256SUMS.txt` from the same release.
* Windows (PowerShell): `Get-FileHash .\aethone-arm64-v8a-rNNN.apk -Algorithm SHA256`.
* Android: any checksum app, or verify on a computer before copying.
* Signature: `apksigner verify --print-certs app.apk` — the certificate SHA-256 must match the one
  published in the release notes.

## 7. Release gates

Existing gates (zipalign `-P 16`, `apksigner verify`, dexdump JNI surface — now including
`routeShield`, `revalidate` and the four shield natives) plus the device acceptance list in
`docs/family-shield-testing.md` §4. Do not publish a shield release with that list open.
