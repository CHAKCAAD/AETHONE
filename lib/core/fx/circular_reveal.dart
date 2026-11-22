/// Circular reveal — the theme-switch transition (v4.43).
///
/// Adapted from flutterfx_widgets `splash-reveal` (MIT License,
/// Copyright (c) 2024 FlutterFX — https://github.com/flutterfx/flutterfx_widgets):
/// the original `CircularRevealClipper` clipped a full-screen overlay away
/// from the SCREEN CENTRE; this port parameterises the origin so the reveal
/// radiates from the theme tile the user actually tapped, and exposes the
/// max-radius math so callers can precompute the corner-to-corner diagonal.
///
/// House rules kept (prompt §11.7 / report §10):
///  * pure geometry — no state, no timers, no platform calls;
///  * direction-neutral (a circle has no reading order — RTL-safe);
///  * the clip only ever VISUALISES a change that has already happened
///    underneath (the palette lerp runs its own 420 ms tween regardless).
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// The reveal clipper: covers everything EXCEPT a circle of [radius] around
/// [center] (even-odd fill — the flutterfx construction, verbatim).
class CircularRevealClipper extends CustomClipper<Path> {
  CircularRevealClipper({required this.center, required this.radius});

  /// Reveal origin in the CLIPPED widget's coordinate space (logical px).
  final Offset center;

  /// Current circle radius (logical px).
  final double radius;

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(CircularRevealClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.center != center;
}

/// The radius that guarantees full coverage of a [size] box from [center],
/// whatever corner is farthest (the original's `sqrt(w²+h²)+20` generalized
/// to an arbitrary origin — the tap point is rarely the screen centre).
double revealMaxRadius(Size size, Offset center) {
  final dx = math.max(center.dx, size.width - center.dx);
  final dy = math.max(center.dy, size.height - center.dy);
  // +20 logical px of slack, the original's own guard against a hairline
  // uncovered sliver at the very end of the wipe.
  return math.sqrt(dx * dx + dy * dy) + 20;
}
