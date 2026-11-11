# FIREFOX GUARDIAN PSIPHON BOOTSTRAP — PERMANENT PROGRESS FILE

> مرجع دائمی مأموریت Guardian Bootstrap Manager (عبور HTTP 451 با Psiphon و ترکیب‌های موجود).
> هر جلسه جدید باید این فایل را بخواند و از همین وضعیت ادامه دهد — نه از حافظه مکالمه.
> هیچ Token/Session/Refresh Token یا اطلاعات حساب در این فایل قرار نمی‌گیرد.

## وضعیت کلی

| فیلد | مقدار |
|---|---|
| تاریخ آخرین اجرا | 2026-11-11 |
| Repository | `CHAKCAAD/AETHONE` (تنها مخزن مجاز) |
| Branch کاری | `feature/firefox-guardian-psiphon-bootstrap` |
| Base Commit | `ce852ea` (= tip شاخه `performance/firefox-vpn-optimization`؛ شامل تمام اصلاحات Performance مراحل ۰–۸) |
| آخرین Commit کد | `0a9e7e1dea51e3cea7f63f5503f963fa6975f374` |
| مرحله فعلی | **Stage 9.2 — Direct → Psiphon Standalone → Aether-selected-protocol + Psiphon؛ کد و تست‌های هدفمند ثبت شده، CI و دستگاه هنوز pending** |
| مرحله تکمیل‌شده آخر | **Stage 9.2 — منطق fallback حمل‌ونقل و انتخاب پروتکل در شاخه feature پیاده‌سازی شده؛ اثبات نهایی با CI و اجرای POCO X3 باقی است** |
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
| سیاست Renewal/Lifecycle + نگاشت outcome (Stage 6) | `lib/connection/firefox/guardian_renewal_policy.dart` (GuardianRenewalSupervisor + kGuardianRenewalGrace + Facts) + `retryInMs` در firefox_protocol + caseهای quotaExhausted در firefox_engine/firefox_errors + wiring در `platform_engine_adapter.dart` (_ensureGuardianBootstrap/_connectFirefox/_hardCleanup) + تست‌های حلقه renewal در `phase1/fxv/internal/upstream/renewal_loop_test.go` |
| طبقه‌بندی 451 Guardian (Go) | `phase1/fxv/internal/fferr/classify.go` (ClassifyGuardian) + `cmd/libfirefoxvpn/main.go` (classifyGuardian) + `internal/upstream/controller.go` (renewalFailCode) |
| مدل خطای Dart + متنها | `lib/connection/firefox/firefox_errors.dart` + `lib/connection/firefox/firefox_protocol.dart` + `lib/l10n/app_strings.dart` (firefoxErrGuardianRegion + firefoxErrQuotaExhausted + firefoxErrRenewalTimeout) |
| اثبات تفکیک Data Plane (Stage 7 — Go) | `phase1/fxv/internal/socks/dataplane_separation_test.go` (داده فقط تونل؛ کنترل-پلن صفر؛ پراکسی bootstrap صفر) |
| تست سطح UI/l10n (Stage 7 — Flutter) | `test/guardian_ui_test.dart` (سطح شکست 451/quota + sheet + عدم موفقیت کاذب + نگاشت ۱۱ کلاس در ۵ زبان) |

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

## یافته‌ها و تغییرات Stage 6 (اجرای 2026-11-10)

### ۱. قرارداد Renewal از سورس pin (شواهد قفل‌شده)

