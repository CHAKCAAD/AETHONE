/// v1.0.2 motion overhaul — the CONNECT STAGE DIRECTOR.
///
/// ONE widget renders the state-driven halo that lives BEHIND the central
/// element of BOTH home looks (the logo in look 1, the Group-45 squircle
/// button in look 2). Because both looks mount THIS SAME widget, their
/// state languages can never contradict each other — the audit's core
/// finding (the old ScanRings only knew "walking" and AuroraBloom only
/// knew "connected") is resolved by mapping ALL EIGHT states here:
///
///   disconnected  — nothing (the calm red control speaks for itself)
///   starting      — IGNITION: one ring bursts outward from the element
///                   (a single ~400 ms one-shot) + a soft glow fades in
///   waitingForPer—— HELD: the dashed ring FREEZES and its opacity
///   missions        breathes slowly (connectHoldMs) — visibly suspended,
///                   not marching
///   connecting    — MARCH: a dashed ring marches around the element
///                   (connectMarchMs, direction = the reading direction)
///                   + a breathing core glow — directional energy
///   connected     — AURORA BLOOM (the owner-approved v4.15 halo, ported
///                   verbatim: soft breathing glow + three water ripples)
///                   + a ONE-SHOT celebration on the connecting→connected
///                   EDGE (three quick rings + a glow flash, celebrationMs)
///   reconnecting  — SEEK: an arc swings back and forth like a searching
///                   radar + a double pulse per period (connectSeekMs) —
///                   a rhythm deliberately DIFFERENT from the march
///   disconnecting — COLLAPSE: the ring contracts into the element and
///                   fades (~320 ms one-shot) — "closing down"
///   failed        — a quiet static error ring (the SHAKE lives on the
///                   control itself, see [ConnectShake])
///
/// Hard rules honored: every visual is a PURE function of the real
/// [VpnState]; nothing fakes progress; the one-shots fire on state EDGES
/// only (a stats tick re-notify can never re-trigger them); tapping is
/// owned by the surfaces, never delayed here; MotionStyle.off paints
/// nothing (the color/text state feedback elsewhere stays — accessibility).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../connection/connection_state.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';

/// The per-state accent — ONE mapping so the pill, the button, the FAB and
/// the halo can never disagree. Honest: green only when REALLY connected.
Color connectAccentFor(VpnState state) => state == VpnState.connected
    ? AethColors.accentConnected
    : AethColors.statusDisconnected;

/// The per-state glyph from the brand's own asset set (the v4.15 pill
/// mapping extended to the three previously-unlabelled states).
String connectGlyphFor(VpnState state) => switch (state) {
      VpnState.connected => AppAssets.iconShieldTick,
      VpnState.starting ||
      VpnState.waitingForPermissions ||
      VpnState.connecting => AppAssets.iconSend,
      _ => AppAssets.iconShieldCross, // disconnected/reconnecting/
                                     // disconnecting/failed
    };

/// The halo stage itself. [size] is the OUTER box; the central element
/// (logo or button composition) occupies ~0.40 of it (both looks derive
/// from ×1.25 of their element, so 0.40 is exact for both) and the state
/// rings ride just outside at ~0.48.
///
/// [hideWalkStates] — the flutterfx round: look 1's walk vocabulary is the
/// SPARK LOADER now (the logo itself marches, see [HeroLogo] /
/// [SparkLoaderSpin]; owner: «هرچی انیمیشن برای حالت در حال اتصال نمای ۱
/// … حذف کن»), so the halo paints NOTHING for the four walk states on that
/// look and their ambient loops park too. The connected edge's celebration,
/// the aurora, the collapse and the error ring stay — only the walk
/// vocabulary is suppressed, and look 2 keeps everything.
///
/// [hideConnectedAura] — v8a (owner round 18: «انیمیشنی که در حالت متصل
/// نمای 1 پشت دکمه اتصال وسط صفحه وجود داره رو از اپ حذف کن و به جاش
/// Shimmer Button رو اعمال کن»): the connected state's AURORA BLOOM —
/// the soft breathing glow + water ripples that played in the AREA
/// AROUND the button — is RETIRED from the app (both looks pass true);
/// the connected idle life now rides the button's OWN EDGE instead
/// ([ShimmerEdge], shimmer_edge.dart — «دقیقا رو لبه های دکمه حرکت
/// کنه نه رو لبه محدوده اون»). The ONE-SHOT celebration on the
/// connecting→connected edge stays (it is the walk vocabulary's landing
/// flourish, not a steady-state ambience), as do the collapse and the
/// error ring; the walk states keep their full vocabulary on look 2.
class ConnectHalo extends StatefulWidget {
  const ConnectHalo({
    super.key,
    required this.state,
    required this.style,
    required this.size,
    this.hideWalkStates = false,
    this.hideConnectedAura = false,
  });

