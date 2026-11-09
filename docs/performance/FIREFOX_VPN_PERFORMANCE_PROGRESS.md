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
| مرحله تکمیل‌شده آخر | **Stage 3 — Transport و نسخه HTTP: PASS** (حسابرسی کامل transport + بازگرداندن لاگ session-established که در تطبیق فاز ۱ حذف شده بود) |
| مرحله فعلی برای اجرای بعدی | **Stage 4 — MTU** |
| مخزن خصوصی | کاملاً خارج از محدوده — ممنوع |

### جدول مراحل

| مرحله | وضعیت |
|---|---|
| 0 — تثبیت نسخه و خط مبنا | **PASS** (بدون تغییر کد؛ فقط این فایل) |
| 1 — بررسی Ping و صحت اندازه‌گیری | **PASS** (شواهد ثبت شد؛ روش سالم؛ بدون تغییر کد — بخش «نتیجه Stage 1») |
| 2 — مسیر انتقال داده، TUN و صف‌ها | **PASS** (اصلاح واقعی: maxConns=256 پیش‌فرض upstream + رفع باگ slot-steal + لاگ تشخیصی + ۶ تست جدید — بخش «نتیجه Stage 2») |
| 3 — Transport و نسخه HTTP | **PASS** (حسابرسی کامل + اصلاح واقعی: بازگرداندن لاگ session-established برای رؤیت transport واقعی on-device + تست جدید — بخش «نتیجه Stage 3») |
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

| # | مشاهده | شواهد | وضعیت |
|---|---|---|---|
| O-1 | probe زنده سنگین از آرمان است (هر ۵s اتصال+CONNECT+HTTP کامل+close) | tunnel_probe.dart + adapter:1984 | **تحلیل شد (S1)**: عدد ~۲-۳× معنای ping آرمان است (CONNECT+درخواست/پاسخ+انتشار close)؛ DNS محلی و TLS در هر probe انجام نمی‌شود؛ سربار ترافیک/CPU ناچیز |
| O-2 | علامت ۸۰۰۰ms | _probeTimeout=20s | **حل شد (S1)**: ۸۰۰۰ms یک اندازه‌گیری موفق واقعی است، نه آرتیفکت timeout/retry (timeout به مسیر خطا/strike می‌رود نه عدد)؛ رشد 200→8000 = تخریب واقعی مسیر داده |
| O-3 | MTU رابط TUN هاردکد 1500 (در برابر 9000 آداپتور آرمان) — بدون اندازه‌گیری تغییری نباید کند | AethoneVpnService.kt:407 | Stage 4 — بدون اندازه‌گیری تغییری نکرد |
| O-4 | transport پیش‌فرض h2 است (config Validate: transport==''→h2؛ Dart هم 'h2') | engine/config.go + firefox_protocol.dart | Stage 3 — تایید شد که upstream هم defaultUpstreamConnections=1 (تک‌اتصال) دارد |
| O-5 | رفتار صف/buffer/backpressure در zeptun و internal/socks | — | **بررسی شد (S2)**: TunnelWriteBuffer کراندار 1MB + backpressure صحیح؛ copyConn 64KB pool + drain نیم‌بسته ۲ دقیقه؛ بدون صف نامحدود در Go. بافرهای zeptun هم کراندار (rx 64KB/tx 128KB/tx budget 4MB) |
| O-6 | idleTimeout جریان‌های SOCKS نامحدود (پیش‌فرض 0 = unlimited) | engine/config.go + firefox_protocol.dart | **تحلیل شد (S2)**: پیش‌فرض upstream demo هم 0 است؛ zeptun جریان idle دستگاه را بعد از ۶۰۰s می‌بندد (cascade به بستن استریم h2) — بدون شواهد on-device تغییری نکرد؛ لاگ تشخیصی live=N برای پایش اضافه شد |
| O-7 | maxConns نامحدود (0 = unlimited) — بدون سقف اتصال هم‌زمان | engine/config.go + main.go:270 | **اصلاح شد (S2)**: پیش‌فرض 256 موتور بازگردانده شد (= defaultMaxConnections خود upstream که در تطبیق حذف شده بود) + رد مقدار منفی + باگ slot-steal در handleConn رفع شد |
| O-8 | همه جریان‌های دستگاه روی یک اتصال TLS+h2 مالتی‌پلکس → HoL تحت loss | upstream/h2.go (تک session، تک ClientConn) | **تایید شد (S2)**: تک‌اتصال = طراحی خود upstream (defaultUpstreamConnections=1؛ pool گزینه‌ای است که فاز ۱ آگاهانه حذف کرده). مکانیزم دقیق: x/net/http2 awaitOpenSlotForStreamLocked منتظر نامحدود slot می‌ماند وقتی استریم‌های باز به MAX_CONCURRENT_STREAMS سرور برسند → رشد تدریجی ping. سقف 256 بازگردانده شد؛ تجزیه pool به Stage 3 موکول |
| O-9 | **جدید (S2)**: باگ slot-steal — defer releaseConnSlot قبل از acquire ثبت شده بود؛ هر اتصال ردشده توکن یک اتصال زنده را می‌دزدد و سقف را فرسوده می‌کند | socks/server.go handleConn (قبل از اصلاح) در برابر upstream:2026-2033 | **اصلاح شد (S2)**: ترتیب defer مطابق upstream شد؛ تست رگرسیون دو-رد شدن متوالی را تضمین می‌کند (روی کد باگ‌دار FAIL شد، روی اصلاح PASS) |
| O-10 | **جدید (S2)**: مقدار واقعی SETTINGS_MAX_CONCURRENT_STREAMS سرور فایرفاکس و رفتار on-device نامشخص | — | NOT TESTED — نیاز به گوشی؛ لاگ تشخیصی live=N + رد سقف با پیام `connection limit reached` برای پایش اضافه شد |
| O-11 | **جدید (S3)**: لاگ session-established خود upstream (شامل transport واقعی) در تطبیق فاز ۱ حذف شده بود؛ رویداد upstreamReady هم transport را می‌فرستد ولی Dart آن را در لاگ رندر نمی‌کند → transport فعال در زمان اجرا روی گوشی قابل راستی‌آزمایی نبود (همان مورد تأییدنشده Stage 0 §11) | upstream main.go:2493,2717,351-353 در برابر h2.go/h3.go/controller.go (بدون لاگ) + firefox_protocol.dart logLine (default case) | **اصلاح شد (S3)**: لاگ `upstream session established transport=%s proxy=%s establish_latency=%s` در Controller.Start بازگردانده شد (آینه رفتار upstream؛ بدون تغییر رفتاری) |

