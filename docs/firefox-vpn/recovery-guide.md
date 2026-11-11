# راهنمای بازیابی و ساخت APK آزمایشی DA — نشست بعدی مالک

> این سند برای **مالک پروژه** نوشته شده است: مرحلهٔ Build و تست روی گوشی
> توسط شما انجام می‌شود. در نشست اصلاحی ایجنت، **هیچ Build، APK یا تست
> سنگینی اجرا نشده است** (`NOT RUN — OWNER REQUEST`) — فقط سورس،
> مستندات و Commit/Push خصوصی.
>
> مخزن خصوصی: `https://github.com/CHAKCAAD/aethonepriv` — شاخه:
> `phase2/firefox-vpn-ui` (HEAD: `9b655e3` + کامیت مستندات)

---

## ۰) خلاصهٔ وضعیت فعلی

| بخش | وضعیت |
|---|---|
| سورس موتور `phase1/fxv` | در مخزن خصوصی ✓ (کامیت `6447932`) |
| اصلاح A1 (CGO + Bionic برای هر ۳ ABI) | در `build_engine.sh` ✓ (کامیت `193f81e`) |
| وصله فاز B (طبقه‌بندی خطا + گارد OAuth) | در سورس واقعی موتور ✓ |
| لوگوی رسمی Firefox + انتقال Speed Scan | ✓ (کامیت `9b655e3`) |
| Build موتور ۲۰۲۶-۱۱-۰۹ (قبل از دستور اصلاحی) | انجام و هش ثبت شده (`phase1/build/SHA256SUMS.txt`) |
| Build مجدد توسط ایجنت در نشست اصلاحی | اجرا نشد — طبق دستور مالک |
| APK آزمایشی DA | **ساخته نشد — مرحلهٔ شماست** |
| تست روی گوشی | اجرا نشده — مرحلهٔ شماست |

## ۱) پیش‌نیازها

نصب و پین‌ها در `docs/LOCAL_BUILD_FA.md` (کامل) و
`phase1/docs/BUILD.md`. خلاصهٔ پین‌های موتور Firefox:

| ابزار | نسخه |
|---|---|
| Go | 1.25.0 |
| Android NDK | 28.2.13676358 (r28c) |
| Flutter | 3.47.9 |
| JDK | 17 (تمپلیت CI: Temurin 17.0.21+9) |
| Gradle wrapper | 9.8.2 · AGP 9.4.0 · Build-Tools 36.0.0 |

## ۲) گرفتن سورس و موتور

```bash
git clone https://github.com/CHAKCAAD/aethonepriv.git aethone
cd aethone
git checkout phase2/firefox-vpn-ui
git log --oneline -5        # HEAD باید 9b655e3 یا جدیدتر باشد

flutter pub get

# دریافت upstream پین‌شده (هرگز Commit دیگری جایگزین نشود):
phase1/scripts/fetch_upstream.sh
# خروجی باید commit c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1 را تأیید کند

# ساخت موتور برای هر سه ABI + host:
phase1/scripts/build_engine.sh all
# خروجی: phase1/build/android/<abi>/libfirefoxvpn.so (+ host)
# هش‌ها باید با phase1/build/SHA256SUMS.txt مطابقت داشته باشند
```

> اگر Workspace ایجنت هنوز زنده باشد، باینری‌های از قبل ساخته‌شده در
> `phase1/build/` موجودند و می‌توانید از Build مجدد صرف‌نظر کنید —
> فقط هش‌ها را با `SHA256SUMS.txt` تطبیق دهید.

## ۳) هسته‌های نیتیو دیگر (چهار کتابخانه)

APK علاوه بر `libfirefoxvpn.so` به چهار هستهٔ نیتیو نیاز دارد:
`libaether.so`، `liblyrebird.so`، `libpsiphon.so`، `libzeptun-jni.so`.

**راه سریع (توصیه‌شده): استخراج از APKهای رسمی v1.0.0 (r93)** — چون
شاخهٔ phase2 سورس `native/` را تغییر نداده، باینری‌های r93 (commit
`5a6a0e6`، دقیقاً `origin/main` فعلی خصوصی) با این نسخه سازگارند:

```bash
# دانلود از Releases مخزن عمومی (فقط خواندن — هیچ تغییری در آن ایجاد نکنید):
#   aethone-arm64-v8a-r93.apk    SHA256: f383bb97a6ed1522e261c7b383037129935d7307ad7a6dd0ddb794e3d461a557
#   aethone-armeabi-v7a-r93.apk  SHA256: 26baa458b71f57d2dc9c67f7c6d574e49013698cba3cc777de1dc31fc0f3b78c
#   aethone-x86_64-r93.apk       SHA256: 5771c3acd988ca28c68fae5faf5b4e3b5574cb8b16805edc05df905aa132660c

for abi in arm64-v8a armeabi-v7a x86_64; do
  for so in libaether.so liblyrebird.so libpsiphon.so libzeptun-jni.so; do
    unzip -p "aethone-$abi-r93.apk" "lib/$abi/$so" \
      > "android/app/src/main/jniLibs/$abi/$so"
    chmod 755 "android/app/src/main/jniLibs/$abi/$so"
  done
  cp "phase1/build/android/$abi/libfirefoxvpn.so" \
     "android/app/src/main/jniLibs/$abi/libfirefoxvpn.so"
done
```

هش‌های SHA256 هسته‌های استخراج‌شده (ثبت نشست ۲۰۲۶-۱۱-۰۹، قابل
بازتولید با دستور بالا — منبع اصلی تأیید، هش خود APKهای r93 است):

```text
arm64-v8a (aethone-arm64-v8a-r93.apk):
  libaether.so      1350ac35b28f7d6e11dabc8c2986715890cef3f51c41f08f3256dccf97aa1b07
  liblyrebird.so    ed463246b954e2cbd2f4608bd20f1cc7b2f688b4963b838b025f24e4b09ade4a
  libpsiphon.so     87545330265d220e5fa708322a17672ecea96a40ddaeebeeb8a568fbb7565686
  libzeptun-jni.so  a8cd83a3ec40496bdab0ce3bc59fc65fbbd6306a666220d08009d9b7a5c65393
armeabi-v7a (aethone-armeabi-v7a-r93.apk):
  libaether.so      04b983a64f74983ee8f7b7325b22ae4d9bc9b5ed6428cbf5bdc3c9ab1ca0b15f
  liblyrebird.so    bb553df31609efd50e96527e8185d2691dd896811a101e560ed7a130a1305ec2
  libpsiphon.so     abd4fc5a6c516577b8f7f8b5e34091e62fe5ddd012fe77895895fc1b6ffa9e68
  libzeptun-jni.so  d6db4cdd2495472178457621f424030e359c28ff6919d3b3701be49e2f6a43bf
x86_64 (aethone-x86_64-r93.apk):
  libaether.so      02d7b1a16e368ef36d9f5b10fc55000dc56d47e9c8b2f878cdaa0315d62fd831
  liblyrebird.so    d53be3e8822c59459a9d5b153efa4e0f8e529dba2376b932167a098bd426504f
  libpsiphon.so     8cf19927904a9ac71ea7d83a46afc9275723a145e3eabe72637bbb0097d10600
  libzeptun-jni.so  d63bdfdf6f92ca351edfac5614d9bdc5467ec1cda6fc4e511340c62e479d74ee
```

**راه کامل:** ساخت نیتیو طبق `docs/LOCAL_BUILD_FA.md` (Rust 1.99.1 +
Zig 0.16.0 + Go 1.26.3 + cargo-ndk 4.1.2).

> توجه: `jniLibs/` در `.gitignore` است — باینری‌ها هرگز وارد Git
> نمی‌شوند (سیاست موجود؛ ورودشان به مخزن نیازمند تصمیم مالک است).

## ۴) بستهٔ DA (نصب کنار اپ اصلی — نه جای آن)

سه تغییر کوچک (پس‌زدن مالک در Workspace ایجنت روی شاخهٔ محلی
`device-acceptance/firefox-core-restored` آماده شده بود — شاخه Push
نشده و ممکن است از بین رفته باشد؛ دستی بازسازی کنید):

**`android/app/build.gradle.kts`:**
```kotlin
applicationId = "com.chakcaad.aethone.da"   // بستهٔ مستقل DA
versionName = "${flutter.versionName}-da"
```

**`android/app/src/main/AndroidManifest.xml`:**
```xml
android:label="AETHONE DA"
```

**`android/gradle.properties`** (فقط اگر میزبان Build ≤ ۴GB RAM دارد —
مقدار پیش‌فرض 8G در میزبان‌های کوچک باعث OOM-Kill شدن Daemon می‌شود):
```properties
org.gradle.jvmargs=-Xmx1536M -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError
kotlin.daemon.jvmargs=-Xmx1024M
org.gradle.workers.max=2
```

## ۵) ساخت APK

```bash
flutter build apk --release
# خروجی: build/app/outputs/flutter-apk/app-release.apk
# امضا: debug keystore (سیاست تست-نصب پروژه — نه Release عمومی)
# نام پیشنهادی نهایی: AETHONE-DA-Firefox-Core-Restored-debug.apk
```

