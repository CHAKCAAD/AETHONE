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
///     art bottom running off the screen bottom (v4.15 — see the
///     [AethGeometry.patternLeftAnchorBottom] measurement note: the art's
///     end now sits ~13 ref px BELOW the glass, so the cut edge is never
///     visible; owner settings round #4).
///   * RIGHT canvas (art hugs its right edge): pinned to the screen RIGHT
///     edge, art top on the screen top → the art band sits above mid-screen.
///
/// The color change is animated as a crossfade between the two artwork
/// variants (owner: «با انیمیشن به رنگ سبز تغییر پیدا میکنند»).
///
/// v4.15 — owner home round #5: «بعد از اتصال و حین اتصال پترن های پس زمینه
/// هم انیمیشن داشته باشند» — while [active] (the engine walking OR the
/// tunnel up) the canvases come alive: a slow 6.5 s horizontal sway
/// (±7 ref px, counter-phased left↔right) plus a gentle luminance breath
/// (opacity 0.88 ↔ 1.00). The sway is HORIZONTAL ONLY on purpose: a vertical
/// drift would slide the left art's bottom end back above the glass and
/// re-expose the cut the v4.15 anchor fix just buried. Deactivating eases
/// the canvases back to rest over 480 ms; MotionStyle.off keeps them static
/// (accessibility clamp).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

class PatternSides extends StatefulWidget {
  const PatternSides({
    super.key,
    required this.connected,
    required this.style,
    this.active = false,
  });

  final bool connected;
  final MotionStyle style;

  /// v4.15 #5 — true while the patterns should be alive (engine walking or
  /// connected). The settings page keeps the default `false` (static, as
  /// before — the owner asked for the motion on the HOME screen).
  final bool active;

  @override
  State<PatternSides> createState() => _PatternSidesState();
}

class _PatternSidesState extends State<PatternSides>
    with SingleTickerProviderStateMixin {
  static const Duration _swayPeriod = Duration(milliseconds: 6500);
  static const double _swayAmpX = 7; // ref px
  static const double _breathFloor = 0.88;

  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: _swayPeriod,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PatternSides old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.style != widget.style) _sync();
  }

  void _sync() {
    final run = widget.active && widget.style != MotionStyle.off;
    if (run) {
      if (!_sway.isAnimating) _sway.repeat();
    } else {
      _sway.stop();
      if (_sway.value != 0) {
        _sway.animateTo(
          0,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(widget.style, MotionDurations.state);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final s = w / AethGeometry.refWidth;

        // v4.12: canvases at 60% of the screen width (art 40% smaller).
        // Left canvas: pinned to the LEFT edge; art runs off the bottom.
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
                child: _Alive(
                  controller: _sway,
                  phase: 0.0,
                  ampX: _swayAmpX * s,
                  breathFloor: _breathFloor,
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: Image.asset(
                      key: ValueKey(
                        'pattern-left-${widget.connected ? 'on' : 'off'}',
                      ),
                      widget.connected
                          ? AppAssets.patternConnectedLeft
                          : AppAssets.patternDisconnectedLeft,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: rightTop,
                width: rightW,
                height: rightH,
                child: _Alive(
                  controller: _sway,
                  phase: math.pi, // counter-phased to the left canvas
                  ampX: _swayAmpX * s,
                  breathFloor: _breathFloor,
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: Image.asset(
                      key: ValueKey(
                        'pattern-right-${widget.connected ? 'on' : 'off'}',
                      ),
                      widget.connected
                          ? AppAssets.patternConnectedRight
                          : AppAssets.patternDisconnectedRight,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
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

/// Applies the v4.15 sway (dx) + luminance breath to one pattern canvas.
/// t = 0 ⇒ identity, so a stopped controller renders the v4.12 static pose.
class _Alive extends StatelessWidget {
  const _Alive({
    required this.controller,
    required this.phase,
    required this.ampX,
    required this.breathFloor,
    required this.child,
  });

  final AnimationController controller;
  final double phase;
  final double ampX;
  final double breathFloor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, kid) {
        final t = controller.value * 2 * math.pi + phase;
        final dx = math.sin(t) * ampX;
        final glow = breathFloor + (1 - breathFloor) * (0.5 - 0.5 * math.cos(t));
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Opacity(opacity: glow, child: kid),
        );
      },
      child: child,
    );
  }
}
