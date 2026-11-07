<div dir="ltr">
  AETHONE

A Modern Multi-Protocol Tunnel & Proxy Client for Android

AETHONE is an experimental network tunneling application designed to bring multiple censorship-resistant transport technologies together in a unified, easy-to-use interface.

Built with Flutter and powered by native networking engines, AETHONE integrates Aether and Zeptun to provide flexible connection modes, advanced routing capabilities, and a customizable user experience.

The project aims to make sophisticated networking technologies more accessible through a clean and intuitive application.

---

✨ Features

- Multiple Transport Profiles — MASQUE, WireGuard, GOOL, GOOL Classic, and MIM.
- Tor Integration — Multiple connection arrangements powered by Aether.
- Psiphon Integration — Additional transport options through the Psiphon ecosystem.
- VPN & Proxy Modes — Android VPN tunneling and local SOCKS5 proxy functionality.
- Advanced Routing — Configurable traffic routing and direct/block rules.
- Connection Configuration — Scan profiles, obfuscation settings, DNS and IP configuration.
- Connection Monitoring — Connection status, latency and available traffic statistics.
- Multilingual Interface — Persian, English, Russian, Chinese, and Turkmen.
- Custom Interface — Dedicated visual assets, protocol icons, themes, and animated backgrounds.

«Development status: AETHONE is currently under active development. Some advanced features and transport modes are experimental and have not yet completed full device-level validation. See the project documentation for implementation and testing status.»

🧩 Core Technologies

AETHONE relies on specialized open-source networking projects.

Aether

A Rust-based networking core that provides the foundation for several of AETHONE's transport modes, including MASQUE and WireGuard-based technologies.

- GitHub: https://github.com/CluvexStudio/Aether
- License: GNU AGPL-3.0

Zeptun

A high-performance userspace TUN networking engine written in Zig. Zeptun handles packet forwarding and bridges Android's VPN interface with the application's proxy networking layer.

- GitHub: https://github.com/Noisemux/zeptun
- License: MIT

Additional Components

AETHONE also incorporates other networking components, including Psiphon Tunnel Core and Lyrebird. Their original licenses and notices must be respected.

🏗️ Architecture

The Android implementation combines several technologies:

Component| Technology| Responsibility
Application UI| Flutter / Dart| Interface and application state
Aether Core| Rust / FFI| Main networking and transport engine
Zeptun| Zig / JNI| TUN packet forwarding
Android VPN| Android VpnService| VPN interface and tunnel lifecycle
Psiphon| Go| Additional circumvention transport
Lyrebird| Go| Pluggable transports

Aether runs inside the application process through its native interface, while Zeptun handles the TUN networking layer through JNI.

📱 Platform Support

Current development focus: Android.

Linux and Windows directories may exist in the repository, but they are not currently established release targets.

Check the Releases page for available Android builds:

https://github.com/CHAKCAAD/AETHONE/releases

🔧 Building from Source

Requirements

- Flutter 3.47.9
- Dart 3.13.7
- Android SDK
- Android NDK 26.3.11579264 (r26d)
- JDK 17
- Rust 1.99.1
- cargo-ndk 4.1.2
- Go 1.26.3
- Zig 0.16.0

Clone the Repository

git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE

Install Flutter Dependencies

flutter pub get

Run Static Analysis and Tests

flutter analyze
flutter test

Build Native Engines

The native networking engines must be built before building the Android APK.

Use the repository's native build script and follow the instructions for your target ABI:

bash scripts/build_native.sh \
  --abi arm64-v8a \
  --rust-target aarch64-linux-android \
  --goarch arm64 \
  --api 29 \
  --src-cache .native-cache \
  --out .native-out/arm64-v8a

For the complete build procedure, including native library staging and APK packaging, see:

"Persian Local Build Guide" (docs/LOCAL_BUILD_FA.md)

📚 Documentation

Additional engineering documentation is available in the "docs/" directory.

