/// v6.1 — THE SPLASH GATE («اسپلش اسکرین», owner: «یک اسپلش اسکرین با
/// بگراند سفید برای اپ ایجاد کنی و لوگو اپ رو هم در وسط صفحه با ابعاد
/// مناسب بزاری»): ONE cold-start beat over the app's first screen — the
/// owner's own green app icon ([AppAssets.appLogoConnected], the artwork
/// the launcher icon ships) centred on [AethColors.splashBg] at
/// [AethGeometry.splashLogoSize].
///
/// Two layers make the decree whole:
///
///  * the NATIVE launch screen (the white `launch_background` layer-list
///    and the API-31 `windowSplashScreen*` icon) covers the engine's cold
///    start with the SAME logo at ~the same size — always white, so
///    «برای اولین ورود باید بکگراند سفید داشته باشه» holds even before
///    Dart runs (the factory pick is LIGHT, ConnectionStore v6.1);
///
///  * THIS gate is what makes the splash follow the APP's own theme
///    («اگر کاربر خودش تم برنامه رو به نایت مود تغیر داد و یا روی حالت
///    خودکار قرارش داد اسپلش اسکرین هم باید از تم تبعیت کنه») — the
///    restored palette is already in [AethThemeSync] when the first frame
///    paints, so a night/auto pick renders the splash in the app's own
///    dark face while the light face stays pure white, seamless against
///    the native layer.
///
/// The beat rides ONE controller: a gentle ~5 % breath while the splash
/// holds, then a fade that reveals the (already-built) app underneath.
/// The master kill-switch ([MotionStyle.off]) mounts no overlay at all.
///
/// The overlay is [IgnorePointer]-wrapped and the child stays mounted
/// beneath it, so taps pass straight through while the beat plays — the
/// widget-test harnesses and impatient users alike never wait on art.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';

/// Wraps the app's first screen for the splash beat. Constructed ONCE at
/// the root (see `AethoneApp.home`); the overlay unmounts itself when its
/// clock completes and never returns for the life of the process.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.store, required this.child});

  final ConnectionStore store;
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  /// The single clock for the whole beat (null until the style resolves —
  /// and forever under the kill-switch).
  AnimationController? _clock;

  /// The beat is done — the overlay never mounts again.
  bool _done = false;

  /// Guards the one-time arm (didChangeDependencies can re-fire).
  bool _armed = false;

  /// The hold, in ms: the beat's still centre. NOT style-scaled — it is a
  /// pause, not motion; only the fade-out rides the style's own tempo.
  static const int _holdMs = 900;

  /// The breath's peak — the logo's slow rise while the splash holds.
  static const double _breathPeak = 0.05;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    // The style needs MediaQuery (the reduce-motion clamp), so it resolves
    // here rather than initState.
    final style = widget.store.effectiveMotionStyle(context);
    if (style == MotionStyle.off) {
      _done = true; // the kill-switch: no splash layer at all
      return;
    }
    final fade = motionDuration(style, MotionDurations.quick);
    _clock = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: _holdMs) + fade,
        )
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            setState(() => _done = true);
          }
        })
        ..forward();
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = _clock;
    if (_done || clock == null) return widget.child;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final totalMs = clock.duration!.inMilliseconds;
    final holdEnd = _holdMs / totalMs;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: clock,
              builder: (context, _) {
                final t = clock.value;
                // The breath [0, holdEnd): the logo's gentle rise; the
                // fade [holdEnd, 1]: the reveal.
                final breath =
                    Interval(0, holdEnd, curve: Curves.easeInOut).transform(t);
                final opacity =
                    1 - Interval(holdEnd, 1, curve: Curves.easeIn).transform(t);
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  // White face: dark glyphs; dark face: light glyphs —
                  // never the login's own light style leaking through.
                  value: AethThemeSync.light
                      ? SystemUiOverlayStyle.dark
                      : SystemUiOverlayStyle.light,
                  child: Opacity(
                    opacity: opacity,
                    child: ColoredBox(
                      key: const ValueKey('splash-surface'),
                      color: AethColors.splashBg,
                      child: Center(
                        child: Transform.scale(
                          scale: 1 + _breathPeak * breath,
                          child: SvgPicture.asset(
                            AppAssets.appLogoConnected,
                            width: AethGeometry.splashLogoSize * s,
                            height: AethGeometry.splashLogoSize * s,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
