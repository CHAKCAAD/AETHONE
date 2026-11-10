# FIREFOX GUARDIAN PSIPHON BOOTSTRAP — PERMANENT PROGRESS FILE

> مرجع دائمی مأموریت Guardian Bootstrap Manager (عبور HTTP 451 با Psiphon و ترکیب‌های موجود).
> هر جلسه جدید باید این فایل را بخواند و از همین وضعیت ادامه دهد — نه از حافظه مکالمه.
> هیچ Token/Session/Refresh Token یا اطلاعات حساب در این فایل قرار نمی‌گیرد.

## وضعیت کلی

| فیلد | مقدار |
|---|---|
| تاریخ آخرین اجرا | 2026-11-10 |
| Repository | `CHAKCAAD/AETHONE` (تنها مخزن مجاز) |
| Branch کاری | `feature/firefox-guardian-psiphon-bootstrap` |
| Base Commit | `ce852ea` (= tip شاخه `performance/firefox-vpn-optimization`؛ شامل تمام اصلاحات Performance مراحل ۰–۸) |
| آخرین Commit | (انتهای فایل — «گیت مراحل») |
| مرحله فعلی | **Stage 6 — Renewal و Lifecycle کامل** |
| مرحله تکمیل‌شده آخر | **Stage 5 — PASS (Routing RoundTripper + اتصال انتخابی Guardian؛ جزئیات بخش Stage 5)** |
| مخزن خصوصی | کاملاً خارج از محدوده — ممنوع |

### وضعیت Git در شروع مأموریت (تأییدشده)

- `ce852ea` در مخزن موجود است و tip هر دو شاخه local/remoteِ `performance/firefox-vpn-optimization` است.
- اصلاحات Performance **هنوز وارد شاخه پیش‌فرض `ci-bootstrap/v4.4` نشده‌اند** (تصمیم ادغام با مالک است) → شاخه جدید باید از `ce852ea` ساخته شود (انجام شد).
- شاخه `integration/firefox-vpn-debug` @ `ff9bc38` (پایه شاخه performance) دست‌نخورده.
- قواعد: بدون Force Push / بازنویسی تاریخچه / Release عمومی / تغییر مخزن خصوصی.

---

## یافته‌های Stage 0 (اجرای 2026-11-10)

### ۱. معماری فعلی Guardian (موتور Firefox — `phase1/fxv` + pin upstream)

- **Control Plane مشترک**: FxA + Guardian + Remote Settings همه از یک `http.Client` مشترک عبور می‌کنند (`phase1/firefox-vpn-client/http_client.go` در pin `55ad91a2ccea1c93e69c82a08a7681e279884db5`).
- **API تزریق Transport موجود است**: `vpnclient.SetControlPlaneTransport(transport http.RoundTripper)` — باید قبل از اولین درخواست control-plane صدا زده شود؛ کلiente فرایندی مشترک است.
- **مسیر مستقیم**: uTLS با `HelloFirefox_Auto` ( fingerprint فایرفاکس؛ خروجی stage قبلی perf: `NewControlPlaneTransport` + `dialFirefoxTLS`). مسیر پروکسی‌شده: net/http خودش TLS می‌زند (HTTP/1.1 pin) — مستند در کامنت خود upstream.
- **Endpointهای واقعی Guardian** (guardian.go، همه روی `https://vpn.mozilla.org` پیش‌فرض = `GuardianEndpointDefault`، قابل override با `FirefoxEngineConfig.guardian`):
  - `GET /api/v1/fpn/token` → `FetchProxyPass` (ProxyPassInfo با claims نادر JWT: exp/nbf — تمدید خودکار توسط `runRenewalLoop` با `renewLead`).
  - `GET /api/v1/fpn/status` → `FetchUserInfo` (Entitlement).
  - `POST /api/v1/fpn/activate` → `ActivateGuardian`.
- **طبقه‌بندی خطای امروز** (guardian.go `fetchProxyPass`):
  - 429 → `ErrQuotaExceeded`؛ 401/403 → `ErrTokenInvalid`؛ سایر non-200 (شامل **451**) → `GuardianHTTPError{Operation, StatusCode, Body}`.
  - Engine (`cmd/libfirefoxvpn/main.go` `classifyGuardian`): `GuardianHTTPError` → `fferr.ClassifyHTTP` → 451 در bucket عمومی 4xx می‌افتد = `CodeServerRejection` (غیرقابل retry) + `HTTPStatus=451` به Dart می‌رسد.
  - **Dart** (`firefox_errors.dart`): failCode=`serverRejection` + `httpStatus=451` → قابل تشخیص از طریق httpStatus اما **کد اختصاصی 451/region وجود ندارد** → شکاف Stage 1.
- **تجدید**: `internal/upstream/controller.go` `runRenewalLoop` → `renew()` → `FetchProxyPass` (+ `FxaRefreshToken` روی ErrTokenInvalid با توکن تازه به Dart از طریق `OnAuthRefresh`) — همه از همان seam ترنسپورت عبور می‌کنند؛ یعنی تزریق proxy یکجا، اولیه و renewal را پوشش می‌دهد.
- **FirefoxEngineConfig امروزی** (`firefox_protocol.dart:43-51`): `socksListen/auth/guardian/country/transport/upstreamOverride/logLevel` — **هیچ فیلد proxy کنترل-پلن ندارد**. نقطه ادغام Stage 5: فیلد جدید stdin-JSON (مثل `apiProxy`) → `main.go` → ساخت transport مطابق `configureAPIProxy` در proxy-demo (مرجع دقیق upstream؛ http/https/socks5/socks5h) → `SetControlPlaneTransport`. توکن‌ها همین حالا فقط از stdin می‌روند؛ proxy URL هم حساس نیست اما باملاحظه در log نویسه شود.

### ۲. معماری فعلی Psiphon

- **موتور**: باینری خارجی `libpsiphon.so` (= psiphon-tunnel-core بازنام‌گذاری‌شده؛ pin CI: `CluvexStudio/psiphon-tunnel-core` @ `2956a96b56fe09b99e72a8eb4bed3e79d29e3543`) به‌عنوان **child process** توسط هسته Rust درون‌فرایندی Aether (`libaether.so`؛ pin CI: `CluvexStudio/Aether` @ `d58f9d568083129ce2c767c85054021eb3ee6a38` v2.4.0) spawn و supervise می‌شود (`aether/src/psiphon.rs` در pin، ۱۵۱۷ خط — تأیید مستقیم سورس).
| مدیر Bootstrap مستقل Psiphon (Stage 2) | `lib/connection/firefox/psiphon_bootstrap.dart` (PsiphonBootstrapProxy + SocksTlsReadyProbe + buildArgs) + `test/psiphon_bootstrap_test.dart` |
- **سازوکار راه‌اندازی** (psiphon.rs `start`): هسته config JSON می‌سازد (`aether-psiphon.json`، مجوز 0600) با کلیدهای: `LocalSocksProxyPort`، `LocalHttpProxyPort`+`DisableLocalHTTPProxy=false` (فقط با `--psiphon-http`)، `UpstreamProxyURL` (زنجیر/`--upstream`)، `EgressRegion` (`--psiphon-region`)؛ باینری با `client_arguments` اجرا می‌شود؛ stdin=null، **notices از stderr** خط‌به‌خط JSON.
- **آمادگی (دقیقاً مطابق الزام Stage 2 مأموریت)**: notice `ListeningSocksProxyPort` (و `ListeningHttpProxyPort` اگر http) + notice `Tunnels` با `count>0` → آماده = «تونل برقرار + پورت شنیده»؛ سپس listenerهای core (نگه‌داشته از ابتدا) به پورت‌های واقعی psiphon relay می‌شوند (`relay_to`). مهلت: `AETHER_PSIPHON_READY_SECS` (پیش‌فرض 180).
- **Notices دیگر**: `ConnectedServer` (ipAddress)، `AvailableEgressRegions`، `ConnectingServer/ActiveTunnel/Homepage` (debug)، `Warning/Alert/Error/InternalError` (با فیلتر expected_without_inproxy). از دست رفتن تونل: `Tunnels.count=0` بعد از برقراری → warn «lost its tunnel; reconnecting».
- **Data Directory**: `--psiphon-dir` → AETHONE پاس می‌دهد `$filesDir/aether/psiphon` (پایدار بین اجراها — الزام مأموریت برآورده).
- **Adaptive Connection**: کاملاً داخلی psiphon-tunnel-core (انتخاب سرور/پروتکل/tactics) — هسته فقط `--psiphon-mode auto` (پیش‌فرض) را پاس می‌دهد؛ محدودسازی نکردن آن رعایت شده.
- **Lifecycle**: `Running{child, socks, http}`؛ `kill_on_drop(true)` + `Drop` → `start_kill` — توقف با کشتن core job (FFI cancel) یا پایان پروسه. Restart = start مجدد.
- **توقف/خاموشی**: چون child با kill_on_drop است، لغو job هسته psiphon را هم می‌کشد — بدون پردازه یتیم.

### ۳. حالت‌های Combination موجود (کشف‌شده از سورس — evidence-locked)

- **موتور «Mask» در AETHONE وجود ندارد** (جستجوی کامل lib/ و android/ و docs؛ تنها «mask»ها فلترهای UI هستند). معادل واقعی الگوی «Mask → Psiphon» مأموریت = ترکیب‌های Aether/Psiphon زیر:
  - `PSIPHON ONLY` (`--psiphon-only`): بدون تونل زیرین؛ listener `--bind` (1819) psiphon ساده serve می‌کند (psiphon.rs `run_only`؛ USAGE L264) — معادل «Psiphon Standalone Adaptive» مأموریت.
  - `AETHER → PSIPHON` (`--psiphon` chain): تونل WARP هسته (MASQUE/WireGuard/GOOL/MIM) اول؛ بعد psiphon با `UpstreamProxyURL=socks5://<تونل>` روی آن (psiphon.rs `run_chain` L940: `Some(format!("socks5://{through}"))`) — listener دوم `--psiphon-bind` (1821) = egress. **این دقیقاً همان الگوی «مسیر اول + Psiphon روی آن» است.**
  - `PSIPHON → AETHER` (`--psiphon-reverse`): psiphon اول؛ تونل WARP از داخل آن (listener `--bind` 1819؛ محدودیت carrier: MASQUE/GOOL/MIM مجاز، WireGuard/GOOL-Classic fail-closed رد می‌شود — lib.rs L229-244).
  - خانواده Tor معادل‌ها: `torChain/torReverse/torOnly` (1820) — برای Bootstrap ملاک نیستند (Tor به‌عنوان upstream پشتیبانی‌شده در pin تعریف نشده؛ دست نسازیم).
