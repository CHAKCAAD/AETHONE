# Release signing key — full rotation (owner decision, 2026-11-26)

Status on branch `feature/family-shield-phase2`: **CI/Gradle prepared; the old key is gone from the
working tree; history is NOT rewritten (separate, owner-coordinated step — §6).**

## 1. Why

`android/app/aethone-release.keystore` and its passwords (`aethone-release`) were committed to the
public repository (v1.0.1 decision for signature continuity). Anyone can therefore sign an APK that
Android installs **as an update** over AETHONE, keeping its data. For a parental-control feature that is
unacceptable. Owner decision: **full rotation — the compromised key must never sign a new build** (no
APK Signature Scheme v3 lineage from the old key either: a lineage would keep the old key trusted for
rotation proofs, and the owner chose a clean break).

Consequence: the first build signed by the new key can **not** be installed over an old-key install. Users
must export their settings, uninstall, install the new build and import (see
[settings-migration.md](settings-migration.md)).

## 2. The compromised certificate (do not trust)

| | |
|---|---|
| Alias / DN | `aethone-release` / `CN=AETHONE Release, O=CHAKCAAD` |
| Valid | 2026-11-17 → 2056-11-09, SHA384withRSA |
| **Cert SHA-256** | `EB:F3:9C:82:FD:46:D5:A4:46:91:AA:08:CE:9A:3A:B6:90:68:74:AE:9D:54:D6:E4:30:64:75:6F:38:6D:1C:79` |
| Cert SHA-1 | `C0:1B:2C:D0:79:7E:79:C3:7B:8F:2C:85:CF:E9:DA:70:5C:FE:C7:C6` |

(Computed with `keytool -list -v` from the committed keystore before it was removed.) CI holds it as
`OLD_COMPROMISED_CERT_SHA256` and **fails any job whose APK is signed by it**.

## 3. Where the key lives now — GitHub Actions secrets only

| Secret | Content |
|---|---|
| `AETHONE_KEYSTORE_B64` | base64 of the PKCS12 keystore file |
| `AETHONE_KEYSTORE_PASSWORD` | store password |
| `AETHONE_KEY_ALIAS` | key alias |
| `AETHONE_KEY_PASSWORD` | key password (same as the store password for a PKCS12 made by keytool) |

Least privilege in `native-ci.yml`:
* **`android-apk`** (Flutter/Gradle, third-party plugins, Maven downloads) **never sees the secrets**. Its
  release APKs are debug-signed and labelled *NOT a release candidate* (`BUILD_INFO.txt`); a signer gate
  prints each APK's signer + SHA-256 and fails on the compromised certificate or if the old keystore
  reappears in the tree.
* **`release-signing`** is the only job with the four secrets in its environment. It downloads the APK
  artifact, decodes the keystore into `$RUNNER_TEMP` (umask 077), re-signs the per-ABI and universal
  release APKs with `apksigner sign` (v1+v2+v3, `--alignment-preserved true`), re-checks `zipalign -c -P 16`,
  runs `apksigner verify --print-certs`, **prints the new signer cert SHA-256 and every APK SHA-256**, fails
  if the signer is the compromised or a debug certificate, deletes the keystore (also on failure) and
  uploads `aethone-apk-signed-r<N>` (+ `SIGNING.txt`, `SHA256SUMS.txt`).
  Secrets missing → nothing is signed, the job says *NO release candidate*, output `signed=false`.
* **`publish-release`** runs only on the default branch **and** only when `signed == 'true'`; it publishes
  the signed APKs only. There is no fallback key anywhere.
* Local builds: `android/app/build.gradle.kts` signs `release` with the same four **environment
  variables** when all are set; otherwise with the debug key (not a release candidate). It never reads a
  keystore file from the repository.

## 4. Owner side — create the new key (on your own machine; the password never leaves it)

