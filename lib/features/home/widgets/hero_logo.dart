/// Look-1 hero: the central app logo. Disconnected: the artwork as committed
/// (correlation 0.997 against the reference frame). Connected: rotated 60°
/// counter-clockwise — the pose measured on حالت متصل-ضاهر1 (correlation
/// 0.933 vs 45°: 0.771 and 75°: 0.624), where the mark's tip points EXACTLY
/// upward (owner defect #6: «نوک آن دقیقا رو به بالا نیست»). Tint animates
/// red ↔ green with the state.
///
/// While the engine is walking toward a connection (starting / connecting /
/// reconnecting) an animated scanning halo (expanding rings, defect #10)
/// plays BEHIND the logo — see [ScanRings].
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

class HeroLogo extends StatelessWidget {
  const HeroLogo({
    super.key,
    required this.connected,
    required this.style,
  });

  final bool connected;
  final MotionStyle style;

  /// Reference-measured pose: 60° CCW = 1/6 turn. Flutter `turns` are
  /// clockwise-positive, hence the negative fraction.
  static const double _connectedTurns = -1 / 6;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.heroSize * s;
    final duration = motionDuration(style, MotionDurations.state);
    final curve = style.curve;

    return AnimatedRotation(
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
          colorFilter: ColorFilter.mode(color ?? AethColors.statusDisconnected,
              BlendMode.srcIn),
        ),
      ),
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
