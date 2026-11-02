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

  /// Top-bar icon tiles — owner Figma CSS «Rectangle 9»: 50x50, #0F1510,
  /// radius 16, shadow 0 4 4 rgba(0,0,0,0.25) (v4.11).
  static const Color topTile = Color(0xFF0F1510);

  /// Dark stroke of the on-core icons per the owner Figma CSS
  /// (Activity 4 vector: border 1.5px #0D4D36).
  static const Color onCoreDark = Color(0xFF0D4D36);

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

/// Shape & effect tokens (report table 8, Figma CSS + owner CSS v4.11).
abstract final class AethRadius {
  /// Status pill radii — owner CSS (Group 8): layers 140x38 r13 /
  /// 132.88x32 r11 / 125.76x26 r9. The 4th blurred blob layer (162x60) is
  /// REMOVED per the owner: the pill has exactly 3 background layers + a soft
  /// blurred accent shadow underneath (like the background-pattern glow).
  static const double pillHalo = 13;
  static const double pillMid = 11;
  static const double pillCore = 9;

  /// Speed Test button radii — owner CSS (Group 11): 96 r32 / 74 r32 /
  /// 62 r27 / 44 r17.
  static const double speedGlow = 32;
  static const double speedHalo = 32;
  static const double speedMid = 27;
  static const double speedCore = 17;

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

  /// Edge patterns. v4.11 anchored each canvas (LEFT art bottom on the
  /// screen bottom, RIGHT art top on the screen top). v4.12 — owner
  /// «پترن‌های چپ و راست رو ۴۰ درصد کوچک‌تر کن، الان خیلی بزرگن»: the
  /// canvases render at [patternScale] of the screen width (art 40% smaller
  /// than the v4.11 full-width span), keeping the same anchors — left art
  /// hugging the LEFT edge, right art the RIGHT edge.
  static const double patternScale = 0.6;
  static const double patternLeftAspect = 1232 / 456; // h/w of the canvas
  static const double patternRightAspect = 1178 / 464;
  static const double patternLeftAnchorBottom = 969 / 1232;
  static const double patternRightAnchorTop = 205 / 1178;

  /// v4.12 — owner «کمی از بالا کل اپ رو فاصله بده تا اپ وارد فرورفتگی
  /// نمایش درصد شارژ و ... گوشی نشه»: extra top gap UNDER the SafeArea so
  /// the content never crowds the status bar / notch on any device.
  static const double topSafeExtraGap = 12;

  /// Look-2 center connect button core: 112px circle (144,328)–(256,432).
  static const double centerButtonSize = 112;

  /// Status pill group — owner CSS (Group 8): outer layer 140×38 at
  /// (131,605); all layers concentric (center x201 = frame center).
  static const double pillWidth = 140;
  static const double pillHeight = 38;
  static const double pillMidWidth = 132.88;
  static const double pillMidHeight = 32;
  static const double pillCoreWidth = 125.76;
  static const double pillCoreHeight = 26;

  /// Soft blurred accent shadow under the pill (owner: «یک سایه محو سبز رنگ
  /// زیرش مثل سایه سبز پترن های پس زمینه») — sigma/offset tuned to the
  /// exported frames' under-glow.
  static const double pillShadowBlur = 12;
  static const double pillShadowOffsetY = 8;
  static const double pillShadowAlpha = 0.45;

  /// Speed Test button group — owner CSS (Group 11): 96×96 glow at (153,508),
  /// layers concentric, core 44×44 at (179,534); icon box 28×28 (Activity 4).
  static const double speedGroupSize = 96;
  static const double speedHaloSize = 74;
  static const double speedMidSize = 62;
  static const double speedCoreSize = 44;
  static const double speedIconSize = 28;

  /// Top-bar icon tile (owner CSS Rectangle 9): 50×50, icon glyph ≈26.
  static const double topTileSize = 50;
  static const double topTileIcon = 26;
  static const double topTileRadius = 16;

  /// Brand mark behind the wordmark (آیکون اپ/2.svg) — measured on the
  /// reference frames: 37×39 px centered on the wordmark center.
  static const double brandMarkSize = 38;
  static const double wordmarkFontSize = 15;
  static const double wordmarkLetterSpacing = 1.1;

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
  /// speed-group(96)→pill 1 (design y604→605), pill(38)→panel 63
  /// (design y643→706), panel→bottom 30. (v4.11 — owner CSS Group 8/11.)
  static const double gapTopbarToLocation = 21;
  static const double gapLocationToFlags = 13;
  static const double gapSpeedToPill = 1;
  static const double gapPillToPanel = 63;
  static const double gapPanelToBottom = 30;

  /// Location header (v4.12): the name · map icon · ping render as ONE
  /// compact cluster at the LEFT-OF-CENTER — [locationInsetStart] is the
  /// cluster's start inset (ref name start x95) and [locationGroupGap] the
  /// gap between the three cluster elements. (v4.11 spread them name-left /
  /// icon-center / ping-right; the owner asked for the left-of-center
  /// cluster instead.)
  static const double locationInsetStart = 95;
  static const double locationGroupGap = 12;
}
