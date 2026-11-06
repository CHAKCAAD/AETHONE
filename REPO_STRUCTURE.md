# AETHONE Repository Structure — branch `ci-bootstrap/v4.4`

First push of the official AETHONE repository (CI-bootstrap transfer, 2026-11-01).
Assembled under the N1–N8 freeze rules: **no upstream commit was changed, no
pin was altered.**

## Top-level layout

| Path | Contents | Origin |
|---|---|---|
| `.github/workflows/native-ci.yml` | Frozen native CI (v4.4: NDK input split + fail-closed `ndk-full-version` check) | CI package v4.4 |
| `scripts/` | `build_native.sh`, `inspect_elf.sh`, `pt-build-pin.patch` | CI package v4.4 |
| `docs/` | `FEATURE_MATRIX.md`, `CLI_REFERENCE.md`, `SMART_AUTO_SPEC.md`, `CI_BOOTSTRAP_PoC.md` | CI package v4.4 |
| `docs/phase1/` | Phase-1 technical audit + machine-readable inventories (CLI flags, env vars, settings schema, zeptun config, API inventory, compatibility matrices) | Client audit/design package |
| `evidence/` | Phase-2 evidence set (v4.1 → v4.4 history) | CI package v4.4 |
| `evidence/transfer/` | THIS transfer's evidence: security scan report, vendored archive hashes, excluded-fonts license record, scanner tool, SHA256 manifest | Transfer v4.4 |
| `design/` | Client design package: app icons, app icon library, protocol icons, 266 flag SVGs + mapping guide, background pattern, page references (home / speed test / settings / onboarding) | Client design package |
| `native/` | Exact `git archive` exports of the three native components at their frozen pins (see below) | Frozen pins (N1/N8) |
| `linux/`, `windows/` | v4.36 desktop runners (Flutter `flutter create` templates + the `aethone/engine` channel glue + the 402x874 phone-frame window) | New (v4.36) |
| `desktop_shared/` | v4.36 platform-independent engine layer (the Kotlin twin): paths, zeptun TOML, bounded core-log capture, tunnel lifecycle — shared by both desktop runners | New (v4.36) |
| `scripts/build_native_desktop.sh` | Host-target builds of the SAME frozen pins for Linux/Windows (aether cdylib, zeptun shared, lyrebird, psiphon; wintun.dll on Windows) | New (v4.36) |
| `rust-toolchain.toml` | Rust toolchain pin for this repository | CI package v4.4 |
| `README.md` | CI package v4.4 README (bundle description + version history) | CI package v4.4 |
| `.gitignore` | Flutter/Android/secrets ignores (anchored; machine-verified to match nothing on this branch) | New (transfer v4.4) |

## Frozen native pins (N1 / N8 — authoritative)

The **authoritative source** for the CI is the upstream repositories at the
frozen SHAs below; the workflow clones and verifies them itself (see the env
block of `.github/workflows/native-ci.yml`). The `native/` directories are
exact read-only reference exports of exactly those commits, included so this
repository is self-contained. Removing them later (owner decision) does not
affect the CI.

| Component | Upstream | Frozen SHA | Vendored at |
|---|---|---|---|
| Aether (Rust) | https://github.com/CluvexStudio/Aether.git | `d58f9d568083129ce2c767c85054021eb3ee6a38` | `native/aether/` |
| Zeptun (Zig) | https://github.com/Noisemux/zeptun.git | `08a1ab05aab315b7872ed582c52b7c230930d05d` | `native/zeptun/` |
| Psiphon fork (Go; builds Lyrebird) | https://github.com/CluvexStudio/psiphon-tunnel-core.git | `2956a96b56fe09b99e72a8eb4bed3e79d29e3543` | `native/psiphon-tunnel-core/` |

Archive-stream SHA256 of each export: `evidence/transfer/vendored_archives_sha256.txt`.

Lyrebird is built by Aether's own frozen `pt-build.sh` (pin `fc105a03c0e0`
lives inside that script at the Aether pin); the psiphon fork tree above is the
AETHONE pin target (N1 decision — recorded deviation from Aether's own
`83aa73b9…` pin; `2956a96…` is its descendant, verified by merge-base).

## What is deliberately NOT on this branch

