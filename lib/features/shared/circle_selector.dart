/// CIRCLE SELECTOR — the flutterfx «circles_selector» technique, rebuilt
/// natively for AETHONE (owner round 18: «Circle Selector رو در صفحه
/// انتخاب پروتکل هم استفاده کن» — confirming the round-17 decree that
/// landed the centered-flag impulse on the home wheel in r109).
///
/// The reference effect: the selected circle springs up in size while
/// its siblings are PUSHED radially away, the push decaying with
/// distance; everything lands soft. AETHONE's reading of it keeps the
/// app's prime directive (the committed frames are the resting
/// contract): the impulse is TRANSIENT — the selected item overshoots
/// ([MotionRecipe.circleSelectGrow] over its resting size) and the
/// siblings displace ([circleSelectPush] ref px at falloff distance 1)
/// for [MotionRecipe.circleSelectMs], then everything settles back to
/// the pixel-true geometry. [MotionStyle.off] skips the travel.
///
/// Shared vocabulary:
///  * [CircleImpulseCurve] — the springy attack + soft decay (0 → peak
///    with an easeOutBack overshoot → 0);
///  * [circleFalloff] — distance 1 pushes full, each further step 68 %;
///  * [CircleSelectRow] — a row of selectable tiles (the protocol page);
///  * [CircleSelectPop] — a single selectable card (no siblings to push);
///  * the flag WHEEL reads the curve + falloff directly (its items are
///    PageView children, not Row children).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/motion.dart';

/// The impulse shape: easeOutBack to the peak (a springy overshoot on
/// the way up), then an easeInOutCubic settle back to zero.
///
/// NOTE: this overrides [Curve.transform] ITSELF — the base class
/// hardcodes `t == 1.0 → 1.0` (the easing-curve contract), but an
/// IMPULSE must return to ZERO at rest; transformInternal would never
/// see the t = 1 call.
class CircleImpulseCurve extends Curve {
  const CircleImpulseCurve();

  static const double _peakAt = 0.42;

  @override
  double transform(double t) {
    if (t <= 0.0 || t >= 1.0) return 0.0;
    if (t <= _peakAt) {
      return Curves.easeOutBack.transform(t / _peakAt);
    }
    return 1 -
        Curves.easeInOutCubic.transform((t - _peakAt) / (1 - _peakAt));
  }
}

/// Distance 1 (the selected item's nearest siblings) displaces fully;
/// every further step keeps 68 % of it — a soft radial trail like the
/// reference grid's falloff.
double circleFalloff(double distance) {
  if (distance < 1) return 1;
  return math.pow(0.68, distance - 1).toDouble();
}

/// One row of selectable tiles with the Circle-Selector impulse. The
/// children keep their own tap handling; the row only adds the transient
/// geometry on top (Transform — never a re-layout, so the committed
/// tile geometry is untouched at rest).
class CircleSelectRow extends StatefulWidget {
  const CircleSelectRow({
    super.key,
    required this.style,
    required this.rtl,
    required this.children,
    this.selectedIndex,
    this.pulseIndex,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final MotionStyle style;

  /// The row's own reading direction — decides which way "away from the
  /// selected index" points on screen (an RTL row lays index 0 out at
  /// the visual RIGHT, so the push flips).
  final bool rtl;
  final List<Widget> children;

  /// The row's main-axis alignment — carried verbatim to the inner Row
  /// (the protocol tile rows spread `spaceBetween`).
  final MainAxisAlignment mainAxisAlignment;

  /// The currently selected child index (null = nothing selected).
  final int? selectedIndex;

  /// The child a tap just landed on — fires the impulse even when the
  /// tap re-selects the already-selected tile.
  final int? pulseIndex;

  @override
  State<CircleSelectRow> createState() => _CircleSelectRowState();
}

class _CircleSelectRowState extends State<CircleSelectRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _impulse;

  @override
  void initState() {
    super.initState();
    _impulse = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.style.recipe.circleSelectMs),
    );
    if (widget.pulseIndex != null) _impulse.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant CircleSelectRow old) {
    super.didUpdateWidget(old);
    _impulse.duration =
        Duration(milliseconds: widget.style.recipe.circleSelectMs);
    final selChanged =
        old.selectedIndex != widget.selectedIndex && widget.selectedIndex != null;
    final pulsed = old.pulseIndex != widget.pulseIndex &&
        widget.pulseIndex != null;
    if (selChanged || pulsed) _impulse.forward(from: 0);
  }

  @override
  void dispose() {
    _impulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.style.recipe;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final sel = widget.selectedIndex;

    // OFF / zero-amplitude recipes render the plain row untouched.
    if (widget.style == MotionStyle.off ||
        (r.circleSelectGrow == 0 && r.circleSelectPush == 0)) {
      return Row(
        mainAxisAlignment: widget.mainAxisAlignment,
        children: widget.children,
      );
    }

    return AnimatedBuilder(
      animation: _impulse,
      builder: (context, _) {
        final p = const CircleImpulseCurve().transform(_impulse.value);
        return Row(
          mainAxisAlignment: widget.mainAxisAlignment,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _impulseChild(
                i,
                sel,
                p,
                r.circleSelectGrow,
                r.circleSelectPush * s,
              ),
          ],
        );
      },
    );
  }

  Widget _impulseChild(
    int i,
    int? sel,
    double p,
    double grow,
    double push,
  ) {
    final child = widget.children[i];
    if (sel == null || p == 0) return child;
    final isSel = i == sel;
    final d = (i - sel).abs().toDouble();

    // The selected tile springs up; the siblings displace AWAY from it.
    final scale = isSel ? 1 + grow * p : 1.0;
    var dx = 0.0;
    if (!isSel && d >= 1) {
      final dir = widget.rtl ? (sel - i) : (i - sel);
      dx = dir * push * circleFalloff(d) * p;
    }
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.scale(scale: scale, child: child),
    );
  }
}

/// The single-card variant: the springy grow without a sibling push —
/// fires on the selected/tapped edge like the row.
class CircleSelectPop extends StatefulWidget {
  const CircleSelectPop({
    super.key,
    required this.style,
    required this.selected,
    required this.pulsing,
    required this.child,
  });

  final MotionStyle style;
  final bool selected;
  final bool pulsing;
  final Widget child;

  @override
  State<CircleSelectPop> createState() => _CircleSelectPopState();
}

class _CircleSelectPopState extends State<CircleSelectPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _impulse;

  @override
  void initState() {
    super.initState();
    _impulse = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.style.recipe.circleSelectMs),
    );
    if (widget.pulsing || widget.selected) _impulse.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant CircleSelectPop old) {
    super.didUpdateWidget(old);
    _impulse.duration =
        Duration(milliseconds: widget.style.recipe.circleSelectMs);
    final selEdge = widget.selected && !old.selected;
    final pulseEdge = widget.pulsing && !old.pulsing;
    if (selEdge || pulseEdge) _impulse.forward(from: 0);
  }

  @override
  void dispose() {
    _impulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.style.recipe;
    if (widget.style == MotionStyle.off || r.circleSelectGrow == 0) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _impulse,
      builder: (context, child) {
        final p = const CircleImpulseCurve().transform(_impulse.value);
        if (p == 0) return child!;
        return Transform.scale(
          scale: 1 + r.circleSelectGrow * p,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
