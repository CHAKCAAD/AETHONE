<div dir="ltr">

# AETHONE

**A multi-protocol tunnel client for Android, Linux and Windows.**

AETHONE carries your traffic through a chain of censorship-resistant transports —
Cloudflare WARP legs (MASQUE, WireGuard, GOOL, GOOL Classic, MIM) with Psiphon and
Tor families on top — in one app, in Persian (فارسی), English, Russian, Chinese and
Turkmen.

<p>
  <img src="design/brand/app-icon.png" width="96" alt="AETHONE" />
</p>

## Features

- **12 connection modes** — five WARP legs plus the Psiphon and Tor families
  (chain, reverse and only modes), each with its own icon.
- **Tunnel or proxy** — whole-device TUN mode (Android `VpnService`, Linux TUN,
  Windows Wintun) or a plain local SOCKS5 listener.
- **Per-app tunneling (Android)** — tunnel *only the selected apps*, or
  *everything except* the selected apps.
- **Country routing profiles** — send the selected country's own domains and IP
  ranges direct (outside the tunnel) while everything else stays tunnelled.
- **Kill switch, scan-speed profiles, SMART auto protocol selection** with
  measured latency ranking.
- **Light / night / auto theme** (auto follows 06:00–18:00), animated background
  patterns, IRANYekan Persian typography, full RTL layout.
- **Connection notification with a Disconnect action** (Android), close-to-tray
  with a toggle-connection menu (desktop).
- **Five languages** — فارسی, English, Русский, 中文, Türkmençe.

## Downloads