علت ریشه‌ای: **دو عامل ساختاری با شواهد کد اثبات شد (S2)** — (۱) حذف سقف اتصال upstream (maxConns=256→unlimited) + (۲) مسدودشدن نامحدود http2 در awaitOpenSlotForStreamLocked هنگام پرشدن سقف استریم سرور؛ ترکیب این دو، رشد تدریجی ping 200→8000ms را توضیح می‌دهد (هر اتصال دستگاه = یک استریم باز روی تک ClientConn؛ probe هر ۵s باید برای slot صف بگیرد). باگ slot-steal (O-9) هم که در سقف جدید فعال می‌شد، رفع شد. تأیید نهایی on-device (مقدار سقف سرور + عدد live=N در عمل) NOT TESTED — معیارهای تأیید در بخش Stage 2.

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

## نتیجه Stage 1 (اجرای 2026-11-09) — بررسی Ping و صحت اندازه‌گیری

### پاسخ پرسش‌های مأموریت (با شواهد کد)

| پرسش | پاسخ | شواهد |
|---|---|---|
| مقصد Ping | `www.cloudflare.com:80` — مقصد اینترنتی (نه سرور VPN)، از داخل تونل | tunnel_probe.dart:71-72 |
| اندازه‌گیری از داخل تونل؟ | بله — SOCKS5 موتور روی 127.0.0.1:1822 (loopback؛ ترافیک خود اپ از TUN مستثنا) | tunnel_probe.dart + AethoneVpnService.kt (disallow خود اپ) |
| DNS در هر probe؟ | خیر محلی — CONNECT با ATYP=domain است؛ «پراکسی» دامنه را سمت سرور حل می‌کند (هر probe = ۱ استریم h2 جدید) | socks/server.go Handshake/ReadAddr + h2.go OpenTunnel |
| TLS در هر probe؟ | خیر — session طولانی‌عمر TLS1.2+ALPN-h2 یک‌بار برقرار می‌شود؛ خود trace روی پورت 80 plain است | h2.go NewH2ProxySession |
| Timeoutها | probe دات: ۲۰s (تیکر) / ۸s (اسکن هوشمند)؛ engine: handshake ۱۰s ، OpenTunnel ۲۰s؛ keepalive: PING هر ۱۰s با مهلت ۵s | adapter:598,655 + engine/config.go + h2.go:27-28 |
| Probe هم‌زمان | دقیقاً ۱ — گارد `_ticking` + تیکر تکی + اسکن ترتیبی؛ probeها stack نمی‌شوند (v4.26) | adapter:1987-1998 |
| باقی‌ماندن probe بعد از timeout | خیر — Dart در finally سیکت را destroy می‌کند؛ engine با خطای copy هر دو conn را می‌بندد و استریم h2 کنسل می‌شود | tunnel_probe.dart trace/finally + socks/server.go ProxyBidirectional/copyConn |
| مدیریت Retry | walk اتصال: هر ۲s داخل بودجه؛ حالت متصل: سلامت درجه‌بندی‌شده — listener رد شد→۲ strike؛ listener جواب داد→۱۲ تیک (۶۰s) کاهش‌یافته→EngineHealthProbeFailed؛ بدون طوفان retry | adapter:1845-1855, 2097-2118 |
| سربار CPU/ترافیک سیستم ping | ناچیز — چند صد بایت هر ۵s + PING h2 هر ۱۰s + یک exit probe فقط در راه‌اندازی | adapter _tick + h2.go runKeepAlive + main.go:288 |
| ۸۰۰۰ms واقعی یا آرتیفکت؟ | **واقعی** — عدد یک probe موفق است (۸۰۰۰ < timeout ۲۰s)؛ timeout به مسیر خطا می‌رود نه به عدد؛ retry در عدد وارد نمی‌شود | تحلیل کامل مسیر بالا |

