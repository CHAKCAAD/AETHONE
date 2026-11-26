/// Traffic Analytics charts — hand-drawn CustomPainters in AETHONE's own
/// language (docs/traffic-analytics-design-research.md): 2 px strokes with
/// round caps, monotone curves (a curve never dips below zero or overshoots
/// a real value), one hairline grid family, IRANYekanX labels, the app's
/// green (download) / red (upload) pair, and no chart library dependency.
/// Every chart draws only the data it is given; an empty series is never
/// drawn as a flat «zero» line — the caller shows an empty state instead.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../analytics/traffic_models.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';

abstract final class TrafficPalette {
  static const Color down = AethColors.accentConnected; // #1AD995
  static const Color downLight = AethColors.pillGreenFrom; // #2FF8B1
  static const Color up = AethColors.pillRedFrom; // #FF5B5E
  static const Color upDeep = AethColors.statusDisconnected; // #EA2323
  static Color get grid => AethColors.textSecondary.withValues(alpha: 0.12);
  static Color get label => AethColors.textSecondary;
  static Color get ink => AethColors.textPrimary;
  static Color get tooltipBg =>
      AethThemeSync.light ? const Color(0xFF141C16) : const Color(0xFFF4F4F4);
  static Color get tooltipInk =>
      AethThemeSync.light ? const Color(0xFFFFFFFF) : const Color(0xFF141C16);

  /// Route colors: the default route green, the second route red, then
  /// tints of those two — never a foreign hue.
  static Color route(int i) => switch (i) {
        0 => down,
        1 => up,
        2 => const Color(0xFF0C7650),
        3 => const Color(0xFFB3262B),
        _ => AethColors.textSecondary.withValues(alpha: 0.5),
      };
}

TextStyle _labelStyle(double s, {Color? color, FontWeight w = FontWeight.w400, double size = 9}) => TextStyle(
      fontFamily: 'IRANYekanX',
      fontSize: size * s,
      fontWeight: w,
      color: color ?? TrafficPalette.label,
      height: 1.2,
    );

/// Monotone cubic (Fritsch–Carlson) through [pts]: no overshoot, so a
/// byte curve never draws a negative dip or a fake peak.
Path _monotone(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) return path;
  final n = pts.length;
  final d = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = pts[i + 1].dx - pts[i].dx;
    d[i] = dx == 0 ? 0 : (pts[i + 1].dy - pts[i].dy) / dx;
  }
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = (d[i - 1] * d[i] <= 0) ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i], b = m[i + 1] / d[i];
    final h = a * a + b * b;
    if (h > 9) {
      final t = 3 / math.sqrt(h);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final dx = (pts[i + 1].dx - pts[i].dx) / 3;
    path.cubicTo(
      pts[i].dx + dx,
      pts[i].dy + m[i] * dx,
      pts[i + 1].dx - dx,
      pts[i + 1].dy - m[i + 1] * dx,
      pts[i + 1].dx,
      pts[i + 1].dy,
    );
  }
  return path;
}

/// A «nice» axis maximum (1, 2, 2.5, 5 × 1024^k bytes).
double niceMax(double v) {
  if (v <= 0) return 1;
  var unit = 1.0;
  while (v / unit >= 1024) {
    unit *= 1024;
  }
  final x = v / unit;
  for (final step in [1.0, 2.0, 2.5, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0, 1024.0]) {
    if (x <= step) return step * unit;
  }
  return 1024 * unit;
}

// ---------------------------------------------------------------------------
// Interactive area chart — download + upload over time (§3.B)
// ---------------------------------------------------------------------------

class TrafficAreaChart extends StatefulWidget {
  const TrafficAreaChart({
    super.key,
    required this.points,
    required this.bucketMs,
    required this.downLabel,
    required this.upLabel,
    this.height = 190,
    this.xLabel,
  });

  final List<TrafficPoint> points;
  final int bucketMs;
  final String downLabel;
  final String upLabel;
  final double height;

  /// Bucket start → its axis/tooltip label.
  final String Function(int t, {bool tooltip})? xLabel;

  @override
  State<TrafficAreaChart> createState() => _TrafficAreaChartState();
}