- **پیاده‌سازی زنجیر = UpstreamProxyURL** (نه VpnService، نه TUN): تونل WARP هسته یک SOCKS محلی است؛ psiphon از طریق آن dial می‌زند. یعنی زنجیر **بدون هیچ VpnService** قابل اجراست.
- **TUN/zeptun فقط برای ترافیک دستگاه است**: walk اداپتر (permission → TUN → engine → listener) جدا از پروسه هسته اجرا می‌شود؛ هسته Rust درون‌فرایندی از طریق FFI (`aether_core_start(args_json)` — آرایه JSON از CLI strings؛ `aether_job_poll/cancel/free`) راه می‌افتد. **نتیجه معماری برای Bootstrap: می‌توان هسته را در حالت psiphon-only/chain بدون VpnService و بدون TUN اجرا کرد و فقط Proxy محلی آن را خواند.**
- **Port map (قفل‌شده)**: 1819 = `--bind` aether (هم SOCKS هسته در حالت عادی/only)؛ 1820 = `--tor-bind`؛ 1821 = `--psiphon-bind` (chain)؛ 1822 = SOCKS موتور Firefox. برای Bootstrap باید پورت(های) جدید یا پورت‌های موقت 0 (core پورت آزاد می‌گیرد و از طریق `local_addr` اعلام می‌کند) استفاده شود تا تداخلی با حالت‌های متصل کاربر نباشد.
- **جلوگیری از Route Loop (موجود و کافی)**: TUN با `addDisallowedApplication(packageName)` کل uid اپ را مستثنا می‌کند + protect() برای سوکت‌های zeptun. موتورها (aether/psiphon/firefox) همه زیر uid اپ اجرا می‌شوند → سوکت‌هایشان هرگز به TUN برنمی‌گردند. در Bootstrap بدون TUN اصلاً مسیری تغییر نمی‌کند.

### ۴. محدودیت Android VpnService

- فقط یک VpnService per user — AETHONE از ابتدا یک `AethoneVpnService` واحد برای همه حالت‌ها دارد. **Bootstrap نیازی به VpnService ندارد** (فقط هسته درون‌فرایندی + child psiphon + proxy محلی). هیچ VpnService موازی ساخته نشود.

### ۵. مرجع Arman (رفتاری — نه کپی)

- `ErrRegionUnavailable` = سنتیل اختصاصی 451؛ `SetRegionRecovery(retry func)` = seam بازگشتی **فقط بعد از 451** (پاسخ 451 اصلی در شکست retry حفظ می‌شود).
- **ترفند doubled-leading-slash**: لبه CDN موزیلا مسیر literal را قبل از رسیدن به Guardian رد می‌کند؛ یک `/` اضافه در ابتدای path از قاعده edge عبور می‌کند و origin همان handler را route می‌کند — Arman این را **قبل از relay** امتحان می‌کند (`doubledPathRequest`). برای AETHONE هم کاندیدای بررسی در Stage 1/5 است (نکته: در مسیر مستقیم uTLS).
- `relayFallback` transport: مستقیم اول، relay در شکست — الگوی «مستقیم در اولویت» مأموریت.
- Arman از relay خارجی استفاده می‌کند؛ AETHONE طبق مأموریت از Psiphon داخلی.

### ۶. شکاف‌های شناسایی‌شده (ورودی مراحل بعد)

1. **Stage 1**: کد خطای اختصاصی 451/region در fferr وجود ندارد (امروز `serverRejection`+httpStatus)؛ bootstrap فقط برای endpointهای Guardian و خطای معتبر منطقه‌ای باید فعال شود — نیاز به classification مستقل + تست.
2. **Stage 2**: اجرای هسته در حالت `--psiphon-only` بدون VpnService/TUN از Dart (FFI `aether_core_start` با args مناسب + `--psiphon-http` برای HTTP CONNECT + پورت‌های موقت) — ادغام با walk موجود لازم نیست؛ یک مسیر سبک مستقل لازم است. Probe واقعی آمادگی (تست TLS/DNS از همان proxy) اضافه شود.
3. **Stage 3**: زنجیر `AETHER → PSIPHON` بدون TUN (hmm: run_chain صبر می‌کند تونل WARP بالا بیاید — هسته باید در حالت chain اجرا شود؛ `wait_for_proxy(through)`؛ سپس psiphon روی آن) — بررسی شود آیا core در chain mode بدون TUN دستگاه کار می‌کند (باید بکند؛ تونل WARP خودش سوکت‌های عادی است).
4. **Stage 5**: فیلد `apiProxy` در FirefoxEngineConfig + پیاده‌سازی `configureAPIProxy` در `cmd/libfirefoxvpn/main.go` (الگوی proxy-demo) + فعال‌سازی فقط پس از 451 (تصمیم مسیر در Dart یا engine؟ — طراحی در Stage 4/5؛ اولویت: درخواست مستقیم).
5. توجه: `FirefoxEngineConfig.guardian` فعلاً فقط endpoint base است؛ endpointهای مجاز bootstrap باید همان `/api/v1/fpn/*` روی همان host باشند.

### ۷. NOT TESTED (Stage 0)

- رفتار واقعی شبکه ایران/Guardian روی دستگاه — لاگ 451 از گوشی در دسترس نیست.
- اجرای واقعی psiphon-only/chain بدون TUN روی دستگاه (تحلیل سورس؛ اجرا در Stage 2/3).
- نسخه دقیق psiphon-tunnel-core fork (فقط SHA pin از CI استخراج شد؛ CHANGELOG بررسی نشد).

---

## یافته‌ها و تغییرات Stage 1 (اجرای 2026-11-10)

### ۱. شواهد خام 451

- بدنه واقعی پاسخ 451 Guardian روی سیم: `{"error":"unavailable_in_region"}` — کد ساختاریافته در فیلد `error` (گواه میدانی؛ در متن مأموریت مالک نیز همین قالب آمده).
- مرجع Arman (`core/internal/guardian/errors.go` + `region_recovery.go`): `ErrRegionUnavailable` فقط با **status code** 451 در نوع `HTTPError` محدود به Guardian ساخته می‌شود؛ `SetRegionRecovery` فقط بعد از 451 (و بعد از ترفند مستقیم doubled-leading-slash) فعال می‌شود و پاسخ 451 اصلی در شکست recovery حفظ می‌شود — الگوی رفتاری دقیق Stage 5.
- upstream pin خودش برای 451 رفتار خاصی ندارد (می‌افتد در `GuardianHTTPError` عمومی).

### ۲. طراحی طبقه‌بندی (پیاده‌سازی‌شده — commit `2c04f5a`)

- کد جدید: `fferr.CodeGuardianRegionUnavailable` = `guardianRegionUnavailable` (پیام static؛ non-retryable؛ httpStatus=451 پاس می‌شود).
- تابع جدید `fferr.ClassifyGuardian(status, body)`:
  - 451 + تأیید بدنه → کد اختصاصی. تأیید = parse JSON بدنه (فیلدهای `error`/`code`)؛ کد ساختاریافته == `unavailable_in_region` → تأیید؛ بدنه خالی/غیرJSON/بدون کد → خود status کافی است (قاعده status-only مرجع Arman؛ لبه CDN صفحه HTML می‌دهد)؛ کد ساختاریافته دیگری غیرخالی → دلیل صریح دیگر → `serverRejection` عمومی می‌ماند.
  - سایر statusها → `ClassifyHTTP` بدون تغییر (401/403 → sessionRejected؛ 4xx → serverRejection؛ 5xx → serverRejection retryable).
- **جداسازی endpoint (اصل مأموریت)**: `ClassifyHTTP` دست نخورده — مسیر FxA (`classifyLoginError`) و Remote Settings (`FetchServerList` → `ClassifyTransport`) برای 451 همان کلاس عمومی را می‌گیرند. فقط `classifyGuardian` در `cmd/libfirefoxvpn/main.go` — که `GuardianHTTPError` می‌گیرد؛ نوعی که pin فقط در walkهای `/api/v1/fpn/*` می‌سازد — به `ClassifyGuardian` وصل است. تست `TestClassifyHTTP451StaysGeneric` این جداسازی را قفل کرده است.
- **مسیر renewal**: `OnRenewalFail` امضای جدید `(redacted, failCode, retryInMs)` + تابع `renewalFailCode` (همان سیاست classifyGuardian برای خطای تجدید)؛ رویداد `renewalFailed` حالا `failCode` هم دارد (additive؛ engine قدیمی بدون فیلد هم parse می‌شود — تست Dart).
- **انتقال تا Flutter**: failCode=`guardianRegionUnavailable` → `FirefoxTransportError.guardianRegionUnavailable` (classify/diagnostic/mirror در firefox_errors/firefox_protocol) → متن fa/en/ru/zh/tk (`firefoxErrGuardianRegion`) از طریق `AppStrings.firefoxErrorText`. httpStatus=451 و retryable=false حفظ می‌شوند؛ زنجیره raw و کد بدنه هرگز به سطح UI نمی‌رسد.

### ۳. Endpointهای واقعی Guardian (استخراج از سورس pin)

| عملیات | متد+مسیر | فراخوان زنده در موتور |
|---|---|---|
| FetchProxyPass (Authorization اولیه + Renewal) | `GET /api/v1/fpn/token` | بله — `AcquireInitialPass` + `renew` (هر دو از seam ترنسپورت مشترک) |
| FetchUserInfo (Entitlement) | `GET /api/v1/fpn/status` | خیر (فقط API کتابخانه) |
| ActivateGuardian | `POST /api/v1/fpn/activate` | خیر (فقط API کتابخانه) |

همه روی host پایه `FirefoxEngineConfig.guardian` (پیش‌فرض `https://vpn.mozilla.org`؛ validation فقط HTTPS). هیچ Host/Path حدس زده نشد.

### ۴. دامنه اثر Transport مشترک (بخش ۳ دستور مکمل — فقط مستند، بدون تغییر کد)

