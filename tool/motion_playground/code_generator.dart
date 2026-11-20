import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/core/motion.dart';

enum PlaygroundTarget {
  connectControl,
  stateHalo,
  customWidget,
}

enum MotionEffect {
  fade,
  scale,
  slide,
  rotate,
  blur,
  fadeScale,
}

enum CurvePreset {
  easeOutCubic,
  easeOutBack,
  easeInOutCubic,
  easeOutQuint,
  elasticOut,
  linear,
}

extension PlaygroundTargetLabel on PlaygroundTarget {
  String get label => switch (this) {
        PlaygroundTarget.connectControl => 'دکمه اتصال واقعی',
        PlaygroundTarget.stateHalo => 'هاله وضعیت اتصال',
        PlaygroundTarget.customWidget => 'Widget اختصاصی',
      };
}

extension MotionEffectLabel on MotionEffect {
  String get label => switch (this) {
        MotionEffect.fade => 'محو شدن · Fade',
        MotionEffect.scale => 'بزرگ‌شدن · Scale',
        MotionEffect.slide => 'حرکت · Slide',
        MotionEffect.rotate => 'چرخش · Rotate',
        MotionEffect.blur => 'رفع تاری · Blur',
        MotionEffect.fadeScale => 'Fade + Scale',
      };
}

extension CurvePresetLabel on CurvePreset {
  String get label => switch (this) {
        CurvePreset.easeOutCubic => 'Ease Out Cubic',
        CurvePreset.easeOutBack => 'Ease Out Back',
        CurvePreset.easeInOutCubic => 'Ease In Out Cubic',
        CurvePreset.easeOutQuint => 'Ease Out Quint',
        CurvePreset.elasticOut => 'Elastic Out',
        CurvePreset.linear => 'Linear',
      };

  String get dartName => switch (this) {
        CurvePreset.easeOutCubic => 'easeOutCubic',
        CurvePreset.easeOutBack => 'easeOutBack',
        CurvePreset.easeInOutCubic => 'easeInOutCubic',
        CurvePreset.easeOutQuint => 'easeOutQuint',
        CurvePreset.elasticOut => 'elasticOut',
        CurvePreset.linear => 'linear',
      };
}

String generateMotionCode({
  required PlaygroundTarget target,
  required MotionStyle style,
  required VpnState state,
  required int durationMs,
  required CurvePreset curve,
  required MotionEffect effect,
  required double strength,
  required String widgetExpression,
}) {
  switch (target) {
    case PlaygroundTarget.connectControl:
      return _connectCode(style: style, state: state);
    case PlaygroundTarget.stateHalo:
      return _haloCode(style: style, state: state);
    case PlaygroundTarget.customWidget:
      return _customWidgetCode(
        durationMs: durationMs,
        curve: curve,
        effect: effect,
        strength: strength,
        widgetExpression: widgetExpression.trim().isEmpty
            ? 'const YourWidget()'
            : widgetExpression.trim(),
      );
  }
}

String _connectCode({
  required MotionStyle style,
  required VpnState state,
}) {
  final styleName = style.name;
  final stateName = state.name;
  return '''
import 'package:flutter/material.dart';

import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/widgets/connect_core.dart';
import 'package:aethone/features/home/widgets/glow_pill.dart';

Widget buildConnectMotion({
  required VoidCallback onTap,
}) {
  const style = MotionStyle.$styleName;
  const state = VpnState.$stateName;

  return SizedBox(
    width: 300,
    height: 300,
    child: Stack(
      alignment: Alignment.center,
      children: [
        ConnectHalo(
          state: state,
          style: style,
          size: 280,
        ),
        ConnectShake(
          state: state,
          style: style,
          child: ConnectButtonGlow(
            connected: state == VpnState.connected,
            state: state,
            style: style,
            duration: motionDuration(style, MotionDurations.state),
            curve: style.curve,
            onTap: onTap,
          ),
        ),
      ],
    ),
  );
}
''';
}

String _haloCode({
  required MotionStyle style,
  required VpnState state,
}) {
  final styleName = style.name;
  final stateName = state.name;
  return '''
import 'package:flutter/material.dart';

import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/widgets/connect_core.dart';

Widget buildConnectionHalo() {
  return SizedBox.square(
    dimension: 280,
    child: Stack(
      alignment: Alignment.center,
      children: [
        ConnectHalo(
          state: VpnState.$stateName,
          style: MotionStyle.$styleName,
          size: 280,
        ),
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF101A14),
            border: Border.all(
              color: const Color(0xFF1AD995),
              width: 1.4,
            ),
          ),
          child: const Text(
            'A',
            style: TextStyle(
              color: Color(0xFF1AD995),
              fontSize: 38,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
''';
}

String _customWidgetCode({
  required int durationMs,
  required CurvePreset curve,
  required MotionEffect effect,
  required double strength,
  required String widgetExpression,
}) {
  final safeStrength = strength.clamp(0.0, 1.0);
  final strengthCode = safeStrength.toStringAsFixed(2);
  final durationCode = durationMs.clamp(0, 10000);
  final curveName = curve.dartName;
  final uiImport = effect == MotionEffect.blur
      ? "import 'dart:ui' show ImageFilter;\n\n"
      : '';
  final body = switch (effect) {
    MotionEffect.fade => '''
      return Opacity(
        opacity: progress,
        child: visibleChild,
      );''',
    MotionEffect.scale => '''
      final scale = 1.0 - ($strengthCode * 0.20) +
          ($strengthCode * 0.20 * progress);
      return Transform.scale(
        scale: scale,
        child: visibleChild,
      );''',
    MotionEffect.slide => '''
      return Transform.translate(
        offset: Offset(0, (1.0 - progress) * $strengthCode * 34),
        child: visibleChild,
      );''',
    MotionEffect.rotate => '''
      return Transform.rotate(
        angle: (1.0 - progress) * $strengthCode * 0.28,
        child: visibleChild,
      );''',
    MotionEffect.blur => '''
      final sigma = (1.0 - progress) * $strengthCode * 8;
      return ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
        ),
        child: visibleChild,
      );''',
    MotionEffect.fadeScale => '''
      final scale = 1.0 - ($strengthCode * 0.18) +
          ($strengthCode * 0.18 * progress);
      return Opacity(
        opacity: progress,
        child: Transform.scale(
          scale: scale,
          child: visibleChild,
        ),
      );''',
  };

  return '''
$uiImport
import 'package:flutter/material.dart';

// Add the import that defines the Widget expression used below.
Widget buildAnimatedWidget() {
  return TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0.0, end: 1.0),
    duration: const Duration(milliseconds: $durationCode),
    curve: Curves.$curveName,
    builder: (context, progress, child) {
      final visibleChild = child ?? const SizedBox.shrink();
$body
    },
    child: $widgetExpression,
  );
}
''';
}
