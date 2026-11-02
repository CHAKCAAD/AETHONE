/// Small vector glyphs that do NOT exist in the committed 462-icon set and
/// are therefore drawn as inline paths in the set's linear style (1.5px
/// stroke, round caps). Precedent: design decision D7 (onboarding icons) —
/// custom drawing in the set's style is allowed, documented, and kept in ONE
/// place. No Material icons, no emoji, no online assets (owner rule).
library;

import 'package:flutter/material.dart';

/// Downward chevron (map-pin expander). Reference crop color:
/// coral-red `#E74C5B` — ONLY used where the reference shows red; the
/// protocol card uses the white forward chevron below.
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

/// Forward chevron (>) — the protocol card's "open selector" affordance
/// (reference: white > at the card's right edge, x 276–290).
class ChevronForwardIcon extends StatelessWidget {
  const ChevronForwardIcon({super.key, this.size = 10, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronForwardPainter(color),
    );
  }
}

class _ChevronForwardPainter extends CustomPainter {
  _ChevronForwardPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.30, h * 0.12)
      ..lineTo(w * 0.78, h * 0.5)
      ..lineTo(w * 0.30, h * 0.88);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronForwardPainter old) => old.color != color;
}

/// Three tiny downward chevrons stacked inside the FAB column
/// (reference: red, x 334–346 / y 800–820 on حالت متصل-ضاهر1).
class TripleChevronsIcon extends StatelessWidget {
  const TripleChevronsIcon({super.key, this.size = 14, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TripleChevronsPainter(color),
    );
  }
}

class _TripleChevronsPainter extends CustomPainter {
  _TripleChevronsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
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
  bool shouldRepaint(_TripleChevronsPainter old) => old.color != color;
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

/// Power symbol (circle with a vertical top line) — the connect-button icon.
/// Owner: icon color `#75160F` (disconnected) → `#123E2B` (connected).
class PowerIcon extends StatelessWidget {
  const PowerIcon({super.key, this.size = 24, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PowerPainter(color),
    );
  }
}

class _PowerPainter extends CustomPainter {
  _PowerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.083 // ~2px at 24
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height * 0.6);
    final r = size.width * 0.30;
    // Arc with a gap at the top (classic power symbol).
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -0.9, 2 * 3.14159 - 1.8,
        false, paint);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.083
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.12),
      Offset(size.width / 2, size.height * 0.48),
      line,
    );
  }

  @override
  bool shouldRepaint(_PowerPainter old) => old.color != color;
}

/// Hexagon with a horizontal wave through it — the Speed Test button icon
/// (VLM crop read: hexagon outline + sine line, dark-green stroke).
class HexWaveIcon extends StatelessWidget {
  const HexWaveIcon({super.key, this.size = 20, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HexWavePainter(color),
    );
  }
}

class _HexWavePainter extends CustomPainter {
  _HexWavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    // Flat-top hexagon centered in the box.
    final hex = Path()
      ..moveTo(w * 0.25, h * 0.10)
      ..lineTo(w * 0.75, h * 0.10)
      ..lineTo(w * 0.95, h * 0.50)
      ..lineTo(w * 0.75, h * 0.90)
      ..lineTo(w * 0.25, h * 0.90)
      ..lineTo(w * 0.05, h * 0.50)
      ..close();
    canvas.drawPath(hex, paint);
    // Sine wave through the middle.
    final wave = Path()
      ..moveTo(w * 0.18, h * 0.50)
      ..cubicTo(w * 0.32, h * 0.28, w * 0.42, h * 0.72, w * 0.55, h * 0.50)
      ..cubicTo(w * 0.66, h * 0.32, w * 0.78, h * 0.62, w * 0.85, h * 0.50);
    canvas.drawPath(wave, paint);
  }

  @override
  bool shouldRepaint(_HexWavePainter old) => old.color != color;
}
