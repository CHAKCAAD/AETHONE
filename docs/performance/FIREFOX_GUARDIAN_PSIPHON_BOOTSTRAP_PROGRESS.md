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
| مرحله فعلی | **Stage 3 — ترکیب واقعی AETHER → PSIPHON (بدون TUN/VpnService)** |
| مرحله تکمیل‌شده آخر | **Stage 2 — PASS (پراکسی محلی مستقل Psiphon؛ کد `b88b423` + مستندات همین commit)** |
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
| مدیر Bootstrap مستقل Psiphon (Stage 2) | `lib/connection/firefox/psiphon_bootstrap.dart` (PsiphonBootstrapProxy + SocksTlsReadyProbe + buildArgs) + `test/psiphon_bootstrap_test.dart` |
| طبقه‌بندی 451 Guardian (Go) | `phase1/fxv/internal/fferr/classify.go` (ClassifyGuardian) + `cmd/libfirefoxvpn/main.go` (classifyGuardian) + `internal/upstream/controller.go` (renewalFailCode) |
| مدل خطای Dart + متنها | `lib/connection/firefox/firefox_errors.dart` + `lib/connection/firefox/firefox_protocol.dart` + `lib/l10n/app_strings.dart` (firefoxErrGuardianRegion) |

---

## دستور دقیق ادامه کار (جلسه بعدی — Stage 3)

1. همین فایل را بخوان؛ HEAD باید commit مستندات Stage 2 باشد و working tree پاک (شاخه `feature/firefox-guardian-psiphon-bootstrap` شامل کد Stage 2).
2. **فقط Stage 3 را اجرا کن** — ترکیب واقعی AETHER → PSIPHON برای Bootstrap:
   - مبنای سورس: `run_chain` (psiphon.rs L940-968): هسته ابتدا listener `--psiphon-bind` را از ابتدا bind می‌کند، `wait_for_proxy(through)` صبر می‌کند تونل WARP (listener `--bind`) جواب بدهد، بعد psiphon را با `UpstreamProxyURL=socks5://<through>` روی آن اجرا می‌کند و خروجی relay روی `--psiphon-bind` است.
   - برای Bootstrap: پورتهای موقت/ephemeral برای هر دو listener (همان الگوی pre-bind مرحله ۲؛ بدون تداخل با 1819/1820/1821/1822)؛ Data Directory همان مسیر اختصاصی bootstrap؛ پروتکل پایه WARP طبق پیش‌فرض/انتخاب کاربر بدون تغییر walk اصلی.
   - **بدون** TUN و **بدون** VpnService دوم (تأیید شده در Stage 0/2: FFI درون‌فرایندی).
   - اثبات مسیر (۳-۶): با upstream/Listenr قابل کنترل ثابت کن psiphon واقعاً از SOCKS هسته dial می‌زند (نه مستقیم)، relay خروجی صحیح است، هیچ loop وجود ندارد (`AETHER→PSIPHON→AETHER` ممنوع — سه آدرس متمایزند).
   - گسترش `PsiphonBootstrapProxy` (حالت ترکیبی جدید در همان مدیر — `psiphonOnly` → `aetherPsiphonChain`) یا کلاس خواهر؛ API سطح Stage 2 نباید بشکند.
   - تست: Dart lifecycle + اثبات مسیر با fake؛ اجرای واقعی روی شبکه در صورت دسترسی، وگرنه NOT TESTED صریح.
   - قواعد ثابت: تغییر حدسی نکن؛ pinها دست‌نخورده؛ commit مستقل؛ push به همین شاخه؛ به‌روزرسانی همین فایل؛ گزارش ۹-بندی؛ توقف.
3. قانون توقف: بعد از Stage 3 متوقف شو؛ مرحله ۴ (Bootstrap Strategy Manager) در اجرای بعدی.

---

## گیت مراحل

| مرحله | Commit | عنوان |
|---|---|---|
| 0 — مستندات | `8a54a1b` | docs(guardian-bootstrap): stage 0 — architecture audit (guardian control-plane seam, psiphon local-proxy/chain mechanics, combination map, no-mask finding) |
| 1 — کد | `2c04f5a` | feat(firefox): classify guardian HTTP 451 as region-unavailable |
| 1 — مستندات | `caac298` | docs(guardian-bootstrap): stage 1 — 451 classification report, transport scope, port map (pins `2c04f5a`) |
| 2 — کد | `b88b423` | feat(psiphon): standalone guardian-bootstrap local proxy (stage 2) |
| 2 — مستندات | (tip شاخه پس از همین فایل) | docs(guardian-bootstrap): stage 2 — standalone proxy report (pins `b88b423`) |

*(Token دسترسی در متن مأموریت مالک تأمین می‌شود؛ در این فایل ذخیره نشده است.)*
