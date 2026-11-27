<div align="center">

<img src="design/brand/app-icon.png" width="112" alt="AETHONE">

# AETHONE

**ایتن — چند هسته، یک دکمه. کلاینت چندپروتکلی تونل و پروکسی برای اندروید**

*Many cores, one button. A multi-protocol tunnel and proxy client for Android.*

[![Release](https://img.shields.io/github/v/release/CHAKCAAD/AETHONE?label=release)](https://github.com/CHAKCAAD/AETHONE/releases/latest)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-@AETHONE-26A5E4?logo=telegram)](https://t.me/AETHONE)

[فارسی](#persian) · [English](#english) · [Русский](#russian) · [简体中文](#chinese) · [Türkmençe](#turkmen)

</div>

---

<a id="persian"></a>
<div dir="rtl">

## فارسی

ایتن چند فناوری و هستهٔ ارتباطی را در یک رابط یکپارچه گرد هم می‌آورد. پروتکل را انتخاب کنید، موقعیت خروج را مشخص کنید و متصل شوید؛ مدیریت اتصال را به ایتن بسپارید.

### تازه‌های نسخهٔ ۱.۰.۳

- **مسیریابی ترکیبی (Hybrid Routing):** تعیین مسیر ترافیک بر اساس برنامه، دامنه و آدرس IP در اتصال‌های ترکیبی.
- **تحلیل ترافیک (Traffic Analytics):** مشاهدهٔ مصرف اینترنت به تفکیک برنامه و مسیر، همراه با سرعت لحظه‌ای، بیشترین سرعت و میانگین سرعت.
- مشاهده و مقایسهٔ آمار در بازه‌های زمانی مختلف و خروجی گرفتن با فرمت‌های CSV و JSON.
- **بازطراحی صفحهٔ تنظیمات:** دسته‌بندی بهتر، جست‌وجوی تنظیمات و دسترسی ساده‌تر به بخش‌های مختلف.

در اتصال‌های ترکیبی زیر می‌توانید مسیر ترافیک را برای برنامه‌ها، دامنه‌ها و IPها مشخص کنید:

- WARP → Psiphon
- Psiphon → WARP
- WARP → Tor
- Tor → WARP

قوانین مسیریابی بدون نیاز به قطع اتصال به‌روزرسانی می‌شوند. داده‌های تحلیل ترافیک نیز به‌صورت محلی روی دستگاه نگه‌داری می‌شوند.

### پروتکل‌ها و امکانات

| بخش | موارد پشتیبانی‌شده |
| --- | --- |
| **پروتکل‌های اصلی** | MASQUE، WireGuard (WARP)، GOOL، GOOL Classic، MIM و Lantern |
| **Tor و Psiphon** | حالت مستقل، زنجیره‌ای روی WARP و حالت معکوس |
| **مسیریابی ترکیبی** | انتخاب مسیر بر اساس برنامه، دامنهٔ دقیق، دامنهٔ وایلدکارد و IP/CIDR |
| **تونل یا پروکسی** | VPN برای کل دستگاه یا پروکسی محلی SOCKS5؛ تونل‌کردن برنامه‌های انتخابی یا مستثناکردن آن‌ها |
| **مسیریابی کشوری** | امکان عبور مستقیم ترافیک داخلی ایران، ترکمنستان، روسیه و چین |
| **تنظیمات هسته** | TLS Fragmentation، HTTP/2، QUIC v2، اثرانگشت TLS، ECH و تنظیمات اسکن |
| **دسترسی سریع** | ویجت صفحهٔ اصلی، کاشی تنظیمات سریع و اعلان دارای دکمهٔ قطع اتصال |
| **زبان‌های برنامه** | فارسی، انگلیسی، روسی، چینی و ترکمنی |

### دریافت و نصب

تمام فایل‌های نسخهٔ جدید در [صفحهٔ انتشارها](https://github.com/CHAKCAAD/AETHONE/releases/latest) قرار می‌گیرند.

- **اندروید ۷ به بالا:** نسخه‌های APK برای معماری‌های مختلف ارائه می‌شوند.
- `arm64-v8a`: مناسب بیشتر گوشی‌های امروزی با پردازندهٔ ۶۴ بیتی.
- `armeabi-v7a`: مناسب دستگاه‌های قدیمی‌تر با پردازندهٔ ۳۲ بیتی.
- `x86_64`: مناسب شبیه‌سازهای اندروید و دستگاه‌های مبتنی بر این معماری.
- `universal`: نسخهٔ عمومی، برای زمانی که معماری دستگاه را نمی‌دانید.

### هسته‌ها و وابستگی‌ها

| مؤلفه | زبان | نقش | مجوز |
| --- | --- | --- | --- |
| [Aether](https://github.com/CluvexStudio/Aether) | Rust | هستهٔ اصلی اتصال؛ شامل MASQUE، WireGuard، GOOL، MIM، Tor و Psiphon | AGPL-3.0 |
| [Zeptun](https://github.com/Noisemux/zeptun) | Zig | موتور TUN در فضای کاربر و پل میان VPN اندروید و پروکسی محلی | MIT |
| [Radiance](https://github.com/getlantern/radiance) | Go | هستهٔ Lantern | GPL-3.0 |
| Psiphon Tunnel Core و Lyrebird | Go | زیرساخت Psiphon و ترنسپورت‌های قابل‌جایگزینی Tor | مجوزهای مربوط به خودشان |

رابط کاربری با Flutter ساخته شده است. Aether درون پردازهٔ برنامه اجرا می‌شود، Zeptun از طریق JNI در دسترس است و Lantern به‌صورت پردازهٔ جداگانه اجرا می‌شود. اتصال Lantern از [MSN-GUARD](https://github.com/mbm110/MSN-GUARD) اقتباس شده است.

### ساخت از سورس

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE
flutter pub get
flutter analyze && flutter test
```

پیش از ساخت APK باید هسته‌های Native را نیز بسازید؛ برای این کار از `scripts/build_native.sh` و `scripts/build_lantern.sh` استفاده کنید. راهنمای ساخت: [docs/LOCAL_BUILD_FA.md](docs/LOCAL_BUILD_FA.md).

ابزارهای نسخهٔ فعلی پروژه: Flutter 3.47.9، Android NDK r26d، JDK 17، Rust 1.99.1 با cargo-ndk 4.1.2، Go 1.26 و Zig 0.16.0.

### وضعیت پروژه

توسعهٔ ایتن ادامه دارد و اندروید پلتفرم اصلی نسخهٔ فعلی است. پشتیبانی Lantern در نسخهٔ اندروید ارائه می‌شود. کیل‌سوئیچ در سطح سیستم‌عامل و پشتیبانی IPv6 در تونل اندروید هنوز کامل نشده‌اند. وضعیت جزئی قابلیت‌ها در [ماتریس امکانات](docs/FEATURE_MATRIX.md) ثبت شده است.

برای گزارش مشکل، متن خطا و لاگ هسته (تنظیمات ← لاگ هسته) را در [کانال تلگرام](https://t.me/AETHONE) ارسال کنید یا در [بخش Issues](https://github.com/CHAKCAAD/AETHONE/issues) یک گزارش ثبت کنید.

### سپاسگزاری

از CluvexStudio برای Aether، از Noisemux برای Zeptun، از تیم Lantern برای Radiance و از نگه‌دارندگان Psiphon، Lyrebird و MSN-GUARD سپاسگزاریم. ایتن بر پایهٔ تلاش و دستاوردهای این پروژه‌های متن‌باز ساخته شده است.

### مجوز

ایتن تحت مجوز **GNU AGPL-3.0** منتشر می‌شود. اجزای شخص ثالث از مجوزهای خود پیروی می‌کنند؛ جزئیات در [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) و پوشهٔ [licenses](licenses/) قرار دارد.

</div>

---

<a id="english"></a>
## English

AETHONE brings multiple connectivity technologies and engines together behind one consistent interface. Choose a protocol, select an exit location, and connect — let AETHONE handle the connection.

### What's new in 1.0.3

- **Hybrid Routing:** choose traffic paths by app, domain, and IP address in supported hybrid connections.
- **Traffic Analytics:** inspect data usage by app and route, with live, peak, and average speed.
- Review and compare usage across different time ranges, and export statistics as CSV or JSON.
- **Redesigned Settings:** clearer categories, settings search, and easier access to app features.

Hybrid routing is available for these combinations:

- WARP → Psiphon
- Psiphon → WARP
- WARP → Tor
- Tor → WARP

Routing rules can be changed without disconnecting. Traffic analytics data is stored locally on the device.

### Protocols and features

| Area | Supported options |
| --- | --- |
| **Core protocols** | MASQUE, WireGuard (WARP), GOOL, GOOL Classic, MIM, and Lantern |
| **Tor and Psiphon** | Standalone, chained over WARP, and reverse modes |
| **Hybrid routing** | Routing by app, exact domain, wildcard domain, and IP/CIDR |
| **Tunnel or proxy** | Full-device VPN or local SOCKS5 proxy; tunnel selected apps or exclude them |
| **Country routing** | Direct routing for domestic traffic in Iran, Turkmenistan, Russia, and China |
| **Core settings** | TLS fragmentation, HTTP/2, QUIC v2, TLS fingerprints, ECH, and scan settings |
| **Quick access** | Home-screen widget, Quick Settings tile, and notification with a disconnect action |
| **App languages** | Persian, English, Russian, Chinese, and Turkmen |

### Download and installation

All current release files are available on the [GitHub Releases page](https://github.com/CHAKCAAD/AETHONE/releases/latest).

- **Android 7 and later:** APKs are provided for different processor architectures.
- `arm64-v8a`: recommended for most modern 64-bit Android phones.
- `armeabi-v7a`: for older 32-bit devices.
- `x86_64`: for Android emulators and devices using this architecture.
- `universal`: a general-purpose build if you are unsure which architecture your device uses.

### Cores and dependencies

| Component | Language | Role | License |
| --- | --- | --- | --- |
| [Aether](https://github.com/CluvexStudio/Aether) | Rust | Main connectivity engine: MASQUE, WireGuard, GOOL, MIM, Tor, and Psiphon | AGPL-3.0 |
| [Zeptun](https://github.com/Noisemux/zeptun) | Zig | Userspace TUN engine bridging Android VPN and the local proxy | MIT |
| [Radiance](https://github.com/getlantern/radiance) | Go | Lantern core | GPL-3.0 |
| Psiphon Tunnel Core and Lyrebird | Go | Psiphon infrastructure and Tor pluggable transports | Their respective licenses |

The user interface is built with Flutter. Aether runs in-process, Zeptun is accessed through JNI, and Lantern runs as a separate process. The Lantern integration is adapted from [MSN-GUARD](https://github.com/mbm110/MSN-GUARD).

### Build from source

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE
flutter pub get
flutter analyze && flutter test
```

Build the native cores before building the APK, using `scripts/build_native.sh` and `scripts/build_lantern.sh`. Build guide: [docs/LOCAL_BUILD_FA.md](docs/LOCAL_BUILD_FA.md).

Current toolchain: Flutter 3.47.9, Android NDK r26d, JDK 17, Rust 1.99.1 with cargo-ndk 4.1.2, Go 1.26, and Zig 0.16.0.

### Project status

AETHONE is under active development, with Android as the primary platform for the current release. Lantern is available in the Android version. The OS-level kill switch and IPv6 support in the Android tunnel are not complete yet. See the [Feature Matrix](docs/FEATURE_MATRIX.md) for per-feature status.

To report an issue, share the error text and core log (Settings → Core log) in the [Telegram channel](https://t.me/AETHONE) or open an [issue](https://github.com/CHAKCAAD/AETHONE/issues).

### Acknowledgements

Thanks to CluvexStudio for Aether, Noisemux for Zeptun, the Lantern team for Radiance, and the maintainers of Psiphon, Lyrebird, and MSN-GUARD. AETHONE builds on the work of these open-source projects.

### License

AETHONE is released under the **GNU AGPL-3.0** license. Third-party components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the [licenses](licenses/) directory.

---

<a id="russian"></a>
## Русский

AETHONE объединяет несколько технологий и сетевых движков в едином интерфейсе. Выберите протокол и выходную локацию, подключитесь — остальным займётся AETHONE.

### Что нового в версии 1.0.3

- **Гибкая маршрутизация (Hybrid Routing):** выбор маршрута трафика по приложению, домену и IP-адресу в поддерживаемых комбинированных подключениях.
- **Анализ трафика (Traffic Analytics):** просмотр расхода трафика по приложениям и маршрутам, а также текущей, максимальной и средней скорости.
- Просмотр и сравнение статистики за разные периоды, экспорт данных в CSV и JSON.
- **Обновлённая страница настроек:** более понятные категории, поиск по настройкам и быстрый доступ к функциям приложения.

Гибкая маршрутизация поддерживается для следующих комбинаций:

- WARP → Psiphon
- Psiphon → WARP
- WARP → Tor
- Tor → WARP

Правила маршрутизации можно менять без отключения соединения. Данные анализа трафика хранятся локально на устройстве.

### Протоколы и возможности

| Раздел | Поддерживаемые варианты |
| --- | --- |
| **Основные протоколы** | MASQUE, WireGuard (WARP), GOOL, GOOL Classic, MIM и Lantern |
| **Tor и Psiphon** | Автономный режим, цепочка через WARP и обратный режим |
| **Гибкая маршрутизация** | Маршрутизация по приложению, точному домену, маске домена и IP/CIDR |
| **Туннель или прокси** | VPN для всего устройства или локальный SOCKS5-прокси; туннелирование выбранных приложений или исключение приложений |
| **Маршрутизация по странам** | Прямой маршрут для внутреннего трафика Ирана, Туркменистана, России и Китая |
| **Настройки ядра** | Фрагментация TLS, HTTP/2, QUIC v2, TLS-отпечатки, ECH и настройки сканирования |
| **Быстрый доступ** | Виджет главного экрана, плитка быстрых настроек и уведомление с кнопкой отключения |
| **Языки приложения** | Персидский, английский, русский, китайский и туркменский |

### Загрузка и установка

Все актуальные файлы доступны на [странице релизов GitHub](https://github.com/CHAKCAAD/AETHONE/releases/latest).

- **Android 7 и новее:** доступны APK для разных архитектур процессора.
- `arm64-v8a`: рекомендуется для большинства современных 64-битных телефонов.
- `armeabi-v7a`: для старых 32-битных устройств.
- `x86_64`: для эмуляторов Android и устройств с этой архитектурой.
- `universal`: универсальная сборка, если вы не знаете архитектуру своего устройства.

### Ядра и зависимости

| Компонент | Язык | Назначение | Лицензия |
| --- | --- | --- | --- |
| [Aether](https://github.com/CluvexStudio/Aether) | Rust | Основной сетевой движок: MASQUE, WireGuard, GOOL, MIM, Tor и Psiphon | AGPL-3.0 |
| [Zeptun](https://github.com/Noisemux/zeptun) | Zig | Пользовательский TUN-движок, соединяющий Android VPN с локальным прокси | MIT |
| [Radiance](https://github.com/getlantern/radiance) | Go | Ядро Lantern | GPL-3.0 |
| Psiphon Tunnel Core и Lyrebird | Go | Инфраструктура Psiphon и подключаемые транспорты Tor | Собственные лицензии |

Пользовательский интерфейс разработан на Flutter. Aether работает внутри процесса приложения, Zeptun подключается через JNI, а Lantern запускается отдельным процессом. Интеграция Lantern адаптирована из проекта [MSN-GUARD](https://github.com/mbm110/MSN-GUARD).

### Сборка из исходного кода

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE
flutter pub get
flutter analyze && flutter test
```

Перед сборкой APK необходимо собрать нативные ядра с помощью `scripts/build_native.sh` и `scripts/build_lantern.sh`. Руководство по сборке: [docs/LOCAL_BUILD_FA.md](docs/LOCAL_BUILD_FA.md).

Текущий набор инструментов: Flutter 3.47.9, Android NDK r26d, JDK 17, Rust 1.99.1 с cargo-ndk 4.1.2, Go 1.26 и Zig 0.16.0.

### Статус проекта

AETHONE продолжает активно развиваться; основной платформой текущего выпуска является Android. Lantern доступен в версии для Android. Системный Kill Switch и поддержка IPv6 в Android-туннеле пока не завершены. Подробный статус функций см. в [матрице возможностей](docs/FEATURE_MATRIX.md).

Чтобы сообщить об ошибке, отправьте текст ошибки и журнал ядра (Настройки → Core log) в [Telegram-канал](https://t.me/AETHONE) или создайте [issue](https://github.com/CHAKCAAD/AETHONE/issues).

### Благодарности

Благодарим CluvexStudio за Aether, Noisemux за Zeptun, команду Lantern за Radiance, а также сопровождающих Psiphon, Lyrebird и MSN-GUARD. AETHONE создан на основе работы этих проектов с открытым исходным кодом.

### Лицензия

AETHONE распространяется по лицензии **GNU AGPL-3.0**. Сторонние компоненты сохраняют собственные лицензии; подробности находятся в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) и каталоге [licenses](licenses/).

---

<a id="chinese"></a>
## 简体中文

AETHONE 将多种网络连接技术和核心整合在统一、简洁的界面中。选择协议和出口位置，然后连接；其余工作交给 AETHONE。

### 1.0.3 版本更新

- **混合路由（Hybrid Routing）：** 在支持的组合连接中，可根据应用、域名和 IP 地址选择流量路径。
- **流量分析（Traffic Analytics）：** 按应用和路由查看流量使用情况，并查看实时速度、峰值速度和平均速度。
- 查看和比较不同时间段的流量统计，并导出为 CSV 或 JSON 格式。
- **设置页面重新设计：** 分类更清晰，支持搜索设置项，访问各项功能更加方便。

以下组合支持混合路由：

- WARP → Psiphon
- Psiphon → WARP
- WARP → Tor
- Tor → WARP

无需断开连接即可修改路由规则。流量分析数据仅保存在设备本地。

### 协议与功能

| 类别 | 支持的选项 |
| --- | --- |
| **核心协议** | MASQUE、WireGuard（WARP）、GOOL、GOOL Classic、MIM 和 Lantern |
| **Tor 与 Psiphon** | 独立模式、通过 WARP 的链式模式和反向模式 |
| **混合路由** | 按应用、精确域名、通配符域名和 IP/CIDR 进行路由 |
| **隧道或代理** | 全设备 VPN 或本地 SOCKS5 代理；仅隧道传输指定应用，或排除指定应用 |
| **国家路由** | 伊朗、土库曼斯坦、俄罗斯和中国的本地流量可直接路由 |
| **核心设置** | TLS 分片、HTTP/2、QUIC v2、TLS 指纹、ECH 和扫描设置 |
| **快捷访问** | 主屏幕小组件、快捷设置磁贴，以及带断开按钮的通知 |
| **应用语言** | 波斯语、英语、俄语、中文和土库曼语 |

### 下载与安装

所有当前版本的安装文件均可在 [GitHub Releases 页面](https://github.com/CHAKCAAD/AETHONE/releases/latest) 获取。

- **Android 7 及更高版本：** 提供适用于不同处理器架构的 APK。
- `arm64-v8a`：推荐大多数现代 64 位 Android 手机使用。
- `armeabi-v7a`：适用于较旧的 32 位设备。
- `x86_64`：适用于 Android 模拟器及采用该架构的设备。
- `universal`：通用版本；不确定设备架构时可选择此版本。

### 核心组件与依赖

| 组件 | 语言 | 作用 | 许可证 |
| --- | --- | --- | --- |
| [Aether](https://github.com/CluvexStudio/Aether) | Rust | 核心连接引擎：MASQUE、WireGuard、GOOL、MIM、Tor 和 Psiphon | AGPL-3.0 |
| [Zeptun](https://github.com/Noisemux/zeptun) | Zig | 用户态 TUN 引擎，连接 Android VPN 与本地代理 | MIT |
| [Radiance](https://github.com/getlantern/radiance) | Go | Lantern 核心 | GPL-3.0 |
| Psiphon Tunnel Core 与 Lyrebird | Go | Psiphon 基础组件及 Tor 可插拔传输 | 各自的许可证 |

用户界面使用 Flutter 构建。Aether 在应用进程内运行，Zeptun 通过 JNI 调用，Lantern 则作为独立进程运行。Lantern 集成部分基于 [MSN-GUARD](https://github.com/mbm110/MSN-GUARD) 改编。

### 从源代码构建

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE
flutter pub get
flutter analyze && flutter test
```

构建 APK 之前，需要先使用 `scripts/build_native.sh` 和 `scripts/build_lantern.sh` 构建原生核心。构建指南：[docs/LOCAL_BUILD_FA.md](docs/LOCAL_BUILD_FA.md)。

当前工具链：Flutter 3.47.9、Android NDK r26d、JDK 17、Rust 1.99.1（cargo-ndk 4.1.2）、Go 1.26 和 Zig 0.16.0。

### 项目状态

AETHONE 仍在积极开发中，当前版本以 Android 为主要平台。Lantern 功能在 Android 版本中提供。系统级 Kill Switch 和 Android 隧道中的 IPv6 支持尚未完成。各项功能的详细状态请参阅[功能矩阵](docs/FEATURE_MATRIX.md)。

如需反馈问题，请将错误信息和核心日志（设置 → Core log）发送至 [Telegram 频道](https://t.me/AETHONE)，或在 [Issues](https://github.com/CHAKCAAD/AETHONE/issues) 中提交问题。

### 致谢

感谢 CluvexStudio 提供 Aether，感谢 Noisemux 提供 Zeptun，感谢 Lantern 团队开发 Radiance，也感谢 Psiphon、Lyrebird 和 MSN-GUARD 的维护者。AETHONE 建立在这些开源项目的成果之上。

### 许可证

AETHONE 使用 **GNU AGPL-3.0** 许可证发布。第三方组件仍遵循各自的许可证，详情请参阅 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [licenses](licenses/) 目录。

---

<a id="turkmen"></a>
## Türkmençe

AETHONE birnäçe birikme tehnologiýalaryny we hereketlendirijilerini ýeke-täk, düşnükli interfeýsde birleşdirýär. Protokoly we çykış ýerini saýlaň-da birigiň — galan işleri AETHONE ýerine ýetirýär.

### 1.0.3 wersiýadaky täzelikler

- **Gibrid marşrutlaşdyrma (Hybrid Routing):** goldanýan gibrid birikmelerde traffigi programma, domen we IP salgysy boýunça ugrukdyrmak.
- **Traffigi seljermek (Traffic Analytics):** internet sarp edilişini programma we marşrut boýunça görmek; häzirki, iň ýokary we ortaça tizligi yzarlamak.
- Dürli wagt aralyklary üçin statistikany görmek we deňeşdirmek, maglumatlary CSV ýa-da JSON görnüşinde eksport etmek.
- **Sazlamalar sahypasynyň täzelenişi:** has düşnükli toparlar, sazlamalaryň içinden gözleg we mümkinçiliklere aňsat giriş.

Gibrid marşrutlaşdyrma şu utgaşmalarda elýeterlidir:

- WARP → Psiphon
- Psiphon → WARP
- WARP → Tor
- Tor → WARP

Birikmäni kesmezden marşrut düzgünlerini üýtgedip bolýar. Traffigi seljermek üçin maglumatlar enjamyň özünde ýerli görnüşde saklanýar.

### Protokollar we mümkinçilikler

| Bölüm | Goldanylýan görnüşler |
| --- | --- |
| **Esasy protokollar** | MASQUE, WireGuard (WARP), GOOL, GOOL Classic, MIM we Lantern |
| **Tor we Psiphon** | Aýratyn işlediş, WARP arkaly zynjyrly we ters tertipler |
| **Gibrid marşrutlaşdyrma** | Programma, takyk domen, şablon domen we IP/CIDR boýunça marşrutlaşdyrma |
| **Tunel ýa-da proksi** | Bütin enjam üçin VPN ýa-da ýerli SOCKS5 proksi; saýlanan programmalary tunelden geçirmek ýa-da olary aýratyn goýmak |
| **Ýurt boýunça marşrutlaşdyrma** | Eýran, Türkmenistan, Russiýa we Hytaýyň içerki traffigini göni geçirmek |
| **Ýadro sazlamalary** | TLS böleklendirmesi, HTTP/2, QUIC v2, TLS fingerprint, ECH we skanirleme sazlamalary |
| **Çalt giriş** | Baş ekran widjeti, Çalt sazlamalar plitkasy we birikmäni kesmek düwmeli bildiriş |
| **Programma dilleri** | Parsça, iňlisçe, rusça, hytaýça we türkmençe |

### Ýüklemek we gurnamak

Iň täze faýllaryň hemmesi [GitHub Releases sahypasynda](https://github.com/CHAKCAAD/AETHONE/releases/latest) ýerleşýär.

- **Android 7 we ondan täze:** dürli prosessor arhitekturalary üçin APK faýllary bar.
- `arm64-v8a`: häzirki zaman 64 bitli Android telefonlarynyň köpüsi üçin maslahat berilýär.
- `armeabi-v7a`: köne 32 bitli enjamlar üçin.
- `x86_64`: Android emulatorlary we şu arhitekturany ulanýan enjamlar üçin.
- `universal`: enjamyňyzyň arhitekturasyny bilmeseňiz, umumy wersiýa.

### Ýadrolar we garaşlylyklar

| Komponent | Dil | Wezipesi | Lisenziýa |
| --- | --- | --- | --- |
| [Aether](https://github.com/CluvexStudio/Aether) | Rust | Esasy birikme hereketlendirijisi: MASQUE, WireGuard, GOOL, MIM, Tor we Psiphon | AGPL-3.0 |
| [Zeptun](https://github.com/Noisemux/zeptun) | Zig | Android VPN bilen ýerli proksiniň arasynda köpri bolup işleýän userspace TUN hereketlendirijisi | MIT |
| [Radiance](https://github.com/getlantern/radiance) | Go | Lantern ýadrosy | GPL-3.0 |
| Psiphon Tunnel Core we Lyrebird | Go | Psiphon infrastrukturası we Tor plagin transportlary | Öz lisenziýalary |

Ulanyjy interfeýsi Flutter bilen döredildi. Aether programmanyň öz prosesinde işleýär, Zeptun JNI arkaly çagyrylýar, Lantern bolsa aýratyn proses hökmünde işleýär. Lantern integrasiýasy [MSN-GUARD](https://github.com/mbm110/MSN-GUARD) taslamasyndan uýgunlaşdyryldy.

### Çeşme kodundan ýygnamak

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE
flutter pub get
flutter analyze && flutter test
```

APK ýygnamazdan öň `scripts/build_native.sh` we `scripts/build_lantern.sh` arkaly native ýadrolary ýygnamaly. Ýygnamak boýunça gollanma: [docs/LOCAL_BUILD_FA.md](docs/LOCAL_BUILD_FA.md).

Häzirki gurallar toplumy: Flutter 3.47.9, Android NDK r26d, JDK 17, cargo-ndk 4.1.2 bilen Rust 1.99.1, Go 1.26 we Zig 0.16.0.

### Taslamanyň ýagdaýy

AETHONE işjeň ösdürilýär; häzirki wersiýanyň esasy platformasy Android bolup durýar. Lantern Android wersiýasynda elýeterlidir. Operasion ulgam derejesindäki Kill Switch we Android tunelindäki IPv6 goldawy entek doly taýýar däl. Aýratyn mümkinçilikleriň ýagdaýyny [Mümkinçilikler matrisasyndan](docs/FEATURE_MATRIX.md) görüň.

Meseläni habar bermek üçin ýalňyşlygyň tekstini we ýadro žurnalyny (Sazlamalar → Core log) [Telegram kanalyna](https://t.me/AETHONE) iberiň ýa-da [Issues](https://github.com/CHAKCAAD/AETHONE/issues) bölüminde habar açyň.

### Minnetdarlyk

Aether üçin CluvexStudio-a, Zeptun üçin Noisemux-a, Radiance üçin Lantern toparyna, şeýle hem Psiphon, Lyrebird we MSN-GUARD taslamalarynyň goldaýjylaryna minnetdarlyk bildirýäris. AETHONE bu açyk çeşmeli taslamalaryň zähmetiniň esasynda döredildi.

### Lisenziýa

AETHONE **GNU AGPL-3.0** lisenziýasy bilen ýaýradylýar. Üçünji tarap komponentleri öz lisenziýalaryna eýerýär; jikme-jiklikler [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) faýlynda we [licenses](licenses/) bukjasynda ýerleşýär.
