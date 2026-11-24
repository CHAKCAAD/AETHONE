/// v4.45 — THE PROTOCOL SELECTION BOTTOM SHEET (the owner's redesign).
///
/// The protocol selection is no longer a pushed page: tapping the protocol
/// card on the home screen slides a BOTTOM SHEET up over the home, with
/// the entrance choreography adapted from flutterfx_widgets `bottom-sheet`
/// (MIT License, Copyright (c) 2024 FlutterFX —
/// https://github.com/flutterfx/flutterfx_widgets):
///   * the HOME behind the sheet scales to 0.85, rises 24 ref px and
///     rounds its top corners to r16 while the barrier dims — the repo's
///     own scale-and-slide recipe, verbatim proportions;
///   * the sheet itself slides up from the screen bottom and carries the
///     owner's committed frame «انتخاب پروتکل.jpg» (402×874 @2×) plus
///     the owner's own Figma CSS: panel 402×565 top-corners r38 with the
///     `0 -6 64 rgba(0,0,0,0.09)` shadow, the 97×8 handle pill 17 below
///     the top edge, and the 2×6 grid of 159×67 r17 protocol cards
///     (17 px gaps, 33 px page inset);
///   * drag-to-dismiss: dragging the sheet down follows the finger, the
///     release snaps by velocity/distance (the flutterfx handlers).
///
/// The 12 tiles flatten the old family cards — each combined mode is its
/// own tile (tor / psiphon / tow / pow / wot / wop), and AUTO carries the
/// owner's new uploaded mark (آیکون پروتکل auto.png — see ProtocolGlyph).
/// Round 25 — the frame's OWN Latin labels and the per-tile calibrated
/// icon heights are BACK (the owner: «منظورم این بود که لوگو ها به سمت چپ
/// تراز بشن، اینکه سایزشون رو تغییر بدی»): what the round-24 re-cut
/// retired is restored, and the [icon ⇒ label] group now packs to the
/// tile's LEFT edge — so the twelve logos read as two tidy aligned
/// columns down the grid, LEFT-locked like the frame's own reading.
/// The SELECTED state is the standing green gradient under a 4px
/// rgba(26,217,149,0.4) ring with white icon + white label (owner CSS
/// «Rectangle 13»); selecting still AUTO-CLOSES the sheet after the green
/// crossfade lands (the owner's v4.16 decree, carried over from the page).
///
/// House rules kept (prompt §11.7 / report §10):
///  * the entrance/exit read the SELECTED motion style's own curve and
///    tempo (SILK's easeInOutCubic IS the flutterfx curve; OFF renders
///    the open state instantly, no decoration);
///  * the tap action commits the protocol IMMEDIATELY — the close ride is
///    pure decoration, never a gate;
///  * the sheet content listens to [ConnectionStore], so the green
///    crossfade applies the moment a tap lands, independent of the close;
///  * the grid is LTR-locked — the frame's own reading (wireguard on the
///    visual LEFT, auto on the visual RIGHT) never bidi-flips.
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../shared/protocol_glyph.dart';

/// The handle the home screen uses to open/close the sheet — the flutterfx
/// `CustomDrawerController` pattern (the controller outlives the host and
/// silently no-ops when no host is mounted).
class ProtocolSheetController {
  _ProtocolSheetHostState? _host;

  /// Whether the sheet is currently fully open.
  bool get isOpen => _host?._controller.value == 1.0;

  /// Slide the sheet fully open.
  void open() => _host?._controller.forward();

  /// Slide the sheet fully closed.
  void close() => _host?._controller.reverse();

  /// Toggle between open and closed.
  void toggle() => isOpen ? close() : open();

  /// Detach any mounted host (the owner widget's dispose hook).
  void detach() => _host = null;
}

/// Hosts the home screen AND the protocol sheet in one Stack: [mainContent]
/// is the full home (it scales/slides/rounds while the sheet opens), the
/// sheet rides above it with the dimming barrier between. Exactly one host
/// should live in the app (the home screen).
class ProtocolSheetHost extends StatefulWidget {
  const ProtocolSheetHost({
    super.key,
    required this.controller,
    required this.store,
    required this.mainContent,
  });

  final ProtocolSheetController controller;
  final ConnectionStore store;

  /// The home screen — rendered untouched while the sheet is closed.
  final Widget mainContent;

