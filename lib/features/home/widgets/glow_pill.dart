/// The layered "glow" structures — status pill, Speed Test button and the
/// look-2 circular connect button.
///
/// v4.11 — rebuilt from the OWNER'S OWN Figma CSS (defect reports #3/#4):
///
/// Status pill (Group 8) — exactly THREE background layers, all concentric:
///   halo : 140×38,     rgba(26,217,149,0.19), r13
///   mid  : 132.88×32,  rgba(26,217,149,0.45), r11
///   core : 125.76×26,  #1AD995 solid,          r9
/// plus ONE soft blurred accent shadow underneath the group («یک سایه محو
/// سبز رنگ زیرش مثل سایه سبز پترن‌های پس زمینه»). The old 4th blurred blob
/// layer (162×60 α0.53) that "broke the button shape" is REMOVED.
///
/// Speed Test (Group 11) — the same look as the status pill, 4 layers:
///   glow : 96×96, α0.53, r32, gaussian blur (the halo)
///   halo : 74×74, α0.19, r32
///   mid  : 62×62, α0.45, r27
///   core : 44×44, #1AD995 solid, r17 — Activity 4 icon 28×28 #0D4D36
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_state.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../core/fx/tap_ripple.dart';
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
    this.gradient,
  });

  /// Size in design px (scaled by [LayerStack.scale] at paint time).
  final double width;
  final double height;
  final double radius;
  final double opacity;

  /// Gaussian sigma (design px); 0 = crisp.
  final double blurSigma;

  /// Vertical offset from the group center (design px) — used by the soft
  /// under-shadow.
  final double dy;

  /// v4.45 — the owner's standing green/red 180° gradients («گرادینت سبز /
  /// قرمز روی همه عناصر هم‌رنگ»): when present the layer paints the
  /// GRADIENT (opacity still applies) instead of [LayerStack.color].
  final LinearGradient? gradient;
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
      final paint = Paint();
      final gradient = spec.gradient;
      if (gradient != null) {
        // v4.45 — the standing gradient core: the shader carries the
        // colors, the layer opacity still modulates it.
        paint.shader = gradient.createShader(rect);
        paint.color = Colors.white.withValues(alpha: spec.opacity);
      } else {
        paint.color = widget.color.withValues(alpha: spec.opacity);
      }
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

