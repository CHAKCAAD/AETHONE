/// Status pill + Speed Test button.
///
/// Status pill («غیرفعال»/«متصل», shield cross/tick icon, 16px w600 text on
/// the 4-layer pill) — text colors from Figma CSS: #75160F on red, #123E2B on
/// green. The Speed Test button uses the SAME 4-layer structure (owner) and
/// appears with animation ONLY after a real connection exists.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
import '../../../connection/connection_state.dart';
import 'custom_icons.dart';
import 'glow_pill.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.state,
    required this.style,
  });

  final VpnState state;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.quick);
    final curve = style.curve;

    final connected = state == VpnState.connected;
    final (label, iconAsset) = switch (state) {
      VpnState.connected =>
        (strings.statusConnected, AppAssets.iconShieldTick),
      VpnState.connecting => (strings.statusConnecting, AppAssets.iconShieldCross),
      VpnState.reconnecting =>
        (strings.statusReconnecting, AppAssets.iconShieldCross),
      VpnState.failed => (strings.statusFailed, AppAssets.iconShieldCross),
      _ => (strings.statusDisconnected, AppAssets.iconShieldCross),
    };
    final fg = connected
        ? AethColors.onPillConnected
        : AethColors.onPillDisconnected;

    return GlowPill(
      active: connected,
      onTap: null, // status indicator, not a button
      duration: duration,
      curve: curve,
      child: AnimatedSwitcher(
        duration: duration,
        child: Row(
          key: ValueKey('pill-$label'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              iconAsset,
              width: 18 * s,
              height: 18 * s,
              colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
            ),
            SizedBox(width: 8 * s),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 16 * s,
                height: 18 / 16, // Figma: line-height 18 on 16px
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Speed Test entry — visible ONLY when connected (pixel-verified: absent in
/// every disconnected reference frame). The reference frame shows a SOLID
/// 43×43 green squircle (x 179–222, y 534–577) with a subtle neon halo —
/// not the 4-layer pill structure — with the hex-wave icon in dark green.
class SpeedTestButton extends StatelessWidget {
  const SpeedTestButton({
    super.key,
    required this.visible,
    required this.style,
    required this.onTap,
  });

  final bool visible;
  final MotionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.state);
    final size = AethGeometry.speedButtonWidth * s;
    final glow = AethColors.accentConnected.withValues(alpha: 0.45);

    // Animated appearance (scale + fade). OFF style ⇒ instant.
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: duration,
      curve: style.curve,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        child: IgnorePointer(
          ignoring: !visible,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Subtle neon halo behind the squircle.
                  Positioned.fill(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: AethGeometry.pillBlur * s,
                        sigmaY: AethGeometry.pillBlur * s,
                      ),
                      child: Container(
                        width: size * 1.35,
                        height: size * 1.35,
                        decoration: BoxDecoration(
                          color: glow,
                          borderRadius: BorderRadius.circular(size * 0.7),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: AethColors.accentConnected,
                      borderRadius: BorderRadius.circular(size * 0.3),
                    ),
                    child: Center(
                      child: HexWaveIcon(
                        size: 18 * s,
                        color: AethColors.onPillConnected,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
