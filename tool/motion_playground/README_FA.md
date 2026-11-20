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

## امکانات Motion Studio 2.0

نسخه آنلاین و عمومی:
  
    https://chakcaad.github.io/AETHONE/

استفاده از نسخه آنلاین به نصب Flutter، Dart یا Android Studio روی سیستم کاربر نیاز ندارد.

- پیش‌نمایش جداگانه‌ی ترکیب کامل اتصال، ConnectButtonGlow، ConnectShake و ConnectHalo؛
  همه با Widgetهای واقعی پروژه.
- انتخاب وضعیت‌های هشت‌گانه‌ی VpnState و پنج شخصیت حرکتی SILK، TIDE، SPRING، BLINK و OFF.
- Timeline با Playhead، پخش، توقف، Replay، Scrub و تنظیم سرعت و Delay.
- افزودن، جابه‌جایی و حذف Keyframe برای Opacity، Scale، Position X/Y، Rotation و Blur.
- ویرایش منحنی‌های Linear، Ease، Back، Quint، Elastic و Bounce.
- منحنی Cubic Bezier سفارشی با کنترل نقاط P1/P2 و پیش‌نمایش گراف.
- Spring Simulation با تنظیم Mass، Stiffness و Damping.
- Loop، Ping-pong / Reverse و آزمون Reduce Motion.
- تغییر Light/Dark پس‌زمینه پیش‌نمایش.
- ذخیره Presetها در فضای ذخیره‌سازی مرورگر، بارگذاری و حذف آن‌ها.
- خروجی و کپی Dart و JSON برای تنظیمات طراحی.

## محدوده نسخه 2.0

Timeline و Keyframeها یک لایه‌ی حرکتی قابل‌تنظیم روی پیش‌نمایش Widget واقعی اعمال می‌کنند.
رفتار داخلی Halo، Shake و PressSpring همان رفتار اصلی AETHONE و وابسته به MotionStyle و
VpnState باقی می‌ماند؛ این ابزار موتور VPN یا اتصال واقعی را اجرا نمی‌کند.

## استفاده از Widget خودت

در حالت «Widget اختصاصی» دو مرحله انجام بده:

1. فایل tool/motion_playground/custom_widget_slot.dart را باز کن و import و
   خروجی تابع buildCustomWidgetPreview را به Widget واقعی خودت تغییر بده. برای
   نمونه، import کلاس خودت را اضافه کن و تابع را به این شکل برگردان:

       Widget buildCustomWidgetPreview() => const YourCard();

2. عبارت سازنده را در فیلد Widget expression برای کد خروجی نیز وارد کن:

       const YourCard()

اکنون Playground همان Widget واقعی را در پیش‌نمایش نمایش می‌دهد و انیمیشن
انتخاب‌شده را روی آن اعمال می‌کند. کد خروجی Dart نیز از همان عبارت استفاده
می‌کند؛ import لازم برای Widget خودت را در فایل مقصد نگه دار یا اضافه کن.

Flutter امکان کامپایل و اجرای امن کد Dart دلخواه را در زمان اجرای Playground
فراهم نمی‌کند؛ به همین دلیل اتصال Widget با یک Preview Adapter صریح و قابل
بازبینی انجام می‌شود، نه اجرای کد متنی دلخواه.

## محدوده ایمنی

- این ابزار فقط ورودی جایگزین main.dart دارد.
- lib/main.dart، تنظیمات اپلیکیشن، ConnectionStore، فایل‌های Engine و
  تنظیمات ذخیره‌شده را تغییر نمی‌دهد.
- دکمه اتصال فقط وضعیت نمایشی را جلو می‌برد؛ هیچ تونل، پروکسی یا درخواست شبکه‌ای
  راه‌اندازی نمی‌شود.
- هیچ Dependency جدیدی به pubspec.yaml اضافه نشده است.
- اجرای flutter analyze و تست‌ها باید پس از دریافت شاخه روی محیط محلی انجام شود.
