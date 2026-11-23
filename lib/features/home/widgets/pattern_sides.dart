/// Edge background patterns — the four committed artworks (red when
/// disconnected, green when connected), shipped as pre-rendered PNGs
/// (v4.10: the SVG sources carry feGaussianBlur, which flutter_svg cannot
/// rasterize — on device the blurred edge circles rendered as SOLID blobs,
/// the single worst visual defect of the first preview build).
///
/// The canvases render at [AethGeometry.patternScale] (0.6) of the screen
/// width (v4.12 — owner: «پترن‌های چپ و راست رو ۴۰ درصد کوچک‌تر کن»).
///
/// v5 («نمای 2», owner round 19) — the owner's NEW artwork pair (the ZIP
/// «پترن سمت چپ/راست» frames, connected + disconnected): the canvases are
/// 534×1593 (left) / 594×1848 (right) at 3×, rendered at their OWN design
/// scale (44 % / 49 % of the 402 reference width) hugging their screen
/// edges. Placement (template-matched on the committed mockups): the LEFT
/// art's centre rides at 27 % of the LIVE screen height, the RIGHT art's
/// ink ends at 48.5 % — both reflow on every device.
///
/// v5: the v4.35 alpha ×1.6 boost is RETIRED — the new art's strokes
/// composite at full design strength on the mockups (measured max ink
/// ≈102/255 vs the PNG's own ≈99 composite), so the canvases render
/// untouched.
///
/// v4.25 — ONE composition for EVERY page (the owner's twin decrees):
/// home, the settings main page and every sub-page share this single
/// placement; there is one code path and it cannot diverge.
///
/// The color change stays an animated crossfade between the two artwork
/// variants; while [active] (the engine walking OR the tunnel up — home
/// only) the canvases keep their vertical drift + luminance breath on the
/// style's own tempo ([MotionRecipe]).
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

        // v5 — the new canvases at their own design scale (×s, s =
        // width/402), hugging their screen edges like the mockups.
        final leftW = AethGeometry.patternLeftCanvasW * s;
        final leftH = leftW * AethGeometry.patternLeftAspect;
        final rightW = AethGeometry.patternRightCanvasW * s;
        final rightH = rightW * AethGeometry.patternRightAspect;

        // v5 placement (mockup-measured): the LEFT art's CENTRE at 27 % of
        // the LIVE height, the RIGHT art's ink BOTTOM at 48.5 %.
        const leftArtMidRow = AethGeometry.patternLeftArtTopRow +
            AethGeometry.patternLeftArtRows / 2;
        final leftTop = AethGeometry.patternLeftAnchor * h -
            leftArtMidRow * leftH / 1593;
        final rightTop = AethGeometry.patternRightAnchor * h -
            AethGeometry.patternRightArtBottomRow * rightH / 1848;

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
                    child: widget.connected
                        ? Image.asset(
                            key: const ValueKey('pattern-left-on'),
                            AppAssets.patternConnectedLeft,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          )
                        : _NightInk(
                            child: Image.asset(
                              key: const ValueKey('pattern-left-off'),
                              AppAssets.patternDisconnectedLeft,
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
                    child: widget.connected
                        ? Image.asset(
                            key: const ValueKey('pattern-right-on'),
                            AppAssets.patternConnectedRight,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          )
                        : _NightInk(
                            child: Image.asset(
                              key: const ValueKey('pattern-right-off'),
                              AppAssets.patternDisconnectedRight,
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

/// v5.1 (owner round 20) — the NIGHT-ink seam: the DISCONNECTED artwork
/// recolors to WHITE on the night theme (owner: «پترن های کناری در حالت
/// قطع اتصال دارک مود رنگشون باید سفید باشه»). The art is a pure
/// #110000 line drawing, so `srcIn` with the art's own ink is
/// byte-identical on the light theme and flips to white on night.
///
/// v5.2 (the round-21 theme-transition fix) — the ink is the PALETTE'S
/// OWN lerped member ([AethColors.patternInk]): the shell's 420 ms mode
/// tween recolors it IN LOCKSTEP with every other surface. The first
/// cut read the binary `AethThemeSync.light` slot through a second
/// `Tween<Color>` — which cannot lerp (Color implements no `+`/`-`/`*`),
/// so EVERY mid-transition rebuild threw and the whole mode switch
/// glitched (owner: «انیمیشن تغیر از حالت دارک مود به لایت مود و بلعکس
/// مشکل داره»). One constant tree — the wrapper never changes shape, so
/// the AnimatedSwitcher's crossfade element survives (the v4.15.1
/// lesson).
class _NightInk extends StatelessWidget {
  const _NightInk({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        AethColors.patternInk,
        BlendMode.srcIn,
      ),
      child: child,
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
