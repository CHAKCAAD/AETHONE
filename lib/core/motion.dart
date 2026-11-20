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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.connectMarchMs = 1200,
    this.connectSeekMs = 2200,
    this.connectHoldMs = 2200,
    this.celebrationMs = 950,
    this.shakeAmpRef = 8,
    this.pressScale = 0.96,
    this.pressStiffness = 350,
    this.pressDamping = 26,
    this.sectionResizeMs = 260,
    this.dialMs = 260,
    this.dialCurve = Curves.easeOutCubic,
    // ---- v8a (owner round 18) — the four animation decrees' tokens
    // (ADDITIVE, same rule as the v1.0.2 block above). ----
    this.shimmerMs = 3200,
    this.hyperTextMs = 480,
    this.circleSelectMs = 380,
    this.circleSelectGrow = 0.10,
    this.circleSelectPush = 8,
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

  // ---- v1.0.2 motion-overhaul additions (all ADDITIVE — every existing
  // field and value above is untouched, so the v4.25 tests and the owner's
  // approved baselines keep passing verbatim). ----

  /// The CONNECTING state's marching-dash ring period (ms). The dashes
  /// march around the connect core — directional energy, one full loop
  /// per period (ZedSecure's 900ms marching-wave principle, retimed per
  /// personality).
  final int connectMarchMs;

  /// The RECONNECTING state's double-pulse "seek" period (ms): two quick
  /// pulses + a rest — a rhythm that is deliberately DISTINCT from
  /// [connectMarchMs] so the two walking states never share an animation.
  final int connectSeekMs;

  /// The WAITING-FOR-PERMISSIONS state's suspended-breath period (ms): the
  /// ring freezes and its opacity breathes slowly — "held", not marching.
  final int connectHoldMs;

  /// The one-shot celebration when the connecting→connected EDGE lands
  /// (ms; 0 = never celebrate). Fired once on the edge, never in the
  /// steady state.
  final int celebrationMs;

  /// The FAILED state's decaying-shake amplitude (ref px; 0 = no shake).
  /// The offset profile is [1, -0.8, 0.6, -0.3, 0.15, 0] × this amplitude,
  /// ~55ms per step (≈330ms total).
  final double shakeAmpRef;

  /// How far a pressable control squashes under the finger (1 = none).
  final double pressScale;

  /// The press-release spring (Flutter [SpringSimulation] stiffness and
  /// damping units). Bouncier personalities get lower damping so the
  /// return visibly overshoots a hair.
  final double pressStiffness;
  final double pressDamping;

  /// AnimatedSize for conditional sections (settings sub-pages expanding
  /// expert panels etc.) — ms; 0 = instant.
  final int sectionResizeMs;

  /// Gauge/number transitions (speed-test needle, value swaps) — ms.
  final int dialMs;

  /// The curve that shapes [dialMs] transitions.
  final Curve dialCurve;

  // ---- v8a (owner round 18) — the four animation decrees. ----

  /// The CONNECTED shimmer: one full lap of the traveling light along
  /// the connect button's own edge (the flutterfx «button-shimmer»
  /// technique, rebuilt natively). 0 = the style keeps the edge still
  /// (OFF — the static faint edge is status feedback, not motion).
  final int shimmerMs;

  /// The HYPER TEXT decode (the flutterfx «fx_10_hyper_text» technique):
  /// how long a changed text takes to resolve out of its scramble (the
  /// location header's country name + ping readout). 0 = instant (OFF).
  final int hyperTextMs;

  /// The CIRCLE SELECTOR impulse (the flutterfx «circles_selector»
  /// technique): the selected item springs up ([circleSelectGrow] over
  /// its resting size) and pushes its siblings aside ([circleSelectPush]
  /// ref px at falloff distance 1) for [circleSelectMs], then everything
  /// settles back to the pixel-true resting geometry. 0/0/0 = instant,
  /// no travel (OFF).
  final int circleSelectMs;
  final double circleSelectGrow;
  final double circleSelectPush;
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
          // v1.0.2 connect-control choreography: SILK = the defaults (a
          // 1.2 s march, a 2.2 s seek, a measured celebration).
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
          // v1.0.2 — TIDE's connect choreography: everything slower, wider
          // and softer; the press is a deep cushioned squash.
          connectMarchMs: 1800,
          connectSeekMs: 2800,
          connectHoldMs: 2600,
          celebrationMs: 1200,
          shakeAmpRef: 10,
          pressScale: 0.965,
          pressStiffness: 180,
          pressDamping: 30,
          sectionResizeMs: 340,
          dialMs: 380,
          dialCurve: Curves.easeOutQuint,
          // v8a — TIDE's decree tempos: a slow shimmer lap, a long decode,
          // a wide soft push.
          shimmerMs: 4800,
          hyperTextMs: 720,
          circleSelectMs: 560,
          circleSelectGrow: 0.08,
          circleSelectPush: 10,
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
          // v1.0.2 — SPRING's connect choreography: a fast march, a tight
          // seek, a punchy celebration and a visibly bouncy press.
          connectMarchMs: 800,
          connectSeekMs: 1600,
          connectHoldMs: 1800,
          celebrationMs: 800,
          shakeAmpRef: 12,
          pressScale: 0.94,
          pressStiffness: 420,
          pressDamping: 17,
          sectionResizeMs: 200,
          dialMs: 180,
          dialCurve: Curves.easeOutBack,
          // v8a — SPRING's decree tempos: a quick lap, a fast decode, a
          // punchy grow with a tight push.
          shimmerMs: 2400,
          hyperTextMs: 384,
          circleSelectMs: 320,
          circleSelectGrow: 0.12,
          circleSelectPush: 7,
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
          // v1.0.2 — BLINK's connect choreography: quick and discreet — a
          // brisk march, the smallest shake, a feather press.
          connectMarchMs: 900,
          connectSeekMs: 1400,
          connectHoldMs: 2000,
          celebrationMs: 600,
          shakeAmpRef: 4,
          pressScale: 0.97,
          pressStiffness: 500,
          pressDamping: 34,
          sectionResizeMs: 120,
          dialMs: 120,
          dialCurve: Curves.easeOut,
          // v8a — BLINK's decree tempos: a discreet lap, a brisk decode,
          // a hair of grow and a whisper of push.
          shimmerMs: 3200,
          hyperTextMs: 192,
          circleSelectMs: 180,
          circleSelectGrow: 0.04,
          circleSelectPush: 3,
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
          // v1.0.2 — the kill-switch identity: no march, no seek, no
          // celebration, no shake, no press squash, instant resizes.
          connectMarchMs: 0,
          connectSeekMs: 0,
          connectHoldMs: 0,
          celebrationMs: 0,
          shakeAmpRef: 0,
          pressScale: 1.0,
          pressStiffness: 0,
          pressDamping: 0,
          sectionResizeMs: 0,
          dialMs: 0,
          dialCurve: Curves.linear,
          // v8a — the kill-switch identity: the edge stays still (the
          // static border is status feedback, not motion), text lands
          // instantly, nothing ever travels.
          shimmerMs: 0,
          hyperTextMs: 0,
          circleSelectMs: 0,
          circleSelectGrow: 0,
          circleSelectPush: 0,
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
///
/// v1.0.2 — [flavor] differentiates the entrance by the block's SEMANTICS
/// (a protocol card pops a little, a stat card stays calm, a router row
/// slides in from the leading edge RTL-aware, …). The default keeps the
/// exact v4.25 choreography, so every existing call site is untouched.
Widget motionCascade(
  BuildContext context,
  MotionStyle style,
  int block,
  Widget child, {
  EntranceFlavor flavor = EntranceFlavor.standard,
}) {
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
      // The flavor's per-math tweaks (v1.0.2). `rise`/`scaleFrom` override
      // the recipe's own values; `slideDx` (ref px) adds a DIRECTIONAL
      // horizontal entrance for row-like cards.
      final rise = flavor.rise(r.blockRise);
      final scaleFrom = flavor.scaleFrom(r.blockScaleFrom);
      final slideDx = flavor.slideDxRef;
      Widget node = child;
      if (slideDx != 0) {
        node = Transform.translate(
          offset: Offset(
            -horizontalSign(context) * (1 - bt) * slideDx * s,
            0,
          ),
          child: node,
        );
      }
      if (rise > 0) {
        node = Transform.translate(
          offset: Offset(0, (1 - bt) * rise * s),
          child: node,
        );
      }
      if (scaleFrom < 1) {
        node = Transform.scale(
          scale: scaleFrom + (1 - scaleFrom) * bt,
          child: node,
        );
      }
      return Opacity(opacity: bt, child: node);
    },
  );
}