/// Status pill: 3 background layers + soft under-shadow + «غیرفعال/متصل»
/// content. Text/icon colors from the Figma CSS: #75160F on red, #123E2B on
/// green. Content row keeps the INHERITED (RTL) directionality — under the
/// fa locale it lays out exactly like the reference frames: text visual-left,
/// shield visual-right.
///
/// v4.15 — owner home round #6: «آیکون دکمه وضعیت اتصال در حالت در حال اتصال
/// باید آیکون Send 1.svg درون پوشه آیکون های اپ باشد» — the CONNECTING
/// icon is the set's Send glyph (the v4.14 Shield Cross stays for the
/// disconnected/failed/reconnecting states, Shield Tick when connected).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.state, required this.style});

  final VpnState state;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.quick);
    final curve = style.curve;

    final connected = state == VpnState.connected;
    final (label, iconAsset) = switch (state) {
      VpnState.connected => (strings.statusConnected, AppAssets.iconShieldTick),
      // v4.15 #6 — the connecting icon is the set's own Send 1.svg.
      VpnState.connecting => (strings.statusConnecting, AppAssets.iconSend),
      VpnState.reconnecting => (
        strings.statusReconnecting,
        AppAssets.iconShieldCross,
      ),
      VpnState.failed => (strings.statusFailed, AppAssets.iconShieldCross),
      _ => (strings.statusDisconnected, AppAssets.iconShieldCross),
    };
    final accent = connected
        ? AethColors.accentConnected
        : AethColors.statusDisconnected;
    final fg = connected
        ? AethColors.onPillConnected
        : AethColors.onPillDisconnected;

    return SizedBox(
      width: AethGeometry.pillWidth * s,
      height: AethGeometry.pillHeight * s,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft blurred accent shadow UNDER the group (owner defect #3;
          // v4.13 round-4 #5: lighter + blurrier, covering a wider area but
          // never a huge blob), painted beneath the three crisp layers.
          LayerStack(
            scale: s,
            color: accent,
            layers: const [
              LayerSpec(
                width: AethGeometry.pillShadowW,
                height: AethGeometry.pillShadowH,
                radius: AethGeometry.pillShadowRadius,
                opacity: AethGeometry.pillShadowAlpha,
                blurSigma: AethGeometry.pillShadowBlur,
                dy: AethGeometry.pillShadowOffsetY,
              ),
            ],
          ),
          // The three crisp background layers (bottom→top), owner CSS.
          // v4.45 — the CORE rides the standing green/red 180° gradient
          // (the owner's «گرادینت روی همه عناصر هم‌رنگ» decree).
          LayerStack(
            scale: s,
            color: accent,
            layers: [
              const LayerSpec(
                width: AethGeometry.pillWidth,
                height: AethGeometry.pillHeight,
                radius: AethRadius.pillHalo,
                opacity: AethColors.pillHaloOpacity,
              ),
              const LayerSpec(
                width: AethGeometry.pillMidWidth,
                height: AethGeometry.pillMidHeight,
                radius: AethRadius.pillMid,
                opacity: AethColors.pillMidOpacity,
              ),
              LayerSpec(
                width: AethGeometry.pillCoreWidth,
                height: AethGeometry.pillCoreHeight,
                radius: AethRadius.pillCore,
                opacity: 1,
                gradient: connected
                    ? AethColors.accentConnectedGradient
                    : AethColors.statusDisconnectedGradient,
              ),
            ],
          ),
          // Content, color-crossfaded on state change (defect #5: the state
          // change must be animated). FittedBox keeps any label (e.g. the
          // longer «در حال اتصال») inside the 125.76 core at ANY font.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: connected
                    ? AethColors.onPillDisconnected
                    : AethColors.onPillConnected,
                end: fg,
              ),
              duration: duration,
              curve: curve,
              builder: (context, color, _) => AnimatedSwitcher(
                duration: duration,
                child: Row(
                  key: ValueKey('pill-$label'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      iconAsset,
                      width: 18 * s,
                      height: 18 * s,
                      colorFilter: ColorFilter.mode(
                        color ?? fg,
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
                        color: color ?? fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Speed Test entry — owner CSS Group 11: the SAME layered look as the
/// status pill (4 layers + halo), core 44×44 with the Activity 4 icon in
/// #0D4D36. Visible ONLY when connected (pixel-verified: absent in every
/// disconnected reference frame).
class SpeedTestButton extends StatelessWidget {
  const SpeedTestButton({
    super.key,
    required this.visible,
    required this.style,
    required this.onTap,
  });

  final bool visible;
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
          ignoring: !visible,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: AethGeometry.speedGroupSize * s,
              height: AethGeometry.speedGroupSize * s,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Owner CSS layers, bottom→top: glow 96 (blurred halo —
                  // v4.13: lighter α.34 + σ24 so the halo spreads wider and
                  // softer, owner round-4 #5), 74 α0.19, 62 α0.45, 44 solid.
                  // v4.45 — the 44 core rides the standing green gradient
                  // (the «گرادینت روی همه عناصر هم‌رنگ» decree).
                  LayerStack(
                    scale: s,
                    color: AethColors.accentConnected,
                    layers: [
                      const LayerSpec(
                        width: AethGeometry.speedGroupSize,
                        height: AethGeometry.speedGroupSize,
                        radius: AethRadius.speedGlow,
                        opacity: AethGeometry.speedGlowOpacity,
                        blurSigma: AethGeometry.speedGlowBlur,
                      ),
                      const LayerSpec(
                        width: AethGeometry.speedHaloSize,
                        height: AethGeometry.speedHaloSize,
                        radius: AethRadius.speedHalo,
                        opacity: AethColors.pillHaloOpacity,
                      ),
                      const LayerSpec(
                        width: AethGeometry.speedMidSize,
                        height: AethGeometry.speedMidSize,
                        radius: AethRadius.speedMid,
                        opacity: AethColors.pillMidOpacity,
                      ),
                      const LayerSpec(
                        width: AethGeometry.speedCoreSize,
                        height: AethGeometry.speedCoreSize,
                        radius: AethRadius.speedCore,
                        opacity: 1,
                        gradient: AethColors.accentConnectedGradient,
                      ),
                    ],
                  ),
                  SvgPicture.asset(
                    AppAssets.iconActivity4,
                    width: AethGeometry.speedIconSize * s,
                    height: AethGeometry.speedIconSize * s,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      AethColors.onCoreDark,
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

/// v4.45 — the look-2 CONNECT button, the owner's NEW three-layer CSS
/// composition (it replaces the v4.33 four-layer «Group 45» — the blurred
/// glow layer is retired): three concentric SQUIRCLES over the standing
/// green/red GRADIENT core —
///   outer : 160×160,  r62, rgba(47,248,177,0.16) / rgba(234,35,35,0.16)
///   mid   : 132×132,  r46, rgba(47,248,177,0.45) / rgba(234,35,35,0.45)
///   core  : 108.17²,  r41, 180° #2FF8B1→#1AD995 / #FF5B5E→#FF383C
///   glyph : the Off.svg 48×48, WHITE in BOTH states (the owner's own
///           spec — the old #0D5138/#75160F inks are retired).
/// Both states share the geometry — colors crossfade on one tween.
/// [scale] renders the whole composition smaller (the look page's
/// preview) without recomputing a single layer. v4.45: the tap NO LONGER
/// moves or shrinks the button (owner: «دکمه اتصال موقع کلیک نباید تکون
/// بخوره») — the flutterfx ripple burst alone answers the finger.
class ConnectButtonGlow extends StatefulWidget {
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
  /// look page passes [AethGeometry.obPreviewGroupSize] /
  /// [AethGeometry.connectGroupSize].
  final double scale;
  final Duration duration;
  final Curve curve;

  @override
  State<ConnectButtonGlow> createState() => _ConnectButtonGlowState();
}

/// v4.43 — owns the [TapRippleController] so the flutterfx tap-ripple
/// burst (owner-approved new dependency round) survives the rebuilds.
class _ConnectButtonGlowState extends State<ConnectButtonGlow> {
  final TapRippleController _ripple = TapRippleController();

  @override
  void dispose() {
    _ripple.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.connected;
    final onTap = widget.onTap;
    final duration = widget.duration;
    final curve = widget.curve;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final k = s * widget.scale;

    // The owner's new layer colors: the translucent rings ride the
    // gradient's own family — #2FF8B1 (the green gradient's light stop)
    // when connected, the standing #EA2323 red when disconnected.
    final ringColor = connected
        ? AethColors.accentConnectedGradient.colors.first
        : AethColors.statusDisconnected;
    final coreGradient = connected
        ? AethColors.accentConnectedGradient
        : AethColors.statusDisconnectedGradient;
    final otherGradient = connected
        ? AethColors.statusDisconnectedGradient
        : AethColors.accentConnectedGradient;

    // The tap target covers the WHOLE composition (outer layer included)
    // — the v4.13 halo-taps-too decree carried over. The ripple burst
    // rides the same gesture (v4.43, the flutterfx port) and is now the
    // ONLY tap feedback: the button itself never moves or shrinks (the
    // owner's v4.45 decree).
    return _TouchFeedback(
      onTap: onTap,
      ripple: _ripple,
      pressScale: false,
      child: SizedBox(
        width: AethGeometry.connectGroupSize * k,
        height: AethGeometry.connectGroupSize * k,
        child: TapRipple(
          controller: _ripple,
          color: ringColor,
          duration:
              Duration(milliseconds: (duration.inMilliseconds * 1.5).round()),
          curve: curve,
          // Ring one is born on the core's own edge (108.17/2 design px,
          // style-scaled) and dies just past the outer layer (×2.2).
          baseRadius: AethGeometry.connectCoreSize * k / 2,
          maxScale: 2.2,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // The three layers, bottom→top — one crossfaded color drives
              // the translucent rings, the core crossfades between the two
              // standing gradients.
              TweenAnimationBuilder<double>(
                tween: Tween(end: connected ? 1.0 : 0.0),
                duration: duration,
                curve: curve,
                builder: (context, t, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    // outer : 160² r62 α0.16
                    Container(
                      width: AethGeometry.connectOuterSize * k,
                      height: AethGeometry.connectOuterSize * k,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          AethColors.statusDisconnected,
                          AethColors.accentConnectedGradient.colors.first,
                          t,
                        )!.withValues(alpha: AethColors.connectOuterOpacity),
                        borderRadius: BorderRadius.circular(
                          AethRadius.connectOuter * k,
                        ),
                      ),
                    ),
                    // mid : 132² r46 α0.45
                    Container(
                      width: AethGeometry.connectMidSize * k,
                      height: AethGeometry.connectMidSize * k,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          AethColors.statusDisconnected,
                          AethColors.accentConnectedGradient.colors.first,
                          t,
                        )!.withValues(alpha: AethColors.pillMidOpacity),
                        borderRadius: BorderRadius.circular(
                          AethRadius.connectMid * k,
                        ),
                      ),
                    ),
                    // core : 108.17² r41, the standing gradient
                    Container(
                      width: AethGeometry.connectCoreSize * k,
                      height: AethGeometry.connectCoreSize * k,
                      decoration: BoxDecoration(
                        gradient: LinearGradient.lerp(
                          otherGradient,
                          coreGradient,
                          t,
                        ),
                        borderRadius: BorderRadius.circular(
                          AethRadius.connectCore * k,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // The Off glyph — 48×48, WHITE in both states (the owner's
              // new spec; the icon file's own stroke carries the weight).
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
      ),
    );
  }
}

/// Short, subtle touch feedback (scale 0.97 + opacity — report table 14,
/// max ~120 ms). Never delays the action. Used with onTap == null by the
/// swipe-only connect surfaces (defect #11). v4.45 — [pressScale] lets a
/// surface opt OUT of the scale/opacity squeeze (the look-2 connect
/// button: the owner decreed it must NOT move on tap — the ripple burst
/// is its only feedback).
class _TouchFeedback extends StatefulWidget {
  const _TouchFeedback({
    required this.onTap,
    required this.child,
    this.ripple,
    this.pressScale = true,
  });

  final VoidCallback? onTap;

  /// v4.43 — optional flutterfx tap-ripple handle: when present, every
  /// tap-down spawns a ring burst at the finger's position. Pure
  /// decoration — the action fires on its own schedule, never delayed.
  final TapRippleController? ripple;

  /// Whether the press squeeze (scale 0.97 + opacity) plays. The look-2
  /// connect button passes false (v4.45).
  final bool pressScale;

  final Widget child;

  @override
  State<_TouchFeedback> createState() => _TouchFeedbackState();
}

class _TouchFeedbackState extends State<_TouchFeedback> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final squeeze = widget.pressScale && _pressed;
    return GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (details) {
              // The burst is born the moment the finger LANDS (the
              // flutterfx ripple's whole point) — inside the same
              // gesture that drives the press feedback and the action.
              widget.ripple?.tapAt(details.localPosition);
              if (widget.pressScale) setState(() => _pressed = true);
            },
      onTapCancel: widget.onTap == null || !widget.pressScale
          ? null
          : () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null || !widget.pressScale
          ? null
          : (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: squeeze ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: squeeze ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}
