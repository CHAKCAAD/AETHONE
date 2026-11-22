/// The home "glow" family — status pill, Speed Test button and the look-2
/// circular connect button.
///
/// v5 (owner round 19, the «نمای 2» redesign) — all three compositions are
/// re-cut from the owner's NEW committed CSS (the ZIP frames «نمای 2-متصل»
/// and «نمای 2-قطع», 402×874 @3×):
///
/// Status pill («Group 8»/«لایه 1») — ONE solid gradient layer, 126×30 r9:
///   connected    linear-gradient(266.14deg, #2FF8B1 → #1AD995)
///                (right-light → left-deep; pixel-verified on the frame)
///   disconnected linear-gradient(180deg, #FF5B5E → #FF383C)
///   content: the Shield Tick glyph 20×20 + the 16px/600 label, both WHITE
///   («color: #FFFFFF»). The v4.11 three-layer halo stack + the soft green
///   under-shadow are RETIRED — the redesign pill is a single crisp chip.
///
/// Speed Test («Group 13») — three crisp layers, no blurred glow:
///   74×74 r32 rgba(26,217,149,.19) / 62×62 r27 rgba(26,217,149,.45) /
///   44×44 r17 #1AD995 + the Activity 4 glyph 28×28 in WHITE.
///   Disconnected («حالت قطع»): the SAME geometry on the idle family —
///   rgba(17,0,0,.19) / rgba(17,0,0,.45) / #363636 — the button stays on
///   screen in a dark, disabled pose (the old build hid it entirely).
///
/// Connect button («Group 45») — two crisp squircles:
///   «3» 160×160 r60 #FFFFFF (the base; themed dark-card at night)
///   «1» 108.17² r41, gradient 180deg #2FF8B1→#1AD995 (connected) /
///       #FF5B5E→#FF383C (disconnected)
///   Off glyph 48×48, 3.5px WHITE in both states.
///   The v4.33 236-glow/halo/mid alpha stack is RETIRED.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_state.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';

/// One concentric layer of a glow group.
class LayerSpec {
  const LayerSpec({
    required this.width,
    required this.height,
    required this.radius,
    required this.opacity,
    this.blurSigma = 0,
    this.dy = 0,
    this.color,
  });

  /// Size in design px (scaled by [LayerStack.scale] at paint time).
  final double width;
  final double height;
  final double radius;
  final double opacity;

  /// Gaussian sigma (design px); 0 = crisp.
  final double blurSigma;

  /// Vertical offset from the group center (design px) — used by soft
  /// under-shadows.
  final double dy;

  /// v5 — an optional per-layer color override (the idle speed button's
  /// #363636 core over its rgba(17,0,0,α) halo/mid needs a second ink).
  /// Null = the stack's own [LayerStack.color].
  final Color? color;
}

/// Paints a stack of concentric rounded-rect layers, bottom-first.
class LayerStack extends StatelessWidget {
  const LayerStack({
    super.key,
    required this.scale,
    required this.color,
    required this.layers,
    this.clipOut = false,
  });

  final double scale;
  final Color color;

  /// Bottom-first layer list. The widget's layout size is taken from the
  /// LAST (topmost/core) layer.
  final List<LayerSpec> layers;

  /// When true, blur spill beyond the widget bounds is clipped.
  final bool clipOut;

  @override
  Widget build(BuildContext context) {
    final core = layers.last;
    return CustomPaint(
      size: Size(core.width * scale, core.height * scale),
      painter: _LayerStackPainter(this),
    );
  }
}

class _LayerStackPainter extends CustomPainter {
  _LayerStackPainter(this.widget);

  final LayerStack widget;

