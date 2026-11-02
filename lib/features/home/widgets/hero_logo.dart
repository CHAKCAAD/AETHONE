/// Look-1 hero: the central app logo. Disconnected: upright, tinted red
/// (#EA2323). Connected: rotated 45° counter-clockwise ("به سمت چپ") and
/// tinted green (#1AD995) — the owner's exact described animation. The base
/// artwork is the clean white logo (آیکون اپ/3.svg) so ONE asset can tint and
/// rotate; the pre-composed green artwork (1.svg) stays available as an
/// alternative if the static variant is preferred (documented).
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

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.heroSize * s;
    final duration = motionDuration(style, MotionDurations.state);
    final curve = style.curve;

    return AnimatedRotation(
      turns: connected ? -0.125 : 0.0, // 45° counter-clockwise (to the left)
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
        builder: (context, color) => SvgPicture.asset(
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
