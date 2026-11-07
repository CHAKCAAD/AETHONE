/// AETHONE design tokens — extracted with three-layer evidence
/// (VLM image reads + programmatic pixel measurement + Figma CSS / asset XML)
/// in the phase-1 analysis report (tables 7 & 8). Do NOT change these values
/// ad hoc: where the owner-declared value and pixel measurement differ by ±1
/// (JPEG drift), the OWNER-DECLARED value wins (report §4 rule).
library;

import 'package:flutter/painting.dart';

import 'app_theme.dart';

/// Colors (report table 7). Every value cites its evidence.
///
/// v4.34 — LIGHT MODE: the theme-dependent half of this table reads the
/// process-wide [AethThemeSync.palette] (night ↔ light, owner round 10);
/// the accent family below stays identical in BOTH modes. The night
/// values are the evidence-locked ones this file always carried.
abstract final class AethColors {
  /// Screen background — night `#141C16` (owner-declared) / light `#EDEDED`
  /// (the owner's light-mode CSS). Theme-dependent (v4.34).
  static Color get bgScreen => AethThemeSync.palette.bgScreen;

  /// Connected / active accent — owner + pattern XML `#1AD995`.
  static const Color accentConnected = Color(0xFF1AD995);

  /// Disconnected / error accent — owner + pattern XML `#EA2323`.
  static const Color statusDisconnected = Color(0xFFEA2323);

  /// Text/icon color on the red status pill — night `#75160F` (Figma CSS)
  /// / light `#141C16` (the owner's light CSS «غیرفعال»). Theme-dependent.
  static Color get onPillDisconnected => AethThemeSync.palette.onPillDisconnected;

  /// Text/icon color on the green status pill — night `#123E2B` (Figma CSS
  /// + owner) / light `#141C16` (the owner's light CSS «مــتـصـل»).
  /// Theme-dependent.
  static Color get onPillConnected => AethThemeSync.palette.onPillConnected;

  /// 4-layer pill opacities (Figma CSS Rectangle 26 / 22 / 21 / 20).
  static const double pillGlowOpacity = 0.53;
  static const double pillHaloOpacity = 0.19;
  static const double pillMidOpacity = 0.45;

  /// Gold accent on mim / gool-classic protocol icons (asset XML `#997A35`).
  static const Color goldAccent = Color(0xFF997A35);

  /// DOWN stat icon box (pixel, connected-look1 @ y=800) — night `#0A4F33` /
  /// light rgba(0,213,137,0.30) (owner CSS Rectangle 11). Theme-dependent.
  static Color get statDownBg => AethThemeSync.palette.statDownBg;

  /// UP stat icon box (pixel) — night `#3A1C1C` / light rgba(230,57,70,
  /// 0.20) (owner CSS Rectangle 12). Theme-dependent (v4.34).
  static Color get statUpBg => AethThemeSync.palette.statUpBg;
  /// v4.34 — theme-dependent: night `#652325` / light a 35 % tint of the
  /// CSS red (the light frames show no border on the UP box).
  static Color get statUpBorder => AethThemeSync.palette.statUpBorder;

  /// Dark cards (protocol / stats / FAB column) — night: pixel-measured on
  /// the four reference frames at y 706–845 (samples #0F1511/#0e1410/
  /// #101511; JPEG drift ±2), DARKER than the screen bg; light: `#FFFFFF`
  /// (owner CSS «بکگراند بخش انتخاب پروتکل»). Theme-dependent (v4.34).
  static Color get cardDark => AethThemeSync.palette.cardDark;

  /// Top-bar icon tiles — owner Figma CSS «Rectangle 9»: 50x50, radius 16,
  /// shadow 0 4 4 rgba(0,0,0,0.25); night fill `#0F1510`, light `#FFFFFF`
  /// (v4.11 + v4.34). Theme-dependent.
  static Color get topTile => AethThemeSync.palette.topTile;

  /// The «Rectangle 9» top-tile drop shadow — night rgba(0,0,0,0.25)
  /// 0 4 4 / light transparent (v4.35, owner round 11 item 1: the two top
  /// buttons carry NO shadow in light mode). Theme-dependent.
  static Color get tileShadow => AethThemeSync.palette.tileShadow;

