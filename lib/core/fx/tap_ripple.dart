/// Tap ripple — the look-2 connect button's touch burst (v4.43, hardened
/// in the flutterfx round 2).
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
/// Round-2 hardening (owner: «Ripple Effect … روی نما ۲ دکمهٔ اتصال هنوز
/// اعمال نشده»):
///  * TIMELINE — the burst clock ACCUMULATES the ticker's per-tick
///    deltas instead of reading the controller's `lastElapsedDuration`
///    raw. That stamp is NULLed by `stop()` and ZEROED by every restart,
///    so ring birth-times recorded on one run could straddle a restart
///    and land in the future of the next run's timeline (invisible
///    bursts). The accumulated sum only ever grows and is paused, never
///    reset, so every born time stays valid across any number of
///    stop/restart cycles — and it still rides the ticker, so it follows
///    the binding's clock in tests exactly as in production.
///  * READABILITY — the v4.43 rings (α .32, 2 rings, hairline blur) were
///    honest but near-invisible on the dark shell. The burst now carries
///    THREE bolder rings (α .55, 6→2 px stroke, crisper blur) plus a soft
///    glow FLASH at the landing point — the effect survives a sunlit
///    screen and still reads as light, not noise.
///
/// House rules kept (prompt §11.7 / report §10):
///  * rings only ever ANSWER a real tap — nothing loops on its own;
///  * the tap action fires IMMEDIATELY (the burst is pure decoration on
///    top of the existing press feedback — never a gate);
///  * a circle has no reading order — RTL-safe by construction;
///  * duration + curve come from the caller, so the 5 animation styles
///    (SILK/TIDE/SPRING/BLINK/OFF) keep their personality; a zero
///    duration (the OFF style) renders nothing at all.
library;

import 'dart:ui' as ui;

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
/// fading out, over a soft landing flash. Renders nothing while idle and
/// nothing at all when [TapRipple.duration] is zero.
class TapRipple extends StatefulWidget {
  const TapRipple({
    super.key,
    required this.controller,
    required this.color,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutCubic,
    this.ringsPerTap = 3,
    this.stagger = const Duration(milliseconds: 80),
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

  /// Rings per tap (the flutterfx demo's density, tuned for a button).
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
  /// The frame driver. It only runs while at least one ring is alive
  /// (`repeat`, stopped the frame the last ring dies) — an idle button
  /// paints nothing and schedules nothing. Its VALUE is meaningless; the
  /// burst timeline is the accumulated [_elapsed] below.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addListener(_tick);

  /// The burst's monotonic timeline: the SUM of every tick delta the
  /// clock has ever produced. `stop()` freezes it (the sum simply stops
  /// growing); a restart resumes from the same value — birth-times
  /// recorded on ANY past run stay in the past, so a burst after an idle
  /// pause renders from the very first frame (the round-2 fix).
  Duration _elapsed = Duration.zero;

  /// The last raw ticker stamp seen — the subtrahend of the next delta.
  /// Reset to zero whenever the clock (re)starts, because a restarted
  /// ticker counts its elapsed from that moment.
  Duration _lastTick = Duration.zero;

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

  /// The burst timeline — the accumulated tick sum. Never resets, so
  /// ring births are always comparable, across any number of runs.
  Duration get _now => _elapsed;

  void onTapAt(Offset origin) {
    if (!mounted || widget.duration == Duration.zero) return;
    setState(() {
      for (var i = 0; i < widget.ringsPerTap; i++) {
        _rings.add(_Ring(origin: origin, born: _now + widget.stagger * i));
      }
    });
    if (!_clock.isAnimating) {
      // A restarted ticker counts from zero — realign the subtrahend so
      // the first delta of the new run is measured against the restart,
      // not against the dead run's last stamp.
      _lastTick = Duration.zero;
      _clock.repeat();
    }
  }

  void _tick() {
    if (!mounted || !_clock.isAnimating) return;
    final tick = _clock.lastElapsedDuration ?? Duration.zero;
    _elapsed += tick - _lastTick;
    _lastTick = tick;
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
        alpha: (1 - t) * 0.55,
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
    // The landing flash: one soft bloom at the touch point, brightest in
    // the first moments of the burst — the readable "light landed" word on
    // a dark shell. It shares the FIRST ring's life (the earliest born).
    if (rings.isNotEmpty) {
      final first = rings.first;
      final flashT = 1 - first.alpha / 0.55; // 0 at birth → 1 at death
      final flash = Paint()
        ..shader = ui.Gradient.radial(
          first.center,
          first.radius,
          [
            color.withValues(alpha: 0.30 * (1 - flashT)),
            color.withValues(alpha: 0),
          ],
        );
      canvas.drawCircle(first.center, first.radius, flash);
    }
    for (final ring in rings) {
      if (ring.alpha <= 0) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: ring.alpha)
        ..style = PaintingStyle.stroke
        // 6 → 2 px while the ring ages: born fat, dying thin.
        ..strokeWidth = 2 + 4 * (ring.alpha / 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(ring.center, ring.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => true;
}
