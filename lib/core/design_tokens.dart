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

  /// Dark cards (protocol / stats) — report `≈#1C1F22`, locked by golden test.
  static const Color cardDark = Color(0xFF1C1F22);

  /// Protocol-logo box inside the protocol card (crop read `#2D323D`).
  static const Color cardIconBg = Color(0xFF2D323D);

  /// Chevron on the protocol card (crop read coral-red `#E74C5B`).
  static const Color chevronRed = Color(0xFFE74C5B);

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

  /// Dark cards — report: 16–25px, Flutter default 20.
  static const double card = 20;
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

  /// Speed-test button: 48×40 @ (176,536) — only visible when connected.
  static const double speedButtonWidth = 48;
  static const double speedButtonHeight = 40;

  /// Look-2 center connect button core: 112px circle (144,328)–(256,432).
  static const double centerButtonSize = 112;

  /// Status pill group: 162×60 (Figma CSS `Group 12`).
  static const double pillWidth = 162;
  static const double pillHeight = 60;

  /// Figma CSS: `filter: blur(57px)` on the glow layer (a.k.a. "layer blur 114").
  static const double pillBlur = 57;

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

  /// Page horizontal padding (report: ≈20px, range 16–24).
  static const double pageHPadding = 20;

  /// Flags: squircle 100×100 assets; center carousel item is larger.
  static const double flagSize = 100;
}