  @override
  void paint(Canvas canvas, Size size) {
    final s = widget.scale;
    final center = Offset(size.width / 2, size.height / 2);
    for (final spec in widget.layers) {
      final rect = Rect.fromCenter(
        center: Offset(center.dx, center.dy + spec.dy * s),
        width: spec.width * s,
        height: spec.height * s,
      );
      final paint = Paint()
        ..color = (spec.color ?? widget.color).withValues(alpha: spec.opacity);
      if (spec.blurSigma > 0) {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          spec.blurSigma * s,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(spec.radius * s)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LayerStackPainter oldDelegate) =>
      oldDelegate.widget.color != widget.color ||
      oldDelegate.widget.scale != widget.scale ||
      oldDelegate.widget.layers != widget.layers;
}

/// Status pill — v5: one 126×30 r9 gradient chip (green connected / red
/// disconnected, crossfaded) with the WHITE Shield glyph + label. Content
/// row keeps the INHERITED (RTL) directionality — under the fa locale it
/// lays out like the reference frames: text visual-left, shield
/// visual-right.
///
/// The CONNECTING icon stays the set's Send glyph (v4.15 #6), Shield Cross
/// for disconnected/failed/reconnecting, Shield Tick when connected.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.state, required this.style});

  final VpnState state;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.quick);

    final connected = state == VpnState.connected;
    final (label, iconAsset) = switch (state) {
      VpnState.connected => (strings.statusConnected, AppAssets.iconShieldTick),
      VpnState.connecting => (strings.statusConnecting, AppAssets.iconSend),
      VpnState.reconnecting => (
        strings.statusReconnecting,
        AppAssets.iconShieldCross,
      ),
      VpnState.failed => (strings.statusFailed, AppAssets.iconShieldCross),
      _ => (strings.statusDisconnected, AppAssets.iconShieldCross),
    };

    return SizedBox(
      width: AethGeometry.pillWidth * s,
      height: AethGeometry.pillHeight * s,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AethRadius.pillCore * s),
        child: TweenAnimationBuilder<double>(
          // 0 = the red disconnected chip, 1 = the green connected one —
          // one tween drives the gradient's colors AND its axis (the green
          // sweep runs right→left at 266°, the red one top→bottom at 180°).
          tween: Tween(end: connected ? 1.0 : 0.0),
          duration: duration,
          curve: style.curve,
          builder: (context, t, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.lerp(
                  const Alignment(0, -1),
                  const Alignment(1, 0),
                  t,
                )!,
                end: Alignment.lerp(
                  const Alignment(0, 1),
                  const Alignment(-1, 0),
                  t,
                )!,
                colors: [
                  Color.lerp(
                    AethColors.pillRedFrom,
                    AethColors.pillGreenFrom,
                    t,
                  )!,
                  Color.lerp(
                    AethColors.pillRedTo,
                    AethColors.accentConnected,
                    t,
                  )!,
                ],
              ),
            ),
            child: Center(
              // FittedBox keeps any label (e.g. the longer «در حال اتصال»)
              // inside the 126-wide chip at ANY font.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Row(
                    key: ValueKey('pill-$label'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        iconAsset,
                        width: AethGeometry.pillIconSize * s,
                        height: AethGeometry.pillIconSize * s,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFFFFFFFF),
                          BlendMode.srcIn,
                        ),
                      ),
                      SizedBox(width: 8 * s),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w600,
                          fontSize: 16 * s,
                          height: 18 / 16,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Speed Test entry — v5 owner CSS «Group 13»: three crisp layers
/// (74 r32 α.19 / 62 r27 α.45 / 44 r17 solid) + the Activity 4 glyph 28×28
/// in WHITE. While DISCONNECTED the button keeps its geometry but flips to
/// the idle family (rgba(17,0,0,α) halo/mid + #363636 core) — the dark,
/// disabled pose of the «حالت قطع» frame (it no longer vanishes).
class SpeedTestButton extends StatelessWidget {
  const SpeedTestButton({
    super.key,
    required this.visible,
    required this.connected,
    required this.style,
    required this.onTap,
  });

