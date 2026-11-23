/// The theme-switch CIRCULAR REVEAL host (v4.43).
///
/// The owner approved porting flutterfx_widgets' `splash-reveal` idea to
/// AETHONE's night ⇄ light switch: instead of only the shell's 420 ms
/// palette cross-fade, the OLD frame is screenshot the moment the tile is
/// tapped, the palette starts lerping underneath, and the screenshot is
/// wiped away by a growing circle centred ON THE TAPPED TILE — the new
/// theme pours out of the user's own finger.
///
/// Mechanics (the house-rules version of the flutterfx demo):
///  * the screenshot is captured BEFORE the store flips (async `toImage`
///    completes, THEN the toggle callback runs) — the overlay is always
///    honestly the OLD theme;
///  * the 420 ms palette lerp keeps running underneath exactly as before
///    (the reveal is ADDED on top, it replaces nothing);
///  * a process-wide slot ([ThemeReveal]) carries the request — the same
///    idiom as [AethThemeSync] — so every page's tile can reach the host
///    the shell mounts, without threading anything through the tree;
///  * style-gated: the OFF style (and a failed capture) falls back to the
///    plain cross-fade; SILK/TIDE/SPRING/BLINK each keep their curve and
///    their tempo;
///  * the AUTO schedule's 06:00/18:00 flips take the plain lerp (no finger
///    was involved — the reveal is a TOUCH affordance, not a state cue);
///  * a circle has no reading order — RTL-safe by construction.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../motion.dart';
import 'circular_reveal.dart';

/// The process-wide request slot every theme tile talks to (the
/// [AethThemeSync] idiom). No host mounted (bare test harnesses) → the
/// toggle runs plainly, nothing is lost.
abstract final class ThemeReveal {
  static _ThemeRevealHostState? _host;

  /// Wipe from [origin] (GLOBAL logical coordinates) while [apply] — the
  /// actual theme flip — runs once the old frame is captured.
  static void request({required Offset origin, required VoidCallback apply}) {
    final host = _host;
    if (host == null) {
      apply();
      return;
    }
    host.reveal(origin: origin, apply: apply);
  }
}

/// Mounts once in the shell: the app under a capture boundary, the reveal
/// overlay above it. `styleOf` re-reads the live motion style per request.
///
/// v5.2 (the round-21 theme-transition fix) — the host is a
/// [TickerProviderStateMixin], not a SingleTickerProviderStateMixin: it
/// vends ONE FRESH [AnimationController] per reveal, so over the State's
/// lifetime MANY tickers come and go. The Single- variant threw «multiple
/// tickers were created» on every toggle AFTER the first — the theme
/// still flipped (apply had already run) but the reveal died mid-flight
/// with an error flash, glitching the whole mode switch.
class ThemeRevealHost extends StatefulWidget {
  const ThemeRevealHost({
    super.key,
    required this.styleOf,
    required this.child,
  });

  final MotionStyle Function() styleOf;
  final Widget child;

  @override
  State<ThemeRevealHost> createState() => _ThemeRevealHostState();
}

class _ThemeRevealHostState extends State<ThemeRevealHost>
    with TickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();

  AnimationController? _wipe;
  ui.Image? _before;
  Offset? _origin;
  Size? _size;
  Curve? _curve;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    ThemeReveal._host = this;
  }

  @override
  void dispose() {
    ThemeReveal._host = null;
    _wipe?.dispose();
    _before?.dispose();
    super.dispose();
  }

  Future<void> reveal({
    required Offset origin,
    required VoidCallback apply,
  }) async {
    // v5.2 (the round-21 fix) — a capture already in flight must NEVER
    // swallow the flip: the theme still changes (plainly, under whatever
    // the running wipe is showing); only the SECOND reveal is dropped.
    // The first cut simply returned, and a quick double-tap lost the
    // second toggle entirely.
    if (_capturing) {
      apply();
      return;
    }
    final style = widget.styleOf();
    // The kill-switch and the BLINK-fast end of the scale keep the plain
    // cross-fade: the reveal is decoration, OFF means NO decoration.
    if (style == MotionStyle.off) {
      apply();
      return;
    }
    final ctx = _boundaryKey.currentContext;
    final boundary = ctx?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.attached) {
      apply();
      return;
    }

    // 1) Capture the OLD frame — must fully complete before the flip.
    _capturing = true;
    ui.Image? before;
    try {
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      before = await boundary.toImage(pixelRatio: ratio);
    } catch (_) {
      before = null; // capture failed → the plain lerp, never a broken flip
    }
    _capturing = false;
    if (!mounted) {
      before?.dispose();
      apply();
      return;
    }

    // 2) A second flip while a wipe is still running: finish that wipe
    //    instantly, then let the new capture proceed cleanly.
    _finishWipe();

    // 3) Flip the theme UNDER the overlay (the 420 ms lerp starts now).
    apply();
    if (before == null) return;

    // 4) Play the wipe over the fresh capture. v5.2 — the wipe rides the
    //    SAME 420 ms window as the palette lerp underneath (the first
    //    cut ran 650 ms: the colors finished at 420 while a patch of the
    //    OLD frame still covered the screen for another quarter second —
    //    the reveal read as lagging, «مشکل داره»). The circle completes
    //    exactly as the palette settles.
    setState(() {
      _before = before;
      _origin = origin;
      _size = boundary.size;
      _curve = style.curve;
    });
    _wipe = AnimationController(
      vsync: this,
      duration: motionDuration(style, 420),
    )
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finishWipe();
      })
      ..forward();
  }

  void _finishWipe() {
    _wipe?.dispose();
    _wipe = null;
    _before?.dispose();
    _before = null;
    _origin = null;
    _size = null;
    _curve = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final wipe = _wipe;
    final before = _before;
    final origin = _origin;
    return Stack(
      children: [
        RepaintBoundary(
          key: _boundaryKey,
          child: widget.child,
        ),
        if (wipe != null && before != null && origin != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipPath(
                clipper: CircularRevealClipper(
                  center: origin,
                  radius:
                      revealMaxRadius(_size ?? Size.zero, origin) *
                          (_curve ?? Curves.easeInOutCubic)
                              .transform(wipe.value),
                ),
                child: RawImage(
                  image: before,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
