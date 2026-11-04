/// The Settings main page — pixel-faithful rebuild of the owner's design
/// frame «صفحه تنظیمات.jpg» (402×874; every geometry value measured on the
/// 3× source and recorded in [AethGeometry] as `settings*` tokens).
///
/// Structure (phase-1 report §3.2 + pixel extraction; v4.15 renames — the
/// owner's own words, settings round #5/#8):
///   * Top bar: chevron tile (Right 2, visual RIGHT = back) · «تنظیمات»
///     centered · info tile (Information Circle, visual LEFT → the Telegram
///     channel, same behaviour as the home top bar).
///   * Six cards, 3 columns × 2 rows (icon top / title / subtitle):
///       row 1 visual L→R: مسیریابی‌ها (Forward) · تنظیمات عمومی
///       (Filter 5) · تنظیمات اتصال (Lock 1)
///       row 2 visual L→R: تنظیمات زبان (Website) · تنظیمات ظاهری
///       (Palette) · تنظیمات امنیت (Security Safe — v4.15 #1)
///   * Two wide pills — «سایفون» / «تور» (renamed from «تنظیمات سایفون» /
///     «تنظیمات تور», v4.15 #8) — the REAL protocol logos (pre-rendered
///     PNGs) tinted accent green at the leading edge, like the frame.
///     Corners: owner CSS «Rectangle 79» r24 (v4.15 #3) — never a stadium.
///   * Section «وضعیت پیکربندی» (renamed from «وضعیت پیشرفته», v4.15 #5;
///     icon Menu Fries — v4.15 #7) + THREE status cards on the same 3-col
///     grid — every value is the REAL store state (report D2: «هر سه کارت
///     وضعیت به دادهٔ واقعی نگاشت شدند»):
///       Kill Switch → ON/OFF · منطقهٔ مسیریابی → Latin region name ·
///       پروتکل → AUTO / SMART.
///   * Section «آدرس هسته ها» (renamed from «آدرس سرور اصلی», v4.15 #6;
///     icon Situation 1 — v4.15 #8, replacing the drawn crosshair) + two
///     pills: Zeptun Tunnel / Aether Core with the owner's own GitHub logo
///     SVG, corners r20 (same Rectangle-79 look, v4.15 #3).
///
/// Subpages (v4.22 — the owner's «تنظیمات جزیی» round): every card, pill
/// and status card opens its REAL page now — the six categories
/// (routing / general / connection / language / appearance / security),
/// the Psiphon/Tor family pages, the three status cards (Kill Switch →
/// security, routing area → routing, protocol → connection) and the
/// Aether-core entry sits on the connection page (fragment / TLS /
/// transport / engine — the owner's headline, with the Iran fragment
/// profiles).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../connection/connection_store.dart';
import '../../connection/core_log.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import '../home/widgets/pattern_sides.dart';
import 'appearance_page.dart';
import 'connection_page.dart';
import 'general_page.dart';
import 'language_page.dart';
import 'psiphon_page.dart';
import 'routing_page.dart';
import 'security_page.dart';
import 'tor_page.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final ConnectionStore store;

  static const String telegramChannelUrl = 'https://t.me/AETHONE';

  /// v4.17 — owner settings round #4: «به صفحه و کارت ها انیمیشن ورود و
  /// خروج اضافه کن». Every page block enters on its own slice of the
  /// ROUTE timeline; v4.25 — the choreography is the STYLE'S OWN recipe
  /// (SILK rise / TIDE drift-zoom / SPRING pop / BLINK pure fade / OFF =
  /// untouched) and the SAME slices retrace on pop, so the exit folds
  /// the page away gently. Blocks: top bar 0, grid rows 1–2, pills 3,
  /// headings 4/6, status cards 5, server pills 7, core log 8.
  /// With no route (bare-harness pumps) the child renders untouched.
  static Widget _enter(
    BuildContext context,
    MotionStyle style,
    int block,
    Widget child,
  ) =>
      motionCascade(context, style, block, child);

  Future<void> _openTelegram() async {
    final uri = Uri.parse(telegramChannelUrl);
    // External browser/app — never an in-app webview (same as home).
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// v4.22 — pushes one of the eight sub-pages (the six cards, the two
  /// family pills, the status cards all land here). v4.25 — every push
  /// rides [aethPageRoute]: the page enters with the SELECTED STYLE'S own
  /// personality (SILK fade-rise / TIDE zoom-dissolve / SPRING pop /
  /// BLINK fade / OFF instant cut).
  void _openSubPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      aethPageRoute<void>(
        style: store.effectiveMotionStyle(context),
        builder: (_) => page,
      ),
    );
  }

  /// v4.21 — opens the core diagnostics page (the captured stderr of both
  /// engines — owner: «چطوره اون بخش متن خطا لاگ کل هسته هارو هم بده تا
  /// بهتر بتونیم دیباگ کنیم»). v4.22 — carries the appearance switch so
  /// the page honors the patterns-off preference too. v4.25 — the honest
  /// connected state + the effective motion style ride along (the page's
  /// patterns were hardcoded red/static — state honesty, the app's #1
  /// rule), and the push itself is style-personal.
  void _openCoreLog(BuildContext context) {
    Navigator.of(context).push(
      aethPageRoute<void>(
        style: store.effectiveMotionStyle(context),
        builder: (_) => CoreLogPage(
          showPatterns: store.showPatterns,
          connected: store.isConnected,
          style: store.effectiveMotionStyle(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    // The APP's ambient direction (fa ⇒ RTL), read ABOVE the LTR geometry
    // lock below — Persian text inside the lock keeps its natural bidi
    // direction (e.g. the trailing «...» of the pill subtitles).
    final appDir = Directionality.maybeOf(context) ?? TextDirection.ltr;

    // Subscribed to the store: the status cards + patterns re-render on
    // every preference/state change (same pattern as the home screen).
    // v4.25 — the effective style (the master kill-switch clamps to OFF)
    // drives the cascade AND the small controls (MotionScope below).
    final style = store.effectiveMotionStyle(context);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        backgroundColor: AethColors.bgScreen,
        // v4.25 — THE pattern-placement fix: the default `StackFit.loose`
        // let the Stack collapse to the CONTENT height (~855 of 874 on the
        // reference frame), so the `Positioned.fill` pattern box was SHORT
        // and the whole composition shifted up — the owner's «مکان درستی
        // نداره باید دقیقا مکانش مثل صفحه اصلی باشه». `StackFit.expand`
        // pins the body (and with it the pattern) to the FULL screen on
        // every device; the ScrollView simply scrolls inside it.
        body: Stack(
          fit: StackFit.expand,
          children: [
            // v4.21 — the owner's decree: the settings page carries the
            // HOME screen's patterns, exactly the same, same position
            // («از پترن های صفحه اصلی برای سایر صفحات مثل انتخاب پروتکل و
            // تنطیمات استفاده کن دقیقا همونا با همون مکان»; v4.25 — one
            // single composition, no per-page variant left in the code).
            // v4.22 — gated by the appearance switch (bare bg when off).
            if (store.showPatterns)
              Positioned.fill(
                child: PatternSides(
                  connected: store.isConnected,
                  style: style,
                ),
              ),
            // v4.10 lesson (main-screen defect): under the fa/RTL locale a
            // plain Row MIRRORS — the settings frame's pixel layout is
            // LTR-locked here (geometry only; Persian text inside renders
            // with its own bidi direction via [appDir]).
            SafeArea(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AethGeometry.pageHPadding * s,
                    ),
                    child: MotionScope(
                      style: style,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: AethGeometry.topSafeExtraGap * s),
                          _enter(context, style, 0, _SettingsTopBar(
                            onInfo: _openTelegram,
                            onBack: () => Navigator.of(context).maybePop(),
                          )),
                          SizedBox(height: 22 * s),
                          _enter(context, style, 1, _SixCardGrid(
                            onCardTap: (i) => _openSubPage(
                              context,
                              switch (i) {
                                0 => RoutingSettingsPage(store: store),
                                1 => GeneralSettingsPage(store: store),
                                2 => ConnectionSettingsPage(store: store),
                                3 => LanguageSettingsPage(store: store),
                                4 => AppearanceSettingsPage(store: store),
                                _ => SecuritySettingsPage(store: store),
                              },
                            ),
                          )),
                          SizedBox(height: AethGeometry.settingsPillGap * s),
                          _enter(context, style, 3, _ProtocolPills(
                            textDir: appDir,
                            onPsiphon: () => _openSubPage(
                              context,
                              PsiphonSettingsPage(store: store),
                            ),
                            onTor: () => _openSubPage(
                              context,
                              TorSettingsPage(store: store),
                            ),
                          )),
                          SizedBox(
                            height: AethGeometry.settingsHeadingGapFromPills * s,
                          ),
                          _enter(context, style, 4, _SectionHeading(
                            icon: AppAssets.iconMenuFries,
                            title: strings.settingsAdvancedStatus,
                          )),
                          SizedBox(
                            height: AethGeometry.settingsHeadingGapToCards * s,
                          ),
                          _enter(context, style, 5, _StatusCards(
                            store: store,
                            onKillSwitch: () => _openSubPage(
                              context,
                              SecuritySettingsPage(store: store),
                            ),
                            onRoutingArea: () => _openSubPage(
                              context,
                              RoutingSettingsPage(store: store),
                            ),
                            onProtocol: () => _openSubPage(
                              context,
                              ConnectionSettingsPage(store: store),
                            ),
                          )),
                          SizedBox(
                            height: AethGeometry.settingsHeading2GapToServer * s,
                          ),
                          _enter(context, style, 6, _SectionHeading(
                            icon: AppAssets.iconSituation1,
                            title: strings.settingsMainServer,
                          )),
                          SizedBox(
                            height: AethGeometry.settingsHeadingGapToCards * s,
                          ),
                          _enter(context, style, 7, const _ServerPills()),
                          SizedBox(height: 22 * s),
                          // v4.21 — the core diagnostics entry (owner:
                          // «چطوره اون بخش متن خطا لاگ کل هسته هارو هم بده تا
                          // بهتر بتونیم دیباگ کنیم») — the full captured
                          // stderr of the engines, tailed live.
                          _enter(context, style, 8, _CoreLogCard(
                            onTap: () => _openCoreLog(context),
                          )),
                          SizedBox(height: 30 * s),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar: chevron (back) · «تنظیمات» · info (Telegram)
// ---------------------------------------------------------------------------

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.onBack, required this.onInfo});

  final VoidCallback onBack;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final tile = AethGeometry.topTileSize * s;
    return SizedBox(
      height: tile,
      child: Row(
        children: [
          // LTR-locked (parent) — visual LEFT: the info tile (i → Telegram).
          _TileButton(
            asset: AppAssets.iconInformationCircle,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Telegram channel',
            onTap: onInfo,
          ),
          const Spacer(),
          Text(
            strings.settingsTitle,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w700,
              fontSize: 17 * s,
              color: AethColors.textPrimary,
            ),
          ),
          const Spacer(),
          // Visual RIGHT: the back chevron tile (Right 2 like the frame).
          _TileButton(
            asset: AppAssets.iconRight2,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Back',
            onTap: onBack,
          ),
        ],
      ),
    );
  }
}

/// The owner «Rectangle 9» tile (50×50, #0F1510, r16, soft shadow) — the
/// exact same tile as the home top bar.
class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.asset,
    required this.size,
    required this.iconSize,
    required this.semanticLabel,
    this.onTap,
  });

  final String asset;
  final double size;
  final double iconSize;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AethColors.topTile,
            borderRadius:
                BorderRadius.circular(AethGeometry.topTileRadius * s),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000), // rgba(0,0,0,0.25) 0 4 4
                offset: Offset(0, 4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              asset,
              width: iconSize,
              height: iconSize,
              colorFilter: const ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Six category cards (3 × 2)
// ---------------------------------------------------------------------------

class _SixCardGrid extends StatelessWidget {
  const _SixCardGrid({required this.onCardTap});

  /// v4.22 — the card's index (0..5, row-major): the page router in
  /// [SettingsScreen.build] maps it to its sub-page (NEVER the localized
  /// title — the index is locale-proof).
  final void Function(int index) onCardTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    // VISUAL left→right per row — the parent Directionality is LTR-locked
    // so the children land EXACTLY on the frame's measured positions
    // (row 1: مسیریابی‌ها x33 · عمومی x150 · اتصال x267).
    final row1 = [
      (
        asset: AppAssets.iconRedo,
        title: strings.settingsRouting,
        sub: strings.settingsRoutingSub,
      ),
      (
        asset: AppAssets.iconFilter5,
        title: strings.settingsGeneral,
        sub: strings.settingsGeneralSub,
      ),
      (
        asset: AppAssets.iconLock1,
        title: strings.settingsConnection,
        sub: strings.settingsConnectionSub,
      ),
    ];
    final row2 = [
      (
        asset: AppAssets.iconWebsite,
        title: strings.settingsLanguage,
        sub: strings.settingsLanguageSub,
      ),
      (
        asset: AppAssets.iconPalette,
        title: strings.settingsAppearance,
        sub: strings.settingsAppearanceSub,
      ),
      (
        asset: AppAssets.iconSecuritySafe,
        title: strings.settingsSecurity,
        sub: strings.settingsSecuritySub,
      ),
    ];
    return Column(
      children: [
        _cardRow(context, row1, 0),
        SizedBox(height: AethGeometry.settingsRowGap * s),
        _cardRow(context, row2, 3),
      ],
    );
  }

  Widget _cardRow(
    BuildContext context,
    List<({String asset, String title, String sub})> cards,
    int baseIndex,
  ) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Row(
      children: [
        for (final (i, c) in cards.indexed) ...[
          if (i > 0) SizedBox(width: AethGeometry.settingsCardGap * s),
          Expanded(
            child: _SettingsCard(
              asset: c.asset,
              title: c.title,
              subtitle: c.sub,
              onTap: () => onCardTap(baseIndex + i),
            ),
          ),
        ],
      ],
    );
  }
}

