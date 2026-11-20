/// Tap ripple — the look-2 connect button's touch burst (v4.43).
///
/// Adapted from flutterfx_widgets `background-ripples` (MIT License,
/// Copyright (c) 2024 FlutterFX — https://github.com/flutterfx/flutterfx_widgets):
/// the original ran a fixed family of EIGHT concentric circles pulsing
/// forever around a centre (eight `AnimationController`s on `repeat`). This
/// port keeps only the gesture-relevant half: each tap spawns a SMALL BURST
/// of expanding, fading rings from the touch point on ONE shared clock, and
/// the field goes completely idle between taps — an ambient forever-loop
/// already exists behind the hero ([AuroraBloom], owner round #2) and a
/// second one would only double the GPU bill.
///
/// House rules kept (prompt §11.7 / report §10):
///  * rings only ever ANSWER a real tap — nothing loops on its own;
///  * the tap action fires IMMEDIATELY (the burst is pure decoration on
///    top of the existing 120 ms press feedback — never a gate);
///  * a circle has no reading order — RTL-safe by construction;
///  * duration + curve come from the caller, so the 5 animation styles
///    (SILK/TIDE/SPRING/BLINK/OFF) keep their personality; a zero
///    duration (the OFF style) renders nothing at all.
library;

import 'package:flutter/material.dart';

/// The handle a gesture surface uses to spawn bursts — the flutterfx
/// `SplashRevealController` pattern (the controller outlives the state and
/// silently no-ops when no field is mounted).
class TapRippleController {
  _TapRippleState? _state;

  /// Spawn a burst at [origin], in the mounted field's coordinate space.
  void tapAt(Offset origin) => _state?.onTapAt(origin);

  /// Detaches any mounted field (the owner widget's dispose hook — the
  /// private state handle stays library-private).
  void detach() => _state = null;

  /// Whether a field is currently mounted (tests assert on this).
  bool get isAttached => _state != null;
}

/// Spawns [TapRipple.ringsPerTap] expanding rings per tap, staggered,
/// fading out. Renders nothing while idle and nothing at all when
/// [TapRipple.duration] is zero.
class TapRipple extends StatefulWidget {
  const TapRipple({
    super.key,
    required this.controller,
    required this.color,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutCubic,
    this.ringsPerTap = 2,
    this.stagger = const Duration(milliseconds: 90),
    this.maxScale = 1.55,
    this.baseRadius = 54,
    this.child,
  });

  final TapRippleController controller;

  /// Ring stroke colour (the caller passes the state accent — green when
  /// connected, red when disconnected).
  final Color color;

  /// One ring's full expand duration. `Duration.zero` (the OFF style)
  /// disables the effect entirely.
  final Duration duration;

  /// The expansion easing (the caller passes the style's curve).
  final Curve curve;

  /// Rings per tap (the flutterfx demo's density, halved for a button).
  final int ringsPerTap;

  /// Delay between consecutive rings of one tap.
  final Duration stagger;

  /// Final radius as a multiple of [baseRadius].
  final double maxScale;

  /// The innermost ring's starting radius (logical px).
  final double baseRadius;

  /// The button; the rings paint IN FRONT of it (the foreground painter)
  /// so the burst reads as light passing over the surface.
  final Widget? child;

  @override
  State<TapRipple> createState() => _TapRippleState();
}

class _TapRippleState extends State<TapRipple>
    with SingleTickerProviderStateMixin {
  /// The shared burst clock. It only runs while at least one ring is
  /// alive (`repeat`, stopped the frame the last ring dies) — an idle
  /// button paints nothing and schedules nothing.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addListener(_tick);

  final List<_Ring> _rings = [];

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(covariant TapRipple old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller._state == this) {
      widget.controller._state = null;
    }
    _clock.dispose();
    super.dispose();
  }

  /// The clock's monotonic timeline (elapsed since the last cold start —
  /// it is only ever restarted while the field is empty, so recorded
  /// birth times never straddle a reset).
  Duration get _now => _clock.lastElapsedDuration ?? Duration.zero;

  void onTapAt(Offset origin) {
    if (!mounted || widget.duration == Duration.zero) return;
    setState(() {
      for (var i = 0; i < widget.ringsPerTap; i++) {
        _rings.add(_Ring(origin: origin, born: _now + widget.stagger * i));
      }
    });
    if (!_clock.isAnimating) {
      _clock
        ..value = 0
        ..repeat();
    }
  }

  void _tick() {
    if (!mounted) return;
    final now = _now;
    setState(() {
      _rings.removeWhere((r) => now - r.born >= widget.duration);
      if (_rings.isEmpty) {
        _clock.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    return CustomPaint(
      foregroundPainter: _RingPainter(
        rings: [
          for (final r in _rings)
            if (now >= r.born)
              r.lerped(
                t: widget.curve.transform(_progress(now, r.born)),
                maxScale: widget.maxScale,
                baseRadius: widget.baseRadius,
              ),
        ],
        color: widget.color,
      ),
      child: widget.child,
    );
  }

  double _progress(Duration now, Duration born) {
    final total = widget.duration.inMicroseconds;
    if (total <= 0) return 1;
    return ((now - born).inMicroseconds / total).clamp(0.0, 1.0);
  }
}

/// One spawned ring's bookkeeping (pre-lerp).
class _Ring {
  const _Ring({required this.origin, required this.born});

  final Offset origin;
  final Duration born;

  _LerpedRing lerped({
    required double t,
    required double maxScale,
    required double baseRadius,
  }) =>
      _LerpedRing(
        center: origin,
        radius: baseRadius * (1 + (maxScale - 1) * t),
        alpha: (1 - t) * 0.32,
      );
}

class _LerpedRing {
  const _LerpedRing({
    required this.center,
    required this.radius,
    required this.alpha,
  });

  final Offset center;
  final double radius;
  final double alpha;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.rings, required this.color});

  final List<_LerpedRing> rings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ring in rings) {
      if (ring.alpha <= 0) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: ring.alpha)
        ..style = PaintingStyle.stroke
        // 5 → 2.5 px while the ring ages: born fat, dying thin.
        ..strokeWidth = 2.5 + 2.5 * (ring.alpha / 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(ring.center, ring.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => true;
}