1. **Flutter application source, the app `android/` folder, app Gradle files.**
   They were **never present in the analysis workspace** (machine-verified:
   0 `.dart` files, 0 `pubspec.yaml`; every `AndroidManifest.xml`/Gradle file
   found belongs to the upstream psiphon library and its sample apps). Nothing
   was invented to fill the gap. The owner must transfer the app source
   separately; `.gitignore` already anticipates a root-level Flutter app.
2. **Font files (`IRANYekanX-*.ttf`).** Commercial family (fontiran.com;
   embedded license: “To use this font, it is necessary to obtain the license
   from www.fontiran.com”). No license document exists in the workspace, so
   under the fail-closed rule the 11 TTFs are NOT committed. Exact inventory +
   SHA256s: `evidence/transfer/fonts_excluded_license.txt` — add later once the
   license is confirmed.
3. **No secrets, keystores or signing material.** Machine scan of the whole
   transfer set: 0 keystores, 0 `.env` files, 0 live tokens. Private-key
   blocks / credential-looking strings exist only inside the public upstream
   sources at the frozen pins (test & example fixtures, e.g. quiche example
   certificates, Go SSH testdata) and are part of those public commits:
   `evidence/transfer/security_scan_report.txt`.

## Branch policy

- Pushed as the **only** branch (`ci-bootstrap/v4.4`). On the empty private repository
  it becomes the default branch. **No `main` is created, no merge to `main`.**
- No force-push, no branch deletion, no history rewrite.
- Toolchain pins on this branch: Rust 1.99.1, Go 1.26.3, Zig 0.16.0,
  NDK r26d (`26.3.11579264`), API 29, ABIs arm64-v8a / armeabi-v7a / x86_64 —
  unchanged (N8). minSdk=24 remains Candidate (N4).

---

## خلاصهٔ فارسی

این شاخه (`ci-bootstrap/v4.4`) نخستین انتقال رسمی پروژهٔ AETHONE است: بستهٔ CI
نسخهٔ 4.4 + مستندات و موجودیت‌های ماشینی فاز ۱ + پکیج طراحی (بدون
فونت‌های تجاری) + خروجی دقیق سه جزء Native در Commitهای منجمدشده
(N1/N8). سورس Flutter و پوشهٔ Android اپ هرگز در Workspace تحلیل موجود
نبوده (۰ فایل Dart و ۰ pubspec.yaml) و به‌جای حدس، صریحاً در همین سند
ثبت شده است؛ انتقال آن بر عهدهٔ مالک پروژه است. هیچ Secret یا
Keystore‌ای منتقل نشده (اسکن ماشینی در `evidence/transfer/`). تنها همین
شاخه Push می‌شود و هیچ Merge به main انجام نمی‌شود.


## v4.36 — دسکتاپ (لینوکس و ویندوز)

خروجی دسکتاپ با **همان ظاهر و اندازه** نسخه اندروید (پنجره ۴۰۲×۸۷۴، همان
پکیج طراحی) و **بدون هیچ اختلالی در اندروید** اضافه شد:

* `desktop_shared/desktop_engine.{h,cpp}` — دوقلوی C++ِ همان لایه کاتلین
  (paths / prepareVpn / startVpn / vpnStatus / zeptunCounters / coreJob /
  readCoreLog)؛ کانال `aethone/engine` در هر دو رانر با همین سطح پیاده شده
  تا `PlatformEngineAdapter` دارت **بدون تغییر** اجرا شود.
* اپ دسکتاپ واقعی خودش را با متغیر محیطی `AETHONE_DESKTOP_ENGINE=1` علامت
  می‌زند (پیش از استارت موتور)؛ میزبان‌های تست هرگز این متغیر را نمی‌گذارند
  پس مسیر legacy (engineNotWired) و تمام ۲۳۴ تست دقیقاً مثل قبل سبز می‌مانند.
* رانر لینوکس: تونل کامل با `exclude_uid` (خود اپ از تونل مستثنا)؛ رانر
  ویندوز: مسیر `exclude` استخرهای WARP (پروتکل‌های `-only` در ویندوز با
  کد صادقانه `platformLimit` رد می‌شوند). تونل لینوکس به root نیاز دارد —
  خطای zeptun عیناً به کاربر نشان داده می‌شود.