### تحلیل ساختاری عدد (مقایسه با Arman)

- probe آرمان: فقط RTT دستور CONNECT روی جلسه H2 موجود (best-of-2) ≈ ~۲ مسیر RTT.
- probe AETHONE: CONNECT (شامل اتصال سمت سرور پراکسی به cloudflare) + درخواست/پاسخ HTTP + انتشار close ≈ ~۳-۴ مسیر RTT.
- نتیجه: برای یک کیفیت شبکه یکسان، عدد AETHONE ساختاراً ~۲-۳× بزرگ‌تر از آرمان است (200ms در AETHONE ≈ ~70-100ms در آرمان). این تورم «ثابت» است و رشد تدریجی 200→8000 را توضیح نمی‌دهد.

### نتیجه Stage 1

- **روش Ping سالم است** → طبق دستور مأموریت («اگر روش Ping سالم بود، شواهد را ثبت و سراغ مرحله بعد برو») هیچ تغییر کدی انجام نشد. حفظ روش فعلی همچنین مقایسه before/after مرحله ۸ را معتبر نگه می‌دارد.
- **رشد 200→8000ms تخریب واقعی مسیر داده است** (نه خطای اندازه‌گیری) → شکار علت در Stage 2، با سه سرنخ جدید مستندشده: O-6 (idle نامحدود) ، O-7 (maxConns نامحدود) ، O-8 (تک‌اتصال h2 مالتی‌پلکس همه جریان‌های دستگاه → head-of-line blocking تحت loss).
- موارد جانبی تأییدشده: پورت 1822 فقط برای موتور Firefox (zeptun در حالت تونل به آن سوکت می‌زند)؛ exit probe موتور فقط یک‌بار در راه‌اندازی اجرا می‌شود؛ renewal مسیر کنترلی جدا دارد (FetchProxyPass به guardian) و روی session داده h2 سوار نیست.

### تست‌های Stage 1

- **NOT RUN** — هیچ کدی تغییر نکرد (تحلیل + مستندسازی). Flutter SDK در محیط ایجنت موجود نیست؛ تستی از probe در `test/` موجود نیست (بررسی شد — ۲۵ فایل تست، هیچ‌کدام tunnel_probe).

---

## نتیجه Stage 2 (اجرای 2026-11-09) — مسیر انتقال داده، TUN و صف بسته‌ها

### ۱. مسیر کامل داده (رفت و برگشت) — استخراج‌شده از سورس

```text
رفت: اپ → TUN fd → zeptun (Zig userspace stack، preset mobile: rx window 64KB،
tx buffer 128KB، tx budget 4MB، max_tcp_sessions=1200، tcp_idle_timeout 600s،
1 io worker) → TCP به 127.0.0.1:1822 → socks.Server.handleConn (سقف جدید ۲۵۶) →
controller.OpenTunnel → H2ProxySession.OpenTunnel (تک ClientConn) →
TunnelWriteBuffer کراندار 1MB (بدنه درخواست CONNECT) → TLS1.2+ALPN-h2 → سرور
برگشت: سرور → resp.Body (استریم h2) → TunnelConn.Read → copyConn (بافر pooled 64KB)
→ سوکت loopback → zeptun → TUN → اپ
پاک‌سازی: EOF هر جهت → بستن هر دو conn → TunnelConn.Close → CloseWrite(END_STREAM)
+ CloseRead + cancel؛ zeptun هم جریان idle >600s را abort و سوکت handler را می‌بندد
(sys.close(up.fd) در tryFree) → cascade به EOF سمت Go
```

