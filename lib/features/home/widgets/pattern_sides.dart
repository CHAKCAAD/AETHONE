/// Edge background patterns — the four committed artworks (red when
/// disconnected, green when connected), shipped as pre-rendered PNGs
/// (v4.10: the SVG sources carry feGaussianBlur, which flutter_svg cannot
/// rasterize — on device the blurred edge circles rendered as SOLID blobs,
/// the single worst visual defect of the first preview build).
///
/// The color change is animated as a crossfade between the two artwork
/// variants (owner: «با انیمیشن به رنگ سبز تغییر پیدا می‌کنند»). Patterns
/// anchor to the screen edges at their natural aspect (viewBox 228×589 /
/// 232×616, artwork hugging the outer edge) — rendered at 2× for sharpness.

library;

import 'package:flutter/material.dart';

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
              child: Image.asset(
                key: ValueKey('pattern-left-${connected ? 'on' : 'off'}'),
                connected
                    ? AppAssets.patternConnectedLeft
                    : AppAssets.patternDisconnectedLeft,
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: duration,
              child: Image.asset(
                key: ValueKey('pattern-right-${connected ? 'on' : 'off'}'),
                connected
                    ? AppAssets.patternConnectedRight
                    : AppAssets.patternDisconnectedRight,
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerRight,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
