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

  // ---- v4.16 protocol sheet (measured on the sheet frame) ----
  /// The 66×66 subtile insets inside the family cards — #1A261C measured,
  /// LIGHTER than the #0F1511 card (a raised inner square, not an inset).
  static const Color sheetSubtile = Color(0xFF1A261C);

  /// The grab handle (#D9D9D9 measured, lum 218).
  static const Color sheetHandle = Color(0xFFD9D9D9);

  /// The descriptions-card fill (#0C120F measured — darker than the scrim
  /// zone, so the card reads as a second, deeper layer over the dimmed
  /// sheet exactly like the frame).
  static const Color sheetDescCard = Color(0xFF0C120F);

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
  ///
  /// v4.15 — owner settings round #4: «پترن سمت چپ پس زمینه پایینش حالت
  /// برش خورده داره یا اون رو پایین تر بیار که بچسبه به پایین و برش
  /// خوردگیش مشخص نباشه». Measured on the shipped PNG (PIL alpha profile):
  /// the visible art (alpha>40) ends at canvas row 834/1232 — the OLD anchor
  /// 969/1232 left that hard end ~71 ref px ABOVE the glass, which read as a
  /// straight cut. New anchor: the art's end runs 25 canvas rows (~13 ref
  /// px) BELOW the screen bottom, so the pattern flows off the bottom edge
  /// and no end edge is ever visible on screen («بچسبه به پایین»).
  static const double patternScale = 0.6;
  static const double patternLeftAspect = 1232 / 456; // h/w of the canvas
  static const double patternRightAspect = 1178 / 464;
  static const double patternLeftAnchorBottom = 809 / 1232;
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
  /// زیرش مثل سایه سبز پترن های پس زمینه»). v4.13 — owner round-4 #5:
  /// «حالۀ سبز زیر دکمهٔ نمایش وضعیت اتصال و دکمهٔ اسپید تست زیادی کوچیک و
  /// پر رنگه؛ کمی کم‌رنگ‌ترش کن و بلرش رو بیشتر کن تا منطقه بیشتری رو پوشش
  /// بده، اما زیاد هم بزرگش نکن» — the halo rect is a touch wider than the
  /// pill, the sigma doubled, the alpha reduced.
  static const double pillShadowW = 152;
  static const double pillShadowH = 48;
  static const double pillShadowRadius = 16;
  static const double pillShadowBlur = 24;
  static const double pillShadowOffsetY = 8;
  static const double pillShadowAlpha = 0.30;

  /// Speed-Test glow layer (Group 11 halo) — same owner tuning: softer and
  /// wider, never a tight saturated ring.
  static const double speedGlowOpacity = 0.34;
  static const double speedGlowBlur = 24;

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

  /// Location header (v4.13 — owner round-4 re-clarification): the map icon
  /// sits at the EXACT screen centre, the country name renders in the LEFT
  /// slot and the ping/آفلاین in the RIGHT slot. [locationSideGap] is the
  /// gap between each text and the icon box (measured 65/60 on
  /// حالت متصل-ضاهر1 — symmetrized to 62 so both texts breathe alike and
  /// the centre can never drift).
  static const double locationSideGap = 62;

  // -------------------------------------------------------------------
  // Settings main page (step 2) — pixel-measured on the owner's design
  // frame «صفحه تنظیمات.jpg» (402×874, 3× source). All values in
  // reference pixels; scaled by `screenWidth / 402` at render time.
  // -------------------------------------------------------------------

  /// Six-card grid: cards 102×106 at x 33/150/267 (h-gap 15), rows at
  /// y 106/224 (v-gap 12), page inset 33 = [pageHPadding].
  static const double settingsCardW = 102;
  static const double settingsCardH = 106;
  static const double settingsCardGap = 15;
  static const double settingsRowGap = 12;

  /// Card corner radius (measured ≈21–22 on the frame's top-left corner).
  static const double settingsCardRadius = 21;

  /// Card internals: icon 28 centered 31 from the card top, title 13px
  /// centered at 65, subtitle centered at 79.
  /// v4.15 — owner settings round #2: «متن توضیحات کارت ها باید کمی کوچک تر
  /// باشد» — the description line drops 10 → 9 (title/value sizes stay).
  static const double settingsCardIconSize = 28;
  static const double settingsCardIconTop = 31;
  static const double settingsCardTitleSize = 13;
  static const double settingsCardTitleCenter = 65;
  static const double settingsCardSubSize = 9;
  static const double settingsCardSubCenter = 79;

  /// Wide Psiphon/Tor pills: 155.5×87 at y 353 (gap 24 after the grid),
  /// pill-to-pill gap 24; logo at the leading (visual right) edge with 16
  /// inset, texts stacked beside it. The logos are the REAL protocol PNGs —
  /// their canvases carry different artwork fills, so each logo gets its
  /// own BOX size such that the final GLYPH matches the frame (Psiphon
  /// glyph ≈26×35 ⇒ box 56; Tor glyph ≈24×36 ⇒ box 42).
  ///
  /// v4.15 — owner settings round #3: «پس زمینه کارت های تنظیمات سایفون و
  /// تور و کارت های آدرس گیت هاب هسته ها گوشه های مناسبی نداره و باید
  /// گوشه های کمتر گردی داشته باشه» + owner CSS «Rectangle 79»
  /// (155×84, #0F1510, border-radius 24px): the stadium (h/2 = 43.5) is
  /// REPLACED by the owner's r24. Sub line 10 → 9 with the cards (round
  /// #2 — «متن توضیحات کارت ها باید کمی کوچک تر باشد»).
  static const double settingsPillH = 87;
  static const double settingsPillGap = 24;
  static const double settingsPillLogoPsiphon = 56;
  static const double settingsPillLogoTor = 42;
  static const double settingsPillInset = 16;
  static const double settingsPillTitleSize = 13;
  static const double settingsPillSubSize = 9;

  /// Owner CSS Rectangle 79 radius for the two wide pills (r24 on the
  /// 155×84 card — applied flat in reference px).
  static const double settingsPillRadius = 24;

  /// Section headings («وضعیت پیشرفته» / «آدرس سرور اصلی»): 15px w700
  /// white, icon 20 to the leading side, right-aligned to the page inset,
  /// first heading 36 below the pills.
  static const double settingsHeadingSize = 15;
  static const double settingsHeadingIconSize = 20;
  static const double settingsHeadingGapFromPills = 36;
  static const double settingsHeadingGapToCards = 24;

  /// Bottom server pills: 155.5×70, GitHub logo ≈34 at the TRAILING
  /// (visual left) edge with 15 inset, single-line title 13.
  /// v4.15 — owner settings round #3 (CSS Rectangle 79, r24 on 84 tall):
  /// the stadium (h/2 = 35) is replaced by the proportional r20
  /// (24 × 70/84) — same look as the wide pills, never a full round.
  static const double settingsServerPillH = 70;
  static const double settingsServerPillRadius = 20;
  static const double settingsServerLogoSize = 34;
  static const double settingsServerInset = 15;
  static const double settingsHeading2GapToServer = 24;

  /// Status-card values (green): 11px w600, centered 79 from the card top
  /// (the subtitle slot of the shared card template).
  static const double settingsStatusValueSize = 11;

  // -----------------------------------------------------------------
  // v4.16 — PROTOCOL SHEET. Every value below is MEASURED on the design
  // frame «صفحه شناور انتخاب پروتکل صفحه اصلی.jpg» (402×874, 1:1 ref) and
  // the companion «صفحه شناور توضیحات پروتکل ها.jpg» (the ⓘ popup).
  // Measurement scripts: scripts/measure_proto_*.py (pixel clusters, corner
  // radii from fill-width profiles, colors sampled at ink centers).
  // -----------------------------------------------------------------

  /// The scrim starts here (the home TOP BAR above stays visible — diff vs
  /// the plain home frame shows the first dimmed row at y≈101).
  static const double protoScrimTop = 101;

  /// Grab handle: 85×6 r3 centered (y125..131), #D9D9D9.
  static const double protoHandleTop = 125;
  static const double protoHandleW = 85;
  static const double protoHandleH = 6;

  /// Section headings: text 16 w700 white; the text's right edge sits 74 from
  /// the screen right edge (measured on all three: x≈328), then a 26 gap,
  /// then the 20×20 badge at the content inset (right edge x374 → 28 inset).
  /// Heading rows top: 164 / 262 / 765.
  static const double protoHeadingTextRightInset = 74;
  static const double protoHeadingBadgeGap = 26;
  static const double protoBadgeSize = 20;
  static const double protoRightInset = 28;
  static const double protoHeadingTextSize = 16;

  /// Segments (تونل | پروکسی): y201..236 h35 r14, x28..374, gap 21 — RTL
  /// order: تونل (right, first) then پروکسی; the frame ships پروکسی SELECTED
  /// (green #1AD995 fill, WHITE text on both states; dark = #0F1511).
  static const double protoSegmentTop = 201;
  static const double protoSegmentH = 35;
  static const double protoSegmentRadius = 14;
  static const double protoSegmentGap = 21;
  static const double protoSegmentTextSize = 16;

  /// Tile grid: 3 per row, w103 gap 21 (x27..374), r16; row1 y301 h100,
  /// row2 y417 h94. Tile internals: ⓘ 13×13 at (11,9); icon center at
  /// top+41; label 12 w500 center at top+66 (measured cy 342/368 row1).
  static const double protoTileW = 103;
  static const double protoTileGap = 21;
  static const double protoTileRadius = 16;
  static const double protoTileRow1Top = 301;
  static const double protoTileRow1H = 100;
  static const double protoTileRow2Top = 417;
  static const double protoTileRow2H = 94;
  static const double protoInfoBadgeSize = 13;
  static const double protoInfoBadgeInset = 11;
  static const double protoTileIconCenter = 41;
  static const double protoTileLabelCenter = 66;
  static const double protoTileLabelSize = 12;

  /// Family cards (سایفون y531 / تور y646): h100 gap 15, x27..374, r16.
  /// Main block zone x27..131: logo center at top+37, label 12 at top+69.
  /// Subtiles 66×66 r14 (#1A261C) at top+16: x131..197 / 213..279 / 295..361
  /// — visual LEFT→RIGHT: plain(only), ∨(chain), ∧(reverse).
  /// Stack glyph: Aether logo ~18×19 + 7 gap + chevron 14×6 + 6 gap +
  /// protocol glyph ~16×20; plain = the protocol glyph alone ~16×20.
  static const double protoCardTopPsiphon = 531;
  static const double protoCardTopTor = 646;
  static const double protoCardH = 100;
  static const double protoCardRadius = 16;
  static const double protoSubtile = 66;
  static const double protoSubtileRadius = 14;
  static const double protoSubtileGap = 16;
  static const double protoSubtileInsetTop = 16;
  static const double protoMainLogoCenterY = 37;
  static const double protoMainLabelCenterY = 69;

  /// Scan pills: y805..841 h36 r8 gap8, CENTERED (row spans x33..367 —
  /// center 200 like the handle, NOT the content inset). Widths increase
  /// toward the right; the frame ships the widest (rightmost, 87) SELECTED.
  static const double protoPillTop = 805;
  static const double protoPillH = 36;
  static const double protoPillRadius = 8;
  static const double protoPillGap = 8;
  static const double protoPillW1 = 28;
  static const double protoPillW2 = 47;
  static const double protoPillW3 = 64;
  static const double protoPillW4 = 77;
  static const double protoPillW5 = 87;

  /// Descriptions popup (the ⓘ sheet): × button Ø22 at y206 (13 above the
  /// card top 242), card x28..374 r24 #0C120F, blocks 14px/lh18 white,
  /// dividers 1px #1A261C, icon column right (plain / Aether+∨+proto /
  /// Aether+∧+proto — same language as the subtiles).
  static const double protoDescCloseTop = 206;
  static const double protoDescCloseSize = 22;
  static const double protoDescCardTop = 242;
  static const double protoDescCardRadius = 24;
  static const double protoDescTextSize = 14;
  static const double protoDescTextHeight = 18;
}