  /// Dark stroke of the on-core icons per the owner Figma CSS
  /// (Activity 4 vector: border 1.5px #0D4D36).
  static const Color onCoreDark = Color(0xFF0D4D36);

  /// v4.35 (owner round 11, item 9): the speed-test start button's REST
  /// glyph — WHITE in BOTH modes (the owner's light-mode CSS «border: 1.5px
  /// solid #FFFFFF»; night was already white). Const by decree: it never
  /// rides the palette lerp, the running glyph stays [onCoreDark].
  static const Color speedIconRest = Color(0xFFFFFFFF);

  /// Protocol-logo box inside the protocol card — night `#2D323D` (crop
  /// read) / light `#E8ECEA`. Theme-dependent (v4.34).
  static Color get cardIconBg => AethThemeSync.palette.cardIconBg;

  // ---- v4.16 protocol sheet (measured on the sheet frame) ----
  /// The 66×66 subtile insets inside the family cards — night #1A261C
  /// measured, LIGHTER than the card (a raised inner square); light
  /// `#EFEFEF` (derived). Theme-dependent (v4.34).
  static Color get sheetSubtile => AethThemeSync.palette.sheetSubtile;

  /// The grab handle (#D9D9D9 measured, lum 218).
  static const Color sheetHandle = Color(0xFFD9D9D9);

  /// The unselected TRACK fill (pill tracks, switches; originally the
  /// v4.16 descriptions-card fill, #0C120F measured). Night `#0C120F` /
  /// light `#E4E7E5` (derived). Theme-dependent (v4.34).
  static Color get sheetDescCard => AethThemeSync.palette.sheetDescCard;

  /// Chevron on the protocol card (crop read coral-red `#E74C5B`).
  static const Color chevronRed = Color(0xFFE74C5B);

  /// Three tiny chevrons under the FAB column slot (crop read #C1303C-ish
  /// red, measured on حالت متصل-ضاهر1 at x 334–346, y 800–820).
  static const Color fabChevrons = Color(0xFFC1303C);

  /// Primary text/icon ink — night `#FFFFFF` / light `#141C16` (owner:
  /// «متن ها و آیکون های روی کارت … باید به رنگ 141C16 در لایت مود»).
  /// Theme-dependent (v4.34).
  static Color get textPrimary => AethThemeSync.palette.textPrimary;

  /// v4.41 (owner round 17, item 10): the AETHONE lockup's TEXT — pinned
  /// PURE WHITE at night («متن AETHONE بالای صفحه اصلی باید در حالت نایت
  /// مود سفید باشه»); light keeps the theme ink. Reads the RESOLVED
  /// binary slot ([AethThemeSync.light]), not the lerped palette, so no
  /// cross-fade frame, restore seed or stale-palette edge can ever render
  /// the wordmark dark at night.
  ///
  /// v1.0.0 (round 18): light mode pins PURE BLACK («متن aethone بالای
  /// صفحه اصلی … در حالت لایت مود باید مشکی رنگ باشه») — the symmetric
  /// decree: white at night, black in light, both resolved slots, never
  /// the lerped palette.
  static Color get wordmarkInk => AethThemeSync.light
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  /// Secondary/muted text — night `#8E8E93` (VLM read) / light `#A3A3A3`
  /// (the light CSS «UP:»/«DOWN:» label color). Theme-dependent (v4.34).
  static Color get textSecondary => AethThemeSync.palette.textSecondary;

  // ---- v4.23 onboarding («صفحه شروع» frames) ----

  /// The dim stepper state — bars + icons of the INACTIVE steps, measured
  /// on all four wizard frames (night #15553B; the bright state is the
  /// accent). Light: `#CBE9DC` (derived). Theme-dependent (v4.34).
  static Color get stepDim => AethThemeSync.palette.stepDim;

  /// The two light-gray tiles (system-language gear, routing «none» ✕) —
  /// fill #D9D9D9 measured on both frames.
  static const Color tileGray = Color(0xFFD9D9D9);

  /// Glyph ink on the gray tiles (dark indigo #353051/#363152 measured).
  static const Color tileGrayInk = Color(0xFF353051);

