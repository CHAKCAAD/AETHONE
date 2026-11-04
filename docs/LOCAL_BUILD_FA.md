# راهنمای بیلد محلی با Android Studio (و بدون GitHub Actions)

> **چرا این سند؟** سهمیه GitHub Actions تمام شده است (`v4.21`). از این به بعد بیلد APK
> روی سیستم خودتان انجام می‌شود. این راهنما **دقیقاً همان پین‌ها و همان دستورات CI**
> را قدم‌به‌قدم برای ویندوز/لینوکس/مک بازسازی می‌کند — هیچ نسخه‌ای «حدسی» نیست؛ همه
> از `native-ci.yml` و `scripts/build_native.sh` استخراج شده‌اند.

---

## ۰) خلاصهٔ معماری بیلد

APK نهایی از **دو لایه** ساخته می‌شود:

| لایه | خروجی | ابزار |
|---|---|---|
| هسته‌های نیتیو (سه زبان) | `libaether.so`، `liblyrebird.so`، `libpsiphon.so`، `libzeptun-jni.so` | Rust + Go + Zig + NDK |
| اپ Flutter | `app-release.apk` / `app-debug.apk` | Flutter 3.47.9 + Gradle 9.8.2 + AGP 9.4.0 |

نیتیوها اول ساخته و در `android/app/src/main/jniLibs/<abi>/` کپی می‌شوند، بعد
`flutter build apk` آن‌ها را داخل APK قرار می‌دهد (`extractNativeLibs=true` — چون
هسته، `liblyrebird.so` و `libpsiphon.so` را به‌صورت پروسه exec می‌کند و فایل واقعی
با مجوز اجرا لازم است).

---

## ۱) نصب پیش‌نیازها (یک‌بار برای همیشه)

### ۱-۱) Android Studio + SDK

1. Android Studio (هر نسخهٔ اخیر) را نصب کنید.
2. از **Tools → SDK Manager** این‌ها را نصب کنید:
   - **Android SDK Platform 36** (compileSdk/targetSdk اپ)
   - **Android SDK Build-Tools 36.0.0** (پین CI)
   - **NDK نسخهٔ 26.3.11579264 (r26d)** — ⚠️ دقیقاً همین نسخه؛ در تب
     *SDK Tools → Show Package Details* قابل انتخاب است.
3. مسیر SDK معمولاً: ویندوز `C:\Users\<you>\AppData\Local\Android\Sdk`،
   مک `~/Library/Android/sdk`، لینوکس `~/Android/Sdk`.

### ۱-۲) JDK 17

Android Studio خودش JBR 17 دارد و برای Gradle کافی است. اگر ترمینال جدا استفاده
می‌کنید، Temurin **17.0.21+9** را نصب کنید و `JAVA_HOME` را به آن بدهید.

### ۱-۳) Flutter 3.47.9 (پین دقیق)

```bash
# ویندوز (PowerShell):
git clone https://github.com/flutter/flutter.git -b 3.47.9 --depth 1 C:\flutter
# لینوکس/مک:
git clone https://github.com/flutter/flutter.git -b 3.47.9 --depth 1 ~/flutter
export PATH="$HOME/flutter/bin:$PATH"        # (در .bashrc/.zshrc دائمی کنید)
flutter doctor
```

در `flutter doctor` باید همهٔ آیتم‌های Android سبز باشند.

### ۱-۴) ابزارهای هسته‌ها

| ابزار | نسخهٔ پین | نصب |
|---|---|---|
| Rust (stable) | **1.99.1** | `rustup default 1.99.1` |
| Rust برای اندروید | targets | `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android` |
| cargo-ndk | **4.1.2** | `cargo install cargo-ndk --version 4.1.2` |
| Go | **1.26.3** | از go.dev/dl (متغیر `GOTOOLCHAIN=local` لازم نیست؛ فایل go.mod خودش پین است) |
| Zig | **0.16.0** | از ziglang.org — SHA256 نسخهٔ x86_64: `70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00` |

همه را در `PATH` بگذارید.

---

## ۲) گرفتن سورس و تنظیم اولیه

```bash
git clone https://github.com/CHAKCAAD/AETHONE.git aethone
cd aethone
git checkout ci-bootstrap/v4.4        # شاخهٔ فعال
flutter pub get
```

> **نکتهٔ مهم:** ساب‌ماژول‌های `native/` (aether، psiphon-tunnel-core، zeptun)
> خودشان داخل همین ریپو commit شده‌اند — نیازی به `git submodule` نیست.

فایل `android/local.properties` را بسازید/ویرایش کنید (مسیر SDK و Flutter خودتان):

```properties
sdk.dir=C:\\Users\\<you>\\AppData\\Local\\Android\\Sdk
flutter.sdk=C:\\flutter
```

---

## ۳) ساخت هسته‌های نیتیو (سه‌تا، فقط یک‌بار)

اسکریپت آمادهٔ خود ریپو این کار را برای هر ABI انجام می‌دهد:

```bash
# از ریشهٔ ریپو — ABI مورد نیاز گوشی شما (سامیونگ/شیائومی مدرن = arm64-v8a):
bash scripts/build_native.sh \
  --abi arm64-v8a \
  --rust-target aarch64-linux-android \
  --goarch arm64 \
  --api 29 \
  --src-cache .native-cache \
  --out .native-out/arm64-v8a
```

**در ویندوز:** این اسکریپت Bash است؛ در **Git Bash** یا **WSL** اجرایش کنید
(خروجی را بعداً کپی می‌کنید، پس WSL هم مشکلی ندارد).

ساخت اول بار **بسیار طولانی** است (کامپایل کامل quiche/boring-sys/arti: حدود
۲۰ تا ۴۵ دقیقه بسته به سیستم). بارهای بعدی کش می‌شوند.

اگر می‌خواهید APK ریلیس **یونیورسال** بسازید (مثل CI)، همین دستور را برای
`armeabi-v7a` (با `--rust-target armv7-linux-androideabi --goarch arm --goarm 7`)
و `x86_64` هم اجرا کنید. برای نصب روی گوشی خودتان، فقط `arm64-v8a` کافی است.

خروجی مورد نیاز در `.native-out/arm64-v8a/`:

```
aether/libaether.so              ← هستهٔ Aether (Rust، in-process)
aether/pt/lyrebird               ← پلاگابل ترنسپورت تور (Go)
aether/pt/psiphon-tunnel-core    ← باینری سایفون (Go)
zeptun/libzeptun-jni.so          ← موتور TUN (Zig)
```

### استیج کردن در jniLibs (نام‌ها عمداً عوض می‌شوند)

دقیقاً همان کاری که CI می‌کند (این نام‌ها را کد انتظار دارد — `libpsiphon.so`
و `liblyrebird.so` به‌صورت `lib*.so` نام‌گذاری شده‌اند تا اندروید آن‌ها را
استخراج کند):

```bash
JL=android/app/src/main/jniLibs
rm -rf "$JL"
mkdir -p "$JL/arm64-v8a"
cp .native-out/arm64-v8a/aether/libaether.so             "$JL/arm64-v8a/libaether.so"
cp .native-out/arm64-v8a/aether/pt/lyrebird              "$JL/arm64-v8a/liblyrebird.so"
cp .native-out/arm64-v8a/aether/pt/psiphon-tunnel-core   "$JL/arm64-v8a/libpsiphon.so"
cp .native-out/arm64-v8a/zeptun/libzeptun-jni.so         "$JL/arm64-v8a/libzeptun-jni.so"
```

> ⚠️ پوشهٔ `android/app/src/main/jniLibs` در `.gitignore` است — کامیت نمی‌شود،
> هر بار بیلد تازه باید موجود باشد.

---

## ۴) بیلد APK

### گزینهٔ A — ترمینال (معادل کامل CI)

```bash
# دیباگ (برای تست روی گوشی — فقط arm64 مثل قانون CI):
flutter build apk --debug --target-platform android-arm64
# خروجی: build/app/outputs/flutter-apk/app-debug.apk

# یا ریلیس (debug-signed، قابل نصب برای تست):
flutter build apk --release
# خروجی: build/app/outputs/flutter-apk/app-release.apk
```

### گزینهٔ B — داخل خود Android Studio

1. پوشهٔ `android/` پروژه را با **File → Open** باز کنید (نه ریشهٔ Flutter).
2. صبر کنید Gradle Sync تمام شود (اولین بار Gradle 9.8.2 را دانلود می‌کند).
3. **Build → Build Bundle(s)/APK(s) → Build APK(s)**.
4. خروجی: `android/app/build/outputs/apk/debug/app-debug.apk`.

> چون `jniLibs` از مرحلهٔ ۳ پر شده، Gradle خودش آن‌ها را داخل APK می‌گذارد.

### گزینهٔ C — مستقیم روی گوشی (سریع‌ترین برای تست)

گوشی را با USB و **Developer Options → USB Debugging** وصل کنید:

```bash
flutter devices          # باید گوشی را نشان دهد
flutter run --debug      # بیلد + نصب + هات‌ریلود
```

---

## ۵) عیب‌یابی رایج

| مشکل | راه‌حل |
|---|---|
| `NDK not found` / نسخهٔ اشتباه | در `local.properties` خط `ndk.dir` **اضافه نکنید**؛ فقط SDK Manager همان r26d را نصب کند. AGP نسخهٔ NDK را از `flutter.ndkVersion` می‌گیرد. |
| `boring-sys` build error | کش cargo را پاک کنید: `cargo clean` در `native/aether` و دوباره. مطمئن شوید NDK دقیقاً r26d است. |
| `libaether.so missing` در اجرای اپ | مرحلهٔ ۳ انجام نشده یا در ABI اشتباه ساخته شده — پوشهٔ `jniLibs/arm64-v8a` را چک کنید (هر ۴ فایل باید باشند). |
| خطای zig `version mismatch` | فقط Zig 0.16.0 کار می‌کند (پین zeptun). |
| `psiphon would not start` در لاگ هسته‌ها | `libpsiphon.so` در APK نیست یا exec bit ندارد — `useLegacyPackaging=true` در build.gradle خودش هنگام بیلد رعایت می‌شود؛ فایل را دوباره از مرحلهٔ ۳ کپی کنید. |
| Gradle Sync طولانی/خطای دانلود | پروکسی/فیلترشکن روشن باشد؛ یا `--offline` نکنید (اولین sync نیاز به اینترنت دارد). |
| تست‌ها/آنالایزر قبل از کامیت | `flutter analyze` (باید 0 issue) و `flutter test` (باید همه سبز). |