- `SetControlPlaneTransport(rt)` کل `controlPlaneHTTPClient` پروسه را عوض می‌کند: FxA + Guardian + Remote Settings با هم، cookie jar مشترک (چالش Fastly) و timeout مشترک؛ باید قبل از اولین درخواست control-plane صدا شود.
- **در این مرحله هیچ پراکسی/ترنسپورتی متصل نشد و معماری تغییر نکرد.**
- امکان‌سنجی Routing RoundTripper برای Stage 5 (مستند، مثبت): RT دوپایه — پایه پیش‌فرض direct = `NewControlPlaneTransport()` (uTLS Firefox hello)؛ پایه bootstrap = transport با Dial از پراکسی محلی Psiphon (socks5/http). شرط مسیر: `req.URL.Host` == host پایه guardian از config (allowlist روی **host** نه path تا با ترفند doubled-slash تداخل نکند). نصب یکباره با `SetControlPlaneTransport` قبل از اولین درخواست. cookie jar مشترک بین دو پایه per-host است → بی‌خطر. TLS/verification هر دو پایه فعال می‌ماند (CONNECT tunnel، بدون MITM).
- نکته Arman برای Stage 5: ترفند doubled-leading-slash (لبه CDN مسیر literal را قبل از Guardian رد می‌کند؛ یک `/` اضافه از قاعده edge عبور می‌کند و origin همان handler را route می‌کند) باید **قبل از** فعال‌سازی مسیر bootstrap امتحان شود؛ در AETHONE یا داخل RT یا قبل از FetchProxyPass قابل اعمال است.

### ۵. نگاشت پورت‌ها (بخش ۴ دستور مکمل — رفع ابهام 1821؛ فقط مستند)

تأیید مستقیم از سورس pin شده Aether (`d58f9d56`؛ `psiphon.rs` + `lib.rs`):

| پورت | مالک واقعی | نقش |
|---|---|---|
| 1819 | هسته aether (`--bind`/AETHER_SOCKS؛ پیش‌فرض lib.rs L105-108) | SOCKS تونل WARP؛ در حالتهای ONLY به tor/psiphon relay می‌شود |
| 1820 | هسته aether (`--tor-bind`) | egress زنجیر aether→tor |
| **1821** | **هسته aether** (`--psiphon-bind`؛ پیش‌فرض psiphon.rs L11) | **relay خروجی زنجیر aether→psiphon — متعلق به پروسه psiphon نیست**؛ هسته از ابتدا نگهش می‌دارد (lib.rs L847-848) و با `relay_to` به SOCKS واقعی psiphon وصل می‌کند |
| (ephemeral) | پروسه child psiphon | `LocalSocksProxyPort` پورت 0 → سیستم انتخاب می‌کند؛ با notice `ListeningSocksProxyPort` اعلام؛ این «listener واقعی Psiphon» است |
| 1822 | پروسه libfirefoxvpn | SOCKS موتور Firefox |

- در زنجیر AETHER→PSIPHON: psiphon با `UpstreamProxyURL=socks5://127.0.0.1:1819` dial می‌زند (`through` = listener اصلی هسته؛ lib.rs L169 + L194-198: `run_chain(through=held)`)؛ یعنی **upstream واقعی Aether برای psiphon همان تونل WARP روی 1819 است** و خروجی کاربر 1821 است.
- **Self-reference / Route Loop: خیر** — سه آدرس متمایزند (upstream تونل 1819 ≠ relay خروجی 1821 ≠ listener واقعی ephemeral psiphon)؛ psiphon هرگز به خروجی خودش dial نمی‌زند؛ برخورد 1821=1819 عملاً غیرممکن است (هسته هر دو را از ابتدا bind می‌کند → bind دوم fail-closed). TUN دستگاه کل uid اپ را با `addDisallowedApplication` مستثنا می‌کند.
- **نتیجه برای Stage 2**: هسته bootstrap در حالت `--psiphon-only` با `--bind 127.0.0.1:0` اجرا شود (پورت مؤثر از status/local_addr خوانده شود — الگوی موجود `status['port']` در platform_engine_adapter L2849) تا با 1819/1820/1821/1822 حالتهای متصل کاربر هیچ تداخلی نباشد.

### ۶. فایلهای تغییرکرده (Stage 1 — commit `2c04f5a`)

- Go (`phase1/fxv`): `internal/fferr/classify.go` (کد/تابع/تأیید بدنه)، `internal/fferr/classify_test.go` (+۲ تست)، `cmd/libfirefoxvpn/main.go` (classifyGuardian → ClassifyGuardian + سیم‌کشی failCode تجدید)، `cmd/libfirefoxvpn/main_test.go` (+۲ تست و imports)، `internal/upstream/controller.go` (امضای OnRenewalFail + renewalFailCode + import fferr)، `internal/upstream/renewal_classify_test.go` (جدید)، `internal/engine/contract.go` (کامنت فیلد FailCode).
- Dart: `lib/connection/firefox/firefox_errors.dart`، `lib/connection/firefox/firefox_protocol.dart`، `lib/l10n/app_strings.dart` (۵ زبان)، `test/firefox_errors_test.dart` (+گروه Stage 1).
- دست‌نخورده: pinهای upstream (firefox `55ad91a2…`، Aether `d58f9d56…`، psiphon fork `2956a96b…`)، CGO/A1 و `phase1/scripts/build_engine.sh`، `phase1/firefox-vpn-client` (pin — فقط مرجع)، `android/`، workflowها، Data Plane.

### ۷. تستها و نتایج واقعی (Stage 1)

- `go vet ./...` → PASS (صفر یافته).
- `go test ./...` → هر ۷ پکیج ok. تستهای جدید: `TestClassifyGuardianStatus` (۱۲ حالت)، `TestClassifyHTTP451StaysGeneric` (جداسازی endpoint)، `TestClassifyGuardianMatrix` (۱۱ حالت + عدم نشت secret)، `TestGuardian451ThroughRealUpstreamClient` (زنجیره واقعی: دابل TLS محلی Guardian → vpnclient pin شده → classifyGuardian؛ فقط داخل تست ترنسپورت test-only با cert محلی — مسیر production دست‌نخورده)، `TestRenewalFailCode` (۸ حالت).
- `go test -race` روی ۴ پکیج تغییرکرده → PASS.
- تستهای موجود همه سبز؛ هیچ تستی حذف یا غیرفعال نشد.
- Dart (analyze + test): sandbox بدون Flutter SDK → اجرا در CI (`native-ci` run `42784595977` روی همین شاخه/`2c04f5a`، job `flutter-ui`): **PASS — run `42784595977`، job `129722568214` (2m16s): flutter analyze (warnings fatal) + flutter test + گیت SOCKS handshake contract همه سبز؛ شامل گروه جدید تست Stage 1 در test/firefox_errors_test.dart**

### ۸. NOT TESTED (Stage 1)

- 451 واقعی Guardian از شبکه ایران روی دستگاه (نیاز به گوشی مالک؛ Stage 9 سناریو B/C).
- قالب بدنه واقعی لبه CDN موزیلا برای 451 (فقط روی دستگاه قابل مشاهده؛ طراحی status-only fallback همین عدم قطعیت را پوشش می‌دهد).
- اجرای مستقیم تستهای Dart در sandbox (نبود Flutter SDK) — پوشش با CI در بالا.
- probe واقعی پراکسی محلی Psiphon (موضوع Stage 2 است).

---



## یافته‌ها و تغییرات Stage 2 (اجرای 2026-11-10)

### ۱. تصمیم معماری پورت — اصل «بدون Parse کردن Log» برقرار شد

- **بررسی مستقیم ffi.rs در pin** (کل فایل خوانده شد): سطح FFI فقط `aether_core_start/job_poll/job_cancel/job_free` (+ identity/team) دارد؛ `job_poll` فقط `running`/`done` برمی‌گرداند. **هیچ API رویدادی یا پرس‌وجوی local_addr وجود ندارد.**
- `--bind 127.0.0.1:0` در هسته **پشتیبانی می‌شود** (psiphon.rs `run_only` L921-922: `listener.local_addr()`) اما پورت مؤثر فقط در لاگ هسته اعلام می‌شود؛ خواندن آن از لاگ توسط مأموریت ممنوع است.
- **راه‌حل پیاده‌سازی‌شده (Dart pre-bind)**: `PsiphonBootstrapProxy.pickFreeLoopbackPort()` — bind روی `127.0.0.1:0` در Dart، خواندن پورت انتخابی OS، آزادسازی سوکت، و پاس‌دادن آدرس **مشخص** `--bind 127.0.0.1:<port>` به هسته. پورت «با ساخت» شناخته می‌شود (هرگز از لاگ parse نمی‌شود)، هر بار تصادفی است، و هیچ‌وقت در بازه 1819/1820/1821/1822 نیست (بازه ephemeral لینوکس/اندروید از 32768 شروع می‌شود + گارد `kPinnedAethonePorts` در کد).
- **Fail-closed**: اگر پورت در پنجره release→bind توسط فرایند دیگری گرفته شود، `socks::bind_listener` هسته با متن منجمد «the socks5 listener cannot use …» خارج می‌شود، job می‌میرد و Manager تا ۳ بار با پورت تازه retry می‌کند (تست‌دار).

### ۲. آمادگی چندشاهدی (الزام ۲-۶ مأموریت)

زنجیره علّی از سورس pin شده: هسته listener مربوط به `--bind` را از همان ابتدا نگه می‌دارد اما **فقط بعد از** دیدن noticeهای `ListeningSocksProxyPort` و `Tunnels.count>0` (درون psiphon.rs `start()`) آن را با `relay_to` به SOCKS داخلی psiphon وصل می‌کند. بنابراین از دید Dart:

1. **job زنده** (poll مثل walk اتصال) — `_pollCoreOnce`.
2. **SOCKS5 greeting کامل + CONNECT با ATYP=domain** از طریق همان listener — عبور موفق فقط بعد از بالاآمدن relay ممکن است؛ یعنی اثبات عبری: تونل psiphon برقرار است (`Tunnels>0`) و listener داخلی psiphon زنده است.
3. **DNS از مسیر Proxy** — نام دامنه در CONNECT توسط psiphon resolve می‌شود (SOCKS5h عملاً)؛ هیچ DNS محلی در کار نیست.
4. **TLS از مسیر Proxy** — `SecureSocket.secure` با verification کامل (بدون `onBadCertificate`) + HTTP trace با status 2xx/3xx.

پروب تولیدی: `SocksTlsReadyProbe` (SOCKS5 → CONNECT → TLS → trace؛ همان `TunnelProbe.socksConnect` مشترک با walk اتصال + ارتقای TLS). باز شدن پورت به‌تنهایی هرگز Ready نیست — تست «an open port that never speaks SOCKS5 is NOT ready» این را قفل کرده است.