  /// The amber Shield Star on the selected «اتوماتیک» card (#DFC62F
  /// measured on the step-4 frame; brighter than [goldAccent]).
  static const Color autoShieldAmber = Color(0xFFDFC62F);

  /// The edge patterns render at low opacity on the wizard frames (the
  /// art peaks ≈24% over the background — measured on all five frames).
  static const double obPatternOpacity = 0.24;

  // ---- v4.24 speed test («صفحه تست سرعت») — measured programmatically on
  // the three committed frames (قبل از شروع / در حال تست سرعت / اتمام
  // تست سرعت): tile-box corner grids + polar midline sampling. ----

  /// The gauge track at rest — a shade DARKER than the bg (night #0A0F0B
  /// read at all 19 midline angles on the idle + done frames; light
  /// `#E0E0E0`, the same relation against #EDEDED). Theme-dependent.
  static Color get speedTrack => AethThemeSync.palette.speedTrack;

  /// The gauge track while a phase runs (night #16543B on the running
  /// frame — the step-dim green family; light `#C8E9DA`, derived).
  /// Theme-dependent (v4.34).
  static Color get speedTrackLive => AethThemeSync.palette.speedTrackLive;

  /// The progress fill's tail at the 180° end (#0C7650, running frame).
  static const Color speedFillTail = Color(0xFF0C7650);

  /// The progress fill's head at the leading edge (#1ACE8D, running frame;
  /// within JPEG drift of [accentConnected] — kept distinct, evidence rule).
  static const Color speedFillHead = Color(0xFF1ACE8D);

  /// The rest-state core of the page's start button — v4.33: the owner's
  /// own CSS (Rectangle 13) says `#080C09`; it flips to [accentConnected]
  /// while running. v4.34 light: `#FFFFFF` (the card family).
  /// Theme-dependent.
  static Color get speedCoreRest => AethThemeSync.palette.speedCoreRest;

  /// v4.33 (owner CSS, «در حالت قبل از استارت تست»): the start button's
  /// inner layers are BLACK at rest — rgba(17,0,0,0.19) halo and
  /// rgba(17,0,0,0.45) mid — under the permanent green glow; the pair
  /// flips to the accent family while running. v4.34 light: the ink tint
  /// `#141C16` under the same opacities. Theme-dependent.
  static Color get speedIdleLayer => AethThemeSync.palette.speedIdleLayer;

  /// v4.33 (owner CSS, the look-2 connect button «Hicon / Linear / Off»):
  /// the power glyph's stroke on the GREEN core = `#0D5138`.
  static const Color onConnectCore = Color(0xFF0D5138);

  /// v4.33 (owner CSS, Rectangle 13 — the wizard CTA): the continue /
  /// «برو بریم» button's fill `#0F1510` (the dark-card family). v4.34
  /// light: `#FFFFFF` (the CTA is a card; its label is [textPrimary]).
  /// Theme-dependent.
  static Color get obCtaBg => AethThemeSync.palette.obCtaBg;

  /// Jitter tile bg (night #0A394B / light rgba(0,143,213,0.15) — the CSS
  /// icon-box tint pattern); its icon #008FD5 both modes. Theme-dependent
  /// bg (v4.34).
  static Color get speedTileJitter => AethThemeSync.palette.speedTileJitter;
  static const Color speedIconJitter = Color(0xFF008FD5);

  /// Ping tile bg (night #3A3C17 / light rgba(230,216,58,0.18)); its icon
  /// #E6D83A both modes. Theme-dependent bg (v4.34).
  static Color get speedTilePing => AethThemeSync.palette.speedTilePing;
  static const Color speedIconPing = Color(0xFFE6D83A);

  /// The DOWN tile bg is the home panel's own [statDownBg]; its icon —
  /// night #01D589 measured EXACT / light #00D589 (owner CSS Graph Down).
  /// Theme-dependent (v4.34).
  static Color get speedIconDown => AethThemeSync.palette.speedIconDown;

  /// The UP tile bg is the home panel's own [statUpBg]; its icon — night
  /// #E83946 measured EXACT / light #E63946 (owner CSS Graph Up).
  /// Theme-dependent (v4.34).
  static Color get speedIconUp => AethThemeSync.palette.speedIconUp;
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

