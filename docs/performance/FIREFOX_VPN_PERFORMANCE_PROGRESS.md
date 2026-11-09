# FIREFOX VPN PERFORMANCE — PERMANENT PROGRESS FILE

> مرجع دائمی مأموریت بهینه‌سازی عملکرد Firefox VPN در AETHONE.
> هر جلسه جدید باید این فایل را بخواند و از همین وضعیت ادامه دهد — نه از حافظه مکالمه.
> هیچ Token/Session/Refresh Token یا لاگ طولانی در این فایل قرار نمی‌گیرد.

## وضعیت کلی

| فیلد | مقدار |
|---|---|
| تاریخ آخرین اجرا | 2026-11-09 |
| Repository | `CHAKCAAD/AETHONE` (تنها مخزن مجاز) |
| Branch کاری | `performance/firefox-vpn-optimization` |
| Commit پایه شاخه | `ff9bc38` (= tip شاخه `integration/firefox-vpn-debug`) |
| Commit آخرین مرحله تکمیل‌شده | (در انتهای همین فایل — بخش «گیت مرحله آخر») |
| مرحله تکمیل‌شده آخر | **Stage 0 — تثبیت نسخه و خط مبنا: PASS** |
| مرحله فعلی برای اجرای بعدی | **Stage 1 — بررسی Ping و صحت اندازه‌گیری** |
| مخزن خصوصی | کاملاً خارج از محدوده — ممنوع |

### جدول مراحل

| مرحله | وضعیت |
|---|---|
| 0 — تثبیت نسخه و خط مبنا | **PASS** (بدون تغییر کد؛ فقط این فایل) |
| 1 — بررسی Ping و صحت اندازه‌گیری | PENDING (بعدی) |
| 2 — مسیر انتقال داده، TUN و صف‌ها | PENDING |
| 3 — Transport و نسخه HTTP | PENDING |
| 4 — MTU | PENDING |
| 5 — IPv4/IPv6 و Endpoint | PENDING |
| 6 — CPU/حافظه/Go Child Process | PENDING |
| 7 — TLS Fragmentation | PENDING |
| 8 — مقایسه نهایی و Build | PENDING |

---

## نتیجه Stage 0 (اجرای 2026-11-09)

### ۱. تطبیق نسخه — PASS

- شاخه‌های مخزن: `ci-bootstrap/v4.4` @ `2ef884f6` (پیش‌فرض؛ فقط به‌روزرسانی README روی v1.0.0) و `integration/firefox-vpn-debug` @ `ff9bc38` (شامل کل بازیابی Firefox VPN + واریانت DA + workflow).
- رابطه تاریخچه: integration از `2ef884f6` منشعب می‌شود (merge-base = tip v4.4) و commitهای `f61d217..2c0835d` (بازیابی کامل fxv از کار قبلی) را روی خود دارد؛ نیازی به انتقال جدید نیست.
- Build موفق GitHub Actions: run #3 (id `42620926020`) از شاخه `integration/firefox-vpn-debug` @ `ff9bc38` در 2026-11-09 13:12 UTC — workflow `.github/workflows/android-debug.yml`، هر ۵ job موفق (3 native cores + Firefox engine + DA debug APK).
- مشخصات APK ساخته‌شده (از لاگ خود run):
  - package: `com.chakcaad.aethone.da` ، versionName `1.0.0-da` ، versionCode 1 (universal debug، zipalign+apksigner تأیید شده — debug-sign مخصوص تست)
  - فایل: `AETHONE-DA-Firefox-Debug.apk` ، 186,944,486 bytes ، SHA256 `66fb73a70f982ec7be93ba5f03692c700fcd070059fbc942aff114674f0861d0` ، artifact تا 2026-11-23.
- باینری Firefox داخل APK — تأیید byte-identical با باینری ساخته‌شده در CI (شرط sha256 در workflow پاس شد):
  - `arm64-v8a/libfirefoxvpn.so` → `19aea224c864e3de9bf57c7f6c6997783cc9d608591d7fd44b01c13675be3f22` (14,445,664 B)
  - `armeabi-v7a/libfirefoxvpn.so` → `e35683fc42ed7450b0ad30ed5aac5fdefe8eca970fadcd11e0c5e2a8aecb1c90` (14,264,000 B)
  - `x86_64/libfirefoxvpn.so` → `0bd5155b988aa621c8d91260d43003eb3294fe1638648ec6896299af4d8854d1` (15,403,296 B)