- "Feature Matrix" (docs/FEATURE_MATRIX.md)
- "Aether CLI Reference" (docs/CLI_REFERENCE.md)
- "Native Engine Integration" (docs/M2_ENGINE_WIRING.md)
- "SMART AUTO Specification" (docs/SMART_AUTO_SPEC.md)
- "Local Build Guide (Persian)" (docs/LOCAL_BUILD_FA.md)

⚠️ Current Development Limitations

AETHONE is an ongoing project, not a finished production-grade networking product.

Some capabilities are still under development or require further device-level testing. In particular:

- SMART AUTO behavior and automatic protocol selection should not be assumed to be fully implemented.
- The Android OS-level kill switch is not yet fully integrated.
- IPv6 handling in the current Android TUN configuration remains incomplete.
- Tor and Psiphon modes require additional real-device validation.
- Speed testing and some diagnostic capabilities remain under development.

For the latest implementation status, refer to "docs/FEATURE_MATRIX.md".

🙏 Credits & Acknowledgements

AETHONE would not be possible without the work of the developers and open-source communities behind its core networking technologies.

A special thank-you to:

"CluvexStudio — Aether" (https://github.com/CluvexStudio/Aether)

For developing and maintaining the powerful Rust-based Aether networking core and making its advanced networking capabilities available to the open-source community.

"Noisemux — Zeptun" (https://github.com/Noisemux/zeptun)

For creating Zeptun, an efficient and high-performance userspace TUN engine that plays an important role in AETHONE's networking architecture.

We sincerely appreciate the time, engineering effort, and dedication invested in these projects. Their work provides an important foundation for AETHONE.

We also acknowledge the contributors and maintainers of the other open-source components used throughout the project.

Open-source software makes projects like AETHONE possible. Thank you! ❤️

📜 Licensing

AETHONE currently does not declare a project-wide license. No root-level "LICENSE" file is present in this repository.

Third-party components retain their respective licenses:

- Aether: GNU Affero General Public License v3.0 (AGPL-3.0).
- Zeptun: MIT License.
- Other bundled components and design assets may have separate licensing requirements.

Please consult the original license files before copying, modifying, or redistributing any component.

The project's overall licensing and redistribution terms will need to be explicitly established.

---

فارسی

اثـان (AETHONE)

یک کلاینت مدرن چندپروتکلی تونل و پروکسی برای اندروید

AETHONE یک برنامه آزمایشی در حوزه شبکه و عبور از محدودیت‌های اینترنت است که با هدف گردآوری فناوری‌های مختلف تونل‌سازی و انتقال ترافیک در یک محیط یکپارچه و ساده توسعه داده می‌شود.

این پروژه با استفاده از Flutter و هسته‌های Native طراحی شده و با بهره‌گیری از دو پروژه قدرتمند Aether و Zeptun تلاش می‌کند امکانات پیشرفته شبکه را در قالب یک رابط کاربری قابل‌استفاده ارائه دهد.

هدف AETHONE فراهم کردن تجربه‌ای منعطف، قابل‌تنظیم و توسعه‌پذیر برای دسترسی به فناوری‌های مختلف ارتباطی است.

✨ امکانات

- پروفایل‌های مختلف ارتباطی: ماسک، وایرگارد، گول، گول کلاسیک و میم.
- یکپارچه‌سازی تور: حالت‌های مختلف اتصال مبتنی بر هسته Aether.
- یکپارچه‌سازی سایفون: پشتیبانی از ترنسپورت‌های مبتنی بر اکوسیستم Psiphon.
- حالت VPN و Proxy: تونل‌سازی ترافیک دستگاه اندرویدی و پروکسی محلی SOCKS5.
- مسیریابی پیشرفته: قوانین مسدودسازی، اتصال مستقیم و تنظیم مسیر ترافیک.
- تنظیمات اتصال: پروفایل‌های اسکن، تنظیمات مبهم‌سازی، DNS و نسخه IP.
- نمایش اطلاعات اتصال: وضعیت ارتباط، تأخیر و آمار ترافیک در بخش‌های پشتیبانی‌شده.
- رابط کاربری چندزبانه: فارسی، انگلیسی، روسی، چینی و ترکمنی.
- طراحی اختصاصی: آیکون‌های اختصاصی پروتکل‌ها، تم‌های مختلف و پس‌زمینه‌های متحرک.

«وضعیت توسعه: این پروژه همچنان در حال توسعه است. بعضی امکانات پیشرفته و حالت‌های ارتباطی آزمایشی هستند و هنوز اعتبارسنجی کامل روی دستگاه‌های واقعی را پشت سر نگذاشته‌اند.»

🧩 هسته‌های اصلی

AETHONE برای عملکرد شبکه خود از پروژه‌های متن‌باز تخصصی استفاده می‌کند.

Aether

هسته‌ای نوشته‌شده با زبان Rust که بخش مهمی از قابلیت‌های ارتباطی AETHONE، از جمله فناوری‌های مبتنی بر MASQUE و WireGuard، بر پایه آن شکل گرفته است.

- مخزن اصلی: https://github.com/CluvexStudio/Aether
- لایسنس: GNU AGPL-3.0

Zeptun

یک موتور قدرتمند و بهینه TUN که با زبان Zig نوشته شده است. این پروژه وظیفه پردازش و انتقال بسته‌های شبکه و ارتباط میان رابط VPN اندروید و لایه پروکسی را بر عهده دارد.

- مخزن اصلی: https://github.com/Noisemux/zeptun
- لایسنس: MIT

سایر مؤلفه‌ها

AETHONE از مؤلفه‌های دیگری مانند Psiphon Tunnel Core و Lyrebird نیز استفاده می‌کند. لایسنس و حقوق توسعه‌دهندگان اصلی این پروژه‌ها محفوظ است.

🏗️ معماری فنی

ساختار نسخه اندروید AETHONE ترکیبی از فناوری‌های زیر است:

مؤلفه| فناوری| وظیفه
رابط کاربری| Flutter / Dart| رابط و مدیریت وضعیت برنامه
هسته Aether| Rust / FFI| موتور اصلی ارتباطی
هسته Zeptun| Zig / JNI| پردازش و انتقال بسته‌های TUN
سرویس VPN| Android VpnService| مدیریت رابط VPN
Psiphon| Go| ترنسپورت ارتباطی مکمل
Lyrebird| Go| ترنسپورت‌های قابل‌جایگزینی

هسته Aether درون فرایند برنامه اجرا می‌شود و Zeptun از طریق JNI ارتباط میان رابط TUN و لایه شبکه را مدیریت می‌کند.

📱 پلتفرم‌ها

تمرکز فعلی توسعه: اندروید

وجود پوشه‌های Linux و Windows در مخزن به معنای پشتیبانی و انتشار نسخه نهایی این سیستم‌عامل‌ها نیست.

برای مشاهده نسخه‌های منتشرشده به صفحه Releases مراجعه کنید:

https://github.com/CHAKCAAD/AETHONE/releases

🔧 ساخت از سورس

برای راه‌اندازی محیط توسعه به ابزارهای زیر نیاز دارید:

- Flutter 3.47.9
- Dart 3.13.7
- Android SDK
- Android NDK 26.3.11579264
- JDK 17
- Rust 1.99.1
- cargo-ndk 4.1.2
- Go 1.26.3
- Zig 0.16.0

دریافت سورس:

git clone https://github.com/CHAKCAAD/AETHONE.git
cd AETHONE

نصب وابستگی‌ها:

flutter pub get

بررسی کد و اجرای تست‌ها:

flutter analyze
flutter test

برای ساخت APK باید ابتدا هسته‌های Native پروژه را طبق راهنمای ساخت کامپایل کنید.

راهنمای کامل فارسی:

"راهنمای ساخت محلی AETHONE" (docs/LOCAL_BUILD_FA.md)

📚 مستندات

مستندات فنی و مهندسی پروژه در پوشه "docs/" قرار دارند:

- "ماتریس امکانات و وضعیت پیاده‌سازی" (docs/FEATURE_MATRIX.md)
- "مرجع تنظیمات هسته Aether" (docs/CLI_REFERENCE.md)
- "مستندات اتصال هسته‌ها به برنامه" (docs/M2_ENGINE_WIRING.md)
- "مشخصات SMART AUTO" (docs/SMART_AUTO_SPEC.md)
- "راهنمای ساخت محلی" (docs/LOCAL_BUILD_FA.md)

⚠️ محدودیت‌های فعلی

AETHONE یک پروژه در حال توسعه است و هنوز نباید آن را محصولی کاملاً نهایی و آماده استفاده حساس و حیاتی در نظر گرفت.

برخی قابلیت‌ها همچنان به توسعه یا آزمایش بیشتر روی دستگاه واقعی نیاز دارند:

- الگوریتم انتخاب هوشمند SMART AUTO نباید به‌عنوان قابلیت کامل و قطعی در نظر گرفته شود.
- کیل‌سوئیچ در سطح قفل ترافیک سیستم‌عامل اندروید هنوز به‌طور کامل پیاده‌سازی نشده است.
- پشتیبانی IPv6 در تنظیمات فعلی TUN اندروید کامل نیست.
- حالت‌های Tor و Psiphon به اعتبارسنجی بیشتر روی دستگاه نیاز دارند.
- تست سرعت و برخی امکانات تشخیصی همچنان در حال توسعه هستند.

برای مشاهده جزئیات و وضعیت دقیق هر قابلیت، فایل "docs/FEATURE_MATRIX.md" را بررسی کنید.

🙏 سپاسگزاری و قدردانی

توسعه AETHONE بدون استفاده از تلاش‌ها و دستاوردهای جامعه متن‌باز امکان‌پذیر نبود.

به همین دلیل، قدردانی ویژه‌ای داریم از:

"CluvexStudio — پروژه Aether" (https://github.com/CluvexStudio/Aether)

برای توسعه و نگهداری هسته قدرتمند Aether با زبان Rust و فراهم کردن زیرساختی پیشرفته برای ارتباطات شبکه‌ای و فناوری‌های عبور از محدودیت‌ها.

"Noisemux — پروژه Zeptun" (https://github.com/Noisemux/zeptun)

برای خلق و توسعه Zeptun؛ موتور سریع و بهینه TUN که نقش مهمی در معماری شبکه‌ای AETHONE ایفا می‌کند.

از زمان، دانش، تلاش فنی و تعهد توسعه‌دهندگان این دو پروژه صمیمانه سپاسگزاریم. بخش مهمی از زیرساخت AETHONE بر پایه دستاوردهای ارزشمند آن‌ها شکل گرفته است.

همچنین از تمام توسعه‌دهندگان و نگهدارندگان سایر پروژه‌های متن‌باز مورد استفاده در AETHONE قدردانی می‌کنیم.

قدرت نرم‌افزار آزاد در همکاری و اشتراک دانش است. ❤️

📜 مجوز و لایسنس

در حال حاضر AETHONE لایسنس کلی مشخصی ندارد و فایل "LICENSE" در ریشه مخزن موجود نیست.

مؤلفه‌های شخص ثالث همچنان تحت لایسنس اصلی خودشان قرار دارند:

- Aether: تحت GNU AGPL نسخه ۳.
- Zeptun: تحت لایسنس MIT.
- سایر هسته‌ها، وابستگی‌ها، فونت‌ها و فایل‌های طراحی ممکن است لایسنس‌های مستقل داشته باشند.

پیش از کپی، تغییر یا بازنشر هر مؤلفه، فایل لایسنس اصلی آن را بررسی کنید.

تعیین لایسنس نهایی AETHONE و شرایط بازنشر آن نیازمند بررسی و اعلام رسمی جداگانه است.
</div>
