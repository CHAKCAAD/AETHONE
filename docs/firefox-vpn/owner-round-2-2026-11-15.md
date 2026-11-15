# Owner round 2 — the visual fixes, the login fix, the guardian-line merge (2026-11-15)

Owner decrees this mission answers:

1. «در صفحه تنظیمات قسمت آدرس هسته ها رو به صغحه تنطیمات عمومی انتقال
   بده و آدرس هسته هارو هم درونش قرار بده» — the core-addresses
   section moves to the general settings page, the addresses inside it.
2. «در صفحه تنظیمات آیکون فایرفاکس در حالت دارک مود باید سفید باشد
   و در حالت لایت مود باید مشکی باشد» — the Firefox mark follows the
   theme ink.
3. «در صفحه تظیمات قسمت سمت چپ کارت فایرفاکس خالی هست … مقدار حجم
   باقی مانده سرویس فایرفاکس را نشان دهد، اگر نامحدود بود باید
   نامحدود نمایش داده شود» — the settings pill's left slot.
4. «در صفحه انتخاب پروتکل قسمت سمت راست کارت فایرفاکس خالی هست …» —
   the protocol page's Firefox card right slot.
5. «همچنین صغحه ورود به حساب کاربری فایرفاکس مشکل داره و بالا
   نمیاد در صورتی که وقتی یک فیلترشکن دیگه روشن میکنی به راحتی
   بالا میاد … ممکنه مشکل از dns باشه یا سیستم تشخیص ربات فستلی» —
   the login page must come up WITHOUT any other VPN (the arman-vpn-
   client reference named by the owner).
6. «این پروژه امکانات دیگه ای هم داره که قبلا در یکی از برنچ های
   اپمون اضافشون کردیم باقی برنچ ها رو هم بررسی کن و اون امکانات
   رو اضافه کن» — the other branches' features ported.

Branch: `fix/owner-round-2`, cut from `feature/firefox-over-warp`
(`9a994da`) with **feature/firefox-guardian-psiphon-bootstrap**
(`d28dbbf`, 131 commits) merged in — the guardian line's engine is the
converged implementation of the same owner decrees.

## 1. The guardian-line merge (fix 6)

The guardian branch ended in the SAME posture as the warp line —
Firefox carried by the in-process Aether core — but with capabilities
the warp line lacked. Merged (engine contract **1.5.0**):

* `internal/dnsresolver` — the process-local resolver policy (system |
  DoH: Cloudflare / Google / Quad9 / custom endpoint + bootstrap IPs),
  installed by the tunnel, `--login`, `--discover` and `--webview-proxy`
  roles before any network work. NEVER touches Android Private DNS or
  the other cores.
* `--webview-proxy` — the loopback CONNECT proxy for the sign-in WebView
  (443-only, private/loopback destinations refused, 32-conn cap, stdin
  EOF = shutdown).
* the single `upstreamSocks` seam (`upstream/socks5.go` +
  `controlplane_socks.go`) replacing 1.4.0's apiProxy + upstreamProxy
  pair: TCP CONNECT carries h2, **UDP ASSOCIATE carries h3** — the h2/h3
  transport picker is restored on the Firefox settings page.
* the Android child-PID hardening (`setFirefoxPid` + /proc cmdline
  verification before SIGTERM, no hidden APIs).
* the Firefox settings page: the DNS section (mode, provider, custom
  endpoint, bootstrap, the DNS probe test button), the carrier section
  under its honest name, the transport section.

Merge resolution (the record): the warp line's owner-round UI fixes
(every launchable app in the picker, the section order, the Turkmen
locale) and walk decisions (fail-fast session check, the Windows tunnel
limit lifted, the bind-race guard, readyBudget probe) kept; the engine
seams take the guardian side; `app_strings` unions both sets (the
guardian branch's CI-breaking EN apostrophe syntax bug fixed — that was
the only reason its build was red); the 1.4.0 `internal/carrier`
package retired (superseded by the socks5 seam; history at `9a994da`).

## 2. The login fix (fix 5) — the WARP-carried sign-in

The owner's evidence: the page loads fine behind another VPN. The
blocked-region failure modes are DNS poisoning, SNI/IP blocking and the
Fastly edge's region-keyed bot defense — none of which a DIRECT
WebView (or a direct DNS-aware proxy) survives. The fix applies the
owner's own tunnel decree to the one-time sign-in («ابتدا به وارپ
متصل بشه و بعد فایرفاکس»):

1. The login screen boots the **login carrier** — the plain WARP leg
   (the per-Firefox core-protocol pick), no TUN, no VPN permission, no
   session: just the in-process Aether core's loopback SOCKS listener,
   listener-waited AND end-to-end probed exactly like the tunnel walk.
   A live session's core is probed and REUSED, never replaced.
2. The `--webview-proxy` child gets the carrier on its stdin line
   (`upstreamSocks`, loopback-only, fail-closed) — its CONNECT targets
   dial through the carrier **BY HOSTNAME** (socks5h semantics: the
   WARP leg resolves the name remotely and carries the traffic, so a
   poisoned local resolver, an SNI/IP block and the region-keyed bot
   defense are all bypassed at once).
3. AndroidX `ProxyController` routes the app's WebView through the
   loopback proxy (installed only after the listener is ready).
