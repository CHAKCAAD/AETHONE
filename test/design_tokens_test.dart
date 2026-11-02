import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/core/design_tokens.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/connection/transport_modes.dart';

/// Locks the evidence-locked token values (report tables 7/8/15 + table 11).
/// If a test here fails, a token was changed without a design decision —
/// do NOT "fix" the test to match the new value.
void main() {
  group('colors (report table 7)', () {
    test('owner-declared values win over pixel drift', () {
      expect(AethColors.bgScreen, const Color(0xFF141C16));
      expect(AethColors.accentConnected, const Color(0xFF1AD995));
      expect(AethColors.statusDisconnected, const Color(0xFFEA2323));
      expect(AethColors.onPillDisconnected, const Color(0xFF75160F));
      expect(AethColors.onPillConnected, const Color(0xFF123E2B));
      expect(AethColors.goldAccent, const Color(0xFF997A35));
      expect(AethColors.statDownBg, const Color(0xFF0A4F33));
      expect(AethColors.statUpBg, const Color(0xFF3A1C1C));
      expect(AethColors.statUpBorder, const Color(0xFF652325));
      expect(AethColors.textPrimary, const Color(0xFFFFFFFF));
      expect(AethColors.textSecondary, const Color(0xFF8E8E93));
    });

    test('pill opacities are the Figma CSS values', () {
      expect(AethColors.pillGlowOpacity, 0.53);
      expect(AethColors.pillMidOpacity, 0.45);
      expect(AethColors.pillHaloOpacity, 0.19);
    });
  });

  group('geometry (report table 8)', () {
    test('reference frame and key sizes', () {
      expect(AethGeometry.refWidth, 402);
      expect(AethGeometry.refHeight, 874);
      expect(AethGeometry.heroSize, 164);
      expect(AethGeometry.connectButtonSize, 48);
      expect(AethGeometry.connectButtonRise, 72);
      expect(AethGeometry.centerButtonSize, 112);
      expect(AethGeometry.pillWidth, 162);
      expect(AethGeometry.pillHeight, 60);
      expect(AethGeometry.pillBlur, 57);
    });

    test('pill radii are the Figma Rectangle 26/22/21/20 values', () {
      expect(AethRadius.pillGlow, 32);
      expect(AethRadius.pillHalo, 13);
      expect(AethRadius.pillMid, 11);
      expect(AethRadius.pillCore, 9);
    });
  });

  group('motion styles (report table 15)', () {
    test('duration multipliers', () {
      expect(MotionStyle.standard.durationMultiplier, 1.0);
      expect(MotionStyle.smooth.durationMultiplier, 1.5);
      expect(MotionStyle.dynamic.durationMultiplier, 0.8);
      expect(MotionStyle.minimal.durationMultiplier, 0.4);
      expect(MotionStyle.off.durationMultiplier, 0.0);
    });

    test('OFF collapses durations to zero', () {
      expect(motionDuration(MotionStyle.off, 400), Duration.zero);
    });

    test('reduce-motion clamp', () {
      expect(clampForReduceMotion(MotionStyle.smooth), MotionStyle.minimal);
      expect(clampForReduceMotion(MotionStyle.dynamic), MotionStyle.minimal);
      expect(clampForReduceMotion(MotionStyle.off), MotionStyle.off);
    });
  });

  group('transport-mode endpoint table (report table 11, code-evidenced)', () {
    test('normal protocols share the 1819 --bind listener', () {
      for (final mode in [
        TransportModes.masque,
        TransportModes.wireguard,
        TransportModes.gool,
        TransportModes.goolClassic,
        TransportModes.mim,
      ]) {
        expect(mode.socksEndpoint.port, 1819, reason: mode.label);
        expect(mode.tcpOnly, isFalse, reason: mode.label);
        expect(mode.exitKind, ExitKind.warp, reason: mode.label);
      }
    });

    test('AETHER→TOR exits via --tor-bind 1820', () {
      expect(TransportModes.torChain.socksEndpoint.port, 1820);
      expect(TransportModes.torChain.exitKind, ExitKind.torExit);
      expect(TransportModes.torChain.tcpOnly, isTrue);
    });

    test('AETHER→PSIPHON exits via --psiphon-bind 1821', () {
      expect(TransportModes.psiphonChain.socksEndpoint.port, 1821);
      expect(TransportModes.psiphonChain.exitKind, ExitKind.psiphonExit);
      expect(TransportModes.psiphonChain.tcpOnly, isTrue);
    });

    test('reverse/only variants stay on 1819 and are TCP-only', () {
      expect(TransportModes.torReverse.socksEndpoint.port, 1819);
      expect(TransportModes.torOnly.socksEndpoint.port, 1819);
      expect(TransportModes.psiphonReverse.socksEndpoint.port, 1819);
      expect(TransportModes.psiphonOnly.socksEndpoint.port, 1819);
      expect(TransportModes.torReverse.tcpOnly, isTrue);
      expect(TransportModes.torOnly.tcpOnly, isTrue);
      expect(TransportModes.psiphonReverse.tcpOnly, isTrue);
      expect(TransportModes.psiphonOnly.tcpOnly, isTrue);
    });

    test('all 11 modes are in the table', () {
      expect(TransportModes.all.length, 11);
    });
  });
}