### ۳. یافته جانبی مهم — باگ latent در مسیر Onionoo (egress_locations)

- `SocksTunnel.detach()` (tunnel_probe.dart) subscription فعال StreamIterator را **cancel** می‌کند؛ در dart:io این کار **سمت خواندن سوکت را می‌بندد** (نوشتن زنده می‌ماند — با آزمون‌های تجربی جداگانه اثبات شد: cancel→write OK، اما `SecureSocket.secure` بعد از detach بلافاصله EOF می‌گیرد و با «Connection terminated during handshake» می‌میرد؛ ClientHello هرگز ارسال نمی‌شود).
- راه درست (در این مرحله اعمال شد): `SecureSocket.secure(tunnel.socket, …)` **بدون cancel** — subscription در حالت paused به لایه TLS سپرده می‌شود (`_detachRaw` خودش آن را adopt می‌کند). با این تغییر، پروب کامل LIVE (SOCKS5 → CONNECT → TLS واقعی → `HTTP/1.1 200 OK` از www.cloudflare.com از طریق relay آزمایشی) سبز شد.
- **اثر در کد موجود**: `_resolveViaOnionoo` در egress_locations.dart همین الگوی معیوب detach→secure را دارد → خطای آن silent catch می‌شود و همیشه به fallback یعنی ip-api (HTTP ساده) می‌رسد. **در این مرحله عمداً دست نخورد** (انضباط محدوده Stage 2)؛ برای مالک ثبت شد — اصلاح آن یک commit مستقل خارج از این مأموریت/در مرحله بعدی با تأیید مالک باشد.

### ۴. فایلهای تغییرکرده (Stage 2)

- **جدید**: `lib/connection/firefox/psiphon_bootstrap.dart` — مدیر `PsiphonBootstrapProxy` (تک‌نمونه‌ای/singleflight؛ start/stop/restart/healthCheck/dispose؛ جریان رخدادهای typed؛ `endpoint.socksUrl`) + پروب تولیدی `SocksTlsReadyProbe` + ساخت arg مخصوص bootstrap (`buildArgs` — فقط `--psiphon-only/--bind/--psiphon-bin/--psiphon-dir/--log-level`) + بهداشت محیط `AETHER_*` قبل از هر start (همان نظم walk اتصال).
- **جدید**: `test/psiphon_bootstrap_test.dart` — ۲۱ تست.
- **دست‌نخورده**: بقیه مخزن (گواهی: `git status` فقط همین دو فایل جدید). pinها، Go، CGO/A1، workflowها، Data Plane — بدون تغییر.

### ۵. قرارداد سطح Stage 2 (ورودی Stage 4/5)

- `PsiphonProxyEndpoint.socksUrl` = `socks5://127.0.0.1:<ephemeral>` — همان چیزی که RoutingRoundTripper مرحله ۵ dial خواهد کرد.
- کدهای خطا (پایدار): `libraryMissing`, `coreStartFailed`, `portConflict`, `coreExited`, `notReady`, `cancelled`, `disposed`؛ رخداد مرگ حین ready: `coreDied`/`listenerDead` (با متن خطای خود هسته).
- **قید مستند برای Stage 4**: محیطِ process بین bootstrap و walk اتصال کاربر مشترک است (بهرست `AETHER_*` هر دو را پاک می‌کند) — انحصار «bootstrap هنگام walk کاربر شروع نشود» مال Stage 4 است. جریان Guardian (موتور Firefox = فرایند child) اصلاً job هسته aether ندارد.
- Data Directory پایدار و اختصاصی: `$filesDir/aether/psiphon-bootstrap` (جدا از `…/aether/psiphon` حالتهای کاربر — دو child psiphon روی یک DataRootDirectory ناامن است) — بین restartها حفظ می‌شود.

### ۶. تستها و نتایج واقعی (Stage 2)

- `flutter analyze` → **صفر یافته** (sandbox با همان Flutter pin شده CI: 3.47.9 / Dart 3.13.7).
- `flutter test` کل مخزن → **331 پاس، 8 skip قبلی (بدون تغییر)، 0 شکست**؛ فایل جدید: ۲۱ تست شامل:
  - قرارداد سورس (نبود MethodChannel/VpnService/TUN در مدیر — با تست قراردادی روی سورس).
  - args منطبق pin (فقط psiphon-only؛ بدون upstream/chain-listener/region/protocol-pin/config/scan).
  - تخصیص پورت ephemeral (خارج نقشه pin؛ واقعاً آزاد).
  - «پورت باز ≠ Ready» با listener واقعی خاموش.
  - **LIVE**: handshake کامل واقعی (SOCKS5 → CONNECT دامنه‌ای → TLS verify شده → `HTTP/1.1 200 OK`) از طریق relay آزمایشی به www.cloudflare.com — در همین اجرا واقعاً اجرا شد و سبز شد (skip صادقانه فقط در محیط آفلاین).
  - lifecycle: singleflight (یک job برای چند start همزمان)، retry تعارض پورت، خطای verbatim هسته (coreExited)، exit تمیز، timeout + پاکسازی cancel/free، stop حین start (cancelled، بدون failed)، stop idempotent، restart (پورت تازه + DataDir ثابت)، مرگ هسته حین ready (health ticker → failed)، healthCheck صادق، dispose (بستن stream + inert بودن callbackها).
- Go: هیچ فایل Go تغییر نکرد (اثبات با git status) — CI (`native-ci`) تأیید نهایی را انجام می‌دهد.

### ۷. NOT TESTED (Stage 2)

- اجرای واقعی روی گوشی با `libaether.so`/`libpsiphon.so` واقعی و شبکه ایران (Stage 9 سناریو B) — در sandbox باینری Android هست.
- متن خطای تعارض bind از هسته واقعی روی دستگاه (مطابق سورس pin منجمد فرض شد؛ evidence-locked string match مثل harvest قبلی).
- انحصار هم‌زمانی bootstrap ↔ walk کاربر (تحویل به Stage 4).
- رفتار `AETHER_PSIPHON_READY_SECS` روی دستگاه (پیش‌فرض 180s هسته ملاک است؛ بودجه Dart 210s).

### ۸. راستی‌آزمایی مستقل Stage 2 (اجرای verification — 2026-11-10)

- دستور جاریِ این اجرا صریح بود: «اگر مرحله دوم قبلاً کامل شده است، آن را از ابتدا اجرا یا بازنویسی نکن؛ شواهد و تست‌های موجود را بررسی و نتیجه واقعی را ثبت کن.» — دقیقاً همین انجام شد: **هیچ کد Stage 2 بازنویسی یا دوباره تولید نشد؛ فقط راستی‌آزمایی و ثبت نتیجه.**
- وضعیت Git در شروع این اجرا: HEAD = `e28e93b` (= commit مستندات Stage 2)، working tree پاک، و `ls-remote` تأیید کرد tip ریموتِ `feature/firefox-guardian-psiphon-bootstrap` دقیقاً همان `e28e93b` است — یعنی کد و مستندات Stage 2 از قبل کاملاً push شده بودند.
- شواهد Stage 0/1 بازتأیید شد: commitهای `8a54a1b` / `0e0126e` / `2c04f5a` / `caac298` در تاریخچه همین شاخه حاضرند و `guardianRegionUnavailable` هنوز زنده است (`phase1/fxv/internal/fferr/classify.go`، `cmd/libfirefoxvpn/main.go`، `internal/upstream/controller.go` + سه فایل Dart/l10n و تستهای مربوط).
- `git show --stat b88b423`: دقیقاً دو فایل **جدید** (`lib/connection/firefox/psiphon_bootstrap.dart` و `test/psiphon_bootstrap_test.dart`)؛ هیچ فایل موجودی تغییر نکرد — قید «pinها/Go/CGO-A1/workflowها/Data Plane دست‌نخورده» برقرار است.
- `flutter analyze` در همان toolchain pin شده CI (sandbox Flutter 3.47.9 / Dart 3.13.7): **صفر یافته** — بازتولید شد.
- `flutter test` کل مخزن: **۳۳۱ پاس / ۸ skip قبلی / ۰ شکست** — عدد ثبت‌شده در §۶ دقیقاً بازتولید شد. فایل Stage 2: **۲۱/۲۱ سبز**، از جمله تست **LIVE** (SOCKS5 → CONNECT دامنه‌ای → TLS با verify کامل → trace واقعی از طریق relay) که در همین sandbox شبکه‌دار واقعاً اجرا و پاس شد (skip نشد).
- تست قرارداد سورس بازبینی مستقیم شد: کدِ بدون کامنتِ مدیر را روی نبود `MethodChannel`/`invokeMethod`/`startVpn`/`startCoreHold`/`VpnService`/`prepareVpn`/`NetworkInterface` قفل می‌کند — معتبر.
- جمع‌بندی: **Stage 2 = PASS (verified)** — هیچ نقصی در محدوده Stage 2 یافت نشد که نیاز به اصلاح داشته باشد؛ تنها خروجی آن اجرا همین ثبت راستی‌آزمایی بود.

## یافته‌ها و تغییرات Stage 3 (اجرای 2026-11-10)

### ۱. تصمیم معماری — ترکیب موجود، بازراه‌اندازی شده (نه بازسازی)

- تأکید مالک در دستور اجرا: «حالت‌های ترکیبی با سایفون از قبل وجود دارن ولازم نیست دوباره ایجادشون کنی». اجرا دقیقاً همین بود: **زنجیره AETHER → PSIPHON هیچ بخشی در Dart بازسازی نشد**؛ مدیر مرحله ۲ با یک حالت دوم (`PsiphonBootstrapMode.aetherPsiphonChain`) گسترش شد که همان حالت `--psiphon` هسته پین‌شده را با پرت‌های اختصاصی موقت راه‌اندازی می‌کند. API سطح Stage 2 حفظ شد (پیش‌فرض سازنده همان `psiphonOnly` است؛ امضای آماده قبلاًگذره تست‌ها بدون تغییر سبز ماند).
- شواهد سورس (مستقیم از `native/aether/aether/src` در pin):
  - `psiphon.rs run_chain` (L940-968): هسته listener `--psiphon-bind` را از ابتدا نگه می‌دارد، `wait_for_proxy(through)` صبر می‌کند تا SOCKS مربوط به `--bind` (تونل WARP) جواب بدهد، بعد psiphon را با `UpstreamProxyURL=socks5://<through>` روی آن اجرا می‌کند و خروجی را به listener داخلی psiphon (ephemeral انتخاب سیستم، `BEHIND_HELD=127.0.0.1:0`) relay می‌کند.
  - `psiphon.rs mode()`: هر مقدار غیرخالی/غیررزرو (از جمله «1/on/chain/yes») → `Mode::Chain`؛ فلگ CLI همان `--psiphon` ساده است.
  - `lib.rs` L222-227: dispatch حالت Chain با `through = held` (آدرس listener `--bind`)؛ `DEFAULT_BIND` زنجیره 1821 است — مدیر Bootstrap هرگز از آن استفاده نمی‌کند.
  - `socks.rs bind_listener`: هر دو listener با متن منجمد «the {kind} listener cannot use …» خطا می‌دهند (kind = «socks5» برای --bind و «psiphon socks5» برای --psiphon-bind) → تشخیص portConflict مرحله ۲ («listener cannot use») هر دو پرت را می‌پوشاند.
  - `socks.rs until_answered`: بدون ديدلاین — مرجع شکست، خود job هسته است (خطای WARP/psiphon قبل از هر timeout دات به‌صورت coreExited verbatim بالا می‌آید).