The current release (**v1.0.0**) ships **Android only** — one APK per CPU,
published on the [Releases](https://github.com/chakcaad/AETHONE/releases)
page:

| Device | File |
| --- | --- |
| Android 64-bit (most phones) | `aethone-arm64-v8a-*.apk` |
| Android 32-bit / older | `aethone-armeabi-v7a-*.apk` |
| Emulator / x86_64 | `aethone-x86_64-*.apk` |

Android requires Android 7.0 (API 24) or newer. Linux and Windows bundles
are built by CI on every commit but are not published as releases yet.

## Build from source

Everything is reproducible from pinned sources:

```bash
git clone https://github.com/chakcaad/AETHONE.git
cd AETHONE

# the Flutter UI (analyze + tests)
flutter pub get
flutter analyze
flutter test

# a debug APK (needs the Android SDK + NDK r26d)
flutter build apk --debug
```

The native cores (the `aether` Rust engine, `zeptun` TUN stack, psiphon-tunnel-core
and lyrebird) are vendored under `native/` at their frozen pins; the CI workflow
(`.github/workflows/native-ci.yml`) builds every platform from scratch on each push.
See [docs/LOCAL_BUILD_FA.md](docs/LOCAL_BUILD_FA.md) for the full Persian
local-build guide and [docs/](docs/) for the engineering specs.

## Repository layout

```
lib/            Flutter UI (Dart)
android/        Android host (VpnService, channels, notification)
linux/ windows/ Desktop hosts (TUN, tray, window bridge)
desktop_shared/ Shared desktop engine glue (C++)
native/         The pinned engines: aether, zeptun, psiphon-tunnel-core, lyrebird
design/         The owner's design sources — icons, flags, patterns, fonts
scripts/        CI/build gates and the icon render pipeline
docs/           Engineering specs (CLI reference, feature matrix, build guide)
evidence/       The pin-provenance audit trail consumed by the CI record
test/           Analyze-clean, 240+ Flutter tests
```

## Privacy

AETHONE connects directly to public transport networks (Cloudflare WARP, Psiphon,
Tor); it contains no analytics, no account and no telemetry. Core logs stay on
your device until you clear them.

</div>

---

<div dir="rtl">

# اثـان (AETHONE)

**کلاینت تونل چندپروتکلی برای اندروید، لینوکس و ویندوز.**

AETHONE ترافیک شما را از طریق زنجیره‌ای از ترنسپورت‌های ضدسانسور عبور می‌دهد —
پاهای وارپ کلادفلر (ماسک، وایرگارد، گول، گول کلاسیک، میم) به‌همراه خانواده‌های
سایفون و تور روی آن‌ها — همه در یک اپ، به فارسی، انگلیسی، روسی، چینی و ترکمنی.

## امکانات

- **۱۲ حالت اتصال** — پنج پایهٔ وارپ به‌علاوهٔ خانواده‌های سایفون و تور
  (حالت‌های زنجیره، معکوس و تنها)، هرکدام با آیکون اختصاصی خودش.
- **تونل یا پروکسی** — حالت تونل تمام‌دستگاه (اندروید `VpnService`، لینوکس TUN،
  ویندوز Wintun) یا شنوندهٔ محلی SOCKS5 ساده.
- **تونل تک‌برنامه‌ای (اندروید)** — «فقط برنامه‌های انتخاب‌شده» تونل شوند یا
  «به‌جز برنامه‌های انتخاب‌شده».
- **پروفایل‌های مسیریابی کشورها** — دامنه‌ها و رنج‌های آی‌پی کشور انتخاب‌شده
  مستقیم (بیرون از تونل) بروند و بقیهٔ ترافیک تونل بماند.
- **کیل‌سوئیچ، پروفایل‌های سرعت اسکن، انتخاب پروتکل هوشمند (SMART)** با
  رتبه‌بندی تأخیر اندازه‌گیری‌شده.
- **تم لایت / نایت / خودکار** (خودکار: ۶ صبح تا ۶ عصر لایت)، پترن‌های متحرک
  پس‌زمینه، تایپوگرافی فارسی ایران‌یکان، چیدمان کامل راست‌به‌چپ.
- **نوتیفیکیشن اتصال با دکمهٔ قطع اتصال** (اندروید)، بستن به سینی سیستم با
  منوی قطع/وصل (دسکتاپ).
- **پنج زبان** — فارسی، English، Русский، 中文، Türkmençe.

## دانلود

نسخهٔ فعلی (**v1.0.0**) فقط برای **اندروید** منتشر می‌شود — برای هر پردازنده
یک APK جدا، در صفحهٔ
[Releases](https://github.com/chakcaad/AETHONE/releases):

| دستگاه | فایل |
| --- | --- |
| اندروید ۶۴ بیتی (اکثر گوشی‌ها) | `aethone-arm64-v8a-*.apk` |
| اندروید ۳۲ بیتی / قدیمی | `aethone-armeabi-v7a-*.apk` |
| شبیه‌ساز / x86_64 | `aethone-x86_64-*.apk` |

اندروید ۷.۰ (API 24) یا جدیدتر لازم است. بسته‌های لینوکس و ویندوز هم در هر
کامیت توسط CI ساخته می‌شوند اما هنوز به‌عنوان نسخه منتشر نشده‌اند.

## ساخت از سورس

همه‌چیز از سورس‌های پین‌شده قابل بازتولید است:

```bash
git clone https://github.com/chakcaad/AETHONE.git
cd AETHONE

# رابط کاربری Flutter (آنالیز + تست‌ها)
flutter pub get
flutter analyze
flutter test

# APK دیباگ (نیاز به Android SDK + NDK r26d)
flutter build apk --debug
```

هسته‌های نیتیو (موتور Rust با نام `aether`، پشتهٔ TUN با نام `zeptun`،
psiphon-tunnel-core و lyrebird) با پین‌های ثابت زیر `native/` قرار دارند؛
ورک‌فلوی CI (`.github/workflows/native-ci.yml`) در هر پوش همهٔ پلتفرم‌ها را از
صفر می‌سازد. راهنمای کامل ساخت محلی به فارسی:
[docs/LOCAL_BUILD_FA.md](docs/LOCAL_BUILD_FA.md) و مستندات مهندسی:
[docs/](docs/).

## ساختار ریپو

```
lib/            رابط کاربری Flutter (دارت)
android/        میزبان اندروید (VpnService، کانال‌ها، نوتیفیکیشن)
linux/ windows/ میزبان‌های دسکتاپ (TUN، سینی، پل پنجره)
desktop_shared/ چسب موتور مشترک دسکتاپ (C++‎)
native/         موتورهای پین‌شده: aether، zeptun، psiphon-tunnel-core، lyrebird
design/         سورس‌های طراحی — آیکون‌ها، پرچم‌ها، پترن‌ها، فونت‌ها
scripts/        گیت‌های CI/بیلد و خط تولید رندر آیکون
docs/           مستندات مهندسی (مرجع CLI، ماتریس امکانات، راهنمای بیلد)
evidence/       سابقهٔ اثبات پین‌ها که رکورد CI به آن ارجاع می‌دهد
test/           بدون خطای آنالیز، ۲۴۰+ تست Flutter
```

## حریم خصوصی

AETHONE مستقیم به شبکه‌های ترنسپورت عمومی (وارپ کلادفلر، سایفون، تور) وصل
می‌شود؛ نه آنالیزکس دارد، نه حساب کاربری، نه تله‌متری. لاگ هسته تا وقتی خودتان
پاکش نکنید روی دستگاه خودتان می‌ماند.

</div>