class _TrafficAreaChartState extends State<TrafficAreaChart> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
  List<TrafficPoint> _from = const [];
  int? _sel;

  @override
  void didUpdateWidget(covariant TrafficAreaChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.points, widget.points)) {
      _from = old.points;
      _sel = null;
      _c
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _x(int t, {bool tooltip = false}) {
    final f = widget.xLabel;
    if (f != null) return f(t, tooltip: tooltip);
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    if (widget.bucketMs < dayMs) return '${d.hour.toString().padLeft(2, '0')}:00';
    return '${d.month}/${d.day}';
  }

  void _touch(Offset p, Size size, double leftPad) {
    final n = widget.points.length;
    if (n == 0) return;
    final w = size.width - leftPad;
    final i = n == 1 ? 0 : (((p.dx - leftPad) / w) * (n - 1)).round().clamp(0, n - 1);
    if (i != _sel) setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final leftPad = 44 * s;
    return Directionality(
      // time runs left → right in every locale (axis convention)
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, widget.height * s);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _touch(d.localPosition, size, leftPad),
            onHorizontalDragStart: (d) => _touch(d.localPosition, size, leftPad),
            onHorizontalDragUpdate: (d) => _touch(d.localPosition, size, leftPad),
            onLongPressEnd: (_) => setState(() => _sel = null),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: size,
                painter: _AreaPainter(
                  from: _from,
                  to: widget.points,
                  t: Curves.easeOutCubic.transform(_c.value),
                  sel: _sel,
                  s: s,
                  leftPad: leftPad,
                  xLabel: _x,
                  downLabel: widget.downLabel,
                  upLabel: widget.upLabel,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.sel,
    required this.s,
    required this.leftPad,
    required this.xLabel,
    required this.downLabel,
    required this.upLabel,
  });

  final List<TrafficPoint> from;
  final List<TrafficPoint> to;
  final double t;
  final int? sel;
  final double s;
  final double leftPad;
  final String Function(int t, {bool tooltip}) xLabel;
  final String downLabel;
  final String upLabel;

  double _v(List<TrafficPoint> l, int i, bool down) {
    if (l.isEmpty) return 0;
    final p = l[i.clamp(0, l.length - 1)];
    return (down ? p.down : p.up).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = to.length;
    if (n == 0) return;
    final bottomPad = 18 * s;
    final topPad = 8 * s;
    final chart = Rect.fromLTRB(leftPad, topPad, size.width, size.height - bottomPad);
    double lerp(int i, bool down) {
      final a = from.length == n ? _v(from, i, down) : 0.0;
      return a + (_v(to, i, down) - a) * t;
    }

    var maxV = 0.0;
    for (var i = 0; i < n; i++) {
      maxV = math.max(maxV, math.max(to[i].down.toDouble(), to[i].up.toDouble()));
    }
    final top = niceMax(maxV);

    // grid: three hairlines + labels (0, ½, max)
    final grid = Paint()
      ..color = TrafficPalette.grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 2; k++) {
      final y = chart.bottom - chart.height * k / 2;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _text(canvas, formatBytes(top * k / 2, decimals: 0), Offset(0, y - 6 * s), leftPad - 6 * s, TextAlign.right);
    }

    double x(int i) => n == 1 ? chart.center.dx : chart.left + chart.width * i / (n - 1);
    double y(double v) => chart.bottom - chart.height * (v / top).clamp(0, 1);

    for (final down in [true, false]) {
      final pts = [for (var i = 0; i < n; i++) Offset(x(i), y(lerp(i, down)))];
      final line = _monotone(pts);
      final area = Path.from(line)
        ..lineTo(pts.last.dx, chart.bottom)
        ..lineTo(pts.first.dx, chart.bottom)
        ..close();
      final c = down ? TrafficPalette.down : TrafficPalette.up;
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, chart.top),
            Offset(0, chart.bottom),
            [c.withValues(alpha: down ? 0.28 : 0.20), c.withValues(alpha: 0.0)],
          ),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // x labels: at most 5, evenly spread
    final ticks = math.min(5, n);
    for (var k = 0; k < ticks; k++) {
      final i = ticks == 1 ? 0 : ((n - 1) * k / (ticks - 1)).round();
      final lx = x(i);
      final w = 48 * s;
      final align = k == 0 ? TextAlign.left : (k == ticks - 1 ? TextAlign.right : TextAlign.center);
      final dx = align == TextAlign.left ? lx : (align == TextAlign.right ? lx - w : lx - w / 2);
      _text(canvas, xLabel(to[i].t), Offset(dx, chart.bottom + 5 * s), w, align);
    }

    // selection: guide, dots, tooltip
    final si = sel;
    if (si != null && si < n) {
      final sx = x(si);
      canvas.drawLine(
        Offset(sx, chart.top),
        Offset(sx, chart.bottom),
        Paint()
          ..color = TrafficPalette.ink.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
      for (final down in [true, false]) {
        final c = down ? TrafficPalette.down : TrafficPalette.up;
        final p = Offset(sx, y(_v(to, si, down)));
        canvas.drawCircle(p, 4.5 * s, Paint()..color = AethColors.cardDark);
        canvas.drawCircle(p, 3 * s, Paint()..color = c);
      }
      final lines = [
        xLabel(to[si].t, tooltip: true),
        '$downLabel  ${formatBytes(to[si].down)}',
        '$upLabel  ${formatBytes(to[si].up)}',
      ];
      final tps = [
        for (var k = 0; k < lines.length; k++)
          TextPainter(
            text: TextSpan(
              text: lines[k],
              style: _labelStyle(s,
                  color: k == 0 ? TrafficPalette.tooltipInk.withValues(alpha: 0.7) : TrafficPalette.tooltipInk,
                  w: k == 0 ? FontWeight.w400 : FontWeight.w600,
                  size: 10),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
      ];
      final w = tps.map((p) => p.width).reduce(math.max) + 20 * s;
      final h = tps.fold<double>(0, (a, p) => a + p.height) + 14 * s + 4 * s;
      var left = sx + 10 * s;
      if (left + w > size.width) left = sx - 10 * s - w;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(left, chart.top, w, h), Radius.circular(10 * s));
      canvas.drawRRect(r, Paint()..color = TrafficPalette.tooltipBg);
      var ty = chart.top + 7 * s;
      for (var k = 0; k < tps.length; k++) {
        if (k > 0) {
          final c = k == 1 ? TrafficPalette.down : TrafficPalette.up;
          canvas.drawCircle(Offset(left + 10 * s, ty + tps[k].height / 2), 3 * s, Paint()..color = c);
          tps[k].paint(canvas, Offset(left + 17 * s, ty));
        } else {
          tps[k].paint(canvas, Offset(left + 10 * s, ty));
        }
        ty += tps[k].height + (k == 0 ? 4 * s : 0);
      }
    }
  }

  void _text(Canvas canvas, String t, Offset o, double width, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: _labelStyle(s)),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) =>
      old.t != t || old.sel != sel || !identical(old.to, to) || old.s != s;
}