### ۲. دستور راه‌اندازی زنجیره (buildChainArgs — هم‌خانواده walk کاربر)

- مبنای مقایسه: `AetherArguments.build` در walk کاربر برای `psiphonChain`: `--bind 127.0.0.1:1819` ثابت + `--config warp.toml` + `--scan` + `--quick-reconnect` + `--protocol <leg>` + `--psiphon` + `--psiphon-bin` + `--psiphon-dir`. Bootstrap همین خانواده را با دو تفاوت هدفمند پاس می‌کند:
  1. **دو پرت ephemeral متمایز** (`pickTwoDistinctLoopbackPorts` — الگوی pre-bind مرحله ۲ دوبار؛ هرگز 1819/1820/1821/1822)؛
  2. `--psiphon-dir` = همان مسیر اختصاصی پایدار bootstrap (`$filesDir/aether/psiphon-bootstrap`) — نه مسیر حالتهای کاربر.
- `--config` پیش‌فرض همان `warp.toml` خود walk است (بازیافت identity؛ هسته identity موجود را دوباره register نمی‌کند) — با پارامتر قابل override برای Stage 4.
- نگاشت leg (`warpProtocolArgs`) کپی آگاهانه از `AetherArguments.protocolArgs(leg, psiphonChain)` است و **تست معادلهای آن را برای همه ۱۳ مقدار ProtocolId قفل کرده** — نگاشت Bootstrap هرگز از walk جدا نمی‌شود.
- غایب‌های عمدی (با دلیل pin): `--upstream` (فقط حالتهای reverse؛ run_chain خودش upstream را دقیقاً به --bind ست می‌کند — گذاشتنش فقط می‌توانست زنجیره را به خودش برگرداند)، `--psiphon-http`، `--psiphon-region`/`--psiphon-mode`/`--exit-loc` (egress تطبیقی)، `-4/-6/--dual`.

### ۳. آمادگی و جلوگیری از Route Loop

- **Probe فقط EGRESS را می‌شمارد**: مدیر فقط پرت `--psiphon-bind` را probe می‌کند و endpoint همان است؛ پرت WARP `--bind` هرگز از سمت AETHONE شماره نمی‌خورد (تست‌دار: portsSeen فقط egress). پایان موفق probe (SOCKS5 greeting + CONNECT دامنه‌ای + TLS verify شده + trace واقعی) اثبات عبیری کل زنجیره است: هسته فقط بعد از جواب `wait_for_proxy` (WARP بالا) و گزارش `ListeningSocksProxyPort` + `Tunnels>0` از سوی psiphonِ روی همان تونل، relay را سرویس می‌کند.
- **چهار پایه ضد-loop**: (۱) دو پرت متمایز by construction؛ (۲) هرگز `--upstream`؛ (۳) پاک‌سازی کامل `AETHER_*` قبل از هر start (باقیمانده `AETHER_UPSTREAM`/`AETHER_PSIPHON_BIND` جلسه قبل همان ریزش v4.21 بود)؛ (۴) سورس pin: upstream پی‌سی‌فون دقیقاً آدرس `--bind` است و relay خروجی به پرت داخلی psiphon وصل است — سه آدرس متمایز، چرخه ناممکن. `AETHER→PSIPHON→AETHER` رخ نمی‌دهد.
- بودجه: پیش‌فرض زنجیره ۳۳۰s = جمع دو فاز خود walk (listener WARP ۱۲۰s + خانواده psiphon ۲۱۰s)؛ override صریح مقدم؛ مستقل ۲۱۰s بدون تغییر.

### ۴. ارزیابی سایر Combinationها (۳-۷) — PSIPHON → AETHER

- از سورس: حالت Reverse (`start_reverse` + lib.rs L229-244) تونل WARP را از داخل psiphon می‌شمارد و خودش `AETHER_UPSTREAM` + `AETHER_MASQUE_HTTP2=1` را در env فرایند ست می‌کند؛ خروجی قابل استفاده همان listener `--bind` است. جهت مسیر با نیاز Guardian «قابل جمع» است اما: (الف) فقط روی پایه‌های TCP/masque-h2 کار می‌کند (پایه‌های UDP صریحاً رد می‌شوند)؛ (ب) متغیرهای env فرایند مشترک را دست‌کاری می‌کند (خطر هم‌زمانی با walk کاربر، شدیدتر از Chain)؛ (ج) در فهرست مسیرهای تأییدشده مأموریت نیست و اثبات «دسترسی Psiphon واقعاً نقش لازم را دارد» نیازمند آزمون روی دستگاه است. **تصمیم: در این مرحله وارد Bootstrap نشد** — فقط مستند شد. هیچ Combination فرضی ساخته نشد.

### ۵. آزمون اثبات مسیر (۳-۶) — دو نیمه صادقانه

- **نیمه سورس (هسته)**: run_chain upstream را دقیقاً به `--bind` هاردکد می‌کند و relay خروجی به پرت داخلی psiphon وصل است — بالا مستند شد.
- **نیمه Dart (تست LIVE واقعی)**: شبیه‌سازی کامل زنجیره با سوکت‌های واقعی: egress (relay خام byte-for-byte به جای `socks::forward` هسته) → psiphon-sim (SOCKS5 که هدف را از طریق SOCKS5 دیگری شماره می‌خورد — دقیقاً رفتار upstream در run_chain) → warp-sim (خروج مستقیم به اینترنت واقعی). تست LIVE پروب تولیدی را از egress اجرا کرد و سبز شد: CONNECT دامنه‌ای تا warp-sim رسید (remote-DNS سرتاسری)، هر سه hop ترافیک را دیدند (شمارنده connections)، TLS واقعی با verify کامل و `HTTP 200` از www.cloudflare.com از مسیر کل زنجیره برگشت — **بدون bypass و بدون loop در سطح Dart**. اجرای واقعی هسته روی گوشی: NOT TESTED (Stage 9 سناریو C).

### ۶. فایلهای تغییرکرده (Stage 3)

- `lib/connection/firefox/psiphon_bootstrap.dart` — گسترش مدیر: enum `PsiphonBootstrapMode`، پارامترهای `warpConfigPath`/`warpProtocol`/`scanProfile`، `buildChainArgs` + `warpProtocolArgs` + `pickTwoDistinctLoopbackPorts`، شاخه mode در `_startInner`، teardown/آزادسازی هر دو پرت (`_awaitPortFree`)، بودجه مؤثر مود-آگاه. **هیچ رفتار Stage 2 تغییر نکرد** (۲۱ تست قبلی بدون تغییر سبز).
- `test/psiphon_bootstrap_test.dart` — ۱۴ تست جدید: قرارداد args زنجیره (پرت‌های متمایز loopback، فلگ `--psiphon`، config/scan/quick-reconnect، dir اختصاصی)؛ override پارامترها؛ رد scan profile خارج از پنج مورد pin؛ ممنوعه‌ها (بدون upstream/http/region/mode/exit-loc/±4/--dual)؛ **معادلهای نگاشت leg با walk برای همه ProtocolId**؛ دو پرت متمایز؛ بودجه ۳۳۰/۲۱۰/override؛ lifecycle زنجیره (probe فقط egress، singleflight، restart با پرت تازه و dir ثابت، retry تعارض bind، coreExited verbatim، cancel تمیز حین start)؛ **LIVE مسیر کامل زنجیره** (بالا).
- دست‌نخورده: بقیه مخزن (گواهی: `git status` فقط همین دو فایل). pinها، Go، CGO/A1، workflowها، Data Plane — بدون تغییر. ابزار: Flutter 3.47.9/Dart 3.13.7 همان pin CI (sandbox پس از بازیافت، SDK دوباره از همان tag نصب شد).

### ۷. قرارداد سطح Stage 3 (ورودی Stage 4)

- `PsiphonBootstrapProxy(mode: psiphonOnly | aetherPsiphonChain, …)`: mode در ساخت ثابت است؛ Stage 4 برای هر تصمیم مسیر یک مدیر می‌سازد و ترتیب/انحصار مال اوست (همان قید مستند: bootstrap و walk کاربر هم‌زمان نشوند — env فرایند + فایل identity مشترک).
- endpoint زنجیره = `socks5://127.0.0.1:<psiphon-bind ephemeral>` — همان چیزی که RoutingRoundTripper مرحله ۵ خواهد شمرد؛ برای هر دو mode یک شکل.
- کدهای خطا و رخدادها مشترک با Stage 2 (`libraryMissing`/`coreStartFailed`/`portConflict`/`coreExited`/`notReady`/`cancelled`/`disposed`/`coreDied`/`listenerDead`).

### ۸. تستها و نتایج واقعی (Stage 3)

- `flutter analyze` → **صفر یافته**.
- فایل Bootstrap: **۳۵/۳۵ سبز** (۲۱ مرحله ۲ + ۱۴ مرحله ۳) شامل هر دو تست **LIVE** (مستقل و زنجیره) که واقعاً اجرا شدند (skip نشدند).
- `flutter test` کل مخزن: **۳۴۵ پاس / ۸ skip قبلی / ۰ شکست**. یادداشت صادقانه: در اولین اجرای full-suite پس از تغییرها، تست UI اسکرین‌شات `zz_appearance_shot_test` یک‌بار شکست خورد (flaky تحت بار/ترتیب — در اجرای ایزوله و در تکرار full-suite سبز؛ فایلهای Stage 3 هیچ سطح UI ندارند). هیچ تست قبلی حذف یا ضعیف نشد.
- Go: بدون تغییر (اثبات با git status) — CI (`native-ci`) تأیید نهایی.

