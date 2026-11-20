/// SHIMMER EDGE — the flutterfx «button-shimmer» technique, rebuilt
/// natively for AETHONE (owner round 18: «انمیشنی که در حالت متصل نمای 1
/// پشت دکمه اتصال وسط صفحه وجود داره رو از اپ حذف کن و به جاش Shimmer
/// Button رو اعمال کن دقت کن که این انیمیشن باید دقیقا رو لبه های دکمه
/// حرکت کنه نه رو لبه محدوده اون»).
///
/// The decree has two halves: the behind-the-button AURORA ambience of
/// the connected state is RETIRED (see [ConnectHalo.hideConnectedAura]
/// in connect_core.dart), and in its place the button's OWN EDGE carries
/// the life — a faint static border plus ONE traveling light segment
/// that laps the button's rounded-rect perimeter (1/8 of the path,
/// gradient tail-to-head, exactly the reference painter's math:
/// PathMetrics.extractPath along the RRect with the gradient stretched
/// between the segment's tangent endpoints).
///
/// It rides ON the button's edge — never beyond it: the stroke is the
/// only ink this widget paints. Mounted only while CONNECTED (state
/// honesty — the shimmer IS the connected state's idle life now), for
/// BOTH looks (the look-1 hero logo's bounds; the look-2 Group-45 core
/// squircle), faded in through the caller's AnimatedSwitcher.
///
/// [MotionStyle.off] keeps the static faint edge (status feedback, not
/// motion) and stops the lap.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

class ShimmerEdge extends StatefulWidget {
  const ShimmerEdge({
    super.key,
    required this.style,
    required this.width,
    required this.height,
    required this.radius,
    this.stroke = 2.5,
  });

  final MotionStyle style;

  /// The BUTTON's own box (design px already scaled by the caller).
  final double width;
  final double height;
  final double radius;

  /// The stroke weight, pre-scaled like the box (2.5 ref px by default).
  final double stroke;

  @override
  State<ShimmerEdge> createState() => _ShimmerEdgeState();
}

class _ShimmerEdgeState extends State<ShimmerEdge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lap;

  @override
  void initState() {
    super.initState();
    _lap = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.style.recipe.shimmerMs),
    );
    if (widget.style.recipe.shimmerMs > 0) _lap.repeat();
  }

  @override
  void didUpdateWidget(covariant ShimmerEdge old) {
    super.didUpdateWidget(old);
    _lap.duration = Duration(milliseconds: widget.style.recipe.shimmerMs);
    if (widget.style.recipe.shimmerMs > 0) {
      if (!_lap.isAnimating) _lap.repeat();
    } else {
      _lap.stop();
    }
  }

  @override
  void dispose() {
    _lap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _lap,
          builder: (context, _) => CustomPaint(
            painter: _ShimmerEdgePainter(
              progress: _lap.value,
              radius: widget.radius,
              stroke: widget.stroke,
            ),
          ),
        ),
      ),
    );
  }
}

/// The reference painter's math, verbatim technique: a static faint
/// border under ONE bright traveling segment (1/8 of the perimeter)
/// whose linear gradient runs tail (transparent → green) to head
/// (bright mint) between the segment's tangent endpoints.
class _ShimmerEdgePainter extends CustomPainter {
  _ShimmerEdgePainter({
    required this.progress,
    required this.radius,
    required this.stroke,
  });

  final double progress;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = stroke / 2;
    final edge = Rect.fromLTWH(
      inset,
      inset,
      size.width - stroke,
      size.height - stroke,
    );
    final rrect = RRect.fromRectAndRadius(
      edge,
      Radius.circular(radius),
    );

    // The static faint edge — the connected state's resting frame.
    final staticPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AethColors.accentConnected.withValues(alpha: 0.28);
    canvas.drawRRect(rrect, staticPaint);

    if (progress == 0) return; // OFF style: the static edge only.

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    final pathLength = metrics.length;

    // One lap, no jump: the segment wraps the perimeter seamlessly.
    final p = progress % 1.0;
    final start = p * pathLength;
    final end = (start + pathLength / 8) % pathLength;

    Path segment;
    if (end > start) {
      segment = metrics.extractPath(start, end);
    } else {
      segment = metrics.extractPath(start, pathLength);
      segment.addPath(metrics.extractPath(0, end), Offset.zero);
    }

    final from = metrics.getTangentForOffset(start)?.position ?? Offset.zero;
    final to = metrics
            .getTangentForOffset((start + pathLength / 8) % pathLength)
            ?.position ??
        Offset.zero;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = ui.Gradient.linear(
        from,
        to,
        [
          AethColors.accentConnected.withValues(alpha: 0.0),
          AethColors.accentConnected,
          const Color(0xCCFFFFFF),
        ],
        [0.0, 0.3, 1.0],
      );
    canvas.drawPath(segment, paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerEdgePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.radius != radius ||
      oldDelegate.stroke != stroke;
}