  final VpnState state;
  final MotionStyle style;
  final double size;

  /// Suppress the walk-state visuals (look 1's spark-loader handoff).
  final bool hideWalkStates;

  /// Suppress the connected state's steady aurora (the v8a shimmer
  /// handoff — the edge replaces the area).
  final bool hideConnectedAura;

  @override
  State<ConnectHalo> createState() => _ConnectHaloState();
}

class _ConnectHaloState extends State<ConnectHalo>
    with TickerProviderStateMixin {
  /// The ambient loop — the march / seek / hold / ripple phase.
  late final AnimationController _loop = AnimationController(vsync: this);

  /// The connected breath (its own period, like the v4.15 aurora pair).
  late final AnimationController _breath = AnimationController(vsync: this);

  /// The one-shot channel — ignition (starting), celebration (connected
  /// edge) and collapse (disconnecting) all ride this single controller.
  late final AnimationController _shot = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _retune(null);
  }

  @override
  void didUpdateWidget(covariant ConnectHalo old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state ||
        old.style != widget.style ||
        old.hideWalkStates != widget.hideWalkStates ||
        old.hideConnectedAura != widget.hideConnectedAura) {
      _retune(old.state);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _breath.dispose();
    _shot.dispose();
    super.dispose();
  }

  void _retune(VpnState? previous) {
    final r = widget.style.recipe;
    final state = widget.state;
    final off = widget.style == MotionStyle.off;
    // The spark-loader handoff: look 1 parks the walk loops entirely.
    final walkHidden =
        widget.hideWalkStates && _isWalkState(state);
    // v8a — the shimmer handoff: the connected state's aurora loops
    // (the ripple cycle + the breath) park when the aura is retired —
    // nothing paints, so nothing ticks (the battery-saver ethos).
    final auraHidden = widget.hideConnectedAura && state == VpnState.connected;

    // --- the ambient loop: which states keep one running? ---
    final loopMs = walkHidden || auraHidden
        ? 0
        : switch (state) {
            VpnState.connecting => r.connectMarchMs,
            VpnState.reconnecting => r.connectSeekMs,
            VpnState.waitingForPermissions => r.connectHoldMs,
            VpnState.connected => r.rippleMs,
            _ => 0,
          };
    if (loopMs > 0 && !off) {
      _loop.duration = Duration(milliseconds: loopMs);
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }

    // --- the breath: only the connected aurora breathes on its own clock
    // (and only while the aura still paints — v8a parks it otherwise). ---
    if (state == VpnState.connected &&
        !off &&
        !auraHidden &&
        r.heroBreathAmp > 0) {
      _breath.duration = Duration(milliseconds: r.heroBreathMs);
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
    }

    // --- the one-shots: fire ONLY on the state EDGE. ---
    if (previous != null && previous != state && !off) {
      switch (state) {
        case VpnState.starting:
          // The ignition ring belongs to the halo's walk vocabulary —
          // suppressed on the spark-loader look with the rest of them.
          if (!widget.hideWalkStates) {
            _fire(motionDuration(widget.style, 400));
          }
        case VpnState.connected:
          // Celebrate the transition, never the steady state.
          if (previous == VpnState.connecting ||
              previous == VpnState.reconnecting) {
            _fire(Duration(milliseconds: r.celebrationMs));
          }
        case VpnState.disconnecting:
          _fire(motionDuration(widget.style, 320));
        default:
          break;
      }
    }
  }

  void _fire(Duration d) {
    if (d == Duration.zero) return;
    _shot
      ..stop()
      ..duration = d
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // OFF paints nothing — the pill/colors carry the state (accessibility).
    if (widget.style == MotionStyle.off) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    final sign = horizontalSign(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _breath, _shot]),
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _ConnectHaloPainter(
          state: widget.state,
          phase: _loop.value,
          breath: Curves.easeInOut.transform(_breath.value),
          shot: _shot.value,
          directionSign: sign,
          hideWalkStates: widget.hideWalkStates,
          hideConnectedAura: widget.hideConnectedAura,
        ),
      ),
    );
  }
}

