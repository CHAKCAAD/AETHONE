/// v1.0.2 motion-overhaul — the reusable FEEDBACK widgets every surface
/// shares. Pure Flutter built-ins; no new packages.
///
///  * [PressSpring]   — a REAL spring press (down = fast squash, up =
///                      [SpringSimulation] return with a hair of overshoot;
///                      the "alive" press the reference study prescribes).
///  * [AnimatedValueText] — value/text swaps without flicker: an
///                      asymmetric fade + micro-rise crossfade whose key is
///                      the text itself, so a stats tick that does NOT
///                      change a value re-animates nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';

/// Press feedback that behaves like a spring, not a timer.
///
/// Press-DOWN is a fast 100 ms squash (the surface must feel the finger
/// immediately); release runs a [SpringSimulation] back to rest so the
/// return overshoots a hair — the personality's own stiffness/damping from
/// [MotionRecipe.pressStiffness]/[pressDamping]. [MotionStyle.off] skips
/// the squash entirely (the tap still fires — animations never block
/// actions).
///
/// Haptic: one [AethHaptics.tap] on press-down (the micro "felt you" word);
/// state-commit words stay with the store/gesture sites, never here.
class PressSpring extends StatefulWidget {
  const PressSpring({
    super.key,
    required this.onTap,
    required this.child,
    this.style = MotionStyle.standard,
    this.haptic = true,
  });

  final VoidCallback? onTap;
  final Widget child;

  /// The motion personality (press squash depth + spring tuning).
  final MotionStyle style;

  /// Whether the micro haptic fires on press-down.
  final bool haptic;

  @override
  State<PressSpring> createState() => _PressSpringState();
}

class _PressSpringState extends State<PressSpring>
    with SingleTickerProviderStateMixin {
  /// Unbounded so the spring may overshoot past rest (scale > 1) — a
  /// bounded controller would clamp the life out of the return.
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  static const _downMs = 100;

  @override
  void initState() {
    super.initState();
    _press.addListener(_tick);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _down() {
    if (widget.haptic) AethHaptics.tap();
    _press
      ..stop()
      ..animateTo(
        1,
        duration: const Duration(milliseconds: _downMs),
        curve: Curves.easeOut,
      );
  }

  void _up() {
    final r = widget.style.recipe;
    _press.stop();
    if (r.pressStiffness <= 0) {
      // OFF (or a personality with no spring) — land instantly.
      _press.value = 0;
      if (mounted) setState(() {});
      return;
    }
    _press.animateWith(
      SpringSimulation(
        SpringDescription(
          mass: 1,
          stiffness: r.pressStiffness,
          damping: r.pressDamping,
        ),
        _press.value,
        0,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.style.recipe;
    final depth = 1 - r.pressScale; // 0 for OFF — no squash at all.

    // The press VISUALS ride a raw [Listener] — pointer events arrive the
    // SAME FRAME the finger lands, never held back by the tap arena's
    // ~100 ms resolution deadline (the audit's «touch immediate» rule).
    // The ACTION stays on [GestureDetector.onTap] — arena-resolved, the
    // platform's own tap semantics (a drag that leaves the surface is a
    // cancel, not a tap). Nothing is ever delayed by the animation.
    if (depth <= 0) {
      // The kill-switch identity: no transform layer at all — the child
      // renders untouched and the tap still fires.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.onTap == null ? null : (_) => _down(),
        onPointerUp: widget.onTap == null ? null : (_) => _up(),
        onPointerCancel: widget.onTap == null ? null : (_) => _up(),
        child: Transform.scale(
          scale: 1 - depth * _press.value,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A value/text that never pops: when [text] changes, the new value lands
/// SOFTLY — it fades in (35% → 100%) with a 3 px micro-rise over the
/// style's quick tempo. Exactly ONE [Text] renders per frame by design:
/// a LIVE counter (the speed-test gauge updates several times a second)
/// must never stack the outgoing number beside the incoming one — the
/// old value is replaced the same frame, the new one simply arrives
/// already-legible and settles (no flicker, no double text, no layout
/// shift; `find.text` in the widget tests keeps matching verbatim).
///
/// OFF swaps instantly; an unchanged text re-animates nothing (the stats
/// tick re-notifying with the same bytes is a no-op).
class AnimatedValueText extends StatefulWidget {
  const AnimatedValueText(
    this.text, {
    super.key,
    this.style,
    this.textStyle,
    this.textAlign,
    this.textDirection,
    this.maxLines,
    this.overflow,
  });

  final String text;

  /// The motion personality (falls back to [MotionScope] when null).
  final MotionStyle? style;

  final TextStyle? textStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<AnimatedValueText> createState() => _AnimatedValueTextState();
}

class _AnimatedValueTextState extends State<AnimatedValueText>
    with SingleTickerProviderStateMixin {
  /// Starts COMPLETE — the first build renders the plain, full-opacity
  /// text (no entrance on mount, exactly like the raw Text it replaces).
  late final AnimationController _settle = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant AnimatedValueText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    final s = widget.style ?? MotionScope.of(context);
    if (s == MotionStyle.off) {
      _settle.value = 1; // instant swap — the kill-switch identity
      return;
    }
    _settle.duration = motionDuration(s, MotionDurations.quick);
    _settle.forward(from: 0);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style ?? MotionScope.of(context);
    final text = Text(
      widget.text,
      key: ValueKey(widget.text),
      style: widget.textStyle,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
    if (s == MotionStyle.off) return text;
    return AnimatedBuilder(
      animation: _settle,
      builder: (context, child) {
        final t = _settle.value;
        if (t >= 0.999) return child!;
        final e = Curves.easeOutCubic.transform(t);
        return Opacity(
          opacity: 0.35 + 0.65 * e,
          child: Transform.translate(
            offset: Offset(0, 3 * (1 - e)),
            child: child,
          ),
        );
      },
      child: text,
    );
  }
}
