# FIREFOX_VPN_SERVER_DISCOVERY

> مستند فنی فاز صفر — سازوکار دریافت، پردازش، ذخیره‌سازی، انتخاب و اعتبارسنجی موقعیت‌های سرویس Firefox VPN
>
> این فایل برای قرارگرفتن در مسیر `docs/FIREFOX_VPN_SERVER_DISCOVERY.md` مخزن AETHONE تهیه شده است. طبق محدودیت فاز صفر، هنوز در مخزن قرار نگرفته و صرفاً به‌عنوان خروجی مستند تحویل شده است.
>
> تاریخ تهیه: 2026-11-08 | همه‌ی ادعاها بر پایه‌ی خواندن کد هسته `UjuiUjuMandan/firefox-vpn-client` در پین `55ad91a` و تست زنده‌ی همان روز است؛ نه فرض و نه گزارش‌های قبلی.

---

## ۱. منبع داده: RemoteSettings موزیلا

فهرست موقعیت‌ها از سرویس عمومی RemoteSettings موزیلا دریافت می‌شود؛ نه از هیچ فایل استاتیک داخل پروژه:

```go
// serverlist.go L11
const remoteSettingsURL = "https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/vpn-serverlist/records"
```

مشخصات درخواست (کد `fetchServerList` در `serverlist.go` L51-91):

| ویژگی | مقدار | شاهد کد |
|---|---|---|
| متد | `GET` بدون احراز هویت | `serverlist.go` L52 |
| User-Agent | `MozillaVPN/2.35.0 (sys:linux; iap:true)` | `http_headers.go` L5, L13 |
| Accept | `application/json` | `http_headers.go` L14 |
| مسیر انتقال | همان کلاینت کنترل‌پلین با uTLS (ClientHello فایرفاکس) و HTTP/2 | `http_client.go` L42-92, L97 |

نکته مهم: این endpoint عمومی است و برای دریافت فهرست، حساب کاربری لازم نیست. فهرست با دسترسی بدون لاگین دریافت و تست شده است (بخش ۳).

## ۲. ساختار پاسخ

پاسخ یک پوشه (envelope) با کلید `data` است که هر عضو آن یک «کشور» است:

```json
{
  "data": [
    {
      "code": "IT",
      "name": "Italy",
      "cities": [
        {
          "code": "MXP",
          "name": "Italy",
          "servers": [
            { "port": 2499, "hostname": "mxp69.m1.fastly-masque.net", "quarantined": true }
          ]
        }
      ],
      "locked": true,
      "schema": 1793145609802,
      "id": "81fb3375-654a-4e75-8f7a-d292f5d022e3",
      "last_modified": 1793679729667
    }
  ]
}
```

ساختار داده‌ای هسته (`serverlist.go` L13-49):

- `Country { Name, Code, Cities[] }` — کشور با کد دوحرفی ISO و نام.
- `City { Name, Code, Servers[] }` — شهر با کد (در داده‌های فعلی عملاً کد فرودگاهی IATA، مثل `LFPB` پاریس یا `RJTF` توکیو).
- `Server { Hostname, Port, Quarantined, Protocols[] }` — سرور با hostname روی دامنه `*.m1.fastly-masque.net` و پورت.
- `Protocol { Name, Host, Port, Scheme, TemplateString }` — در داده‌های زنده‌ی فعلی این آرایه خالی است؛ هسته در این حالت مسیر پیش‌فرض «CONNECT روی https به همان hostname:port» را به‌کار می‌برد (`serverlist.go` L119-121 و `cmd/proxy-demo/main.go` L1351-1359).

پارس کردن در هسته سخت‌گیر است: رکوردی که `code` خالی یا `cities` خالی داشته باشد نادیده گرفته می‌شود (`serverlist.go` L85-87). رکورد خراب باعث شکست کل پارس نمی‌شود؛ فقط skip می‌شود.

## ۳. فهرست زنده (تست 2026-11-08)

دریافت زنده با همان هدرهای هسته انجام شد — ۳۵ رکورد در ۲۹ میلی‌ثانیه. ترکیب دقیق:

- **۳۳ کشور واقعی** (کد ISO دوحرفی)
- **۱ رکورد شبه‌کشور `REC`** با نام «Recomended Location» و hostname `p.m1.fastly-masque.net` (anycast «پیشنهادی»)
- **۱ رکورد شبه‌کشور «CatchAll Anycast»** با کد `US`/شهر `Q30` و همان hostname `p.m1.fastly-masque.net`، همراه با `filter_expression` مخصوص کلاینت‌های قدیمی‌تر از Firefox 151

تمام سرورها روی پورت **2499** هستند. در لحظه‌ی تست، سرور ایتالیا (`mxp69`) **quarantined** بود.

| کد | کشور | کد شهر | hostname |
|---|---|---|---|
| AR | Argentina | EZE | eze223.m1.fastly-masque.net |
| AT | Austria | VIE | vie63.m1.fastly-masque.net |
| AU | Australia | YSBK | ysbk106.m1.fastly-masque.net |
| BE | Belgium | BRU | bru148.m1.fastly-masque.net |
| BG | Bulgaria | SOF | sof151.m1.fastly-masque.net |
| BR | Brazil | SBSP | sbsp209.m1.fastly-masque.net |
| CA | Canada | CA | ca.m1.fastly-masque.net |
| CL | Chile | SCL | scl222.m1.fastly-masque.net |
| CO | Colombia | SKBO | skbo234.m1.fastly-masque.net |
| DE | Germany | MUC | muc139.m1.fastly-masque.net |
| DK | Denmark | CPH | cph232.m1.fastly-masque.net |
| ES | Spain | LETO | leto235.m1.fastly-masque.net |
| FI | Finland | HEL | hel141.m1.fastly-masque.net |
| FR | France | LFPB | lfpb115.m1.fastly-masque.net |
| GB | United Kingdom | EGLC | eglc860.m1.fastly-masque.net |
| GH | Ghana | ACC | acc96.m1.fastly-masque.net |
| IE | Ireland | DUB | dub43.m1.fastly-masque.net |
| IT | Italy | MXP | mxp69.m1.fastly-masque.net (quarantined) |
| JP | Japan | RJTF | rjtf770.m1.fastly-masque.net |
| KR | Korea | ICN | icn145.m1.fastly-masque.net |
| MY | Malaysia | KUL | kul98.m1.fastly-masque.net |
| MX | Mexico | MMQT | mmqt107.m1.fastly-masque.net |
| NL | Netherlands | EHRD | ehrd229.m1.fastly-masque.net |
| NO | Norway | OSL | osl65.m1.fastly-masque.net |
| NZ | New Zealand | AKL | akl103.m1.fastly-masque.net |
| PE | Peru | SPJC | spjc128.m1.fastly-masque.net |
| PH | Philippines | MNL | mnl215.m1.fastly-masque.net |
| PT | Portugal | LIS | lis149.m1.fastly-masque.net |
| SE | Sweden | ESSB | essb127.m1.fastly-masque.net |
| SG | Singapore | WSAT | wsat188.m1.fastly-masque.net |
| TH | Thailand | BKK | bkk228.m1.fastly-masque.net |
| US | United States | US | us.m1.fastly-masque.net |
| ZA | South Africa | FAOR | faor73.m1.fastly-masque.net |
| REC | Recomended Location | REC | p.m1.fastly-masque.net |
| US | CatchAll Anycast | Q30 | p.m1.fastly-masque.net |

**نتیجه مهم برای UI:** فهرست ۲۶۶ پرچم موجود در AETHONE فقط دارایی گرافیکی است. فهرست قابل انتخاب Firefox VPN باید از همین سرویس زنده ساخته شود: ۳۳ کشور واقعی؛ رکورد REC قابل نگهداری به‌عنوان گزینه «خودکار/پیشنهادی» (الگوی موجود `autoWheelCode` در `transport_modes.dart`)، و «CatchAll Anycast» باید حذف شود (الگوی مرجع MIT: `FoxyVPN/ServerListClient.kt` — `EXCLUDED_COUNTRY_NAMES = setOf("CatchAll Anycast")`).

## ۴. گردش انتخاب سرور در هسته Go

زنجیره‌ی کامل از فهرست تا hostname (کد `cmd/proxy-demo/main.go`):