---

## ۶) چک‌لیست قبل از تست روی گوشی

- [ ] `flutter analyze` → **No issues found**
- [ ] `flutter test` → **All tests passed**
- [ ] هر ۴ فایل `jniLibs/arm64-v8a/*.so` موجودند
- [ ] بعد از نصب، در اپ: **تنظیمات → لاگ هسته‌ها** — باید خطوط `Aether v2.4.0`
      و `[*] starting psiphon from ...` را ببینید (اثبات اینکه هسته‌ها واقعاً بوت شدند)
- [ ] سناریوی تست این دور: اتصال → قطع → **اتصال دوباره با همان پروتکل** (باید وصل
      شود — باگ engineClosed رفع شده) + لاگ هسته‌ها را بعد از هر خطا کپی کنید.

---

### نکتهٔ v4.22 (صفحه‌های تنظیمات جزیی)

این دور فقط **دارت و asset** بود — هیچ گام بیلدی جدیدی ندارد؛ همان
مراحل ۱ تا ۵ بالا. تنها تفاوت‌ها:

- `version` پاب‌اسپک به `4.22.0+1` رفت (پیش‌فرض؛ تغییری در فرایند نمی‌دهد).
- آیکون‌های جدید فقط به لیست `flutter.assets` اضافه شدند — `flutter pub get`
  و بیلد همان‌طور قبلی آن‌ها را داخل APK می‌گذارد.
- **چک اضافه برای تست این دور:** در اپ، تنظیمات → تنظیمات اتصال →
  «تنظیمات هستهٔ Aether»: یکی از پروفایل‌های فرگمنت (متعادل/تهاجمی) را
  انتخاب و وصل شوید؛ بعد در **تنظیمات → لاگ هسته‌ها** دنبال خط
  `fragment` بگردید (اندازه/تأخیر باید همان مقدار انتخابی باشد). سپس
  حالت حرفه‌ای را روشن کنید و برای شبکهٔ سخت‌گیر، Noize را روی GFW
  بگذارید و نتیجه را گزارش کنید.

---

### نکتهٔ v4.23 (ویزارد اولین اجرا — «صفحه شروع»)

این دور هم فقط **دارت و asset** بود — همان مراحل ۱ تا ۵. تفاوت‌ها:

- `version` پاب‌اسپک به `4.23.0+1` رفت.
- ۴ آیکون SVG جدید (تیک، ضربدر، دو سپر) فقط به `flutter.assets` اضافه
  شدند؛ پرچم‌ها همان PNGهای موجود بودند.
- **ویزارد فقط روی نصب تازه اجرا می‌شود** — برای تست، یا اپ را
  حذف و دوباره نصب کنید یا «Clear data» بزنید (دیتای تنظیمات هم پاک
  می‌شود؛ برای حفظ تنظیمات، اول بکاپ بگیرید).
- **چک اضافه برای تست این دور:** بعد از نصب تازه باید ویزارد ۴ مرحله‌ای
  بیاید (زبان → مسیریابی → ضاهر → حالت/پروتکل/سرعت اسکن) با پیش‌فرض‌های
  قاب‌ها: فارسی، ایران، نمای ۱، تونل، اتوماتیک، عریض‌ترین قرص سرعت.
  دکمهٔ برگشت سیستم در مراحل ۲ به بعد باید یک مرحله عقب برود.
  «برو بریم!» → مودال تار «در حال پیدا کردن بهترین راه» (~۳ ثانیه) →
  صفحهٔ اصلی. بستن و باز کردن دوبارهٔ اپ باید **مستقیم** به صفحهٔ اصلی
  برود (ویزارد دوباره نیاید). هر انتخاب ویزارد باید همان لحظه اعمال شود
  (مثلاً زبان صفحه با لمس پرچم عوض شود).

---

## ۷) مرجع پین‌ها (یک‌جا)

| ابزار | نسخه |
|---|---|
| Flutter | 3.47.9 |
| JDK | 17 (Temurin 17.0.21+9) |
| Gradle wrapper | 9.8.2 |
| AGP | 9.4.0 |
| Build-Tools | 36.0.0 |
| NDK | r26d (26.3.11579264) |
| Rust | 1.99.1 |
| cargo-ndk | 4.1.2 |
| Go | 1.26.3 |
| Zig | 0.16.0 |
| API level نیتیو | 29 |
| minSdk / targetSdk اپ | 24 (کاندید) / 36 |
