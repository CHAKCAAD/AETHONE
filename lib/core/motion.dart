/// Motion tokens — report §10 / table 15 → v4.25 «انیمیشن‌های اختصاصی».
///
/// HISTORY: the five ANIMATION SETTINGS styles began life as duration
/// multipliers + curve swaps — the FEEL was identical, only the speed
/// changed. The owner's v4.25 round («برای هر حالت انیمیشن خودش رو ایجاد
/// کن و به همه بخش ها بده. انیمیشن های خلاقانه و جدید استفاده کن»)
/// promotes every style to a full RECIPE — its own choreography for the
/// page routes, the block cascades, the pattern drift, the breathing halo
/// and the small controls — so each mode is a distinct personality:
///
///  استاندارد SILK   — the owner-approved baseline: a clean fade with a
///                     22 px rise, blocks cascade on their own timeline
///                     slice; the page fades in while sliding up 3%.
///  نرم       TIDE   — long, flowing, "underwater": blocks drift up 34 px
///                     while they materialize out of a 96.5% zoom, the
///                     route cross-dissolves through a soft zoom (no
///                     slide), the side patterns drift slower and wider,
///                     everything breathes deeper.
///  پویا      SPRING — snappy and alive: blocks POP from 90% scale with an
///                     easeOutBack overshoot, the route springs up from
///                     5.5% below, the patterns bob quickly, the controls
///                     snap in 140 ms.
///  حداقلی    BLINK  — discreet: pure quick fades, no travel at all.
///  خاموش     —      — the master kill-switch state: nothing non-essential
///                     moves, changes land instantly (colour/text status
///                     feedback is KEPT — the accessibility requirement).
///
/// Hard rules (prompt §11.7 + report §10) stay:
///  * animation REFLECTS state, never fakes it;
///  * real operations are never delayed by animations;
///  * no external animation packages — Flutter built-ins only.
library;

import 'package:flutter/widgets.dart';

import 'design_tokens.dart';

/// The five user-selectable animation styles (prompt §11.8).
enum MotionStyle {
  /// SILK — ×1.0, easeInOutCubic, the owner-approved baseline.
  standard,

  /// TIDE — ×1.5, easeOutQuint: softer, slower, wider; a zoom-dissolve
  /// page personality and a deep pattern drift.
  smooth,

  /// SPRING — ×0.8, easeOutBack: bolder; everything pops with a slight
  /// overshoot.
  dynamic,

  /// BLINK — ×0.4, easeOut: minimal; pure quick fades, no travel.
  minimal,

  /// No non-essential animation; changes apply instantly. Color/text
  /// status feedback is KEPT (accessibility requirement).
  off,
}

/// The per-style choreography (v4.25). One immutable recipe per style —
/// every animated surface in the app reads ITS OWN fields from here, so
/// a style is a personality, not a speed knob.
final class MotionRecipe {
  const MotionRecipe({
    required this.stateCurve,
    required this.blockRise,
    required this.blockScaleFrom,
    required this.blockCurve,
    required this.staggerStep,
    required this.staggerSpan,
    required this.pageSlide,
    required this.pageScaleFrom,
    required this.pageFadeCurve,
    required this.pageMoveCurve,
    required this.swayPeriodMs,
    required this.swayAmpRef,
    required this.swayBreathFloor,
    required this.controlMs,
    required this.controlCurve,
    required this.heroBreathMs,
    required this.heroBreathAmp,
    required this.rippleMs,
  });

  /// State transitions (logo rotation, colour changes, button rise).
  final Curve stateCurve;

  /// The block-cascade entrance: how many ref px a block rises while it
  /// fades in (0 = no travel — the BLINK personality).
  final double blockRise;

  /// The cascade's starting scale (1 = no zoom — SILK/BLINK; <1 = the
  /// block materializes out of a zoom — TIDE 0.965 / SPRING 0.90).
  final double blockScaleFrom;

  /// The cascade curve (SPRING overshoots on purpose).
  final Curve blockCurve;

  /// Route-timeline fraction between one block's start and the next's.
  final double staggerStep;

  /// Route-timeline slice each block animates over (bigger = more
  /// overlap between neighbours = a more flowing cascade).
  final double staggerSpan;

  /// The page-route entry slide (Offset fraction; zero = no slide).
  final Offset pageSlide;

  /// The page-route entry zoom (1 = none; TIDE 0.965 / SPRING 0.975).
  final double pageScaleFrom;

  /// The route's fade + move curves (split so SILK keeps its exactly
  /// owner-approved pairing: fade easeOut · move easeOutCubic).
  final Curve pageFadeCurve;
  final Curve pageMoveCurve;

  /// The background-pattern drift: period, amplitude (ref px) and the
  /// luminance-breath floor while the patterns are alive.
  final int swayPeriodMs;
  final double swayAmpRef;
  final double swayBreathFloor;

  /// Small controls (setting pills, toggles, flag strips).
  final int controlMs;
  final Curve controlCurve;

