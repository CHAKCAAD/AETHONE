/// v4.17 — THE PROTOCOL SELECTION PAGE, promoted from the v4.16 floating
/// sheet to a full page «مثل صفحه اصلی تنظیمات» (owner round #6): the same
/// settings-page chrome around the «انتخاب پروتکل» title. v4.19 (owner
/// device test #10): the two chrome tiles SWAPPED SLOTS — the BACK chevron
/// and the INFO tile (i → Telegram channel) exchanged places («جای دکمه
/// برگشت رو با دکمه ای که آیکون تعجب داره و آدرس کانال تلگرام عملکردشه
/// جابه جا کن»). The chrome Row runs under the app's RTL directionality:
/// the FIRST Row child renders on the visual RIGHT.
///
/// The v4.16 pixel work survives verbatim (design frames «صفحه شناور انتخاب
/// پروتکل صفحه اصلی.jpg» 402×874 + «صفحه شناور توضیحات پروتکل ها.jpg»); the
/// section geometry is re-anchored to the page (AethGeometry `proto*`
/// tokens) and every v4.17 owner defect report is folded in:
///
///  * YELLOW UNDERLINES FIXED: the v4.16 sheet route built a raw Stack with
///    NO Material ancestor — Flutter deliberately paints a double yellow
///    underline under every text without one (the v4.16 capture QA
///    mis-read it as a raster artifact; the owner then reported it from the
///    device). The page sits on a Scaffold/Material — gone.
///  * LIVE BINDING: the page listens to [ConnectionStore] — «حالت اتصال»
///    segments apply visually the moment they are tapped, INDEPENDENT of
///    protocol selection (the v4.16 sheet only rebuilt when a protocol
///    tap's setState ran). v2.1.0 (the owner's decree): the «سرعت اسکن»
///    pills are BACK on this page — the Firefox card that replaced them
///    is retired with the whole Firefox protocol.
///  * Headings: «پروتکل» badge = Swap 1.svg, «حالت اتصال» keeps Password
///    1.svg; badges 20 → 26 and the text moved next to its icon
///    (gap 26 → 12). The «سرعت اسکن» heading keeps Scan 1.svg.
///  * Tiles/family cards: radius 16 → 21 (the settings cards' corners);
///    family cards breathe (h 116, subtile gaps 20, vertically centred).
///  * v4.33 (owner round 9): the ⓘ info badges and the WHOLE protocol
///    descriptions popup are REMOVED by decree («تمام آیکون‌های علامت
///    تعجب که برای توضیح پروتکل‌ها هست رو حذف بکن و کلا قسمت توضیحات
///    پروتکل رو حذف بکن»); the combined sub-tiles carry the owner's own
///    SVG logos (سایفون اور وارپ / وارپ اور سایفون / تور اور وارپ / وارپ
///    اور تور); ماسک/وایرگارد glyph boxes shrink 28 → 24 («آیکون ماسک و
///    وایرگارد رو کوچک‌تر کن تا به اندازه آیکون بقیه پروتکل‌ها بشن»).
///  * ENTRANCE/EXIT kept: the route fade + the internal block cascade
///    (staggered slide-up) ride the same route timeline; the exit retraces
///    the cascade on pop. Selecting a protocol still pulses and AUTO-POPS
///    back to the home page (owner v4.16 decree).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_state.dart';
import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
import '../../shared/circle_selector.dart';
import '../../shared/protocol_glyph.dart';
import '../../shared/theme_toggle_tile.dart';

/// Pushes the protocol-selection page. v4.25 — the route itself is the
/// STYLE'S OWN personality via [aethPageRoute] (SILK fade-rise / TIDE
/// zoom-dissolve / SPRING pop / BLINK fade / OFF instant cut); the
/// internal block cascade rides the same timeline (the sheet's recipe,
/// kept per the owner's «انیمیشن های فعلی رو حذف نکن»).
PageRouteBuilder<void> protocolPageRoute({
  required ConnectionStore store,
  required MotionStyle style,
}) {
  return aethPageRoute<void>(
    style: style,
    builder: (_) => ProtocolPage(store: store, style: style),
  );
}

