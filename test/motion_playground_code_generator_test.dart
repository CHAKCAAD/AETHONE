import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/core/motion.dart';
import '../tool/motion_playground/code_generator.dart';

void main() {
  group('Motion Playground code generator', () {
    test('exports the real AETHONE connect composition', () {
      final output = generateMotionCode(
        target: PlaygroundTarget.connectControl,
        style: MotionStyle.dynamic,
        state: VpnState.connecting,
        durationMs: 640,
        curve: CurvePreset.easeOutBack,
        effect: MotionEffect.fadeScale,
        strength: 0.75,
        widgetExpression: 'const ExampleWidget()',
      );

      expect(output, contains('ConnectHalo('));
      expect(output, contains('ConnectShake('));
      expect(output, contains('ConnectButtonGlow('));
      expect(output, contains('MotionStyle.dynamic'));
      expect(output, contains('VpnState.connecting'));
      expect(output, contains('MotionDurations.state'));
    });

    test('exports the selected connection halo and state', () {
      final output = generateMotionCode(
        target: PlaygroundTarget.stateHalo,
        style: MotionStyle.smooth,
        state: VpnState.reconnecting,
        durationMs: 500,
        curve: CurvePreset.easeOutQuint,
        effect: MotionEffect.blur,
        strength: 0.5,
        widgetExpression: 'const ExampleWidget()',
      );

      expect(output, contains('ConnectHalo('));
      expect(output, contains('MotionStyle.smooth'));
      expect(output, contains('VpnState.reconnecting'));
    });

    test('exports custom widget expression, timing and curve', () {
      final output = generateMotionCode(
        target: PlaygroundTarget.customWidget,
        style: MotionStyle.standard,
        state: VpnState.disconnected,
        durationMs: 760,
        curve: CurvePreset.elasticOut,
        effect: MotionEffect.rotate,
        strength: 0.6,
        widgetExpression: 'const FrostedCard()',
      );

      expect(output, contains('Duration(milliseconds: 760)'));
      expect(output, contains('Curves.elasticOut'));
      expect(output, contains('const FrostedCard()'));
      expect(output, contains('Transform.rotate('));
      expect(output, contains('visibleChild'));
      expect(output, isNot(contains("import 'dart:ui' show ImageFilter;")));
    });

    test('adds the ImageFilter import only for blur', () {
      final output = generateMotionCode(
        target: PlaygroundTarget.customWidget,
        style: MotionStyle.standard,
        state: VpnState.disconnected,
        durationMs: 440,
        curve: CurvePreset.easeOutCubic,
        effect: MotionEffect.blur,
        strength: 0.9,
        widgetExpression: 'const BlurCard()',
      );

      expect(output, contains("import 'dart:ui' show ImageFilter;"));
      expect(output, contains('ImageFilter.blur('));
    });

    test('uses a safe default when the widget expression is empty', () {
      final output = generateMotionCode(
        target: PlaygroundTarget.customWidget,
        style: MotionStyle.standard,
        state: VpnState.disconnected,
        durationMs: 300,
        curve: CurvePreset.linear,
        effect: MotionEffect.fade,
        strength: 0.4,
        widgetExpression: '  ',
      );

      expect(output, contains('child: const YourWidget(),'));
    });
  });
}