  /// The connected hero's breathing pulse (period + amplitude).
  final int heroBreathMs;
  final double heroBreathAmp;

  /// The aurora halo's ripple cycle.
  final int rippleMs;
}

extension MotionStyleX on MotionStyle {
  double get durationMultiplier => switch (this) {
        MotionStyle.standard => 1.0,
        MotionStyle.smooth => 1.5,
        MotionStyle.dynamic => 0.8,
        MotionStyle.minimal => 0.4,
        MotionStyle.off => 0.0,
      };

  /// The state-change curve (kept from the pre-recipe era — the hero
  /// rotation, the pill crossfades and the colour tweens read this).
  Curve get curve => switch (this) {
        MotionStyle.standard => Curves.easeInOutCubic,
        MotionStyle.smooth => Curves.easeOutQuint,
        MotionStyle.dynamic => Curves.easeOutBack,
        MotionStyle.minimal => Curves.easeOut,
        MotionStyle.off => Curves.linear,
      };

  /// The style's full choreography (v4.25).
  MotionRecipe get recipe => switch (this) {
        // SILK — the owner-approved baseline, verbatim from the v4.17
        // cascade + the v4.17 route (fade easeOut · slide 3% easeOutCubic)
        // + the v4.17 pattern sway (6.5 s ±7 px) + the v4.12 breathing
        // hero (2.6 s ±2%) + the v4.15 aurora (3.9 s ripples).
        MotionStyle.standard => const MotionRecipe(
          stateCurve: Curves.easeInOutCubic,
          blockRise: 22,
          blockScaleFrom: 1.0,
          blockCurve: Curves.easeOutCubic,
          staggerStep: 0.075,
          staggerSpan: 0.55,
          pageSlide: Offset(0, 0.03),
          pageScaleFrom: 1.0,
          pageFadeCurve: Curves.easeOut,
          pageMoveCurve: Curves.easeOutCubic,
          swayPeriodMs: 6500,
          swayAmpRef: 7,
          swayBreathFloor: 0.88,
          controlMs: 200,
          controlCurve: Curves.easeOut,
          heroBreathMs: 2600,
          heroBreathAmp: 0.02,
          rippleMs: 3900,
        ),

        // TIDE — long, flowing, underwater: the blocks drift up 34 px out
        // of a soft zoom, neighbours overlap more (0.09/0.62), the route
        // cross-dissolves through a 96.5% zoom with NO slide, the
        // patterns drift 9.5 s ±11 px with a deeper breath, the halo
        // ripples slower and the hero breathes deeper.
        MotionStyle.smooth => const MotionRecipe(
          stateCurve: Curves.easeOutQuint,
          blockRise: 34,
          blockScaleFrom: 0.965,
          blockCurve: Curves.easeOutQuint,
          staggerStep: 0.09,
          staggerSpan: 0.62,
          pageSlide: Offset.zero,
          pageScaleFrom: 0.965,
          pageFadeCurve: Curves.easeOut,
          pageMoveCurve: Curves.easeOutQuint,
          swayPeriodMs: 9500,
          swayAmpRef: 11,
          swayBreathFloor: 0.80,
          controlMs: 320,
          controlCurve: Curves.easeOutQuint,
          heroBreathMs: 3400,
          heroBreathAmp: 0.03,
          rippleMs: 5200,
        ),

        // SPRING — snappy and alive: the blocks pop from 90% with an
        // easeOutBack overshoot and a short 12 px rise, the cascade
        // staggers quicker (0.05/0.45), the route springs up from 5.5%
        // below through a 97.5% zoom, the patterns bob at 4.2 s ±9 px,
        // the controls snap in 140 ms.
        MotionStyle.dynamic => const MotionRecipe(
          stateCurve: Curves.easeOutBack,
          blockRise: 12,
          blockScaleFrom: 0.90,
          blockCurve: Curves.easeOutBack,
          staggerStep: 0.05,
          staggerSpan: 0.45,
          pageSlide: Offset(0, 0.055),
          pageScaleFrom: 0.975,
          pageFadeCurve: Curves.easeOut,
          pageMoveCurve: Curves.easeOutBack,
          swayPeriodMs: 4200,
          swayAmpRef: 9,
          swayBreathFloor: 0.86,
          controlMs: 140,
          controlCurve: Curves.easeOutBack,
          heroBreathMs: 2000,
          heroBreathAmp: 0.025,
          rippleMs: 2800,
        ),

        // BLINK — discreet: pure quick fades, no rise, no zoom, a tight
        // stagger, a pure-fade route, a barely-there pattern sway.
        MotionStyle.minimal => const MotionRecipe(
          stateCurve: Curves.easeOut,
          blockRise: 0,
          blockScaleFrom: 1.0,
          blockCurve: Curves.easeOut,
          staggerStep: 0.03,
          staggerSpan: 0.30,
          pageSlide: Offset.zero,
          pageScaleFrom: 1.0,
          pageFadeCurve: Curves.easeOut,
          pageMoveCurve: Curves.linear,
          swayPeriodMs: 6500,
          swayAmpRef: 3,
          swayBreathFloor: 0.94,
          controlMs: 90,
          controlCurve: Curves.easeOut,
          heroBreathMs: 2600,
          heroBreathAmp: 0.008,
          rippleMs: 3900,
        ),

        // The kill-switch state: identity everywhere, zero durations.
        MotionStyle.off => const MotionRecipe(
          stateCurve: Curves.linear,
          blockRise: 0,
          blockScaleFrom: 1.0,
          blockCurve: Curves.linear,
          staggerStep: 0,
          staggerSpan: 0,
          pageSlide: Offset.zero,
          pageScaleFrom: 1.0,
          pageFadeCurve: Curves.linear,
          pageMoveCurve: Curves.linear,
          swayPeriodMs: 6500,
          swayAmpRef: 0,
          swayBreathFloor: 1.0,
          controlMs: 0,
          controlCurve: Curves.linear,
          heroBreathMs: 2600,
          heroBreathAmp: 0,
          rippleMs: 3900,
        ),
      };
}

