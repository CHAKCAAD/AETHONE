/// Edge background patterns — the four committed artworks (red when
/// disconnected, green when connected), shipped as pre-rendered PNGs
/// (v4.10: the SVG sources carry feGaussianBlur, which flutter_svg cannot
/// rasterize — on device the blurred edge circles rendered as SOLID blobs,
/// the single worst visual defect of the first preview build).
///
/// v4.12 placement (owner: «پترن‌های چپ و راست رو ۴۰ درصد کوچک‌تر کن، الان
/// خیلی بزرگن»): each canvas renders at [AethGeometry.patternScale] (0.6) of
/// the screen width — the artwork is 40% smaller than the v4.11 full-width
/// span. Anchors keep the v4.11 composition, mirrored to the artwork side:
///   * LEFT canvas (art hugs its left edge): pinned to the screen LEFT edge,
///     art bottom on the screen bottom → the art band sits below mid-screen.
///   * RIGHT canvas (art hugs its right edge): pinned to the screen RIGHT
///     edge, art top on the screen top → the art band sits above mid-screen.
///
/// The color change is animated as a crossfade between the two artwork
/// variants (owner: «با انیمیشن به رنگ سبز تغییر پیدا می‌کنند»).
library;

import 'package:flutter/material.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

class PatternSides extends StatelessWidget {
  const PatternSides({super.key, required this.connected, required this.style});

  final bool connected;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(style, MotionDurations.state);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;

        // v4.12: canvases at 60% of the screen width (art 40% smaller).
        // Left canvas: pinned to the LEFT edge; art bottom on screen bottom.
        final leftW = w * AethGeometry.patternScale;
        final leftH = leftW * AethGeometry.patternLeftAspect;
        final leftTop = h - leftH * AethGeometry.patternLeftAnchorBottom;

        // Right canvas: pinned to the RIGHT edge; art top on screen top.
        final rightW = w * AethGeometry.patternScale;
        final rightH = rightW * AethGeometry.patternRightAspect;
        final rightTop = -rightH * AethGeometry.patternRightAnchorTop;

        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: leftTop,
                width: leftW,
                height: leftH,
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Image.asset(
                    key: ValueKey('pattern-left-${connected ? 'on' : 'off'}'),
                    connected
                        ? AppAssets.patternConnectedLeft
                        : AppAssets.patternDisconnectedLeft,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: rightTop,
                width: rightW,
                height: rightH,
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Image.asset(
                    key: ValueKey('pattern-right-${connected ? 'on' : 'off'}'),
                    connected
                        ? AppAssets.patternConnectedRight
                        : AppAssets.patternDisconnectedRight,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