### ۲. شواهد کلیدی (همه از سورس؛ بدون حدس)

| شواهد | محل |
|---|---|
| پیش‌فرض‌های upstream demo: handshake=10s، idle=0، **maxConns=256**، upstreamConns=1 | `phase1/firefox-vpn-client/cmd/proxy-demo/main.go:59-62` (پین 55ad91a2 تأیید bit-exact با fetch_upstream.sh) |
| AETHONE فقط پیش‌فرض handshake را حفظ کرده بود؛ MaxConns بدون پیش‌فرض → 0 → unlimited | `fxv/internal/engine/config.go` (قبل از اصلاح) + `main.go:270-273` |
| Dart هیچ‌گاه idleTimeoutMs/maxConns نمی‌فرستد | `firefox_protocol.dart` toJson (فیلدها اصلا وجود ندارند) |
| ترتیب defer صحیح upstream (release فقط بعد از acquire) | upstream main.go:2026-2033 در برابر نسخه تطبیق‌یافته |
| مسدود شدن نامحدود RoundTrip وقتی استریم‌های باز = MAX_CONCURRENT_STREAMS سرور | x/net/http2 v0.53.0 transport.go:1741 `awaitOpenSlotForStreamLocked` → `cc.cond.Wait()` |
| مرگ جریان idle توسط zeptun بعد از 600s + بستن سوکت handler | native/zeptun src/stack/tcp.zig:1747-1752 + tryFree (sys.close(up.fd)) |
| کراندار بودن بافرها: TunnelWriteBuffer 1MB + notFull.Wait (backpressure) | fxv/internal/upstream/tunnel.go:76-108 |
| drain نیم‌بسته کراندار (۲ دقیقه) | fxv/internal/socks/server.go halfCloseDrainTimeout |

### ۳. علت ریشه‌ای اثبات‌شده (سطح کد)

۱. **حذف سقف اتصال**: تطبیق فاز ۱ پیش‌فرض maxConns=256 خود upstream را حذف کرد → موتور با سقف نامحدود اجرا می‌شد. هر جریان TCP دستگاه = یک استریم h2 باز روی تک ClientConn.
۲. **مسدودسازی نامحدود http2**: وقتی تعداد استریم‌های باز به SETTINGS_MAX_CONCURRENT_STREAMS سرور برسد، هر CONNECT جدید (شامل probe هر ۵s) در `awaitOpenSlotForStreamLocked` به‌صورت نامحدود منتظر slot می‌ماند (تنها مرز = OpenTunnel timeout ۲۰s که به مسیر خطا می‌رود). با انباشت جریان‌ها (zeptun تا 1200 session و 600s idle اجازه می‌دهد)، زمان انتظار probe به‌تدریج رشد می‌کند → **الگوی دقیق 200→8000ms**.
۳. **باگ slot-steal (کشف جدید)**: `defer s.releaseConnSlot()` قبل از acquire ثبت شده بود → هر اتصال ردشده یک توکن از اتصال زنده می‌دزدید → سقف با هر رد شدن یکی فرسوده می‌شد (روی کد قبلی با maxConns=0 نامرئی؛ با هر سقفی فعال). نسخه upstream ترتیب صحیح دارد.

### ۴. اصلاح اعمال‌شده (کوچک‌ترین اصلاح مؤثر — یک متغیر عملکردی)