### ۹. NOT TESTED (Stage 3)

- اجرای واقعی زنجیره روی گوشی با `libaether.so`/`libpsiphon.so` واقعی، WARP واقعی و شبکه ایران (Stage 9 سناریو C) — در sandbox باینری Android نیست؛ آزمون LIVE فوق فقط نیمه Dart مسیر را با اینترنت واقعی ثابت کرد.
- رفتار ثبت/بازیافت identity واقعی WARP (`warp.toml`) در اولین bootstrap زنجیره وقتی کاربر هرگز aether اجرا نکرده (ثبت identity نیاز به دسترسی API دارد).
- متن خطای تعارض bind از هسته واقعی روی دستگاه (منجمد فرض شد؛ evidence-locked).
- انحصار هم‌زمانی bootstrap ↔ walk کاربر (تحویل به Stage 4).

## یافته‌ها و تغییرات Stage 4 (اجرای 2026-11-10)

### ۱. معماری پیاده‌سازی‌شده — Firefox Guardian Bootstrap Manager

- دو فایل جدید: `lib/connection/firefox/guardian_bootstrap_manager.dart` (مدیر + ماشین وضعیت + singleflight + Fast Path/Discovery + Cancellation) و `lib/connection/firefox/bootstrap_route_memory.dart` (حافظه مسیر سطح دوم مأموریت §۷.۱). **مدیر مرحله ۲/۳ (`PsiphonBootstrapProxy`) دست‌نخورده ماند** — مدیر فقط آن را از طریق `proxyFactory` می‌سازد (تست‌ها همان fake core/probe مراحل قبل را تزریق می‌کنند).
- **پنج Seam برای Stage 5** (مأموریت: Authorization واقعی هنوز وجود ندارد — این مرحله آن را به‌صورت interface طراحی کرد تا Stage 5 بدون بازنویسی وصل شود):
  1. `GuardianDirectAttempt` — تلاش مستقیم Guardian با سه خروجی: success / regionUnavailable (فقط 451 واقعی طبق طبقه‌بندی Stage 1) / otherFailure (۴۰۱/۴۰۳/عمومی — هرگز Bootstrap نمی‌سازند).
  2. `GuardianAuthorizationVerifier` — Authorization واقعی «از مسیر پراکسی برنده»؛ مسیر فقط پس از readiness+probe+verify موفق در حافظه موفق ثبت می‌شود (الزام §۴-۴).
  3. `GuardianNetworkContextProvider` — پیش‌فرض: باکت واحد («محدودیت مستند»: اپ منبع connectivity ندارد؛ مأموریت §۷.۱ دسته‌بندی محدود را با مستندسازی مجاز دانست؛ با یک باکت، حافظه بین شبکه‌ها مشترک است اما Fast Path فقط «اولویت» را عوض می‌کند — آمادگی/Authorization همیشه دوباره تأیید می‌شوند). Stage 5+ می‌تواند دسته کلی wifi/cellular از منبع مجاز موجود وصل کند.
  4. `UserWalkGuard` — ممنوعیت شروع Bootstrap حین walk کاربر aether (env فرایند + identity مشترک — قید مراحل ۲/۳؛ قبل از هر start چک می‌شود، خطای `walkActive`).
  5. `proxyFactory` — ساخت مدیر پراکسی بر اساس mode.

### ۲. ماشین وضعیت (§۴-۶) و نگاشت صادقانه

- حالتها: idle / directRequest / guardian451 / bootstrapSelecting / psiphonDirectStarting / psiphonDirectReady / **combinedStarting / combinedReady** / guardianAuthorizing / authorized / failed / stopping / stopped.
- دو حالت AETHER_UPSTREAM_STARTING و COMBINED_PSIPHON_STARTING مأموریت عمداً یکی شدند (combinedStarting): هسته pin کل زنجیره را «یک job FFI» اجرا می‌کند و مرز قابل‌مشاهده Dart بین پای WARP و فرزند psiphon وجود ندارد (جدا کردن آنها فقط با parse لاگ ممکن بود که ممنوع است). مدل سطح اپ (`VpnState` در connection_state.dart) دست‌نخورده — نگاشت به آن در ادغام Stage 5.
- رخدادها typed (`GuardianBootstrapEvent`) — بدون parse لاگ.

### ۳. حافظه مسیر (سطح دوم) — قواعد §۷.۱

- فایل JSON نسخه‌دار (`$filesDir/guardian-bootstrap/route-memory.json`)، نوشتن اتمی (tmp+rename)، بارگذاری tolerant (خرابی/نبود → خالی — هرگز crash یا مانع Direct؛ تست‌دار).
- رکورد هر Network Context: مسیر آخرین موفقیت کامل، طبقه‌بندی آخرین Direct (ok/451/other + زمان)، و به‌ازای هر مسیر: شمارنده‌ها، زمانهای جداگانه آماده‌سازی/Authorization، آخرین شکست با تفکیک start/authorization و cooldownUntil.
- **Schema بدون فیلد راز**: تست، کلیدهای فایل را با مجموعه ممنوعه دقیق (token/session/ssid/bssid/ip/…) و مجموعه مجاز دقیق فیلدهای stats قفل می‌کند.
- TTL پیش‌فرض ۲۴h و Cooldown پیش‌فرض ۱۰min (ثابتهای سیاستی مستند؛ قابل تزریق). TTL منقضی → Discovery؛ موفقیت تازه Cooldown را پاک می‌کند.
- ترتیب Discovery (§۴-۳، عمداً ساده/تست‌پذیر — بدون مدل ضرایب): مسیرهای بدون Cooldown مقدم؛ میان آنها «آخرین موفقیت اخیرتر اول» (تازگی = وزن‌دهی)؛ بدون سابقه → نردبان پیش‌فرض مأموریت (Standalone سپس Chain)؛ Cooldownدار آخر (جرم محدود، نه لیست سیاه).
- Fast Path (§۴-۲): فقط وقتی «مسیر Bootstrap ذخیرهشده معتبر (TTL/بدون Cooldown)» + «شاهد 451 واقعی اخیر در همین Context» → پرش از Direct. هرگز کورکورانه نیست: آمادگی واقعی (probe چندشاهدی مراحل ۲/۳) و Authorization دوباره اجرا می‌شوند (تست: پس از restart، Direct صفر بار و verify دوباره صدا زده شد).

### ۴. مدیریت درخواست، شکستها و Cancellation (§۴-۵)

- **Singleflight کل عملیات**: آینده عمل در همان فراخوانی اول به‌صورت همزمان نصب می‌شود (بدون پنجره رقابت)؛ چند ensureAuthorized هم‌زمان = یک پراکسی/یک core job (تست‌دار).
- **بازاستفاده سشن**: سشن سالم در همان Context دوباره برگردانده می‌شود بدون کار جدید؛ پراکسی مُرده → بازسازی (با ابطال فوری در healthCheck برای بستن پنجره رقابت).
- شکستها با کدهای پایدار: `walkActive` / `directFailed` (با کد داخلی؛ بدون Bootstrap) / `allRoutesFailed` (با جمع شکست هر مسیر) / `authorizationFailed` / `cancelled` / `disposed`؛ در حافظه: شکست start (کد خود هسته از مراحل ۲/۳) جدا از شکست authorization (کد verifier).
- Retry: هر مسیر حداکثر یک‌بار در هر فراخوانی؛ Backoff بین‌فراخوانی از طریق Cooldown حافظه — حلقه بی‌نهایت ممنوع.
- Cancellation: چک‌پوینت در همه مراحل + «مسابقه stop» روی awaitهای Seam (روی verify و direct فوراً اثر می‌کند)؛ stop مالک حالت پایانی است (stopping→stopped)؛ فراخوانی بعدی پس از stop مجدد کار می‌کند.
- `release()` سطح Stage 6 (سیاست توقف Psiphon پس از Authorization مال آن مرحله است)؛ حافظه پس از release زنده می‌ماند.
- تغییر شبکه: `notifyNetworkContextChanged` سشن با Context متفاوت را باطل می‌کند (توقف پراکسی؛ حافظه می‌ماند؛ ارزیابی مجدد در فراخوانی بعد).
- اندازه‌گیری جداگانه (§۷.۱): `directMillis` / `bootstrapReadyMillis` / `authorizationMillis` — در سشن و در حافظه (برای مقایسه Cold/Warm مرحله ۷/۹؛ بدون اعلام عدد اندازه‌گیری‌نشده).

### ۵. فایلهای تغییرکرده (Stage 4)

- **جدید**: `lib/connection/firefox/guardian_bootstrap_manager.dart`، `lib/connection/firefox/bootstrap_route_memory.dart`، `test/guardian_bootstrap_manager_test.dart` (۲۳ تست).
- دست‌نخورده: همه فایلهای قبلی شامل مدیر مراحل ۲/۳ (گواهی: git status فقط سه فایل جدید). pinها، Go، CGO/A1، workflowها، Data Plane — بدون تغییر.

### ۶. تستها و نتایج واقعی (Stage 4)

- `flutter analyze` → **صفر یافته**.
- فایل جدید: **۲۳/۲۳ سبز** — شش گروه: حافظه (نبود/خرابی فایل، ترتیب Discovery، TTL، ایزوله‌سازی Context، قرارداد Schema بدون راز)؛ مسیر Direct (سناریو A: موفقیت بدون هیچ موتور؛ خطای غیر-۴۵۱ بدون حلقه Bootstrap)؛ Discovery (سناریوهای B/C: توالی وضعیت کامل + زمانها، شکست Standalone→موفقیت Chain، allRoutesFailed با تفکیک و آزادسازی، شکست Authorization جدا از start)؛ Singleflight/بازاستفاده (۳ فراخوانی هم‌زمان = ۱ job؛ سشن سالم بدون کار جدید؛ پراکسی مُرده بازسازی می‌شود)؛ Fast Path (سناریو G: پس از restart پرش از Direct + تأیید مجدد؛ شکست Fast Path→Cooldown→Discovery؛ انقضای TTL→Direct اول؛ Context دیگر هرگز)؛ تغییر شبکه/release/walk؛ Cancellation/dispose.
- `flutter test` کل مخزن: **۳۶۸ پاس / ۸ skip قبلی / ۰ شکست**.
- Go: بدون تغییر (اثبات با git status) — CI نهایی.

### ۷. NOT TESTED (Stage 4)

