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
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, spec.blurSigma * s);
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
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.state,
    required this.style,
  });

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
      VpnState.connected =>
        (strings.statusConnected, AppAssets.iconShieldTick),
      VpnState.connecting => (strings.statusConnecting, AppAssets.iconShieldCross),
      VpnState.reconnecting =>
        (strings.statusReconnecting, AppAssets.iconShieldCross),
      VpnState.failed => (strings.statusFailed, AppAssets.iconShieldCross),
      _ => (strings.statusDisconnected, AppAssets.iconShieldCross),
    };
    final accent =
        connected ? AethColors.accentConnected : AethColors.statusDisconnected;
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
          // Soft blurred accent shadow UNDER the group (owner defect #3),
          // painted beneath the three crisp layers.
          LayerStack(
            scale: s,
            color: accent,
            layers: const [
              LayerSpec(
                width: AethGeometry.pillWidth,
                height: AethGeometry.pillHeight,
                radius: AethRadius.pillHalo,
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

          ),        ],
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
                  // Owner CSS layers, bottom→top: glow 96 (blurred halo),
                  // 74 α0.19, 62 α0.45, 44 solid — all concentric.
                  LayerStack(
                    scale: s,
                    color: AethColors.accentConnected,
                    layers: const [
                      LayerSpec(
                        width: AethGeometry.speedGroupSize,
                        height: AethGeometry.speedGroupSize,
                        radius: AethRadius.speedGlow,
                        opacity: AethColors.pillGlowOpacity,
                        blurSigma: AethGeometry.pillBlur,
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

/// Circular variant of the layered structure (look-2 center connect button).
class GlowCircle extends StatelessWidget {
  const GlowCircle({
    super.key,
    required this.active,
    required this.onTap,
    required this.child,
    this.diameter,
    this.colorOn = AethColors.accentConnected,
    this.colorOff = AethColors.statusDisconnected,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeInOutCubic,
  });

  final bool active;
  final VoidCallback? onTap;
  final Widget child;
  final double? diameter;
  final Color colorOn;
  final Color colorOff;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final d = diameter ?? AethGeometry.centerButtonSize * s;
    final color = active ? colorOn : colorOff;

    return _TouchFeedback(
      onTap: onTap,
      child: SizedBox(
        width: d,
        height: d,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            LayerStack(
              scale: s,
              color: color,
              layers: [
                LayerSpec(
                  width: d / s * 1.42,
                  height: d / s * 1.42,
                  radius: d / s * 0.71,
                  opacity: AethColors.pillGlowOpacity,
                  blurSigma: AethGeometry.pillBlur,
                ),
                LayerSpec(
                  width: d / s * 1.24,
                  height: d / s * 1.24,
                  radius: d / s * 0.62,
                  opacity: AethColors.pillHaloOpacity,
                ),
                LayerSpec(
                  width: d / s * 1.12,
                  height: d / s * 1.12,
                  radius: d / s * 0.56,
                  opacity: AethColors.pillMidOpacity,
                ),
                LayerSpec(
                  width: d / s,
                  height: d / s,
                  radius: d / s * 0.5,
                  opacity: 1,
                ),
              ],
            ),
            child,
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