- **`fxv/internal/engine/config.go`**: ثابت `DefaultMaxConns = 256` + در Validate: صفر→۲۵۶ + رد مقدار منفی (`maxConnsNegative`). این بازگرداندن پیش‌فرض خود upstream است، نه مقدار tune‌شده. مقدار صریح Dart همچنان معتبر است (override).
- **`fxv/internal/engine/contract.go`**: جزئیات خطای جدید `maxConnsNegative`.
- **`fxv/internal/socks/server.go`**: (الف) رفع باگ slot-steal — ترتیب defer مطابق upstream؛ (ب) لاگ تشخیصی `socks: conn tracked/untracked live=N` (Debug، از طریق stderr → core-log.txt مالک) برای پایش انباشت جریان on-device.
- **`fxv/cmd/libfirefoxvpn/main.go`**: خط راه‌اندازی به سبک upstream با حدود مؤثر: `socks5 ready on %s handshake_timeout=%s idle_timeout=%s max_conns=%d`.
- **idleTimeout عمداً دست نخورد** — پیش‌فرض upstream (0) است؛ تغییرش بدون اندازه‌گیری حدسی می‌بود (قانون ماموریت). پایش با live=N انجام می‌شود؛ تصمیم در مراحل بعد با شواهد on-device.
- معماری/پورت/pin/CGO/Child-Process همه دست‌نخورده.

### ۵. تست‌های Stage 2 (Go 1.25.0 — همان نسخه CI؛ ابزار در sandbox نصب شد)

| تست | نتیجه |
|---|---|
| `go test ./internal/socks/ ./internal/engine/` (قبل از تغییرات — baseline) | PASS |
| `TestConnectionLimitRejectsBeyondCap` (رد سریع فراتر از سقف + عدم فرسایش سقف + بازیابی پس از آزادسازی slot) | PASS — و روی کد باگ‌دار FAIL شد (اثبات اثر تست رگرسیون) |
| `TestConcurrentTunnelsBelowCapRelay` (۱۶ تونل هم‌زمان زیر سقف ۱۶) | PASS |
| `TestSequentialTunnelsNoConnOrGoroutineLeak` (۱۰۰ چرخه؛ صفر conn باقی‌مانده؛ goroutine ≤ baseline+2؛ شمارش لاگ تشخیصی) | PASS |
| `TestMaxConns*` (پیش‌فرض 256 / حفظ مقدار صریح 64 / رد -1) — سه تست جدید در engine | PASS |
| کل بسته‌ها با `-race` (socks + engine) | PASS (1.06s / 1.02s) |
| fakeOpener ارتقا یافت: `halfClosePipeConn` با CloseWrite واقعی (مثل TunnelConn) تا drain نیم‌بسته در تست‌ها فوری تمام شود | PASS |

### ۶. موارد NOT TESTED

- **Build کامل موتور (cmd/libfirefoxvpn با quic-go/utls) محلی ممکن نشد** — محدودیت دیسک sandbox (~180MB آزاد؛ درخت وابستگی‌ها بیشتر می‌خواهد). کامپایل parse-check شد (gofmt -e) و هر دو پکیج تغییریافته کامل تست شدند. **معیار تأیید**: job «Firefox engine (Go 1.25.0 — CGO + NDK r28c, all ABIs)» در CI (workflow_dispatch روی integration/firefox-vpn-debug بعد از merge، یا دستور مالک) باید سبز شود.
- **رفتار on-device**: مقدار واقعی MAX_CONCURRENT_STREAMS سرور، مسیر رشد live=N، و اثر اصلاح بر رشد ping — نیاز به گوشی مالک. **معیار تأیید**: در core-log.txt، خط `socks5 ready ... max_conns=256` باید دیده شود؛ روند live=N باید زیر 256 بماند؛ اگر `connection limit reached` ظاهر شد یعنی دستگاه واقعا >256 جریان هم‌زمان دارد (آن موقع باید سقف بازبینی شود)؛ رشد ping باید متوقف/کند شود.
- تست‌های Flutter/Dart اجرا نشدند (SDK موجود نیست؛ تغییر Dart وجود ندارد).

### ۷. وضعیت گیت Stage 2

- Commit مستقل روی `performance/firefox-vpn-optimization` (جدول انتهای فایل)؛ فایل‌های تغییرکرده: `phase1/fxv/internal/engine/{config.go,config_test.go,contract.go}`، `phase1/fxv/internal/socks/{server.go,server_test.go}`، `phase1/fxv/cmd/libfirefoxvpn/main.go`، همین فایل پیشرفت.
- کپی upstream پس از بررسی دوباره fetch شد و manifest SHA256 بدون تغییر ماند (پین سالم؛ فایل upstream هرگز commit نمی‌شود).

---

## نتیجه Stage 3 (اجرای 2026-11-09) — Transport و نسخه HTTP

### ۱. فهرست کامل Transport واقعی (از سورس — همه با شواهد)

