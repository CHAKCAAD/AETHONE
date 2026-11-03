/// The Settings main page — pixel-faithful rebuild of the owner's design
/// frame «صفحه تنظیمات.jpg» (402×874; every geometry value measured on the
/// 3× source and recorded in [AethGeometry] as `settings*` tokens).
///
/// Structure (phase-1 report §3.2 + pixel extraction):
///   * Top bar: chevron tile (Right 2, visual RIGHT = back) · «تنظیمات»
///     centered · info tile (Information Circle, visual LEFT → the Telegram
///     channel, same behaviour as the home top bar).
///   * Six cards, 3 columns × 2 rows (icon top / title / subtitle):
///       row 1 visual L→R: مسیریابی‌ها (Forward) · تنظیمات عمومی
///       (Filter 5) · تنظیمات اتصال (Lock 1)
///       row 2 visual L→R: تنظیمات زبان (Website) · تنظیمات ظاهری
///       (Palette) · تنظیمات امنیت (Shield Star)
///   * Two wide stadium pills — تنظیمات سایفون / تنظیمات تور — the REAL
///     protocol logos (pre-rendered PNGs) tinted accent green at the
///     leading edge, like the frame.
///   * Section «وضعیت پیشرفته» (hamburger icon) + THREE status cards on
///     the same 3-col grid — every value is the REAL store state
///     (report D2: «هر سه کارت وضعیت به دادهٔ واقعی نگاشت شدند»):
///       Kill Switch → ON/OFF · منطقهٔ مسیریابی → Latin region name ·
///       پروتکل → AUTO / SMART.
///   * Section «آدرس سرور اصلی» (crosshair icon — the set has no
///     crosshair, so it is drawn as a CustomPainter in the set's stroke
///     style per the doc's missing-artwork rule) + two stadium pills:
///     Zeptun Tunnel / Aether Core with the owner's own GitHub logo SVG.
///
/// Subpages (the six categories + Psiphon/Tor sheets) are pending the
/// owner's mockup approval (doc §11.5) — the cards open the same honest
/// placeholder sheet used across the app until then.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_strings.dart';
import '../home/widgets/pattern_sides.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final ConnectionStore store;

  static const String telegramChannelUrl = 'https://t.me/AETHONE';

  Future<void> _openTelegram() async {
    final uri = Uri.parse(telegramChannelUrl);
    // External browser/app — never an in-app webview (same as home).
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openPlaceholderSheet(BuildContext context, String message) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AethColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AethColors.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w500,
                fontSize: 15,
                color: AethColors.textPrimary,
              ),
            ),
          ],
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
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        backgroundColor: AethColors.bgScreen,
        body: Stack(
          children: [
            // Same dark stage + edge patterns as the home screen (the design
            // frame carries the faint geometric patterns in the corners).
            Positioned.fill(
              child: PatternSides(
                connected: store.isConnected,
                style: store.animationStyle,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: AethGeometry.topSafeExtraGap * s),
                        _SettingsTopBar(
                          onInfo: _openTelegram,
                          onBack: () => Navigator.of(context).maybePop(),
                        ),
                        SizedBox(height: 22 * s),
                        _SixCardGrid(
                          onCardTap: (title) => _openPlaceholderSheet(
                            context,
                            '$title — ${strings.settingsSubpageComingNext}',
                          ),
                        ),
                        SizedBox(height: AethGeometry.settingsPillGap * s),
                        _ProtocolPills(
                          textDir: appDir,
                          onPsiphon: () => _openPlaceholderSheet(
                            context,
                            '${strings.settingsPsiphon} — '
                            '${strings.settingsSubpageComingNext}',
                          ),
                          onTor: () => _openPlaceholderSheet(
                            context,
                            '${strings.settingsTor} — '
                            '${strings.settingsSubpageComingNext}',
                          ),
                        ),
                        SizedBox(
                          height: AethGeometry.settingsHeadingGapFromPills * s,
                        ),
                        _SectionHeading(
                          icon: AppAssets.iconMenuHamburger,
                          title: strings.settingsAdvancedStatus,
                        ),
                        SizedBox(
                          height: AethGeometry.settingsHeadingGapToCards * s,
                        ),
                        _StatusCards(store: store),
                        SizedBox(
                          height: AethGeometry.settingsHeading2GapToServer * s,
                        ),
                        _SectionHeading.custom(
                          customIcon: CrosshairIcon(
                            size: AethGeometry.settingsHeadingIconSize * s,
                          ),
                          title: strings.settingsMainServer,
                        ),
                        SizedBox(
                          height: AethGeometry.settingsHeadingGapToCards * s,
                        ),
                        const _ServerPills(),
                        SizedBox(height: 30 * s),
                      ],
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

  final void Function(String title) onCardTap;

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
        asset: AppAssets.iconShieldStar,
        title: strings.settingsSecurity,
        sub: strings.settingsSecuritySub,
      ),
    ];
    return Column(
      children: [
        _cardRow(context, row1),
        SizedBox(height: AethGeometry.settingsRowGap * s),
        _cardRow(context, row2),
      ],
    );
  }

  Widget _cardRow(
    BuildContext context,
    List<({String asset, String title, String sub})> cards,
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
              onTap: () => onCardTap(c.title),
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

/// The wide stadium pill (سایفون/تور): real protocol logo tinted accent
/// green at the LEADING edge (visual right in RTL), texts stacked after it.
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
          borderRadius: BorderRadius.circular(h / 2), // stadium
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
  const _SectionHeading({required this.icon, required this.title})
      : customIcon = null;

  const _SectionHeading.custom({required this.customIcon, required this.title})
      : icon = null;

  final String? icon;
  final Widget? customIcon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final Widget iconWidget;
    if (customIcon != null) {
      iconWidget = customIcon!;
    } else {
      iconWidget = SvgPicture.asset(
        icon!,
        width: AethGeometry.settingsHeadingIconSize * s,
        height: AethGeometry.settingsHeadingIconSize * s,
        colorFilter: const ColorFilter.mode(
          AethColors.textPrimary,
          BlendMode.srcIn,
        ),
      );
    }
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
  const _StatusCards({required this.store});

  final ConnectionStore store;

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
            asset: AppAssets.iconRedo,
            title: 'Kill Switch',
            subtitle: store.killSwitch ? 'ON' : 'OFF',
            subtitleColor: store.killSwitch
                ? AethColors.accentConnected
                : AethColors.textSecondary,
          ),
        ),
        SizedBox(width: AethGeometry.settingsCardGap * s),
        Expanded(
          child: _SettingsCard(
            asset: AppAssets.iconRedo,
            title: strings.settingsRoutingArea,
            subtitle: strings.routingRegionName(store.routingRegion),
            subtitleColor: AethColors.accentConnected,
          ),
        ),
        SizedBox(width: AethGeometry.settingsCardGap * s),
        Expanded(
          child: _SettingsCard(
            asset: AppAssets.iconScan1,
            title: strings.protocol,
            subtitle: store.protocolModeSmart ? 'SMART' : 'AUTO / SMART',
            subtitleColor: AethColors.accentConnected,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Server pills (Zeptun Tunnel / Aether Core) — GitHub logos
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
              borderRadius: BorderRadius.circular(h / 2),
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
// Crosshair icon — the icon set has NO crosshair, so it is drawn in the
// set's own stroke style (round caps, hairline): a rounded square frame
// with side notches, four cross lines and a center ring with a dot.
// ---------------------------------------------------------------------------

class CrosshairIcon extends StatelessWidget {
  const CrosshairIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CrosshairPainter(color ?? AethColors.textPrimary),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final r = w * 0.16; // frame corner radius
    final c = Offset(w / 2, w / 2);
    final gap = w * 0.18; // side notch half-length

    // Rounded-square frame with a notch in the middle of each side.
    final frame = Path()
      ..moveTo(r, 0)
      ..lineTo(w / 2 - gap, 0)
      ..moveTo(w / 2 + gap, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..moveTo(w, w / 2 - gap)
      ..lineTo(w, w / 2 + gap)
      ..moveTo(w, w - r)
      ..arcToPoint(Offset(w - r, w), radius: Radius.circular(r))
      ..moveTo(w / 2 + gap, w)
      ..lineTo(w / 2 - gap, w)
      ..moveTo(r, w)
      ..arcToPoint(Offset(0, w - r), radius: Radius.circular(r))
      ..moveTo(0, w / 2 + gap)
      ..lineTo(0, w / 2 - gap)
      ..moveTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r));
    canvas.drawPath(frame, paint);

    // Four cross lines through the notches.
    canvas.drawLine(Offset(w * 0.28, c.dy), Offset(w * 0.72, c.dy), paint);
    canvas.drawLine(Offset(c.dx, w * 0.28), Offset(c.dx, w * 0.72), paint);

    // Center ring + dot.
    canvas.drawCircle(c, w * 0.13, paint);
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, w * 0.045, dot);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.color != color;
}
