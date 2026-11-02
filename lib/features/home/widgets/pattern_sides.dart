/// Edge background patterns — the four committed artworks (red when
/// disconnected, green when connected), shipped as pre-rendered PNGs
/// (v4.10: the SVG sources carry feGaussianBlur, which flutter_svg cannot
/// rasterize — on device the blurred edge circles rendered as SOLID blobs,
/// the single worst visual defect of the first preview build).
///
/// v4.11 placement (owner defect report #1: «پترن‌ها تمام عرض صفحه رو نگرفتن؛
/// چپ کمی پایین‌تر از وسط، راست کمی بالاتر از وسط»):
///   * Each PNG canvas now spans the FULL screen width (the soft green wash
///     + line art reach across the screen like the reference frames).
///   * LEFT canvas: artwork bottom (969/1232 of the canvas) pinned to the
///     screen bottom → the art band sits below mid-screen.
///   * RIGHT canvas: artwork top (205/1178 of the canvas) pinned to the
///     screen top → the art band sits above mid-screen.
///   Measured against حالت متصل-ضاهر1: left art lands y251..874 (frame:
///   261..870), right art y0..618 (frame: 0..760 incl. halo tail).
///
/// The color change is animated as a crossfade between the two artwork
/// variants (owner: «با انیمیشن به رنگ سبز تغییر پیدا می‌کنند»).
library;

import 'package:flutter/material.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
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
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;

        // Left canvas: full width; art bottom anchored to screen bottom.
        final leftH = w * AethGeometry.patternLeftAspect;
        final leftTop = h - leftH * AethGeometry.patternLeftAnchorBottom;

        // Right canvas: full width; art top anchored to screen top.
        final rightH = w * AethGeometry.patternRightAspect;
        final rightTop = -rightH * AethGeometry.patternRightAnchorTop;

        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: leftTop,
                width: w,
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
                width: w,
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
