import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/core/design_tokens.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/connection/transport_modes.dart';

/// Locks the evidence-locked token values (report tables 7/8/15 + table 11).
/// If a test here fails, a token was changed without a design decision —
/// do NOT "fix" the test to match the new value.
void main() {
  group('colors (report table 7)', () {
    test('owner-declared values win over pixel drift', () {
      // v5.3 — the night slot is the owner's dark-mode round
      // («بکگراند کل صفحه 000000»); the slot starts at night in every
      // test (no shell tween ran).
      expect(AethColors.bgScreen, const Color(0xFF000000));
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
      // v2.1.0 — the scan-speed section is BACK on the protocol page
      // (the owner's decree, replacing the retired Firefox card): the
      // page rides the DEVICE frame constant again (the pattern
      // composition's own), the scan heading/pills sit at their
      // pre-PHASE-2 positions, and the pills end inside the frame
      // (776 + 36 = 812 < 874).
      expect(AethGeometry.protoPageHeadingScanTop, 736);
      expect(AethGeometry.protoPillTop, 776);
      expect(AethGeometry.protoPillTop + AethGeometry.protoPillH,
          lessThan(AethGeometry.refHeight));
      expect(AethGeometry.heroSize, 164);
      expect(AethGeometry.connectButtonSize, 48);
      expect(AethGeometry.connectButtonRise, 72);
      // v6 (owner round 23) — the look-2 connect button is the re-cut
      // THREE-layer «Group 45»: the 160² r62 outer · the 132² r46 mid ·
      // the 108.17² r41 gradient core + the 48×48 Off glyph.
      expect(AethGeometry.connectGroupSize, 160);
      expect(AethGeometry.connectMidSize, 132);
      expect(AethGeometry.connectCoreSize, 108.17);
      expect(AethGeometry.connectIconSize, 48);
      expect(AethRadius.connectBase, 62);
      expect(AethRadius.connectMid, 46);
      expect(AethRadius.connectCore, 41);
      // v5 — the pill is ONE gradient layer: 126×30 r9 («لایه 1»). v6:
      // LOOK 1's own chip is the three-layer 140×38 «Group 119».
      expect(AethGeometry.pillWidth, 126);
      expect(AethGeometry.pillHeight, 30);
      expect(AethGeometry.pillIconSize, 20);
      expect(AethGeometry.pillL1Width, 140);
      expect(AethGeometry.pillL1Height, 38);
      expect(AethGeometry.pillL1MidWidth, 132.88);
      expect(AethGeometry.pillL1MidHeight, 32);
      expect(AethGeometry.pillL1CoreWidth, 125.76);
      expect(AethGeometry.pillL1CoreHeight, 26);
      expect(AethRadius.pillL1Halo, 13);
      expect(AethRadius.pillL1Mid, 11);
      expect(AethRadius.pillL1Core, 9);
      // v5 — owner CSS «Group 13»: the home speed-test group is 74/62/44.
      expect(AethGeometry.speedGroupSize, 74);
      expect(AethGeometry.speedMidSize, 62);
      expect(AethGeometry.speedCoreSize, 44);
      expect(AethGeometry.speedIconSize, 28);
      // The speed-test PAGE's own start button keeps the v4.33 «Group 11»
      // 96-glow composition.
      expect(AethGeometry.speedStartGroupSize, 96);
      expect(AethGeometry.speedStartGlowOpacity, 0.53);
      expect(AethGeometry.speedStartGlowBlur, 57);
    });

    test('pill + speed radii are the owner CSS values (v5)', () {
      expect(AethRadius.pillCore, 9);
      expect(AethRadius.speedHalo, 32);
      expect(AethRadius.speedMid, 27);
      expect(AethRadius.speedCore, 17);
      expect(AethRadius.speedStartGlow, 32);
      expect(AethRadius.protocolCard, 17);
    });

    test('v5.2 — the green/red gradient pair rides every green/red element', () {
      // Owner round 21: «گردینت سبز و قرمزی که توی تغیرات جدید داریم رو
      // برای المان های سبز و قرمز رنگ دیگه هم اعمال کن» — the shared
      // stops ARE the redesign's own CSS values.
      expect(AethColors.greenStops, const [
        Color(0xFF2FF8B1),
        Color(0xFF1AD995),
      ]);
      expect(AethColors.redStops, const [
        Color(0xFFFF5B5E),
        Color(0xFFFF383C),
      ]);
      // The crossfade helper: t = 0 paints the flat solid (equal stops),
      // t = 1 the full gradient. v5.3 — the HOME button's idle core is
      // the palette getter now (light #363636 / night #424242).
      final rest = AethColors.homeIdleCore;
      expect(
        AethColors.lerpGradientStops(AethColors.greenStops, rest, 0),
        [rest, rest],
      );
      expect(
        AethColors.lerpGradientStops(AethColors.greenStops, rest, 1),
        AethColors.greenStops,
      );
      // The pattern ink is the palette's own lerped member (the round-21
      // theme-transition fix): the committed art's #110000 by day, WHITE
      // at night.
      expect(AethPal.light.patternInk, const Color(0xFF110000));
      expect(AethPal.night.patternInk, const Color(0xFFFFFFFF));
      expect(
        AethPal.lerp(AethPal.light, AethPal.night, 0.5).patternInk,
        Color.lerp(
          AethPal.light.patternInk,
          AethPal.night.patternInk,
          0.5,
        ),
      );
      // v4.45-fixed — the protocol sheet's OWN surface family: the panel
      // is a DEDICATED slot (light #FFFFFF / night #000000 — round 24:
      // the home screen's own page-bg pair) and can never collapse onto
      // the chip color (light #F4F4F4 / night #1C1C1C — the home card
      // family) — the improper-merge lesson, locked: the unselected
      // cards must always read AGAINST the panel in both modes.
      expect(AethPal.light.protoSheetBg, const Color(0xFFFFFFFF));
      expect(AethPal.night.protoSheetBg, const Color(0xFF000000));
      expect(AethPal.light.protoSheetChip, const Color(0xFFF4F4F4));
      expect(AethPal.night.protoSheetChip, const Color(0xFF1C1C1C));
      expect(
        AethPal.light.protoSheetBg,
        isNot(AethPal.light.protoSheetChip),
      );
      expect(
        AethPal.night.protoSheetBg,
        isNot(AethPal.night.protoSheetChip),
      );
      expect(
        AethPal.lerp(AethPal.light, AethPal.night, 0.5).protoSheetBg,
        Color.lerp(
          AethPal.light.protoSheetBg,
          AethPal.night.protoSheetBg,
          0.5,
        ),
      );
    });

    test('v5 «نمای 2» — the look-2 vertical rhythm and the panel crown', () {
      expect(AethGeometry.gapTopbarToPill, 114);
      expect(AethGeometry.gapHeroToPanel, 3);
      expect(AethGeometry.panelTopPad, 62);
      expect(AethGeometry.gapStatsToFlags, 27);
      expect(AethGeometry.gapFlagsToRow, 12);
      expect(AethGeometry.countryRowHeight, 45);
      expect(AethGeometry.gapRowToCard, 27);
      expect(AethGeometry.gapCardToBottom, 37);
      expect(AethGeometry.statGlyphSize, 36);
      expect(AethGeometry.statGlyphTextGap, 17);
      expect(AethGeometry.statGroupNudge, 6);
      // v5.3 — the owner's new CSS «Group 124»: the row spans x 32–348.
      expect(AethGeometry.statRowPadLeft, 32);
      expect(AethGeometry.statRowPadRight, 54);
      expect(AethGeometry.panelShadowSigma, 47.5);
      expect(AethGeometry.panelShadowDy, -16);
      expect(AethGeometry.panelShadowAlpha, 0.09);
      expect(AethGeometry.panelDipDepth, 30.0);
      // The new pattern canvases and their mockup-measured anchors.
      expect(AethGeometry.patternLeftCanvasW, 178);
      expect(AethGeometry.patternRightCanvasW, 198);
      expect(AethGeometry.patternLeftAspect, 1593 / 534);
      expect(AethGeometry.patternRightAspect, 1848 / 594);
      expect(AethGeometry.patternLeftAnchor, 0.27);
      expect(AethGeometry.patternRightAnchor, 0.485);
      // Round 24 — the look-1 anchors: each art's ink centre only a
      // LITTLE off the middle (the round-23 third-of-screen throw is
      // retired): left slightly BELOW (58 %), right slightly ABOVE (42 %).
      expect(AethGeometry.patternLeftAnchorLookOne, 0.58);
      expect(AethGeometry.patternRightAnchorLookOne, 0.42);
      // The circular flag clips + the «Ellipse 74» ring.
      expect(AethGeometry.flagRadiusFactor, 0.47);
      expect(AethGeometry.flagRingSize, 58);
      expect(AethGeometry.flagRingBorder, 4);
    });
  });

  group('v4.45 — the protocol BOTTOM SHEET geometry (owner CSS + frame)',
      () {
    test('panel, handle, cards, ring and the flutterfx entrance', () {
      // Panel 402×565, top corners r38, shadow 0 -6 64 rgba(0,0,0,0.09).
      expect(AethGeometry.protoSheetH, 565);
      expect(AethGeometry.protoSheetRadius, 38);
      expect(AethGeometry.protoSheetShadowDy, -6);
      expect(AethGeometry.protoSheetShadowBlur, 64);
      expect(AethGeometry.protoSheetShadowAlpha, 0.09);
      // Handle 97×8, 17 below the top edge.
      expect(AethGeometry.protoSheetHandleW, 97);
      expect(AethGeometry.protoSheetHandleH, 8);
      expect(AethGeometry.protoSheetHandleTop, 17);
      // Cards 159×67 r17, 17 gaps, 33 inset, first row 53 below the top.
      expect(AethGeometry.protoSheetCardW, 159);
      expect(AethGeometry.protoSheetCardH, 67);
      expect(AethGeometry.protoSheetCardRadius, 17);
      expect(AethGeometry.protoSheetCardGap, 17);
      expect(AethGeometry.protoSheetInset, 33);
      expect(AethGeometry.protoSheetGridTop, 53);
      // The 2×6 grid arithmetic closes on the 402 frame.
      expect(
        AethGeometry.protoSheetInset * 2 +
            AethGeometry.protoSheetCardW * 2 +
            AethGeometry.protoSheetCardGap,
        lessThanOrEqualTo(AethGeometry.refWidth),
      );
      // The selected card: the 4px rgba(26,217,149,0.4) ring.
      expect(AethGeometry.protoSheetCardBorder, 4);
      expect(AethGeometry.protoSheetCardRingAlpha, 0.4);
      // The flutterfx entrance recipe: home scale 0.85, rise 24, r16.
      expect(AethGeometry.protoSheetMainScale, 0.85);
      expect(AethGeometry.protoSheetMainRise, 24);
      expect(AethGeometry.protoSheetMainRadius, 16);
      // The dimming barrier (the flutterfx recipe: black54 × 0.7).
      expect(AethGeometry.protoSheetBarrierAlpha, 0.38);
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

    test('the aether family kept its 11 modes; firefox makes 12', () {
      // v2.1.0 — the Firefox engine mode is RETIRED: exactly the 11
      // aether modes remain (regression guard).
      expect(TransportModes.all.length, 11);
    });
  });
}