  final bool visible;
  final bool connected;
  final MotionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.state);

    // Animated appearance (scale + fade). OFF style ⇒ instant.
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: duration,
      curve: style.curve,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        child: IgnorePointer(
          // v5: the button is on screen in BOTH states (the dark idle
          // pose), but only a live tunnel can run a test — taps are dead
          // until connected.
          ignoring: !visible || !connected,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: AethGeometry.speedGroupSize * s,
              height: AethGeometry.speedGroupSize * s,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // v5 layers, bottom→top: 74 α0.19 / 62 α0.45 / 44 solid —
                  // the accent family when connected, the CSS idle family
                  // (rgba(17,0,0,α) + the #363636 core) when not, one
                  // crossfade tween driving every ink.
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: connected ? 1.0 : 0.0),
                    duration: duration,
                    curve: style.curve,
                    builder: (context, t, _) => LayerStack(
                      scale: s,
                      color: AethColors.accentConnected,
                      layers: [
                        LayerSpec(
                          width: AethGeometry.speedGroupSize,
                          height: AethGeometry.speedGroupSize,
                          radius: AethRadius.speedHalo,
                          opacity: AethColors.pillHaloOpacity,
                          color: Color.lerp(
                            AethColors.speedIdleLayer,
                            AethColors.accentConnected,
                            t,
                          ),
                        ),
                        LayerSpec(
                          width: AethGeometry.speedMidSize,
                          height: AethGeometry.speedMidSize,
                          radius: AethRadius.speedMid,
                          opacity: AethColors.pillMidOpacity,
                          color: Color.lerp(
                            AethColors.speedIdleLayer,
                            AethColors.accentConnected,
                            t,
                          ),
                        ),
                        LayerSpec(
                          width: AethGeometry.speedCoreSize,
                          height: AethGeometry.speedCoreSize,
                          radius: AethRadius.speedCore,
                          opacity: 1,
                          color: Color.lerp(
                            AethColors.speedIdleCore,
                            AethColors.accentConnected,
                            t,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SvgPicture.asset(
                    AppAssets.iconActivity4,
                    width: AethGeometry.speedIconSize * s,
                    height: AethGeometry.speedIconSize * s,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      AethColors.speedIconRest, // WHITE — owner CSS vector
                      BlendMode.srcIn,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// v5 — the look-2 CONNECT button (the owner's new «Group 45»): the WHITE
/// 160×160 r60 base + the 108.17² r41 gradient core + the Off glyph 48×48
/// in WHITE. The gradient runs top→bottom in both states (green
/// #2FF8B1→#1AD995 connected, red #FF5B5E→#FF383C disconnected) and the
/// whole composition crossfades on the state edge. [scale] renders the
/// composition smaller (the look page's preview) without recomputing a
/// single layer.
class ConnectButtonGlow extends StatelessWidget {
  const ConnectButtonGlow({
    super.key,
    required this.connected,
    this.onTap,
    this.scale = 1.0,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeInOutCubic,
  });

  final bool connected;
  final VoidCallback? onTap;

  /// 1.0 = the full 160px composition (the home hero button); the wizard's
  /// look page passes [AethGeometry.obPreviewGroupSize] / 160.
  final double scale;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final k = s * scale;
    final size = AethGeometry.connectGroupSize * k;

    return _TouchFeedback(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // The WHITE base («3»: 160² r60) — themed (light #FFFFFF, night
            // the dark-card family), crossfaded with the core so the whole
            // button breathes on the state edge.
            TweenAnimationBuilder<double>(
              tween: Tween(end: connected ? 1.0 : 0.0),
              duration: duration,
              curve: curve,
              builder: (context, t, _) => DecoratedBox(
                decoration: BoxDecoration(
                  color: AethColors.connectBase,
                  borderRadius: BorderRadius.circular(
                    AethRadius.connectBase * k,
                  ),
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // The gradient core («1»: 108.17² r41, 180deg).
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(
                            AethColors.pillRedFrom,
                            AethColors.pillGreenFrom,
                            t,
                          )!,
                          Color.lerp(
                            AethColors.pillRedTo,
                            AethColors.accentConnected,
                            t,
                          )!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        AethRadius.connectCore * k,
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: AethGeometry.connectCoreSize * k,
                    ),
                  ),
                ),
              ),
            ),
            // The Off glyph — 48×48, WHITE in both states (owner CSS
            // «border: 3.5px solid #FFFFFF»).
            SvgPicture.asset(
              AppAssets.iconOff,
              width: AethGeometry.connectIconSize * k,
              height: AethGeometry.connectIconSize * k,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                Color(0xFFFFFFFF),
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short, subtle touch feedback (scale 0.97 + opacity — report table 14,
/// max ~120 ms). Never delays the action.
class _TouchFeedback extends StatefulWidget {
  const _TouchFeedback({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_TouchFeedback> createState() => _TouchFeedbackState();
}

class _TouchFeedbackState extends State<_TouchFeedback> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}