1. **ساخت کاندیدها** — `connectProxyCandidates` (L1343-1376): پیمایش کشور→شهر→سرور؛ سرورهای quarantined حذف می‌شوند (L1348-1350)؛ هر سرور سالم یک `proxyCandidate { Addr: "host:port", CountryName, CountryCode, CityName, CityCode }` می‌شود.
2. **اولویت ورودی صریح** — `resolveProxyWithStateAndCountry` (L1100-1138): اگر `-proxy HOST:PORT` داده شده باشد، همان (با تطبیق متادیتا از فهرست) استفاده می‌شود؛ `-proxy` و `-country` متقابلاً انحصاری‌اند (L221-224).
3. **حالت ماندگار** — اگر `-proxy-state-file` تنظیم شده و فایل انتخاب قبلی موجود باشد و با کشورِ درخواستی سازگار باشد، همان hostname قبلی بازاستفاده می‌شود (L1109-1131). اگر hostname ذخیره‌شده دیگر در فهرست نباشد، با هشدار جایگزین می‌شود (L1120).
4. **انتخاب با فیلتر کشور** — `selectProxyCandidate` (L1140-1171): فقط کاندیدهای منطبق با `-country` (کد یا نام، case-insensitive — L1173-1180).
5. **سیاست ضدتصادفی** — بدون فیلتر، اگر بیش از یک کشور موجود باشد برنامه با خطای «multiple VPN countries are available» متوقف می‌شود (L1156-1169)؛ **انتخاب تصادفی کشور در کد وجود ندارد**. اگر فقط یک موقعیت موجود باشد، همان انتخاب می‌شود.
6. **نرمال‌سازی آدرس** — `normalizeProxyURL` (L1378-1394): تبدیل `host:port` به `https://host:port`.
7. **پایداری انتخاب** — پس از برقراری موفق upstream، انتخاب در `proxy-state-file` ذخیره می‌شود (main L319-323)؛ سه شکست پیاپی راه‌اندازی، انتخاب را پاک می‌کند تا انتخاب جدید انجام شود (`recordProxySelectionFailure` L1239-1265).

## ۵. کش و رفتار در قطع دسترسی

- **هسته Go هیچ کشی برای فهرست سرورها ندارد.** هر بار که فهرست لازم باشد (ورود بدون `-proxy`، یا `-print-info`)، `fetchServerList` صدا زده می‌شود.
- خطای دریافت فهرست فقط یک `logWarn` است و برنامه با فهرست خالی ادامه می‌دهد (main L630-637).
- در نبود فهرست: انتخاب از `proxy-state-file` ذخیره‌شده ممکن است (L1112-1119)، ولی انتخاب جدید با خطای «no CONNECT proxies available» شکست می‌خورد (L1143).
- **الگوی مرجع FoxyVPN** (`ServerListClient.kt`): کش کامل پاسخ خام در `filesDir/vpn_serverlist_cache.json`، اعتبار ۶ ساعت، جایگزینی اتمی (tmp+rename)، و در صورت شکش fetch، استفاده از آخرین کش معتبر. حذف صریح «CatchAll Anycast» و نرمال‌سازی نام REC به «Recommended» هم همان‌جاست.
- **توصیه برای AETHONE:** پیاده‌سازی الگوی موجود `EgressLocations` در AETHONE (fetch در شروع اپ + TTL + کش دیسک + seed آفلاین ثبت‌شده از داده‌ی همین سند) — سازگار با سیاست «لوکیشن‌های واقعی، نه فیک» که از قبل در `transport_modes.dart` و `egress_locations.dart` مستند شده است. پیشنهاد TTL: ۶ ساعت (مطابق مرجع MIT).

## ۶. چهار مفهوم متمایز «موقعیت»

این چهار چیز با هم یکسان نیستند و UI نباید آن‌ها را خلط کند (مستند `OPERATOR.md` بخش «Fastly POP،配置位置与实际出口» و کد `logVerifiedExit` main L398-416):

1. **کشور تنظیم‌شده** — همان `country.Code` رکورد انتخابی از server list.
2. **hostname انتخاب‌شده** — مثلاً `lfpb115.m1.fastly-masque.net` (سایت فیزیکی POP پاریس، کد IATA + شماره سایت).
3. **POP ورودی Fastly** — مسیر شبکه‌ای که ترافیک وارد Fastly می‌کند؛ معمولاً نزدیک‌ترین POP به کاربر، مستقل از کشور انتخابی.
4. **IP خروجی واقعی** — آدرسی که مقصد نهایی می‌بیند؛ فقط با probe واقعی از داخل تونل قابل اثبات است (`verifyExit` main L426-485: درخواست `https://www.cloudflare.com/cdn-cgi/trace` از مسیر همان تونل).