```bash
# 1. generate (PKCS12, RSA 4096, 30 years). keytool prompts for the password — do not put it on the command line.
keytool -genkeypair -v -storetype PKCS12 -keystore aethone-release-2026.p12 \
  -alias aethone-release-2026 -keyalg RSA -keysize 4096 -validity 10950 \
  -dname "CN=AETHONE Release 2026, O=CHAKCAAD"
# 2. record the new fingerprint (publish it in the release notes)
keytool -list -v -keystore aethone-release-2026.p12 | grep SHA256
# 3. base64 for the secret (single line)
base64 -w0 aethone-release-2026.p12 > keystore.b64        # macOS: base64 -i aethone-release-2026.p12 -o keystore.b64
# 4. create the secrets (GitHub CLI, or Settings › Secrets and variables › Actions)
gh secret set AETHONE_KEYSTORE_B64      -R CHAKCAAD/AETHONE < keystore.b64
gh secret set AETHONE_KEYSTORE_PASSWORD -R CHAKCAAD/AETHONE      # paste when prompted
gh secret set AETHONE_KEY_ALIAS         -R CHAKCAAD/AETHONE --body aethone-release-2026
gh secret set AETHONE_KEY_PASSWORD      -R CHAKCAAD/AETHONE      # same as the store password (PKCS12)
shred -u keystore.b64                                             # macOS: rm -P keystore.b64
```

## 5. Offline encrypted backup (do this before the first release)

1. Two independent encrypted copies of `aethone-release-2026.p12` **and** its password, e.g.
   (a) a password manager entry with the file attached; (b) an offline USB stick holding
   `gpg --symmetric --cipher-algo AES256 aethone-release-2026.p12` (passphrase different from the key
   password, written on paper kept with the stick in a separate place).
2. Write down the alias, the cert SHA-256 and the creation date next to each copy.
3. Test the restore once: decrypt the USB copy on another machine and run `keytool -list` against it.
4. Delete the plain file from the working machine after both copies are verified.

## 6. Coordinated history purge — PLAN ONLY (not executed)

The old key is still in git history. Rotation makes it harmless for *new* builds (users of a new-key
install reject old-key updates), but the purge removes the temptation and the confusion. Steps, to be run
by the owner after the new-key release is out:

1. Announce a freeze; make sure every open branch is pushed; record every branch and tag
   (`git ls-remote --heads --tags origin`).
2. Fresh mirror clone: `git clone --mirror https://github.com/CHAKCAAD/AETHONE.git aethone-purge.git`.
3. `pip install git-filter-repo`, then in the mirror:
   `git filter-repo --invert-paths --path android/app/aethone-release.keystore`
   and replace the passwords in old `build.gradle.kts` versions:
   `git filter-repo --replace-text <(printf 'aethone-release==>REDACTED\n')` (review the matches first —
   the alias string also appears in comments).
4. Verify: `git log --all -- android/app/aethone-release.keystore` is empty; `git grep aethone-release $(git rev-list --all)` shows nothing sensitive.
5. Force-push **all** refs: `git push --force --mirror origin` (branches and tags; temporarily lift branch
   protection on `ci-bootstrap/v4.4`).
6. Ask GitHub Support to purge cached views / PR refs (`refs/pull/*` are read-only and keep old objects).
7. Every collaborator deletes local clones and re-clones; forks keep the old history (cannot be fixed by us).
8. Re-create release tags if they moved; re-check that release assets are unchanged.

## 7. Recovery

* **New key lost** (both backups gone): no further updates are possible under that signature. Create a
  new key (§4), publish a release with a reinstall notice and the new fingerprint, users migrate with
  settings export/import (as for this rotation).
* **New key leaked**: rotate again immediately (§4), revoke/replace the four secrets, publish the new
  fingerprint and a security notice; treat every APK signed after the leak date as untrusted.
* **Secret deleted / corrupted in GitHub**: restore it from the offline backup (§5), re-run CI.
* **CI prints an unexpected signer fingerprint**: do not publish; compare with the backup's fingerprint.