/// Whether [s] is one of the four engine-walk states (the spark loader's
/// active domain on look 1).
bool _isWalkState(VpnState s) =>
    s == VpnState.starting ||
    s == VpnState.waitingForPermissions ||
    s == VpnState.connecting ||
    s == VpnState.reconnecting;

/// All eight states, one painter, one layer — `shouldRepaint` is exact, so
/// an idle disconnected home paints nothing at all and the march costs one
/// thin dashed stroke per frame.
class _ConnectHaloPainter extends CustomPainter {
  _ConnectHaloPainter({
    required this.state,
    required this.phase,
    required this.breath,
    required this.shot,
    required this.directionSign,
    this.hideWalkStates = false,
    this.hideConnectedAura = false,
  });

  final VpnState state;
  final double phase;
  final double breath;
  final double shot;

  /// The reading-direction sign (+1 LTR / −1 RTL) — a double because it
  /// multiplies radian rotations directly.
  final double directionSign;

  /// Look 1's spark-loader handoff: paint nothing for the walk states.
  final bool hideWalkStates;

  /// v8a — the shimmer handoff: the connected state's steady AURORA is
  /// retired; only the one-shot celebration may paint there.
  final bool hideConnectedAura;

  /// The central element's radius as a fraction of the box (0.40 for BOTH
  /// looks — each mounts the halo at element × 1.25).
  static const double _element = 0.40;

  /// Where the state rings ride.
  static const double _ring = 0.48;

  @override
  void paint(Canvas canvas, Size size) {
    // The spark-loader look: the walk states own NOTHING here — the logo
    // itself is the motion (the calm-before/the march/the landing all
    // live in SparkLoaderSpin).
    if (hideWalkStates && _isWalkState(state)) return;
    final c = Offset(size.width / 2, size.height / 2);
    final col = connectAccentFor(state);
    switch (state) {
      case VpnState.disconnected:
        break; // calm — the control itself speaks

      case VpnState.starting:
        _ignition(canvas, size, c, col);

      case VpnState.waitingForPermissions:
        _held(canvas, size, c, col);

      case VpnState.connecting:
        _march(canvas, size, c, col);

      case VpnState.connected:
        // v8a — the steady AURORA BLOOM behind the button is RETIRED by
        // the owner's decree (the ShimmerEdge on the button's own edge
        // carries the connected idle life now); the ONE-SHOT landing
        // celebration stays — it belongs to the walk vocabulary's finale,
        // never to the steady state.
        if (!hideConnectedAura) _aurora(canvas, size, c, col);
        if (shot > 0 && shot < 1) _celebration(canvas, size, c, col);

      case VpnState.reconnecting:
        _seek(canvas, size, c, col);

      case VpnState.disconnecting:
        _collapse(canvas, size, c, col);

      case VpnState.failed:
        _errorRing(canvas, size, c, col);
    }
  }