// ---------------------------------------------------------------------------
// Live speed line (§6): last 60 s of the engine counters
// ---------------------------------------------------------------------------

class LiveSpeedChart extends StatelessWidget {
  const LiveSpeedChart({super.key, required this.down, required this.up, this.height = 70});

  final List<int> down;
  final List<int> up;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(double.infinity, height * s),
          painter: _LivePainter(down, up, s),
        ),
      ),
    );
  }
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.down, this.up, this.s);
  final List<int> down;
  final List<int> up;
  final double s;

  static const window = 60;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = niceMax([...down, ...up, 1].reduce(math.max).toDouble());
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = TrafficPalette.grid,
    );
    for (final isDown in [true, false]) {
      final v = isDown ? down : up;
      if (v.length < 2) continue;
      final pts = <Offset>[];
      for (var i = 0; i < v.length; i++) {
        // right-aligned: the newest sample sits at the right edge
        final x = size.width * (window - v.length + i) / (window - 1);
        pts.add(Offset(x, size.height - 2 * s - (size.height - 4 * s) * (v[i] / maxV).clamp(0, 1)));
      }
      final c = isDown ? TrafficPalette.down : TrafficPalette.up;
      final line = _monotone(pts);
      if (isDown) {
        final area = Path.from(line)
          ..lineTo(pts.last.dx, size.height)
          ..lineTo(pts.first.dx, size.height)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(0, size.height),
              [c.withValues(alpha: 0.22), c.withValues(alpha: 0)],
            ),
        );
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * s
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(pts.last, 2.6 * s, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(covariant _LivePainter old) => !identical(old.down, down) || !identical(old.up, up);
}

// ---------------------------------------------------------------------------
// Donut — share of each route (§5)
// ---------------------------------------------------------------------------

class TrafficDonut extends StatelessWidget {
  const TrafficDonut({
    super.key,
    required this.values,
    required this.colors,
    required this.center,
    required this.caption,
    this.size = 132,
    this.selected,
  });