  /// v4.33 — the look-2 CONNECT button composition (the owner's own CSS,
  /// «Group 45»/«Group 11», 236×236 at the hero position): four concentric
  /// layers, the outermost a circular blurred glow, the inner three
  /// SQUIRCLES (the old circular GlowCircle is retired by decree):
  ///   glow : 236×236,   r120 (a circle), rgba(26,217,149,0.53), blur(57)
  ///   halo : 181.92²,   r69,  rgba(26,217,149,0.19)
  ///   mid  : 152.42²,   r62,  rgba(26,217,149,0.45)
  ///   core : 108.17²,   r41,  #1AD995 + the Off glyph 48×48, 4.5px #0D5138
  static const double connectGlow = 120;
  static const double connectHalo = 69;
  static const double connectMid = 62;
  static const double connectCore = 41;

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
  // v4.35 (owner round 11, item 8: «حالت‌های سبز و قرمز پترن‌های صفحات رو
  // کمی پر رنگ‌تر و بزرگ‌تر کن») — 0.6 → 0.7: the canvases grow back
  // ~17 % (a bit bigger, the v4.12 40 % cut restored partially), and the
  // paint adds an alpha ×1.6 lift (see pattern_sides.dart) so the soft
  // blurred strokes read stronger in BOTH color states.
  static const double patternScale = 0.7;
  static const double patternLeftAspect = 1232 / 456; // h/w of the canvas
  static const double patternRightAspect = 1178 / 464;
  static const double patternLeftAnchorBottom = 809 / 1232;
  static const double patternRightAnchorTop = 205 / 1178;

  /// v4.12 — owner «کمی از بالا کل اپ رو فاصله بده تا اپ وارد فرورفتگی
  /// نمایش درصد شارژ و ... گوشی نشه»: extra top gap UNDER the SafeArea so
  /// the content never crowds the status bar / notch on any device.
  static const double topSafeExtraGap = 12;

  /// Edge-pattern ART BOUNDS inside the committed canvases (PIL alpha>40
  /// profile, v4.17): the LEFT art occupies canvas rows 375..834 of 1232
  /// (hugs its LEFT edge), the RIGHT art rows 357..719 of 1178 (hugs its
  /// RIGHT edge). The v4.17 per-screen placement formulas need these to put
  /// the art itself — not the canvas — on the owner's requested bands.
  static const double patternLeftArtTopRow = 375;
  static const double patternLeftArtRows = 459; // 375..834
  static const double patternRightArtBottomRow = 719; // art rows 357..719

  /// v4.33 — the look-2 CONNECT button composition sizes (the owner's own
  /// CSS, 236×236 «Group 45» at the hero position left:83 top:263):
  /// glow 236 (circle r120, blurred 57) / halo 181.92 / mid 152.42 /
  /// core 108.17 (squircle r41) with the Off glyph 48×48. The whole group
  /// IS the button's layout box — the glow spills past it via blur.
  static const double connectGroupSize = 236;
  static const double connectHaloSize = 181.92;
  static const double connectMidSize = 152.42;
  static const double connectCoreSize = 108.17;
  static const double connectIconSize = 48;

  /// v4.33 — the look page's look-2 preview renders the FULL composition
  /// (ConnectButtonGlow) scaled to this group size (the frame's preview
  /// measures ≈150 total / ≈66 core).
  static const double obPreviewGroupSize = 150;

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

  /// Speed-Test glow layer (Group 11 halo) — v4.33: the owner's own CSS
  /// (both states) pins the glow at rgba(26,217,149,0.53) with
  /// `filter: blur(57px)`; the old 0.34/24 tuning is superseded by the
  /// explicit decree («کد css ش رو هم میزارم»).
  static const double speedGlowOpacity = 0.53;
  static const double speedGlowBlur = 57;