4. The `--login` token exchange rides the SAME carrier
   (`LoginConfig.upstreamSocks` → the SOCKS control-plane transport
   with the uTLS Firefox ClientHello kept — the Fastly edge sees the
   WARP egress, not the blocked region's).
5. Honest degradation: if the carrier cannot come up (no network, WARP
   itself blocked), the screen falls back to the guardian branch's
   direct DNS-aware proxy — the page still loads wherever the block is
   DNS-only. Never a fake page. The status strip says «در حال اتصال…»
   while the carrier boots.

## 3. The remaining-data slots (fixes 3 + 4)

The source: Guardian's quota headers (X-Quota-Limit / -Remaining /
-Reset) ride the upstream's ProxyPassInfo; the engine now emits them
with `quotaMax` beside quotaLeft/quotaReset on every passAcquired /
renewed event (1.5.0). The Dart side parses with ARMAN's ProxyUsage
semantics adapted: both counts present → metered (remaining shown);
BOTH empty → the account carries no metered quota → «نامحدود»;
garbage → unknown («—», never a made-up number). The last known value
is persisted (`firefox.quota`) so the cards survive a restart.

* Settings page (fix 3): the Firefox pill's visual-LEFT slot — the
  muted label over the accent-green value, the page's own card grammar,
  theme-aware both modes (the pill's texts hug the logo at the right
  edge; the left half was dead space on the full-width row).
* Protocol page (fix 4): the Firefox card's visual-RIGHT block — the
  account chip's twin (sheetSubtile fill, r14, the label over the
  value), legible on the dark card AND the selected green tile.

## 4. The visual fixes (fixes 1 + 2)

* Fix 1: «آدرس هسته ها» moved from the settings main page into
  «تنظیمات عمومی» — and the addresses now RIDE the rows: Zeptun Tunnel
  → `Noisemux/zeptun`, Aether Core → `CluvexStudio/Aether`, each
  opening its repository externally (the About-card link precedent).
* Fix 2: the Firefox pill's monochrome mark renders with the theme ink
  (`AethColors.textPrimary` — white at night, `#141C16` in light mode,
  riding the 420 ms mode tween); the ProtocolGlyph rule, applied to the
  one surface that still rendered the raw default-black file.

## Verification

