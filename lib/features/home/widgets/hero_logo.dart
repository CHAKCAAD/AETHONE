/// Look-1 hero: the central app logo. Disconnected: the artwork as committed
/// (correlation 0.997 against the reference frame). Connected: rotated 58°
/// COUNTER-CLOCKWISE (v4.17 — owner: «آیکون وسط صفحه باید بعد از اتصال ۵۸
/// درجه به سمت چپ بچرخد در حال حاظر برعکس به سمت راست میچرخد» — the
/// v4.15 clockwise 57° pose was the wrong DIRECTION; the magnitude now
/// lands on the owner's 58°).
///
/// v4.15 — owner home round #1 gave the turn its dedicated 600 ms ease curve
/// («کاملا نرم») — kept (the landing/settle tempo).
///
/// CONNECTING (the flutterfx round): the walk's motion language on this
/// look is now the SPARK LOADER — the logo itself marches in 90° steps,
/// each an easeOutBack swing with a rest between ([SparkLoaderSpin], the
/// flutterfx `particles-spark-loader` port; owner: «هرچی انیمیشن برای
/// حالت در حال اتصال نمای ۱ دکمه اتصال در نظر گرفته بودی حذف کن و به
/// جاش از چرخش لوگو Spark Loader … استفاده کن»). The retired walk
/// vocabulary (ignition ring / held dashes / march / seek arcs) is
/// suppressed on THIS look only — [HomeScreen] hides the halo's walk
/// states in look 1; look 2 keeps them. When the walk resolves, the logo
/// settles onto the resting pose by the shortest equivalent turn.
///
/// CONNECTED IDLE: the logo breathes — a slow, gentle scale pulse (its own
/// clock, the recipe's hero tempo) — while the shared halo breathes with
/// it. MotionStyle.off disables the idle motion (accessibility rule) — the
/// state change animations stay.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/fx/spark_loader.dart';
import '../../../core/motion.dart';

class HeroLogo extends StatelessWidget {
  const HeroLogo({
    super.key,
    required this.connected,
    required this.style,
    this.sparking = false,
  });

  final bool connected;
  final MotionStyle style;

  /// The engine-walk flag (starting / waiting / connecting / reconnecting):
  /// the spark-march runs while true. [HomeScreen] derives it from the REAL
  /// [VpnState] — nothing here fakes a walk.
  final bool sparking;

  /// v4.17 pose: 58° to the LEFT (counter-clockwise) on connection —
  /// Flutter `turns` are clockwise-positive, so LEFT is negative.
  static const double _connectedTurns = -58 / 360;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.heroSize * s;
    final duration = motionDuration(style, MotionDurations.state);
    final curve = style.curve;

    final Widget logo = SparkLoaderSpin(
      active: sparking,
      style: style,
      restTurns: connected ? _connectedTurns : 0.0,
      // v5.2 (owner round 21) — the look-1 logo tint carries the
      // redesign's own GREEN/RED gradient («گردینت سبز و قرمز … برای
      // المان های سبز و قرمز رنگ دیگه هم اعمال کن»): a ShaderMask in
      // srcIn mode tints the white logo art exactly like the old flat
      // ColorFilter did, but with the sweep. ONE tween drives the whole
      // crossfade — the stops lerp between the two gradients, so t = 0
      // paints the flat red pair and t = 1 the flat green pair, and every
      // frame between is a true gradient mix.
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: connected ? 1.0 : 0.0),
        duration: duration,
        curve: curve,
        builder: (context, t, _) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                AethColors.redStops[0],
                AethColors.greenStops[0],
                t,
              )!,
              Color.lerp(
                AethColors.redStops[1],
                AethColors.greenStops[1],
                t,
              )!,
            ],
          ).createShader(bounds),
          child: SvgPicture.asset(
            AppAssets.appLogoNeutralWhite,
            width: size,
            height: size,
          ),
        ),
      ),
    );

    // Connected idle life: a gentle breathing pulse of the logo itself.
    return _BreathingWhileConnected(
      connected: connected,
      style: style,
      child: logo,
    );
  }
}

/// Slow scale pulse that runs ONLY while [connected] — v4.25: the
/// tempo and depth are the STYLE'S OWN ([MotionRecipe.heroBreathMs]/
/// heroBreathAmp): TIDE breathes slower and deeper (3.4 s ±3%), SPRING
/// quicker and livelier (2.0 s ±2.5%), BLINK barely moves (±0.8%).
/// With MotionStyle.off the child renders statically (accessibility
/// clamp).
class _BreathingWhileConnected extends StatefulWidget {
  const _BreathingWhileConnected({
    required this.connected,
    required this.style,
    required this.child,
  });

  final bool connected;
  final MotionStyle style;
  final Widget child;

  @override
  State<_BreathingWhileConnected> createState() =>
      _BreathingWhileConnectedState();
}

class _BreathingWhileConnectedState extends State<_BreathingWhileConnected>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.style.recipe.heroBreathMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.connected && widget.style != MotionStyle.off) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _BreathingWhileConnected old) {
    super.didUpdateWidget(old);
    // v4.25 — a style change mid-session retunes the breath.
    _controller.duration =
        Duration(milliseconds: widget.style.recipe.heroBreathMs);
    final animate = widget.connected && widget.style != MotionStyle.off;
    if (animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!animate) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected || widget.style == MotionStyle.off) {
      return widget.child;
    }
    final amp = widget.style.recipe.heroBreathAmp;
    if (amp <= 0) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(scale: 1.0 + amp * t, child: child);
      },
      child: widget.child,
    );
  }
}

/// Scanning halo behind the central icon while the engine is trying to
/// connect (owner defect #10: «حین اتصال ... پشت آیکون وسط صفحه باید
/// انیمیشن نمایش داده شود»). Two expanding, fading rings + a breathing
/// core glow — pure Flutter animation, repeats until the state leaves the
/// connecting walk.
class ScanRings extends StatefulWidget {
  const ScanRings({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<ScanRings> createState() => _ScanRingsState();
}

class _ScanRingsState extends State<ScanRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ring(t, startScale: 0.85, endScale: 1.65, baseOpacity: 0.40),
              _ring(
                (t + 0.5) % 1.0,
                startScale: 0.85,
                endScale: 1.65,
                baseOpacity: 0.28,
              ),
              // Breathing core glow hugging the icon.
              Transform.scale(
                scale: 0.72 + 0.06 * (0.5 - (t - 0.5).abs()) * 2,
                child: Container(
                  width: widget.size * 0.62,
                  height: widget.size * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ring(
    double t, {
    required double startScale,
    required double endScale,
    required double baseOpacity,
  }) {
    final eased = Curves.easeOutCubic.transform(t);
    final scale = startScale + (endScale - startScale) * eased;
    final opacity = baseOpacity * (1 - eased);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size * 0.62,
        height: widget.size * 0.62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.color.withValues(alpha: opacity),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}
