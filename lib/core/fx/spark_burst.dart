/// Spark burst — the connection-established celebration (v4.45).
///
/// Adapted from flutterfx_widgets `particles-github-spark`
/// (RisingParticles — MIT License, Copyright (c) 2024 FlutterFX —
/// https://github.com/flutterfx/flutterfx_widgets): the original streamed
/// particles UP the screen forever on cubic Bézier paths. This port keeps
/// the particle identity — the circle/star/diamond shapes, the spin, the
/// shrink-and-fade, the repo's own four-ink palette — and re-aims it at
/// the owner's moment: the instant the tunnel REALLY comes up, a ONE-SHOT
/// burst of sparks flies out from behind the central connect button in
/// every direction («وقتی اتصال برقرار میشه جرقه ها از پشت دکمه اتصال به
/// همه جهت ها پرت بشن»).
///
/// House rules kept (prompt §11.7 / report §10):
///  * state-honest — the burst fires ONLY on the real connected edge
///    (the store's own verdict), never on a selection or a tap;
///  * ONE shared clock that runs only while sparks are alive — an idle
///    field paints nothing and schedules nothing;
///  * the OFF style renders nothing at all;
///  * a radial burst has no reading order — RTL-safe by construction.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';

/// The handle the home screen fires the burst through — the flutterfx
/// controller idiom (outlives the field, silently no-ops when unmounted).
class SparkBurstController {
  _SparkBurstState? _state;

  /// Fire a one-shot burst from the field's centre.
  void fire() => _state?._fire();

  /// Detach any mounted field (the owner widget's dispose hook).
  void detach() => _state = null;

  /// Whether a field is currently mounted (tests assert on this).
  bool get isAttached => _state != null;
}

enum _SparkShape { circle, star, diamond }

/// The one-shot radial spark field. Mount it centred wherever the burst
/// should originate (behind the home's central connect composition).
class SparkBurst extends StatefulWidget {
  const SparkBurst({
    super.key,
    required this.controller,
    required this.style,
    this.count = 26,
    this.maxSize = 7,
    this.minSize = 3,
    this.colors = const [
      Color(0xFF4C40BB), // deep purple/blue
      Color(0xFF5DEC88), // bright green
      Color(0xFFFF4423), // bright red/orange
      Color(0xFF8157E8), // bright purple
    ],
  });

  final SparkBurstController controller;

  /// The motion style: the burst's tempo scales with it; OFF renders
  /// nothing (the kill-switch).
  final MotionStyle style;

  /// Sparks per burst (the flutterfx demo's 50, halved for the one-shot
  /// moment — the GPU budget rule every fx port follows).
  final int count;

  /// Spark size range in logical px.
  final double maxSize;
  final double minSize;

  /// The repo's own GitHub-spark palette.
  final List<Color> colors;

  @override
  State<SparkBurst> createState() => _SparkBurstState();
}