هسته به‌صورت صریح هشدار می‌دهد وقتی کشور IP خروجی با کشور تنظیم‌شده فرق کند (L410-415): `verified exit country differs from configured upstream location`. `PROXY_STATE_FILE` فقط hostname را ثابت نگه می‌دارد و «تضمین» نمی‌کند POP، مسیر داخلی یا IP خروجی ثابت بماند.

نکته جدا: فهرست ۲۹ کشورِ «در دسترس بودن سرویس برای حساب‌ها» (اعلام رسمی موزیلا برای اندروید، به‌روزرسانی 2026-07-28) با فهرست ۳۳ کشورِ سرورها یکی نیست — مثلاً لهستان و سوئیس در فهرست دسترسی رسمی‌اند ولی سروری در server list ندارند. دسترسی حساب موضوع تست حساب واقعی است، نه این مستند.

## ۷. اعتبارسنجی موقعیت پس از اتصال (معیار درست‌بودن)

- پیش از اعلام موفقیت، `verifyExit` یک درخواست HTTPS واقعی از داخل تونل به `/cdn-cgi/trace` می‌فرستد و `ip` و `loc` (کشور) پاسخ را پارس می‌کند (`parseExitProbeResponse` L512-540؛ پذیرش هر دو فرمت key=value و JSON).
- این probe به‌صورت پیش‌فرض **غیرمهلک** است (شکستش سرویس را نمی‌کشد — OPERATOR.md)، پس برای AETHONE باید به‌عنوان **دروازه‌ی اعلام Connected** استفاده شود — دقیقاً همان کاری که `TunnelProbe` فعلی AETHONE برای پورت‌های 1819/1820/1821 می‌کند و برای 1822 هم انجام می‌شود.
- نمایش کشور خروجی باید از نتیجه‌ی همین probe بیاید، نه از انتخاب کاربر؛ نمایش ping واقعی هم از RTT همین درخواست. نمایش ping یا کشور ساختگی ممنوع.

## ۸. نحوه‌ی تست مجدد (تکرارپذیری)

ابزارهای تست این سند (تحویل‌شده در کنار گزارش فاز صفر، آماده انتقال به `scripts/` مخزن پس از تأیید):

- دریافت زنده‌ی فهرست با هدرهای عین هسته: برنامه‌ی کوچک Go با فراخوانی `vpnclient.FetchServerList` (خروجی‌های خام: `remotesettings_raw.json` و پارس‌شده: `serverlist_live.json`).
- بررسی دسترسی دیتاپلین: probeهای TCP+TLS(ALPN h2) و QUIC(ALPN h3) روی پورت 2499 هاست‌های انتخابی — نتیجه 2026-11-08: ۷/۷ هاست h2 موفق (TLS 1.3، ۱۵۳-۴۷۷ms)، ۳/۳ هاست h3 موفق (۶۳-۲۱۴ms).

فهرست سرورها پویاست (رکوردها `last_modified` دارند)؛ هنگام پیاده‌سازی فاز یک، مقدار seed آفلاین باید از همان روز گرفته و تاریخ ثبت شود.

## ۹. جمع‌بندی تصمیم‌های مستندشده

1. هیچ فهرست کشور ثابتی در AETHONE ساخته نمی‌شود؛ منبع فقط RemoteSettings است.
2. REC به‌عنوان گزینه «خودکار» (در صورت تأیید مالک) و «CatchAll Anycast» حذف؛ سرورهای quarantined از انتخاب کنار گذاشته می‌شوند (هسته همین‌طور عمل می‌کند).
3. کش با TTL (پیشنهاد: ۶ ساعت، مطابق مرجع MIT) + seed آفلاین با تاریخ ثبت.
4. کشورِ خروجیِ نمایش‌داده‌شده فقط از probe واقعی تونل می‌آید؛ تفاوت با کشور انتخابی به‌صورت صریح به کاربر اعلام می‌شود.
5. انتخاب کاربر روی کد کشور ISO از فهرست زنده اعمال می‌شود؛ «انتخاب تصادفی» وجود ندارد و اگر لیست چندکشوری باشد و کاربر انتخاب نکرده باشد، اتصال شروع نمی‌شود.
