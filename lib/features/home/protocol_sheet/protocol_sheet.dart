/// v4.16 — THE PROTOCOL SELECTION SHEET, pixel-faithful to the design frame
/// «صفحه شناور انتخاب پروتکل صفحه اصلی.jpg» (402×874) + its companion ⓘ
/// popup «صفحه شناور توضیحات پروتکل ها.jpg».
///
/// Every geometry value is MEASURED on that frame and lives in
/// [AethGeometry] as `proto*` tokens (measurement scripts:
/// scripts/measure_proto_*.py — pixel clusters, corner radii from
/// fill-width profiles, colors sampled at ink centers):
///
///   * Layer cake: the home page stays mounted behind the route; a scrim
///     (#141C16 @ 92%) starts at y≈101 — the home TOP BAR above it (info
///     tile, AETHONE wordmark, settings tile) stays fully visible, exactly
///     like the frame (diff vs the plain home frame: first dimmed row
///     y≈101). The sheet content sits directly on the scrim — the frame has
///     NO distinct panel edge, just the grab handle at y125.
///   * «حالت اتصال» (Password 1 badge) + the تونل/پروکسی segments — the
///     frame ships پروکسی selected (green #1AD995, WHITE text on both
///     states); binds to [ConnectionStore.connectionMode].
///   * «پروتکل» (Scan 1 badge) + 3+3 tiles (RTL: اتوماتیک|ماسک|وایرگارد
///     then گول|گول کلاسیک|میم) + two family cards (سایفون/تور) whose three
///     subtiles encode the variants in the frame's own language: plain
///     glyph = ONLY, Aether-logo + ∨ + glyph = CHAIN, Aether-logo + ∧ +
///     glyph = REVERSE (the app logo 3.svg IS the Aether mark here —
///     pixel-matched on the frame).
///   * «سرعت اسکن» (Password 1 badge) + 5 pills of increasing width
///     (28/47/64/77/87), the widest (rightmost) selected in the frame;
///     binds to [ConnectionStore.scanSpeed] 1..5.
///
/// Behaviour (owner v4.16): selecting a protocol (tile or subtile) commits
/// it to the store, plays a short selection pulse, then AUTO-POPS back to
/// the home page. The mode segments and the scan pills update the store
/// without closing. The ⓘ badges open the descriptions popup (the family
/// gets its 3 variant descriptions verbatim from the phase-1 report §11;
/// singles get one block). Dismiss: scrim tap, handle tap/drag-down, or
/// system back (the popup consumes back first).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_state.dart';
import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';