  /// The connect-button glow blur — the owner CSS `filter: blur(57px)`
  /// on the 236×236 layer (v4.33).
  static const double connectBlur = 57;

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
  // v4.41 (owner round 17, item 2): «آیکون تور و سایفون صفحه تنطیمات هم
  // حداکثر ارتفاع 35 داشته باشن در حال حاضر زیادی بزرگ هستن» — the v4.40
  // 56/42 boxes were too big; both logos cap at 35 ink-height now (the
  // psiphon 27×36 art prints 26×35, the tor 32×32 art prints 35×35).
  static const double settingsPillLogoPsiphon = 35;
  static const double settingsPillLogoTor = 35;
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
  // v4.16 — PROTOCOL SELECTION, measured on the design frame «صفحه شناور
  // انتخاب پروتکل صفحه اصلی.jpg» (402×874, 1:1 ref) and the companion
  // «صفحه شناور توضیحات پروتکل ها.jpg» (the ⓘ popup).
  // v4.17 — owner: the floating sheet is PROMOTED to a full PAGE «مثل صفحه
  // اصلی تنظیمات» (top bar + patterns + back/info tiles). All v4.16
  // measurement values are preserved and re-anchored to the page: the
  // sheet's y-coordinates shifted up by the reclaimed sheet-chrome zone and
  // the family cards grew (owner round: «نمایش زیرمجموعه‌ها فشرده‌ست»).
  // -----------------------------------------------------------------

  /// The home TOP BAR band height the page content sits under — the page
  /// content starts below [topSafeExtraGap] + top tile (50) + 34 gap.
  static const double protoPageContentTop = 96;

  /// Section headings: text 16 w700 white; the text's right edge sits
  /// [protoHeadingTextRightInset] from the screen right, then the
  /// [protoHeadingBadgeGap] gap, then the badge at the content inset
  /// (right edge x374 → 28 inset).
  /// v4.17 — owner: the badges were «کمی کوچیکه» → 20 → 26, and the text
  /// sat «خیلی زیاد از آیکونشون فاصله داره» → gap 26 → 12 (inset follows:
  /// 28 + 26 + 12 = 66).
  static const double protoHeadingTextRightInset = 66;
  static const double protoHeadingBadgeGap = 12;
  static const double protoBadgeSize = 26;
  static const double protoRightInset = 28;
  static const double protoHeadingTextSize = 16;

  /// Heading row tops on the page: حالت اتصال 96, پروتکل 194, سرعت اسکن 736.
  static const double protoPageHeadingModeTop = 96;
  static const double protoPageHeadingProtocolTop = 194;
  static const double protoPageHeadingScanTop = 736;

  /// Segments (تونل | پروکسی): h35 r14, x28..374, gap 21 — RTL order: تونل
  /// (right, first) then پروکسی; the frame ships پروکسی SELECTED (green
  /// #1AD995 fill, WHITE text on both states; dark = #0F1511).
  /// Page top: 37 below its heading top (the sheet's 164→201 rhythm).
  static const double protoSegmentTop = 133;
  static const double protoSegmentH = 35;
  static const double protoSegmentRadius = 14;
  static const double protoSegmentGap = 21;
  static const double protoSegmentTextSize = 16;

  /// Tile grid: 3 per row, w103 gap 21 (x27..374), row1 y233 h100, row2 y349
  /// h94 (the sheet's internal gaps kept: heading→row1 39, row1→row2 16).
  /// v4.33 — the ⓘ badge tokens are gone (the descriptions are gone).
  static const double protoTileW = 103;
  static const double protoTileGap = 21;
  static const double protoTileRadius = 21;
  static const double protoTileRow1Top = 233;
  static const double protoTileRow1H = 100;
  static const double protoTileRow2Top = 349;
  static const double protoTileRow2H = 94;
  static const double protoTileIconCenter = 41;
  static const double protoTileLabelCenter = 66;
  static const double protoTileLabelSize = 12;

  /// Family cards (سایفون / تور): v4.17 breathing — the owner called the
  /// sub-protocol display «جالب نیست و یکم فشردهست»: card h 100 → 116, the
  /// subtiles stay 66 (the stack-glyph calibration is evidence-locked) but
  /// gain air (gap 16 → 20) and vertical centering (inset 25), and the main
  /// block narrows 103 → 95 so everything fits the 346 card: 95 + 3×66 +
  /// 2×20 + 13 inset = 346. Main block: logo center top+43, label top+80.
  static const double protoCardTopPsiphon = 463;
  static const double protoCardTopTor = 594;
  static const double protoCardH = 116;
  static const double protoCardRadius = 21;
  static const double protoSubtile = 66;
  static const double protoSubtileRadius = 14;
  static const double protoSubtileGap = 20;
  static const double protoSubtileInsetTop = 25;
  static const double protoMainBlockW = 95;
  static const double protoMainLogoCenterY = 43;
  static const double protoMainLabelCenterY = 80;

