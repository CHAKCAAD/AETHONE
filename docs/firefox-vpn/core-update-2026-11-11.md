# به‌روزرسانی هسته Firefox VPN — 2026-11-11

> شاخه: `update/firefox-vpn-core` (مستقل؛ پایه: `performance/firefox-vpn-optimization`
> که خودش شامل تمام تاریخچه‌ی `integration/firefox-vpn-debug` است —
> `git merge-base --is-ancestor` تأیید شد). دستور مالک: افزودن آخرین
> تغییرات هسته‌ی upstream به یک شاخه‌ی مستقل، بدون دست‌زدن به دو شاخه‌ی موجود.
> هدف: نگه‌داشتن دقیق ساختار اثبات‌محور مخزن (پین + مانیفست + شواهد).

## ۱. خلاصه‌ی تغییر

پین هسته‌ی upstream از `55ad91a2ccea1c93e69c82a08a7681e279884db5`
(2026-11-06, «fix(fxa): present Firefox ClientHello on the control plane»)
به آخرین کامیت upstream یعنی
`c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1`
(2026-11-10, «chore: update pinned Firefox identity (#7)») ارتقا یافت و
هویت Firefox در لایه‌ی Dart هم برای حفظ سیاست «یک هویت در همه‌جا» همگام شد.

## ۲. تحلیل دقیق دلتای upstream (55ad91a → c1c5d89)

فهرست کامل کامیت‌های بین دو پین (برگرفته از `git log 55ad91a..c1c5d89`):

| کامیت | تاریخ | شرح | اثر بر کد Go |
|---|---|---|---|
| `ff19107` | 2026-11-09 | docs: add README (#4) | هیچ — فقط فایل `README.md` اضافه شد |
| `1c39e8f` | 2026-11-09 | chore: update pinned Firefox identity (#5) | `defaultFirefoxVersion`: «159.0» → «159.0.1» |
| `eac3224` | 2026-11-09 | typo | هیچ — اصلاح برندینگ «Mozilla VPN» → «Firefox VPN» در README |
| `c1c5d89` | 2026-11-10 | chore: update pinned Firefox identity (#7) | `defaultFirefoxVersion`: «159.0.1» → «160.0» |

`git diff --stat 55ad91a..c1c5d89`:

```text
 .gitignore          |   3 +
 README.md           | 560 ++++++++++++++++++++++++++++++++++++++++++++++++++++
 firefox_identity.go |   2 +-
 3 files changed, 564 insertions(+), 1 deletion(-)
```

**تنها تغییر کد:** ثابت `defaultFirefoxVersion` در `firefox_identity.go`
از «159.0» به «160.0» — یعنی UA هویت control-plane که Fastly می‌بیند به
نسخه‌ی stable فعلی موزیلا (Firefox 160) ارتقا می‌یابد. این دقیقاً همان
چیزی است که workflow روزانه‌ی `update-firefox-version.yml` خود upstream
به‌صورت خودکار نگه می‌دارد؛ پین قبلی یک نسخه عقب بود.

**سطح کتابخانه‌ای مورد استفاده‌ی AETHONE بایت‌به‌بایت بدون تغییر است:**
`FxaOAuthToken`، `FxaRefreshToken`، `FetchProxyPass`، `FetchServerList`،
`NewControlPlaneTransport`، sentinelهای Guardian (`ErrQuotaExceeded` /
`ErrTokenInvalid`) و رفتار uTLS ClientHello هیچ تغییری نکرده‌اند؛ بنابراین
هیچ تعدیلی در لایه‌ی `phase1/fxv` لازم نبود و `go.mod`/`go.sum` ما هم
دست‌نخورده ماند (کامیت‌های بعد از پین قبلی در go.mod/go.sum تغییری
نداده‌اند).

نکته‌ی مهم تاریخی: سه فیکس حیاتی Fastly (پین UA فایرفاکس در `a390c37`،
پین HTTP/1.1 در `23486f4` و uTLS Firefox ClientHello در `55ad91a`) همگی
**از قبل در پین قبلی موجود بودند**؛ دلتای این به‌روزرسانی فقط نگهداری
نسخه‌ی هویت است، نه تغییر معماری.

## ۳. تغییرات این شاخه (فایل‌به‌فایل)

| فایل | تغییر |
|---|---|
| `phase1/scripts/fetch_upstream.sh` | `UPSTREAM_PIN` → `c1c5d89…` + یادداشت re-pin در هدر |
| `phase1/scripts/build_engine.sh` | `UPSTREAM_PIN` → `c1c5d89…` (assert ساخت) |
| `phase1/firefox-vpn-client.SHA256SUMS` | بازتولید توسط خود `fetch_upstream.sh` از snapshot جدید: هش `firefox_identity.go` تغییر کرد، `README.md` و `.gitignore` اضافه شدند؛ ۲۷ فایل |
| `phase1/fxv/ORIGIN.md` | بلوک «Upstream pin (exact)» + جدول «Re-pin history» + تأیید مجدد وضعیت license در پین جدید |
| `lib/connection/firefox/firefox_web_channel.dart` | `kFirefoxIdentityVersion`: «159.0» → «160.0» (همگامی هویت WebView با هویت control-plane) |
| `test/firefox_login_test.dart` | انتظارهای تست UA: `rv:160.0` / `Firefox/160.0` |
| `docs/firefox-vpn/build.md` | جدول پین‌ها + رویه §2 + §7 (شواهد تست جدید) |
| `docs/firefox-vpn/recovery-guide.md` | commit مورد انتظار دستور بازیابی |
| `docs/firefox-vpn/architecture.md` | برچسب هسته‌ی پین‌شده در نمودار زنجیره |
| `docs/FIREFOX_VPN_ENGINE.md`، `FIREFOX_VPN_ANDROID.md`، `FIREFOX_VPN_SECURITY.md` | ارجاع پین جاری + تأیید مجدد license |
| `.github/workflows/android-debug.yml` | شاخه‌ی `update/firefox-vpn-core` به تریگر push اضافه شد (همان قواعد containment؛ فقط artifact های ۱۴روزه، هیچ انتشار عمومی) |

گزارش‌های تاریخی فازها (PHASE1/PHASE2/PHASEB، SERVER_DISCOVERY،
PERFORMANCE_PROGRESS، phaseb-engine-patch و `phase1/docs/BUILD.md`) عمداً
دست‌نخورده ماندند — آن‌ها ثبتِ تاییدهای گذشته‌اند، نه وضعیت جاری.

## ۴. شواهد تایید (اجراشده در همین نشست)

| بررسی | نتیجه |
|---|---|
| `fetch_upstream.sh --force` | `pin verified: c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1` — مانیفست ۲۷ فایلی بازنویسی شد |
| دلتای مانیفست | فقط ۳ ورودی تغییر کرد (همسو با `git diff` upstream): `firefox_identity.go` (هش جدید)، +`README.md`، +`.gitignore` |
| `defaultFirefoxVersion` در کپی fetchشده | `"160.0"` |
| `go vet ./...` (aethone/fxv، Go 1.25.0) | PASS |
| `go test ./...` (aethone/fxv) | **۹۸/۹۸ PASS، ۰ FAIL** — `cmd/libfirefoxvpn`, `internal/discovery`, `internal/engine`, `internal/fferr`, `internal/redact`, `internal/socks`, `internal/upstream` |
| `go build ./...` (aethone/fxv) | PASS |
| `go test ./...` (خود هسته‌ی upstream پین‌شده) | PASS (هر دو پکیج) |
| `bash -n` روی هر دو اسکریپت | سینتکس سالم |

تست‌های Dart (از جمله `firefox_login_test.dart`) در همین محیط اجرا نشدند
(Flutter SDK در دسترس نبود) — در CI با `flutter analyze` + `flutter test`
پوشش داده می‌شوند و workflow `android-debug.yml` حالا با push این شاخه
به‌صورت خودکار کل زنجیره (موتور + هسته‌های native + APK دیباگ DA) را از
سورس می‌سازد.

## ۵. باینری‌ها و فاز بعدی

- باینری‌های ثبت‌شده در `phase1/build/SHA256SUMS.txt` و فایل‌های
  `.inspection.txt` مربوط به بیلد 2026-11-09 با پین قبلی‌اند و به‌عنوان
  سابقه دست‌نخورده می‌مانند؛ **بازسازی .so برای هر سه ABI + host لازم است**
  تا هویت Firefox 160 داخل باینری کامپایل شود — با push این شاخه،
  GitHub Actions این کار را از سورس انجام می‌دهد (زنجیره‌ی evidence
  همان است که در `docs/firefox-vpn/build.md` §۴ مستند شده).
- تست روی دستگاه (device acceptance) همچنان فاز مالک است.
- وضعیت license هنوز UNRESOLVED است (در پین جدید هم هیچ فایل licenseای
  وجود ندارد — re-verify شد)؛ تمام قواعد containment برقرار می‌ماند.