/// Pushes the sheet over the home. `opaque: false` keeps the home (and its
/// live top bar) painting behind; the fade + internal cascade both ride the
/// route animation so entry, pop and drag-dismiss share one timeline.
PageRouteBuilder<void> protocolSheetRoute({
  required ConnectionStore store,
  required MotionStyle style,
}) {
  return PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: motionDuration(style, 380),
    reverseTransitionDuration: motionDuration(style, 320),
    pageBuilder: (_, _, _) =>
        ProtocolSheetPage(store: store, style: style),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class ProtocolSheetPage extends StatefulWidget {
  const ProtocolSheetPage({
    super.key,
    required this.store,
    required this.style,
  });

  final ConnectionStore store;
  final MotionStyle style;

  @override
  State<ProtocolSheetPage> createState() => _ProtocolSheetPageState();
}

class _ProtocolSheetPageState extends State<ProtocolSheetPage> {
  /// The protocol whose ⓘ descriptions popup is open (a family id for the
  /// cards, the protocol itself for a tile).
  ProtocolId? _descFor;

  /// The protocol currently pulsing from a selection tap (auto-pop follows).
  ProtocolId? _pulseId;

  void _select(ProtocolId id) {
    if (!mounted) return;
    final already = widget.store.selectedProtocol == id;
    setState(() => _pulseId = id);
    if (!already) widget.store.selectProtocol(id);
    // Owner v4.16: after choosing a protocol the user is returned to the
    // home page automatically. The 300 ms hold lets the green crossfade +
    // pulse land before the reverse slide.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _openDesc(ProtocolId id) => setState(() => _descFor = id);

  void _closeDesc() => setState(() => _descFor = null);

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final strings = AppStrings.of(context);
    final routeAnim = ModalRoute.of(context)!.animation!;

    return PopScope(
      // The popup consumes BACK first; otherwise the route pops normally.
      canPop: _descFor == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _descFor != null) _closeDesc();
      },
      child: AnimatedBuilder(
        animation: routeAnim,
        builder: (context, _) {
          final t = routeAnim.value;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ---- L1: the scrim (below the home top bar) + its tap target
              Positioned(
                top: AethGeometry.protoScrimTop * s,
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      _descFor != null ? _closeDesc() : Navigator.of(context).pop(),
                  child: IgnorePointer(
                    // The desc layer owns taps while open.
                    ignoring: _descFor != null,
                    child: Opacity(
                      // The frame's dimmed zone: the home content ghosts
                      // through at ~8% (measured ink falloff on the frame).
                      opacity: const Interval(0, 0.5).transform(t).clamp(0, 1),
                      child: const ColoredBox(
                        color: Color(0xEA141C16), // #141C16 @ 92%
                      ),
                    ),
                  ),
                ),
              ),
              // ---- L2: the sheet content, staggered on the same timeline
              _enter(
                t,
                0,
                Positioned(
                  top: (AethGeometry.protoHandleTop - 15) * s,
                  left: 0,
                  right: 0,
                  height: 36 * s,
                  child: GestureDetector(
                    key: const ValueKey('proto-handle'),
                    behavior: HitTestBehavior.translucent,
                    onTap: () => Navigator.of(context).pop(),
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) > 180) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Center(
                      child: Container(
                        key: const ValueKey('proto-handle-bar'),
                        width: AethGeometry.protoHandleW * s,
                        height: AethGeometry.protoHandleH * s,
                        decoration: BoxDecoration(
                          color: AethColors.sheetHandle,
                          borderRadius: BorderRadius.circular(3 * s),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _enter(
                t,
                1,
                Positioned(
                  top: 164 * s,
                  left: 0,
                  right: 0,
                  child: _SheetHeadingRow(
                    text: strings.sheetHeadingMode,
                    badge: AppAssets.iconPassword1,
                  ),
                ),
              ),
              _enter(
                t,
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
              _enter(
                t,
                2,
                Positioned(
                  top: 262 * s,
                  left: 0,
                  right: 0,
                  child: _SheetHeadingRow(
                    text: strings.protocol, // «پروتکل» — verbatim frame text
                    badge: AppAssets.iconScan1,
                  ),
                ),
              ),
              _enter(
                t,
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
                    selected: widget.store.selectedProtocol,
                    pulse: _pulseId,
                    onSelect: _select,
                    onInfo: _openDesc,
                  ),
                ),
              ),
              _enter(
                t,
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
                    selected: widget.store.selectedProtocol,
                    pulse: _pulseId,
                    onSelect: _select,
                    onInfo: _openDesc,
                  ),
                ),
              ),
              _enter(
                t,
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
                    label: strings.protocolName(ProtocolId.psiphonChain),
                    logoAsset: AppAssets.protocolPsiphonLogo,
                    selected: widget.store.selectedProtocol,
                    pulse: _pulseId,
                    onSelect: _select,
                    onInfo: _openDesc,
                    infoId: ProtocolId.psiphonChain,
                  ),
                ),
              ),
              _enter(
                t,
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
                    label: strings.protocolName(ProtocolId.torChain),
                    logoAsset: AppAssets.protocolTorLogo,
                    selected: widget.store.selectedProtocol,
                    pulse: _pulseId,
                    onSelect: _select,
                    onInfo: _openDesc,
                    infoId: ProtocolId.torChain,
                  ),
                ),
              ),
              _enter(
                t,
                7,
                Positioned(
                  top: 765 * s,
                  left: 0,
                  right: 0,
                  child: _SheetHeadingRow(
                    text: strings.sheetHeadingScanSpeed,
                    badge: AppAssets.iconPassword1,
                  ),
                ),
              ),
              _enter(
                t,
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
              // ---- L3: the ⓘ descriptions popup
              if (_descFor != null)
                _DescLayer(
                  forId: _descFor!,
                  onClose: _closeDesc,
                ),
            ],
          );
        },
      ),
    );
  }

  /// The stagger wrapper: block [i] slides up 22px + fades on its own slice
  /// of the route timeline (starts i*0.075, 0.55 wide, easeOutCubic). On
  /// reverse the same slices retrace — the sheet folds away gently.
  Widget _enter(double t, int block, Widget child) {
    final start = (block * 0.075).clamp(0.0, 0.45);
    final bt =
        Curves.easeOutCubic.transform(Interval(start, start + 0.55).transform(t));
    if (bt >= 0.999) return child;

    // The animation must live INSIDE the Positioned (ParentData rule:
    // Positioned has to stay a DIRECT Stack child), so a Positioned child
    // is unwrapped, animated, and re-wrapped with identical bounds.
    final pd = child is Positioned ? child : null;
    final inner = pd?.child ?? child;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final animated = Opacity(
      opacity: bt,
      child: Transform.translate(
        offset: Offset(0, (1 - bt) * 22 * s),
        child: inner,
      ),
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
// Section heading row: «TEXT … [badge]» — text 16 w700 white, its right
// edge 74 from the screen right (measured x≈328 on all three headings),
// 26 gap, then the 20×20 badge at the content inset (right edge x374).
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
            // Text right edge = 74 from the screen right (measured) — the
            // badge (20) + gap (26) + inset (28) sit to its right.
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
              colorFilter: const ColorFilter.mode(
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
    final h = AethGeometry.protoSegmentH * s;
    final r = AethGeometry.protoSegmentRadius * s;

    Widget segment(ConnectionMode mode, String label) {
      final isSel = selected == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
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
// Protocol tiles: r16; ⓘ 13×13 at (11,9); icon center at top+41; label
// 12 w500 at top+66. Unselected: #0F1511 + native icon colors (white /
// gold) + white label. Selected: #1AD995 + all-white glyph (measured on
// the frame's وایرگارد tile).
// ---------------------------------------------------------------------------

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.ids,
    required this.labels,
    required this.selected,
    required this.pulse,
    required this.onSelect,
    required this.onInfo,
  });

  final List<ProtocolId> ids;
  final List<String> labels;
  final ProtocolId selected;
  final ProtocolId? pulse;
  final void Function(ProtocolId) onSelect;
  final void Function(ProtocolId) onInfo;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl, // first child at the visual RIGHT
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < ids.length; i++)
            _ProtoTile(
              id: ids[i],
              label: labels[i],
              isSelected: selected == ids[i],
              pulsing: pulse == ids[i],
              onSelect: onSelect,
              onInfo: onInfo,
            ),
        ],
      ),
    );
  }
}