  /// v4.33 (owner round 9) — the combined-mode subtile glyphs: the owner's
  /// own SVGs (38×41 «X اور وارپ» / 24×35 «وارپ اور X»), rendered 48 tall
  /// inside the 66 subtile (the retired aether+chevron stack measured ≈59
  /// ink-height; the owner's art carries its own breathing room). The
  /// plain ONLY subtiles keep the family logos at the old stack's own
  /// calibrated boxes (psiphon 31.2 / tor 26.3 — the _StackGlyph evidence).
  // v4.41 (owner round 17, item 1): «حداکثر ارتفاع 35 کافیه … آیکون های
  // اصلی سایفون و تور هم ارتفاعشون اندازه آیکون سمت چپ باشه» — EVERY
  // family-card glyph (the combined modes AND the plain family logos inside
  // the three right subtiles) caps at 35 ink-height, matching the
  // main-block logo on the visual left; the v4.40 48/31.2/26.3 frame
  // calibration is retired by the decree.
  static const double protoCombinedGlyphH = 35;
  static const double protoPsiphonGlyphBox = 35;
  static const double protoTorGlyphBox = 35;

  /// Scan pills: h36 r8 gap8, CENTERED (row spans x33..367). Widths increase
  /// toward the right; the frame ships the widest (rightmost, 87) SELECTED.
  /// Page top: 40 below its heading top (the sheet's 765→805 rhythm).
  static const double protoPillTop = 776;
  static const double protoPillH = 36;
  static const double protoPillRadius = 8;
  static const double protoPillGap = 8;
  static const double protoPillW1 = 28;
  static const double protoPillW2 = 47;
  static const double protoPillW3 = 64;
  static const double protoPillW4 = 77;
  static const double protoPillW5 = 87;

  // -------------------------------------------------------------------
  // v4.23 — ONBOARDING («صفحه شروع», the four wizard frames + «لودینگ
  // اسکن»), all measured programmatically on the 402×874 sources:
  // logo lockup, 4-segment stepper, question headings, the flag/gear
  // tile grids, the two look previews, the step-4 sections and the
  // scanning modal. Reference pixels, scaled by screenWidth/402.
  // -------------------------------------------------------------------

  /// Logo lockup: brand mark 38 (same canvas as the home wordmark mark)
  /// with a LARGER 17px wordmark; bars start 34 below the lockup.
  static const double obWordmarkSize = 17;
  static const double obLockupToStepper = 34;

  /// Stepper: 4 bars 70×7 (r3.5) with 19 gaps spanning the page inset,
  /// icons 22 centered under each bar 12 below; the ACTIVE step's bar +
  /// icon render in the accent, the rest in [AethColors.stepDim].
  static const double obBarW = 70;
  static const double obBarH = 7;
  static const double obBarGap = 19;
  static const double obBarToIcon = 12;
  static const double obStepIcon = 22;

  /// The question headings («زبان برنامه چی باشه؟» family): 20 w700 white,
  /// a 22 white glyph at the page's right inset, 8 gap to the text.
  static const double obHeadingSize = 20;
  static const double obHeadingIcon = 22;
  static const double obHeadingIconGap = 8;
  static const double obHeadingToTiles = 34;

  /// The wizard's flexible vertical rhythm (steps 1–3): the heading+tiles
  /// block floats between the stepper and the CTA with spacer flexes
  /// 179:223 (measured on the frames) so every screen height lands close.
  static const int obFlexAbove = 179;
  static const int obFlexBelow = 223;

