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
///  * step 3 «ضاهر دکمه اتصال چجوری باشه؟» — the two live previews
///    (v4.33): the look-1 slot renders the main screen's OWN FabColumn
///    (an exact copy — no chevrons, the real geometry) and the look-2
///    slot renders the REAL ConnectButtonGlow composition (the owner's
///    own CSS, scaled to the preview band), the Tick-Circle check badge
///    under the SELECTED one;
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
import '../home/widgets/bottom_panel.dart';
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
// v4.33 (owner round 9): the LEFT slot is an EXACT copy of the main
// screen's own [FabColumn] (the real widget — no more mini re-drawing with
// the chevrons the v4.15 decree removed: «این دکمه دقیقا همون دکمه صفحه
// اصلی هست همون رو عینا کپی کن همینجا»), and the RIGHT slot renders the
// REAL [ConnectButtonGlow] composition (the owner's CSS «Group 45»)
// scaled to the preview band — the very button the home screen shows in
// look 2.
// ---------------------------------------------------------------------------

class ObLookPreviews extends StatelessWidget {
  const ObLookPreviews({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final glowH = AethGeometry.obPreviewGroupSize * s;
    final zoneH =
        glowH + AethGeometry.obCheckGap * s + AethGeometry.obCheckBadge * s;

    return SizedBox(
      height: zoneH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left zone (visual left): the main screen's OWN look-1 column.
          Expanded(
            child: _LookGroup(
              keyId: 'ob-look-one',
              selected: store.homeLook == HomeLook.one,
              onTap: () => store.setHomeLook(HomeLook.one),
              // The real FabColumn — its own gestures are absorbed so the
              // GROUP's tap (the look pick) owns every touch.
              preview: AbsorbPointer(
                child: FabColumn(
                  connected: true,
                  style: store.effectiveMotionStyle(context),
                  onConnect: () {},
                  onDisconnect: () {},
                ),
              ),
            ),
          ),
          // Right zone: the main screen's look-2 button — the owner's CSS
          // composition at the preview scale.
          Expanded(
            child: _LookGroup(
              keyId: 'ob-look-two',
              selected: store.homeLook == HomeLook.two,
              onTap: () => store.setHomeLook(HomeLook.two),
              preview: const ConnectButtonGlow(
                connected: true,
                scale: AethGeometry.obPreviewGroupSize /
                    AethGeometry.connectGroupSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One preview group: the preview centered in the preview-band box, then
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
    final glowH = AethGeometry.obPreviewGroupSize * s;
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
                        colorFilter: ColorFilter.mode(
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

// ---------------------------------------------------------------------------
// Step 4 — «حالت اتصال» segments + «سرعت اسکن» pills. v4.40 (owner round
// 15: «صمت حالت پروتکل در تنظیمات اتصال برنامه رو کلا حذف کن»): the
// AUTO/SMART option cards are GONE — the setting has no picker anywhere;
// the engine keeps its persisted value.
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

/// A section heading — v4.33 (owner round 9): the SAME 20 w700 size as
/// the question headings on steps 1–3 (owner: «سایز متن سرتیترها توی هر ۴
/// صفحه باید یکسان باشه»), and the flex-split bug is gone — the old
/// [Spacer]+[Flexible] pair shared the free row space, floating the text
/// mid-row («سرتیترها… کمی وسط تر اومدن باید به سمت راست برن»); the text
/// now renders at its fixed size, right-aligned against its 26 badge with
/// the protocol page's own 12 gap.
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
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              text,
              textDirection: TextDirection.rtl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.obHeadingSize * s,
                color: AethColors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: AethGeometry.protoHeadingBadgeGap * s),
          SvgPicture.asset(
            badge,
            width: AethGeometry.protoBadgeSize * s,
            height: AethGeometry.protoBadgeSize * s,
            colorFilter: ColorFilter.mode(
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