- Authorization و Direct واقعی Guardian (Seamها با fake تست شدند — وصلکردن واقعی Stage 5 است).
- منبع واقعی Network Context (دسته‌بندی wifi/cellular) — اپ منبع ندارد؛ باکت واحد پیش‌فرض با محدودیت مستند.
- رفتار روی دستگاه/شبکه ایران (Stage 8/9).
- اعداد Cold/Warm واقعی — فقط ساختار اندازه‌گیری ساخته شد؛ عدد بدون اندازه‌گیری اعلام نشده (Stage 9).

---
## نقشه فایل‌های کلیدی (برای مراحل بعد)

| موضوع | مسیر |
|---|---|
| Control-plane client/transport seam | `phase1/firefox-vpn-client/http_client.go` (pin؛ فقط مرجع — تغییر نمی‌شود) |
| Guardian API + خطاها | `phase1/firefox-vpn-client/guardian.go` (pin؛ مرجع) |
| الگوی api-proxy | `phase1/firefox-vpn-client/cmd/proxy-demo/main.go` L1396-1453 (pin؛ مرجع) |
| خطاهای موتور → Dart | `phase1/fxv/internal/fferr/classify.go` + `cmd/libfirefoxvpn/main.go` (classifyGuardian) |
| Renewal | `phase1/fxv/internal/upstream/controller.go` (runRenewalLoop/renew) |
| Config موتور (stdin JSON) | `phase1/fxv/internal/engine/config.go` + `lib/connection/firefox/firefox_protocol.dart` |
| ساخت FirefoxEngineConfig | `lib/connection/platform_engine_adapter.dart` (~L2440) |
| اجرای هسته Rust | `lib/connection/aether_ffi.dart` (aether_core_start) + `lib/connection/engine.dart` |
| args هسته (psiphon) | `lib/connection/platform_engine_adapter.dart` AetherArguments.build (~L100-380) |
| TUN/VpnService | `android/.../AethoneVpnService.kt` + MainActivity.startVpn |
| ترکیب‌ها/پورت‌ها | `lib/connection/transport_modes.dart` + `docs/CLI_REFERENCE.md` + `docs/FEATURE_MATRIX.md` §4 |
| spawn/notice های psiphon | pin `CluvexStudio/Aether` @ `d58f9d56` → `aether/src/psiphon.rs` |
| مدیر Bootstrap Psiphon — مستقل + زنجیره (Stage 2+3) | `lib/connection/firefox/psiphon_bootstrap.dart` (PsiphonBootstrapProxy با دو mode + SocksTlsReadyProbe + buildArgs/buildChainArgs/warpProtocolArgs/pickTwoDistinctLoopbackPorts) + `test/psiphon_bootstrap_test.dart` |
| Bootstrap Strategy Manager + حافظه مسیر (Stage 4) | `lib/connection/firefox/guardian_bootstrap_manager.dart` (GuardianBootstrapManager + پنج Seam: DirectAttempt/AuthorizationVerifier/NetworkContext/UserWalkGuard/proxyFactory + ماشین وضعیت) + `lib/connection/firefox/bootstrap_route_memory.dart` + `test/guardian_bootstrap_manager_test.dart` |
| RoutingRoundTripper + allowlist + نقش probe (Stage 5 — Go) | `phase1/fxv/internal/cptransport/routing.go` (RoutingRoundTripper/GuardianAllowlist/NewProxyRoundTripper) + `cmd/libfirefoxvpn/guardianprobe.go` (--guardian-probe + installGuardianRouting) + فیلد `apiProxy` در `internal/engine/config.go` |
| Seamهای واقعی + ادغام walk (Stage 5 — Dart) | `lib/connection/firefox/guardian_engine_seams.dart` (EngineGuardianProbe + DirectAttempt/Verifier + EvidenceForwarding + Integration.build) + `apiProxy`/`args` در firefox_protocol/firefox_engine + walk بازسازی‌شده در `platform_engine_adapter.dart` (_connectFirefox: Fast Path + escalation یک‌بار در 451) + `fastPathEligible` در مدیر |
| طبقه‌بندی 451 Guardian (Go) | `phase1/fxv/internal/fferr/classify.go` (ClassifyGuardian) + `cmd/libfirefoxvpn/main.go` (classifyGuardian) + `internal/upstream/controller.go` (renewalFailCode) |
| مدل خطای Dart + متنها | `lib/connection/firefox/firefox_errors.dart` + `lib/connection/firefox/firefox_protocol.dart` + `lib/l10n/app_strings.dart` (firefoxErrGuardianRegion) |

---

## یافته‌ها و تغییرات Stage 5 (اجرای 2026-11-10)

### ۱. معماری پیاده‌سازی‌شده — Routing RoundTripper و اتصال انتخابی Guardian

- **Go — بسته جدید `internal/cptransport`**: `RoutingRoundTripper` دقیقاً با ساختار مأموریت §۵-۲ (Default = همان `vpnclient.NewControlPlaneTransport()` مستقیم uTLS؛ پایه bootstrap فقط برای allowlist). نصب فقط وقتی `apiProxy` غیرخالی باشد (با apiProxy خالی هیچ `SetControlPlaneTransport`ای صدا نمی‌شود — رفتار pre-Stage-5 بایت‌به‌بایت).
- **Allowlist دقیق (§۵-۳)**: `GuardianAllowlist` از Base URL واقعی `cfg.Guardian` + مدخلهای Method+Path ساخته می‌شود؛ مدخل اولیه فقط `GET /api/v1/fpn/token` (تنها endpoint در مسیر اجرایی — جدول Stage 1). `/status` و `/activate` خارج ماندند. تطبیق: Host (case-insensitive) + Port + Method + Path دقیق؛ پذیرش تحمل doubled-leading-slash (یادداشت Armanِ Stage 1 — مسیر `//api/v1/fpn/token` هم allowlist می‌شود تا ترفند آینده نشکند؛ خودش تغییری ایجاد نمی‌کند).
- **Redirect (§۵-۵)**: http.Client هر hop را دوباره از RoundTrip عبور می‌دهد → هر hop مستقل بازبینی Allowlist می‌شود؛ hop خارج از allowlist خودکار Direct می‌رود (تست‌دار).
- **`NewProxyRoundTripper`** (الگوی `configureAPIProxy` در proxy-demoِ pin، بدون تغییر pin): http/https → `Proxy`+`DialContext`؛ socks5/socks5h → `proxy.SOCKS5` dialer (نام مقصد به پراکسی می‌رود → DNS Guardian از مسیر پراکسی، بدون لو رفتن local DNS)؛ HTTP/1.1 pin؛ `TLSClientConfig=nil` (Certificate+Hostname Verification پیش‌فرض روشن؛ هیچ InsecureSkipVerify در هیچ‌جای این بسته نیست — تست‌دار).
- **Validation موتور**: فیلد `apiProxy` در `engine.Config` (stdin JSON؛ فقط وقتی غیرخالی serialize می‌شود)؛ قواعد: scheme ∈ {http,https,socks5,socks5h}، host فقط loopback (یا localhost)، **userinfo ممنوع** (`apiProxyCredentialsForbidden` — نشت از راه log؛ پراکسی محلی bootstrap بدون auth است). کدهای جزئیات: `apiProxyInvalid`/`apiProxySchemeUnsupported`/`apiProxyNotLoopback`/`apiProxyCredentialsForbidden`.
- **نقش جدید موتور `--guardian-probe`**: walk واقعی `AcquireInitialPass` (همان controller تونل: FetchProxyPass + بازیابی same-account FxA) بدون discovery/session/listener؛ نصب همان routing قبل از اولین درخواست control-plane؛ رویدادها `started`→`passAcquired`+exit پاک یا `quotaExhausted`/`failed` با طبقه‌بندی Stage 1 (451 واقعی = `guardianRegionUnavailable`). خروجی ساختار یافته؛ parse لاگ وجود ندارد. `authRefreshed` (رویداد راز) مستقیم به callback والت می‌رود.
- **Dart — `guardian_engine_seams.dart`**: `EngineGuardianProbe` (spawn واقعی `--guardian-probe` با/بدون apiProxy + طبقه‌بندی: passAcquired/regionUnavailable/otherFailure/timeout + stop بدون process یتیم + timeout)؛ `EngineGuardianDirectAttempt` و `EngineGuardianAuthorizationVerifier` (seamهای Stage 4 با درخواست واقعی از طریق همان موتور)؛ `EvidenceForwardingGuardianDirectAttempt` (حامل یک‌بارمصرف شواهد direct خود walk — مانع probe تکراری می‌شود؛ fallback به probe واقعی برای فراخوانی‌های بدون شواهد مثل renewal مرحله 6)؛ `GuardianBootstrapEngineIntegration.build` (مونتاژ مدیر + seamهای واقعی + walk guard).
- **`FirefoxVpnEngine.start`**: پارامتر `args` (فقط role flagهای ثابت مثل `--guardian-probe`؛ قرارداد امنیتی argv بدون راز دست‌نخورده)؛ `FirefoxEngineConfig.apiProxy` (additive؛ empty → فیلد در JSON نمی‌آید).

### ۲. ادغام walk (رفتار درخواست §۵-۴ در `_connectFirefox`)

- **Direct اول**: spawn موتور بدون apiProxy — خود walk، درخواست مستقیم Guardian است (بدون probe اضافی/هزینه دوبرابر).
- **Fast Path پیش از spawn** (`fastPathEligible` — متد جدید فقط-خواندنی مدیر، همان منطق داخلی `_runOperation`): مسیر معتبر ذخیره‌شده + شاهد 451 اخیر → `ensureAuthorized()` قبل از spawn (مدیر مستقیم را skip می‌کند) → spawn با apiProxy از ابتدا. شکست Fast Path (allRoutesFailed بعد از discovery داخلی) → یک spawn مستقیم صادقانه باقی می‌ماند (شاید محدودیت برداشته شده).
- **Escalation در 451**: فقط در تلاش مستقیم و فقط یک‌بار در هر walk — شواهد 451 خود walk به `directEvidence.forward` داده می‌شود (درخواست مستقیم واقعیِ اتفاق‌افتاده؛ manager بدون probe مجدد) → `ensureAuthorized()` (bootstrap مسیرها به‌ترتیب + verify از طریق proxy) → **respawn همان walk با apiProxy** («همان درخواست با Retry محدود» §۵-۴). شکست respawn → خطای صادقانه `firefoxTransport:guardianRegionUnavailable` (بدون حلقه). سهمیه/خطاهای غیر-451 → مسیرهای pre-Stage-5 دست‌نخورده.
- **Lifecycle**: `_hardCleanup` → `manager.stop()` (پراکسی bootstrap با سشن teardown می‌شود — بدون یتیم؛ **نمونه manager می‌ماند** — singleflight؛ حافظه فایلی می‌ماند)؛ موفقیت متصل → bootstrap زنده می‌ماند برای renewal (§۵-۶؛ سیاست release مال Stage 6). `UserWalkGuard` = `_userAetherWalkActive` (walk/sشن aether خانواده فعال: `_jobId != null || (_connecting && aetherFamily)`).