/// v1.0.2 — the per-card-type entrance personalities. The STYLE recipe
/// stays the choreography's backbone (its curve, stagger and tempo); the
/// flavor bends two numbers so a card's MEANING reads in its entrance:
/// action cards reach out, data cards stay calm, list rows arrive from the
/// reading direction, status surfaces just fade.
enum EntranceFlavor {
  /// The recipe verbatim (the v4.25 baseline).
  standard,

  /// Protocol / primary action cards: always a slight zoom (≤3%) and a
  /// touch more rise — the card "reaches" for the finger.
  action,

  /// Info cards: rise only — no zoom, ever.
  info,

  /// Stat / data cards: calm — less rise, no zoom; numbers never bounce.
  stat,

  /// Status pills / cards: a pure fade — state changes, not geometry.
  status,

  /// Router / server rows: slide in from the leading edge (RTL-aware).
  route,

  /// The speed-test gauge group: a zoom-dissolve like TIDE's route.
  gauge,

  /// Onboarding tiles: the biggest rise — the wizard's playful step.
  onboarding;

  double rise(double recipeRise) => switch (this) {
        EntranceFlavor.stat => recipeRise * 0.6,
        EntranceFlavor.status => 0,
        EntranceFlavor.onboarding => recipeRise * 1.3 + 6,
        EntranceFlavor.route => 0,
        _ => recipeRise,
      };

