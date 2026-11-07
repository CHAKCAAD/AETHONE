/// Edge background patterns — the four committed artworks (red when
/// disconnected, green when connected), shipped as pre-rendered PNGs
/// (v4.10: the SVG sources carry feGaussianBlur, which flutter_svg cannot
/// rasterize — on device the blurred edge circles rendered as SOLID blobs,
/// the single worst visual defect of the first preview build).
///
/// The canvases render at [AethGeometry.patternScale] (0.6) of the screen
/// width (v4.12 — owner: «پترن‌های چپ و راست رو ۴۰ درصد کوچک‌تر کن»).
///
/// v4.25 — ONE composition for EVERY page (the owner's twin decrees:
/// «از پترن های صفحه اصلی برای سایر صفحات مثل انتخاب پروتکل و تنطیمات
/// استفاده کن دقیقا همونا با همون مکان» and «مکانش دقیقا مثل صفحه اصلی
/// باشه»): the v4.17 per-screen [PatternStage] split is RETIRED — the old
/// edge-glued settings variant could still ship in a stale build and read
/// as "wrong place"; now there is a single code path and it cannot diverge.
/// The ART (not the canvas) is placed with the measured art bounds
/// ([AethGeometry.patternLeftArtTopRow] etc.): the LEFT art is centred at
/// 60% of the screen height (10% below the middle — owner v4.17: «پترن سمت
/// چپ رو بیار بالا تر در حدی که حدود ۱۰٪ پایین‌تر از وسط صفحه باشه»),
/// the RIGHT art's bottom edge lands at 40% (10% above the middle — «پترن
/// سمت راست رو بیار پایین تر در حدی که حدود ۱۰٪ بالاتر از وسط صفحه
/// باشه») — the diagonal frame the reference screens show, computed from
/// the LIVE height so it holds on every device.
///
/// The color change is animated as a crossfade between the two artwork
/// variants (owner: «با انیمیشن به رنگ سبز تغییر پیدا میکنند»).
///
/// v4.41 (owner round 17, item 6): «کمی فلش های رو به بالا پترن های کنار
/// تمام صفحات رو کوچیک تر کن دقت کن فقط فلش رو به بالا رو کوچیک کن، نه
/// حاله رنگی زیرش» — the up-arrow chevron STROKES of all four artworks
/// were re-scaled to 0.8 around their own centre (path + mask + gradient
/// coordinates, SVG sources in design/پترن پس زمینه صفحه اصلی), while the
/// blurred halo circle underneath kept its geometry untouched; the PNGs
/// were re-rendered from those sources.
///
/// While [active] (the engine walking OR the tunnel up — home only) the
/// canvases come alive: a slow VERTICAL drift plus a gentle luminance
/// breath — v4.25 makes the drift the STYLE'S OWN tempo ([MotionRecipe]):
/// SILK 6.5 s ±7 px · TIDE 9.5 s ±11 px (slow, wide, deep breath) ·
/// SPRING 4.2 s ±9 px (a quick bob) · BLINK ±3 px (barely there) ·
/// OFF static. v4.17 — the drift runs on the VERTICAL axis (owner home
/// round #4: the old horizontal sway slid the edge-hugging art out of
/// view; with the floating anchors neither art touches a screen edge, so
/// an up-down drift can never push ink off-screen). MotionStyle.off keeps
/// them static (accessibility clamp).
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

  /// True while the patterns should be alive (engine walking or
  /// connected). The settings pages keep the default `false` (static —
  /// the owner asked for the motion on the HOME screen; the speed-test
  /// page passes its own running state).
  final bool active;

  @override
  State<PatternSides> createState() => _PatternSidesState();
}

/// v4.35 (owner round 11, item 8: «حالت‌های سبز و قرمز پترن‌های صفحات رو
/// کمی پر رنگ‌تر و بزرگ‌تر کن») — the paint half of the decree: the pattern
/// PNGs are thin blurred strokes whose alpha mostly sits at 12–25 % (the
/// feGaussianBlur falloff of the source art), so on screen they read as a
/// dim ghost. This matrix multiplies every pixel's ALPHA by 1.6 (capped at
/// opaque by the rasterizer) — the soft halos lift toward their stroke
/// colors and the canvases grow 0.6 → 0.7 ([AethGeometry.patternScale],
/// the size half of the same decree). Hue/saturation untouched (the
/// strokes are already pure #1AD995 / #EA2323).
const List<double> _patternAlphaBoost = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1.6, 0, //
];

class _PatternSidesState extends State<PatternSides>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.style.recipe.swayPeriodMs),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PatternSides old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.style != widget.style) {
      // The recipe's tempo can differ between styles — retune the live
      // controller so a mid-session style change re-times the drift.
      _sway.duration =
          Duration(milliseconds: widget.style.recipe.swayPeriodMs);
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
    final recipe = widget.style.recipe;
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

        // v4.25 — the ONE composition (the v4.17 home placement, from the
        // LIVE height): the LEFT art centred at 0.60h (10% below the
        // middle), the RIGHT art's bottom edge at 0.40h (10% above it).
        const leftArtMidRow = AethGeometry.patternLeftArtTopRow +
            AethGeometry.patternLeftArtRows / 2;
        final leftTop = 0.60 * h - leftArtMidRow * leftH / 1232;
        final rightTop =
            0.40 * h - AethGeometry.patternRightArtBottomRow * rightH / 1178;

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
                  ampY: recipe.swayAmpRef * s,
                  breathFloor: recipe.swayBreathFloor,
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(
                        _patternAlphaBoost,
                      ),
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
              ),
              Positioned(
                right: 0,
                top: rightTop,
                width: rightW,
                height: rightH,
                child: _Alive(
                  controller: _sway,
                  phase: math.pi, // counter-phased to the left canvas
                  ampY: recipe.swayAmpRef * s,
                  breathFloor: recipe.swayBreathFloor,
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(
                        _patternAlphaBoost,
                      ),
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
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Applies the vertical drift + luminance breath to one pattern canvas,
/// timed by the style's own recipe. t = 0 ⇒ identity, so a stopped
/// controller renders the static pose.
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