سه ABI در یک APK (fat) بسته می‌شوند؛ `useLegacyPackaging` فعال است تا
باینری‌ها با مجوز اجرا استخراج شوند.

## ۶) چک‌لیست تأیید APK (قبل از نصب)

```bash
# ۱. اعتبار Archive:
unzip -t app-release.apk > /dev/null && echo OK

# ۲. شناسه بسته و لیبل (باید com.chakcaad.aethone.da / AETHONE DA باشد):
aapt dump badging app-release.apk | rg "package:|application-label:"

# ۳. هر سه ABI + هر پنج کتابخانه:
unzip -l app-release.apk | rg "lib/"

# ۴. تطبیق هش موتور داخل APK با Build (برای هر ABI):
unzip -p app-release.apk lib/arm64-v8a/libfirefoxvpn.so | sha256sum
# باید برابر a404bbbb67e58d153fe439fee3996ebb24458f0cd7263cc30ea6ce2bde980a2b باشد

# ۵. هش نهایی APK را ثبت کنید (APK قبلی را هرگز overwrite نکنید):
sha256sum app-release.apk
```

## ۷) تست DNS در هر معماری (روی گوشی)

نقش `--dns-probe` موتور، دامنه‌های Control Plane را resolve می‌کند و
نتیجهٔ واقعی را گزارش می‌کند (بدون هیچ دادهٔ حساب). برای هر ABI می‌توانید
باینری استخراج‌شده را روی دستگاه اجرا کنید یا جریان Login اپ را با
`da_diagnostic.log` (لایهٔ شاخهٔ `device-acceptance` قدیمی — اگر
ادغامش را بخواهید، تصمیم مالک است) بررسی کنید.

دامنه‌های مرجع:
```text
api.accounts.firefox.com
firefox.settings.services.mozilla.com
```

## ۸) موارد اجرانشده (صادقانه)

| مورد | وضعیت |
|---|---|
| `go test ./...` / `go vet ./...` در نشست اصلاحی | NOT RUN — OWNER REQUEST (رکورد سبز ۲۰۲۶-۱۱-۰۹: 85/85) |
| `flutter test` / `flutter analyze` در نشست اصلاحی | NOT RUN — OWNER REQUEST (رکورد ۲۰۲۶-۱۱-۰۹: 313 PASS / analyze clean) |
| Build مجدد موتور در نشست اصلاحی | NOT RUN — OWNER REQUEST |
| ساخت APK | NOT RUN — OWNER REQUEST |
| تست DNS روی دستگاه (هر ABI) | NOT RUN — فقط شواهد ELF/host ثبت شده |
| تست عبور ترافیک واقعی VPN | خارج از Scope (مالک درخواست نکرده) |
| تست تغییر IP عمومی | خارج از Scope |

**هیچ‌کدام از موارد بالا را PASS گزارش نکنید مگر خودتان اجرا کرده و
نتیجه را دیده باشید.**

## ۹) محدودیت‌ها و تصمیم‌های باز مالک

1. **مجوز upstream حل‌نشده** (`phase1/fxv/ORIGIN.md`): هیچ توزیع
   عمومی، Release یا Artifact حاوی موتور مجاز نیست تا زمان انتخاب
   یکی از گزینه‌ها (اجازهٔ کتبی نویسندهٔ upstream / جایگزین
   دارای مجوز / خصوصی ماندن دائمی).
2. **لایهٔ لاگ تشخیصی DA** (`da_log.dart` روی شاخهٔ قدیمی
   `device-acceptance` مبتنی بر `c148968`): ادغامش با زنجیرهٔ خطای
   بازنویسی‌شدهٔ فاز B یک تصمیم مالک است — hooks قدیمی با قرارداد
   جدید بازنویسی می‌خواهند.
3. **minSdk 24 همچنان CANDIDATE** (اثبات سمبل‌سطح و runtime لازم دارد).
4. امضای Release با debug keystore فقط برای تست-نصب است؛ keystore
   واقعی یک open item ثبت‌شدهٔ پروژه است.

## ۱۰) قواعد ثابت

- فقط مخزن خصوصی `CHAKCAAD/aethonepriv` — هیچ Push/PR/Release به
  مخزن عمومی `CHAKCAAD/AETHONE`.
- بدون Force Push، بدون بازنویسی تاریخچه.
- هیچ Token/Secret در argv، Environment، Log، سورس یا گزارش.
- باینری/آرتيفکت در Git فقط با تصمیم صریح مالک.