| قابلیت | وضعیت | شواهد |
|---|---|---|
| Transport پیش‌فرض | **h2** — TLS1.2+ با ALPN h2، تک `tls.Conn` + تک `http2.ClientConn`؛ همه جریان‌های دستگاه = استریم CONNECT روی همان یک اتصال (multiplex کامل) | controller.go Start/default + h2.go NewH2ProxySession + engine/config.go Validate (transport==''→h2) |
| HTTP/3 | **واقعی و قابل انتخاب** — QUIC (quic-go v0.59.0) + TLS1.3 + ALPN h3؛ dial ترتیبی روی همه IPها با بودجه per-attempt؛ InitialPacketSize=1200 (کف RFC 9000؛ DPLPMTUD/RFC 8899 بزرگش می‌کند)؛ KeepAlivePeriod=30s | h3.go NewH3ProxySession + quic-go |
| HTTP/1.1 | **وجود ندارد** — موتور فقط h2/h3 دارد (هم upstream و هم AETHONE)؛ مقایسه h1 در برابر h2 در سطح API موتور «غیرممکن» است؛ افزودن h1 = قابلیت جدید بدون پشتوانه upstream (ممنوع طبق مأموریت) | upstream main.go (فقط newH2/newH3ProxySession) + engine/config.go detailTransportUnknown |
| انتخاب Transport از UI | **موجود و کامل** — SettingPills های h2/h3 در صفحه تنظیمات Firefox → store (setFirefoxTransport) → persistence → adapter (_firefoxTransportForEngine: 'h3' پاس، بقیه→'h2') → stdin JSON → engine | firefox_page.dart:166-174 + connection_store.dart:383-385 + platform_engine_adapter.dart:2286-2289,2448 |
| Connection Reuse | حداکثری — تک session طولانی‌عمر؛ renewal توکن را درجا عوض می‌کند (UpdateToken بدون rebuild)؛ keepalive جلوی مرگ خاموش را می‌گیرد | controller.go renew/UpdateToken + h2.go runKeepAlive |
| Multiplexing | تک‌اتصال (upstream defaultUpstreamConnections=1)؛ pool بالادست (-upstream-conns با client-IP affinity + failover) در فاز  ۱ آگاهانه حذف شده — بازگرداندنش تغییر معماری بزرگ است و طبق برنامه فقط با شواهد on-device و تأیید جداگانه مالک | upstream main.go:188 + حذف‌های مستندشده در controller.go header |
| Keepalive/سلامت h2 | app-level: PING هر ۱۰s با مهلت ۵s (یک miss ⇒ مرگ session) + transport-level: ReadIdleTimeout=30s / PingTimeout=15s / WriteByteTimeout=30s — همه **bit-identical با upstream پین‌شده** | h2.go:27-28,105-107 vs upstream main.go:66-67,2484-2486 |
| Keepalive/سلامت h3 | QUIC-level: KeepAlivePeriod=30s؛ liveness از Context اتصال؛ بدون حلقه PING app-level (همان upstream) | h3.go:80,206-211 vs upstream main.go:2665 |

### ۲. تحلیل زیر loss (سطح کد — مقایسه h2/h3)

- **h2**: همه استریم‌ها روی یک TCP ⇒ Head-of-Line واقعی تحت loss (تأیید O-8 از Stage 2)؛ در loss پایدار، ReadIdleTimeout/PingTimeout بعد از ~30-45s اتصال را می‌بندد (بازتعریف به‌جای hang بی‌نهایت). مکانیک دقیق سقف استریم (بازبینی S3 از x/net/http2 v0.53.0): تا رسیدن SETTINGS سرور سقف=۱۰۰ است؛ اگر SETTINGS اولیه سرور فیلد را ذکر نکند سقف=۱۰۰۰ می‌شود؛ در هر حالت `cc.RoundTrip` مستقیم (بدون pool) در `awaitOpenSlotForStreamLocked` تا آزادشدن slot می‌ماند — تنها مرز = مهلت OpenTunnel (۲۰s).
- **h3**: هر استریم QUIC بازیابی loss مستقل دارد (بدون HoL بین استریم‌ها)؛ InitialPacketSize=1200 + DPLPMTUD با MTU پایین سازگار است. حالت شکست: UDP مسدود ⇒ dial شکست می‌خورد ⇒ موتور صادقانه fail می‌شود (بدون fallback خودکار به h2 — تصمیم upstream: انتخاب سخت).
- **نتیجه سطح کد**: h3 ذاتاً زیر loss بهتر است؛ h2 مسیر اثبات‌شده پیش‌فرض است. **مقایسه عملی on-device: NOT TESTED** (نیاز به گوشی مالک؛ انتخابگر UI + لاگ جدید stage 3 ثبت نتیجه را ممکن می‌کند). پیش‌فرض طبق قانون مأموریت بدون اندازه‌گیری تغییر نکرد (h2 ماند).