- **عمر واقعی Proxy Pass**: claims پاسخ — `ProxyPassInfo.ExpiresAt()` = JWT `exp` (Unix) + تصحیح ساعت claim (`claimTimeOffset`؛ tolerance یک دقیقه، سقف آینده ۲ ساعت) — `firefox-vpn-client/guardian.go` L40-45. هیچ طول عمر hardcode وجود ندارد؛ موتور آن را در رویدادهای `passAcquired`/`renewed` به‌صورت `passExpiresAt` (RFC3339 UTC) ساطع می‌کند (`cmd/libfirefoxvpn/main.go`).
- **زمان‌بندی renewal**: `runRenewalLoop` تا `expiresAt − proxyPassRenewLead(2min)` می‌خوابد، بعد `renew()` → همان `GET /api/v1/fpn/token` از طریق همان transport کنترل-پلن نصب‌شده (صندلی RoutingRoundTripper مرحله ۵) → یعنی **renewal موتوری که با apiProxy spawn شده، از مسیر bootstrap می‌گذرد** (اثبات اجرایی در §۵).
- **Rotation**: تمدید موفق، توکن خام تازه را با `Session.UpdateToken` روی سشن زنده swap می‌کند (host توکن را نمی‌بیند) + `OnPassRenewed` → رویداد `renewed` با انقضای جدید.
- **شکست renewal**: `OnRenewalFail(پیام redact‌شده، failCode طبقه‌بندی Stage-1 — 451 واقعی = `guardianRegionUnavailable`، retryInMs = `proxyPassRetryDelay` = ۳۰ثانیه) → رویداد `renewalFailed`؛ حلقه retry می‌کند و هرگز روی شکست retryable پارک نمی‌شود.
- **Terminalها**: 429 → `quotaExhausted` + خروج ۲؛ انقضای عقب‌مانده بیش از `proxyPassRenewTimeout(2min)` → `failed`(`renewalTimeout`) + خروج ۳ (host باید reconnect کند). خطای OAuth در renew → همان-حساب `FxaRefreshToken` + retry (رویداد راز `authRefreshed` فقط به callback می‌رود).

### ۲. شکاف‌های واقعی کشف‌شده و رفع‌شده

- **`retryInMs` در Dart parse نمی‌شد** (فقط `loginRetry` آن را می‌شناخت) → به `FirefoxEngineEvent` اضافه شد (tolerant؛ ۰ وقتی نبود).
- **رویداد `quotaExhausted` outcome را کامل نمی‌کرد**: موتور آن را به‌عنوان رویداد مستقل + خروج ۲ ساطع می‌کند (نه `failed` با failCode) → outcome از مسیر exit-code با `engineExited:2` resolve می‌شد و شاخه quota در walk (`o.failCode == quotaExhausted` — پیام «موتور دیگری انتخاب کن» مالک) **هرگز اجرا نمی‌شد**. حالا case اختصاصی در `firefox_engine.dart` outcome را با کلاس خودش کامل می‌کند (تست‌دار با spawn واقعی).
- **کدهای `quotaExhausted`/`renewalTimeout` در classify به `unknown` می‌افتادند** → caseهای اختصاصی + diagnostic (quota: غیرقابل retry؛ renewalTimeout: retryable — walk تازه کل تصمیم را بازاجرا می‌کند).
- **باگ واقعی escalation**: `late final outcome` در `_connectFirefox` در respawn مرحله ۵ (تلاش دوم همان walk) دوباره assign می‌شد → `LateInitializationError` و مرگ walk در میانه escalation. **اثبات‌شده با repro مستقل Dart**؛ fix: `late` غیر-final (همان semantics تنبل، بدون crash). هیچ تستی این مسیر adapter را نمی‌پوشاند (NOT TESTED ثبت‌شده Stage 5) — باگ تا Stage 6 بی‌سر‌وزن ماند.

### ۳. سیاست Psiphon (§۶ مأموریت) — تصمیم‌ها و مبنای هر تصمیم

- **آیا Renewal به Guardian نیاز دارد؟** بله — همان `GET /api/v1/fpn/token`؛ از همان transport می‌گذرد → با apiProxy از مسیر bootstrap (حالا کار می‌کند؛ Go-تست §۵ اثبات می‌کند درخواست renewal از transport نصب‌شده عبور می‌کند).
- **زمان توقف امن bootstrap**: مبنای تصمیم = **اعتبار باقی‌مانده مجوز از پاسخ واقعی** (`passExpiresAt`). سیاست: سشنِ روی مسیر bootstrap → پیش‌فرض **نگه‌داشتن** (مسیر، مسیر renewal همین موتور است؛ release زودتر = شکست renewal جاری — «خاموشی Psiphon نباید renewal بعدی را بی‌دلیل بشکند»)؛ هر `renewed` پنجره را با انقضای جدید re-arm می‌کند (rotation حالت عادی است)؛ **release قطعی** = teardown سشن (`_hardCleanup` → `manager.stop()` — Stage 5) و **backstop انقضا** = `passExpiresAt + kGuardianRenewalGrace(2min)` (آینه‌ی `proxyPassRenewTimeout` موتور pin — ثابتِ قراردادی از سورس، نه زمان فرضی) که حتی با از دست رفتن teardown، bootstrap را بی‌دلیل زنده نگه نمی‌دارد («Psiphon بدون دلیل دائماً فعال باقی نماند»).
- **فعال‌سازی مجدد**: بعد از release/stop، نمونه manager + singleflight + حافظه فایل می‌ماند → `ensureAuthorized()` بعدی مسیر را بازمی‌سازد (تست جدید: reactivation پس از release با rebuild واقعی proxy، نه reuse ساختگی). EvidenceForwarding برای فراخوانی‌های بدون شواهد (مثل reauthorization زمان renewal) به probe واقعی fallback می‌کند (تست جدید). **بدون کار پس‌زمینه خودخواسته** (§7.1): reconnect walk خودِ درخواست است.
- **خاموشی Psiphon و renewal بعدی**: موتور مستقیم (بدون apiProxy) که renewal آن 451 می‌گیرد، retry می‌کند (۳۰ث) و خودش پارک می‌شود (خروج ۳) → walk بعدی کل تصمیم را بازاجرا می‌کند (fast path/escalation با apiProxy تازه). apiProxy در spawn ثابت است — سوئیچ درجا در موتور pin ممکن نیست و ساخت آن ممنوع؛ این محدودیت صادقانه مستند شد.
- **Network Change**: `notifyNetworkContextChanged` مدیر موجود است و تست دارد؛ اما با SingleBucketContextProvider (محدودیت مستند Stage 4) ساختاراً no-op است و هیچ منبع connectivity مجازی در اپ وجود ندارد (§7.1 مجوز جدید ممنوع) → **caller واقعی وصل نشد** (کد مرده ممنوع)؛ رفتار واقعی تغییر شبکه = بازارزیابی هر walk (direct→451→fast path از نو).

### ۴. معماری پیاده‌سازی‌شده — GuardianRenewalSupervisor (Dart)

- **فایل جدید `lib/connection/firefox/guardian_renewal_policy.dart`**: سیاست renewal/lifecycle به‌صورت شیء صریح و تست‌پذیر؛ ورودی = رویدادهای واقعی موتور (`onEngineEvent` با فیلتر passAcquired/renewed/renewalFailed/quotaExhausted)، `attachSession(viaBootstrapProxy)`، `onEngineGone` (backstop مسلح می‌ماند — سقف teardown-from-hand-risen)، `onSessionTeardown` (قطعی — لغو timer)، `dispose` (بدون timer یتیم). خروجی = `onBootstrapExpired` (آداپتور: فقط manager آرام/authorized را release می‌کند — عمل in-flight مالک proxy است) + `GuardianRenewalFacts` (انقضا/quota/شمار شکست/آخرین failCode+retryInMs — بدون هیچ راز).
- **قواعد**: timestamp غیرقابل‌parse (موتور legacy/خصوصه) → هیچ deadline فرضی مسلح نمی‌شود (تست‌دار)؛ انقضای گذشته (clock skew) → بلافاصله؛ سشن مستقیم → هرگز release نمی‌کند؛ quota → فقط ثبت (توقف با خود engine؛ teardown مال release است).
- **Wiring آداپتور**: `_ensureGuardianBootstrap` ناظر را روی همان manager می‌سازد؛ `_connectFirefox` در حلقه spawn به‌ازای هر spawn: اشتراک رویدادها (جایگزین per-spawn؛ لغو در `_hardCleanup` — بدون listener یتیم) + attach + دنبال‌کردن outcome برای engine-gone؛ `_hardCleanup`: ابتدا لغو اشتراک + teardown ناظر، بعد `manager.stop()`.
- **Lifecycle پوشش‌داده‌شده**: Start (attach)/Stop و Dispose (teardown + dispose)/Restart (walk جدید = teardown + attach تازه؛ + رفع باگ late final)/Network Change (بازارزیابی هر walk + API تست‌دار مدیر)/Cancellation (stop مدیر؛ Stage 4/5)/Timeout (probe/authorization budgets + backstop انقضا)/Process Crash (outcome → death watch → health fail → store reconnect → teardown؛ backstop سقف)/Renewal (کل قرارداد §۱)/Rotation (re-arm با انقضای جدید؛ Go-تست swap توکن روی سشن زنده)/Resource Cleanup (بدون process/listener/timer یتیم — تست‌دار).

### ۵. فایلهای تغییرکرده (Stage 6)

- **Go — جدید**: `internal/upstream/renewal_loop_test.go` (۴ تست: rotation از transport نصب‌شده + UpdateToken روی سشن زنده؛ failCode کلاس 451 + retryInMs=30000؛ quota terminal؛ renewalTimeout terminal — با double تراپی HTTP محلی + transport ضبط‌کننده + بازگرداندن uTLS pin در teardown تست).
- **Dart — جدید**: `lib/connection/firefox/guardian_renewal_policy.dart`، `test/guardian_renewal_policy_test.dart` (۱۳ تست: backstop از انقضای خود pass؛ عدم release قبل از deadline؛ rotation re-arm؛ سشن مستقیم هرگز؛ engine-gone نگه‌می‌دارد؛ quota سقف می‌ماند؛ teardown قطعی لغو می‌کند؛ dispose بدون timer یتیم؛ ثبت failCode/retryInMs؛ timestamp خراب بدون crash/بدون arm فرضی؛ انقضای گذشته فوری؛ + ۳ تست spawn واقعی: نگاشت outcome quotaExhausted (exit 2)، failCode renewalTimeout (exit 3)، توالی کامل renewal از طریق spawn واقعی که ناظر را end-to-end تغذیه می‌کند).
- **Dart — تغییر**: `firefox_protocol.dart` (+parse `retryInMs`)، `firefox_engine.dart` (+case outcome `quotaExhausted`)، `firefox_errors.dart` (+کلاس‌های `quotaExhausted`/`renewalTimeout` + diagnostics)، `platform_engine_adapter.dart` (+فیلدها/ساخت ناظر/wiring هر spawn/teardown؛ +رفع باگ `late final outcome`)، `test/guardian_bootstrap_manager_test.dart` (+۱: reactivation پس از release)، `test/guardian_engine_seams_test.dart` (+۱: fallback به probe واقعی برای renewal-time)، `test/firefox_errors_test.dart` (+۱: نگاشت کلاس‌های lifecycle).
- **مستندات**: `docs/FIREFOX_VPN_ENGINE.md` (بخش «Renewal & lifecycle policy (Stage 6)» + به‌روزرسانی تست‌ها).
- دست‌نخورده: pinها (firefox-vpn-client، Aether `d58f9d56`، psiphon fork)، هیچ کد production در Go تغییر نکرد (فقط تست؛ binary نیازی به rebuild ندارد)، CGO/A1، workflowها، Data Plane، مدیر/پراکسی/seamهای مراحل ۲-۵ (فقط مصرف شدند).

### ۶. تستها و نتایج واقعی (Stage 6)

- **Go**: `go vet ./...` → صفر. `go test ./...` → هر ۸ پکیج ok (بالای ۴ تست جدید upstream). `go test -race` روی upstream + cmd → ok. تست‌های کلیدی renewal: درخواست اولیه + renewal هر دو از transport نصب‌شده کنترل-پلن عبور کردند (ضبط ≥۲ hit؛ مسیر `GET /api/v1/fpn/token`)؛ توکن تازه روی سشن زنده swap شد (۱ UpdateToken)؛ شکست 451 → `guardianRegionUnavailable` + `retryInMs=30000` و حلقه زنده ماند؛ 429 → TerminalQuota بدون OnRenewalFail؛ انقضای ۵-دقیقه‌ای عقب‌مانده → TerminalRenewalTimeout بدون OnRenewalFail.
- **Dart**: `flutter analyze` → صفر یافته. `flutter test` کل: **۴۰۱ پاس / ۸ skip قبلی / ۰ شکست** (۳۸۵→۴۰۱؛ +۱۶ تست جدید، هیچ تست قبلی حذف/ضعیف نشد). تست‌های کلیدی: نگاشت outcome quota از رویداد واقعی (exit 2 + کلاس خودش)؛ renewalTimeout از failed event (exit 3)؛ توالی کامل passAcquired→renewalFailed(retryInMs روی سیم)→renewed از یک spawn واقعی bash که ناظر را تغذیه کرد (facts + backstop مسلح با انقضای rotation؛ teardown لغو کرد)؛ سیاست‌های supervisor با تایمرهای واقعی.
- **Dart standalone repro باگ late final**: `LateInitializationError: Local 'x' has already been initialized` — قبل از fix اثبات شد.

### ۷. NOT TESTED (Stage 6)

- چرخه واقعی renewal روی دستگاه از شبکه ایران (سناریو E مرحله ۸/۹) — عمر واقعی pass از Guardian واقعی و رفتار درجا.
- Wiring سطح adapter در UI واقعی (تست widget/engine سطح adapter موجود نیست — همان NOT TESTED ثبت‌شده Stage 5؛ پوشش با تست‌های supervisor/engine-outcome/manager/seams).
- رفتار پس‌زمینه Android (Background/Foreground): پوشش طراحی (stdin-به-بسته‌شدن = خاموشی engine؛ FFI درون-فرایندی = مرگ با پروسه اپ) اما سناریوی واقعی چرخه حیات Android تست نشد.
- notifyNetworkContextChanged بدون منبع واقعی connectivity (تست واحد موجود؛ اتصال caller واقعی به Stage آینده/مالک واگذار شد).

---

## یافته‌ها و تغییرات Stage 7 (اجرای 2026-11-10)

### ۰. وضعیت آغاز اجرا (شفافیت کامل)

- این اجرا با یک clone محلی قدیمی شروع شد (تا Stage 2 راستی‌آزمایی `27d0319`)؛ `ls-remote` نشان داد ریموت شاخه **۵ commit جلوتر** است (مراحل ۳/۴/۵/۶ قبلاً اجرا و push شده بودند). کار محلی نیمه‌کاره Stage 3 که بر پایه clone قدیمی تولید شده بود، **بدون commit** به‌صورت patch آرشیو شد و شاخه محلی با fast-forward (بدون force، بدون بازنویسی) به tip ریموت `d36cf1e` رسید. سپس وضعیت ریموت بازتولید شد: `flutter analyze` صفر، `flutter test` ۴۰۱+۸~۰، `go vet` صفر، `go test` ۸/۸ ok — اعداد ثبت‌شده Stage 6 دقیقاً تأیید شدند. **Stage 7 فقط روی این پایه اجرا شد.**

### ۱. جدول پوشش رسمی (تست → مورد مأموریت)

Go (همه سبز؛ `go vet` صفر، ۸/۸ پکیج ok، `-race` روی socks/cptransport/cmd سبز):

| مورد مأموریت | شاهد تست |
|---|---|
| تشخیص دقیق 451 | `fferr` `TestClassifyGuardianStatus` (۴۵۱ ساختاریافته/کد-variant/بدنه-خالی/HTML-CDN/بدون-کد → کلاس region؛ بدنه هرگز به پیام نمی‌ریزد) + `guardianprobe` `TestGuardianProbeClassifiesReal451` (سرور واقعی) |
| عدم تریگر در 401/403/429/5xx | `TestClassifyGuardianStatus` (401/403 session، 429 generic، 500/502/503 retryable) + `TestHTTPStatuses` + Dart مدیر («a NON-451 direct failure fails honestly — no bootstrap loop») + probe quota (429 هرگز 451 نیست) |
| مسیر مستقیم | `cptransport` `TestBootstrapUnavailableMeansEverythingDirect` + probe `TestGuardianProbeSucceedsDirect` |
| Psiphon Standalone / AETHER→PSIPHON | Dart: `psiphon_bootstrap_test` (فقط/زنجیر — args، پورت‌ها، probe، lifecycle، LIVE شبیه‌سازی زنجیر)؛ Go: e2e از طریق apiProxy (`TestEndToEndGuardianThroughProxyEverythingElseDirect`، `TestGuardianProbeRoutesThroughTheLocalProxyWithVerifiedTLS`) |
| سایر ترکیب‌ها | ارزیابی Stage 3: `PSIPHON→AETHER` برای wg/gool-classic در هسته pin fail-closed است (UDP روی psiphon ناممکن) — تصمیم مستند، ترکیب رد شده |
| پورت/آمادگی Proxy | Dart `pickFreeLoopbackPort(Pair)` + «an open port that never speaks SOCKS5 is NOT ready» + probe چندشاهدی + LIVE |
| Timeout/Retry/Cooldown | Dart (notReady، بودجه probe، توقف probe آویزان در seams)؛ Go renewal (`TestRenewalLoopFailureCarriesClassAndRetryDelay` = retryInMs 30s)؛ Dart memory (Cooldown/TTL دهها تست) |
| Cancellation | Dart مدیر/پراکسی (stop حین start، checkpointها، dispose) + seams (hang→timeout بدون process یتیم) |
| Network Change | Dart (`notifyNetworkContextChanged`، ایزوله‌سازی Context، بازارزیابی هر walk) |
| Renewal | Go `renewal_loop_test` (چرخش از transport نصب‌شده + UpdateToken روی سشن زنده؛ ترمینال‌ها) + Dart supervisor (۱۳ تست) |
| جلوگیری از Cycle | Dart زنجیر (سه آدرس متمایز، بدون upstream تزریقی، آرگ‌های قفل‌شده) + allowlist Go |
| Singleflight | Dart مدیر (۳ فراخوانی هم‌زمان = ۱ job) + پراکسی (share one future) |
| جلوگیری از نشت Process | Dart (توقف/تخریب بدون یتیم؛ kill_on_drop هسته pin) + seams (hang→stop) |
| جلوگیری از افشای Token | `fferr` `TestTokenGuard`/`TestNoLeak` + `cptransport` رندر Redacted + engine apiProxy userinfo ممنوع + schema حافظه بدون فیلد راز (Dart) |
| FxA/RemoteSettings 451 | طراحی: فقط Guardian در allowlist است؛ FxA/RS حتی با bootstrap فعال Direct می‌مانند — `TestAllowlistRoutesOnlyTheExactGuardianEntry` (۱۵+ زیرکیس شامل FxA/RS/پورت/substring/POST) |

Dart/Flutter (همه سبز؛ `flutter analyze` صفر، ۴۰۴+۸~۰):

| مورد مأموریت | شاهد تست |
|---|---|
| ماشین وضعیت / انتقال وضعیت Bootstrap | `guardian_bootstrap_manager_test` (توالی کامل وضعیت‌ها + زمان‌بندی‌ها) |
| Singleflight / هم‌زمانی | همان فایل (۳ فراخوانی = ۱ پراکسی) |
| خطاهای Psiphon / Combination | همان فایل (شکست start جدا از authorization؛ allRoutesFailed با تفکیک هر مسیر) |
| خطاها → UI | `guardian_ui_test` (جدید، این مرحله): کلاس 451 و quota با کد+تشخیص خودشان زیر pill و در sheet رندر می‌شوند؛ هرگز pill متصل |
| Restart/Cancellation | مدیر + پراکسی + renewal (teardown قطعی، dispose بدون timer یتیم) |
| تغییر Network | مدیر (notify…، ایزوله‌سازی، بازارزیابی) |
| ماندگاری Strategy پس از restart | مدیر («fast path پس از restart: Direct صفر بار، verify مجدد») + memory (پس از release زنده) |
| Fast Path از حافظه معتبر | مدیر (true فقط با مسیر معتبر + شاهد 451؛Direct-skip تست‌دار) |
| Discovery بعد از شکست Fast Path | مدیر («fast-path failure → cooldown + discovery») |
| TTL و Cooldown | memory (انقضا→Discovery؛ موفقیت→پاک شدن Cooldown) |
| جداسازی per-Network-Context | memory/مدیر (Context دیگر هرگز مسیر/سشن این Context را نمی‌بیند) |
| خرابی حافظه بدون crash | memory («corrupt file degrades to empty») |
| Cold-Discovery در برابر Warm-FastPath | ساختار اندازه‌گیری (directMillis/bootstrapReadyMillis/authorizationMillis) + تست توالی؛ اعداد واقعی = Stage 9 |
| Renewal / Proxy Endpoint | supervisor ۱۳ تست + seams (endpoint روی سیم) + manager (release/reactivation) |
| نمایش وضعیت (Flutter) | `guardian_ui_test` (جدید): سطح شکست صادقانه + عدم موفقیت کاذب + l10n پنج زبان برای همه کلاس‌ها. **زیرحالت‌های ریز bootstrap (Checking/Starting Psiphon/Trying Combined/Authorizing) عمداً به UI وصل نشده‌اند** — طراحی مراحل ۵/۶: bootstrap فاز داخلی walk است؛ قرارداد UI = وضعیت‌های walk + کلاس شکست. اتصال chip های ریز = کار UI جدید با تأیید مالک، نه تغییر مرحله تست |
| حفظ رفتار سایر پروتکل‌ها | کل suite سبز (home/protocol/onboarding/settings…) + `firefox_errors_test` («region class ONLY by the Guardian walk») |

Integration (۱۰ سناریوی مأموریت با double/سرور محلی — همه با spawn واقعی یا سوکت واقعی):

| سناریو | شاهد |
|---|---|
| 1. مستقیم 200 → بدون Psiphon | مدیر («direct success authorizes with NO bootstrap») |
| 2. 451 → Bootstrap آغاز | مدیر («451 → standalone first, full state sequence») |
| 3. Psiphon موفق → Guardian از Proxy | seams («451 direct → bootstrap → through-the-proxy authorization» با spawn واقعی) + Go probe e2e |
| 4. شکست Standalone → Chain | مدیر («standalone fails → the EXISTING chain is tried and wins») |
| 5. شکست مسیر → مسیر بعد | مدیر (fast-path failure → discovery از مسیرهای باقی) |
| 6. شکست همه → خطای دقیق+توقف امن | مدیر («allRoutesFailed با طبقه‌بندی per-route») |
| 7. درخواست‌های هم‌زمان → یک Bootstrap | مدیر singleflight |
| 8. انقضای مجوز → فعال‌سازی مجدد | supervisor backstop + مدیر reactivation |
| 9. تغییر شبکه → بازارزیابی | مدیر notify… + ایزوله‌سازی Context |
| 10. Psiphon آماده ولی Guardian شکست → خطای Guardian | مدیر («authorization failure is classified separately») + probe Go (خطا هرگز موفقیت کاذب نیست) |

### ۲. تفکیک Data Plane — اثبات صریح

- **تست جدید Go** `internal/socks/dataplane_separation_test.go` — `TestUserDataPlaneStaysOnTheTunnelWithABootstrapControlPlane`: اتصال REAL کاربر (greeting + DOMAIN CONNECT + echo) از سرور production SOCKS، همزمان با نصب **شکل production کنترل-پلن** روی seam یکتای pin (`SetControlPlaneTransport` با RoutingRoundTripper + allowlist واقعی Guardian + پایه proxied به یک stand-in ثبت‌کننده). سه شاهد: (۱) داده فقط از seam تونل عبور کرد (authority ثبت‌شده)؛ (۲) پایه Direct کنترل-پلن **صفر** درخواست دید؛ (۳) پراکسی bootstrap **صفر** اتصال پذیرفت.
- جهت معکوس (Guardian از پراکسی، غیرمجاز Direct): `cptransport` e2e + probe — ماتریس کامل تفکیک بسته شد: **داده کاربر فقط تونل؛ کنترل-پلن فقط allowlist؛ هیچ مسیر غیرمجاز به پراکسی کمکی نمی‌رود.**

### ۳. شکاف واقعی پیدا و بسته شد (اصلاح در همین مرحله طبق قانون توقف)

- **l10n ناقص**: کلاس‌های Stage 6 (`quotaExhausted`/`renewalTimeout`) تشخیص انگلیسی داشتند اما متن بومی نه — به `firefoxLoginFailed` عمومی می‌افتادند. کلیدهای `firefoxErrQuotaExhausted`/`firefoxErrRenewalTimeout` در **هر پنج زبان** (fa/en/ru/zh/tk) + mapping در `firefoxErrorText` اضافه شد (تست‌دار: نگاشت هر ۱۱ کلاس در ۵ زبان به متن اختصاصی غیرخالی).

### ۴. فایلهای تغییرکرده (Stage 7)

- **Go — جدید**: `phase1/fxv/internal/socks/dataplane_separation_test.go` (۱ تست، سه شاهد تفکیک).
- **Dart — جدید**: `test/guardian_ui_test.dart` (۳ تست: سطح شکست 451 با sheet؛ کلاس quota متمایز؛ l10n پنج‌زبانه همه کلاس‌ها).
- **Dart — تغییر**: `lib/l10n/app_strings.dart` (+۲ کلید × ۵ زبان + getter + mapping).
- **مستندات**: همین فایل (بخش Stage 7 + وضعیت + دستور Stage 8).
- دست‌نخورده: pinها، کد production Go (فقط تست)، CGO/A1، workflowها، کد مراحل ۲–۶ (فقط مصرف شدند)، Data Plane.

### ۵. تستها و نتایج واقعی (Stage 7)

- `flutter analyze` → **صفر یافته**.
- `flutter test` کل: **۴۰۴ پاس / ۸ skip قبلی / ۰ شکست** (۴۰۱→۴۰۴؛ +۳ تست جدید، هیچ تست قبلی حذف/ضعیف نشد).
- `go vet ./...` → صفر. `go test ./...` → **۸/۸ پکیج ok** (socks با تست تفکیک جدید). `go test -race` روی socks/cptransport/cmd → ok.
- بازتولید وضعیت Stage 6 پیش از تغییرات (شفافیت §۰): ۴۰۱+۸~۰ و ۸/۸ ok — مطابق ثبت قبلی.

### ۶. NOT TESTED (Stage 7)

- اجرای واقعی روی گوشی/شبکه ایران (Stage 8 build + Stage 9 سناریوها).
- زیرحالت‌های ریز bootstrap در UI (طراحی: وصل نشده؛ تصمیم با مالک — §۱).
- منبع واقعی Network Context (باکت واحد؛ محدودیت مستند Stage 4).
- اعداد واقعی Cold/Warm (ساختار هست؛ اندازه‌گیری = Stage 9).

---

## یافته‌ها و تغییرات Stage 8 (اجرای 2026-11-11)

### ۰. وضعیت آغاز اجرا و یک رویداد مهم (شفافیت کامل)

- در شروع این اجرا، HEAD لوکال `27d0319` (= راستی‌آزمایی Stage 2) بود؛ فایل پیشرفت لوکال نیز تا Stage 2 را نشان می‌داد. پس از پیاده‌سازی کامل یک Stage 3 موازی، **push با رد مواجه شد**: ریموت شاخه در همان بازه توسط اجرای دیگری تا Stage 7 (`332ff03`) پیش رفته بود (Stage 3–7 کامل، ۴۰۴ تست سبز). تاریخچه ریموت محترم شمرده شد (بدون Force Push — قاعده مأموریت)؛ کار موازی محلی (هرگز push نشده) کنار گذاشته و شاخه لوکال به `332ff03` fast-forward شد. پیام کلیدی برای اجراهای بعدی: **همیشه قبل از شروع، `git ls-remote`/`git fetch` ریموت را بررسی کن، نه فقط HEAD لوکال را.**
- دستور مالک برای این اجرا: «برو مرحله بعد؛ بیلد را باید با Actions گیت‌هاب بگیری نه خودت» — دقیقاً منطبق با Stage 8.

### ۱. مسیر Build (طبق دستور: فقط Actions، هیچ Build محلی)

- Workflow موجود `android-debug.yml` بدون هیچ تغییری استفاده شد (`git status` در طول مرحله فقط فایل پیشرفت را نشان می‌دهد؛ workflow دست‌نخورده).
- push-trigger این workflow فقط به `integration/firefox-vpn-debug` است؛ مطابق رویه ثبت‌شده Performance Stage 8، اجرا از طریق **workflow_dispatch API روی ref شاخه کاری** انجام شد → **HTTP 204**.
- **Run**: `42869865882` — branch `feature/firefox-guardian-psiphon-bootstrap`، commit `332ff03` (= tip شاخه، شامل کد کامل Stage 2–7)؛ شروع 2026-11-10T17:55:23Z، پایان 18:13 UTC (~۱۸ دقیقه).
- **conclusion: success — هر ۵ job سبز**: Firefox engine (Go 1.25.0 — go vet + go test + ساخت سه ABI) | Native cores ×3 (arm64-v8a / armeabi-v7a / x86_64 — دستور فروزن native-ci) | DA debug APK (شامل flutter analyze + flutter test).

### ۲. تأیید CI (خود workflow به‌عنوان شاهد)

- `flutter analyze` → **«No issues found»** (لاگ job).
- `flutter test` → **«412 tests passed»** — شامل تمام تستهای Guardian Stage 1–7 (گواه مستقیم در لاگ job: تست UI «GUARDIAN-BOOTSTRAP STAGE 7 — the 451 region failure renders the honest failed surface…» و ۱۵۵ خط مرتبط guardian/bootstrap/psiphon).
- `go vet` + `go test` (فاز موتور، phase1/fxv) → PASS (job «Firefox engine»).

### ۳. اصلاح A1/CGO — حفظ شده (راستی‌آزمایی، نه تغییر)

- سه خط Build موتور از build-report خود CI:
  - `android/arm64-v8a: CGO_ENABLED=1 CC=aarch64-linux-android34-clang` (NDK r28c = 28.2.13676358)
  - `android/armeabi-v7a: CGO_ENABLED=1 CC=armv7a-linux-androideabi34-clang`
  - `android/x86_64: CGO_ENABLED=1 CC=x86_64-linux-android34-clang`
- gateهای بسته‌بندی خود workflow سبز: `zipalign -c -P 16` + `apksigner verify` + `aapt dump badging` + presence پنج کتابخانه در هر سه ABI + **byte-identity شش‌گانه libfirefoxvpn.so با خروجی Build در هر ABI** (sha256 داخل CI مقایسه شد).

### ۴. Artifact و راستی‌آزمایی مستقل (دانلود و بازبینی، نه Build)

| قلم | مقدار تأییدشده |
|---|---|
| Artifact | `AETHONE-DA-Firefox-Debug` (id `13790711461`) — از run `42869865882` در `CHAKCAAD/AETHONE` قابل دریافت؛ انقضا 2026-11-24T18:13:02Z (پنجره ۱۴روزه Actions) |
| APK | `AETHONE-DA-Firefox-Debug.apk` — 187,234,418 بایت (≈۱۷۸.۵ MB) |
| SHA256 (CI) | `7914908e916c74f489aff62f82950db84410301a811d7abbf4d700bb51ced93e` |
| SHA256 (بازمحاسبه مستقل در sandbox) | **یکسان** ✓ |
| اعتبار آرشیو | `unzip -t` → «No errors detected» ✓ |
| package ID | `com.chakcaad.aethone.da` (سافیکس `.da` در build.gradle — **کنار** نسخه اصلی `com.chakcaad.aethone` نصب می‌شود، جایگزین آن نمی‌شود) |
| ABIها | arm64-v8a + armeabi-v7a + x86_64 (universal — POCO X3 = arm64-v8a) |
| کتابخانههای Bootstrap در APK | `libaether.so` + `libpsiphon.so` + `libfirefoxvpn.so` + `liblyrebird.so` در هر سه ABI (۱۲/۱۲ موجود ✓) |
| امضا | debug-keystore (فقط نصب آزمایشی — release نیست) |
| Release عمومی | **ساخته نشد** (artifact صرفاً Actions با انقضا؛ طبق مأموریت) |
- «APK قبلی overwrite نشود»: artifact هر run در فضای خودش است (run قبلی Performance `42771904063` دست‌نخورده باقی است؛ نام artifact در workflow فروزن است و دستکاری آن تغییر غیرضروری workflow می‌شد).

### ۵. دستور نصب روی گوشی مالک (POCO X3، Android، arm64-v8a)

```bash
# 1) artifact را از Actions دانلود کنید (نیاز به لاگین GitHub):
#    https://github.com/CHAKCAAD/AETHONE/actions/runs/42869865882/artifacts/13790711461
#    (zip را باز کنید: AETHONE-DA-Firefox-Debug.apk + build-report.txt + SHA256SUMS.txt)

