/// Look-1 hero: the central app logo. Disconnected: the artwork as committed
/// (correlation 0.997 against the reference frame). Connected: rotated 58°
/// COUNTER-CLOCKWISE (v4.17 — owner: «آیکون وسط صفحه باید بعد از اتصال ۵۸
/// درجه به سمت چپ بچرخد در حال حاظر برعکس به سمت راست میچرخد» — the
/// v4.15 clockwise 57° pose was the wrong DIRECTION; the magnitude now
/// lands on the owner's 58°).
///
/// v4.15 — owner home round #1 gave the turn its dedicated 600 ms ease curve
/// («کاملا نرم») — kept. The v4.15 CLOCKWISE direction is superseded by
/// v4.17 (counter-clockwise 58°, see above). Tint animates red ↔ green with
/// the state as before.
///
/// While the engine is walking toward a connection (starting / connecting /
/// reconnecting) an animated scanning halo (expanding rings, defect #10)
/// plays BEHIND the logo — see [ScanRings].
///
/// CONNECTED IDLE: the logo breathes — a slow, gentle scale pulse driven by
/// [AuroraBloom]'s phase — and the [AuroraBloom] glow/ripple halo breathes
/// BEHIND it (see home_screen: the halo is mounted for BOTH looks).
/// MotionStyle.off disables the idle motion (accessibility rule) — the
/// state change animations stay.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

class HeroLogo extends StatelessWidget {
  const HeroLogo({super.key, required this.connected, required this.style});

  final bool connected;
  final MotionStyle style;

  /// v4.17 pose: 58° to the LEFT (counter-clockwise) on connection —
  /// Flutter `turns` are clockwise-positive, so LEFT is negative.
  static const double _connectedTurns = -58 / 360;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.heroSize * s;
    final duration = motionDuration(style, MotionDurations.state);
    final curve = style.curve;

    // v4.15 #1: the rotation gets its own slower base (600 ms) — «کاملا نرم».
    final turnDuration = motionDuration(style, 600);

    final Widget logo = AnimatedRotation(
      turns: connected ? _connectedTurns : 0.0,
      duration: turnDuration,
      curve: curve,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: connected
              ? AethColors.statusDisconnected
              : AethColors.accentConnected,
          end: connected
              ? AethColors.accentConnected
              : AethColors.statusDisconnected,
        ),
        duration: duration,
        curve: curve,
        builder: (context, color, _) => SvgPicture.asset(
          AppAssets.appLogoNeutralWhite,
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(
            color ?? AethColors.statusDisconnected,
            BlendMode.srcIn,
          ),
        ),
      ),
    );

    // Connected idle life: a gentle breathing pulse of the logo itself.
    return _BreathingWhileConnected(
      connected: connected,
      style: style,
      child: logo,
    );
  }
}

/// Slow scale pulse (1.00 → 1.02) that runs ONLY while [connected].
/// With MotionStyle.off the child renders statically (accessibility clamp).
class _BreathingWhileConnected extends StatefulWidget {
  const _BreathingWhileConnected({
    required this.connected,
    required this.style,
    required this.child,
  });

  final bool connected;
  final MotionStyle style;
  final Widget child;

  @override
  State<_BreathingWhileConnected> createState() =>
      _BreathingWhileConnectedState();
}

class _BreathingWhileConnectedState extends State<_BreathingWhileConnected>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.connected && widget.style != MotionStyle.off) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _BreathingWhileConnected old) {
    super.didUpdateWidget(old);
    final animate = widget.connected && widget.style != MotionStyle.off;
    if (animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!animate) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected || widget.style == MotionStyle.off) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(scale: 1.0 + 0.02 * t, child: child);
      },
      child: widget.child,
    );
  }
}

/// The connected halo (v4.15 — owner home round #2: «انیمیشن بعد از اتصال
/// پشت آیکون وسط صفحه زیبا نیست یک انیمیشن زیبا ایجاد کن و این انیمیشن
/// رو بردار»: the v4.13 rotating comet sweep is RETIRED). AURORA BLOOM in
/// its place: a soft breathing glow + three slow water-ripples that expand
/// and fade behind the icon — one quiet 3.9 s ripple cycle (a new ring is
/// born every 1.3 s) and a 2.6 s breath that matches the logo's own pulse
/// (they breathe together, like v4.12). It lives BEHIND the central icon in
/// BOTH looks; the home_screen mounts it only while connected.
class AuroraBloom extends StatefulWidget {
  const AuroraBloom({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<AuroraBloom> createState() => _AuroraBloomState();
}

class _AuroraBloomState extends State<AuroraBloom>
    with TickerProviderStateMixin {
  /// One ripple phase cycle — every 1/3 of it a new ring is born; each ring
  /// takes the full 3.9 s to expand and dissolve.
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3900),
  );