class _SparkBurstState extends State<SparkBurst>
    with SingleTickerProviderStateMixin {
  /// ONE shared clock for every spark; it only runs while sparks are
  /// alive (stopped the frame the last one dies).
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addListener(_tick);

  final math.Random _random = math.Random();
  final List<_Spark> _sparks = [];
  Size _field = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(covariant SparkBurst old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    _clock.dispose();
    super.dispose();
  }

  void _fire() {
    if (!mounted || widget.style == MotionStyle.off) return;
    if (_field == Size.zero) return; // no layout yet — nothing to aim at
    setState(_spawn);
    if (!_clock.isAnimating) {
      _clock
        ..value = 0
        ..repeat();
    }
  }

  /// The radial re-aim of the flutterfx recipe: every spark is born AT
  /// the centre and flies out along its own curved path — direction
  /// uniform, distance and curvature random, the repo's own sizes,
  /// shapes, palette and speed spread.
  void _spawn() {
    _sparks.clear();
    final w = widget;
    for (var i = 0; i < w.count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final dist = (0.28 + _random.nextDouble() * 0.72) * _field.shortestSide / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      // The perpendicular bow — the S-curve's curvature, re-aimed radially.
      final bow = (_random.nextDouble() * 60 + 30) *
          (_random.nextBool() ? 1 : -1) *
          (w.minSize / 3 + 1);
      final perp = Offset(-dir.dy, dir.dx) * bow;
      final start = _field.center(Offset.zero);
      _sparks.add(
        _Spark(
          start: start,
          control1: start + dir * dist * 0.33 + perp,
          control2: start + dir * dist * 0.66 - perp,
          end: start + dir * dist,
          size: _random.nextDouble() * (w.maxSize - w.minSize) + w.minSize,
          color: w.colors[_random.nextInt(w.colors.length)],
          shape: _SparkShape.values[_random.nextInt(_SparkShape.values.length)],
          born: _clock.lastElapsedDuration ?? Duration.zero,
          speed: 0.9 + _random.nextDouble() * 0.5,
        ),
      );
    }
  }

  void _tick() {
    if (!mounted) return;
    final now = _clock.lastElapsedDuration ?? Duration.zero;
    setState(() {
      _sparks.removeWhere((s) => s.progressAt(now, widget.style) >= 1.0);
      if (_sparks.isEmpty) _clock.stop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / 402;
    // The field: a generous box around the burst origin (the centre
    // composition) — sparks fly up to ~half the screen width out.
    final side = 420 * s;
    return SizedBox(
      width: side,
      height: side,
      child: LayoutBuilder(
        builder: (context, box) {
          _field = box.biggest;
          return IgnorePointer(
            child: AnimatedBuilder(
              animation: _clock,
              builder: (context, _) => CustomPaint(
                size: box.biggest,
                painter: _SparkBurstPainter(
                  sparks: [
                    for (final s in _sparks)
                      s.lerped(now: _clock.lastElapsedDuration ?? Duration.zero,
                          style: widget.style),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One spark's bookkeeping (pre-lerp).
class _Spark {
  const _Spark({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
    required this.size,
    required this.color,
    required this.shape,
    required this.born,
    required this.speed,
  });

  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;
  final double size;
  final Color color;
  final _SparkShape shape;

  /// Birth time on the shared clock (all sparks of one burst share it —
  /// the one-shot field has no stagger).
  final Duration born;

  /// The flutterfx speed spread (0.2–0.5 there; re-scaled for the quick
  /// one-shot flight: 0.9–1.4 progress-per-second).
  final double speed;

  static const Duration _life = Duration(milliseconds: 1100);

  double progressAt(Duration now, MotionStyle style) =>
      ((now - born).inMicroseconds / _life.inMicroseconds) * speed;

  _LerpedSpark lerped({required Duration now, required MotionStyle style}) {
    final t = progressAt(now, style).clamp(0.0, 1.0);
    // The repo's own easing: easeIn on the fade and the shrink.
    final eased = Curves.easeIn.transform(t);
    return _LerpedSpark(
      position: _bezier(
        t,
        start,
        control1,
        control2,
        end,
      ),
      size: size * (1 - (0.7 * eased)), // 100 % → 30 %
      alpha: 1 - eased,
      rotation: t * 4 * math.pi, // two full spins, the repo's own rule
      color: color,
      shape: shape,
    );
  }

  static Offset _bezier(double t, Offset a, Offset c1, Offset c2, Offset b) {
    final t1 = math.pow(1 - t, 3).toDouble();
    final t2 = 3 * math.pow(1 - t, 2) * t;
    final t3 = 3 * (1 - t) * math.pow(t, 2);
    final t4 = math.pow(t, 3).toDouble();
    return Offset(
      t1 * a.dx + t2 * c1.dx + t3 * c2.dx + t4 * b.dx,
      t1 * a.dy + t2 * c1.dy + t3 * c2.dy + t4 * b.dy,
    );
  }
}

class _LerpedSpark {
  const _LerpedSpark({
    required this.position,
    required this.size,
    required this.alpha,
    required this.rotation,
    required this.color,
    required this.shape,
  });

  final Offset position;
  final double size;
  final double alpha;
  final double rotation;
  final Color color;
  final _SparkShape shape;
}

/// The painter — the flutterfx shapes, verbatim (circle / curved star /
/// diamond), each rotated around its own centre.
class _SparkBurstPainter extends CustomPainter {
  const _SparkBurstPainter({required this.sparks});

  final List<_LerpedSpark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparks) {
      if (s.alpha <= 0) continue;
      final paint = Paint()
        ..color = s.color.withValues(alpha: s.alpha)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.save();
      canvas.translate(s.position.dx, s.position.dy);
      canvas.rotate(s.rotation);
      canvas.translate(-s.position.dx, -s.position.dy);

      switch (s.shape) {
        case _SparkShape.circle:
          canvas.drawCircle(s.position, s.size, paint);
        case _SparkShape.star:
          _drawStar(canvas, s.position, s.size, paint);
        case _SparkShape.diamond:
          final path = Path()
            ..moveTo(s.position.dx, s.position.dy - s.size)
            ..lineTo(s.position.dx + s.size, s.position.dy)
            ..lineTo(s.position.dx, s.position.dy + s.size)
            ..lineTo(s.position.dx - s.size, s.position.dy)
            ..close();
          canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  /// The repo's own star: four quadratic curves, control points pulled to
  /// 0.4 × the radius.
  void _drawStar(Canvas canvas, Offset center, double size, Paint paint) {
    final fullSize = size;
    final cp = fullSize * 0.4;
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final px = center.dx + math.cos(angle) * fullSize;
      final py = center.dy + math.sin(angle) * fullSize;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        final mid = (i - 1) * math.pi / 2 + math.pi / 4;
        path.quadraticBezierTo(
          center.dx + math.cos(mid) * cp,
          center.dy + math.sin(mid) * cp,
          px,
          py,
        );
      }
    }
    path.quadraticBezierTo(
      center.dx + math.cos(7 * math.pi / 4) * cp,
      center.dy + math.sin(7 * math.pi / 4) * cp,
      center.dx + fullSize,
      center.dy,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparkBurstPainter oldDelegate) => true;
}