- **نتیجه تطبیق**: APK نصب‌شده روی گوشی مالک (که ورود Firefox در آن موفق است) فقط می‌تواند DA debug APK از run #3 @ `ff9bc38` باشد — چون APKهای r93/v1.0.0 (از `5a6a0e6`) قبل از بازیابی موتور ساخته شده‌اند و `libfirefoxvpn` ندارند. سورس تحت بررسی (`ff9bc38` = پایه شاخه performance) با همان Build مطابق است. (بر تأیید قطعی نصب از طرف مالک تأکید نشده — جزو موارد تأییدنشده.)

### ۲. تأیید اصلاح A1 (CGO در ARM64) — PRESERVED

- `phase1/scripts/build_engine.sh`:
  - هر سه ABI اندروید با `CGO_ENABLED=1` و کامپایلر صحیح NDK ساخته می‌شوند: `aarch64-linux-android34-clang` / `armv7a-linux-androideabi34-clang` (+`GOARM=7`) / `x86_64-linux-android34-clang`.
  - `CGO_ENABLED=0` صریح برای هدف اندروید **رد می‌شود** (خط ۱۹۱: "the A1 decree: every Android ABI builds with CGO + NDK clang").
  - فقط Build میزبان (linux/amd64) با CGO_ENABLED=0 است — صحیح.
- CI: job «Firefox engine (Go 1.25.0 — CGO + NDK r28c, all ABIs)» با `FXV_GO_VERSION: 1.25.0` و `FXV_NDK_PIN: 28.2.13676358` (r28c) موفق.
- ماژول `phase1/fxv` در سورس حاضر است: `cmd/libfirefoxvpn/` (main، login، discover، dnsprobe، resolver_cgo، resolver_nocgo) + `internal/{discovery, engine, fferr, redact, socks, upstream}`.
- pin بالادست تأیید شد (`phase1/fxv/ORIGIN.md`): `UjuiUjuMandan/firefox-vpn-client` @ `55ad91a2ccea1c93e69c82a08a7681e279884db5` — مطابق دستور مأموریت؛ بدون تغییر.

### ۳. پین‌های ابزار (از workflow اندروید)

- Flutter `3.47.9` ، JDK `17.0.21+9` ، Gradle `9.8.2` ، AGP `9.4.0` ، Build-Tools `36.0.0`
- موتور Firefox: Go `1.25.0` + NDK `28.2.13676358` (r28c) — CGO اجباری
- هسته‌های native دیگر (Aether v2.4.0 / Zeptun 1.1.3 / Psiphon fork): Go `1.26.3` ، Rust `1.99.1` ، Zig `0.16.0` ، NDK `r26d` ، API 29
- سیاست git: `jniLibs/` و باینری‌های `phase1/build` هرگز وارد Git نمی‌شوند (CI از سورس می‌سازد).

### ۴. معماری واقعی انتقال داده (استخراج‌شده از سورس — ساخت فرضی نیست)

```text
App (Flutter/Dart)
  └─ FirefoxVpnEngine (lib/connection/firefox/firefox_engine.dart)
       spawn: Process.start(libfirefoxvpn.so, argv=[]) — includeParentEnvironment=false،
       env صریح (پیش‌فرض خالی)؛ کل پیکربندی+توکن فقط در «یک خط JSON روی stdin»؛
       بستن stdin = درخواست shutdown؛ stdout = رویدادهای JSON (socksReady/failed/authRefreshed…)
Android VpnService (AethoneVpnService.kt)
  Builder: setMtu(1500) «هاردکد» ، آدرس 172.19.0.1/30 ، route 0.0.0.0/0
  (یا allow/disallow per-app) ، DNS سرور 172.19.0.2
  └─ TUN ParcelFileDescriptor (fd)
       └─ Zeptun.nativeStart(service, fd, toml) — libzeptun-jni (Zig، استک userspace،
            preset "mobile"، fake-IP DNS، handler socks5)
            └─ تمام جریان‌های TCP تونل → پروکسی SOCKS5 «127.0.0.1:1822»
                 (پورت ثابتِ engine فایرفاکس — lib/connection/transport_modes.dart)
                 └─ Go engine: internal/socks/server.go (شنونده SOCKS5)
                      └─ internal/upstream: controller.go (مدیریت session/pass/renew)
                         + h2.go + h3.go + tunnel.go (transportها) → سرورهای Firefox VPN
بازگشت: مسیر معکوس. سوکت‌های بالادست با VpnService.protect (کال‌بک zeptun) +
uid خود اپ از TUN مستثنا — جلوگیری از حلقه مسیر.
آمار زنده: شمارنده‌های zeptun (rx/tx) از طریق MethodChannel هر ۵ ثانیه.
```

