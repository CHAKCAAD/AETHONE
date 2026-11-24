/// GitHub spark burst — the connecting→connected EDGE celebration
/// (flutterfx port, owner round 23: «وقتی اتصال شکل گرفت باید از انیمیشن
/// GitHub Spark استفاده بشه و از پشت دکمه اتصال وسط صفحه به سرعت
/// اسپارک به جهات مختلف بریزه»).
///
/// Adapted from flutterfx_widgets `particles-github-spark` (MIT License,
/// Copyright (c) 2024 FlutterFX —
/// https://github.com/flutterfx/flutterfx_widgets): the original's
/// `RisingParticles` walks every particle along a cubic Bézier S-curve
/// (two randomized control points), rotating it TWO full turns
/// (`progress × 4π`) while it shrinks toward 30 % of its born size and
/// fades out on an easeIn ramp, drawing each as a circle, a four-point
/// curved star or a diamond.
///
/// This port keeps the PARTICLE ENGINE verbatim — the Bézier walk, the
/// double rotation, the eased shrink-and-fade, the three shapes and the
/// 4-second family feel — and re-aims the geometry at the decree: the
/// sparks are born BEHIND the connect button's centre and POUR OUTWARD
/// in every direction ("به جهات مختلف"), a quick ONE-SHOT on the
/// moment the tunnel really forms, never a steady-state ambience. The
/// palette is the connected green family (the burst celebrates a REAL
/// connection — the accent pair plus white), not the demo's violet set.
///
/// Round 24 (the owner: «انیمیشن اسپارک بعد از موفقیت اتصال گسترده تر
/// باشه و سرعتش کمی کمتر باشه تا کاربر بتونه ببینه») — the burst is
/// WIDER and SLOWER: every spark flies ~2× further out (up to 2.0× the
/// halo band's radius, vs the old 1.3×), the family is fatter (34 vs
/// 26) with bigger sparks, and the whole one-shot rides the recipe's
/// [MotionRecipe.celebrationMs] ×1.5 — the eye can actually follow it.
///
/// House rules (prompt §11.7 / report §10):
///  * ONE-SHOT on the state EDGE — a stats re-notify that re-builds the
///    same `connected` state never re-fires it, and nothing loops once
///    the sparks die;
///  * MotionStyle.off renders nothing at all;
///  * pure decoration — [IgnorePointer] wraps the mount, nothing gates;
///  * a radial burst has no reading order — RTL-safe by construction;
///  * the tempo rides [MotionRecipe.celebrationMs] (the edge it owns),
///    so each personality keeps its feel.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../connection/connection_state.dart';
import '../motion.dart';

/// The one-shot spark field, mounted BEHIND the connect button. [size] is
/// the outer box (the halo band); the sparks are born at its centre.
class GitHubSparkBurst extends StatefulWidget {
  const GitHubSparkBurst({
    super.key,
    required this.state,
    required this.style,
    required this.size,
    this.quantity = 34,
  });

  final VpnState state;
  final MotionStyle style;

  /// The outer box (logical px — the caller passes the scaled halo size).
  final double size;

  /// Sparks per burst (round 24 — 34: the WIDER family the owner asked
  /// for; the demo ships 50 for a full screen).
  final int quantity;

  @override
  State<GitHubSparkBurst> createState() => _GitHubSparkBurstState();
}

class _GitHubSparkBurstState extends State<GitHubSparkBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shot = AnimationController(vsync: this);

  /// The sparks of the LIVE burst (empty ⇒ nothing paints, nothing ticks).
  List<_Spark> _sparks = const [];

  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    // A cold start into `connected` never plays a phantom burst — only
    // the EDGE fires (didUpdateWidget below). When a burst completes the
    // field clears: nothing paints, nothing ticks.
    _shot.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _sparks.isNotEmpty) {
        setState(() => _sparks = const []);
      }
    });
  }

  @override
  void didUpdateWidget(covariant GitHubSparkBurst old) {
    super.didUpdateWidget(old);
    final landed = old.state != VpnState.connected &&
        widget.state == VpnState.connected &&
        (old.state == VpnState.connecting ||
            old.state == VpnState.reconnecting ||
            old.state == VpnState.starting ||
            old.state == VpnState.waitingForPermissions);
    if (!landed) return;
    // Round 24 — the ×1.5 tempo stretch (the owner: «سرعتش کمی کمتر
    // باشه تا کاربر بتونه ببینه»): the recipe's celebration slot stays
    // the style's own base (SILK 950 → 1425 ms, TIDE 1200 → 1800,
    // SPRING 800 → 1200, BLINK 600 → 900).
    final ms = (widget.style.recipe.celebrationMs * 1.5).round();
    if (widget.style == MotionStyle.off || ms <= 0) return;
    _spawn();
    _shot
      ..stop()
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _shot.dispose();
    super.dispose();
  }

  /// The burst's geometry: every spark is born at the centre and flies
  /// to a random point on a WIDE disc — round 24: the reach runs
  /// 0.95–2.0× the halo band's radius (the old 0.55–1.3× family hugged
  /// the button; the painter spills past its own box freely — the hero
  /// stack's Clip.none hosts it). The demo's randomized S-curve control
  /// points become perpendicular offsets along the way.
  void _spawn() {
    final r = widget.size / 2;
    _sparks = [
      for (var i = 0; i < widget.quantity; i++)
        _Spark(
          start: Offset.zero,
          end: Offset.fromDirection(
            _random.nextDouble() * 2 * math.pi,
            r * (0.95 + 1.05 * _random.nextDouble()),
          ),
          bend1: Offset.fromDirection(
                _random.nextDouble() * 2 * math.pi,
                r * (0.15 + 0.45 * _random.nextDouble()),
              ),
          bend2: Offset.fromDirection(
                _random.nextDouble() * 2 * math.pi,
                r * (0.15 + 0.45 * _random.nextDouble()),
              ) +
              Offset(0, -r * 0.22), // the rising bias of the demo's walk
          size: 3.5 + _random.nextDouble() * 5.5,
          color: _palette[_random.nextInt(_palette.length)],
          shape: _SparkShape.values[_random.nextInt(
            _SparkShape.values.length,
          )],
        ),
    ];
  }

  /// The connected family — the green gradient pair + white (the decree's
  /// celebration of a real tunnel; the demo's violet set stays in the demo).
  static const List<Color> _palette = [
    Color(0xFF2FF8B1),
    Color(0xFF1AD995),
    Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    if (_sparks.isEmpty) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return AnimatedBuilder(
      animation: _shot,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _SparkFieldPainter(sparks: _sparks, t: _shot.value),
      ),
    );
  }
}