  Paint _stroke(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..isAntiAlias = true;

  /// STARTING — one ring bursts outward from the element (t = the one-shot
  /// progress) while a soft glow fades in behind it.
  void _ignition(Canvas canvas, Size size, Offset c, Color col) {
    final t = shot.clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(t);
    if (t < 1) {
      final ring = _stroke(col.withValues(alpha: 0.45 * (1 - e)))
        ..strokeWidth = 3;
      canvas.drawCircle(
        c,
        size.width * (_element + (0.10 * e)),
        ring,
      );
    }
    _softGlow(canvas, size, c, col, alpha: 0.10 + 0.06 * t);
  }

  /// WAITING — the dashed ring FREEZES; only its opacity breathes. Held,
  /// not marching — the state is suspended waiting for the OS dialog.
  void _held(Canvas canvas, Size size, Offset c, Color col) {
    final b = 0.5 - 0.5 * math.cos(phase * 2 * math.pi);
    _dashedRing(
      canvas,
      size,
      c,
      col.withValues(alpha: 0.22 + 0.22 * b),
      rotation: 0,
    );
    _softGlow(canvas, size, c, col, alpha: 0.08 + 0.05 * b);
  }

  /// CONNECTING — the dashes march around the element in the reading
  /// direction (RTL flips it), plus a gently breathing core glow.
  void _march(Canvas canvas, Size size, Offset c, Color col) {
    _dashedRing(
      canvas,
      size,
      c,
      col.withValues(alpha: 0.55),
      rotation: -phase * 2 * math.pi * directionSign,
    );
    final b = 0.5 - 0.5 * math.cos(phase * 2 * math.pi);
    _softGlow(canvas, size, c, col, alpha: 0.10 + 0.07 * b);
  }

  /// RECONNECTING — the seek: an arc swings back and forth (a searching
  /// radar) while the ring double-pulses per period. A rhythm distinct
  /// from the march in shape, tempo AND motion.
  void _seek(Canvas canvas, Size size, Offset c, Color col) {
    final p = phase * 2 * math.pi;
    // Double pulse: two gaussian bumps early in the period, then rest.
    double bump(double m) => math.exp(-math.pow((phase - m) / 0.09, 2));
    final pulse = math.max(bump(0.18), 0.65 * bump(0.42));
    final radius = size.width * (_ring + 0.015 * pulse);
    final ring = _stroke(col.withValues(alpha: 0.30 + 0.35 * pulse))
      ..strokeWidth = 2.5 + 1.5 * pulse;
    canvas.drawCircle(c, radius, ring);
    // The swinging search arc (~70°), oscillating like a radar needle.
    final swing = math.sin(p) * 0.9; // radians, ±0.9
    const sweep = math.pi / 2.6;
    final center = -math.pi / 2 + swing * directionSign;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      center - sweep / 2,
      sweep,
      false,
      _stroke(col.withValues(alpha: 0.60))..strokeWidth = 3,
    );
  }

  /// CONNECTED — the owner-approved v4.15 AURORA BLOOM, ported verbatim:
  /// a faint breathing halo, a breathing core glow and three staggered
  /// water-ripples, all soft edges (heavy blur), never hard circles.
  void _aurora(Canvas canvas, Size size, Offset c, Color col) {
    // 1) Faint outer halo.
    final halo = Paint()
      ..shader = ui.Gradient.radial(
        c,
        size.width * 0.5,
        [col.withValues(alpha: 0.05 + 0.04 * breath), col.withValues(alpha: 0)],
      );
    canvas.drawCircle(c, size.width * 0.5, halo);

    // 2) Breathing core glow.
    final glowRadius = size.width * (0.28 + 0.07 * breath);
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        c,
        glowRadius,
        [col.withValues(alpha: 0.14 + 0.12 * breath), col.withValues(alpha: 0)],
      );
    canvas.drawCircle(c, glowRadius, glow);