### ۳. مقایسه با Arman (مرجع — فقط تحلیل، بدون کپی)

| مورد | AETHONE (upstream فایرفاکس) | Arman | تصمیم |
|---|---|---|---|
| keepalive app-level | PING هر ۱۰s / ۵s مهلت / ۱ miss ⇒ مرگ | PING هر ۵s / ۵s مهلت / ۲ miss متوالی ⇒ مرگ | تفاوت جزئی در سرعت تشخیص (~۱۰-۱۵s هر دو)؛ مقدار خود upstream است؛ بدون شواهد on-device تغییر نشد |
| ReadIdleTimeout/PingTimeout/WriteByteTimeout | 30/15/30s | 30/15/30s (یکسان) | — |
| StrictMaxConcurrentStreams | تنظیم نشده | true | فقط روی مسیر pool سطح Transport اثر دارد (جلوگیری از dial اتصال جدید)؛ AETHONE مستقیم cc.RoundTrip می‌زند و مسدودسازی slot مسیر واحدش است — **قابل‌انتقال نیست، صرفاً مستند شد** |
| adapterMTU | TUN=1500 هاردکد | 9000 (session در [1280,9000]) | موضوع Stage 4 |
| h3 | موجود (قابل انتخاب) | موجود (PMTU-aware initial size) | — |

### ۴. مشکل اثبات‌شده و اصلاح اعمال‌شده (یک تغییر منطقی، بدون تغییر رفتاری)

- **مشکل (O-11)**: تطبیق فاز ۱ هر سه لاگ session-established بالادست را حذف کرده بود (`upstream HTTP/2 session established proxy=…` / `upstream HTTP/3 session established proxy=… remote=…` / `transport=http2|http3 …`)؛ رویداد upstreamReady هم transport را می‌فرستاد ولی Dart فقط `engine: upstreamReady` خالی لاگ می‌کرد. نتیجه: transport فعال روی گوشی (فیلد «Transport واقعی» جدول خط مبنا مأموریت) قابل ثبت نبود و هیچ مقایسه h2/h3 قابل استناد نمی‌شد.
- **اصلاح**: `Controller.Start` بعد از برقراری session با موفقیت، از طریق `cfg.Logf` (→ Info → stderr → core-log.txt مالک) لاگ می‌زند: `upstream session established transport=%s proxy=%s establish_latency=%s` — آینه‌ای از همان حقایقی که upstream در همان نقطه لاگ می‌کند (proxy + transport + latency). تابع کمکی `sessionEstablishedLog` + تست رگرسیون `TestSessionEstablishedLog` (قرارداد سه فیلد برای هر دو h2/h3).
- **چرا این محل**: کنترلر هم logger را دارد هم می‌داند کدام شاخه (h2/h3) واقعاً بالا آمده؛ لاگ فقط بعد از موفقیت واقعی session صادر می‌شود (نه صرف پیکربندی)؛ امضای سازنده‌های session دست نخورد.
- **تغییر رفتاری: هیچ** — فقط یک خط لاگ Info. معماری/پورت/pin/CGO/Child-Process/پیش‌فرض‌ها همه دست‌نخورده. (یادداشت Stage 5: نسخه upstream برای h3 فیلد remote=IP را هم لاگ می‌کند؛ آن فیلد عمداً به Stage 5 موکول شد تا endpoint تفکیک شود.)

### ۵. تست‌های Stage 3 (Go 1.25.0 — همان نسخه CI؛ ابزار دوباره در sandbox نصب شد)

| تست | نتیجه |
|---|---|
| `gofmt -e` روی هر دو فایل تغییرکرده | PASS — بدون خطای parse |
| ماژول مستقل با کد عیناً کپی‌شده از فایل‌های واقعی (`sessionEstablishedLog` + `TestSessionEstablishedLog`) | **PASS** — `ok stage3verify 0.001s` (قرارداد قالب: transport=/proxy=/establish_latency= با گردکردن صحیح: 1234ms→`1.234s`، 0→`0s`) |
| رگرسیون Stage 2: `go test ./internal/socks/ ./internal/engine/` | PASS (هر دو پکیج سبز؛ cache گرم) |
| `go test ./internal/upstream/` (کل پکیج با quic-go/utls) | **NOT RUN محلی** — محدودیت دیسک sandbox (۲۰MB آزاد؛ کامپایل quic-go نمی‌گنجد)؛ **معیار CI**: `go vet ./...` + `go test ./...` در job «Firefox engine» (بعد از merge به integration/firefox-vpn-debug یا dispatch مالک) باید سبز شود — تست جدید دقیقاً همانجاست |
| تست‌های Flutter/Dart | NOT RUN — SDK موجود نیست؛ تغییر Dart در این مرحله وجود ندارد |