/// One spark's Bézier contract (pre-walk bookkeeping).
class _Spark {
  const _Spark({
    required this.start,
    required this.end,
    required this.bend1,
    required this.bend2,
    required this.size,
    required this.color,
    required this.shape,
  });

  final Offset start;
  final Offset end;
  final Offset bend1;
  final Offset bend2;
  final double size;
  final Color color;
  final _SparkShape shape;
}

enum _SparkShape { circle, star, diamond }

/// The demo's painter, ported: the cubic-Bézier walk, the eased opacity
/// (1 − easeIn), the eased shrink (→ 30 % of the born size) and the
/// `progress × 4π` rotation, drawn as circle / curved star / diamond.
class _SparkFieldPainter extends CustomPainter {
  _SparkFieldPainter({required this.sparks, required this.t});

  final List<_Spark> sparks;

  /// The burst's progress (0..1).
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    for (final s in sparks) {
      final eased = Curves.easeIn.transform(t);
      final paint = Paint()
        ..color = s.color.withValues(alpha: 1.0 - eased)
        ..style = PaintingStyle.fill;
      final at = _bezier(t, s.start, s.bend1, s.bend2, s.end);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(t * 4 * math.pi); // two full turns, verbatim
      final sparkSize = s.size * (1.0 - (0.7 * eased)); // → 30 %, verbatim
      switch (s.shape) {
        case _SparkShape.circle:
          canvas.drawCircle(Offset.zero, sparkSize, paint);
        case _SparkShape.star:
          _drawStar(canvas, sparkSize, paint);
        case _SparkShape.diamond:
          _drawDiamond(canvas, sparkSize, paint);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  /// The demo's cubic point resolver.
  static Offset _bezier(double t, Offset p0, Offset p1, Offset p2, Offset p3) {
    final t1 = math.pow(1 - t, 3).toDouble();
    final t2 = 3 * math.pow(1 - t, 2) * t;
    final t3 = 3 * (1 - t) * t * t;
    final t4 = math.pow(t, 3).toDouble();
    return Offset(
      t1 * p0.dx + t2 * p1.dx + t3 * p2.dx + t4 * p3.dx,
      t1 * p0.dy + t2 * p1.dy + t3 * p2.dy + t4 * p3.dy,
    );
  }

  /// The demo's four-point star — four quadratic curves whose control
  /// points pull inward (0.4×), one per quarter turn.
  static void _drawStar(Canvas canvas, double size, Paint paint) {
    final path = Path();
    const control = 0.4;
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final px = math.cos(angle) * size;
      final py = math.sin(angle) * size;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        final prev = (i - 1) * math.pi / 2;
        final mid = prev + math.pi / 4;
        path.quadraticBezierTo(
          math.cos(mid) * size * control,
          math.sin(mid) * size * control,
          px,
          py,
        );
      }
    }
    path.quadraticBezierTo(
      math.cos(7 * math.pi / 4) * size * control,
      math.sin(7 * math.pi / 4) * size * control,
      size,
      0,
    );
    canvas.drawPath(path, paint);
  }

  /// The demo's diamond.
  static void _drawDiamond(Canvas canvas, double size, Paint paint) {
    final path = Path()
      ..moveTo(0, -size)
      ..lineTo(size, 0)
      ..lineTo(0, size)
      ..lineTo(-size, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparkFieldPainter old) => old.t != t;
}
