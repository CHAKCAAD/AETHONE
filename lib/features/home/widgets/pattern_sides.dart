/// Edge background patterns — the four committed SVGs (red when
/// disconnected, green when connected). The color change is animated as a
/// crossfade between the two artwork variants (owner: "با انیمیشن به رنگ سبز
/// تغییر پیدا می‌کنند"). Patterns anchor to the screen edges at their natural
/// aspect (viewBox 232×589 / 228×616, artwork hugging the outer edge).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/motion.dart';

class PatternSides extends StatelessWidget {
  const PatternSides({
    super.key,
    required this.connected,
    required this.style,
  });

  final bool connected;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(style, MotionDurations.state);
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: duration,
              child: SvgPicture.asset(
                key: ValueKey('pattern-left-${connected ? 'on' : 'off'}'),
                connected
                    ? AppAssets.patternConnectedLeft
                    : AppAssets.patternDisconnectedLeft,
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: duration,
              child: SvgPicture.asset(
                key: ValueKey('pattern-right-${connected ? 'on' : 'off'}'),
                connected
                    ? AppAssets.patternConnectedRight
                    : AppAssets.patternDisconnectedRight,
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerRight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
