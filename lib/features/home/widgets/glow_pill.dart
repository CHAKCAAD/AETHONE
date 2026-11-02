/// The signature 4-layer "glow pill" — the shared structure of the status
/// pill, the Speed Test button and (in a circular variant) the look-2 center
/// connect button. Geometry/opacities are the Figma CSS from the owner's
/// prompt (Rectangle 26/22/21/20), pixel-verified in the phase-1 report:
///
///  glow  : 162×60, bg α0.53, blur 57, radius 32 (+ box-shadows)
///  halo  : 140×38, bg α0.19, radius 13
///  mid   : 132.88×32, bg α0.45, radius 11
///  core  : 125.76×26, bg α1.0, radius 9 — content (text + icon)
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';

/// A pill whose 4 stacked layers fade between [colorOff] and [colorOn]
/// according to [active]. [child] is rendered on the core layer.
class GlowPill extends StatelessWidget {
  const GlowPill({
    super.key,
    required this.active,
    required this.onTap,
    required this.child,
    this.width,
    this.height,
    this.colorOn = AethColors.accentConnected,
    this.colorOff = AethColors.statusDisconnected,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeInOutCubic,
  })  : assert(width == null || width > 0),
        assert(height == null || height > 0);

  /// Reference size 162×60; when null, sizes derive from [MediaQuery] scale.
  final double? width;
  final double? height;

  final bool active;
  final VoidCallback? onTap;
  final Widget child;
  final Color colorOn;
  final Color colorOff;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final w = width ?? AethGeometry.pillWidth * s;
    final h = height ?? AethGeometry.pillHeight * s;
    final color = active ? colorOn : colorOff;

    return _TouchFeedback(
      onTap: onTap,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Layer 1 — glow (α0.53, blur 57, radius 32) + Figma box-shadows.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: AethGeometry.pillShadow,
                  borderRadius: BorderRadius.circular(AethRadius.pillGlow * s),
                ),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: AethGeometry.pillBlur * s,
                    sigmaY: AethGeometry.pillBlur * s,
                  ),
                  child: _FadingLayer(
                    color: color,
                    opacity: AethColors.pillGlowOpacity,
                    borderRadius:
                        BorderRadius.circular(AethRadius.pillGlow * s),
                    duration: duration,
                    curve: curve,
                  ),
                ),
              ),
            ),
            // Layer 2 — halo (140×38, α0.19, r13) ⇒ 0.864 × pill size.
            _FadingLayer(
              size: Size(w * 0.864, h * 0.633),
              color: color,
              opacity: AethColors.pillHaloOpacity,
              borderRadius: BorderRadius.circular(AethRadius.pillHalo * s),
              duration: duration,
              curve: curve,
            ),
            // Layer 3 — mid (132.88×32, α0.45, r11) ⇒ 0.820 × pill size.
            _FadingLayer(
              size: Size(w * 0.820, h * 0.533),
              color: color,
              opacity: AethColors.pillMidOpacity,
              borderRadius: BorderRadius.circular(AethRadius.pillMid * s),
              duration: duration,
              curve: curve,
            ),
            // Layer 4 — core (125.76×26, α1.0, r9) ⇒ 0.776 × pill size.
            _FadingLayer(
              size: Size(w * 0.776, h * 0.433),
              color: color,
              opacity: 1,
              borderRadius: BorderRadius.circular(AethRadius.pillCore * s),
              duration: duration,
              curve: curve,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular variant of the same 4-layer structure (look-2 center button).
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
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: AethGeometry.pillBlur * s,
                sigmaY: AethGeometry.pillBlur * s,
              ),
              child: _FadingLayer(
                size: Size.square(d * 1.42),
                color: color,
                opacity: AethColors.pillGlowOpacity,
                borderRadius: BorderRadius.circular(d * 0.71),
                duration: duration,
                curve: curve,
              ),
            ),
            _FadingLayer(
              size: Size.square(d * 1.24),
              color: color,
              opacity: AethColors.pillHaloOpacity,
              borderRadius: BorderRadius.circular(d * 0.62),
              duration: duration,
              curve: curve,
            ),
            _FadingLayer(
              size: Size.square(d * 1.12),
              color: color,
              opacity: AethColors.pillMidOpacity,
              borderRadius: BorderRadius.circular(d * 0.56),
              duration: duration,
              curve: curve,
            ),
            _FadingLayer(
              size: Size.square(d),
              color: color,
              opacity: 1,
              borderRadius: BorderRadius.circular(d * 0.5),
              duration: duration,
              curve: curve,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _FadingLayer extends StatelessWidget {
  const _FadingLayer({
    required this.color,
    required this.opacity,
    required this.borderRadius,
    required this.duration,
    required this.curve,
    this.size,
    this.child,
  });

  final Size? size;
  final Color color;
  final double opacity;
  final BorderRadius borderRadius;
  final Duration duration;
  final Curve curve;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final box = child != null
        ? Container(
            width: size?.width,
            height: size?.height,
            alignment: Alignment.center,
            child: child,
          )
        : SizedBox(
            width: size?.width,
            height: size?.height,
          );
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: color.withValues(alpha: 0), end: color),
      duration: duration,
      curve: curve,
      builder: (context, value, childBox) => Container(
        width: size?.width,
        height: size?.height,
        decoration: BoxDecoration(
          color: value?.withValues(alpha: opacity),
          borderRadius: borderRadius,
        ),
        child: childBox,
      ),
      child: box,
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