  /// Tiles: 65×65 r20 (flags AND the gray glyphs), selection = a 2.5 accent
  /// ring 1px off the tile edge (overflow 3.5) + a soft green glow.
  static const double obTileSize = 65;
  static const double obTileRadius = 20;
  static const double obTileGapX = 43;
  static const double obTileGapY = 30;
  static const double obRingStroke = 2.5;
  static const double obRingGap = 1;
  static const double obRingRadius = 23.5;
  static const double obGrayGlyph = 26;

  /// Step-2's staggered routing grid: same 3 columns × 95 pitch, the gray
  /// «none» tile vertically centered in the LEFT column (top 47.5).
  static const double obRowPitch = 95;
  static const double obMidTileTop = 47.5;

  /// CTA — v4.33 (owner CSS Rectangle 13): full-width 62-tall box, the
  /// app's own card corner language (r17 — «گردی گوشه‌ها باید اندازه بقیه
  /// باکس‌های اپ باشه»), ink #0F1510 (AethColors.obCtaBg), the CSS shadow
  /// rgba(0,0,0,0.25) 0 4 4; 18 w700 white label + the white Left-2
  /// chevron from the leading (visual left) edge; 39 of glass below it.
  static const double obCtaH = 62;
  static const double obCtaRadius = 17;
  static const double obCtaTextSize = 18;
  static const double obCtaChevron = 18;
  static const double obCtaChevronInset = 20;
  static const double obCtaToBottom = 39;

  /// Step-3 look previews — v4.33 (owner round 9): the look-1 slot is an
  /// EXACT copy of the home screen's own [FabColumn] (65×138 r20, the
  /// sliding 48×48 r14 power FAB, NO chevrons — they were removed from
  /// the real column by the v4.15 decree), and the look-2 slot renders
  /// the REAL [ConnectButtonGlow] composition scaled to
  /// [obPreviewGroupSize]; the 24×24 r8 Tick-Circle check badge rides 20
  /// under the SELECTED preview.
  static const double obCheckBadge = 24;
  static const double obCheckBadgeRadius = 8;
  static const double obCheckGap = 20;

  /// Step-4 (mode + protocol + scan): 77 below the stepper icons, section
  /// headings — v4.33: the SAME 20 w700 size as steps 1–3 (owner: «سایز
  /// متن سرتیترها توی هر ۴ صفحه باید یکسان باشه») — with the 26 badge
  /// (the protocol page's own family), segments 36 r14 gap 21, option
  /// cards 101 r24 gap 12 with a 56-wide icon+label column 24 from the
  /// card's right edge, body text 12/1.25.
  static const double obStep4TopGap = 77;
  static const double obHeadingToSegments = 16;
  static const double obSegmentsToHeading = 38;
  static const double obHeadingToCard = 14;
  static const double obCardGap = 12;
  static const double obCardToHeading = 28;
  static const double obHeadingToPills = 17;
  static const double obCardH = 101;
  static const double obCardRadius = 24;
  static const double obCardColumnW = 56;
  static const double obCardColumnInset = 24;
  static const double obCardBodyGap = 16;
  static const double obCardIcon = 26;
  static const double obCardLabelSize = 12;
  static const double obCardBodySize = 12;
  static const double obCardBodyHeight = 1.25;

  /// The scanning modal: 216×133 #0F1511 r16, brand mark 38, 21 gap,
  /// 16 w600 title — over the blurred step-4 page.
  static const double obModalW = 216;
  static const double obModalH = 133;
  static const double obModalRadius = 16;
  static const double obModalMark = 38;
  static const double obModalGap = 21;
  static const double obModalTextSize = 16;