### ۳. فایلهای تغییرکرده (Stage 5)

- **Go — جدید**: `internal/cptransport/routing.go` (+`routing_test.go` — ۹ تست)، `cmd/libfirefoxvpn/guardianprobe.go` (+`guardianprobe_test.go` — ۴ تست).
- **Go — تغییر**: `internal/engine/config.go` (+۴۷؛ فیلد+validation)، `internal/engine/contract.go` (+۷؛ کدهای جزئیات)، `internal/engine/config_test.go` (+۵۷؛ ۳ تست validation)، `cmd/libfirefoxvpn/main.go` (+۳۳؛ نقش probe در run()، نصب routing در runTunnel، `watchStdinCloseReader` با reader تزریق‌شده — رفع data-race جهانی os.Stdin در تستها با لبه settle).
- **Dart — جدید**: `lib/connection/firefox/guardian_engine_seams.dart`، `test/guardian_engine_seams_test.dart` (۱۳ تست با spawn واقعی پروسه و binary جانشین bash).
- **Dart — تغییر**: `firefox_protocol.dart` (+۱۴؛ apiProxy)، `firefox_engine.dart` (+۱۶؛ args)، `guardian_bootstrap_manager.dart` (+۴۰؛ `fastPathEligible` + حمل directMillis به سشن bootstrap — کمال §۷.۱)، `platform_engine_adapter.dart` (ادغام walk)، `test/guardian_bootstrap_manager_test.dart` (+۶۶؛ ۴ تست fastPathEligible).
- **مستندات**: `docs/FIREFOX_VPN_ENGINE.md` (سطر apiProxy در جدول config + بخش نقش `--guardian-probe`).
- دست‌نخورده: pinها (`firefox-vpn-client`، Aether `d58f9d56`، psiphon fork)، CGO/A1، workflowها، Data Plane، مدیر/پراکسی مراحل ۲+۳ (فقط مصرف شدند).

### ۴. تستها و نتایج واقعی (Stage 5)

- **Go**: `go vet ./...` → صفر. `go test ./...` → هر ۸ پکیج ok. `go test -race` روی cptransport+engine+cmd → ok (رفع data race واقعی در تست probe: خواننده os.Stdin جهانی). تست‌های کلیدی:
  - cptransport: ۱۵+ زیرکیس allowlist (ورودی واقعی proxied؛ POST/status/activate/پیشوند/FxA/RemoteSettings/پورت متفاوت/substring-host/http-schema → همه Direct؛ پروکسی nil → Direct؛ doubled-slash → proxied)؛ ساخت پراکسی برای ۴ scheme + رد bad؛ **TLS verification روشن** (بدون InsecureSkipVerify + HTTP/1.1 pin)؛ **e2e با پراکسی CONNECT واقعی محلی**: GET token از طریق پراکسی + مسیرهای غیرمجاز و host دیگر Direct + redirect فقط hop اول از پراکسی؛ **TLS تأییدشده از طریق پراکسی** (CA تستی با SSL_CERT_FILE؛ برگشت‌نامه wrong-CA با خطای certificate رد می‌شود — اثبات اجرایی verification).
  - probe: 451 واقعی → `guardianRegionUnavailable`+httpStatus 451؛ موفقیت → passAcquired+exit پاک؛ سهمیه → quotaExhausted (هرگز 451)؛ **مسیریابی از طریق apiProxy با TLS تأییدشده** (پراکسی CONNECT واقعی، شاهد ptravers).
  - engine config: apiProxy خالی معتبر؛ ۶ شکل loopback مجاز؛ ۱۰ رد (non-loopback/credential/scheme/invalid).
- **Dart**: `flutter analyze` → صفر یافته. `flutter test` کل: **۳۸۵ پاس / ۸ skip قبلی / ۰ شکست** (۳۶۸→۳۸۵). تست‌های کلیدی seams (با spawn واقعی پروسه + binary جانشین که رفتارش به فیلد apiProxy روی سیم کلید خورده): 451→regionUnavailable؛ ok→passAcquired؛ **apiProxy واقعاً روی سیم** (بدون آن 451، با آن موفق)؛ garbage→otherFailure؛ hang→timeout بدون یتیم؛ authRefreshed→callback والت؛ EvidenceForwarding یک‌بارمصرف؛ **جریان کامل §۵-۴**: direct probe (451) → bootstrap → verify از طریق proxy → سشن با endpoint+زمانها + ترتیب کامل ماشین وضعیت + `fastPathEligible=true` پس از آن.
- Go/Dart با هم: هیچ تست قبلی حذف/ضعیف نشد (suite قبلی ۳۶۸ سبز ماند).

### ۵. NOT TESTED (Stage 5)

- 451 واقعی Guardian از شبکه ایران و مسیر کامل روی دستگاه (Stage 8/9 — سناریوهای B/C/F).
- رفتار walk ادغام‌شده در adapter روی UI واقعی (تست widget/engine سطح adapter موجود نیست؛ پوشش با تست‌های manager/seams/probe + ادغام Stage 7 سناریوهای A–F).
- ترفند doubled-leading-slash پیاده نشد (فقط تحمل مسیر در allowlist؛ طبق دستور Stage 5 فقط مستندسازی Stage 1).
- منبع واقعی Network Context هنوز باکت واحد است (محدودیت مستند Stage 4).

---

## دستور دقیق ادامه کار (جلسه بعدی — Stage 6)

1. همین فایل را بخوان؛ HEAD باید commit مستقل Stage 5 باشد و working tree پاک (شاخه شامل کد Stage 2+3+4+5 و مستندات).
2. **فقط Stage 6 را اجرا کن** — Renewal و Lifecycle کامل:
   - بررسی از سورس pin: عمر واقعی Proxy Pass (از claims پاسخ — `pass.ExpiresAt()`)، زمان‌بندی renewal در `runRenewalLoop`/`renew` (کنترلر)، رفتار `OnRenewalFail` (+failCode از Stage 1) و `retryInMs`.
   - سیاست Psiphon (§۶ مأموریت): بعد از Authorization موفق — آیا Renewal به Guardian نیاز خواهد داشت (بله: همان `GET /api/v1/fpn/token`؛ renewal از همان transport می‌گذرد → با apiProxy از مسیر bootstrap می‌رود — این حالا کار می‌کند)؛ **زمان توقف امن bootstrap** (مبنای تصمیم: اعتبار باقی‌مانده مجوز از پاسخ واقعی؛ هیچ زمان hardcode نشود)؛ توانایی فعال‌سازی مجدد Manager وقتی Renewal بعداً proxy بخواهد (manager پس از stop دوباره کار می‌کند — تست‌دار)؛ خاموشی Psiphon نباید renewal بعدی را بی‌دلیل بشکند.
   - Lifecycle: Start/Stop/Dispose/Restart/Network change (`notifyNetworkContextChanged` موجود)/Cancellation/Timeout/Process crash/Renewal/Rotation/Resource cleanup — از سورس واقعی سناریوها را بساز و تست بنویس؛ `release()` مدیر مال این مرحله است.
   - یکپارچه‌سازی با walk: رفتار پس از قطع (disconnect → _hardCleanup → manager.stop — الان پیاده است) و نگه‌داشتن تا انقضای مجوز؛ نقش `session.endpoint` در respawnها.
   - قواعد ثابت: تغییر حدسی نکن؛ pinها دست‌نخورده؛ هیچ تست قبلی حذف/ضعیف نشود؛ commit مستقل؛ push به همین شاخه؛ به‌روزرسانی همین فایل؛ گزارش ۱۰-بندی؛ توقف.
3. قانون توقف: بعد از Stage 6 متوقف شو؛ مرحله ۷ (تست جامع و تفکیک Data Plane) در اجرای بعدی.

---

## گیت مراحل

| مرحله | Commit | عنوان |
|---|---|---|
| 0 — مستندات | `8a54a1b` | docs(guardian-bootstrap): stage 0 — architecture audit (guardian control-plane seam, psiphon local-proxy/chain mechanics, combination map, no-mask finding) |
| 1 — کد | `2c04f5a` | feat(firefox): classify guardian HTTP 451 as region-unavailable |
| 1 — مستندات | `caac298` | docs(guardian-bootstrap): stage 1 — 451 classification report, transport scope, port map (pins `2c04f5a`) |
| 2 — کد | `b88b423` | feat(psiphon): standalone guardian-bootstrap local proxy (stage 2) |
| 2 — مستندات | `e28e93b` | docs(guardian-bootstrap): stage 2 — standalone proxy report (pins `b88b423`) |
| 2 — راستی‌آزمایی | `27d0319` | docs(guardian-bootstrap): stage 2 — independent verification (git/remote sync، analyze 0، 331+8~0، 21/21 + LIVE سبز؛ بدون بازنویسی کد) |
| 3 — کد | `cebb710` | feat(psiphon): launch the EXISTING aether-psiphon chain for guardian bootstrap (stage 3) |
| 3 — مستندات | (همان `cebb710`؛ کد و مستندات در یک commit مستقل این مرحله) | شامل بخش Stage 3 + به‌روزرسانی وضعیت/نقشه/دستور Stage 4 |
| 4 — کد | (tip شاخه پس از همین commit) | feat(guardian): bootstrap strategy manager — fast path, discovery, route memory (stage 4) |
| 4 — مستندات | (همان tip؛ کد و مستندات در یک commit مستقل این مرحله) | شامل همین بخش Stage 4 + به‌روزرسانی وضعیت/نقشه/دستور Stage 5 |
| 5 — کد+مستندات | (tip شاخه پس از همین commit) | feat(guardian): routing roundtripper — guardian-only selective control plane (stage 5) — شامل بخش Stage 5 این فایل + به‌روزرسانی وضعیت/نقشه/دستور Stage 6 |

*(Token دسترسی در متن مأموریت مالک تأمین می‌شود؛ در این فایل ذخیره نشده است.)*
