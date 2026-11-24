/// Hero bob — look 1's CONNECTED-state vertical lift (owner round 24:
/// «آیکون اتصال وسط صفحه در نمای1 در حالت متصل یه انیمیشن حرکت به بالا
/// و پایین سریع داشته باشه که صفحه در حالت متصل زیادی خشک نباشه برای
/// میزان سریع بودنش هم میتونی از انیمیشن چرخش هنگام تلاش برای اتصال
/// همین دکمه الهام بگیری یا استفاده کنی»).
///
/// The round-22 stillness decree is RE-CUT for LOOK 1's connected state:
/// the logo (the connect surface) keeps a QUICK up-and-down bob so the
/// live home never reads as dry — the TEMPO is borrowed straight from the
/// walk's own spark march ([SparkLoaderSpin]'s cadence: a 420 ms swing +
/// a 240 ms rest per quarter turn), re-aimed at a vertical lift:
///
///   up-swing 420 ms (easeOutBack — the march swing's own snap, a hair
///     past the lift) → rest 240 ms → down-swing 420 ms → rest 240 ms —
///   one full cycle every 1320 ms, style-scaled through [motionDuration]
///   so each personality keeps its feel.
///
/// House rules (prompt §11.7 / report §10):
///  * STATE-DRIVEN — the loop runs ONLY while [active] (the real
///    connected state); the moment the state clears the loop stops and
///    the logo settles back onto its exact rest baseline (≤ the lift's
///    own 260 ms — the edge is masked by the state crossfade anyway);
///  * MotionStyle.off renders the child untouched — the kill-switch;
///  * nothing here gates anything — the tap lives on the surfaces;
///  * a vertical lift has no reading order — RTL-safe by construction.
library;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../motion.dart';

/// Lifts [child] up and back down in a quick cycle while [active].
class HeroBob extends StatefulWidget {
  const HeroBob({
    super.key,
    required this.active,
    required this.style,
    this.lift = 6,
    this.child,
  });

  /// True while the bob should run (look 1 + the real connected state).
  final bool active;

  /// The motion personality — tempos + the kill-switch.
  final MotionStyle style;

  /// The lift's amplitude in DESIGN px (scaled by the live ref factor at
  /// build time — the hero's own 402-px grammar).
  final double lift;

  final Widget? child;

  @override
  State<HeroBob> createState() => _HeroBobState();
}

class _HeroBobState extends State<HeroBob>
    with SingleTickerProviderStateMixin {
  /// One full cycle: up-swing → rest → down-swing → rest. The swing/rest
  /// split rides the spark march's own cadence (420/240 ms base).
  late final AnimationController _cycle = AnimationController(vsync: this);

  /// The cycle's own proportions (base ms, before style scaling): the
  /// spark-loader swing (420) + its rest (240), mirrored for the return.
  static const int _swingMs = 420;
  static const int _restMs = 240;
  static const int _cycleMs = 2 * (_swingMs + _restMs);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant HeroBob old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.style != widget.style) {
      _sync();
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  void _sync() {
    final run = widget.active && widget.style != MotionStyle.off;
    if (run) {
      _cycle.duration = motionDuration(widget.style, _cycleMs);
      if (!_cycle.isAnimating) _cycle.repeat();
    } else if (widget.style == MotionStyle.off) {
      // The kill-switch: instant rest.
      _cycle
        ..stop()
        ..value = 0;
    } else {
      // The state left connected: settle back onto the rest baseline
      // (the cycle's own 0 — the same beat the state crossfade rides).
      if (_cycle.value != 0) {
        _cycle.animateTo(
          0,
          duration: motionDuration(widget.style, 260),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  /// The cycle's offset profile, 0 → −amp → 0 across one period:
  /// the up-swing over the first 420/1320, a rest, the down-swing over
  /// the third block, a rest. The swings carry the spark march's own
  /// `easeOutBack` snap (a hair past the lift, settling back).
  double _offset(double amp) {
    final t = _cycle.value;
    final swing = _swingMs / _cycleMs; // 0.318
    final rest = _restMs / _cycleMs; // 0.182
    if (t < swing) {
      // Rising: 0 → 1 with the march swing's overshoot.
      return -amp * Curves.easeOutBack.transform(t / swing);
    } else if (t < swing + rest) {
      return -amp; // the hold at the top
    } else if (t < 2 * swing + rest) {
      // Falling: 1 → 0 (eased in — the mirrored swing).
      final u = (t - swing - rest) / swing;
      return -amp * (1 - Curves.easeInOut.transform(u));
    }
    return 0; // the rest at the baseline
  }

  @override
  Widget build(BuildContext context) {
    final kid = widget.child;
    if (kid == null) return const SizedBox.shrink();

    // The kill-switch identity: OFF never even mounts a lift layer.
    if (widget.style == MotionStyle.off) return kid;

    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final amp = widget.lift * s;

    return AnimatedBuilder(
      animation: _cycle,
      builder: (context, child) {
        if (!_cycle.isAnimating && _cycle.value == 0) return child!;
        return Transform.translate(
          offset: Offset(0, _offset(amp)),
          child: child,
        );
      },
      child: kid,
    );
  }
}
