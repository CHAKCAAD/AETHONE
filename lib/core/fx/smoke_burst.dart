/// Smoke field — the connected home's ambient green haze (v4.43).
///
/// Adapted from flutterfx_widgets `smoke` (MIT License, Copyright (c) 2024
/// FlutterFX — https://github.com/flutterfx/flutterfx_widgets): the
/// original wandered EIGHT gray circles along cubic Bézier paths between
/// keyframes, each painted with `MaskFilter.blur(BlurStyle.normal, 100)`.
///
/// THE PERFORMANCE PORT: a 100-sigma mask blur re-rasterizes every circle
/// every frame on Skia (desktop) — instead, each blob is painted as a
/// RADIAL-GRADIENT circle (opaque centre → transparent edge), the exact
/// technique the app's own [_AuroraBloomPainter] already uses («all soft
/// edges, no hard rings»). Visually indistinguishable from a blurred disc
/// at these alphas, ~free on every backend (Skia and Impeller alike), and
/// the 60 fps / cold-start budgets stay untouched.
///
/// House rules kept (prompt §11.7 / report §10):
///  * the field renders ONLY while the tunnel is really up — it is a
///    state HONEST decoration, never a fake «connected» cue;
///  * it is gated by the appearance switch ([ConnectionStore.showPatterns]
///    — the background-decoration family) and by the motion style (OFF
///    renders nothing);
///  * the drift paths are absolute geometry — no reading order, RTL-safe;
///  * the tempo (and whether it breathes at all) reads the style's own
///    recipe, so SILK/TIDE/SPRING/BLINK keep their personality.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../motion.dart';

/// Four soft green blobs drifting on closed Bézier loops behind the home
/// composition while connected. Pure decoration — hit-test transparent.
class SmokeField extends StatefulWidget {
  const SmokeField({
    super.key,
    required this.style,
    this.color,
    this.blobCount = 4,
  });

  final MotionStyle style;

  /// How many drifting blobs the field carries (default 4 — the flutterfx
  /// original's eight, halved for the GPU budget).
  final int blobCount;

  /// Defaults to the connected accent (the caller may override for tests).
  final Color? color;

  @override
  State<SmokeField> createState() => _SmokeFieldState();
}

class _SmokeFieldState extends State<SmokeField>
    with SingleTickerProviderStateMixin {
  /// One shared clock for every blob (the flutterfx original gave the
  /// family a single controller too — one ticker, one repaint per frame).
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.style.recipe.swayPeriodMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.style != MotionStyle.off) {
      _clock.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SmokeField old) {
    super.didUpdateWidget(old);
    // A style change mid-session retunes the tempo (the AuroraBloom
    // precedent); OFF parks the clock where it stands.
    _clock.duration = Duration(milliseconds: widget.style.recipe.swayPeriodMs);
    if (widget.style == MotionStyle.off) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _SmokePainter(
            phase: _clock.value,
            color: widget.color ?? AethColors.accentConnected,
            blobs: List.generate(
              widget.blobCount,
              (i) => _BlobSpec.seed(i),
            ),
            breathFloor: widget.style.recipe.swayBreathFloor,
          ),
        ),
      ),
    );
  }
}

/// One blob's loop definition — a closed cubic path through four anchor
/// points, re-seeded per index (the flutterfx `CircleData` keyframe
/// lerp collapsed into one perpetual curve).
class _BlobSpec {
  const _BlobSpec({
    required this.anchors,
    required this.baseRadius,
    required this.baseAlpha,
    required this.phaseOffset,
    required this.drift,
  });

  /// Four normalized (0–1) waypoints the blob forever travels between.
  final List<Offset> anchors;

  /// Blob radius as a fraction of the screen diagonal.
  final double baseRadius;

  /// Peak alpha (the haze stays VERY quiet — the pattern art remains the
  /// owner's tuned frame; this only warms the field behind it).
  final double baseAlpha;

  /// Per-blob phase offset so the four loops never sync visibly.
  final double phaseOffset;

  /// Radius breathing amplitude (fraction of baseRadius).
  final double drift;

  factory _BlobSpec.seed(int i) {
    final rng = math.Random(100 + i * 7);
    Offset waypoint() => Offset(
          0.12 + rng.nextDouble() * 0.76,
          0.08 + rng.nextDouble() * 0.84,
        );
    return _BlobSpec(
      anchors: [waypoint(), waypoint(), waypoint(), waypoint()],
      baseRadius: 0.22 + rng.nextDouble() * 0.16,
      baseAlpha: 0.05 + rng.nextDouble() * 0.045,
      phaseOffset: i / 4.0,
      drift: 0.10 + rng.nextDouble() * 0.10,
    );
  }
}

class _SmokePainter extends CustomPainter {
  const _SmokePainter({
    required this.phase,
    required this.color,
    required this.blobs,
    required this.breathFloor,
  });

  final double phase;
  final Color color;
  final List<_BlobSpec> blobs;

  /// The style's luminance-breath floor (1.0 = no breath — OFF).
  final double breathFloor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final breath =
        breathFloor + (1 - breathFloor) * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));

    for (final blob in blobs) {
      final t = (phase + blob.phaseOffset) % 1.0;
      final center = _bezierLoop(blob.anchors, t);
      final position = Offset(center.dx * size.width, center.dy * size.height);
      final radius = blob.baseRadius * diag * (1 - blob.drift * 0.5 + blob.drift * breath);
      final alpha = blob.baseAlpha * breath;

      // The soft disc: radial gradient, opaque centre → transparent edge —
      // the blur-free port of the original's MaskFilter circle.
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          position,
          radius,
          [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.55),
            color.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        );
      canvas.drawCircle(position, radius, paint);
    }
  }

  /// Closed cubic loop through [points] ( Catmull-Rom-style: each segment
  /// is a cubic Bézier whose control points lean on the neighbours, so the
  /// curve closes smoothly — the original's random control points, but
  /// deterministic and seam-free).
  Offset _bezierLoop(List<Offset> points, double t) {
    final n = points.length;
    final scaled = t * n;
    final i = scaled.floor() % n;
    final f = scaled - scaled.floor();
    final p0 = points[(i - 1 + n) % n];
    final p1 = points[i];
    final p2 = points[(i + 1) % n];
    final p3 = points[(i + 2) % n];
    // Catmull-Rom to Bézier control conversion.
    final c1 = Offset(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
    );
    final c2 = Offset(
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
    );
    return Offset(
      _cubic(p1.dx, c1.dx, c2.dx, p2.dx, f),
      _cubic(p1.dy, c1.dy, c2.dy, p2.dy, f),
    );
  }

  static double _cubic(double p0, double p1, double p2, double p3, double t) =>
      math.pow(1 - t, 3) * p0 +
      3 * math.pow(1 - t, 2) * t * p1 +
      3 * (1 - t) * t * t * p2 +
      t * t * t * p3;

  @override
  bool shouldRepaint(_SmokePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.breathFloor != breathFloor;
}