  @override
  State<ProtocolSheetHost> createState() => _ProtocolSheetHostState();
}

class _ProtocolSheetHostState extends State<ProtocolSheetHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The protocol currently pulsing from a selection tap (auto-close
  /// follows) — the v4.16 hold, carried over from the retired page.
  ProtocolId? _pulseId;

  @override
  void initState() {
    super.initState();
    // v4.46 fix — NO inherited lookups in initState (the first cut read
    // the motion style here, which calls MediaQuery through the store —
    // illegal before the state is mounted and it killed every test that
    // pumps a home). The controller starts on the baseline tempo; the
    // build below retunes it on the very first frame (and after any
    // settings round-trip) — where reading the style is legal.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: MotionDurations.page),
    );
    widget.controller._host = this;
  }

  @override
  void didUpdateWidget(covariant ProtocolSheetHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._host = null;
      widget.controller._host = this;
    }
    // A mid-session style change retunes the slide's tempo in build
    // (the legal place for the store's MediaQuery read).
  }

  @override
  void dispose() {
    if (widget.controller._host == this) widget.controller._host = null;
    _controller.dispose();
    super.dispose();
  }

  /// The flutterfx drag-to-dismiss bookkeeping.
  bool _dragging = false;
  double _dragStartValue = 0;
  double _dragDistance = 0;

  void _onDragStart(DragStartDetails _) {
    _dragging = true;
    _dragStartValue = _controller.value;
    _dragDistance = 0;
  }

  void _onDragUpdate(DragUpdateDetails details, double sheetH) {
    if (!_dragging) return;
    _dragDistance += details.primaryDelta ?? 0;
    _controller.value =
        (_dragStartValue - _dragDistance / sheetH).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 200) {
      _controller.reverse(); // flick down → close
    } else if (velocity < -200) {
      _controller.forward(); // flick up → open
    } else {
      _controller.value > 0.5 ? _controller.forward() : _controller.reverse();
    }
  }

  /// Tap-a-tile: commit IMMEDIATELY (the action never waits), let the
  /// green crossfade + pulse land for the v4.16 300 ms hold, then slide
  /// the sheet away (the owner's auto-return decree).
  void _select(ProtocolId id) {
    if (_controller.value < 0.95) return; // already closing — ignore
    final already = widget.store.selectedProtocol == id;
    setState(() => _pulseId = id);
    if (!already) widget.store.selectProtocol(id);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.store.effectiveMotionStyle(context);
    final curve = style == MotionStyle.off ? Curves.linear : style.curve;
    // The style read is legal here — retune the slide's tempo every
    // build (a no-op when unchanged; a settings round-trip retimes it).
    _controller.duration = motionDuration(style, MotionDurations.page);

    return LayoutBuilder(builder: (context, box) {
      final s = box.maxWidth / AethGeometry.refWidth;
      // v4.46 — the panel clears the gesture bar: the frame itself ends
      // the sheet ~7 ref px above the glass (its own bottom inset), so
      // the anchor is the bottom SAFE inset, not the physical edge.
      final bottomInset = MediaQuery.paddingOf(context).bottom;
      // The panel height is the frame's own 565 ref px (clamped on squat
      // viewports so the sheet can never swallow the whole screen).
      final sheetH =
          box.maxHeight >= AethGeometry.protoSheetH * s + bottomInset
              ? AethGeometry.protoSheetH * s
              : (box.maxHeight - bottomInset) * 0.92;

      return Stack(
        children: [
          // ── The home: scales down, rises, rounds its top corners ─────
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              if (_controller.value == 0) return child!;
              final t = curve.transform(_controller.value);
              return Transform.scale(
                scale: 1 + (AethGeometry.protoSheetMainScale - 1) * t,
                child: Transform.translate(
                  offset: Offset(0, -AethGeometry.protoSheetMainRise * s * t),
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(
                        AethGeometry.protoSheetMainRadius * s * t,
                      ),
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: widget.mainContent,
          ),

          // ── The dimming barrier (tap = close) ────────────────────────
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              if (_controller.value == 0) return const SizedBox.shrink();
              return Positioned.fill(
                child: GestureDetector(
                  onTap: _controller.reverse,
                  behavior: HitTestBehavior.opaque,
                  child: IgnorePointer(
                    ignoring: false,
                    child: DecoratedBox(
                      key: const ValueKey('proto-sheet-barrier'),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha: AethGeometry.protoSheetBarrierAlpha *
                              _controller.value,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // ── The sheet panel (drag-to-dismiss on the whole panel) ──────
          AnimatedBuilder(
            animation: Listenable.merge([_controller, widget.store]),
            builder: (context, _) {
              if (_controller.value == 0) return const SizedBox.shrink();
              final t = curve.transform(_controller.value);
              return Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset,
                height: sheetH,
                child: Transform.translate(
                  offset: Offset(0, sheetH * (1 - t)),
                  child: GestureDetector(
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: (d) => _onDragUpdate(d, sheetH),
                    onVerticalDragEnd: _onDragEnd,
                    behavior: HitTestBehavior.opaque,
                    child: _SheetPanel(
                      store: widget.store,
                      pulseId: _pulseId,
                      onSelect: _select,
                      // v4.46 — the squat-viewport guard: only a CLAMPED
                      // sheet scrolls its grid (the fixed column keeps
                      // the whole-panel drag-to-dismiss).
                      gridScrolls: sheetH < AethGeometry.protoSheetH * s - 0.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    });
  }
}

/// The sheet's own surface: handle + the 2×6 grid, LTR-locked. When
/// [gridScrolls] (a squat viewport clamped the panel) the grid rides a
/// scroll view so it can never overflow; on the reference viewport the
/// fixed column renders pixel-identical to the frame.
class _SheetPanel extends StatelessWidget {
  const _SheetPanel({
    required this.store,
    required this.pulseId,
    required this.onSelect,
    this.gridScrolls = false,
  });

  final ConnectionStore store;
  final ProtocolId? pulseId;
  final void Function(ProtocolId) onSelect;

  /// v4.46 — true when the host had to clamp the panel below the frame's
  /// own 565 px (the grid then scrolls instead of overflowing).
  final bool gridScrolls;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;

    return Container(
      key: const ValueKey('proto-sheet-panel'),
      decoration: BoxDecoration(
        // The sheet surface: #FFFFFF light / #000000 night (round 24 —
        // the home screen's own page-bg pair) — the DEDICATED protoSheetBg
        // slot (NOT cardDark: the round-22 re-cut made that the home-card
        // family #F4F4F4/#1C1C1C, which rendered the panel the same color
        // as its own chips).
        color: AethColors.protoSheetBg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AethGeometry.protoSheetRadius * s),
        ),
        boxShadow: [
          BoxShadow(
            // Owner CSS Rectangle 88: 0 -6 64 rgba(0,0,0,0.09).
            color: Colors.black
                .withValues(alpha: AethGeometry.protoSheetShadowAlpha),
            offset: Offset(0, AethGeometry.protoSheetShadowDy * s),
            blurRadius: AethGeometry.protoSheetShadowBlur * s,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The drag handle (owner CSS Rectangle 89): 97×8 pill, 17 below
          // the sheet's top edge (Padding+Center so the keyed pill's own
          // rect is exactly the pill — no margin inside the render box).
          SizedBox(
            height: (AethGeometry.protoSheetHandleTop +
                    AethGeometry.protoSheetHandleH) *
                s,
            child: Padding(
              padding: EdgeInsets.only(
                top: AethGeometry.protoSheetHandleTop * s,
              ),
              child: Center(
                child: Container(
                  key: const ValueKey('proto-sheet-handle'),
                  width: AethGeometry.protoSheetHandleW * s,
                  height: AethGeometry.protoSheetHandleH * s,
                  decoration: BoxDecoration(
                    color: AethColors.protoSheetChip,
                    borderRadius: BorderRadius.circular(
                      AethGeometry.protoSheetHandleH * s,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Handle bottom (25) → grid top (53): the frame's own 28 px.
          SizedBox(
            height: (AethGeometry.protoSheetGridTop -
                    AethGeometry.protoSheetHandleTop -
                    AethGeometry.protoSheetHandleH) *
                s,
          ),
          // v4.46 — the squat-viewport guard: on a clamped sheet the grid
          // rides a scroll view (it can never overflow the panel); on the
          // reference viewport the fixed column renders pixel-identical
          // to the frame and the WHOLE panel keeps the flutterfx
          // drag-to-dismiss (a scrollable would otherwise steal the
          // grid's vertical drags). The 25 px bottom padding keeps the
          // frame's own bottom rhythm while scrolling.
          if (gridScrolls)
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: (AethGeometry.protoSheetInset - 8) * s),
                  child: _grid(context, s),
                ),
              ),
            )
          else
            _grid(context, s),
        ],
      ),
    );
  }

  /// The 2×6 grid — LTR-locked (the frame's own reading order).
  Widget _grid(BuildContext context, double s) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: AethGeometry.protoSheetInset * s),
        child: Column(
          children: [
            for (var row = 0; row < _sheetRows.length; row++) ...[
              if (row > 0)
                SizedBox(height: AethGeometry.protoSheetCardGap * s),
              Row(
                children: [
                  for (var col = 0; col < _sheetRows[row].length; col++) ...[
                    if (col > 0)
                      SizedBox(
                        width: AethGeometry.protoSheetCardGap * s,
                      ),
                    Expanded(
                      child: _ProtoTile(
                        spec: _sheetRows[row][col],
                        selected:
                            store.selectedProtocol == _sheetRows[row][col].id,
                        pulsing: pulseId == _sheetRows[row][col].id,
                        onSelect: onSelect,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One grid slot: the protocol id + the frame's own LATIN label
/// (`text-transform: capitalize`) + the calibrated icon height (the CSS
/// vector boxes of the committed frame). Round 25 — the frame's own
/// labels and heights are RESTORED (the round-24 localized re-cut is
/// retired: the owner's decree was the LEFT alignment, not a rename or
/// a re-size; the app's localized names keep riding the home card and
/// the settings, exactly as before).
class _TileSpec {
  const _TileSpec(this.id, this.label, this.iconH, {this.wide = false});

  final ProtocolId id;
  final String label;
  final double iconH;

  /// Lantern round — the full-width card (the owner's frame: the logo at
  /// the tile's own left inset, the label CENTERED on the whole card).
  final bool wide;
}

/// The frame's grid, row by row, visual LEFT → RIGHT:
///   wireguard | auto      mim | masq      g classic | gool
///   tor | psiphon         tow | pow       wot | wop
///   lantern (full width)
const List<List<_TileSpec>> _sheetRows = [
  [
    _TileSpec(ProtocolId.wireguard, 'Wireguard', 19),
    _TileSpec(ProtocolId.auto, 'Auto', 23),
  ],
  [
    _TileSpec(ProtocolId.mim, 'M I M', 28),
    _TileSpec(ProtocolId.masque, 'Masq', 19),
  ],
  [
    _TileSpec(ProtocolId.goolClassic, 'G Classic', 26),
    _TileSpec(ProtocolId.gool, 'Gool', 26),
  ],
  [
    _TileSpec(ProtocolId.torOnly, 'Tor', 28),
    _TileSpec(ProtocolId.psiphonOnly, 'Psiphon', 34),
  ],
  [
    _TileSpec(ProtocolId.torChain, 'T O W', 28),
    _TileSpec(ProtocolId.psiphonChain, 'P O W', 30),
  ],
  [
    _TileSpec(ProtocolId.torReverse, 'W O T', 31),
    _TileSpec(ProtocolId.psiphonReverse, 'W O P', 31),
  ],
  // Lantern round — the owner's frame: one full-width Lantern card under
  // the grid (the sidecar core, Android only).
  [
    _TileSpec(ProtocolId.lantern, 'Lantern', 40, wide: true),
  ],
];

/// One protocol card: 159×67 r17, the LEFT-packed [icon 18 label]
/// group (round 25 — the logos lead from the tile's own left inset, so
/// the grid reads as two aligned logo columns).
/// Unselected: the chip fill + the theme-ink icon + [AethColors.textPrimary]
/// label. Selected: the standing green gradient under the 4px green ring,
/// all-white icon + label. The crossfade rides one 260 ms tween (the old
/// page's own rhythm).
class _ProtoTile extends StatefulWidget {
  const _ProtoTile({
    required this.spec,
    required this.selected,
    required this.pulsing,
    required this.onSelect,
  });

  final _TileSpec spec;
  final bool selected;
  final bool pulsing;
  final void Function(ProtocolId) onSelect;

  @override
  State<_ProtoTile> createState() => _ProtoTileState();
}

class _ProtoTileState extends State<_ProtoTile>
    with SingleTickerProviderStateMixin {
  // v4.46 fix — the pulse RESTS at 1.0 (the first cut left the controller
  // at its lowerBound, so every tile permanently rendered 3 % small —
  // 1 px off its frame geometry — until its own tap). forward() still
  // rides 0.97 → 1.0 (the v4.16 spring-settle on a selection tap).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    lowerBound: 0.97,
  )..value = 1.0;

  @override
  void didUpdateWidget(covariant _ProtoTile old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !old.pulsing) {
      _pulse.forward(); // 0.97 → 1.0 spring-ish settle (the v4.16 pulse)
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Lantern round — the full-width card's content (the owner's frame):
  /// the logo keeps the grid's left inset, the label centers on the card.
  Widget _wideContent(_TileSpec spec, double s, double t) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ProtocolGlyph(
            id: spec.id,
            size: spec.iconH * s,
            white: t > 0.5,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (spec.iconH + AethGeometry.protoSheetIconGap) * s,
          ),
          child: Text(
            spec.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w400,
              fontSize: AethGeometry.protoSheetLabelSize * s,
              height: 18 / 16,
              color: Color.lerp(
                AethColors.textPrimary,
                const Color(0xFFFFFFFF),
                t,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;

    return Semantics(
      button: true,
      label: spec.label,
      child: ScaleTransition(
        scale: _pulse,
        child: GestureDetector(
          key: ValueKey('proto-tile-${spec.id.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(spec.id),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: widget.selected ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            builder: (context, t, _) {
              final chip = AethColors.protoSheetChip;
              return Container(
                height: AethGeometry.protoSheetCardH * s,
                decoration: BoxDecoration(
                  // The selected fill crossfades INTO the standing green
                  // gradient (both stops lerp from the flat chip color).
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        chip,
                        AethColors.accentConnectedGradient.colors.first,
                        t,
                      )!,
                      Color.lerp(
                        chip,
                        AethColors.accentConnectedGradient.colors.last,
                        t,
                      )!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(
                    AethGeometry.protoSheetCardRadius * s,
                  ),
                  border: Border.all(
                    width: AethGeometry.protoSheetCardBorder * s,
                    color: AethColors.accentConnected.withValues(
                      alpha: AethGeometry.protoSheetCardRingAlpha * t,
                    ),
                  ),
                ),
                // Round 25 — the group packs to the tile's LEFT edge
                // (the owner: «لوگو ها به سمت چپ تراز بشن»): every logo
                // in a column leads from the same x (the Container MERGES
                // this pad with the 4 px ring — _paddingIncludingDecoration
                // — so the glyph starts at tile edge + 4 + 16), and the
                // grid reads as two tidy aligned logo columns. The grid
                // itself is LTR-locked (see _grid), so «start» is the
                // VISUAL left under the fa locale too.
                padding: EdgeInsets.only(
                  left: AethGeometry.protoSheetTilePadLeft * s,
                  // The wide Lantern card mirrors the pad so its label
                  // centers on the whole card.
                  right: spec.wide ? AethGeometry.protoSheetTilePadLeft * s : 0,
                ),
                child: spec.wide
                    ? _wideContent(spec, s, t)
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    // Round 25 — the per-tile calibrated heights are
                    // RESTORED (the owner: «سایز لوگوها رو هم به حالت
                    // قبل برگردون»); the round-24 uniform 24 ref-px box
                    // is retired.
                    ProtocolGlyph(
                      id: spec.id,
                      size: spec.iconH * s,
                      // The standing all-ink white rule lands at the
                      // crossfade's midpoint (the theme's own swap beat).
                      white: t > 0.5,
                    ),
                    SizedBox(width: AethGeometry.protoSheetIconGap * s),
                    // v4.46 — the label is FLEXIBLE (the no-overflow
                    // decree): on the real IRANYekanX metrics every
                    // frame label fits the 151.5 px ink box naturally,
                    // and an unexpected metric can only ellipsize —
                    // never push the row past the card.
                    Flexible(
                      child: Text(
                        spec.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w400,
                          fontSize: AethGeometry.protoSheetLabelSize * s,
                          height: 18 / 16,
                          color: Color.lerp(
                            AethColors.textPrimary,
                            const Color(0xFFFFFFFF),
                            t,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
