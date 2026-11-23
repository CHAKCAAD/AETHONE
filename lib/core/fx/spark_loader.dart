/// Spark loader — the connecting-state animation (v4.45).
///
/// Adapted from flutterfx_widgets `particles-spark-loader`
/// (StepRotatingShape — MIT License, Copyright (c) 2024 FlutterFX —
/// https://github.com/flutterfx/flutterfx_widgets): the four-point curved
/// star rotates in 90° STEPS, each step an easeOutBack spring with a short
/// pause between steps — the repo's own loader personality.
///
/// THE PORT: the original was a free-standing demo shape; here it is the
/// home's CONNECTION-ATTEMPT animation (owner: «حین اتصال از انیمیشن Spark
/// Loader استفاده کن»), replacing the retired ScanRings halo — it renders
/// BEHIND the central logo/connect button while the engine walks and is
/// gone the moment a verdict lands.
///
/// v4.46 fix — the step/pause rhythm now rides ONE repeating 500 ms clock
/// (300 ms rotate + 200 ms pause) instead of the first cut's
/// `Future.delayed` chain: a bare Future kept a TIMER alive after the
/// tree was disposed mid-walk (the connect tests' "Timer is still
/// pending" failure) and the loop could re-arm after unmount. A
/// controller's ticker dies with dispose — nothing can outlive the
/// widget.
///
/// House rules kept (prompt §11.7 / report §10):
///  * state-honest — the caller only mounts it while the walk is live;
///  * the OFF style parks the clock (a static star, no ticking);
///  * a rotation has no reading order — RTL-safe by construction;
///  * ONE controller, one repaint per frame while stepping.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';

/// The step-rotating four-point star.
class SparkLoader extends StatefulWidget {
  const SparkLoader({
    super.key,
    required this.color,
    required this.size,
    this.style = MotionStyle.standard,
  });

  /// The star's ink (the caller passes the state accent — green while the
  /// walk is a connect, red while it is a disconnect/reconnect).
  final Color color;

  /// The star's layout box in logical px (the ink spans ~80 % of it — the
  /// flutterfx original's own `size * 0.8` fit rule).
  final double size;

  /// The motion style: SPRING keeps the flutterfx easeOutBack step;
  /// SILK/TIDE/BLINK soften it; OFF parks the star (accessibility clamp).
  final MotionStyle style;

  @override
  State<SparkLoader> createState() => _SparkLoaderState();
}

class _SparkLoaderState extends State<SparkLoader>
    with SingleTickerProviderStateMixin {
  /// ONE clock per full step cycle: 0 → 0.6 rotates, 0.6 → 1 rests.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _stepDuration + _pauseDuration, // 300 + 200 ms
  );

  /// The completed 90° steps (the live step rides the clock's phase).
  int _currentStep = 0;

  /// The previous frame's phase — a wrap (1 → 0) completes a step.
  double _prevPhase = 0.0;

  /// The flutterfx tempo: 300 ms rotate + 200 ms pause.
  static const Duration _stepDuration = Duration(milliseconds: 300);
  static const Duration _pauseDuration = Duration(milliseconds: 200);

  /// The rotation share of the cycle (0.6 = 300/500).
  static const double _rotateShare = 300 / 500;

  @override
  void initState() {
    super.initState();
    // Registered BEFORE the build's AnimatedBuilder listener, so the step
    // counter is already advanced when the angle is next painted.
    _clock.addListener(_onPhase);
    _start();
  }

  @override
  void didUpdateWidget(covariant SparkLoader old) {
    super.didUpdateWidget(old);
    // A mid-walk style change (settings round-trip) only retunes the
    // tempo; the star keeps its phase.
    if (old.style != widget.style) {
      _start();
    }
  }

  @override
  void dispose() {
    _clock.dispose(); // stops the ticker — nothing outlives the widget
    super.dispose();
  }

  void _onPhase() {
    final v = _clock.value;
    if (v < _prevPhase) {
      _currentStep = (_currentStep + 1) % 4; // the wrap completes a step
    }
    _prevPhase = v;
  }

  void _start() {
    if (!mounted) return;
    if (widget.style == MotionStyle.off) {
      _clock.stop(); // the kill-switch: a static star, nothing ticks
      return;
    }
    if (!_clock.isAnimating) _clock.repeat();
  }

  /// The step's easing — the flutterfx original's easeOutBack, kept for
  /// every style except the OFF clamp (the SPRING personality is exactly
  /// this overshoot; the softer styles ease without it).
  Curve get _curve => switch (widget.style) {
        MotionStyle.off => Curves.linear,
        MotionStyle.dynamic => Curves.easeOutBack,
        MotionStyle.minimal => Curves.easeOut,
        _ => Curves.easeOutBack,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          // 0..1 within the rotation share; clamped at 1 through the rest.
          final rotate =
              (_clock.value / _rotateShare).clamp(0.0, 1.0).toDouble();
          final angle = _currentStep * (math.pi / 2) +
              _curve.transform(rotate) * (math.pi / 2);
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SparkStarPainter(rotationAngle: angle, color: widget.color),
          );
        },
      ),
    );
  }
}

/// The four-point star — the flutterfx StarPainter, verbatim geometry:
/// quadratic curves between the four cardinal points with the control
/// points pulled toward the centre (the `0.4 × fullSize` inset).
class _SparkStarPainter extends CustomPainter {
  const _SparkStarPainter({
    required this.rotationAngle,
    required this.color,
  });

  final double rotationAngle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final center = Offset(size.width / 2, size.height / 2);
    final fullSize = size.width / 2 * 0.8; // the repo's own 80 % fit rule
    final cp = fullSize * 0.4;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationAngle);
    canvas.translate(-center.dx, -center.dy);

    final path = Path();
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final pointX = center.dx + math.cos(angle) * fullSize;
      final pointY = center.dy + math.sin(angle) * fullSize;
      if (i == 0) {
        path.moveTo(pointX, pointY);
      } else {
        final midAngle = (i - 1) * math.pi / 2 + math.pi / 4;
        path.quadraticBezierTo(
          center.dx + math.cos(midAngle) * cp,
          center.dy + math.sin(midAngle) * cp,
          pointX,
          pointY,
        );
      }
    }
    path.quadraticBezierTo(
      center.dx + math.cos(7 * math.pi / 4) * cp,
      center.dy + math.sin(7 * math.pi / 4) * cp,
      center.dx + fullSize,
      center.dy,
    );

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparkStarPainter oldDelegate) =>
      oldDelegate.rotationAngle != rotationAngle || oldDelegate.color != color;
}