  final List<int> values;
  final List<Color> colors;
  final String center;
  final String caption;
  final double size;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final d = size * s;
    return SizedBox(
      width: d,
      height: d,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _DonutPainter(shares(values), colors, t, s, selected),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(center,
                    style: _labelStyle(s, color: TrafficPalette.ink, w: FontWeight.w700, size: 15),
                    textDirection: TextDirection.ltr),
                SizedBox(height: 2 * s),
                Text(caption, style: _labelStyle(s, size: 9.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.sh, this.colors, this.t, this.s, this.selected);
  final List<double> sh;
  final List<Color> colors;
  final double t;
  final double s;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 11 * s;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2 + 2 * s);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = TrafficPalette.grid
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (sh.isEmpty) return;
    final gap = sh.where((x) => x > 0).length > 1 ? 0.06 : 0.0;
    var a = -math.pi / 2;
    for (var i = 0; i < sh.length; i++) {
      final sweep = sh[i] * math.pi * 2 * t;
      if (sweep <= 0) continue;
      final g = math.min(gap, sweep * 0.4);
      canvas.drawArc(
        selected == i ? r.inflate(1.5 * s) : r,
        a + g / 2,
        math.max(0.001, sweep - g),
        false,
        Paint()
          ..color = (selected == null || selected == i) ? colors[i % colors.length] : colors[i % colors.length].withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = selected == i ? stroke + 2 * s : stroke,
      );
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.t != t || old.selected != selected || old.sh != sh;
}

// ---------------------------------------------------------------------------
// Horizontal bar (apps / routes comparison) and sparkline
// ---------------------------------------------------------------------------

/// One stacked bar: download (green) then upload (red), scaled to [max].
class TrafficHBar extends StatelessWidget {
  const TrafficHBar({super.key, required this.down, required this.up, required this.max, this.height = 6});

  final int down;
  final int up;
  final int max;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final h = height * s;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final m = max <= 0 ? 1 : max;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          final dw = w * (down / m) * t;
          final uw = w * (up / m) * t;
          return Container(
            height: h,
            decoration: BoxDecoration(color: TrafficPalette.grid, borderRadius: BorderRadius.circular(h)),
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: dw,
                  height: h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [TrafficPalette.downLight, TrafficPalette.down]),
                    borderRadius: BorderRadiusDirectional.horizontal(
                      start: Radius.circular(h),
                      end: Radius.circular(uw < 1 ? h : 0),
                    ),
                  ),
                ),
                Container(
                  width: uw,
                  height: h,
                  decoration: BoxDecoration(
                    color: TrafficPalette.up,
                    borderRadius: BorderRadiusDirectional.horizontal(
                      end: Radius.circular(h),
                      start: Radius.circular(dw < 1 ? h : 0),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

class TrafficSparkline extends StatelessWidget {
  const TrafficSparkline({super.key, required this.values, this.width = 54, this.height = 20, this.color});

  final List<int> values;
  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        size: Size(width * s, height * s),
        painter: _SparkPainter(values, color ?? TrafficPalette.down, s),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.c, this.s);
  final List<int> v;
  final Color c;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final m = v.reduce(math.max);
    if (m <= 0) return;
    final pts = [
      for (var i = 0; i < v.length; i++)
        Offset(size.width * i / (v.length - 1), size.height - 1.5 * s - (size.height - 3 * s) * v[i] / m),
    ];
    canvas.drawPath(
      _monotone(pts),
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * s
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.v != v || old.c != c;
}

/// Two-bar comparison (current vs previous) for §7.
class CompareBars extends StatelessWidget {
  const CompareBars({
    super.key,
    required this.current,
    required this.previous,
    required this.currentLabel,
    required this.previousLabel,
  });

  final int current;
  final int? previous;
  final String currentLabel;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final m = math.max(current, previous ?? 0);
    Widget row(String label, int? v, bool cur) => Padding(
          padding: EdgeInsets.symmetric(vertical: 4 * s),
          child: Row(
            children: [
              SizedBox(width: 64 * s, child: Text(label, style: _labelStyle(s, size: 10))),
              Expanded(
                child: v == null
                    ? Container(
                        height: 8 * s,
                        decoration: BoxDecoration(
                          border: Border.all(color: TrafficPalette.grid),
                          borderRadius: BorderRadius.circular(8 * s),
                        ),
                      )
                    : _FlatBar(
                        value: v,
                        max: m,
                        color: cur ? TrafficPalette.down : AethColors.textSecondary.withValues(alpha: 0.45),
                      ),
              ),
              SizedBox(width: 8 * s),
              SizedBox(
                width: 62 * s,
                child: Text(
                  v == null ? '—' : formatBytes(v),
                  textAlign: TextAlign.end,
                  textDirection: TextDirection.ltr,
                  style: _labelStyle(s, color: TrafficPalette.ink, w: FontWeight.w600, size: 10.5),
                ),
              ),
            ],
          ),
        );
    return Column(children: [row(currentLabel, current, true), row(previousLabel, previous, false)]);
  }
}

class _FlatBar extends StatelessWidget {
  const _FlatBar({required this.value, required this.max, required this.color});
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final h = 8 * s;
    return LayoutBuilder(
      builder: (context, box) => Container(
        height: h,
        decoration: BoxDecoration(color: TrafficPalette.grid, borderRadius: BorderRadius.circular(h)),
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          width: box.maxWidth * (max <= 0 ? 0 : value / max),
          height: h,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(h)),
        ),
      ),
    );
  }
}
