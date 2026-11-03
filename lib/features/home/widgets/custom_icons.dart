/// Small vector glyphs that do NOT exist in the committed 462-icon set and
/// are therefore drawn as inline paths in the set's linear style (1.5px
/// stroke, round caps). Precedent: design decision D7 (onboarding icons) —
/// custom drawing in the set's style is allowed, documented, and kept in ONE
/// place. No Material icons, no emoji, no online assets (owner rule).
///
/// v4.11: the custom PowerIcon / HexWaveIcon / ChevronForwardIcon were
/// REPLACED by the owner-mandated real assets (Off.svg, Activity 4.svg,
/// Right 2.svg — defect reports #2/#4/#12) and are gone.
///
/// v4.15 (owner home round #4: «سه فلش رو به بالا در بخش دکمه اتصال کلا حذف
/// شود») — TripleChevronsIcon is REMOVED with its only caller; the
/// ChevronDownIcon (map-pin expander) stays.
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