  // -------------------------------------------------------------------
  // v4.24 — SPEED TEST («صفحه تست سرعت»), measured programmatically on the
  // three committed frames (402×874 ref px): run-extraction of the dial
  // band (center (200,376), outer r108 / inner r87 — stroke 21 — 180° top
  // semicircle with round caps), the 12-o'clock tick (x197.5–207.5,
  // y308–360, gradient fading down), the value block («0.0» x183–221
  // y365–384 + «Mbs» x228–253 y366–378, baseline-aligned — the NUMBER's
  // right edge is pinned at x221 and the unit hangs at x228 in BOTH the
  // idle («0.0») and running («50.4») frames, i.e. the number grows
  // LEFTWARD), the «دانلود» phase label (x174–234, ink y415–438 — running
  // only), the 2×2 stat grid (cards 160 wide at x33/210 with the page's
  // own 33 inset, rows y510/588; 48px r14 tiles at 8 inset, label 12 over
  // value 14, the frame's own glyphs 26px inside the tiles) and the button
  // group (the home Group 11: glow 96 σ24 / halo 74 / mid 62 / core 44
  // r17, the label «شروع» 16px w500, ink y787–801).
  //
  // v4.24.1 — the second measurement round (status-bar inset 24 simulated
  // in the shots test, every element re-probed): the title is the frame's
  // 26px/24-ink («تست سرعت» x116–259), the badge is the hexagon+wave BRAND
  // glyph at 24 (x273–296, gap 14 after the text), the phase label 25
  // (61 wide), the card row gap 16 (row2 y588 − row1 y510 − card 62), the
  // button glow box top at y692 (cards bottom 650 + 42) and the label
  // under the group.
  // -------------------------------------------------------------------

  /// Title row + dial rhythm (all ref px, frame coords).
  static const double speedTitleSize = 28;
  static const double speedTitleBadge = 27;
  static const double speedTitleBadgeGap = 14; // text x259 → badge x273
  static const double speedGapTopbarToTitle = 52; // tile bottom y86 → title ink y146
  static const double speedGapTitleToDial = 89; // title row → dial zone top y267

  /// The dial itself (the painter box is 216×118.5, center (108,108)).
  static const double speedDialOuterR = 108;
  static const double speedDialInnerR = 87;

  /// v4.33 — the gauge NEEDLE (the owner's own SVG «عقربه صفحه تست سرعت»,
  /// 15×52, a green→transparent gradient): pivots at the dial's centre
  /// (108,108 in the painter box), points at the scale's start (WEST) at
  /// zero and sweeps with the measured download speed to EAST at 100 Mbs.
  /// The frames measure the same 52px length (ink y308–360, pivot y≈362).
  static const double speedNeedleW = 15;
  static const double speedNeedleH = 52;
  static const double speedNeedleCx = 108;
  static const double speedNeedleCy = 108;

  /// The whole dial zone: the arc + the value slot + the phase-label slot
  /// as ONE FIXED 176 box — the cards below never move between states.
  static const double speedDialZoneH = 176;
  static const double speedValueSize = 28; // «0.0» / «50.4» (ink 20 tall, 40/55 wide)
  static const double speedUnitSize = 14; // «Mbs» (25 wide, 10 tall on the frame)
  static const double speedValueRightInset = 117; // group right x252 (zone x369−252)
  static const double speedValueGap = 3.5; // number right x221 → unit x228
  static const double speedPhaseLabelSize = 25; // «دانلود» 61 wide, ink 24 tall
  static const double speedGapDialToCards = 67; // zone bottom y443 → cards y510

  /// The 2×2 stat grid.
  static const double speedCardH = 62;
  static const double speedCardGapX = 17;
  static const double speedCardGapY = 16; // row1 y510+62 → row2 y588
  static const double speedTileSize = 48; // == statIconBoxSize
  static const double speedTileRadius = 14;
  static const double speedTileInset = 8;
  static const double speedTileGap = 9; // tile → label run (measured)
  static const double speedCardLabelSize = 12;
  static const double speedCardValueSize = 14;

  /// The frame's own tile glyphs — per-icon sizes (the graphs' rounded
  /// square is 26px on the frames; the SVG's square is 25/30 of its box).
  static const double speedIconJitterSize = 22;
  static const double speedIconPingSize = 22;
  static const double speedIconGraphSize = 31; // 26px square at 25/30 fill

  /// The button + its label zone. v4.33: the core glyph is the set's own
  /// Activity 4 waveform (the owner's CSS «Hicon / Linear / Activity 4»
  /// — 28×28, white on the dark rest core, #0D4D36 on the green one).
  static const double speedGapCardsToButton = 41; // cards y650 → glow box y692
  static const double speedButtonIcon = 28; // the Activity 4 waveform
  static const double speedButtonLabelSize = 16; // «شروع» ink y787–801
  static const double speedGapButtonToLabel = -6; // glow bottom y785 → ink y787
}