# 2) صحت فایل را تأیید کنید:
sha256sum AETHONE-DA-Firefox-Debug.apk
#    باید چاپ کند: 7914908e916c74f489aff62f82950db84410301a811d7abbf4d700bb51ced93e

# 3) گوشی را با USB debugging وصل کنید و نصب کنید:
adb devices
adb install -r AETHONE-DA-Firefox-Debug.apk
#    اگر قبلاً نسخه DA قدیمی (از run قبلی Performance) نصب بوده و خطای signature گرفتید
#    (debug-keystore در CI هر بار تازه است)، اول:
adb uninstall com.chakcaad.aethone.da
#    و دوباره adb install -r …

# نکته: پکیج DA (com.chakcaad.aethone.da) کنار اپ اصلی نصب می‌شود؛
# برچسب آن «AETHONE DA» است تا با نسخه اصلی اشتباه نشود.
```

### ۶. NOT TESTED (Stage 8)

- نصب و اجرای واقعی روی POCO X3 (موضوع Stage 9 — نیاز به گوشی مالک؛ ایجنت بدون دسترسی واقعی PASS اعلام نمی‌کند).
- رفتار ۴۵۱/Bootstrap روی شبکه ایران (Stage 9 سناریوهای B/C/F).
- مقایسه سطری build-report با artifactهای جانبی native (فقط گزارش اصلی و APK بازبینی شد؛ artifactهای engine/native برای عمق بیشتر در همان run موجودند).

---

## یافته‌های Stage 9 — اجرای میدانی ۱ (تحلیل لاگ گوشی مالک؛ 2026-11-11)

> ورودی: لاگ فیلترشده `connection-20261110-224329-filtered.log` (مالک؛ POCO X3). این اجرا فقط تحلیل شواهد است — هیچ سناریویی PASS اعلام نمی‌شود.

### ۰. پاسخ پرسش مالک («آیا مکانیزم اصلاً به بیلد اضافه شده؟») — **بله؛ سه گواهی مستقل**

1. **بستهٔ نصبی درست است**: نصب/به‌روزرسانی `com.chakcaad.aethone.da` (uid 10870) در `11-10 22:35:09` — همان APK آزمایشی Stage 8 (run `42869865882`، commit `332ff03`)؛ پروسه‌های بعدی با برچسب `1.2.0-phaseb`.
2. **کد Stage 6 واقعاً روی گوشی اجرا می‌شود**: سه رشتهٔ `guardian-renewal: session attached direct` / `guardian-renewal: engine gone — teardown owns the release; the expiry backstop stays armed` / `guardian-renewal: session torn down — backstop cancelled` فقط در `guardian_renewal_policy.dart` (Stage 6) وجود دارند و در لاگ ظاهر شده‌اند — با semantics درست (spawn مستقیم → attach بدون پراکسی؛ مرگ موتور → backstop مسلح؛ teardown → لغو).
3. **کد Stage 5 در همان سورس بیلد حاضر است**: بلاک escalation در `_connectFirefox` (شرط `failCode == guardianRegionUnavailable && apiProxy.isEmpty && attempt == 0`) در commit `332ff03` موجود است (HEAD فعلی `c3ca2a9` فقط دو commit مستندات بالاتر است).

پس «مکانیزم در بیلد نیست» **رد شد**. آنچه اجرا نشد **تریگر** است (بند ۲).

### ۱. شواهد زمانی: مرگ موتور دقیقاً روی تایم‌اوت dial کنترل‌پلن (۱۵ ثانیهٔ pin)

| تلاش | engine: started | engine failed (timeout) | طول |
|---|---|---|---|
| ۱ | 22:37:26.660 | 22:37:42.021 | 15.36s |
| ۲ | 22:41:55.124 | 22:42:10.297 | 15.17s |
| ۳ | 22:43:30.980 | 22:43:46.329 | 15.35s |

- pin `firefox-vpn-client/http_client.go`: `controlPlaneDialTimeout = 15 * time.Second` (سقف TCP connect + handshake uTLS برای FxA/Guardian/Remote Settings) — تطابق کامل سه تلاش.
- پیام روی سیم = پیام استاتیک `fferr.CodeTimeout` («The server took too long to respond»؛ classify.go L67)؛ طبقه‌بندی از `net.Error.Timeout()` / `DeadlineExceeded` (classify.go L108-116) — یعنی **شکست در سطح transport، بدون هیچ پاسخ HTTP**.
- متن UI همان کلاس timeout است («The account server took too long to respond») — ارور گزارش‌شدهٔ مالک.

### ۲. چرا Bootstrap اجرا نشد — زنجیرهٔ علّی کامل

1. walk مرحله ۵ عمداً مستقیم‌اول است: spawn بدون `apiProxy` (درست طبق مأموریت؛ مستقیم در اولویت). `guardian-renewal: session attached direct` هم دقیقاً همین را تأیید می‌کند.
2. موتور pin در runTunnel اول `FetchServerList` (Remote Settings: `firefox.settings.services.mozilla.com/v1/buckets/main/collections/vpn-serverlist/records`) و بعد `AcquireInitialPass` (`GET <guardian>/api/v1/fpn/token`) را می‌زند — هر دو مستقیم.
3. روی این شبکه، dial مستقیم به endpoint کنترل‌پلن **بی‌پاسخ ماند (blackhole)** → ۱۵ث → failCode=`timeout`.
4. شرط escalation فقط `guardianRegionUnavailable` (451 واقعی) را می‌پذیرد → `timeout ≠ 451` → مسیر «شکست صادقانهٔ pre-Stage-5» → `fail('firefoxTransport:timeout')`.
5. منیجر هرگز صدا زده نشد → در کل لاگ **صفر** خط `guardian bootstrap:` (fast path / activating / all routes failed)؛ صفر نشانهٔ Psiphon از پروسهٔ AETHONE (psiphonهای موجود در لاگ متعلق به اپ‌های دیگر گوشی‌اند؛ یک `libpsiphon.so/u0a864` در 22:22 مربوط به walk عادی aether اپ اصلی بود) — دقیقاً مشاهدهٔ مالک: نه ListeningSocksProxyPort، نه PSIPHON ONLY، نه AETHER→PSIPHON.
6. Fast Path هم هرگز eligible نیست (حافظهٔ مسیر شاهد 451 می‌خواهد؛ هیچ 451 واقعی هرگز دیده نشد).

### ۳. یافتهٔ میدانی کلیدی: بلاک منطقه‌ای این‌بار Blackhole است، نه 451

- پیش‌فرض مأموریت (و طراحی Stage 1–5) بر «Guardian با HTTP 451 جواب می‌دهد» بود. در این اجرای میدانی **هیچ پاسخ HTTP‌ای** از پای کنترل‌پلن مستقیم برنگشت — اتصال در سطح TCP/uTLS بلعیده شد.
- FxA در همین پنجره از همین شبکه پاسخ می‌داد (خطاهای HTTP 400 errno 138 واقعی در 22:36:47–22:37:02 و mint موفق توکن‌ها در 22:37:06) → **ورود حساب در این لاگ کامل شد**؛ کندیِ چندتلاشی بود، نه بن‌بست (با گفتهٔ مالک دربارهٔ تحریم ورود، سازگار — فعلاً خارج از محدوده).
- **باز ماند (از این لاگ قابل تعیین نیست)**: پای مرده Remote Settings است یا Guardian — زنجیرهٔ خام فقط به diagnostics (redact) می‌رود و `discoveryFetched` لاگ عمومی ندارد. **فیک باید هر دو را پوشش دهد.**
- مورد جانبی 172.19.0.2: اعتبارسنجی Private DNS اندروید با DNS داخلی VPN — شبکه بعداً validated شد؛ **عامل Timeout نیست** (تشخیص مالک تأیید شد).

### ۴. طرح اصلاح پیشنهادی — نیازمند تصویب مالک (دو تغییر صریح نسبت به متن مأموریت)

1. **تریگر**: شکست transport-level `timeout` در تلاش مستقیم نیز evidence قابل escalation شود (در کنار 451؛ در صورت تأیید مالک: `networkUnreach`/`dns` هم). همان‌ها: سقف یک‌بار در هر walk، verify واقعی از مسیر پراکسی (بدون موفقیت کاذب)، cooldown/حافظهٔ مسیر. دلیل: شواهد بند ۳ — بلاک عملاً blackhole است.
2. **دامنهٔ allowlist**: اگر پای مرده Remote Settings باشد، respawn با apiProxy باز در `FetchServerList` می‌میرد (allowlist فعلی فقط endpoint توکن Guardian را پراکسی می‌کند). گزینه‌ها: (الف) افزودن همان یک GET عمومی server-list به allowlist فقط هنگام bootstrap فعال؛ (ب) fallback کش لیست سرور. انحراف از قید «فقط Guardian» — تصمیم با مالک.
3. **لاگ تشخیصی**: یک خط engine-level (بدون URL/توکن) که اعلام کند کدام پا مُرد (discovery vs pass) — تا ابهام بند ۳ در اجرای بعدی رفع شود.

### ۵. نتیجهٔ Stage 9 اجرای میدانی ۱: **PARTIAL**

- سناریو A (Guardian مستقیم): اجرا شد — نتیجه: **timeout سطح transport** (نه 451). یافتهٔ بالا ثبت شد.
- سناریوهای B–F: **شروع نشدند** (تریگر 451 هرگز رؤیت نشد) — NOT TESTED صادقانه.
- جمع‌بندی: مکانیزم حاضر/وصل، اما طراحی تریگر 451-only با رفتار واقعی شبکه (blackhole) قابل شروع نیست. اصلاح بند ۴ در انتظار تصمیم مالک.

### ۶. NOT TESTED (اجرای میدانی ۱)

- پایداری الگوی blackhole-vs-451 در ساعات/شبکه‌های دیگر (رفتار مسدودسازی ناپایدار است).
- کدام پای کنترل‌پلن (Remote Settings/Guardian) دقیقاً بی‌پاسخ می‌ماند (نیاز به لاگ بند ۴-۳).
- عملکرد واقعی bootstrap در این شبکه (چون هرگز تریگر نشد).

---


## Stage 9.1 — failure-stage instrumentation (2026-11-11; owner approved)

### تصمیم و محدوده

مالک معماری ترکیبی Guardian + Firefox Account را تأیید کرد. طبق قاعده توقف مرحله‌ای، این commit فقط مرحله تشخیصی را انجام می‌دهد تا پیش از تغییر تریگر یا routing، محل دقیق Timeout در موتور قابل مشاهده شود.

- فیلد اختیاری و additive با نام `failureStage` به رویداد `failed` افزوده شد؛ این فیلد فقط نام ثابت مرحله را حمل می‌کند و هیچ URL، متن خطای خام، توکن یا داده حسابی ندارد.
- مقدارهای ثبت‌شده در walk اصلی:
  - `remoteSettingsDiscovery`: شکست `FetchServerList` از Remote Settings.
  - `guardianPass`: شکست `AcquireInitialPass` / درخواست دریافت مجوز Guardian.
  - `upstreamSession`: شکست ایجاد نشست بالادستی پس از دریافت مجوز.
  - همچنین شکست‌های داخلی تنظیم transport، انتخاب سرور، SOCKS و renewal نیز stage ثابت خود را دارند.
- parser دارت مقدار را به‌صورت tolerant می‌خواند؛ مقدار غایب در نسخه‌های قدیمی و مقدار با نوع اشتباه به رشته خالی تبدیل می‌شود.
- `FirefoxEngineOutcome` مقدار را حفظ می‌کند تا مرحله بعد بتواند بدون تجزیه متن خطا درباره escalation تصمیم بگیرد.
- تست Go قرارداد JSON و حذف فیلد خالی را بررسی می‌کند؛ تست Flutter هم parse، عبور از outcome پردازش فرزند و سازگاری با پیام قدیمی را پوشش می‌دهد.

### چیزهایی که عمداً تغییر نکردند

- **هیچ timeout سه‌ثانیه‌ای اضافه نشد.**
- هیچ خطای transport هنوز باعث شروع Psiphon نمی‌شود.
- allowlist فعلی Guardian دست‌نخورده است؛ Remote Settings هنوز مستقیم می‌رود.
- WebView و `--login` هنوز به Psiphon متصل نشده‌اند.
- ترتیب routeها، حافظه مسیر، UI، token handling و native core تغییر نکردند.
- نه APK ساخته شد و نه تست دستگاه انجام شد؛ تأیید build/test به اجرای CI روی همین commit وابسته است.

### معیار پذیرش

1. Go: `go vet ./...` و `go test ./...` سبز.
2. Flutter: `flutter analyze` و `flutter test` سبز.
3. در خروجی جدید، failure ناشی از Remote Settings باید `failureStage=remoteSettingsDiscovery` و شکست Guardian باید `failureStage=guardianPass` داشته باشد.
4. نبود فیلد در event قدیمی نباید crash یا تغییر رفتار ایجاد کند.

### مرحله بعد

پس از عبور CI، APK آزمایشی جدید فقط برای جمع‌آوری لاگ stage روی دستگاه استفاده می‌شود. سپس بر اساس شواهد واقعی تصمیم نهایی درباره فعال‌کردن fallback برای Timeout و نیاز یا عدم نیاز به عبور Remote Settings از bootstrap گرفته می‌شود. تا پیش از آن هیچ‌کدام از این دو رفتار تغییر نمی‌کند.

---


## Stage 9.2 — Direct timeout escalation + selected Aether/Psiphon chain (2026-11-11)

### تصمیم اجرایی و وضعیت کد

این مرحله برای پوشش رفتار واقعی مشاهده‌شده در POCO X3 انجام شد: کنترل‌پلن مستقیم به‌جای پاسخ HTTP 451، در سطح transport بدون پاسخ می‌ماند. بنابراین علاوه بر 451 واقعی Guardian، فقط خطاهای transport بدون پاسخ در دو مرحله مشخص نیز واجد شرایط Bootstrap هستند.

### ترتیب اتصال نهایی

1. **Direct first:** موتور Firefox ابتدا بدون Psiphon اجرا می‌شود. در Go، Remote Settings server-list discovery ابتدا با context مستقیم مستقلِ حداکثر ۴ ثانیه اجرا می‌شود. اگر موفق شد، دریافت مجوز اولیه Guardian یک context تازه با ۴ ثانیهٔ کامل می‌گیرد؛ زمان مصرف‌شده در discovery از فرصت Guardian کم نمی‌شود. این deadline واقعی HTTP است، نه صرفاً تایمر UI.
2. **Psiphon Standalone:** در صورت Guardian HTTP 451 معتبر یا خطای transport بدون پاسخ در `remoteSettingsDiscovery` یا `guardianPass`، موتور مستقیم متوقف می‌شود و شاهد خطای همان تلاش فقط یک‌بار به manager داده می‌شود. مسیر Standalone با بودجهٔ readiness سی‌ثانیه‌ای شروع می‌شود. Ready فقط با probe کامل SOCKS5، CONNECT دامنه‌ای (DNS از داخل تونل) و HTTPS/TLS با اعتبارسنجی گواهی پذیرفته می‌شود؛ بازبودن پورت به‌تنهایی کافی نیست. سپس همان مجوز واقعی Guardian از مسیر پراکسی درخواست می‌شود.
3. **Aether → Psiphon:** اگر Standalone در بودجه آماده نشود یا مجوز واقعی Guardian از آن مسیر دریافت نشود، پراکسی Standalone پاک‌سازی می‌شود و manager ترکیب موجود هسته Aether → Psiphon را راه می‌اندازد. این ترکیب پیاده‌سازی پروتکل جدید نیست؛ همان mode و argument builder هسته اصلی استفاده می‌شود. بودجهٔ پیش‌فرض readiness ترکیب ۳۳۰ ثانیه است و مسیر خروجی همان listener زنجیره است.

### حفظ پروتکل انتخاب‌شده کاربر

- provider در `PlatformEngineAdapter` مقدار فعلی `coreSettings.psiphonLegProtocol` را از config فعال می‌خواند؛ بنابراین مقدار ذخیره‌شده در تنظیمات Psiphon به سازندهٔ chain می‌رسد.
- نگاشت از `AetherArguments.legProtocolId` و `PsiphonBootstrapProxy.warpProtocolArgs` استفاده می‌کند و با `AetherArguments.protocolArgs(..., ProtocolId.psiphonChain)` هم‌ارز است.
- نمونه: انتخاب MASQUE به `--protocol masque` در leg اول Aether تبدیل می‌شود؛ سپس Psiphon روی SOCKS همان leg سوار می‌شود. WireGuard/GOOL/GOOL Classic/MIM نیز از نگاشت واقعی هسته عبور می‌کنند. مقدار کاربر به WireGuard یا مقدار دیگری بازنویسی نمی‌شود.
- در صورت نبود provider در یک integration آزمایشی، fallback پیش‌فرض سازنده هنوز WireGuard است؛ در production provider تنظیمات فعال را تزریق می‌کند. تست جدید mapping همه گزینه‌های ذخیره‌شده را پوشش می‌دهد.

### دامنهٔ پراکسی و خطاهای مجاز

در درخواست‌های Bootstrap، allowlist فقط این دو GET را از پراکسی محلی عبور می‌دهد:
- Guardian: `GET /api/v1/fpn/token` روی host واقعی Guardian پیکربندی‌شده.
- Remote Settings: فقط GET مجموعهٔ `main/vpn-serverlist/records` روی origin ثابت Mozilla.

FxA و سایر endpointهای Guardian/Remote Settings همچنان مستقیم می‌مانند. خطاهای HTTP دارای پاسخ از جمله 401/403، 429، validation و سایر پاسخ‌های application/server trigger این fallback نیستند. شرط transport trigger مستلزم `httpStatus == 0`، stage برابر `remoteSettingsDiscovery` یا `guardianPass` و کد timeout/DNS/networkUnavailable است.

### حافظهٔ مسیر و چرخهٔ عمر

- فقط routeای که readiness کامل و دریافت مجوز واقعی Guardian را با موفقیت طی کرده باشد، می‌تواند Fast Path شود.
- برای دور بعد، Fast Path فقط با route معتبر در همان network context و شاهد تازهٔ Direct 451 یا transport-blackhole فعال می‌شود؛ شواهد به‌تنهایی کافی نیستند و TTL/cooldown همچنان اعمال می‌شوند.
- اگر Fast Path واجد شرایط نباشد، Direct دوباره اولویت دارد.
- شکست readiness یا authorization باعث teardown route جاری و رفتن به route بعدی می‌شود؛ stop/cancel و محدودیت هم‌زمانی user Aether walk همچنان رعایت می‌شوند.
- توکن‌ها همچنان فقط از stdin خصوصی موتور عبور می‌کنند و در لاگ/argv/environment قرار نمی‌گیرند.

### تغییرات این commit کد (`1759bac`)

- پیام log علت escalation را بین Guardian HTTP 451 و transport-unavailable تفکیک می‌کند.
- توضیحات manager و engine seams با رفتار واقعی transport fallback و Remote Settings allowlist همگام شده‌اند.
- تست manager: transport blackhole → شکست readiness در Standalone → موفقیت Aether/Psiphon chain → ذخیرهٔ route → Fast Path زنجیره در تلاش بعدی.
- تست route memory: transport evidence به‌تنهایی Fast Path نمی‌سازد؛ route باید قبلاً کاملاً تأیید شده باشد و TTL معتبر بماند.
- تست protocol: هر مقدار `AetherLegProtocol` از تنظیمات به argumentهای chain نگاشت می‌شود؛ MASQUE به‌طور مشخص `--protocol masque` را می‌دهد.
- تست engine seam: timeout در Remote Settings و Guardian با status صفر eligible است؛ HTTP 401 با وجود stage Guardian eligible نیست.
- تست Go جدید: اگر Remote Settings دو ثانیه از بودجه‌اش را مصرف کند، Guardian همچنان context مستقل چهارثانیه‌ای می‌گیرد؛ مسیر پروکسی‌شده deadline مشترک ۵۵ثانیه‌ای خود را حفظ می‌کند.
- خطای کامپایل CI قبلی (`undefined: fferr` در `guardianprobe.go`) با import صریح `internal/fferr` در commit `410de85` اصلاح شد.

### گیت تأیید — هنوز انجام نشده

- Commit سخت‌سازی کد `1759bac32b3535e2e0d15ca02dced8404c8aea95`، اصلاح import `410de854847775c4826c2e2cfd823a7d3a37d618` و اصلاح بودجه‌های مجزای Direct `0a9e7e1dea51e3cea7f63f5503f963fa6975f374` ثبت شده‌اند.
- **CI هنوز تأیید نشده است.** run #7 روی SHA قدیمی‌تر به‌خاطر import جاافتادهٔ `fferr` در مرحلهٔ `go vet` شکست خورد؛ اصلاح در `410de85` ثبت شد. run #10 با شناسهٔ `43029425484` روی commit بودجهٔ مستقل `0a9e7e1` در آخرین مشاهده pending بود. تست‌های Go/Flutter یا APK هنوز PASS اعلام نمی‌شوند.
- **APK جدید هنوز آماده نیست.** run #10 باید پس از خروج از صف اجرا و با conclusion=success تمام شود تا Artifact آن قابل نصب باشد. run قبلی #6 با SHA `218f42c` قدیمی است.
- نصب، اتصال واقعی و بررسی خروجی روی POCO X3 انجام نشده است؛ تا آن زمان عملکرد شبکه‌ای نهایی NOT VERIFIED باقی می‌ماند.

---
## دستور دقیق ادامه کار (پس از Stage 9.2)

1. HEAD شاخه `feature/firefox-guardian-psiphon-bootstrap` را بررسی کن؛ commitهای کد `1759bac`، `410de85` و `0a9e7e1` باید در تاریخچهٔ آن باشند.
2. push روی همین feature branch workflow شمارهٔ 412045413 را خودکار اجرا می‌کند؛ آخرین اجرا در زمان این گزارش #10 (`43029425484`) است.
3. نتیجهٔ run باید success باشد و Artifact ساخته شود؛ SHA run باید همین HEAD یا commit مستندات فرزند آن باشد.
4. فقط Artifact همان run موفق را نصب کن؛ APK اجرای شمارهٔ 6 (`218f42c`) قدیمی است.
5. روی POCO X3 لاگ کامل بگیر و بررسی کن: Direct start، علت escalation، آماده‌شدن یا timeout مسیر Standalone، انتخاب chain، `passAcquired` و SOCKS readiness.
6. تا دریافت شواهد دستگاه، اتصال واقعی و عبور ترافیک را PASS اعلام نکن. به default branch، شاخه integration یا Release دست نزن.

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
| 5 — کد+مستندات | `c8e62b6` | feat(guardian): routing roundtripper — guardian-only selective control plane (stage 5) — شامل بخش Stage 5 این فایل + به‌روزرسانی وضعیت/نقشه/دستور Stage 6 |
| 6 — کد+مستندات | `2c31cba` | feat(guardian): renewal lifecycle — expiry-based bootstrap release policy, renewal event plumbing, quota outcome mapping (stage 6) — شامل بخش Stage 6 این فایل + به‌روزرسانی وضعیت/نقشه/دستور Stage 7 |
| 6 — پین هش | `d36cf1e` | docs(guardian-bootstrap): pin the stage-6 commit hash in the progress table |
| 7 — کد+مستندات | `efe707a` | test(guardian): comprehensive coverage + data-plane separation proof (stage 7) — تست تفکیک Data Plane در Go، تستهای UI/l10n در Flutter، تکمیل l10n کلاسهای Stage 6، جدول پوشش رسمی این فایل |
| 7 — پین هش | `332ff03` | docs(guardian-bootstrap): pin the stage-7 commit hash in the progress table |
| 8 — مستندات | `278b1a1` | docs(guardian-bootstrap): stage 8 — trial build report via Actions run 42869865882 (sha256 verified, package id .da, engines 12/12, install commands) |
| 9 — اجرای میدانی ۱ (تحلیل لاگ) | `3bcf278` | docs(guardian-bootstrap): field run 1 — mechanism present, but the 451-only trigger did not fire because the network blackholed the direct control-plane dial |
| 9.1 — کد + تست + گزارش | `21cc5ad` | feat(firefox): add optional failureStage diagnostics for Remote Settings, Guardian pass and upstream session; no routing/timeout behavior changed |
| 9.1 — اصلاح جزئی + پین | `218f42c` | fix(test): wait for the child stdout pipe to flush; tag config failures; pin the Stage 9.1 implementation SHA |
| 9.2 — کد + تست سخت‌سازی | `1759bac` | test(firefox): harden direct-timeout and selected Psiphon fallback (transport escalation, Standalone→selected chain, route Fast Path, settings→protocol mapping, HTTP non-trigger tests) |
| 9.2 — اصلاح compile | `410de85` | fix(firefox): import transport error classifier in Guardian probe (fixes CI go vet undefined fferr) |
| 9.2 — deadline مستقل | `0a9e7e1` | fix(firefox): give Direct Guardian its own four-second window (separate 4s Remote Settings and Guardian contexts; shared 55s proxied budget; Go tests) |
| CI feature branch | `b25e61a` | ci(android): include the Guardian/Psiphon feature branch in push builds; Actions run #7 queued (`43028323588`) |

*(Token دسترسی در متن مأموریت مالک تأمین می‌شود؛ در این فایل ذخیره نشده است.)*
