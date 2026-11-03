/// Edge background patterns — the four committed artworks (red when
/// disconnected, green when connected), shipped as pre-rendered PNGs
/// (v4.10: the SVG sources carry feGaussianBlur, which flutter_svg cannot
/// rasterize — on device the blurred edge circles rendered as SOLID blobs,
/// the single worst visual defect of the first preview build).
///
/// The canvases render at [AethGeometry.patternScale] (0.6) of the screen
/// width (v4.12 — owner: «پترن‌های چپ و راست رو ۴۰ درصد کوچک‌تر کن»). The
/// placement is PER-SCREEN since v4.17 ([PatternStage]):
///
///  * [PatternStage.settings] — the v4.12/v4.15 composition: the LEFT art
///    is GLUED to the screen bottom (owner settings round #4 + v4.17
///    round #3: «پترن پس زمینه سمت چپ رو به پایین بچسبون» — the art's end
///    runs ~13 ref px BELOW the glass so no cut edge is ever visible,
///    anchor [AethGeometry.patternLeftAnchorBottom]); the RIGHT art hangs
///    from the screen top (anchor [AethGeometry.patternRightAnchorTop]).
///
///  * [PatternStage.home] — v4.17 owner round: «پترن سمت چپ رو بیار بالا تر
///    در حدی که حدود ۱۰٪ پایین‌تر از وسط صفحه باشه» + «پترن سمت راست رو
///    بیار پایین تر در حدی که حدود ۱۰٪ بالاتر از وسط صفحه باشه». The ART
///    (not the canvas) is placed with the measured art bounds
///    ([AethGeometry.patternLeftArtTopRow] etc.): the LEFT art is centred
///    at 60% of the screen height (10% below the middle), the RIGHT art's
///    bottom edge lands at 40% (10% above the middle) — the diagonal frame
///    the reference screens show, computed from the LIVE height so it holds
///    on every device.
///
/// The color change is animated as a crossfade between the two artwork
/// variants (owner: «با انیمیشن به رنگ سبز تغییر پیدا میکنند»).
///
/// While [active] (the engine walking OR the tunnel up — home only) the
/// canvases come alive: a slow 6.5 s VERTICAL drift (±7 ref px,
/// counter-phased left↔right) plus a gentle luminance breath (opacity
/// 0.88 ↔ 1.00). v4.17 — owner home round #4: «انیمیشن پترن ها ... باعث
/// میشه از صفحه بیرون بزنند. انیمیشن رو عوض کن و یا حالتش رو بالا به پایین
/// کن (در حال حاضر به چپ و راست میرن)» — the v4.15 HORIZONTAL sway is
/// turned to the vertical axis: with the v4.17 floating anchors neither art
/// touches a screen edge, so an up-down drift can never push ink off-screen
/// (the old horizontal sway slid the edge-hugging art out of view). The
/// settings page keeps [active] = false (static, as before). MotionStyle.off
/// keeps them static (accessibility clamp).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

/// Which composition the patterns follow (v4.17).
enum PatternStage { home, settings }

class PatternSides extends StatefulWidget {
  const PatternSides({
    super.key,
    required this.connected,
    required this.style,
    this.active = false,
    this.stage = PatternStage.home,
  });

  final bool connected;
  final MotionStyle style;

  /// v4.15 #5 — true while the patterns should be alive (engine walking or
  /// connected). The settings page keeps the default `false` (static, as
  /// before — the owner asked for the motion on the HOME screen).
  final bool active;

  /// v4.17 — home floats the arts around the middle band; settings keeps
  /// the v4.12/v4.15 edge-glued composition.
  final PatternStage stage;

  @override
  State<PatternSides> createState() => _PatternSidesState();
}

class _PatternSidesState extends State<PatternSides>
    with SingleTickerProviderStateMixin {
  static const Duration _swayPeriod = Duration(milliseconds: 6500);
  static const double _swayAmpY = 7; // ref px
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
    if (old.active != widget.active ||
        old.style != widget.style ||
        old.stage != widget.stage) {
      _sync();
    }
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

        // Canvases at 60% of the screen width (v4.12, art 40% smaller).
        final leftW = w * AethGeometry.patternScale;
        final leftH = leftW * AethGeometry.patternLeftAspect;
        final rightW = w * AethGeometry.patternScale;
        final rightH = rightW * AethGeometry.patternRightAspect;

        final double leftTop;
        final double rightTop;
        switch (widget.stage) {
          case PatternStage.settings:
            // v4.12/v4.15 composition: left art glued to the screen bottom
            // (its end runs below the glass — never a visible cut), right
            // art hanging from the top.
            leftTop = h - leftH * AethGeometry.patternLeftAnchorBottom;
            rightTop = -rightH * AethGeometry.patternRightAnchorTop;
          case PatternStage.home:
            // v4.17 — the ART bands around the middle, from the LIVE height:
            //   LEFT  : art centred at 0.60h (10% below the middle).
            //   RIGHT : art bottom edge at 0.40h (10% above the middle).
            const leftArtMidRow = AethGeometry.patternLeftArtTopRow +
                AethGeometry.patternLeftArtRows / 2;
            leftTop = 0.60 * h - leftArtMidRow * leftH / 1232;
            rightTop = 0.40 * h -
                AethGeometry.patternRightArtBottomRow * rightH / 1178;
        }

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
                  ampY: _swayAmpY * s,
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
                  ampY: _swayAmpY * s,
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

/// Applies the v4.17 sway (dy — VERTICAL, owner home round #4) + luminance
/// breath to one pattern canvas. t = 0 ⇒ identity, so a stopped controller
/// renders the static pose.
class _Alive extends StatelessWidget {
  const _Alive({
    required this.controller,
    required this.phase,
    required this.ampY,
    required this.breathFloor,
    required this.child,
  });

  final AnimationController controller;
  final double phase;
  final double ampY;
  final double breathFloor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, kid) {
        final t = controller.value * 2 * math.pi + phase;
        final dy = math.sin(t) * ampY;
        final glow = breathFloor + (1 - breathFloor) * (0.5 - 0.5 * math.cos(t));
        return Transform.translate(
          offset: Offset(0, dy),
          child: Opacity(opacity: glow, child: kid),
        );
      },
      child: child,
    );
  }
}