  double scaleFrom(double recipeScaleFrom) => switch (this) {
        EntranceFlavor.action =>
          recipeScaleFrom < 1 ? recipeScaleFrom : 0.97,
        EntranceFlavor.info => 1.0,
        EntranceFlavor.stat => 1.0,
        EntranceFlavor.status => 1.0,
        EntranceFlavor.gauge =>
          recipeScaleFrom < 1 ? recipeScaleFrom : 0.965,
        EntranceFlavor.route => 1.0,
        _ => recipeScaleFrom,
      };

  double get slideDxRef => switch (this) {
        EntranceFlavor.route => 26,
        _ => 0,
      };
}

/// v1.0.2 — the horizontal reading-direction sign: +1 under LTR, −1 under
/// RTL. Multiplying a westward (leftward) design offset by this renders the
/// mirrored motion under Persian without any hardcoded direction.
double horizontalSign(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl ? -1 : 1;

/// v1.0.2 — the CONTENT direction of the app's own locale (fa ⇒ RTL;
/// en/ru/zh/tk ⇒ LTR). The settings rows and content columns follow the
/// LANGUAGE, not whatever LTR-locked geometry frame they sit in — the old
/// hardcoded `Directionality(rtl)` locks mirrored the content under every
/// non-Persian locale too (the audit's RTL finding). Reads the MATERIAL
/// locale (what the app actually renders), never a guess.
TextDirection appContentDirection(BuildContext context) {
  final l = Localizations.maybeLocaleOf(context)?.languageCode;
  return switch (l) {
    'fa' || 'ar' || 'he' || 'ur' => TextDirection.rtl,
    _ => TextDirection.ltr,
  };
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
      // `.drive(CurveTween(...))` (not `CurvedAnimation`) — the driven
      // animation adds NO listener to the route's controller, so building
      // per animation tick cannot accumulate listeners on it.
      final fade = animation.drive(CurveTween(curve: r.pageFadeCurve));
      final move = animation.drive(CurveTween(curve: r.pageMoveCurve));
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

/// v1.0.2 — the app's haptic vocabulary. Exactly THREE words, mirroring the
/// two-word discipline of the reference study (a heavy word only when a
/// REAL state change commits, a light word for previews/selection) plus the
/// owner's already-approved connected pulse:
///
///  * [tap]      — micro: a press lands, a pill/flag is picked, a drag
///                 starts. The "the surface felt you" word.
///  * [commit]   — a real state change landed (the existing owner-approved
///                 medium pulse on connection lives on in the store).
///  * [failure]  — the tunnel failed; the heaviest word the platform offers.
///
/// Never called from an animation callback — only from gesture handlers and
/// store state edges, so haptics can never delay or fake an operation.
abstract final class AethHaptics {
  /// Micro feedback (selection-grade).
  static void tap() => HapticFeedback.selectionClick();

  /// A real state change committed.
  static void commit() => HapticFeedback.mediumImpact();

  /// Something failed.
  static void failure() => HapticFeedback.heavyImpact();
}

/// v1.0.2 — the app's dialog/sheet transition, style-scaled: a fade paired
/// with a soft 0.94 → 1.0 zoom (the same asymmetric-fade language as the
/// page routes; OFF = the instant cut). `barrierColor` stays the caller's
/// own choice (the brand's black54).
Widget aethDialogTransition(
  MotionStyle style,
  Animation<double> animation,
  Widget child,
) {
  if (style == MotionStyle.off) return child;
  return FadeTransition(
    opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
    child: ScaleTransition(
      scale: animation.drive(
        Tween<double>(begin: 0.94, end: 1.0)
            .chain(CurveTween(curve: style.recipe.stateCurve)),
      ),
      child: child,
    ),
  );
}

/// v1.0.2 — [showDialog] with the app's own style-aware transition (the
/// Material black54 barrier kept; the content zoom-fades with the style's
/// own curve — OFF renders the content instantly). Rides
/// [showGeneralDialog] so the transition itself is ours, not Material's.
Future<T?> showAethDialog<T>({
  required BuildContext context,
  required MotionStyle style,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x8A000000), // Colors.black54
    transitionDuration: motionDuration(style, MotionDurations.page),
    transitionBuilder: (context, animation, _, child) =>
        aethDialogTransition(style, animation, child),
    pageBuilder: (context, _, _) => builder(context),
  );
}