/// Clamp for the OS "reduce motion" accessibility setting (top-level so any
/// Dart version resolves it identically).
MotionStyle clampForReduceMotion(MotionStyle style) =>
    style == MotionStyle.dynamic || style == MotionStyle.smooth
        ? MotionStyle.minimal
        : style;

/// Base durations (ms, before style scaling).
abstract final class MotionDurations {
  /// Touch feedback (scale/opacity) — report: max ~120ms.
  static const int touch = 120;

  /// Small component transitions (pill text/icon swap, toggle).
  static const int quick = 200;

  /// State transitions (logo rotation, color changes, button rise).
  static const int state = 400;

  /// Sheet / page transitions.
  static const int page = 320;
}

/// Scales [baseMs] by the style multiplier; OFF yields [Duration.zero].
Duration motionDuration(MotionStyle style, int baseMs) => Duration(
      milliseconds: (baseMs * style.durationMultiplier).round(),
    );

/// The block-entrance cascade every staggered page shares (v4.25 — the
/// v4.17/v4.22 `subpageEnter`/`_enter` recipes, generalized per style).
/// Each block rides its own slice of the ROUTE timeline — the entrance
/// cascades block-by-block and the SAME slices retrace on pop, so the exit
/// folds the page away gently. With no route (bare-harness pumps) or with
/// the OFF style the child renders untouched.
Widget motionCascade(
  BuildContext context,
  MotionStyle style,
  int block,
  Widget child,
) {
  if (style == MotionStyle.off) return child;
  final anim = ModalRoute.of(context)?.animation;
  if (anim == null) return child;
  final r = style.recipe;
  return AnimatedBuilder(
    animation: anim,
    builder: (context, _) {
      final t = anim.value;
      final start = (block * r.staggerStep).clamp(0.0, 0.45);
      final bt =
          r.blockCurve.transform(Interval(start, start + r.staggerSpan).transform(t));
      if (bt >= 0.999) return child;
      final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
      Widget node = child;
      if (r.blockRise > 0) {
        node = Transform.translate(
          offset: Offset(0, (1 - bt) * r.blockRise * s),
          child: node,
        );
      }
      if (r.blockScaleFrom < 1) {
        node = Transform.scale(
          scale: r.blockScaleFrom + (1 - r.blockScaleFrom) * bt,
          child: node,
        );
      }
      return Opacity(opacity: bt, child: node);
    },
  );
}

/// The app's ONE page-route factory (v4.25): every pushed page enters with
/// its style's own personality —
///   SILK   fade + 3% rise      · TIDE   zoom-dissolve (96.5%)
///   SPRING 5.5% spring + zoom  · BLINK  pure fade
///   OFF    an instant cut (Duration.zero).
PageRouteBuilder<T> aethPageRoute<T>({
  required MotionStyle style,
  required WidgetBuilder builder,
}) {
  final r = style.recipe;
  return PageRouteBuilder<T>(
    transitionDuration: motionDuration(style, 380),
    reverseTransitionDuration: motionDuration(style, 320),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      final fade = CurvedAnimation(parent: animation, curve: r.pageFadeCurve);
      final move = CurvedAnimation(parent: animation, curve: r.pageMoveCurve);
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: r.pageSlide,
            end: Offset.zero,
          ).animate(move),
          child: ScaleTransition(
            scale: Tween<double>(begin: r.pageScaleFrom, end: 1).animate(move),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Ambient motion style for the SMALL controls (setting pills, toggles,
/// flag strips) — provided by the pages ([SubPageFrame] /
/// [SettingsScreen]), read by settings_controls so every control's
/// AnimatedContainer timing follows the selected style without threading a
/// style parameter through every constructor. Bare harnesses (widget
/// tests that pump controls directly) fall back to SILK.
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    required this.style,
    required super.child,
  });

  final MotionStyle style;

  static MotionStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.style ??
      MotionStyle.standard;

  @override
  bool updateShouldNotify(MotionScope oldWidget) => oldWidget.style != style;
}
