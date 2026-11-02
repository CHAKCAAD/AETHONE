/// Look-1 hero: the central app logo. Disconnected: the artwork as committed
/// (correlation 0.997 against the reference frame). Connected: rotated 57°
/// counter-clockwise (v4.12 — owner: «میزان چرخش آیکون وسط صفحه به اندازه ۶۰
/// درجه زیاده، کمترش کن به ۵۷ درجه»; the v4.11 pose was the measured 60°).
/// Tint animates red ↔ green with the state.
///
/// While the engine is walking toward a connection (starting / connecting /
/// reconnecting) an animated scanning halo (expanding rings, defect #10)
/// plays BEHIND the logo — see [ScanRings].
///
/// CONNECTED IDLE (v4.12 — owner: «بعد از اتصال هم آیکون وسط صفحه یک انیمیشن
/// جذاب داشته باشه تا صفحه بی روح نباشه»): the logo breathes — a slow,
/// gentle scale pulse driven by [ConnectedAura]'s phase — and the
/// [ConnectedAura] radial halo breathes BEHIND it (see home_screen: the aura
/// is mounted for BOTH looks). MotionStyle.off disables the idle motion
/// (accessibility rule) — the state change animations stay.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

class HeroLogo extends StatelessWidget {
  const HeroLogo({super.key, required this.connected, required this.style});

  final bool connected;
  final MotionStyle style;

  /// v4.12 pose: 57° CCW (owner-tuned down from the measured 60°). Flutter
  /// `turns` are clockwise-positive, hence the negative fraction.
  static const double _connectedTurns = -57 / 360;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.heroSize * s;
    final duration = motionDuration(style, MotionDurations.state);
    final curve = style.curve;

    final Widget logo = AnimatedRotation(
      turns: connected ? _connectedTurns : 0.0,
      duration: duration,
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

/// The connected aura (v4.12): a soft radial halo BEHIND the central icon
/// that breathes in the same 2.6 s phase as the logo pulse — the connected
/// screen stays alive without stealing attention. Mounted for BOTH looks by
/// home_screen (hero logo / look-2 connect button).
class ConnectedAura extends StatefulWidget {
  const ConnectedAura({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<ConnectedAura> createState() => _ConnectedAuraState();
}

class _ConnectedAuraState extends State<ConnectedAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
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
        final t = Curves.easeInOut.transform(_controller.value);
        final d = widget.size * (0.92 + 0.14 * t);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.color.withValues(alpha: 0.05 + 0.09 * t),
                    widget.color.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
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