    // 3) The three water-ripples.
    for (var i = 0; i < 3; i++) {
      final p = (phase + i / 3) % 1.0;
      final e = Curves.easeOutCubic.transform(p);
      final fade = math.pow(1 - e, 2).toDouble();
      final ring = Paint()
        ..color = col.withValues(alpha: 0.24 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.008 + 0.024 * fade)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          size.width * (0.007 + 0.014 * fade),
        );
      canvas.drawCircle(c, size.width * (0.16 + 0.30 * e), ring);
    }
  }

  /// The connecting→connected EDGE celebration: three quick rings race
  /// outward (staggered starts) under a glow flash — once, then the calm
  /// aurora carries the steady state.
  void _celebration(Canvas canvas, Size size, Offset c, Color col) {
    final t = shot;
    final flash = Paint()
      ..shader = ui.Gradient.radial(
        c,
        size.width * 0.5,
        [col.withValues(alpha: 0.30 * (1 - t)), col.withValues(alpha: 0)],
      );
    canvas.drawCircle(c, size.width * 0.5, flash);
    for (var i = 0; i < 3; i++) {
      final lt = ((t - i * 0.15) / 0.85).clamp(0.0, 1.0);
      if (lt <= 0) continue;
      final e = Curves.easeOutCubic.transform(lt);
      final ring = _stroke(
        col.withValues(alpha: 0.5 * math.pow(1 - lt, 2).toDouble()),
      );
      canvas.drawCircle(c, size.width * (0.42 + 0.20 * e), ring);
    }
  }

  /// DISCONNECTING — the collapse: the ring contracts INTO the element and
  /// dissolves (t = the one-shot progress).
  void _collapse(Canvas canvas, Size size, Offset c, Color col) {
    final t = shot.clamp(0.0, 1.0);
    final e = Curves.easeInCubic.transform(t);
    if (t < 1) {
      final ring = _stroke(col.withValues(alpha: 0.40 * (1 - e)))
        ..strokeWidth = 3;
      canvas.drawCircle(
        c,
        size.width * (_ring - (_ring - _element) * e),
        ring,
      );
    }
    _softGlow(canvas, size, c, col, alpha: 0.12 * (1 - e));
  }

  /// FAILED — one quiet static ring; the decaying shake on the control
  /// (see [ConnectShake]) carries the drama, the halo stays composed.
  void _errorRing(Canvas canvas, Size size, Offset c, Color col) {
    canvas.drawCircle(
      c,
      size.width * _ring,
      _stroke(col.withValues(alpha: 0.30))..strokeWidth = 2,
    );
  }

  /// The breathing soft glow shared by the walking states.
  void _softGlow(Canvas canvas, Size size, Offset c, Color col,
      {required double alpha}) {
    if (alpha <= 0) return;
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        c,
        size.width * 0.34,
        [col.withValues(alpha: alpha), col.withValues(alpha: 0)],
      );
    canvas.drawCircle(c, size.width * 0.34, glow);
  }

  /// The dashed circle the march/hold states share (28 dashes; rotation
  /// moves them around the ring).
  void _dashedRing(
    Canvas canvas,
    Size size,
    Offset c,
    Color color, {
    required double rotation,
  }) {
    const n = 28;
    const gap = 2 * math.pi / n;
    const sweep = gap * 0.45;
    final radius = size.width * _ring;
    final rect = Rect.fromCircle(center: c, radius: radius);
    final paint = _stroke(color)..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final start = i * gap + rotation;
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectHaloPainter old) =>
      old.state != state ||
      old.phase != phase ||
      old.breath != breath ||
      old.shot != shot ||
      old.directionSign != directionSign ||
      old.hideWalkStates != hideWalkStates ||
      old.hideConnectedAura != hideConnectedAura;
}

/// The FAILED state's decaying shake for the CONTROL itself (logo or
/// button): the offset profile [1, −0.8, 0.6, −0.3, 0.15, 0] × the style's
/// amplitude, ~55 ms per step (≈330 ms total) — fired ONCE on the edge to
/// failed, horizontally (direction-neutral: RTL needs no mirroring).
class ConnectShake extends StatefulWidget {
  const ConnectShake({
    super.key,
    required this.state,
    required this.style,
    required this.child,
  });

  final VpnState state;
  final MotionStyle style;
  final Widget child;

  @override
  State<ConnectShake> createState() => _ConnectShakeState();
}

class _ConnectShakeState extends State<ConnectShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 330),
  );

  @override
  void didUpdateWidget(covariant ConnectShake old) {
    super.didUpdateWidget(old);
    // EDGE only — a rebuild that re-notifies with the same failed state
    // (the stats tick, a second failure caption build) never re-shakes.
    if (widget.state == VpnState.failed &&
        old.state != VpnState.failed &&
        widget.style != MotionStyle.off &&
        widget.style.recipe.shakeAmpRef > 0) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  /// The decaying profile —TweenSequence weights are equal (55 ms steps).
  static TweenSequence<double> _profile(double amp) => TweenSequence<double>([
        for (final step in const [1.0, -0.8, 0.6, -0.3, 0.15, 0.0])
          TweenSequenceItem(
            tween: Tween(begin: step * amp, end: step * amp),
            weight: 1,
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final amp = widget.style.recipe.shakeAmpRef * s;
    if (amp <= 0) return widget.child;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, kid) {
        if (!_shake.isAnimating && _shake.value == 0) return kid!;
        final dx = _profile(amp).evaluate(
          AlwaysStoppedAnimation(_shake.value),
        );
        return Transform.translate(offset: Offset(dx, 0), child: kid);
      },
      child: widget.child,
    );
  }
}
