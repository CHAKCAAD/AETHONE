# AETHONE Motion Playground

آزمایشگاه مستقل انیمیشن برای توسعه‌دهندگان AETHONE. این ابزار از همان Flutter SDK،
assetها، فونت‌ها و Widgetهای موجود در مخزن استفاده می‌کند، اما وارد مسیر اجرای
اپلیکیشن اصلی نمی‌شود.

## اجرا

از ریشه مخزن اجرا کن:

    flutter pub get
    flutter run -t tool/motion_playground/main.dart -d web-server --web-hostname 127.0.0.1 --web-port 7357

سپس در Firefox یا مرورگر دلخواه باز کن:

    http://127.0.0.1:7357

برای اجرای دسکتاپ لینوکس (در صورت آماده بودن Linux desktop toolchain):

    flutter run -t tool/motion_playground/main.dart -d linux

## امکانات نسخه اول

- پیش‌نمایش مستقیم Widget واقعی ConnectButtonGlow و ConnectHalo.
- آزمایش وضعیت‌های هشت‌گانه VpnState بدون اتصال به Engine یا VPN واقعی.
- انتخاب پنج شخصیت حرکتی رسمی پروژه: SILK، TIDE، SPRING، BLINK و OFF.
- مشاهده پارامترهای مهم MotionRecipe از جمله Connect March، Reconnect Seek،
  Press Spring، Section Resize و Dial.
- پیش‌نمایش افکت‌های عمومی Fade، Scale، Slide، Rotate، Blur و Fade + Scale.
- تنظیم Duration، Curve و شدت افکت.
- تولید و کپی کد Dart برای کامپوننت انتخاب‌شده.

## استفاده از Widget خودت

در حالت «Widget اختصاصی»، عبارت سازنده Widget خودت را در فیلد
Widget expression برای کد خروجی وارد کن؛ مثلاً:

    const YourCard()

این عبارت در خروجی Dart قرار می‌گیرد. پیش‌نمایش زنده نسخه اول از کارت نمونه
استفاده می‌کند؛ Flutter امکان اجرای امن و دلخواه کد Dart واردشده در زمان اجرا
را فراهم نمی‌کند. برای دیدن کامپوننت واقعی خودت، در مرحله بعد می‌توان یک
Preview Adapter کوچک در همین ابزار تعریف کرد که Widget تو را import و نمایش دهد.

## محدوده ایمنی

- این ابزار فقط ورودی جایگزین main.dart دارد.
- lib/main.dart، تنظیمات اپلیکیشن، ConnectionStore، فایل‌های Engine و
  تنظیمات ذخیره‌شده را تغییر نمی‌دهد.
- دکمه اتصال فقط وضعیت نمایشی را جلو می‌برد؛ هیچ تونل، پروکسی یا درخواست شبکه‌ای
  راه‌اندازی نمی‌شود.
- هیچ Dependency جدیدی به pubspec.yaml اضافه نشده است.
- اجرای flutter analyze و تست‌ها باید پس از دریافت شاخه روی محیط محلی انجام شود.
