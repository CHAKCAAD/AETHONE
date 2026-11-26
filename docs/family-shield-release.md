# Family Shield — release & distribution (GitHub only)

Phase 1 changes **no** release behaviour (no version bump, no release, workflow untouched apart from
the added test gates). This document is the release checklist for the first build that ships the shield.

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

## 4. Signing key — current state and required change

**Current state (honest):** the permanent release keystore `android/app/aethone-release.keystore` and its
passwords are committed to the repository (`android/app/build.gradle.kts`, decided in v1.0.1 for
signature continuity). Anyone can therefore sign an APK that installs *as an update* over AETHONE. For
a parental-control feature this matters: a child (or anyone) could install a modified build over the
parent's install without losing data.

**Required before the shield ships (owner decision, not done in phase 1):**
1. Create a new release key offline; store it **only** as CI secrets (`ANDROID_KEYSTORE_B64`,
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) and in an offline
   backup (two encrypted copies, e.g. password manager + offline USB, with the recovery procedure written
   down).
2. Rotate with **APK Signature Scheme v3 key rotation** (`apksigner rotate` to create a lineage from the
   committed key to the new key, then sign with `--lineage`), so existing installs on Android 9+ accept
   the update; Android 7–8 installs need a one-time reinstall (state it in the notes).
3. Remove the old key and passwords from the repository (history keeps them — the lineage is what makes
   the old key harmless going forward).
4. Recovery procedure: if the new key is lost, updates are impossible — restore from the offline
   backup; if both copies are lost, publish a new package signature with a reinstall notice.

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
