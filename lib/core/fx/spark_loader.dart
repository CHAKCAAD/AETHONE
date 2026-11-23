/// Spark loader spin — the connecting-state logo rotation (flutterfx port).
///
/// RESTORED (owner round 23: «انیمیشن دکمه اتصال وسط صفحه در نمای 1 حین
/// تلاش برای اتصال رو چرا حذف کردی؟ برشگردون به حالت قبل، از انیمیشن
/// Spark Loader ریپو flutterfx_widgets استفاده شده بود») — the round-22
/// stillness decree that deleted this file is REVERTED for the WALK
/// states: the connected-state stillness stands (no breathing, no shimmer),
/// but the engine's walk toward a session owns the spark march again.
///
/// Adapted from flutterfx_widgets `particles-spark-loader` (MIT License,
/// Copyright (c) 2024 FlutterFX —
/// https://github.com/flutterfx/flutterfx_widgets): the original's
/// `StepRotatingShape` rotates a star in 90° STEPS — each step an
/// `easeOutBack` swing (a hair past the quarter turn, snapping back),
/// then a short rest, forever. This port keeps the STEP ENGINE verbatim
/// and wraps the OWNER'S OWN ARTWORK instead of the star: while the
/// engine walks toward a connection, look 1's central logo — the connect
/// surface — does the spark march (owner round: «به جاش از چرخش لوگو
/// Spark Loader برای دکمه اتصال وسط صفحه نمای ۱ استفاده کن»).
///
/// House rules (prompt §11.7 / report §10):
///  * the loop is STATE-DRIVEN — it runs only while [active] (the real
///    walk states); a stats re-notify with the same state never restarts
///    it, and the moment the state clears the loop stops dead;
///  * MotionStyle.off renders the child untouched;
///  * nothing here gates anything — the tap lives on the surfaces;
///  * a rotation has no reading order — RTL-safe by construction;
///  * the step/pause tempos ride [motionDuration], so each animation
///    personality (SILK/TIDE/SPRING/BLINK) keeps its own feel.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';

/// Rotates [child] in quarter-turn steps while [active]; settles to
/// [restTurns] (the caller's pose — e.g. look 1's connected −58°) when
/// the walk ends, taking the SHORTEST equivalent path from wherever the
/// march left the angle (a turn is a turn modulo 1 — the landing never
/// unwinds whole laps).
class SparkLoaderSpin extends StatefulWidget {
  const SparkLoaderSpin({
    super.key,
    required this.active,
    required this.style,
    this.restTurns = 0.0,
    this.stepTurns = 0.25,
    this.child,
  });

  /// The walk flag (starting / waiting / connecting / reconnecting).
  final bool active;

  /// The motion personality — tempos + the kill-switch.
  final MotionStyle style;

  /// The resting pose while NOT active (full turns; look 1 passes its
  /// connected −58/360).
  final double restTurns;

  /// One step's rotation, in turns (the flutterfx 90°).
  final double stepTurns;

  final Widget? child;

  @override
  State<SparkLoaderSpin> createState() => _SparkLoaderSpinState();
}

