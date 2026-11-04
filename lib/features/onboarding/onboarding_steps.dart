/// v4.23 — the wizard's four step BODIES («صفحه شروع» frames, every value
/// measured on the 402×874 sources):
///
///  * step 1 «زبان برنامه چی باشه؟» — a centered 3×2 flag grid (65×65
///    r20 tiles, 43/30 gaps): فارسی · ترکمنی · انگلیسی / چینی · روسی ·
///    the gray SYSTEM tile (gear, dark-indigo ink);
///
///  * step 2 «ترافیک کدوم کشور مستقیم باشه؟» — the staggered routing
///    grid: ایران و ترکمنستان on the top row, روسیه و چین below, the
///    gray «none» tile (✕-in-circle) floating mid-left;
///
///  * step 3 «ضاهر دکمه اتصال چجوری باشه؟» — the two live previews: the
///    look-1 mini FAB column (dark 65×132 panel, green 48 FAB with the
///    dark power glyph, 3 red chevrons) and the look-2 core button
///    (110×110 squircle r42 with the app's own glow layer stack), the
///    Tick-Circle check badge under the SELECTED one;
///
///  * step 4 — «حالت اتصال» segments (تونل/پروکسی), the «پروتکل اتوماتیک
///    میخوای؟» option cards (Shield Star amber on the green اتوماتیک
///    card, plain Shield on the dark دستی card) and «سرعت اسکن» pills —
///    the protocol page's own geometry, all bound LIVE to the store.
///
/// Selection on the tile grids = the frames' accent ring: 2.5px stroke
/// 1px off the tile edge plus a soft green glow (overflow 3.5, so the
/// ring never shifts the grid).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_state.dart';
import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_strings.dart';
import '../home/widgets/glow_pill.dart';

// ---------------------------------------------------------------------------
// The shared tile: 65×65 r20 face + the accent selection ring.
// ---------------------------------------------------------------------------

class ObTile extends StatelessWidget {
  const ObTile({
    super.key,
    required this.keyId,
    required this.selected,
    required this.onTap,
    required this.face,
  });

