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
enum MotionStyle {
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

extension MotionStyleX on MotionStyle {
  double get durationMultiplier => switch (this) {
        MotionStyle.standard => 1.0,
        MotionStyle.smooth => 1.5,
        MotionStyle.dynamic => 0.8,
        MotionStyle.minimal => 0.4,
        MotionStyle.off => 0.0,
      };

  Curve get curve => switch (this) {
        MotionStyle.standard => Curves.easeInOutCubic,
        MotionStyle.smooth => Curves.easeOutQuint,
        MotionStyle.dynamic => Curves.easeOutBack,
        MotionStyle.minimal => Curves.easeOut,
        MotionStyle.off => Curves.linear,
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