/// One settings card — the shared template: green line icon top, white
/// title, grey subtitle (or GREEN value for the status cards).
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.asset,
    required this.title,
    required this.subtitle,
    this.subtitleColor = AethColors.textSecondary,
    this.onTap,
  });

  final String asset;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: AethGeometry.settingsCardH * s,
        decoration: BoxDecoration(
          color: AethColors.cardDark,
          borderRadius:
              BorderRadius.circular(AethGeometry.settingsCardRadius * s),
        ),
        child: Stack(
          children: [
            Positioned(
              top: (AethGeometry.settingsCardIconTop -
                      AethGeometry.settingsCardIconSize / 2) *
                  s,
              left: 0,
              right: 0,
              child: Center(
                child: SvgPicture.asset(
                  asset,
                  width: AethGeometry.settingsCardIconSize * s,
                  height: AethGeometry.settingsCardIconSize * s,
                  colorFilter: const ColorFilter.mode(
                    AethColors.accentConnected,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            Positioned(
              top: (AethGeometry.settingsCardTitleCenter -
                      AethGeometry.settingsCardTitleSize) *
                  s,
              left: 6 * s,
              right: 6 * s,
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w600,
                    fontSize: AethGeometry.settingsCardTitleSize * s,
                    color: AethColors.textPrimary,
                  ),
                ),
              ),
            ),
            Positioned(
              top: (AethGeometry.settingsCardSubCenter -
                      AethGeometry.settingsCardSubSize) *
                  s,
              left: 6 * s,
              right: 6 * s,
              child: Center(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w400,
                    fontSize: AethGeometry.settingsCardSubSize * s,
                    color: subtitleColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Psiphon / Tor wide pills
// ---------------------------------------------------------------------------

class _ProtocolPills extends StatelessWidget {
  const _ProtocolPills({
    required this.textDir,
    required this.onPsiphon,
    required this.onTor,
  });

  final TextDirection textDir;
  final VoidCallback onPsiphon;
  final VoidCallback onTor;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Row(
      children: [
        // LTR-locked: visual LEFT = Psiphon (x35), RIGHT = Tor (x214) —
        // the frame's measured pill positions.
        Expanded(
          child: _WidePill(
            logo: AppAssets.protocolPsiphonLogo,
            logoBox: AethGeometry.settingsPillLogoPsiphon * s,
            title: strings.settingsPsiphon,
            subtitle: strings.settingsPillSub,
            textDir: textDir,
            onTap: onPsiphon,
          ),
        ),
        SizedBox(width: AethGeometry.settingsPillGap * s),
        Expanded(
          child: _WidePill(
            logo: AppAssets.protocolTorLogo,
            logoBox: AethGeometry.settingsPillLogoTor * s,
            title: strings.settingsTor,
            subtitle: strings.settingsPillSub,
            textDir: textDir,
            onTap: onTor,
          ),
        ),
      ],
    );
  }
}

/// The wide pill (سایفون/تور): real protocol logo tinted accent
/// green at the LEADING edge (visual right in RTL), texts stacked after it.
/// v4.15 #3 — corners follow the owner CSS «Rectangle 79» (r24), replacing
/// the v4.14 stadium (h/2 = 43.5).
class _WidePill extends StatelessWidget {
  const _WidePill({
    required this.logo,
    required this.logoBox,
    required this.title,
    required this.subtitle,
    required this.textDir,
    this.onTap,
  });

  final String logo;

  /// The PNG canvas box — sized per logo so the artwork GLYPH matches the
  /// frame (the canvases carry different artwork fills).
  final double logoBox;
  final String title;
  final String subtitle;
  final TextDirection textDir;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final h = AethGeometry.settingsPillH * s;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: AethColors.cardDark,
          // v4.15 #3 — owner CSS Rectangle 79: r24, never a stadium.
          borderRadius:
              BorderRadius.circular(AethGeometry.settingsPillRadius * s),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AethGeometry.settingsPillInset * s,
        ),
        child: Row(
          children: [
            // LTR-locked parent: texts render at the visual LEFT (measured
            // x60–147), end-aligned toward the logo.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDir,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w600,
                      fontSize: AethGeometry.settingsPillTitleSize * s,
                      color: AethColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDir,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w400,
                      fontSize: AethGeometry.settingsPillSubSize * s,
                      color: AethColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10 * s),
            // The REAL protocol logo at the visual RIGHT edge (x148–173),
            // accent-green like the frame.
            Image.asset(
              logo,
              width: logoBox,
              height: logoBox,
              fit: BoxFit.contain,
              color: AethColors.accentConnected,
              colorBlendMode: BlendMode.srcIn,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section headings
// ---------------------------------------------------------------------------

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});

  final String icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final Widget iconWidget = SvgPicture.asset(
      icon,
      width: AethGeometry.settingsHeadingIconSize * s,
      height: AethGeometry.settingsHeadingIconSize * s,
      colorFilter: const ColorFilter.mode(
        AethColors.textPrimary,
        BlendMode.srcIn,
      ),
    );
    // LTR-locked parent: the heading block hugs the visual RIGHT edge
    // (measured: text x220–333, icon x336–364, block ends at x368).
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w700,
              fontSize: AethGeometry.settingsHeadingSize * s,
              color: AethColors.textPrimary,
            ),
          ),
          SizedBox(width: 8 * s),
          iconWidget,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status cards — REAL store state (report D2)
// ---------------------------------------------------------------------------

class _StatusCards extends StatelessWidget {
  const _StatusCards({
    required this.store,
    required this.onKillSwitch,
    required this.onRoutingArea,
    required this.onProtocol,
  });

  final ConnectionStore store;

  /// v4.22 — the three cards are now TAPPABLE: each opens the page that
  /// owns its value (the owner: «تنظیمات به درستی توی دسته بندی مناسب
  /// خودشون قرار بگیرن و به صفحه اصلی تنظیمات متصل باشن»).
  final VoidCallback onKillSwitch;
  final VoidCallback onRoutingArea;
  final VoidCallback onProtocol;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Row(
      children: [
        // LTR-locked: visual left→right exactly like the frame —
        // Kill Switch (x33) · منطقهٔ مسیریابی (x150) · پروتکل (x267).
        // The protocol value renders the mode's Latin name exactly like
        // the frame («AUTO / SMART"); SMART alone when smart is picked
        // (the subpage flips it).
        Expanded(
          child: _SettingsCard(
            // v4.17 — owner round #1: the Kill Switch card takes the set's
            // power glyph (Off.svg — the owner's message cut the icon name
            // off; one-line swap when the exact name arrives).
            asset: AppAssets.iconOff,
            title: 'Kill Switch',
            subtitle: store.killSwitch ? 'ON' : 'OFF',
            subtitleColor: store.killSwitch
                ? AethColors.accentConnected
                : AethColors.textSecondary,
            onTap: onKillSwitch,
          ),
        ),
        SizedBox(width: AethGeometry.settingsCardGap * s),
        Expanded(
          child: _SettingsCard(
            asset: AppAssets.iconRedo,
            title: strings.settingsRoutingArea,
            subtitle: strings.routingRegionName(store.routingRegion),
            subtitleColor: AethColors.accentConnected,
            onTap: onRoutingArea,
          ),
        ),
        SizedBox(width: AethGeometry.settingsCardGap * s),
        Expanded(
          child: _SettingsCard(
            // v4.17 — owner round #2: the protocol card takes Swap 1.svg.
            asset: AppAssets.iconSwap1,
            title: strings.protocol,
            subtitle: store.protocolModeSmart ? 'SMART' : 'AUTO / SMART',
            subtitleColor: AethColors.accentConnected,
            onTap: onProtocol,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Server pills (Zeptun Tunnel / Aether Core) — GitHub logos.
// v4.15 #3 — corners r20 (owner CSS Rectangle 79 scaled 24 × 70/84),
// replacing the v4.14 stadium (h/2 = 35).
// ---------------------------------------------------------------------------
class _ServerPills extends StatelessWidget {
  const _ServerPills();

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final h = AethGeometry.settingsServerPillH * s;
    Widget pill(String title) => Expanded(
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: AethColors.cardDark,
              borderRadius: BorderRadius.circular(
                AethGeometry.settingsServerPillRadius * s,
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: AethGeometry.settingsServerInset * s,
            ),
            child: Row(
              children: [
                // GitHub logo at the TRAILING edge (visual left in the
                // frame — pixel-verified: logo x50–83, text x94–174).
                SvgPicture.asset(
                  AppAssets.logoGithub,
                  width: AethGeometry.settingsServerLogoSize * s,
                  height: AethGeometry.settingsServerLogoSize * s,
                  fit: BoxFit.contain,
                  colorFilter: const ColorFilter.mode(
                    AethColors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
                SizedBox(width: 10 * s),
                Expanded(
                  // FittedBox keeps the FULL title inside the pill at any
                  // locale/font — never «Zeptun Tun…» (device-test lesson).
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w600,
                        fontSize: AethGeometry.settingsPillTitleSize * s,
                        color: AethColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        // LTR-locked: visual LEFT = Zeptun Tunnel, RIGHT = Aether Core
        // (the frame's measured positions).
        pill('Zeptun Tunnel'),
        SizedBox(width: AethGeometry.settingsPillGap * s),
        pill('Aether Core'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// v4.21 — the core diagnostics entry + page (owner device-test round 3:
// «چطوره اون بخش متن خطا لاگ کل هسته هارو هم بده تا بهتر بتونیم دیباگ
// کنیم»). The Kotlin layer redirects the process stderr (aether's
// env_logger + the zeptun JNI) into filesDir/logs/core-log.txt; this page
// tails that capture live. Same visual language as the rest of the app
// (dark card, IRANYekanX, the home patterns behind).
// ---------------------------------------------------------------------------

class _CoreLogCard extends StatelessWidget {
  const _CoreLogCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Semantics(
      button: true,
      label: strings.coreLogTitle,
      child: GestureDetector(
        key: const ValueKey('settings-core-log-card'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 58 * s,
          decoration: BoxDecoration(
            color: AethColors.cardDark,
            borderRadius:
                BorderRadius.circular(AethGeometry.settingsPillRadius * s),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                const SizedBox(width: 16),
                SvgPicture.asset(
                  AppAssets.iconInformationCircle,
                  width: 22 * s,
                  height: 22 * s,
                  colorFilter: const ColorFilter.mode(
                    AethColors.accentConnected,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.coreLogTitle,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w500,
                      fontSize: AethGeometry.settingsPillTitleSize * s,
                      color: AethColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  strings.coreLogOpen,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w400,
                    fontSize: 12 * s,
                    color: AethColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full-screen core log viewer: tails the capture every 2 s while
/// open, supports copy (share sheet is out of scope — Clipboard + a toast
/// is honest) and clear.
class CoreLogPage extends StatefulWidget {
  const CoreLogPage({
    super.key,
    this.showPatterns = true,
    this.connected = false,
    this.style = MotionStyle.standard,
  });

  /// v4.22 — the appearance switch (bare bg when off, like every page).
  final bool showPatterns;

  /// v4.25 — the HONEST connection state + the effective motion style:
  /// the page's patterns used to be hardcoded red/static, which broke the
  /// app's #1 rule (animation reflects state) whenever the log was opened
  /// from a CONNECTED session.
  final bool connected;
  final MotionStyle style;

  @override
  State<CoreLogPage> createState() => _CoreLogPageState();
}

class _CoreLogPageState extends State<CoreLogPage> {
  final CoreLogReader _reader = CoreLogReader();
  CoreLogSnapshot _snapshot = const CoreLogSnapshot(text: '', totalBytes: 0);
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final snapshot = await _reader.read();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await _reader.clear();
    await _refresh();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _snapshot.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).coreLogCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AethColors.bgScreen,
        // v4.25 — the pattern-placement fix (see the settings page's Stack):
        // expand keeps the pattern box at the FULL screen height.
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The home patterns behind (v4.21 — same composition as every
            // page; v4.22 — honors the appearance switch; v4.25 — the
            // honest connected state + the effective motion style).
            if (widget.showPatterns)
              Positioned.fill(
                child: PatternSides(
                  connected: widget.connected,
                  style: widget.style,
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  // Header row: back · title · copy · clear
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        IconButton(
                          key: const ValueKey('core-log-back'),
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: SvgPicture.asset(
                            AppAssets.iconRight2,
                            width: 22,
                            height: 22,
                            colorFilter: const ColorFilter.mode(
                              AethColors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            strings.coreLogTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'IRANYekanX',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AethColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('core-log-copy'),
                          tooltip: strings.coreLogCopy,
                          onPressed: _snapshot.isEmpty ? null : _copy,
                          icon: SvgPicture.asset(
                            AppAssets.iconSend,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              _snapshot.isEmpty
                                  ? AethColors.textSecondary
                                  : AethColors.accentConnected,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('core-log-clear'),
                          tooltip: strings.coreLogClear,
                          onPressed: _snapshot.isEmpty ? null : _clear,
                          icon: SvgPicture.asset(
                            AppAssets.iconClose,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              _snapshot.isEmpty
                                  ? AethColors.textSecondary
                                  : AethColors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        strings.coreLogSize(_snapshot.totalBytes),
                        style: const TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w400,
                          fontSize: 11,
                          color: AethColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Container(
                      key: const ValueKey('core-log-body'),
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: AethColors.cardDark,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AethColors.accentConnected,
                              ),
                            )
                          : _snapshot.isEmpty
                              ? Center(
                                  child: Text(
                                    strings.coreLogEmpty,
                                    style: const TextStyle(
                                      fontFamily: 'IRANYekanX',
                                      fontWeight: FontWeight.w400,
                                      fontSize: 13,
                                      color: AethColors.textSecondary,
                                    ),
                                  ),
                                )
                          : Scrollbar(
                              child: SingleChildScrollView(
                                // The core's own lines are LTR (English +
                                // timestamps); one line per log record.
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: SelectionArea(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        _snapshot.text,
                                        key: const ValueKey(
                                          'core-log-text',
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'IRANYekanX',
                                          fontWeight: FontWeight.w400,
                                          fontSize: 11,
                                          height: 1.5,
                                          color: AethColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