نکته‌های مهم برای مراحل بعد:
- **MTU رابط TUN = 1500 هاردکد** (`AethoneVpnService.kt` حدود خط 407).
- مسیر داده Firefox از نوع TUN→userspace stack→SOCKS5 محلی است؛ موتور Go فقط یک SOCKS5 محلی + upstream است.
- نگاشت جهت آمار: TUN tx = دانلود ، TUN rx = آپلود.

### ۵. روش واقعی محاسبه Ping در AETHONE

`lib/connection/tunnel_probe.dart` — `TunnelProbe.trace()`:
1. اتصال TCP جدید به `127.0.0.1:1822` (SOCKS5 هسته).
2. SOCKS5 CONNECT با ATYP=domain به `www.cloudflare.com:80` — **DNS را خود هسته از طریق تونل حل می‌کند**.
3. `GET /cdn-cgi/trace` با `Connection: close`.
4. **pingMs = فاصله نوشتن درخواست تا خوانده‌شدن «کل» پاسخ و بسته‌شدن اتصال** (`readAll` تا close).
- ICMP نیست؛ RTT واقعی HTTP از داخل تونل است.
- تازه‌سازی: `Timer.periodic` هر **۵ ثانیه** (`_statsInterval`) — هر بار probe کامل جدید؛ گارد `_ticking` جلوگیری از همبستگی probeها را دارد (v4.26).
- Timeout پروب: **۲۰ ثانیه** (`_probeTimeout`).
- همان probe دروازه اعلام `Connected` است (اتصال بدون probe موفق هرگز Connected نمی‌شود).
- Speed Scan (تنظیمات اتصال): چند probe با انتخاب بهترین ping.

### ۶. روش Ping در Arman VPN (مرجع — `armanlife/arman-vpn-client`)

`core/internal/proxy/ping.go`:
- هدف: `www.google.com:443` از طریق پروکسی هر location؛ **فقط زمان round-trip دستور CONNECT** زمان‌گیری می‌شود (نه پاسخ HTTP و نه close) روی «جلسه H2 از قبل برقرارشده»؛ best-of-2؛ موازی‌سازی با سقف ۸؛ مهلت کل ۲ دقیقه؛ نتیجه در UI تا ۱۰ دقیقه معتبر است.
- keepalive در لایه transport: H2 PING با timeout ۵ ثانیه (`upstream_h2.go`).
- TUN آداپتور: `adapterMTU = 9000` (tunservice/server.go) — session MTU در بازه [1280, 9000].
- upstream: هم h2 و هم `upstream_h3.go` (QUIC با اندازه پکت اولیه آگاه از PMTU/RFC 8899).
- تضاد کلیدی با AETHONE: probe آرمان سبک‌تر است (CONNECT روی جلسه موجود)؛ probe AETHONE هر ۵ ثانیه اتصال SOCKS5 + CONNECT + HTTP کامل + close است و شامل DNSِ هسته و اثر راه‌اندازی جریان است.

### ۷. مشکل‌های شناسایی‌شده و مشاهدات (فرضیه — علت ریشه‌ای هنوز اثبات نشده)

| # | مشاهده | شواهد | مرحله بررسی |
|---|---|---|---|
| O-1 | probe زنده سنگین‌تر از لازم است: هر ۵ ثانیه اتصال+CONNECT+HTTP کامل+close؛ عدد شامل DNS هسته و راه‌اندازی جریان است | tunnel_probe.dart + platform_engine_adapter.dart:1984 | Stage 1 |
| O-2 | علامت ۸۰۰۰ms زیر timeout پروب (۲۰s) است → تأخیر واقعی/صف‌بندی است نه آرتیفکت timeout — اما دقیق‌بودن عدد باید در Stage 1 روشن شود | _probeTimeout=20s | Stage 1 |
| O-3 | MTU رابط TUN هاردکد 1500 (در برابر 9000 آداپتور آرمان) — بدون اندازه‌گیری تغییری نباید کند | AethoneVpnService.kt:407 | Stage 4 |
| O-4 | upstream موتور هم h2.go و هم h3.go دارد؛ transport فعال واقعی و امکان انتخاب آن هنوز از سورس استخراج نشده | phase1/fxv/internal/upstream/ | Stage 3 |
| O-5 | رفتار صف/buffer/backpressure در zeptun و internal/socks هنوز بررسی نشده | — | Stage 2 |

