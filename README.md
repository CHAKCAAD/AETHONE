<div align="center">

<img src="design/brand/app-icon.png" width="112" alt="AETHONE">

# AETHONE

**چند هسته، یک دکمه. کلاینت تونل و پروکسی چندپروتکلی برای اندروید و لینوکس**

*Many cores, one button. A multi-protocol tunnel and proxy client for Android and Linux.*

[![Release](https://img.shields.io/github/v/release/CHAKCAAD/AETHONE?label=release)](https://github.com/CHAKCAAD/AETHONE/releases/latest)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-@AETHONE-26A5E4?logo=telegram)](https://t.me/AETHONE)

[فارسی](#فارسی) · [English](#english)

</div>

---

<div dir="rtl">

## فارسی

AETHONE چند فناوری عبور از فیلترینگ را کنار هم می‌گذارد و پشت یک رابط ساده و یکدست پنهانشان می‌کند. پروتکل را انتخاب کنید، لوکیشن را بچرخانید و وصل شوید؛ بقیه‌اش کار برنامه است.

### تازه‌های نسخهٔ ۱.۰.۲

- **هستهٔ لنترن** (اندروید): پروتکل تازه با انتخاب لوکیشن از سرورهای خود لنترن. اتصال مستقیم روی کشور انتخاب‌شده برقرار می‌شود و همهٔ کشورهایی که لنترن تا حالا اعلام کرده در فهرست می‌مانند.
- **پروکسی تلگرام با یک لمس** در تنظیمات هر پروتکل (Aether، سایفون، تور و لنترن).
- **سرعت اسکن** در تنظیمات هستهٔ Aether با پنج حالت؛ پیش‌فرض: توربو.
- بازطراحی کامل حرکت و انیمیشن‌ها، صفحهٔ انتخاب پروتکل تازه و آیکون‌های اختصاصی در هر دو تم.

### امکانات

| | |
| --- | --- |
| **پروتکل‌ها** | ماسک (MASQUE)، وایرگارد، گول، گول کلاسیک، میم، لنترن |
| **تور و سایفون** | تنها، زنجیره روی وارپ (TOW / POW) و معکوس (WOT / WOP) |
| **حالت هوشمند** | انتخاب خودکار پروتکل بر اساس موفقیت و تأخیر اندازه‌گیری‌شده |
| **تونل یا پروکسی** | VPN کامل دستگاه یا سوکس۵ محلی؛ تونل تک‌برنامه‌ای (فقط برنامه‌های انتخابی یا به‌جز آن‌ها) |
| **مسیریابی کشوری** | ترافیک داخلی ایران، ترکمنستان، روسیه و چین مستقیم، بقیه از تونل |
| **تنظیمات هسته** | فرگمنت TLS، HTTP/2، QUIC v2، اثرانگشت TLS، ECH، سرعت اسکن |
| **دسترسی سریع** | ویجت صفحهٔ اصلی، کاشی تنظیمات سریع و نوتیفیکیشن با دکمهٔ قطع |
| **زبان‌ها** | فارسی، انگلیسی، روسی، چینی و ترکمنی |

### دانلود

همهٔ فایل‌ها در [صفحهٔ ریلیزها](https://github.com/CHAKCAAD/AETHONE/releases/latest) هستند.

- **اندروید** (۷.۰ به بالا): برای هر پردازنده یک APK جدا. `arm64-v8a` برای بیشتر گوشی‌های امروزی، `armeabi-v7a` برای گوشی‌های ۳۲ بیتی و قدیمی، `x86_64` برای شبیه‌سازها.
- **لینوکس** (x86-64، glibc 2.39 به بالا): tar.gz پرتابل، deb، rpm، AppImage و فلت‌پک. راهنمای نصب: [`packaging/linux/README.md`](packaging/linux/README.md).

صحت فایل‌ها را با `SHA256SUMS` همان ریلیز بررسی کنید.

### هسته‌ها

| مؤلفه | زبان | نقش | لایسنس |
| --- | --- | --- | --- |
| [Aether](https://github.com/CluvexStudio/Aether) | Rust | موتور اصلی: ماسک، وایرگارد، گول، میم، تور و سایفون | AGPL-3.0 |
| [Zeptun](https://github.com/Noisemux/zeptun) | Zig | موتور TUN در فضای کاربر؛ پل میان VPN اندروید و سوکس محلی | MIT |
| [Radiance](https://github.com/getlantern/radiance) | Go | هستهٔ لنترن، به‌صورت پردازهٔ جانبی روی `127.0.0.1:1822` | GPL-3.0 |
| Psiphon Tunnel Core و Lyrebird | Go | سایفون و ترنسپورت‌های تور | لایسنس خودشان |

رابط کاربری با Flutter نوشته شده است. Aether درون پردازهٔ برنامه اجرا می‌شود، Zeptun از راه JNI و لنترن به‌عنوان پردازهٔ جداگانه. پیوند لنترن از [MSN-GUARD](https://github.com/mbm110/MSN-GUARD) (AGPL-3.0) اقتباس شده است.

### ساخت از سورس

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE
flutter pub get
flutter analyze && flutter test
```

هسته‌های Native را پیش از ساخت APK کامپایل کنید (`scripts/build_native.sh` و `scripts/build_lantern.sh`). راهنمای کامل: [`docs/LOCAL_BUILD_FA.md`](docs/LOCAL_BUILD_FA.md).

ابزارها: Flutter 3.47.9، Android NDK r26d، JDK 17، Rust 1.99.1 با cargo-ndk 4.1.2، Go 1.26 و Zig 0.16.0.

### وضعیت پروژه

AETHONE در حال توسعه است. کیل‌سوئیچ در سطح سیستم‌عامل و IPv6 در تونل اندروید هنوز کامل نیستند و لنترن فقط روی اندروید در دسترس است. جزئیات هر قابلیت در [`docs/FEATURE_MATRIX.md`](docs/FEATURE_MATRIX.md).

اگر مشکلی دیدید، متن خطا و لاگ هسته (تنظیمات ← لاگ هسته) را در [کانال تلگرام](https://t.me/AETHONE) یا [Issues](https://github.com/CHAKCAAD/AETHONE/issues) بفرستید.

### سپاس

از CluvexStudio برای Aether، از Noisemux برای Zeptun، از تیم Lantern برای Radiance و از نگهدارندگان Psiphon، Lyrebird و MSN-GUARD. این برنامه روی دوش کار آن‌ها ایستاده است.

</div>

---

## English

AETHONE puts several censorship-resistant transports behind one clean interface. Pick a protocol, spin the location wheel, connect; the app handles the rest.

### What's new in 1.0.2

- **Lantern core** (Android): a new protocol with exit locations from Lantern's own servers. It connects straight to the picked country, and every country Lantern has announced stays in the list.
- **One-tap Telegram proxy** in each protocol's settings (Aether, Psiphon, Tor and Lantern).
- **Scan speed** in the Aether core settings with five profiles; turbo by default.
- A full motion-design overhaul, a new protocol picker and custom icons for both themes.

### Features

| | |
| --- | --- |
| **Protocols** | MASQUE, WireGuard, Gool, Gool Classic, MIM, Lantern |
| **Tor and Psiphon** | Standalone, chained over WARP (TOW / POW) and reverse (WOT / WOP) |
| **Smart mode** | Picks the protocol from measured success and latency |
| **Tunnel or proxy** | Full-device VPN or a local SOCKS5 proxy; per-app tunneling (only, or all except) |
| **Country routing** | Domestic traffic for Iran, Turkmenistan, Russia and China goes direct |
| **Core settings** | TLS fragmentation, HTTP/2, QUIC v2, TLS fingerprints, ECH, scan speed |
| **Quick access** | Home-screen widget, Quick Settings tile, notification with a disconnect button |
| **Languages** | Persian, English, Russian, Chinese, Turkmen |

### Download

Everything is on the [releases page](https://github.com/CHAKCAAD/AETHONE/releases/latest).

- **Android** (7.0+): one APK per CPU. `arm64-v8a` for most current phones, `armeabi-v7a` for 32-bit and older phones, `x86_64` for emulators.
- **Linux** (x86-64, glibc 2.39+): portable tar.gz, deb, rpm, AppImage and Flatpak. Install guide (Persian): [`packaging/linux/README.md`](packaging/linux/README.md).

Verify downloads against the release's `SHA256SUMS`.

### Cores

| Component | Language | Role | License |
| --- | --- | --- | --- |
| [Aether](https://github.com/CluvexStudio/Aether) | Rust | Main engine: MASQUE, WireGuard, Gool, MIM, Tor and Psiphon | AGPL-3.0 |
| [Zeptun](https://github.com/Noisemux/zeptun) | Zig | Userspace TUN engine bridging Android's VPN to the local SOCKS | MIT |
| [Radiance](https://github.com/getlantern/radiance) | Go | The Lantern core, run as a sidecar on `127.0.0.1:1822` | GPL-3.0 |
| Psiphon Tunnel Core, Lyrebird | Go | Psiphon and Tor pluggable transports | Their own |

The UI is Flutter. Aether runs in-process, Zeptun through JNI, and Lantern as a separate process. The Lantern bridge is adapted from [MSN-GUARD](https://github.com/mbm110/MSN-GUARD) (AGPL-3.0).

### Building from source

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE
flutter pub get
flutter analyze && flutter test
```

Build the native cores before the APK (`scripts/build_native.sh` and `scripts/build_lantern.sh`). Full guide (Persian): [`docs/LOCAL_BUILD_FA.md`](docs/LOCAL_BUILD_FA.md).

Toolchain: Flutter 3.47.9, Android NDK r26d, JDK 17, Rust 1.99.1 with cargo-ndk 4.1.2, Go 1.26, Zig 0.16.0.

### Documentation

- [Feature matrix](docs/FEATURE_MATRIX.md)
- [Aether CLI reference](docs/CLI_REFERENCE.md)
- [Native engine wiring](docs/M2_ENGINE_WIRING.md)
- [SMART AUTO spec](docs/SMART_AUTO_SPEC.md)

### Status

AETHONE is under active development. The OS-level kill switch and IPv6 in the Android tunnel are not complete, and Lantern is Android-only. Per-feature status lives in the feature matrix.

Found a problem? Send the error text and the core log (Settings → Core log) to the [Telegram channel](https://t.me/AETHONE) or open an [issue](https://github.com/CHAKCAAD/AETHONE/issues).

### Thanks

To CluvexStudio for Aether, Noisemux for Zeptun, the Lantern team for Radiance, and the maintainers of Psiphon, Lyrebird and MSN-GUARD. This app stands on their work.

### License

AETHONE is licensed under the **GNU AGPL-3.0** ([LICENSE](LICENSE)). Third-party components keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [`licenses/`](licenses/).