class _SparkLoaderSpinState extends State<SparkLoaderSpin>
    with SingleTickerProviderStateMixin {
  /// One step's clock: 0 → 1 across the swing, mapped through
  /// `easeOutBack` onto the quarter turn (the flutterfx engine).
  late final AnimationController _step = AnimationController(vsync: this);

  /// Whole steps already marched (each completed step folds in here, so
  /// `_step.value` always measures only the swing in flight).
  double _turns = 0;

  /// The landing pose's start angle, captured the moment the walk ends —
  /// the nearest turn-equivalent of the frozen march angle, so the settle
  /// tween travels at most half a turn. Seeded with the INITIAL rest pose
  /// so a cold start (or a resume into connected) never plays a phantom
  /// landing spin.
  double _landFrom = 0;

  /// Bumped whenever the loop must (re)start or die — a stale async
  /// continuation (a paused step, a rest delay) checks this and no-ops.
  int _generation = 0;

  /// The rest between steps, as a CANCELABLE timer — a bare
  /// `Future.delayed` would outlive dispose and trip the test binding's
  /// no-pending-timers invariant (and leak a timer on hot unmounts).
  Timer? _restTimer;

  Future<void> _rest(Duration d) {
    final completer = Completer<void>();
    _restTimer?.cancel();
    _restTimer = Timer(d, completer.complete);
    return completer.future;
  }

  /// The flutterfx step feel, ported verbatim.
  static const Curve _swing = Curves.easeOutBack;

  @override
  void initState() {
    super.initState();
    _landFrom = widget.restTurns;
    if (widget.active && widget.style != MotionStyle.off) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLoop());
    }
  }

  @override
  void didUpdateWidget(covariant SparkLoaderSpin old) {
    super.didUpdateWidget(old);
    final wasActive = old.active && old.style != MotionStyle.off;
    final isActive = widget.active && widget.style != MotionStyle.off;
    if (wasActive == isActive) return;
    if (isActive) {
      _startLoop();
    } else {
      _stopLoop();
    }
  }

  @override
  void dispose() {
    _generation++; // any in-flight continuation is now a no-op
    _restTimer?.cancel(); // never leave a pending rest timer behind
    _step.dispose();
    super.dispose();
  }

  /// The spark march: swing a quarter turn, rest, repeat — the flutterfx
  /// `_startNextRotation` chain, with epoch + mounted guards so a
  /// mid-flight stop never leaves a step half-scheduled.
  Future<void> _startLoop() async {
    final gen = ++_generation;
    _turns = _visualTurns(); // absorb any half-finished swing first
    _step.stop();
    _step.value = 0;
    while (mounted && gen == _generation) {
      final stepDuration = motionDuration(widget.style, _stepMs);
      if (stepDuration == Duration.zero) {
        // Unreachable for the styles that run the loop, but a zero-length
        // step + zero pause would spin the chain hot — clamp instead.
        _turns += widget.stepTurns;
        await _rest(const Duration(milliseconds: 240));
        if (!mounted || gen != _generation) return;
        continue;
      }
      _step.duration = stepDuration;
      try {
        await _step.forward().orCancel;
      } on TickerCanceled {
        return; // superseded or disposed — the new owner owns the loop
      }
      if (!mounted || gen != _generation) return;
      // Fold the completed swing in BEFORE the rest, so the pose never
      // snaps when the next step resets the controller.
      _turns += widget.stepTurns;
      _step.value = 0;
      await _rest(_pause());
      if (!mounted || gen != _generation) return;
    }
  }

  void _stopLoop() {
    _generation++; // kills the chain at its next checkpoint
    _restTimer?.cancel(); // a pending rest dies with the loop
    // Freeze exactly where the swing is — then land from the nearest
    // turn-equivalent of that pose (never unwind whole laps).
    _landFrom = _nearestEquivalent(_visualTurns(), widget.restTurns);
    _step.stop();
    _step.value = 0;
    _turns = 0;
    setState(() {});
  }

  /// Base tempos (ms, before style scaling): a 420 ms swing + a 240 ms
  /// rest ≈ the flutterfx demo's cadence scaled for the 164 dp hero logo.
  static const int _stepMs = 420;
  static const int _pauseMs = 240;

  Duration _pause() => motionDuration(widget.style, _pauseMs);

  /// The angle on screen right now (whole steps + the live swing).
  double _visualTurns() =>
      _turns + widget.stepTurns * _swing.transform(_step.value);

  /// The representative of [from] (mod 1) closest to [to] — a rotation by
  /// whole turns is pixel-identical, so the landing may snap the bookkeeping
  /// to any equivalent and only the residual travels.
  static double _nearestEquivalent(double from, double to) {
    final delta = from - to;
    return to + (delta - delta.roundToDouble());
  }

  @override
  Widget build(BuildContext context) {
    final kid = widget.child;
    if (kid == null) return const SizedBox.shrink();

    // The kill-switch identity: OFF never even mounts a rotation layer.
    if (widget.style == MotionStyle.off) return kid;

    if (!widget.active) {
      // The settle: one tween from the frozen march pose to the resting
      // pose, on the style's own «کاملا نرم» 600 ms base (the v4.15
      // dedicated turn tempo). While resting steady the tween is a no-op;
      // a rest-pose change (connected → disconnected) re-tweens on it.
      return TweenAnimationBuilder<double>(
        key: ValueKey('spark-land-$_landFrom'),
        tween: Tween(begin: _landFrom, end: widget.restTurns),
        duration: motionDuration(widget.style, 600),
        curve: widget.style.curve,
        builder: (context, t, child) =>
            Transform.rotate(angle: t * 2 * math.pi, child: child),
        child: kid,
      );
    }

    return AnimatedBuilder(
      animation: _step,
      builder: (context, child) => Transform.rotate(
        angle: 2 * math.pi * _visualTurns(),
        child: child,
      ),
      child: kid,
    );
  }
}