* Go (phase1/fxv, Go 1.25.0): `go vet ./...` clean; `go test ./...` —
  **all packages green**, including the new
  `TestWebViewProxyConfigLine` (the carrier line's gates) and the
  guardian line's own dnsresolver / webview-proxy / socks5 suites.
* Dart: edited files pass the balanced-literal sanity gate (no SDK in
  the sandbox — `flutter analyze` runs fatal in CI, as always).
* Docs: FIREFOX_VPN_ENGINE.md at 1.5.0 (the upstreamSocks seam, the
  dns block, the webview-proxy role, quotaMax); ORIGIN.md records the
  merge and the retirement of the 1.4.0 carrier package.

## Honest gaps

* NOT TESTED on a real device — the debug APK comes from GitHub Actions
  (the sandbox cannot build/sign it).
* The carrier boot can take tens of seconds on a cold WARP registration
  (first run); the strip says «در حال اتصال…» but the wait is real.
* The `--login` exchange riding the carrier is engine-contract tested
  (the SOCKS transport is the tunnel's own audited path) but has no
  device evidence yet; the direct fallback covers a dead carrier.


## 5. Round 3 — the CI fix + the DIRECT mode (same day, evening)

Owner decrees: «اکشن شکست خورد بررسی کن. یک حالت اتصال مستقیم هسته
فایرفاکس هم باید اضافه کنی اما باید از پروژه آرمان وی پی ان ببینی توی
حالت مستقیم چطوری اتصال برقرار میشه و اگه از رله استفاده میشه باید
ببینی چطوری میشه هسته ایتر رو جایگزین رله کنی».

### 5.1 The CI failure (run 43698888528)

321 tests passed, 2 failed — both the new quota tests: the byte
formatter's `toStringAsFixed(1)` rendered «5.0 GB» where the tests (and
the frame's decimal-free number grammar) expect «5 GB». Fixed by
trimming the trailing `.0` in both formatters (settings pill + protocol
card). Run 43697410574's earlier failure was the union round's
duplicate `firefoxLegDesc` (equal_keys/duplicate_definition) — fixed
before that; this run is the remaining fallout only.

### 5.2 The arman study (the owner's named reference)

arman-vpn-client's core answers the same question with a two-posture
design (`core/internal/config/config.go`, Network block):

* **DIRECT** — the core dials everything itself: the control plane
  (FxA / Guardian / RemoteSettings) with its own resolver (system or
  DoH), the desktop-Firefox uTLS ClientHello and an optional
  ClientHello split; the Fastly MASQUE data plane direct (h2 or h3).
* **RELAYS (the blocked-region fallbacks)** — `upstream_proxy`: the
  user's OWN SOCKS5 proxy (e.g. a v2ray client on the device); every
  connection to Mozilla and the control plane goes through it, the
  names resolved there, h3 off (TCP only). `network.api_relay`: a
  personal HTTPS relay (Cloudflare Worker / PHP) for control-plane
  requests only, tried after a direct 451 retry
  (`core/internal/controlplane`, `docs/relay`).

**The mapping the owner asked for**: AETHONE's relay seat is the
in-process AETHER core — its loopback SOCKS listener is exactly
arman's `upstream_proxy`, except it is OUR core (no external v2ray,
WARP egress, UDP ASSOCIATE included). That is the over-WARP mode the
owner decreed as the default; what was missing was arman's OTHER
posture — the direct one.

### 5.3 The DIRECT mode (engine contract unchanged, 1.5.0)

* `CoreSettings.firefoxCarrierMode` (overWarp default — the standing
  «دیفالت اور وارپ» decree stands; legacy blobs migrate to it) |
  `direct`.
* The Firefox settings page gains the «نوع اتصال» section: over-WARP
  / DIRECT pills with the honest per-mode description; the Aether
  leg-protocol section renders only in over-WARP (a dead picker is
  never shown); the transport note names the direct reality; the DNS
  section stands in BOTH modes (it is the direct mode's own tool).
* The adapter walk: DIRECT skips the whole carrier leg (no Aether
  core, no listener wait, no probe, no 1819 busy check — an unrelated
  listener there must not block a direct connection) and sends NO
  `upstreamSocks` — the engine keeps its exact 1.2.0 direct behavior.
  The Windows whole-device-tunnel limit RETURNS for DIRECT + tunnel
  (the engine dials the internet itself; its own outbound would loop
  through zeptun's TUN) — over-WARP keeps the lifted limit.
* The login screen follows the mode: DIRECT never boots a login
  carrier — the direct DNS-aware webview proxy carries the page
  (arman's sign-in posture), and the `--login` exchange dials direct.
* Over-WARP is unchanged: the Aether core keeps the relay's seat
  (control plane + data plane + the login carrier + the exchange).

### 5.4 Verification

* Dart sanity (balanced literals) clean on every edited file; the
  quota arithmetic verified by script (5 GiB → «5 GB», 2 GiB →
  «2 GB», 5.5 GiB → «5.5 GB», 256 MiB → «256 MB»).
* New tests: the mode pick's default/persist/migration roundtrip, the
  direct config's omitted seam, and the mode strings in all 5 locales
  (test/firefox_over_warp_test.dart).

### 5.5 Build — PASS (GitHub Actions, طبق قاعده مالک)

- **Run**: `43702458897` — branch `fix/owner-round-2`، commit
  `f248ee0` (= کد نهایی شاخه)، **conclusion: success**. مسیر رسیدن:
  `43697410574` (duplicate firefoxLegDesc) → `43698888528` (۳۲۱ گذشت،
  ۲ شکست فرمت «5.0 GB») → `43700985076` (۳۲۵ گذشت، ۱ شکست تست
  migration بدون `v:1`) → سبز.
- **جاب‌ها**: Firefox engine (go_vet=PASS، go_test=PASS) / Native cores
  هر ۳ ABI success / DA debug APK (flutter_analyze=PASS «No issues
  found»، flutter_test=PASS — **۳۲۶ تست گذشت**، شامل real-engine
  --login suite).
- **APK**: `AETHONE-DA-Firefox-Debug.apk` — ۱۸۷,۳۳۵,۲۵۰ بایت؛
  universal (۳ ABI)؛ package_id=`com.chakcaad.aethone.da`.
- **SHA256 APK**: `ebddb3bc9d98526bd02813cf42b521ec1ea63931819b0d296d26145cc34a1f1a`
  — توسط CI ثبت و مستقل در sandbox بازمحاسبه و تطبیق یافت؛
  `libfirefoxvpn.so` در هر ۳ ABI byte-identical با باینری ساخته‌شده
  (fail-closed در CI).
- **نسخه محلی برای مالک**: کپی APK + build-report.txt +
  SHA256SUMS.txt در پوشه download/owner-round-2 ایجنت؛ artifact
  Actions (انقضا ۱۴ روز). NOT TESTED روی دستگاه — پذیرش on-device با
  مالک است.

## 6. Round 4 — the DIRECT mode corrected + the run-124 flake (same day, night)

دستور مالک (این بار صریح دربارهٔ معنای «مستقیم»):

«دقت کن در حالت رله آرمان وی‌پی‌ان کل تونل از رله عبور نمیکنه بلکه
مراحل اولیه اتصال از رله عبور میکنه. منظور من از ایجاد حالت مستقیم
همین بود یعنی مراحل اولیه اتصال که باید از روی کد ببینی چه مراحلیه
از تونل ایتر بگذره و بعد خود اتصال مستقیم انجام بشه.»

Round 3 had read «مستقیم» as arman's *direct* posture (no carrier at
all). The owner's correction: DIRECT is arman's *relay* posture — the
initial connection stages ride the Aether/WARP tunnel, then the
connection itself runs direct. The code walk identified the stages:

* **The initial stages (control plane)** — the sign-in WebView exchange
  (`--login` / `--webview-proxy`), the RemoteSettings discovery
  (`FetchServerList`), the Guardian pass (`FetchProxyPass`) and the
  OAuth refresh (`FxaRefreshToken` — also the renewal walk's recurring
  legs). These ride the carrier in BOTH modes now.
* **The connection itself (data plane)** — the single h2/h3 MASQUE
  session to the selected Fastly edge (`NewH2/H3ProxySession*` in
  `internal/upstream`). In over-WARP it dials through the carrier's
  SOCKS (TCP CONNECT / UDP ASSOCIATE); in DIRECT it dials the edge
  itself (h2 over TCP+TLS, h3 over QUIC; the process-local `dns`
  policy resolves the edge hostname).

### 6.1 The engine contract 1.6.0 (additive)

* `dataPlaneDirect` (bool, tunnel config): with `upstreamSocks` set it
  splits the planes — the control-plane transport seam
  (`SetControlPlaneTransport`) still rides the carrier, while the
  controller receives NO data-plane SOCKS (`dataPlaneCarrier`). A new
  Info line records the split on-device («direct data plane — the
  control plane … rides socks5://127.0.0.1:1819»).
* Fail-fast: the flag without `upstreamSocks` is a config bug
  (`dataPlaneDirectWithoutCarrier` — a carrier-less config is already
  fully direct; never a silent no-op). Absent flag = the exact 1.5.0
  carried behavior.
* `EngineVersion` 1.5.0 → **1.6.0** (started/loginStarted events); the
  two version-prefix tests follow.

### 6.2 The host walk (round-3 reversals)

* The carrier leg (Aether core boot, listener wait, probe, the 1819
  busy gate) runs in BOTH modes — the initial stages need it either
  way; only `dataPlaneDirect` differs on the engine config line.
* The login carrier boots in DIRECT too (round 3 had suppressed it):
  the sign-in IS an initial stage — a DIRECT-mode user in a blocked
  region signs in through WARP exactly like an over-WARP user.
* The Aether leg-protocol picker renders in BOTH modes again (round 3
  had hidden it in DIRECT — a dead picker was the wrong fix because
  the carrier is alive in both).
* The Windows whole-device-tunnel limit STANDS for DIRECT + tunnel
  (the data plane's own dials would loop through zeptun's TUN).
* l10n: the DIRECT-mode texts rewritten in all 5 locales to the relay
  semantics («مراحل اولیهٔ اتصال … از تونل وارپ … بعد خودِ اتصال داده
  مستقیماً …»), plus `firefoxLegDesc` naming the per-mode split.

### 6.3 The run-124 CI failure (the flake, diagnosed)

Run `43704068797` (commit `c511a71`, docs-only) failed the engine job
at `go test`: `TestRealGuardianInvalidTokenHonestFailure` —
`failCode = serverRejection (want sessionRejected)`. The probe evidence
(sandbox, same day): with the upstream's exact headers the live edge
answers the all-zero bearer with **401** («{"error":"Unauthorized"}»),
but the edge has ALSO been observed answering **406** (a wrong client
signature) and other non-401/403 4xx/5xx depending on the edge node —
the exact status is the SERVER's to choose. The test was over-specified
(round-124's failure was environmental, not a code regression — run
123 passed the same code). Reworked to assert the CONTRACT instead of
one outcome:

* the `failed` event must carry a REAL 4xx/5xx `httpStatus`;
* the failCode must be CONSISTENT with that status (401/403 →
  `sessionRejected`, any other 4xx/5xx → `serverRejection`);
* the rejected token never leaks; exit 1;
* environmental outcomes are HONEST SKIPS, never greens: the edge's 429
  (surfaces as `quotaExhausted`) and the transport classes
  (dnsError/networkUnavailable/timeout/tlsError — no HTTP answer at
  all). An HTTP-level failure WITHOUT a status still FAILS the test
  (the masking hole stays closed).

### 6.4 Verification (this round)

* Go 1.25.0 (the CI pin): `go vet ./...` PASS; `go test ./...` — all
  8 packages PASS, including the reworked live-edge test (0.28 s, real
  401 → sessionRejected) and the new 1.6.0 shape tests
  (`TestDataPlaneDirectRequiresCarrier`,
  `TestDataPlaneDirectWithCarrierAccepted`, `TestDataPlaneCarrierSplit`).
* Flutter 3.47.9 (the CI pin): `flutter analyze` — No issues found;
  `flutter test` — **320 passed, 8 skipped** (the skips are the
  suite's own honest network/platform guards), including the three
  reworked config-shape tests.

### 6.5 Build — PASS (GitHub Actions, طبق قاعده مالک)

- **Run**: `43710519166` (run_number 125) — branch `fix/owner-round-2`،
  commit `6774e4d` (= کد نهایی این دور)، **conclusion: success**. مسیر
  رسیدن: `43704068797` (run 124 — تستِ over-specifiedِ واقعی-شبکه‌ای که
  لبهٔ زنده با وضعیتی غیر از 401/403 جوابش داد؛ ریشه‌یابی و اصلاح در
  §6.3) → سبز در همان یک پوش.
- **جاب‌ها**: Firefox engine (go_vet=PASS، go_test=PASS — هر ۸ پکیج،
  شامل تست بازنویسی‌شدهٔ live-edge) / Native cores هر ۳ ABI success /
  DA debug APK (flutter_analyze=PASS «No issues found»،
  flutter_test=PASS — **۳۲۸ تست گذشت**، شامل real-engine --login
  suite؛ zipalign + apksigner PASS).
- **APK**: `AETHONE-DA-Firefox-Debug.apk` — ۱۸۷,۳۳۶,۸۸۶ بایت؛
  universal (۳ ABI)؛ package_id=`com.chakcaad.aethone.da`.
- **SHA256 APK**: `c9501159591af9e12e22354bc6e3902726d7505958de12cc3c092a62a99b5ca0`
  — توسط CI ثبت و مستقل در sandbox بازمحاسبه و تطبیق یافت.
- **_byte-identity مستقل موتور درون APK_** (manifest جابِ engine در
  برابر استخراج از APK، در sandbox): arm64-v8a `4c321b23…`
  (۱۴,۶۳۳,۸۲۴ بایت) / armeabi-v7a `b61e3b6c…` (۱۴,۴۴۳,۴۸۴ بایت) /
  x86_64 `563f5352…` (۱۵,۶۱۰,۲۸۰ بایت) — هر سه مطابق.
- **نسخه محلی برای مالک**: کپی APK + build-report.txt +
  SHA256SUMS.txt در پوشه download/owner-round-4 ایجنت؛ artifact
  Actions (ID 14160627577، انقضا ۱۴ روز). NOT TESTED روی دستگاه —
  پذیرش on-device با مالک است.

---

## 7. Round 5 (2026-11-15, after the owner's device test of the round-4 build)

The owner's report (verbatim diagnoses, each traced to a root cause):

> «بخش حجم باقی مانده رو اصلاح کن چون ظاهرا کار نمیکنه. ورود به حساب
> کاربری فایرفاکس هنوز مشکل داره. اتصال مستقیم و از طریق اور وارپ
> فایرفاکس انجام نمیشه در صورتی که تو نسخه قبلی حالت اور وارپ به خوبی
> متصل میشد. توی تست DNS برای همه DNS ها ارور برخی درخواست های DNS
> ناموفق بودند میده. برنامه هم هی متوقف میشه پشت سر هم. وقتی روی دکمه
> ای تو صفحه کلیک میشه که یک عملیات بک اند بعدش انجام میگیره مثل اسکن
> کردن باید لودینگ یا چیزی نمایش داده بشه … برای لودینگ هم میتونی از
> لودینگ آخر صفحات ورود اصلی اپ استفاده کنی»

### 7.1 The root causes found (the code walk)

1. **The remaining-data section** — the quota surfaced ONLY on
   `passAcquired`/`renewed`, i.e. only after a fully-connected tunnel.
   With the connect defects below, no quota event ever fired, and an
   account whose Guardian answers `X-Quota-Unlimited: true` (the flag
   arman's ProxyUsage reads) was indistinguishable from "no data yet".
2. **The DNS test failing for EVERY provider** — the DoH provider
   defaults were HOSTNAME endpoints (`cloudflare-dns.com`, …), and the
   DoH bootstrap resolved that hostname through the ANDROID SYSTEM
   resolver — which the network's DNS poisoner answers. Every provider
   failed identically before its first query; system mode failed the
   Mozilla domains for the same poisoning. Arman's reference uses
   IP-LITERAL endpoints (`https://1.1.1.1/dns-query`,
   `https://8.8.8.8/dns-query` — core/internal/resolver/through.go):
   no bootstrap lookup at all, no SNI to key on.
3. **Both connect modes dying** — TWO independent defects:
   a. An INVALID DNS line killed the engine at startup
      (`dnsConfigInvalid`): picking DoH + «سفارشی» without saving an
      endpoint produced exactly that, and the app sent it verbatim —
      both modes, instantly dead.
   b. The h3 data plane had no fallback: a network that drops UDP
      (QUIC throttling) or a carrier refusing UDP ASSOCIATE left the
      walk dead even though h2 rides the same path fine — the 1.4.0
      build the owner compared against simply REFUSED h3+carrier, so
      its over-WARP always ran h2.
4. **The loading absence** — the backend-op buttons (the DNS test, the
   location refresh, …) gave no feedback while their walks ran, which
   the owner experienced as "the app stops".

### 7.2 The fixes (contract **1.7.0**, additive)

* **`--usage` (the remaining-data fix)** — the engine's new role
  (arman's `fetchProxyUsage` model): HEAD then GET on the Guardian
  token endpoint, NO pass minted, the `X-Quota-*` headers parsed with
  arman's ProxyUsage semantics — including the explicit
  `X-Quota-Unlimited` flag the pass-minting path never surfaces, and
  the 429-carries-usage rule. It rides the WARP carrier
  (`upstreamSocks` → the control-plane seam, the uTLS Firefox
  ClientHello kept). The app runs it: right after sign-in (the login
  screen awaits it BEFORE its carrier teardown), when the Firefox
  settings page opens, on every connect (the standing
  passAcquired path), and from a new refresh button. The quota slots
  (the settings pill, the protocol card, and a new card on the
  Firefox settings page with the reset stamp) all read the same store.
* **The DoH provider defaults are now IP-LITERAL** (arman's
  ThroughServers): Cloudflare `https://1.1.1.1/dns-query`, Google
  `https://8.8.8.8/dns-query`, Quad9 `https://9.9.9.9/dns-query` — no
  bootstrap lookup, no SNI. The DoH transport dials an IP-literal
  endpoint directly; the DNS test's setup failure gets its own message
  (distinct from «برخی درخواست‌ها ناموفق بودند»).
* **The app never sends an invalid DNS line**: a custom provider
  without a saved endpoint degrades to system (surfaced by an inline
  hint, «نشانی DoH سفارشی خالی است…»), and switching providers resets
  the endpoint fields so a stale custom endpoint never rides a
  built-in provider.
* **The h3→h2 fallback**: a failed h3 session build retries ONCE as h2
  through the same dial path (direct or carrier), honestly logged
  (`h3 session failed (…) — falling back to h2`) and mirrored in the
  live transport label; a double failure reports the h3 chain. The
  user's pick is a preference, not a death sentence.
* **The scan-loading affordances** (the owner's named precedent: the
  onboarding/home scan rings): `SettingActionButton` gained a `busy`
  state — the ScanRings animation at button height + the running
  operation's label — applied to the DNS test, the quota refresh, and
  the location refresh (rings beside the live/cached label).

### 7.3 The crashes («برنامه هی متوقف میشه»)

No deterministic crash reproduced from the code walk: every new native
path (the WebView `ProxyController` override, the child-PID
registration, the engine spawn discipline) is try/catch-guarded on
both sides, and the startup path's new loads are all
failure-swallowing by design. The most probable reading given the
loading absence is the perceived freeze/kill of backend-op presses —
which the affordances above address directly. If a real crash
persists on the device, the app's OWN core diagnostics page
(تنظیمات → «لاگ هسته» — filesDir/logs/core-log.txt) carries the
engine + core stderr; `adb logcat` carries the Dart/native stack. The
owner's report of either would pin it in one round.

### 7.4 Verification (the CI gates, per the standing rule)

Go 1.25.0 + Flutter 3.47.9 (the CI pins). New tests: the usage role
suite (the unlimited flag, the trio parse, the HEAD→GET fallback, the
429-carries-usage rule, the rejected-token classification, the
fail-closed config) · the IP-literal endpoint defaults + the
no-resolver dial · the h3→h2 fallback suite (one retry, honest log,
h2-pick-never-touches-h3, the double-failure chain) · the Dart round-5
suite (the quota flag parse, the never-invalid DNS line, the provider
switch reset, the usage event parse, the page affordances). The build
pin lands in §7.5 below after the run goes green.

---

## 8. Round 6 (2026-11-15, after the owner's device test of the round-5 build)

The owner's report on the round-5 build:

> «در صفحه ورود به حساب کاربری ارور صفحه وب در دسترس نیست دریافت میشه
> و برای DNS ها هم ارور راه اندازی DNS انتخاب شده ناموفق بود. تنظیمات
> را بررسی کنید. دریافت میشه. مجدد مشکل بسته شدن برنامه و ارور ایتن
> پاسخ نمی دهد دریافت میکنم این اتفاق زمانی که توی صغحه تنظیمات
> فایرفاکس هستم اتفاق میفته. ضمن اینکه اتصال هم اتفاق نمیشه که ممکنه
> به خاطر همین مساله DNS باشه.»

### 8.1 The diagnosis — one root cause, three symptoms

The quoted error strings are the round-5 additions themselves
(`firefoxDnsSetupFailed`), which made the trail precise:

* «راه‌اندازی DNS انتخاب‌شده ناموفق بود» = the `--dns-probe` role
  produced NO events = `dnsresolver.Install()` failed = the DNS config
  line was INVALID. Round 5's store guard covered only the EMPTY
  custom endpoint — a **MALFORMED** endpoint (a schemeless hostname
  typed into the free-text field) or **junk bootstrap IPs** (any text
  was accepted; the earlier builds persisted it) still sailed through.
* «صفحه وب در دسترس نیست» = the `--webview-proxy` child installs the
  same DNS config first → `dnsSetupFailed` → `proxy.start()` threw →
  the login screen's honest-unavailable fallback. **Same root.**
* «اتصال هم اتفاق نمیشه» = `runTunnel` installs it too →
  `dnsConfigInvalid` → the engine dies at startup, BOTH carrier modes.
  **Same root.** (The owner's own guess — «ممکنه به خاطر همین مساله
  DNS باشه» — was exactly right.)

The settings-page ANR + app closes («ایتن پاسخ نمی دهد», on the
Firefox settings page): round 5's auto quota refresh BOOTED A FULL
WARP CARRIER (an Aether core) at every page open — the memory churn
the device felt as repeated kills, and while that carrier held
127.0.0.1:1819, a concurrent connect walk failed outright with
`firefoxCarrierPortBusy`.

### 8.2 The fixes (host-side only — the engine contract stays 1.7.0)

* **The DNS line is now bullet-proof against ANY garbage the store can
  hold**: the custom endpoint rides only when it parses as an absolute
  HTTPS URL (scheme https, a host, no user-info/fragment — the engine's
  own rule); bootstrap entries ride only when they are real IP
  literals (v4 or v6), junk entries are dropped rather than fatal; any
  invalid custom piece degrades the effective mode to system and the
  inline hint now says «نشانی DoH سفارشی معتبر نیست…» (covering
  malformed, not just empty). `setFirefoxDnsCustom` sanitizes at save
  time too. One getter feeds the tunnel config, the login screen's
  proxy line AND the DNS probe — one fix, all three symptoms.
* **The quota refresh NEVER boots a carrier anymore**: a LIVE carrier
  (a connected session's, or the login screen's own during the
  post-sign-in fetch) is probed and ridden; without one the `--usage`
  role walks DIRECT (the pinned-uTLS control plane with the selected
  DNS — the IP-literal DoH defaults survive poisoned networks). No
  core churn on the settings page, no port-1819 conflict with a
  concurrent connect, and an honest failure on a hard-blocked network
  is fine — the value still lands on connect through the standing
  passAcquired path.

### 8.3 Verification

Go: unchanged engine (vet/test green from round 5, re-run in this
round's gates). Flutter analyze clean; the round-6 suite adds the
malformed-endpoint shapes (schemeless / http / garbage), the junk
bootstrap filtering, the save-time sanitization, and the end-to-end
regression shape (DoH + custom + schemeless endpoint + junk bootstrap →
a system line the engine accepts). The build pin lands in §8.4.

### 8.4 Build — PASS (GitHub Actions, طبق قاعده مالک)

- **Run**: `43728500150` (run_number 128) — branch `fix/owner-round-2`،
  commit `759f413` (= کد نهایی دور ۶)، **conclusion: success** در همان
  یک پوش.
- **جاب‌ها**: Firefox engine (go_vet=PASS، go_test=PASS) / Native cores
  هر ۳ ABI success / DA debug APK (flutter_analyze=PASS «No issues
  found»، flutter_test=PASS — **۳۵۰ تست گذشت**؛ zipalign + apksigner
  PASS).
- **APK**: `AETHONE-DA-Firefox-Debug.apk` — ۱۸۷,۴۰۲,۵۷۴ بایت؛
  universal (۳ ABI)؛ package_id=`com.chakcaad.aethone.da`.
- **SHA256 APK**: `e70b6e5d2a5cf8e6f29237d824bad3e59fe71a6429c7bcaee695e0408448b2f0`
  — توسط CI ثبت و مستقل در sandbox بازمحاسبه و تطبیق یافت.
- **_byte-identity مستقل موتور درون APK_** (manifest جابِ engine در
  برابر استخراج از APK، در sandbox): arm64-v8a `7a113229…`
  (۱۴,۶۶۰,۴۴۰ بایت) / armeabi-v7a `e79bbe7f…` (۱۴,۴۶۸,۹۱۲ بایت) /
  x86_64 `e1a94941…` (۱۵,۶۳۷,۹۳۶ بایت) — هر سه مطابق.
- **نسخه محلی برای مالک**: کپی APK + build-report.txt +
  SHA256SUMS.txt در پوشه download/owner-round-6 ایجنت؛ artifact
  Actions (ID 14167753103، انقضا ۱۴ روز). NOT TESTED روی دستگاه —
  پذیرش on-device با مالک است.

**نکتهٔ مهم برای تست دستگاه**: پس از نصب این نسخه، اگر صفحهٔ تنظیمات
فایرفاکس هنوز نشان می‌دهد «نشانی DoH سفارشی معتبر نیست»، یعنی همان
تنظیم ذخیره‌شدهٔ قبلی (سفارشی + نشانی ناقص) در جای خود است — یا
نشانیِ معتبر (مثل `https://1.2.3.4/dns-query`) را ذخیره کنید یا
ارائه‌دهندهٔ آماده (Cloudflare/Google/Quad9) را برگزینید؛ در هر دو حالت
خطا رفع می‌شود و اتصال/ورود باید کار کند. اگر تنظیم DNS روی «سیستم»،
یا DoH با ارائه‌دهندهٔ آماده است و مشکل باقی ماند، لاگ هسته
(تنظیمات → لاگ هسته) و `adb logcat` مدرک لازم را فراهم می‌کنند.

---

## 9. Round 7 (2026-11-15, the WireGuard report + the run-129 flake)

> «اکشن شکست خورد بررسی کن علتشو. یک مشکلی که وجود داره اینه که
> پروتکل وایرگارد متصل نمیشه در صورتی که توی اپ دیگه ای برام پروتکل
> وایرگارد همین هسته به راحتی متصل میشه یک بررسی بکن کدهای هسته رو
> ببین مشکل یا باگی وجود داره یا نه و اگه وجود داره اصلاحش کن، هسته:
> github.com/CluvexStudio/Aether»

### 9.1 The run-129 failure (the CI side)

Run 128 (the round-6 code) was green; run 129 was the docs-only pin
commit and failed in `zz_appearance_shot_test.dart` —
`PathNotFoundException: /tmp/ui_shots/appearance_v425.png`: the test
wrote its PNG without creating `/tmp/ui_shots` itself, relying on
another shot-test file to have created it first — but `flutter test`
runs files in PARALLEL isolates whose order is not guaranteed, so on
that runner the appearance test ran first. Fixed: the test now creates
its own directory and the PNG write is guarded (the shot is a debug
artifact; the assertions are the test — a filesystem hiccup can never
fail the suite again).

### 9.2 The core audit (the requested check — no core bug found)

The pinned core (`CluvexStudio/Aether` @ `d58f9d5`, verified in CI) was
audited end-to-end on the WireGuard path, against the question "why
would the same core connect in another app but not here":

* **The pin is the latest release** (2.4.0): upstream `d58f9d5..HEAD`
  holds only README/OPENWRT/tor-password doc merges — nothing after it
  touches WireGuard. The vendored tree equals the export at the pin.
* **The whole WG chain was read**: the WARP-API registration and edge
  fallback (account.rs/api.rs — identity cached in warp.toml, reused,
  never re-registered per connect) · `run_wireguard` (lib.rs — profile
  candidates balanced→aggressive→light→off, the cached endpoint
  verified before reuse, endpoint cooldowns) · `hunt_wg_endpoints`
  (wg_prober.rs — CIDR sampling, port waves, honest deadlines) ·
  `verify_endpoint_keep_session` (wireguard.rs — init/retransmit at
  750 ms/2 s, decapsulation, TWO data-plane confirmations) · the run
  loop (recv/send/timer/health tasks, stale detection at 10 s) · the
  FFI harness (ffi.rs `aether_core_start` → `run_with(args)` — the
  exact CLI path, so the other app's invocation and ours run the same
  code). **No bug found.**
* The app-side invocation matches the core's own defaults
  (`--noize balanced` IS the core default; env cleared per start;
  `--quick-reconnect` = the non-TTY default; listener binds before the
  data path, probe retries — the walk is sound).

### 9.3 What actually differed — the app killed the core's scan

The audit's one real finding is an APP-vs-CORE CONTRACT bug, exactly
the shape the owner's rule bans («اپ باید تابع هسته ایتر باشه …»,
v4.31):

* The core's scanners run to PROFILE-DEPENDENT overall deadlines —
  prober.rs (MASQUE) / wg_prober.rs (WireGuard): turbo 45/30 s ·
  **balanced 120/80 s** · verified 60/60 s · **ironclad 180/180 s** ·
  **thorough 300/250 s**.
* The app's plain-mode ready budget was a FIXED 120 s — so for every
  scan pick deeper than verified (balanced-MASQUE, ironclad,
  thorough), the walk FAILED while the core was still legitimately
  scanning; every retry restarted the scan from zero. On the device
  that reads as «پروتکل وایرگارد متصل نمیشه» + «برنامه هی متوقف
  میشه» — while the same core under its own defaults (balanced,
  no app deadline above it) connects in the other app.
* The default scan pick made it worse: the app defaulted to 5 =
  «turbo» — the THINNEST WG scan (40 samples/CIDR, 1 port wave,
  first-success exit) where the core's own default is «balanced»
  (120 samples/CIDR, 3 port waves).

### 9.4 The fixes (app-side; the core stays at the pin, untouched)

1. **The ready budget follows the scan profile** (`readyBudget` gains
   `scanSpeed`, wired at every call site — the plain walk, the
   Firefox WARP-leg probe, the login carrier): the core's per-profile
   MAX deadline + 45 s of registration/handshake headroom, floored at
   the historical 120 s so nothing tightens (turbo 120 · verified 120
   · balanced 165 · ironclad 225 · thorough 345 s). The v4.31 rule —
   never give up on a core you are still giving time to — now holds
   for every scan depth.
2. **The default scan is now 4 = «balanced»** — the pinned core's OWN
   default (`select_scan_mode_str`, lib.rs), the posture the reference
   app runs. A persisted pick is untouched; only fresh installs,
   resetToDefaults and the persistence fallback land here.
3. The run-129 flake fix (§9.1).

If WireGuard still fails on the device after this, the evidence to
send is the app's own «لاگ هسته» page (filesDir/logs/core-log.txt) —
it carries the core's whole scan trail (profile lines, candidate
counts, per-endpoint failures), which pins the remaining cause in one
round.

### 9.5 Build — PASS (GitHub Actions, طبق قاعده مالک)

- **Run**: `43734302737` (run_number 130) — branch `fix/owner-round-2`،
  commit `b136e10` (= کد نهایی دور ۷)، **conclusion: success** در همان
  یک پوش (رفع شکست run 129 — همان فلکِ تست اسکرین‌شات، §9.1).
- **جاب‌ها**: Firefox engine (go_vet=PASS، go_test=PASS) / Native cores
  هر ۳ ABI success / DA debug APK (flutter_analyze=PASS، flutter_test=PASS؛
  zipalign + apksigner PASS).
- **APK**: `AETHONE-DA-Firefox-Debug.apk` — ۱۸۷,۴۰۲,۱۴۲ بایت؛
  universal (۳ ABI)؛ package_id=`com.chakcaad.aethone.da`.
- **SHA256 APK**: `be81edb290ee63a732852a3acee8917b0ed264d6040d79c1d94b959b8d3a8cc0`
  — توسط CI ثبت و مستقل در sandbox بازمحاسبه و تطبیق یافت.
- **_byte-identity مستقل موتور درون APK_**: arm64-v8a `998ac846…`
  (۱۴,۶۶۰,۴۴۰ بایت) / armeabi-v7a `b2f4a58c…` (۱۴,۴۶۸,۹۱۲ بایت) /
  x86_64 `9ecce2b6…` (۱۵,۶۳۷,۹۳۶ بایت) — هر سه مطابق.
- **نسخه محلی برای مالک**: کپی APK + build-report.txt +
  SHA256SUMS.txt در پوشه download/owner-round-7 ایجنت؛ artifact
  Actions (ID 14169644702، انقضا ۱۴ روز). NOT TESTED روی دستگاه.

**برای تست دستگاه**: وایرگارد را امتحان کنید — اگر باز هم وصل نشد،
صفحهٔ «لاگ هسته» در تنظیمات (filesDir/logs/core-log.txt) ردپای کامل
اسکن هسته را دارد (خطوط profile، تعداد کاندیدها، خطای هر endpoint) و
همان یک دور بعدی را قطعی می‌کند. توجه: مقدار پیش‌فرض «سرعت اسکن»
اکنون ۴ (balanced) است؛ انتخاب ذخیره‌شدهٔ قبلی دست‌نخورده مانده.
