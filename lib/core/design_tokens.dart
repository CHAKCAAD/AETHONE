/// AETHONE design tokens — extracted with three-layer evidence
/// (VLM image reads + programmatic pixel measurement + Figma CSS / asset XML)
/// in the phase-1 analysis report (tables 7 & 8). Do NOT change these values
/// ad hoc: where the owner-declared value and pixel measurement differ by ±1
/// (JPEG drift), the OWNER-DECLARED value wins (report §4 rule).
library;

import 'package:flutter/painting.dart';

/// Colors (report table 7). Every value cites its evidence.
abstract final class AethColors {
  /// Screen background — owner: `#141C16`; pixel-dominant read `#151C15`.
  static const Color bgScreen = Color(0xFF141C16);

  /// Connected / active accent — owner + pattern XML `#1AD995`.
  static const Color accentConnected = Color(0xFF1AD995);

  /// Disconnected / error accent — owner + pattern XML `#EA2323`.
  static const Color statusDisconnected = Color(0xFFEA2323);

  /// Text/icon color on the red status pill (Figma CSS `color: #75160F`).
  static const Color onPillDisconnected = Color(0xFF75160F);

  /// Text/icon color on the green status pill (Figma CSS + owner: `#123E2B`).
  static const Color onPillConnected = Color(0xFF123E2B);

  /// 4-layer pill opacities (Figma CSS Rectangle 26 / 22 / 21 / 20).
  static const double pillGlowOpacity = 0.53;
  static const double pillHaloOpacity = 0.19;
  static const double pillMidOpacity = 0.45;

  /// Gold accent on mim / gool-classic protocol icons (asset XML `#997A35`).
  static const Color goldAccent = Color(0xFF997A35);

  /// DOWN stat icon box (pixel, connected-look1 @ y=800).
  static const Color statDownBg = Color(0xFF0A4F33);

  /// UP stat icon box (pixel): background + border tones.
  static const Color statUpBg = Color(0xFF3A1C1C);
  static const Color statUpBorder = Color(0xFF652325);

  /// Dark cards (protocol / stats / FAB column) — pixel-measured on the four
  /// reference frames at y 706–845 (samples #0F1511/#0e1410/#101511; JPEG
  /// drift ±2): the cards are DARKER than the screen bg #141C16, not lighter.
  /// Re-measured 2026-11-02 against the device screenshots (v4.10 fix):
  /// the previous #1C1F22 read was wrong (it matched the JPEG noise floor).
  static const Color cardDark = Color(0xFF0F1511);

  /// Protocol-logo box inside the protocol card (crop read `#2D323D`).
  static const Color cardIconBg = Color(0xFF2D323D);

  /// Chevron on the protocol card (crop read coral-red `#E74C5B`).
  static const Color chevronRed = Color(0xFFE74C5B);

  /// Three tiny chevrons under the FAB column slot (crop read #C1303C-ish
  /// red, measured on حالت متصل-ضاهر1 at x 334–346, y 800–820).
  static const Color fabChevrons = Color(0xFFC1303C);

  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary/muted text (VLM reads `≈#8E8E93`).
  static const Color textSecondary = Color(0xFF8E8E93);
}

/// Shape & effect tokens (report table 8, Figma CSS).
abstract final class AethRadius {
  /// 4-layer pill radii: Rectangle 26 / 22 / 21 / 20.
  static const double pillGlow = 32;
  static const double pillHalo = 13;
  static const double pillMid = 11;
  static const double pillCore = 9;

  /// Dark cards — corner radius pixel-measured on the reference frames:
  /// protocol card (62 tall) and stat cards (65 tall) both ≈16.
  static const double card = 16;

  /// FAB column container radius (65×138 squircle column, ≈20).
  static const double fabColumn = 20;

  /// FAB squircle radius (48×48, ≈14).
  static const double fab = 14;
}

/// Geometry tokens. The reference frame is iPhone 17 Pro **402×874**; all
/// component sizes below are expressed in reference pixels and scaled by
/// `screenWidth / 402` at render time (report §4.2).
abstract final class AethGeometry {
  static const double refWidth = 402;
  static const double refHeight = 874;

  /// Hero logo: 164dp, top 292.7 (Figma XML) → horizontal center.
  static const double heroSize = 164;

  /// Bottom connect button (look 1): ~48×48 at (312,784)–(360,832);
  /// moves UP by 72px when connected (pixel-verified 784 → 712).
  static const double connectButtonSize = 48;
  static const double connectButtonRise = 72;

  /// Speed-test button: 43×43 @ (179,534)–(222,577) — only visible when
  /// connected (pixel-measured v4.10; the 48×40 read was the glow bbox).
  static const double speedButtonWidth = 44;
  static const double speedButtonHeight = 44;

  /// Look-2 center connect button core: 112px circle (144,328)–(256,432).
  static const double centerButtonSize = 112;

  /// Status pill group: 162×60 (Figma CSS `Group 12`).
  static const double pillWidth = 162;
  static const double pillHeight = 60;

  /// Figma CSS: `filter: blur(57px)` on the glow layer — but the reference
  /// FRAMES show a tight neon halo (~15–25px beyond the group box). Figma's
  /// blur value and a CSS blur(57px) disagree with the exported frames; the
  /// frames are the ground truth the user compares against, so the effective
  /// sigma is tuned to them (v4.10; measured glow profile on
  /// حالت متصل-ضاهر1: α 0.45→0.19 within 15px of the core).
  static const double pillBlur = 10;

  /// Figma CSS box-shadow of the pill group.
  static final List<BoxShadow> pillShadow = [
    const BoxShadow(
      color: Color(0x0D00091F), // rgba(0,9,31,0.05) 0 8 24
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
    const BoxShadow(
      color: Color(0x1AFFFFFF), // rgba(255,255,255,0.1) 0 1 1
      offset: Offset(0, 1),
      blurRadius: 1,
    ),
  ];

  /// Page horizontal padding — pixel-measured v4.10: bottom-panel cards span
  /// x 33–370 and the top-bar icons start at x 45 (= 33 + 12 IconButton
  /// padding) on the 402-wide reference frame.
  static const double pageHPadding = 33;

  /// Flags: 42×42 tiles, selected 52 (pixel-measured on the reference flags
  /// row y 161–212); carousel pitch 72. Assets are 256×256 PNGs.
  static const double flagSize = 42;
  static const double flagSizeSelected = 52;
  static const double flagPitch = 72;

  /// Bottom panel rows (pixel-measured v4.10, ref frame 402×874):
  /// protocol card y 706–768 (62), stat cards y 776–841 (65),
  /// FAB column x 305–370 (65×138), gap protocol→stats 8, cards→column 7.
  static const double protocolCardHeight = 62;
  static const double statCardHeight = 65;
  static const double statIconBoxSize = 48;
  static const double fabColumnWidth = 65;
  static const double fabColumnHeight = 138;
  static const double protocolLogoSize = 30;

  /// Vertical rhythm gaps (ref frame): topbar→location 21, location→flags 13,
  /// speed→pill 17, pill→panel 52, panel→bottom 30.
  static const double gapTopbarToLocation = 21;
  static const double gapLocationToFlags = 13;
  static const double gapSpeedToPill = 17;
  static const double gapPillToPanel = 52;
  static const double gapPanelToBottom = 30;

  /// Location row insets (ref: name x 95–130, ping ends x 324).
  static const double locationInsetStart = 95;
  static const double locationInsetEnd = 78;
}
