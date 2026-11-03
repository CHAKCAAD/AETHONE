/// Small vector glyphs that do NOT exist in the committed 462-icon set and
/// are therefore drawn as inline paths in the set's linear style (1.5px
/// stroke, round caps). Precedent: design decision D7 (onboarding icons) —
/// custom drawing in the set's style is allowed, documented, and kept in ONE
/// place. No Material icons, no emoji, no online assets (owner rule).
///
/// v4.11: the custom PowerIcon / HexWaveIcon / ChevronForwardIcon were
/// REPLACED by the owner-mandated real assets (Off.svg, Activity 4.svg,
/// Right 2.svg — defect reports #2/#4/#12) and are gone.
library;

import 'package:flutter/material.dart';

/// Downward chevron (map-pin expander). Reference crop color:
/// coral-red `#E74C5B` — ONLY used where the reference shows red; the
/// header's map expander uses the muted grey.
class ChevronDownIcon extends StatelessWidget {
  const ChevronDownIcon({super.key, this.size = 10, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(color ?? const Color(0xFFE74C5B)),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.1, h * 0.3)
      ..lineTo(w * 0.5, h * 0.75)
      ..lineTo(w * 0.9, h * 0.3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

/// Three tiny chevrons stacked inside the FAB column.
/// * connected (v4.12 reference): red, DOWN-pointing, below the button —
///   REMOVED in v4.13 by owner decree («آیکون های فلش رو به پایین که در حالت
///   متصل درون این بخش وجود داره رو هم کلا بردار»).
/// * disconnected (reference حالت غیر متصل-ضاهر1): muted green, UP-pointing,
///   above the button — kept via [up] (v4.13 restores the reference pose).
class TripleChevronsIcon extends StatelessWidget {
  const TripleChevronsIcon({
    super.key,
    this.size = 14,
    required this.color,
    this.up = false,
  });

  final double size;
  final Color color;

  /// true → the chevrons point UP (disconnected reference pose).
  final bool up;

  @override
  Widget build(BuildContext context) {
    final painter = _TripleChevronsPainter(color, up: up);
    return CustomPaint(size: Size.square(size), painter: painter);
  }
}

class _TripleChevronsPainter extends CustomPainter {
  _TripleChevronsPainter(this.color, {this.up = false});

  final Color color;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    if (up) {
      // Vertical mirror: the same down-path becomes the up-pose.
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    for (final t in [0.22, 0.5, 0.78]) {
      final path = Path()
        ..moveTo(w * 0.18, h * t - h * 0.13)
        ..lineTo(w * 0.5, h * t)
        ..lineTo(w * 0.82, h * t - h * 0.13);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TripleChevronsPainter old) =>
      old.color != color || old.up != up;
}
