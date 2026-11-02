/// Motion tokens — report §10 / table 15. All durations and curves come from
/// one global source and scale with the five ANIMATION SETTINGS styles.
/// OS "Reduce motion" clamps the effective style to MINIMAL/OFF.
///
/// Hard rules (prompt §11.7 + report §10):
///  * animation REFLECTS state, never fakes it;
///  * real operations are never delayed by animations;
///  * no external animation packages — Flutter built-ins only.
library;

import 'package:flutter/animation.dart';

/// The five user-selectable animation styles (prompt §11.8).
enum AnimationStyle {
  /// ×1.0, easeInOutCubic — default.
  standard,

  /// ×1.5, easeOutQuint — softer, calmer.
  smooth,

  /// ×0.8, light spring (easeOutBack) — bolder but controlled.
  dynamic,

  /// ×0.4, easeOut — minimal.
  minimal,

  /// No non-essential animation; changes apply instantly. Color/text status
  /// feedback is KEPT (accessibility requirement).
  off,
}

extension AnimationStyleX on AnimationStyle {
  double get durationMultiplier => switch (this) {
        AnimationStyle.standard => 1.0,
        AnimationStyle.smooth => 1.5,
        AnimationStyle.dynamic => 0.8,
        AnimationStyle.minimal => 0.4,
        AnimationStyle.off => 0.0,
      };

  Curve get curve => switch (this) {
        AnimationStyle.standard => Curves.easeInOutCubic,
        AnimationStyle.smooth => Curves.easeOutQuint,
        AnimationStyle.dynamic => Curves.easeOutBack,
        AnimationStyle.minimal => Curves.easeOut,
        AnimationStyle.off => Curves.linear,
      };
}

/// Clamp for the OS "reduce motion" accessibility setting (top-level so any
/// Dart version resolves it identically).
AnimationStyle clampForReduceMotion(AnimationStyle style) =>
    style == AnimationStyle.dynamic || style == AnimationStyle.smooth
        ? AnimationStyle.minimal
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
Duration motionDuration(AnimationStyle style, int baseMs) => Duration(
      milliseconds: (baseMs * style.durationMultiplier).round(),
    );