class _ProtoTile extends StatefulWidget {
  const _ProtoTile({
    required this.id,
    required this.label,
    required this.isSelected,
    required this.pulsing,
    required this.onSelect,
    required this.onInfo,
  });

  final ProtocolId id;
  final String label;
  final bool isSelected;
  final bool pulsing;
  final void Function(ProtocolId) onSelect;
  final void Function(ProtocolId) onInfo;

  @override
  State<_ProtoTile> createState() => _ProtoTileState();
}

class _ProtoTileState extends State<_ProtoTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    lowerBound: 0.97,
  );

  @override
  void didUpdateWidget(covariant _ProtoTile old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !old.pulsing) {
      _pulse.forward(); // 0.97 → 1.0 spring-ish settle
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final w = AethGeometry.protoTileW * s;
    final iconBox = _tileIconBox(widget.id);

    return SizedBox(
      width: w,
      height: AethGeometry.protoTileRow1H * s,
      child: ScaleTransition(
        scale: _pulse,
        child: GestureDetector(
          key: ValueKey('proto-tile-${widget.id.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(widget.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AethColors.accentConnected
                  : AethColors.cardDark,
              borderRadius: BorderRadius.circular(AethGeometry.protoTileRadius * s),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ⓘ info badge — 13×13 at (11,9), white circle + i
                // (Information Circle.svg, the set's own glyph).
                Positioned(
                  left: AethGeometry.protoInfoBadgeInset * s,
                  top: AethGeometry.protoInfoBadgeInset * s,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onInfo(widget.id),
                    child: SvgPicture.asset(
                      AppAssets.iconInformationCircle,
                      width: AethGeometry.protoInfoBadgeSize * s,
                      height: AethGeometry.protoInfoBadgeSize * s,
                      colorFilter: const ColorFilter.mode(
                        AethColors.textPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                // Icon — center at top+41 (measured cy 342 on row 1).
                Positioned(
                  left: 0,
                  right: 0,
                  top: (AethGeometry.protoTileIconCenter - iconBox / 2) * s,
                  child: Center(
                    child: _ProtocolGlyph(
                      id: widget.id,
                      box: iconBox,
                      white: widget.isSelected,
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
                      widget.label,
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
      ),
    );
  }
}

/// Per-protocol tile icon boxes, calibrated so the final GLYPH matches the
/// frame (each SVG carries its own ink ratio — the settings-page recipe):
/// ماسک 38×21, وایرگارد 36×21, اتوماتیک 21×23 (Shield Tick, gold),
/// گول/گول کلاسیک ~21×28, میم ~31×26.
double _tileIconBox(ProtocolId id) => switch (id) {
      ProtocolId.auto => 26,
      ProtocolId.masque => 38,
      ProtocolId.wireguard => 37,
      ProtocolId.gool => 28,
      ProtocolId.goolClassic => 28,
      ProtocolId.mim => 32,
      _ => 30, // families never render on the tile grid
    };

// ---------------------------------------------------------------------------
// One protocol glyph at a calibrated box. SVGs render in their NATIVE
// colors (white / #997A35 gold — exactly how the frame colours them);
// PNGs (psiphon/tor) are tinted white. `white` forces the all-white
// treatment the frame uses on the SELECTED (green) surface.
// ---------------------------------------------------------------------------

class _ProtocolGlyph extends StatelessWidget {
  const _ProtocolGlyph({
    required this.id,
    required this.box,
    this.white = false,
  });

  final ProtocolId id;
  final double box;
  final bool white;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final asset = AppAssets.protocolIcon(id);
    final isRaster = AppAssets.isRasterAsset(asset);
    final w = box * s;

    if (id == ProtocolId.auto) {
      // AUTO has no dedicated artwork (report §6.9): Shield Tick, gold —
      // the frame's gold shield.
      return SvgPicture.asset(
        AppAssets.iconShieldTick,
        width: w,
        height: w,
        colorFilter: ColorFilter.mode(
          white ? AethColors.textPrimary : AethColors.goldAccent,
          BlendMode.srcIn,
        ),
      );
    }
    if (isRaster) {
      return Image.asset(
        asset,
        width: w,
        height: w,
        fit: BoxFit.contain,
        color: white ? AethColors.textPrimary : Colors.white,
        colorBlendMode: BlendMode.srcIn,
      );
    }
    if (white) {
      return SvgPicture.asset(
        asset,
        width: w,
        height: w,
        colorFilter: const ColorFilter.mode(
          AethColors.textPrimary,
          BlendMode.srcIn,
        ),
      );
    }
    return SvgPicture.asset(asset, width: w, height: w);
  }
}

// ---------------------------------------------------------------------------
// Family cards (سایفون/تور): h100 r16 #0F1511. Visual LEFT→RIGHT (the
// frame's own reading): [main logo+label] gap16 [plain=only] gap16
// [Aether+∨=chain] gap16 [Aether+∧=reverse]. Subtiles 66×66 r14 #1A261C.
// ---------------------------------------------------------------------------

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({
    required this.family,
    required this.label,
    required this.logoAsset,
    required this.selected,
    required this.pulse,
    required this.onSelect,
    required this.onInfo,
    required this.infoId,
  });

  /// Visual order [only, chain, reverse] — matches the frame's subtiles.
  final List<ProtocolId> family;
  final String label;
  final String logoAsset;
  final ProtocolId selected;
  final ProtocolId? pulse;
  final void Function(ProtocolId) onSelect;
  final void Function(ProtocolId) onInfo;

  /// The id the ⓘ opens descriptions for (a family representative).
  final ProtocolId infoId;

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
          borderRadius: BorderRadius.circular(AethGeometry.protoCardRadius * s),
        ),
        child: Directionality(
          // LTR by design: the main block sits at the visual LEFT, the
          // three subtiles to its right (frame-measured x28..131 zone).
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              // ---- main block (logo center top+37, label 12 at top+69)
              SizedBox(
                width: AethGeometry.protoTileW * s,
                child: Stack(
                  children: [
                    Positioned(
                      left: AethGeometry.protoInfoBadgeInset * s,
                      top: AethGeometry.protoInfoBadgeInset * s,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onInfo(infoId),
                        child: SvgPicture.asset(
                          AppAssets.iconInformationCircle,
                          width: AethGeometry.protoInfoBadgeSize * s,
                          height: AethGeometry.protoInfoBadgeSize * s,
                          colorFilter: const ColorFilter.mode(
                            AethColors.textPrimary,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (AethGeometry.protoMainLogoCenterY - 28) * s,
                      child: Center(
                        child: Image.asset(
                          logoAsset,
                          height: (isPsiphon ? 56 : 42) * s,
                          fit: BoxFit.contain,
                          color: Colors.white,
                          colorBlendMode: BlendMode.srcIn,
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
              // NO separator here: the frame's main zone is a full 103-wide
              // slot (x28..131) and sub1 starts exactly at its right edge;
              // the remaining 13px after sub3 is the card's right inset
              // (28+103+82+82+66 = 361, +13 = 374 = the content edge).
              for (final id in family)
                Padding(
                  padding: EdgeInsets.only(
                    right: id == family.last ? 0 : AethGeometry.protoSubtileGap * s,
                  ),
                  child: _SubTile(
                    id: id,
                    isPsiphon: isPsiphon,
                    isSelected: selected == id,
                    pulsing: pulse == id,
                    onSelect: onSelect,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTile extends StatefulWidget {
  const _SubTile({
    required this.id,
    required this.isPsiphon,
    required this.isSelected,
    required this.pulsing,
    required this.onSelect,
  });

  final ProtocolId id;
  final bool isPsiphon;
  final bool isSelected;
  final bool pulsing;
  final void Function(ProtocolId) onSelect;

  @override
  State<_SubTile> createState() => _SubTileState();
}

class _SubTileState extends State<_SubTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    lowerBound: 0.95,
  );

  @override
  void didUpdateWidget(covariant _SubTile old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !old.pulsing) _pulse.forward();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final chain = widget.id.isPsiphon
        ? widget.id == ProtocolId.psiphonChain
        : widget.id == ProtocolId.torChain;
    final reverse = widget.id.isPsiphon
        ? widget.id == ProtocolId.psiphonReverse
        : widget.id == ProtocolId.torReverse;

    return ScaleTransition(
      scale: _pulse,
      child: GestureDetector(
        key: ValueKey('proto-subtile-${widget.id.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect(widget.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          width: AethGeometry.protoSubtile * s,
          height: AethGeometry.protoSubtile * s,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AethColors.accentConnected
                : AethColors.sheetSubtile,
            borderRadius: BorderRadius.circular(AethGeometry.protoSubtileRadius * s),
          ),
          child: Center(
            child: _StackGlyph(
              protocol: widget.id,
              chain: chain,
              reverse: reverse,
              white: widget.isSelected,
              scale: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The stack glyph language (frame-measured): plain = the protocol glyph
// alone; chain/reverse = [Aether logo ~18×19] +7 [chevron 14×6] +6
// [protocol glyph ~16×20]. The Aether mark is the app logo 3.svg (white)
// — pixel-matched to the frame's stack-top glyph. `scale` grows it for the
// descriptions popup (×1.45).
// ---------------------------------------------------------------------------

class _StackGlyph extends StatelessWidget {
  const _StackGlyph({
    required this.protocol,
    required this.chain,
    required this.reverse,
    this.white = false,
    this.scale = 1.0,
  });

  final ProtocolId protocol;
  final bool chain;
  final bool reverse;

  /// All-white treatment (selected surfaces — measured on the frame).
  final bool white;

  final double scale;

  // Canvas-honest layout. The family PNGs carry big transparent margins
  // (psiphon ink = 47%×64% of its 128-canvas; tor = 57%×86% of 42-box), so
  // the glyph BOX is larger than its ink. The LAYOUT gaps are compensated
  // so the VISUAL ink-to-ink gaps land on the frame's ~7 / ~6 and the
  // whole stack totals ≈59 ink-height inside the 66 box (measured):
  //   psiphon: box 31.2 (ink 14.6×20), gaps 6.7 / 0.4
  //   tor:     box 26.3 (ink 15×22.5), gaps 6.7 / 4.1
  // (aether canvas 20 ≈ its ink — only ~0.2 pad.)
  static const double _psiphonBox = 31.2;
  static const double _psiphonG1 = 6.7;
  static const double _psiphonG2 = 0.4;
  static const double _torBox = 26.3;
  static const double _torG1 = 6.7;
  static const double _torG2 = 4.1;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final isPsiphon = protocol.isPsiphon;
    final box = (isPsiphon ? _psiphonBox : _torBox) * scale;
    final glyph = _ProtocolGlyph(id: protocol, box: box, white: white);
    if (!chain && !reverse) return glyph; // plain = ONLY

    final k = s * scale;
    final aether = SvgPicture.asset(
      AppAssets.appLogoNeutralWhite,
      width: 20 * k,
      height: 20 * k,
    );
    final chevron = _StackChevron(
      up: reverse,
      width: 14 * k,
      height: 6 * k,
      color: white ? AethColors.textPrimary : Colors.white,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        aether,
        SizedBox(height: (isPsiphon ? _psiphonG1 : _torG1) * k),
        chevron,
        SizedBox(height: (isPsiphon ? _psiphonG2 : _torG2) * k),
        glyph,
      ],
    );
  }
}

/// The stack chevron — 14×6, 2px round-cap strokes (drawn once here in the
/// set's linear style; custom drawing precedent D7, documented).
class _StackChevron extends StatelessWidget {
  const _StackChevron({
    required this.up,
    required this.width,
    required this.height,
    required this.color,
  });

  final bool up;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _StackChevronPainter(up, color),
    );
  }
}

class _StackChevronPainter extends CustomPainter {
  _StackChevronPainter(this.up, this.color);

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.06, up ? h * 0.85 : h * 0.15)
      ..lineTo(w * 0.5, up ? h * 0.28 : h * 0.72)
      ..lineTo(w * 0.94, up ? h * 0.85 : h * 0.15);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StackChevronPainter old) =>
      old.up != up || old.color != color;
}

// ---------------------------------------------------------------------------
// «سرعت اسکن» pills: 5 increasing widths 28/47/64/77/87, h36 r8 gap8,
// CENTERED (the row spans x33..367 — center 200 like the handle, not the
// content inset). The widest (rightmost) is selected in the frame.
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
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
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

// ---------------------------------------------------------------------------
// The ⓘ descriptions popup: × Ø22 at y206 (13 above the card top 242),
// card r24 #0C120F, blocks 14px/lh18 white + dividers #1A261C, icon column
// on the right (plain / Aether+∨ / Aether+∧ — the subtile language ×1.45).
// ---------------------------------------------------------------------------

class _DescLayer extends StatelessWidget {
  const _DescLayer({required this.forId, required this.onClose});

  final ProtocolId forId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final strings = AppStrings.of(context);

    final bool isFamily = forId.isPsiphon || forId.isTor;
    final blocks = <({String text, bool chain, bool reverse})>[
      if (isFamily) ...[
        (
          text: forId.isPsiphon ? strings.descPsiphonOnly : strings.descTorOnly,
          chain: false,
          reverse: false,
        ),
        (
          text: forId.isPsiphon
              ? strings.descPsiphonChain
              : strings.descTorChain,
          chain: true,
          reverse: false,
        ),
        (
          text: forId.isPsiphon
              ? strings.descPsiphonReverse
              : strings.descTorReverse,
          chain: true,
          reverse: true,
        ),
      ] else
        (
          text: switch (forId) {
            ProtocolId.auto => strings.descAuto,
            ProtocolId.masque => strings.descMasque,
            ProtocolId.wireguard => strings.descWireguard,
            ProtocolId.gool => strings.descGool,
            ProtocolId.goolClassic => strings.descGoolClassic,
            ProtocolId.mim => strings.descMim,
            _ => strings.descMasque,
          },
          chain: false,
          reverse: false,
        ),
    ];

    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          if (t < 0.01) return const SizedBox.shrink();
          return Stack(
            children: [
              // Second scrim over the dimmed sheet (the frame's desc page
              // reads ~1.5-2× darker than the sheet around it).
              Positioned(
                top: AethGeometry.protoScrimTop * s,
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Opacity(
                    opacity: t,
                    child: const ColoredBox(
                      color: Color(0xC20C120F), // #0C120F @ 76%
                    ),
                  ),
                ),
              ),
              // × close — Ø22 thin white ring + the set's Close.svg
              Positioned(
                top: AethGeometry.protoDescCloseTop * s,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Container(
                      width: AethGeometry.protoDescCloseSize * s,
                      height: AethGeometry.protoDescCloseSize * s,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AethColors.cardDark,
                        border: Border.all(
                          color: AethColors.textPrimary.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: SvgPicture.asset(
                        AppAssets.iconClose,
                        width: 10 * s,
                        height: 10 * s,
                        colorFilter: const ColorFilter.mode(
                          AethColors.textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // the card
              Positioned(
                top: AethGeometry.protoDescCardTop * s,
                left: AethGeometry.protoRightInset * s,
                right: AethGeometry.protoRightInset * s,
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.96 + 0.04 * t,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              ),
            ],
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AethColors.sheetDescCard,
            borderRadius: BorderRadius.circular(AethGeometry.protoDescCardRadius * s),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 32 * s,
                      vertical: 10 * s,
                    ),
                    child: Container(
                      height: 1,
                      color: AethColors.sheetSubtile,
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    32 * s, // left text pad (frame: text starts x≈60)
                    i == 0 ? 24 * s : 8 * s,
                    30 * s + 22 * s + 12 * s, // pad + icon column + gap
                    i == blocks.length - 1 ? 24 * s : 8 * s,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          blocks[i].text,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'IRANYekanX',
                            fontWeight: FontWeight.w400,
                            fontSize: AethGeometry.protoDescTextSize * s,
                            height:
                                AethGeometry.protoDescTextHeight / AethGeometry.protoDescTextSize,
                            color: AethColors.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * s),
                      SizedBox(
                        width: 22 * s,
                        child: _StackGlyph(
                          protocol: forId,
                          chain: blocks[i].chain,
                          reverse: blocks[i].reverse,
                          scale: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