  final String keyId;
  final bool selected;
  final VoidCallback onTap;
  final Widget face;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.obTileSize * s;
    final ring = size + 2 * (AethGeometry.obRingStroke + AethGeometry.obRingGap + 0.5) * s;
    return Semantics(
      label: keyId,
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey(keyId),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(AethGeometry.obTileRadius * s),
                child: SizedBox(width: size, height: size, child: face),
              ),
              if (selected)
                Positioned(
                  left: -(ring - size) / 2,
                  top: -(ring - size) / 2,
                  width: ring,
                  height: ring,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AethGeometry.obRingRadius * s,
                        ),
                        border: Border.all(
                          color: AethColors.accentConnected,
                          width: AethGeometry.obRingStroke * s,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AethColors.accentConnected
                                .withValues(alpha: 0.35),
                            blurRadius: 10 * s,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flag face — the app's own pre-rendered 256×256 flag PNGs.
Widget _flagFace(String code) => Image.asset(
      AppAssets.flag(code),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );

/// The gray tile face — light-gray fill + the dark-indigo glyph.
Widget _grayFace(String icon) => LayoutBuilder(
      builder: (context, box) => Container(
        color: AethColors.tileGray,
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: SvgPicture.asset(
            icon,
            width: AethGeometry.obGrayGlyph * (box.maxWidth / 65),
            height: AethGeometry.obGrayGlyph * (box.maxWidth / 65),
            colorFilter: const ColorFilter.mode(
              AethColors.tileGrayInk,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Step 1 — the language grid (3×2, centered; RTL: فارسی lands top-right).
// ---------------------------------------------------------------------------

class ObLanguageTiles extends StatelessWidget {
  const ObLanguageTiles({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final gap = AethGeometry.obTileGapX * s;

    // The wizard's fresh-install default is 'fa' (applied at restore); a
    // null store value means the user explicitly picked SYSTEM.
    final current = store.appLocale ?? 'system';

    ObTile tile(String code, Widget face) => ObTile(
          keyId: 'ob-lang-$code',
          selected: current == code,
          onTap: () => store.setAppLocale(code == 'system' ? null : code),
          face: face,
        );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile('fa', _flagFace('ir')),
                SizedBox(width: gap),
                tile('tk', _flagFace('tm')),
                SizedBox(width: gap),
                tile('en', _flagFace('us')),
              ],
            ),
          ),
          SizedBox(height: AethGeometry.obTileGapY * s),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile('zh', _flagFace('cn')),
                SizedBox(width: gap),
                tile('ru', _flagFace('ru')),
                SizedBox(width: gap),
                tile('system', _grayFace(AppAssets.iconSetting)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — the staggered routing grid (the «none» tile floats mid-left).
// ---------------------------------------------------------------------------

class ObRoutingTiles extends StatelessWidget {
  const ObRoutingTiles({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final tile = AethGeometry.obTileSize * s;
    final gridW = 3 * tile + 2 * AethGeometry.obTileGapX * s;
    final current = store.routingRegion ?? 'none';

    ObTile make(String code, Widget face) => ObTile(
          keyId: 'ob-route-$code',
          selected: current == code,
          onTap: () => store.setRoutingRegion(code == 'none' ? null : code),
          face: face,
        );

    return Center(
      child: SizedBox(
        width: gridW,
        height: 2 * tile + AethGeometry.obTileGapY * s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Local x: 0 = the grid's LEFT column, 2 = the RIGHT (RTL
            // first) column — measured straight off the frame.
            Positioned(
              left: 2 * (tile + AethGeometry.obTileGapX * s),
              top: 0,
              child: make('ir', _flagFace('ir')),
            ),
            Positioned(
              left: tile + AethGeometry.obTileGapX * s,
              top: 0,
              child: make('tm', _flagFace('tm')),
            ),
            Positioned(
              left: 0,
              top: AethGeometry.obMidTileTop * s,
              child: make('none', _grayFace(AppAssets.iconCloseCircle)),
            ),
            Positioned(
              left: tile + AethGeometry.obTileGapX * s,
              top: tile + AethGeometry.obTileGapY * s,
              child: make('ru', _flagFace('ru')),
            ),
            Positioned(
              left: 2 * (tile + AethGeometry.obTileGapX * s),
              top: tile + AethGeometry.obTileGapY * s,
              child: make('cn', _flagFace('cn')),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — the two look previews with the moving check badge.
// ---------------------------------------------------------------------------

class ObLookPreviews extends StatelessWidget {
  const ObLookPreviews({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final glowH = AethGeometry.obCoreButton * 1.42 * s;
    final zoneH = glowH + AethGeometry.obCheckGap * s + AethGeometry.obCheckBadge * s;

    return SizedBox(
      height: zoneH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left zone (visual left): the look-1 FAB column preview.
          Expanded(
            child: _LookGroup(
              keyId: 'ob-look-one',
              selected: store.homeLook == HomeLook.one,
              onTap: () => store.setHomeLook(HomeLook.one),
              preview: _FabColumnPreview(s: s),
            ),
          ),
          // Right zone: the look-2 center button preview.
          Expanded(
            child: _LookGroup(
              keyId: 'ob-look-two',
              selected: store.homeLook == HomeLook.two,
              onTap: () => store.setHomeLook(HomeLook.two),
              preview: _CoreButtonPreview(s: s),
            ),
          ),
        ],
      ),
    );
  }
}

/// One preview group: the preview centered in a 1.42× glow-tall box, then
/// the check badge slot 20 below (the badge rides the SELECTED group —
/// the frame ships it under the look-1 column).
class _LookGroup extends StatelessWidget {
  const _LookGroup({
    required this.keyId,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String keyId;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final glowH = AethGeometry.obCoreButton * 1.42 * s;
    return GestureDetector(
      key: ValueKey(keyId),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: glowH,
            child: Center(child: preview),
          ),
          SizedBox(height: AethGeometry.obCheckGap * s),
          SizedBox(
            width: AethGeometry.obCheckBadge * s,
            height: AethGeometry.obCheckBadge * s,
            child: selected
                ? Container(
                    decoration: BoxDecoration(
                      color: AethColors.accentConnected,
                      borderRadius: BorderRadius.circular(
                        AethGeometry.obCheckBadgeRadius * s,
                      ),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        AppAssets.iconTickCircle,
                        width: AethGeometry.obCheckBadge * 0.7 * s,
                        height: AethGeometry.obCheckBadge * 0.7 * s,
                        colorFilter: const ColorFilter.mode(
                          AethColors.onPillConnected,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The look-1 preview: the mini FAB column — dark 65×132 r20 panel, the
/// 48×48 r14 green FAB with the dark power glyph at its top, 3 red
/// chevrons low (the home screen's own column, shrunk).
class _FabColumnPreview extends StatelessWidget {
  const _FabColumnPreview({required this.s});

  final double s;

  @override
  Widget build(BuildContext context) {
    final fab = AethGeometry.obPreviewFab * s;
    return Container(
      width: AethGeometry.obPreviewColumnW * s,
      height: AethGeometry.obPreviewColumnH * s,
      decoration: BoxDecoration(
        color: AethColors.cardDark,
        borderRadius:
            BorderRadius.circular(AethGeometry.obPreviewColumnRadius * s),
      ),
      child: Column(
        children: [
          SizedBox(height: AethGeometry.obPreviewColumnTopInset * s),
          Container(
            width: fab,
            height: fab,
            decoration: BoxDecoration(
              color: AethColors.accentConnected,
              borderRadius:
                  BorderRadius.circular(AethGeometry.obPreviewFabRadius * s),
            ),
            child: Center(
              child: SvgPicture.asset(
                AppAssets.iconOff,
                width: 24 * s,
                height: 24 * s,
                fit: BoxFit.contain,
                colorFilter: const ColorFilter.mode(
                  AethColors.onPillConnected,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const Spacer(),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < 2 ? 3 * s : 0),
              child: SvgPicture.asset(
                AppAssets.iconDown1,
                width: AethGeometry.obPreviewChevronW * s,
                height: AethGeometry.obPreviewChevronH * s,
                fit: BoxFit.contain,
                colorFilter: const ColorFilter.mode(
                  AethColors.fabChevrons,
                  BlendMode.srcIn,
                ),
              ),
            ),
          SizedBox(height: 24 * s),
        ],
      ),
    );
  }
}

/// The look-2 preview: the 110×110 squircle core button with the app's
/// own glow layer stack (LayerStack — the home center-button recipe at
/// the frame's squircle corners) and the dark power glyph on top.
class _CoreButtonPreview extends StatelessWidget {
  const _CoreButtonPreview({required this.s});

  final double s;

  @override
  Widget build(BuildContext context) {
    const core = AethGeometry.obCoreButton;
    const r = AethGeometry.obCoreButtonRadius;
    return Stack(
      alignment: Alignment.center,
      children: [
        LayerStack(
          scale: s,
          color: AethColors.accentConnected,
          layers: [
            // The frame's three halo steps + the wide soft glow, radii
            // kept at the core's 42/110 squircle proportion.
            const LayerSpec(
              width: core * 1.42,
              height: core * 1.42,
              radius: r * 1.42,
              opacity: 0.30,
              blurSigma: 16,
            ),
            const LayerSpec(
              width: core * 1.25,
              height: core * 1.25,
              radius: r * 1.25,
              opacity: 0.18,
            ),
            const LayerSpec(
              width: core * 1.12,
              height: core * 1.12,
              radius: r * 1.12,
              opacity: 0.35,
            ),
            const LayerSpec(width: core, height: core, radius: r, opacity: 1.0),
          ],
        ),
        SvgPicture.asset(
          AppAssets.iconOff,
          width: AethGeometry.obCoreIcon * s,
          height: AethGeometry.obCoreIcon * s,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(
            AethColors.onPillConnected,
            BlendMode.srcIn,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — «حالت اتصال» segments + the option cards + «سرعت اسکن» pills.
// ---------------------------------------------------------------------------

class ObProtocolSections extends StatelessWidget {
  const ObProtocolSections({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: (AethGeometry.obStep4TopGap - 22) * s),
        _ObSectionHeading(
          text: strings.sheetHeadingMode,
          badge: AppAssets.iconPassword1,
        ),
        SizedBox(height: AethGeometry.obHeadingToSegments * s),
        _ObSegments(store: store),
        SizedBox(height: AethGeometry.obSegmentsToHeading * s),
        _ObSectionHeading(
          text: strings.obProtocolHeading,
          badge: AppAssets.iconSwap1,
        ),
        SizedBox(height: AethGeometry.obHeadingToCard * s),
        _ObOptionCard(
          keyId: 'ob-card-auto',
          selected: store.protocolModeSmart,
          icon: AppAssets.iconShieldStar,
          label: strings.protoAutoSheet,
          body: strings.obAutoDesc,
          onTap: () => store.setProtocolModeSmart(true),
        ),
        SizedBox(height: AethGeometry.obCardGap * s),
        _ObOptionCard(
          keyId: 'ob-card-manual',
          selected: !store.protocolModeSmart,
          icon: AppAssets.iconShield1,
          label: strings.obManualLabel,
          body: strings.obManualDesc,
          onTap: () => store.setProtocolModeSmart(false),
        ),
        SizedBox(height: AethGeometry.obCardToHeading * s),
        _ObSectionHeading(
          text: strings.sheetHeadingScanSpeed,
          badge: AppAssets.iconScan1,
        ),
        SizedBox(height: AethGeometry.obHeadingToPills * s),
        _ObScanPills(store: store),
        SizedBox(height: 24 * s),
      ],
    );
  }
}

/// A section heading — the protocol page's own row: 16 w700 white text,
/// 12 gap, the 26 badge flush with the content's right edge.
class _ObSectionHeading extends StatelessWidget {
  const _ObSectionHeading({required this.text, required this.badge});

  final String text;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          const Spacer(),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w700,
                  fontSize: AethGeometry.protoHeadingTextSize * s,
                  color: AethColors.textPrimary,
                ),
              ),
            ),
          ),
          SizedBox(width: AethGeometry.protoHeadingBadgeGap * s),
          SvgPicture.asset(
            badge,
            width: AethGeometry.protoBadgeSize * s,
            height: AethGeometry.protoBadgeSize * s,
            colorFilter: const ColorFilter.mode(
              AethColors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    );
  }
}

/// «حالت اتصال» — the protocol page's segments: h36 r14 gap21, تونل at
/// the visual RIGHT (RTL first), WHITE text on both states.
class _ObSegments extends StatelessWidget {
  const _ObSegments({required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    Widget segment(ConnectionMode mode, String label) {
      final isSel = store.connectionMode == mode;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('ob-segment-${mode.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => store.setConnectionMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            height: AethGeometry.protoSegmentH * s,
            decoration: BoxDecoration(
              color: isSel ? AethColors.accentConnected : AethColors.cardDark,
              borderRadius:
                  BorderRadius.circular(AethGeometry.protoSegmentRadius * s),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.protoSegmentTextSize * s,
                color: AethColors.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          segment(ConnectionMode.tunnel, strings.modeTunnel),
          SizedBox(width: AethGeometry.protoSegmentGap * s),
          segment(ConnectionMode.proxy, strings.modeProxy),
        ],
      ),
    );
  }
}

/// One option card: 101 tall r24, the icon+label column 56 wide at 24
/// from the card's RIGHT edge (amber glyph on the green selected card,
/// white on the dark one), the 3-line body to its left.
class _ObOptionCard extends StatelessWidget {
  const _ObOptionCard({
    required this.keyId,
    required this.selected,
    required this.icon,
    required this.label,
    required this.body,
    required this.onTap,
  });

  final String keyId;
  final bool selected;
  final String icon;
  final String label;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return GestureDetector(
      key: ValueKey(keyId),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        height: AethGeometry.obCardH * s,
        decoration: BoxDecoration(
          color: selected ? AethColors.accentConnected : AethColors.cardDark,
          borderRadius: BorderRadius.circular(AethGeometry.obCardRadius * s),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              SizedBox(width: AethGeometry.obCardColumnInset * s),
              SizedBox(
                width: AethGeometry.obCardColumnW * s,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      icon,
                      width: AethGeometry.obCardIcon * s,
                      height: AethGeometry.obCardIcon * s,
                      colorFilter: ColorFilter.mode(
                        selected
                            ? AethColors.autoShieldAmber
                            : AethColors.textPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                    SizedBox(height: 6 * s),
                    Text(
                      label,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w600,
                        fontSize: AethGeometry.obCardLabelSize * s,
                        color: AethColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: AethGeometry.obCardBodyGap * s),
              Expanded(
                child: Text(
                  body,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w400,
                    fontSize: AethGeometry.obCardBodySize * s,
                    height: AethGeometry.obCardBodyHeight,
                    color: AethColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «سرعت اسکن» — the protocol page's pill row: widths 28/47/64/77/87
/// toward the visual RIGHT (RTL), h36 r8 gap8, the widest selected.
class _ObScanPills extends StatelessWidget {
  const _ObScanPills({required this.store});

  final ConnectionStore store;

  static const List<double> _w = [
    AethGeometry.protoPillW1,
    AethGeometry.protoPillW2,
    AethGeometry.protoPillW3,
    AethGeometry.protoPillW4,
    AethGeometry.protoPillW5,
  ];

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Center(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var level = 5; level >= 1; level--)
              Padding(
                padding: EdgeInsets.only(
                  left: level == 1 ? 0 : AethGeometry.protoPillGap * s,
                ),
                child: GestureDetector(
                  key: ValueKey('ob-scan-$level'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => store.setScanSpeed(level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    width: _w[level - 1] * s,
                    height: AethGeometry.protoPillH * s,
                    decoration: BoxDecoration(
                      color: store.scanSpeed == level
                          ? AethColors.accentConnected
                          : AethColors.cardDark,
                      borderRadius:
                          BorderRadius.circular(AethGeometry.protoPillRadius * s),
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