class ProtocolPage extends StatefulWidget {
  const ProtocolPage({
    super.key,
    required this.store,
    required this.style,
  });

  final ConnectionStore store;
  final MotionStyle style;

  @override
  State<ProtocolPage> createState() => _ProtocolPageState();
}

class _ProtocolPageState extends State<ProtocolPage> {
  /// The protocol currently pulsing from a selection tap (auto-pop follows).
  ProtocolId? _pulseId;

  /// v4.21 — the single-knob plain-tile highlight: the committed protocol
  /// when it is a PLAIN tile, null when a family member is committed (the
  /// v4.20 "leg tile stays green under a family mode" double-highlight is
  /// exactly what the owner asked to remove).
  ProtocolId? get _plainHighlight {
    final p = widget.store.selectedProtocol;
    return p.isTor || p.isPsiphon ? null : p;
  }

  void _select(ProtocolId id) {
    if (!mounted) return;
    // v4.21 — SINGLE-KNOB selection, the v4.19 semantics restored (owner
    // device-test round 3: «حالت جدید که برای انتخاب پروتکل AETHER در حالت
    // اور وارپ ایجاد کردی از لحاظ تجربه کاربری جالب نیست لطفا به حالت قبل
    // برشگردون بعدا یک گزینه برای انتخاب پروتکل هسته AETHER در پروتکل های
    // اور وارپ اضافه میکنیم»): every tile and every family sub-tile commits
    // THE protocol — one green selection on the whole page. The WARP leg
    // under a family mode stays the fixed WireGuard default inside the
    // engine adapter until the promised dedicated option lands.
    final already = widget.store.selectedProtocol == id;
    setState(() => _pulseId = id);
    if (!already) widget.store.selectProtocol(id);
    // Owner v4.16: after choosing a protocol the user is returned to the
    // home page automatically. The 300 ms hold lets the green crossfade +
    // pulse land before the reverse slide — v1.0.2: style-scaled (OFF pops
    // immediately; its crossfade is instant too, so nothing is lost).
    Future.delayed(motionDuration(widget.style, 300), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return MotionScope(
      style: widget.style,
      child: Scaffold(
        backgroundColor: AethColors.bgScreen,
        // v1.0.2 — the page no longer rebuilds its WHOLE tree on every
        // route tick: each block's [motionCascade] subscribes to the route
        // animation itself, so the outer listener now only rebuilds on
        // REAL store changes (the audit's no-full-screen-rebuild rule).
        body: AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) {
            final s =
                MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
            return Stack(
              // v4.25 — the pattern-placement fix: expand keeps the root
              // at the FULL screen height — the loose default collapsed
              // it to the content height and the composition drifted (the
              // owner's decree).
              fit: StackFit.expand,
              children: [
                // v5.3 (the owner: «پترن های سمت راست و چپ فقط باید در صفحه
                // اصلی و صفحه تست سرعت نمایش داده بشن و در سایر صفحه ها
                // نباید نمایش داده شوند») — the protocol page carries NO
                // patterns (and no smoke) any more: the v4.21/v8a
                // every-page rules are retired here.
                SafeArea(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: AethGeometry.refHeight * s,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // ---- top bar: theme toggle · title · back
                          // (v4.34 — the exclamation tile became the
                          // night ⇄ light switch, owner round 10).
                          _enter(
                            0,
                            Positioned(
                              top: AethGeometry.topSafeExtraGap * s,
                              left: AethGeometry.pageHPadding * s,
                              right: AethGeometry.pageHPadding * s,
                              child: _PageTopBar(
                                store: widget.store,
                                onBack: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                          // ---- «حالت اتصال» + the تونل/پروکسی segments
                          _enter(
                            1,
                            Positioned(
                              top: AethGeometry.protoPageHeadingModeTop * s,
                              left: 0,
                              right: 0,
                              child: _SheetHeadingRow(
                                text: strings.sheetHeadingMode,
                                badge: AppAssets.iconPassword1,
                              ),
                            ),
                          ),
                          _enter(
                            1,
                            Positioned(
                              top: AethGeometry.protoSegmentTop * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _ModeSegments(
                                selected: widget.store.connectionMode,
                                onSelect: widget.store.setConnectionMode,
                              ),
                            ),
                          ),
                          // ---- «پروتکل» + the 3+3 tiles + family cards
                          _enter(
                            2,
                            Positioned(
                              top:
                                  AethGeometry.protoPageHeadingProtocolTop * s,
                              left: 0,
                              right: 0,
                              child: _SheetHeadingRow(
                                text: strings.protocol, // «پروتکل» verbatim
                                badge: AppAssets.iconSwap1,
                              ),
                            ),
                          ),
                          _enter(
                            3,
                            Positioned(
                              top: AethGeometry.protoTileRow1Top * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _TileRow(
                                ids: const [
                                  ProtocolId.auto,
                                  ProtocolId.masque,
                                  ProtocolId.wireguard,
                                ],
                                labels: [
                                  strings.protoAutoSheet,
                                  strings.protocolName(ProtocolId.masque),
                                  strings.protocolName(ProtocolId.wireguard),
                                ],
                                // v4.21 — the single-knob highlight: a
                                // family selection means NO plain tile is
                                // active (the v4.20 double-green is gone).
                                selected: _plainHighlight,
                                pulse: _pulseId,
                                style: widget.style,
                                onSelect: _select,
                              ),
                            ),
                            flavor: EntranceFlavor.action,
                          ),
                          _enter(
                            4,
                            Positioned(
                              top: AethGeometry.protoTileRow2Top * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _TileRow(
                                ids: const [
                                  ProtocolId.gool,
                                  ProtocolId.goolClassic,
                                  ProtocolId.mim,
                                ],
                                labels: [
                                  strings.protocolName(ProtocolId.gool),
                                  strings.protocolName(ProtocolId.goolClassic),
                                  strings.protocolName(ProtocolId.mim),
                                ],
                                // v4.21 — the single-knob highlight.
                                selected: _plainHighlight,
                                pulse: _pulseId,
                                style: widget.style,
                                onSelect: _select,
                              ),
                            ),
                            flavor: EntranceFlavor.action,
                          ),
                          _enter(
                            5,
                            Positioned(
                              top: AethGeometry.protoCardTopPsiphon * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _FamilyCard(
                                family: const [
                                  ProtocolId.psiphonOnly,
                                  ProtocolId.psiphonChain,
                                  ProtocolId.psiphonReverse,
                                ],
                                label:
                                    strings.protocolName(ProtocolId.psiphonChain),
                                logoAsset: AppAssets.protocolPsiphonLogo,
                                // v4.21 — the single-knob selection: the
                                // card highlights only when one of ITS
                                // members is the committed protocol.
                                selected: widget.store.selectedProtocol,
                                pulse: _pulseId,
                                style: widget.style,
                                onSelect: _select,
                              ),
                            ),
                            flavor: EntranceFlavor.action,
                          ),
                          _enter(
                            6,
                            Positioned(
                              top: AethGeometry.protoCardTopTor * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _FamilyCard(
                                family: const [
                                  ProtocolId.torOnly,
                                  ProtocolId.torChain,
                                  ProtocolId.torReverse,
                                ],
                                label:
                                    strings.protocolName(ProtocolId.torChain),
                                logoAsset: AppAssets.protocolTorLogo,
                                // v4.21 — the single-knob selection.
                                selected: widget.store.selectedProtocol,
                                pulse: _pulseId,
                                style: widget.style,
                                onSelect: _select,
                              ),
                            ),
                            flavor: EntranceFlavor.action,
                          ),
                          // ---- v2.1.0 (the owner's decree): the
                          // «سرعت اسکن» section is BACK on the protocol
                          // page, in the Firefox card's place — the
                          // pre-PHASE-2 geometry, restored verbatim.
                          _enter(
                            7,
                            Positioned(
                              top: AethGeometry.protoPageHeadingScanTop * s,
                              left: 0,
                              right: 0,
                              child: _SheetHeadingRow(
                                text: strings.sheetHeadingScanSpeed,
                                badge: AppAssets.iconScan1,
                              ),
                            ),
                          ),
                          _enter(
                            7,
                            Positioned(
                              top: AethGeometry.protoPillTop * s,
                              left: 0,
                              right: 0,
                              child: _ScanPills(
                                selected: widget.store.scanSpeed,
                                onSelect: widget.store.setScanSpeed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The stagger wrapper (kept from the sheet — owner: «انیمیشن های فعلی رو
  /// حذف نکن»): block [i] enters on its own slice of the route timeline.
  /// v1.0.2 — UNIFIED with the app's ONE cascade ([motionCascade]): the
  /// hand-rolled twin (the audit's «دو مسیر ناهمگون» finding — two code
  /// paths for one behaviour, already drifting) is gone; the flavour
  /// differentiates the block's MEANING (the protocol tiles reach for the
  /// finger with [EntranceFlavor.action], the chrome stays standard).
  /// The Positioned unwrap stays (ParentData rule: Positioned must remain
  /// a DIRECT Stack child).
  Widget _enter(
    int block,
    Widget child, {
    EntranceFlavor flavor = EntranceFlavor.standard,
  }) {
    final pd = child is Positioned ? child : null;
    final inner = pd?.child ?? child;
    final animated = motionCascade(
      context,
      widget.style,
      block,
      inner,
      flavor: flavor,
    );
    if (pd == null) return animated;
    return Positioned(
      left: pd.left,
      top: pd.top,
      right: pd.right,
      bottom: pd.bottom,
      width: pd.width,
      height: pd.height,
      child: animated,
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — the settings page's own chrome around the title, «Rectangle 9»
// 50×50 tiles. v4.19: the owner swapped the tile slots. The Row runs under
// the app's RTL directionality — the FIRST child renders on the visual
// RIGHT: back first (visual RIGHT), info second (visual LEFT).
// ---------------------------------------------------------------------------

class _PageTopBar extends StatelessWidget {
  const _PageTopBar({required this.store, required this.onBack});

  final ConnectionStore store;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final tile = AethGeometry.topTileSize * s;
    return SizedBox(
      height: tile,
      child: Row(
        children: [
          // FIRST child → visual RIGHT (RTL row): the back chevron tile
          // (owner v4.19: slots swapped with the info tile).
          _TileButton(
            key: const ValueKey('proto-page-back'),
            asset: AppAssets.iconRight2,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Back',
            onTap: onBack,
          ),
          const Spacer(),
          Text(
            strings.protocolPageTitle,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w700,
              fontSize: 17 * s,
              color: AethColors.textPrimary,
            ),
          ),
          const Spacer(),
          // Visual LEFT: the theme toggle (v4.34).
          ThemeToggleTile(
            store: store,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            tileKey: const ValueKey('proto-page-info'),
          ),
        ],
      ),
    );
  }
}

/// The owner «Rectangle 9» tile (50×50, #0F1510, r16, soft shadow) — the
/// exact same tile as the settings/home top bars.
class _TileButton extends StatelessWidget {
  const _TileButton({
    super.key,
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
            // v4.35 (owner round 11, item 1): NO shadow in light mode —
            // the color rides the palette (night rgba(0,0,0,0.25) 0 4 4 /
            // light transparent) and fades with the 420 ms mode tween.
            boxShadow: [
              BoxShadow(
                color: AethColors.tileShadow,
                offset: const Offset(0, 4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              asset,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(
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
// Section heading row: «TEXT … [badge]» — text 16 w700 white.
// v4.17 — the badge grows 20 → 26 and the text sits 12 (was 26) from it.
// ---------------------------------------------------------------------------

class _SheetHeadingRow extends StatelessWidget {
  const _SheetHeadingRow({required this.text, required this.badge});

  final String text;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    // LTR-locked geometry (the settings-page precedent): the badge hugs the
    // visual RIGHT edge, the Persian text right-aligned to its left.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          const Spacer(),
          Padding(
            // Text right edge = [protoHeadingTextRightInset] from the screen
            // right (66 = badge 26 + gap 12 + inset 28).
            padding: EdgeInsets.only(
              right: AethGeometry.protoHeadingBadgeGap * s,
            ),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.protoHeadingTextSize * s,
                color: AethColors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: AethGeometry.protoRightInset * s),
            child: SvgPicture.asset(
              badge,
              width: AethGeometry.protoBadgeSize * s,
              height: AethGeometry.protoBadgeSize * s,
              colorFilter: ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// «حالت اتصال» segments: h35 r14 gap21; RTL order تونل (right/first) then
// پروکسی. Selected = #1AD995 fill, unselected = #0F1511; WHITE text on both
// (measured: «پروکسی» ink is white on the green segment).
// ---------------------------------------------------------------------------

class _ModeSegments extends StatelessWidget {
  const _ModeSegments({
    required this.selected,
    required this.onSelect,
  });

  final ConnectionMode selected;
  final void Function(ConnectionMode) onSelect;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final strings = AppStrings.of(context);
    // v1.0.2 — the segment's timing follows the SELECTED style through
    // [MotionScope] (the audit's zero-hardcode rule; was a fixed 260 ms).
    final ms = MotionScope.of(context);
    final ctrl = Duration(milliseconds: ms.recipe.controlMs);
    final ctrlCurve = ms.recipe.controlCurve;
    final h = AethGeometry.protoSegmentH * s;
    final r = AethGeometry.protoSegmentRadius * s;

    Widget segment(ConnectionMode mode, String label) {
      final isSel = selected == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(mode),
          child: AnimatedContainer(
            duration: ctrl,
            curve: ctrlCurve,
            height: h,
            decoration: BoxDecoration(
              color: isSel ? AethColors.accentConnected : AethColors.cardDark,
              borderRadius: BorderRadius.circular(r),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.protoSegmentTextSize * s,
                color: AethColors.textPrimary, // white on BOTH (measured)
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

// ---------------------------------------------------------------------------
// Protocol tiles: r21 (v4.17 — the settings cards' corners); ⓘ 15×15 visual
// inside a 32×32 invisible hit box at the same corner; icon center at
// top+41; label 12 w500 at top+66. Unselected: #0F1511 + native icon colors
// (white / gold) + white label. Selected: #1AD995 + all-white glyph.
// ---------------------------------------------------------------------------

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.ids,
    required this.labels,
    required this.selected,
    required this.pulse,
    required this.style,
    required this.onSelect,
  });

  final List<ProtocolId> ids;
  final List<String> labels;

  /// v4.21 — nullable: the single-knob highlight shows NO plain tile when
  /// a family member is committed.
  final ProtocolId? selected;
  final ProtocolId? pulse;

  /// v8a — the ambient style (the Circle-Selector impulse's tempo,
  /// owner round 18: «Circle Selector رو در صفحه انتخاب پروتکل هم
  /// استفاده کن»).
  final MotionStyle style;
  final void Function(ProtocolId) onSelect;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl, // first child at the visual RIGHT
      // v8a — the CIRCLE SELECTOR row: the selected tile springs up and
      // PUSHES its row siblings aside for the impulse's duration, then
      // everything settles back to the committed tile geometry (the old
      // 0.97→1.0 tap pulse is superseded by this — same fire seams: the
      // tap AND the committed-selection edge).
      child: CircleSelectRow(
        style: style,
        rtl: true,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        selectedIndex: selected == null ? null : ids.indexOf(selected!),
        pulseIndex: pulse == null ? null : ids.indexOf(pulse!),
        children: [
          for (var i = 0; i < ids.length; i++)
            _ProtoTile(
              id: ids[i],
              label: labels[i],
              isSelected: selected == ids[i],
              onSelect: onSelect,
            ),
        ],
      ),
    );
  }
}

class _ProtoTile extends StatelessWidget {
  const _ProtoTile({
    required this.id,
    required this.label,
    required this.isSelected,
    required this.onSelect,
  });

  final ProtocolId id;
  final String label;
  final bool isSelected;
  final void Function(ProtocolId) onSelect;

  // v8a — the pulse controller is GONE: the parent CircleSelectRow owns
  // the impulse (grow + sibling push) for the whole row.

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final ms = MotionScope.of(context);
    final w = AethGeometry.protoTileW * s;
    final iconBox = _tileIconBox(id);

    return SizedBox(
      width: w,
      height: AethGeometry.protoTileRow1H * s,
      child: GestureDetector(
        key: ValueKey('proto-tile-${id.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(id),
        child: AnimatedContainer(
            duration: Duration(milliseconds: ms.recipe.controlMs),
            curve: ms.recipe.controlCurve,
            decoration: BoxDecoration(
              color: isSelected
                  ? AethColors.accentConnected
                  : AethColors.cardDark,
              borderRadius:
                  BorderRadius.circular(AethGeometry.protoTileRadius * s),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // v4.33 (owner round 9): the ⓘ info badge is REMOVED by
                // decree («تمام آیکون‌های علامت تعجب که برای توضیح
                // پروتکل‌ها هست رو حذف بکن») — the tile is the icon + the
                // label only.
                // Icon — center at top+41 (measured cy 342 on row 1).
                Positioned(
                  left: 0,
                  right: 0,
                  top: (AethGeometry.protoTileIconCenter - iconBox / 2) * s,
                  child: Center(
                    child: ProtocolGlyph(
                      id: id,
                      size: iconBox * s,
                      white: isSelected,
                    ),
                  ),
                ),
                // Label — 12 w5, center at top+66 (measured cy 368).
                Positioned(
                  left: 0,
                  right: 0,
                  top: (AethGeometry.protoTileLabelCenter - 6) * s,
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w500,
                        fontSize: AethGeometry.protoTileLabelSize * s,
                        color: AethColors.textPrimary,
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


/// Per-protocol tile icon boxes, calibrated so the final GLYPH matches the
/// frame (each SVG carries its own ink ratio — the settings-page recipe).
/// v4.17 — owner: ماسک و وایرگارد «هم بزرگه هم اندازه سایر آیکون ها باید
/// باشن» — 38/37 → 28. v4.33 (owner round 9): «آیکون ماسک و وایرگارد رو
/// کوچک‌تر کن تا به اندازه آیکون بقیه پروتکل‌ها بشن» — the two WIDE
/// landscape SVGs (39×22 / 38×22) span the full 28-box WIDTH, visually
/// outweighing the portrait glyphs (gool prints only ≈24 wide in the same
/// box) — their box drops to 24 so their ink width matches the others.
double _tileIconBox(ProtocolId id) => switch (id) {
      ProtocolId.auto => 26,
      ProtocolId.masque => 24, // v4.33 — 28 → 24 (the wide-glyph shrink)
      ProtocolId.wireguard => 24, // v4.33 — 28 → 24
      ProtocolId.gool => 28,
      ProtocolId.goolClassic => 28,
      ProtocolId.mim => 32,
      _ => 30, // families never render on the tile grid
    };

// v4.35 — the tile glyphs render through the shared [ProtocolGlyph]
// (lib/features/shared/protocol_glyph.dart): theme ink + the combined
// modes' rebuilt drop shadow (owner round 11, items 4 + 5).

// ---------------------------------------------------------------------------
// Family cards (سایفون/تور): v4.17 breathing — h116 r21 #0F1511, subtiles
// 66×66 r14 #1A261C vertically centred (inset 25), gaps 20. Visual LEFT→
// RIGHT (the frame's own reading): [main logo+label] gap [plain=only] gap
// [Aether+∨=chain] gap [Aether+∧=reverse].
// ---------------------------------------------------------------------------

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({
    required this.family,
    required this.label,
    required this.logoAsset,
    required this.selected,
    required this.pulse,
    required this.style,
    required this.onSelect,
  });

  /// Visual order [only, chain, reverse] — matches the frame's subtiles.
  final List<ProtocolId> family;
  final String label;
  final String logoAsset;

  /// v4.20 — the CHAIN overlay selection (null = no overlay active).
  final ProtocolId? selected;
  final ProtocolId? pulse;

  /// v8a — the ambient style (the subtile row's Circle-Selector
  /// impulse, owner round 18).
  final MotionStyle style;
  final void Function(ProtocolId) onSelect;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final bool isPsiphon = family.first.isPsiphon;

    return SizedBox(
      key: ValueKey('proto-card-${family.first.isPsiphon ? 'psiphon' : 'tor'}'),
      height: AethGeometry.protoCardH * s,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AethColors.cardDark,
          borderRadius:
              BorderRadius.circular(AethGeometry.protoCardRadius * s),
        ),
        child: Directionality(
          // LTR by design: the main block sits at the visual LEFT, the
          // three subtiles to its right (frame-measured zone).
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              // ---- main block (logo center top+43, label 12 at top+80)
              SizedBox(
                width: AethGeometry.protoMainBlockW * s,
                child: Stack(
                  children: [
                    // v4.33 — the ⓘ badge is gone (owner decree); the main
                    // block is the logo + the label only.
                    Positioned(
                      left: 0,
                      right: 0,
                      // v4.41 (owner round 17, item 1): the main logo is 35
                      // tall now — re-center the box on the frame's cy 43.
                      top: (AethGeometry.protoMainLogoCenterY - 35 / 2) * s,
                      child: Center(
                        // v4.35 (owner item 4): the family main logo rides
                        // the theme ink (was hardcoded Colors.white —
                        // invisible on the light card).
                        child: ProtocolGlyph(
                          id: isPsiphon
                              ? ProtocolId.psiphonOnly
                              : ProtocolId.torOnly,
                          // v4.41: «حداکثر ارتفاع 35 کافیه» — the v4.40
                          // 56/42 boxes were too big; 35 for both families.
                          size: 35 * s,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (AethGeometry.protoMainLabelCenterY - 6) * s,
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'IRANYekanX',
                            fontWeight: FontWeight.w500,
                            fontSize: AethGeometry.protoTileLabelSize * s,
                            color: AethColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // NO separator: the main zone + 3 subtiles + gaps exactly
              // fill the 346 card (95 + 3×66 + 2×20 + 13 inset).
              // v8a — the CIRCLE SELECTOR row for the family's own
              // subtiles (owner round 18): the selected subtile springs
              // up and pushes its subtile siblings aside, then settles.
              CircleSelectRow(
                style: style,
                rtl: false, // LTR by design (see the Directionality above)
                selectedIndex:
                    selected == null ? null : family.indexOf(selected!),
                pulseIndex: pulse == null ? null : family.indexOf(pulse!),
                children: [
                  for (final id in family)
                    Padding(
                      padding: EdgeInsets.only(
                        right: id == family.last
                            ? 0
                            : AethGeometry.protoSubtileGap * s,
                      ),
                      child: _SubTile(
                        id: id,
                        isPsiphon: isPsiphon,
                        isSelected: selected == id,
                        onSelect: onSelect,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTile extends StatelessWidget {
  const _SubTile({
    required this.id,
    required this.isPsiphon,
    required this.isSelected,
    required this.onSelect,
  });

  final ProtocolId id;
  final bool isPsiphon;
  final bool isSelected;
  final void Function(ProtocolId) onSelect;

  // v8a — the pulse controller is GONE: the parent CircleSelectRow
  // owns the impulse (grow + sibling push) for the whole subtile row.

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final ms = MotionScope.of(context);
    final chain = id.isPsiphon
        ? id == ProtocolId.psiphonChain
        : id == ProtocolId.torChain;
    final reverse = id.isPsiphon
        ? id == ProtocolId.psiphonReverse
        : id == ProtocolId.torReverse;

    return GestureDetector(
      key: ValueKey('proto-subtile-${id.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(id),
      child: AnimatedContainer(
        duration: Duration(milliseconds: ms.recipe.controlMs),
        curve: ms.recipe.controlCurve,
        width: AethGeometry.protoSubtile * s,
        height: AethGeometry.protoSubtile * s,
        decoration: BoxDecoration(
          color: isSelected
              ? AethColors.accentConnected
              : AethColors.sheetSubtile,
          borderRadius:
              BorderRadius.circular(AethGeometry.protoSubtileRadius * s),
        ),
        child: Center(
          // v4.33 (owner round 9): the combined modes carry their OWN
          // owner-drawn logos — now through the shared [ProtocolGlyph]
          // (v4.35: theme ink + the rebuilt drop shadow, owner items 4/5);
          // the plain ONLY tiles keep the family's real logo.
          child: (chain || reverse)
              ? ProtocolGlyph(
                  id: id,
                  size: AethGeometry.protoCombinedGlyphH * s,
                  // v4.41 (owner round 17, item 11): «آیکون وارپ اور تور
                  // و وارپ اور سایفون باید وقتی در حالت انتخاب هستن
                  // سفید رنگ باشن» — the v4.40 verbatim-artwork rewrite
                  // dropped the selected-tile all-ink rule for the
                  // combined modes; their green artworks (#1AD995) are
                  // the tile's own fill and vanished when selected.
                  white: isSelected,
                )
              : ProtocolGlyph(
                  id: id,
                  size: (isPsiphon
                          ? AethGeometry.protoPsiphonGlyphBox
                          : AethGeometry.protoTorGlyphBox)
                      * s,
                  white: isSelected,
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// «سرعت اسکن» pills: 5 increasing widths 28/47/64/77/87, h36 r8 gap8,
// CENTERED (the row spans x33..367). The widest (rightmost) is selected
// in the frame.
// ---------------------------------------------------------------------------

class _ScanPills extends StatelessWidget {
  const _ScanPills({required this.selected, required this.onSelect});

  final int selected;
  final void Function(int) onSelect;

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
    final ms = MotionScope.of(context);
    final h = AethGeometry.protoPillH * s;
    final r = AethGeometry.protoPillRadius * s;

    return Center(
      child: Directionality(
        // RTL with children 5→1: the FIRST child (the widest, level 5)
        // lands at the visual RIGHT — the frame's reading (87 selected at
        // x281..367, then 77/64/47/28 toward the left).
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
                  key: ValueKey('proto-pill-$level'),
                  onTap: () => onSelect(level),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: ms.recipe.controlMs),
                    curve: ms.recipe.controlCurve,
                    width: _w[level - 1] * s,
                    height: h,
                    decoration: BoxDecoration(
                      color: selected == level
                          ? AethColors.accentConnected
                          : AethColors.cardDark,
                      borderRadius: BorderRadius.circular(r),
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