### ۶. موارد NOT TESTED

- **مقایسه عملکرد واقعی h2 در برابر h3** (و اثر Keepalive/Multiplexing روی اعداد) — نیاز به گوشی مالک با روش یکسان. روش پیشنهادی ثبت: در تنظیمات Firefox هر دو حالت را وصل کنید؛ برای هر حالت خط `upstream session established transport=… proxy=…` در core-log.txt باید مطابق انتخاب باشد (راستی‌آزمایی زنده)؛ سپس Idle/Loaded Ping + Download/Upload + Packet Loss هر دو حالت ثبت شود.
- **transport فعال on-device تا قبل از اجرای مالک** — لاگ جدید الآن موجود است ولی خروجی واقعی گوشی هنوز جمع نشده.
- **تصمیم pool بالادست** — موکول به شواهد on-device (HoL ماندگار زیر loss که با سقف ۲۵۶ حل نشد) + تأیید جداگانه مالک (طبق برنامه Stage 2).

### ۷. وضعیت گیت Stage 3

- Commit کد: مستقل روی `performance/firefox-vpn-optimization` (جدول انتهای فایل)؛ فایل‌های تغییرکرده: `phase1/fxv/internal/upstream/{controller.go,upstream_test.go}` (+ همین فایل پیشرفت در commit جداگانه docs).
- کپی upstream دوباره با pin بررسی شد: `55ad91a` — همه مقادیر transport تطبیق bit-identical؛ فایل upstream هرگز commit نمی‌شود.

---

## دستور دقیق ادامه کار (جلسه بعدی)

1. همین فایل را بخوان؛ `git -C <repo> log --oneline -3` و `git status` را بررسی کن.
2. **فقط Stage 4 را اجرا کن**: MTU —
   - وضعیت فعلی: MTU رابط TUN = **۱۵۰۰ هاردکد** در `AethoneVpnService.kt` (~خط 407) — O-3؛ آدرس 172.19.0.1/30؛ DNS 172.19.0.2.
   - از سورس استخراج کن: MTU رابط TUN، رفتار پکت‌های بزرگ در zeptun (بافرهای rx 64KB/tx 128KB/tx budget 4MB از Stage 2 مستند شده)، TCP MSS در استک userspace، PMTU discovery، ICMP Packet-Too-Big، و رابطه با InitialPacketSize=1200 هنگام h3 (DPLPMTUD).
   - مقایسه با Arman: adapterMTU=9000 (tunservice/server.go) — فقط مرجع؛ بدون دلیل فنی کپی نشود.
   - مقادیر آزمایشی مأموریت (۱۴۲۰/۱۴۰۰/۱۳۶۰/۱۳۰۰/۱۲۸۰) فقط با اندازه‌گیری on-device و هر بار فقط یک متغیر؛ بدون اندازه‌گیری هیچ پیش‌فرضی تغییر نکند.
   - اگر تغییری اعمال شد: همان یک متغیر + تست + commit مستقل + ثبت در همین فایل.
3. قوانین: فقط مخزن `CHAKCAAD/AETHONE`؛ push فقط به `performance/firefox-vpn-optimization`؛ بدون Force Push/Release/تغییر pin upstream؛ CGO اندروید دست‌نخورده؛ چند متغیر هم‌زمان تغییر نکند.
4. پایان مرحله: commit مستقل + به‌روزرسانی همین فایل + push + گزارش با قالب ۱۰ بندی مأموریت + توقف.

*(Token دسترسی در دستور مأموریت مالک تأمین می‌شود؛ در این فایل ذخیره نشده است.)*

---

## گیت مرحله آخر

| مرحله | Commit | عنوان |
|---|---|---|
| 0 | `3639838` | docs(performance): stage 0 — version match, data path, ping method, progress file |
| 1 | `c1951a7` | docs(performance): stage 1 — ping measurement audit (method sound, 8000ms real) |
| 2 | `8865a8e` | fix(engine): restore the upstream max-conns cap (256), fix rejection slot-steal, live-conn diagnostics |
| 3 | `6e78ed3` | fix(engine): restore the upstream session-established transport logging (stage 3) |
