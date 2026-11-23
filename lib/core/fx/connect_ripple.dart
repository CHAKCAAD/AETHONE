/// Connect ripple — look 2's CONNECTING-state animation (flutterfx port,
/// owner round 23: «انیمیشن حین تلاش برای اتصال دکمه اتصال نمای 2 رو هم
/// حذف کن و به جاش از انیمیشن Ripple Effect ریپو flutterfx_widgets
/// استفاده کن»).
///
/// Adapted from flutterfx_widgets `background-ripples` (MIT License,
/// Copyright (c) 2024 FlutterFX —
/// https://github.com/flutterfx/flutterfx_widgets): the original's
/// `Ripple` runs a family of concentric circles around a centre — each
/// circle a fixed size step outward (main + 70 per index), a fill opacity
/// that falls per index (0.24 − 0.03·i) under a border opacity that rises
/// ((5 + 5·i)/100), each breathing INWARD on its own `repeat(reverse:
/// true)` easeInOut clock with a staggered start.
///
/// This port keeps the ripple GRAMMAR verbatim and re-aims it at the
/// walk: the circles centre on the connect button (the Group-45
/// composition), the family is sized to the button's own group (the main
/// circle IS the 160 group, each step a further step-fraction outward),
/// and the field runs ONLY while the engine walks toward a session
/// (starting / waiting / connecting / reconnecting). ONE shared clock
/// drives every ring with a per-ring phase offset — the original's one
/// `Future.delayed`-armed controller per circle would leave pending
/// timers behind on a hot unmount (the test binding's no-pending-timers
/// invariant); the phase offset renders the same staggered,
/// counter-breathing family with none of that.
///
/// House rules (prompt §11.7 / report §10):
///  * STATE-DRIVEN — paints only while [state] is one of the four walk
///    states; the moment the state clears (connected, failed,
///    disconnected) the clock stops dead and nothing paints;
///  * MotionStyle.off renders nothing at all;
///  * nothing here gates anything — the tap lives on the button;
///  * a circle has no reading order — RTL-safe by construction;
///  * the tempo rides the walk vocabulary's own [MotionRecipe.connectMarchMs]
///    slot (the march it replaces), so each personality keeps its feel.
library;

import 'package:flutter/material.dart';

import '../../connection/connection_state.dart';
import '../motion.dart';

/// The breathing concentric family behind look 2's connect button while
/// the engine walks. [size] is the OUTER box (the halo band); the rings
/// centre in it and the main circle spans the button's own group.
class ConnectRipple extends StatefulWidget {
  const ConnectRipple({
    super.key,
    required this.state,
    required this.style,
    required this.size,
    this.rings = 4,
  });

  final VpnState state;
  final MotionStyle style;

  /// The outer box (logical px — the caller passes the scaled halo size).
  final double size;

  /// Circles in the family (the flutterfx demo's eight, tuned down to a
  /// button-scale four).
  final int rings;

  @override
  State<ConnectRipple> createState() => _ConnectRippleState();
}

class _ConnectRippleState extends State<ConnectRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _retune();
  }

  @override
  void didUpdateWidget(covariant ConnectRipple old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state || old.style != widget.style) {
      _retune();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  static bool _isWalk(VpnState s) =>
      s == VpnState.starting ||
      s == VpnState.waitingForPermissions ||
      s == VpnState.connecting ||
      s == VpnState.reconnecting;

  void _retune() {
    final periodMs = widget.style.recipe.connectMarchMs;
    final run = _isWalk(widget.state) &&
        widget.style != MotionStyle.off &&
        periodMs > 0;
    if (run) {
      _clock.duration = Duration(milliseconds: periodMs);
      // A plain sawtooth: every ring folds ITS OWN triangle (up then down)
      // out of the shared phase with its index offset — the staggered
      // `repeat(reverse: true)` family without a controller per circle.
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // OFF / not walking: nothing at all (the state's colours elsewhere
    // carry the story — accessibility).
    if (widget.style == MotionStyle.off || !_isWalk(widget.state)) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _ConnectRipplePainter(
          t: _clock.value,
          rings: widget.rings,
          color: connectRippleInk(widget.state),
        ),
      ),
    );
  }
}

/// The walk's accent — the red family (the engine is NOT connected yet;
/// the honest ink, the same mapping the halo/pill/button share).
Color connectRippleInk(VpnState state) => state == VpnState.connected
    ? const Color(0xFF1AD995)
    : const Color(0xFFEA2323);

/// One ring's inward breath (the flutterfx `repeat(reverse: true)` easeInOut
/// pair, staggered): the SHARED clock's phase [t] is offset by the ring's
/// index share, folded into that ring's own triangle wave — up over the
/// first half of its cycle, down over the second — then eased both ways.
/// Scale 1.0 → 0.90, the original's exact pair.
double _ringScale(int index, int rings, double t) {
  final phase = (t + index / rings) % 1.0;
  final up = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
  return 1.0 - 0.10 * Curves.easeInOut.transform(up);
}

/// The concentric family, painted bottom-up: the main circle spans the
/// button's group, each next ring one step further out, fill opacity
/// falling and border opacity rising per index (the flutterfx pair).
class _ConnectRipplePainter extends CustomPainter {
  _ConnectRipplePainter({
    required this.t,
    required this.rings,
    required this.color,
  });

  /// The shared clock's phase (0..1 across the period).
  final double t;

  final int rings;

  final Color color;

  /// The button's group (design px) relative to the painted box: the halo
  /// band is the element × 1.25 and the Group-45 composition fills the
  /// element — the main circle spans 0.80 of the band.
  static const double _mainFraction = 0.80;

  /// One ring's step outward, as a fraction of the main circle.
  static const double _stepFraction = 0.275;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final main = size.width * _mainFraction;
    // The flutterfx opacity ladder: fill 0.24 − 0.03·i, border (5+5·i)%.
    for (var i = 0; i < rings; i++) {
      final radius =
          (main + main * _stepFraction * i) * _ringScale(i, rings, t) / 2;
      canvas.drawCircle(c, radius, Paint()..color = color.withValues(alpha: 0.24 - 0.03 * i));
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..color = color.withValues(alpha: (5 + 5 * i) / 100)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectRipplePainter old) =>
      old.t != t || old.rings != rings || old.color != color;
}