  /// The 2.6 s breathing phase (the logo pulse and the halo breathe
  /// together — kept from v4.12).
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _ripple.repeat();
    _breath.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ripple.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_ripple, _breath]),
      builder: (context, _) {
        final breath = Curves.easeInOut.transform(_breath.value);
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _AuroraBloomPainter(
            color: widget.color,
            ripple: _ripple.value,
            breath: breath,
          ),
        );
      },
    );
  }
}

/// Paints the aurora bloom — all soft edges, no hard rings:
///  1. a faint outer halo (breathes 0.05 ↔ 0.09 alpha);
///  2. a breathing core glow (0.14 ↔ 0.26 alpha, radius 0.28 ↔ 0.35 of the
///     box) that fades to nothing at its edge;
///  3. three staggered water-ripples (phase 0, ⅓, ⅔): each expands from
///     0.16 to 0.46 of the box over 3.9 s while its stroke thins and its
///     alpha decays quadratically — heavily blurred (MaskFilter), so the
///     rings read as soft light, never as hard circles.
class _AuroraBloomPainter extends CustomPainter {
  _AuroraBloomPainter({
    required this.color,
    required this.ripple,
    required this.breath,
  });

  final Color color;
  final double ripple;
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final col = color;

    // 1) Faint outer halo.
    final halo = Paint()
      ..shader = ui.Gradient.radial(
        c,
        size.width * 0.5,
        [
          col.withValues(alpha: 0.05 + 0.04 * breath),
          col.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(c, size.width * 0.5, halo);

    // 2) Breathing core glow.
    final glowRadius = size.width * (0.28 + 0.07 * breath);
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        c,
        glowRadius,
        [
          col.withValues(alpha: 0.14 + 0.12 * breath),
          col.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(c, glowRadius, glow);

    // 3) The three water-ripples.
    for (var i = 0; i < 3; i++) {
      final p = (ripple + i / 3) % 1.0;
      final e = Curves.easeOutCubic.transform(p);
      final fade = math.pow(1 - e, 2).toDouble();
      final ring = Paint()
        ..color = col.withValues(alpha: 0.24 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.008 + 0.024 * fade)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          size.width * (0.007 + 0.014 * fade),
        );
      canvas.drawCircle(
        c,
        size.width * (0.16 + 0.30 * e),
        ring,
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraBloomPainter old) =>
      old.ripple != ripple || old.breath != breath || old.color != color;
}

/// Scanning halo behind the central icon while the engine is trying to
/// connect (owner defect #10: «حین اتصال ... پشت آیکون وسط صفحه باید
/// انیمیشن نمایش داده شود»). Two expanding, fading rings + a breathing
/// core glow — pure Flutter animation, repeats until the state leaves the
/// connecting walk.
class ScanRings extends StatefulWidget {
  const ScanRings({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<ScanRings> createState() => _ScanRingsState();
}

class _ScanRingsState extends State<ScanRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ring(t, startScale: 0.85, endScale: 1.65, baseOpacity: 0.40),
              _ring(
                (t + 0.5) % 1.0,
                startScale: 0.85,
                endScale: 1.65,
                baseOpacity: 0.28,
              ),
              // Breathing core glow hugging the icon.
              Transform.scale(
                scale: 0.72 + 0.06 * (0.5 - (t - 0.5).abs()) * 2,
                child: Container(
                  width: widget.size * 0.62,
                  height: widget.size * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ring(
    double t, {
    required double startScale,
    required double endScale,
    required double baseOpacity,
  }) {
    final eased = Curves.easeOutCubic.transform(t);
    final scale = startScale + (endScale - startScale) * eased;
    final opacity = baseOpacity * (1 - eased);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size * 0.62,
        height: widget.size * 0.62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.color.withValues(alpha: opacity),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}
