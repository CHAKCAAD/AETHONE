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
| مرحله فعلی | **Stage 1 — تشخیص دقیق خطای Guardian (451) و مسیر درخواست** |
| مرحله تکمیل‌شده آخر | **Stage 0 — PASS (بررسی معماری؛ بدون تغییر کد — این فایل)** |
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

---

## دستور دقیق ادامه کار (جلسه بعدی — Stage 1)

1. همین فایل را بخوان؛ `git -C <repo> log --oneline -3` و `git status` (باید HEAD = commit مستندات Stage 0 و working tree پاک باشد؛ شاخه `feature/firefox-guardian-psiphon-bootstrap` از `ce852ea`).
2. **فقط Stage 1 را اجرا کن** — تشخیص دقیق خطای Guardian و مسیر درخواست:
   - هدف: فقط 451 معتبر از endpointهای Guardian (`/api/v1/fpn/*` روی host پیکربندی‌شده) باید مسیر bootstrap را فعال کند؛ 401/403/429/5xx/خطای شبکه هرگز.
   - کار: (الف) کد fferr جدید (مثلاً `CodeGuardianRegionUnavailable`/"guardianRegionUnavailable") برای 451 در `ClassifyHTTP` یا نقطه دقیق‌تر `classifyGuardian` (فقط برای GuardianHTTPError با status 451؛ body برای تشخیص `unavailable_in_region` در دسترس است اما status خودش کافی و پایدارتر است — تصمیم با شواهد تست upstream)؛ (ب) انتقال به Dart (`firefox_errors.dart` + mapping) با httpStatus حفظ‌شده؛ (ج) تست‌های Go: 451→کد جدید؛ 401/403→sessionRejected؛ 429→quota؛ 5xx→serverRejection retryable؛ شبکه→transport classes؛ (د) تست Dart برای mapping جدید؛ (هـ) هیچ توکن/لاگ حساس.
   - قواعد: تغییر حدسی نکن؛ تست قبل/بعد؛ commit مستقل با نام منطبق (مثلاً `feat(firefox): classify guardian HTTP 451 as region-unavailable`)؛ push به همین شاخه؛ به‌روزرسانی همین فایل؛ گزارش ۹-بندی؛ توقف.
3. قوانین ثابت: فقط مخزن `CHAKCAAD/AETHONE`؛ بدون Force Push/Release/تغییر pinها (upstream firefox `55ad91a2…`، Aether `d58f9d56…`، psiphon fork `2956a96b…`)؛ CGO/A1 دست‌نخورده؛ معماری Child Process/stdin-JSON حفظ؛ برای فایل‌های Go با tab-indent فقط اسکریپت python (قانون تجربه‌شده مأموریت قبل).

---

## گیت مراحل

| مرحله | Commit | عنوان |
|---|---|---|
| 0 — مستندات | (پس از commit این جلسه تکمیل می‌شود) | docs(guardian-bootstrap): stage 0 — architecture audit (guardian control-plane seam, psiphon local-proxy/chain mechanics, combination map, no-mask finding) |

*(Token دسترسی در متن مأموریت مالک تأمین می‌شود؛ در این فایل ذخیره نشده است.)*
