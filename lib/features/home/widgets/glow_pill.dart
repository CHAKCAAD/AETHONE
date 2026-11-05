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
        ..color = widget.color.withValues(alpha: spec.opacity);
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
          LayerStack(
            scale: s,
            color: accent,
            layers: const [
              LayerSpec(
                width: AethGeometry.pillWidth,
                height: AethGeometry.pillHeight,
                radius: AethRadius.pillHalo,
                opacity: AethColors.pillHaloOpacity,
              ),
              LayerSpec(
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
                  LayerStack(
                    scale: s,
                    color: AethColors.accentConnected,
                    layers: const [
                      LayerSpec(
                        width: AethGeometry.speedGroupSize,
                        height: AethGeometry.speedGroupSize,
                        radius: AethRadius.speedGlow,
                        opacity: AethGeometry.speedGlowOpacity,
                        blurSigma: AethGeometry.speedGlowBlur,
                      ),
                      LayerSpec(
                        width: AethGeometry.speedHaloSize,
                        height: AethGeometry.speedHaloSize,
                        radius: AethRadius.speedHalo,
                        opacity: AethColors.pillHaloOpacity,
                      ),
                      LayerSpec(
                        width: AethGeometry.speedMidSize,
                        height: AethGeometry.speedMidSize,
                        radius: AethRadius.speedMid,
                        opacity: AethColors.pillMidOpacity,
                      ),
                      LayerSpec(
                        width: AethGeometry.speedCoreSize,
                        height: AethGeometry.speedCoreSize,
                        radius: AethRadius.speedCore,
                        opacity: 1,
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

/// v4.33 — the look-2 CONNECT button (owner round 9): the owner's own
/// CSS composition «Group 45» — four concentric layers, the outermost a
/// CIRCULAR blurred glow, the inner three SQUIRCLES (the old all-circle
/// GlowCircle is retired by decree: «این دکمه رو هم در صفحه اصلی و هم در
/// این صفحه بد طراحی کردی»):
///   glow : 236×236,  r120, α0.53, blur 57 — the soft green/red bloom
///   halo : 181.92²,  r69,  α0.19
///   mid  : 152.42²,  r62,  α0.45
///   core : 108.17²,  r41,  solid — the Off glyph 48×48 on top
///   (#0D5138 stroke on the green core, #75160F on the red one).
/// Both states share the geometry (the frames agree: «identical shapes,
/// color only») — green when connected, red when disconnected, colors
/// crossfaded. [scale] renders the whole composition smaller (the look
/// page's preview) without recomputing a single layer.
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

  /// 1.0 = the full 236px composition (the home hero button); the wizard's
  /// look page passes [AethGeometry.obPreviewGroupSize] / 236.
  final double scale;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final k = s * scale;
    final accent =
        connected ? AethColors.accentConnected : AethColors.statusDisconnected;
    final iconOn =
        connected ? AethColors.onConnectCore : AethColors.onPillDisconnected;

    // The tap target covers the WHOLE composition (glow included) — the
    // v4.13 halo-taps-too decree carried over from the old circle.
    return _TouchFeedback(
      onTap: onTap,
      child: SizedBox(
        width: AethGeometry.connectGroupSize * k,
        height: AethGeometry.connectGroupSize * k,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // The four layers, bottom→top — ONE crossfaded color drives
            // them all (green ↔ red), the owner's own opacities/radii.
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: connected
                    ? AethColors.statusDisconnected
                    : AethColors.accentConnected,
                end: accent,
              ),
              duration: duration,
              curve: curve,
              builder: (context, color, _) => LayerStack(
                scale: k,
                color: color ?? accent,
                layers: const [
                  LayerSpec(
                    width: AethGeometry.connectGroupSize,
                    height: AethGeometry.connectGroupSize,
                    radius: AethRadius.connectGlow,
                    opacity: AethColors.pillGlowOpacity,
                    blurSigma: AethGeometry.connectBlur,
                  ),
                  LayerSpec(
                    width: AethGeometry.connectHaloSize,
                    height: AethGeometry.connectHaloSize,
                    radius: AethRadius.connectHalo,
                    opacity: AethColors.pillHaloOpacity,
                  ),
                  LayerSpec(
                    width: AethGeometry.connectMidSize,
                    height: AethGeometry.connectMidSize,
                    radius: AethRadius.connectMid,
                    opacity: AethColors.pillMidOpacity,
                  ),
                  LayerSpec(
                    width: AethGeometry.connectCoreSize,
                    height: AethGeometry.connectCoreSize,
                    radius: AethRadius.connectCore,
                    opacity: 1,
                  ),
                ],
              ),
            ),
            // The Off glyph — 48×48, stroke crossfaded with the state.
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: connected
                    ? AethColors.onPillDisconnected
                    : AethColors.onConnectCore,
                end: iconOn,
              ),
              duration: duration,
              curve: curve,
              builder: (context, color, _) => SvgPicture.asset(
                AppAssets.iconOff,
                width: AethGeometry.connectIconSize * k,
                height: AethGeometry.connectIconSize * k,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  color ?? iconOn,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short, subtle touch feedback (scale 0.97 + opacity — report table 14,
/// max ~120 ms). Never delays the action. Used with onTap == null by the
/// swipe-only connect surfaces (defect #11).
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