علت ریشه‌ای: **هنوز مشخص نیست** — هیچ اصلاح حدسی در Stage 0 انجام نشد.

### ۸. خط مبنا (Baseline)

دستگاه در محیط ایجنت در دسترس نیست → **تمام معیارها NOT TESTED**. هیچ داده ساختگی تولید نشد. پروتکل اندازه‌گیری آماده است:

- شرایط: یک گوشی (POCO X3 / ARM64 / HyperOS)، یک شبکه زیرین، زمان نزدیک، سرور و خانواده IP تا حد امکان یکسان برای AETHONE و Arman؛ روش اندازه‌گیری یکسان.
- ثبت برای هر دو اپ: Idle Ping (میانگین/حداقل/حداکثر ≥10 نمونه در سکون) ، Loaded Ping (حین دانلود) ، Max Ping ، Packet Loss ٪ ، Download/Upload Mbps ، CPU ٪ ، RAM ، پایداری (مدت تا قطع/افت) ، Transport واقعی (HTTP/TLS/QUIC) ، Endpoint (IP + خانواده IP).
- توجه: «کشور یکسان» = «سرور یکسان» نیست؛ IP خروجی هر دو ثبت شود.
- مقادیر اندازه‌گیری‌نشده در گزارش‌ها همیشه `NOT TESTED` درج می‌شود.

### ۹. تغییرات انجام‌شده در Stage 0

- ایجاد همین فایل `docs/performance/FIREFOX_VPN_PERFORMANCE_PROGRESS.md` (تنها تغییر؛ کدی تغییر نکرد).
- ایجاد شاخه `performance/firefox-vpn-optimization` از `ff9bc38` در مخزن اصلی.

### ۱۰. تست‌ها

- **NOT RUN** — در Stage 0 هیچ کدی تغییر نکرد (تغییر docs-only؛ تست مرتبط ندارد) و Flutter SDK در محیط ایجنت موجود نیست.
- تست‌های موجود مرتبط برای مراحل بعد: `test/firefox_engine_test.dart` ، `test/firefox_errors_test.dart` ، `test/firefox_login_test.dart` ، `test/connection_state_test.dart` و غیره (اجرای آن‌ها به مرحله دارای تغییر کد موکول است؛ در صورت نبود SDK محلی، اصلاحات + تست باید از طریق CI یا دستور مالک اجرا/تأیید شود).

### ۱۱. موارد تأییدنشده

- منبع دقیق APK نصب‌شده روی گوشی مالک (استنتاج: DA debug از run #3 @ ff9bc38 — تأیید نصب با مالک لازم است).
- همه معیارهای خط مبنا (NOT TESTED).
- transport بالادست فعال در زمان اجرا (Stage 3).
- رفتار واقعی صف‌ها/بافرها تحت بار (Stage 2).

---

## دستور دقیق ادامه کار (جلسه بعدی)

1. همین فایل را بخوان؛ `git -C <repo> log --oneline -3` و `git status` را بررسی کن.
2. **فقط Stage 1 را اجرا کن**: بررسی Ping و صحت اندازه‌گیری — تحلیل کامل `tunnel_probe.dart` + تیکر `platform_engine_adapter.dart` (خطوط ~542، ~1061-1100، ~1560-1600، ~1960-2100) + مصرف‌کنندگان pingMs؛ تعیین اینکه عدد ۸۰۰۰ms تأخیر واقعی است یا حاصل جزئیات اندازه‌گیری (DNS/CONNECT/close)؛ در صورت اثبات نقص روش، کوچک‌ترین اصلاح + تست؛ در غیر این صورت ثبت شواهد صحت.
3. قوانین: فقط مخزن `CHAKCAAD/AETHONE`؛ push فقط به `performance/firefox-vpn-optimization`؛ بدون Force Push/Release/تغییر pin upstream؛ CGO اندروید دست‌نخورده.
4. پایان مرحله: commit مستقل + به‌روزرسانی همین فایل + push + گزارش با قالب ۱۰ بندی مأموریت + توقف.

*(Token دسترسی در دستور مأموریت مالک تأمین می‌شود؛ در این فایل ذخیره نشده است.)*

---

## گیت مرحله آخر

| مرحله | Commit | عنوان |
|---|---|---|
| 0 | `3639838` | docs(performance): stage 0 — version match, data path, ping method, progress file |
