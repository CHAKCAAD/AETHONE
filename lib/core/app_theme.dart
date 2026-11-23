/// v4.34 — LIGHT MODE (owner round 10: «میخوایم برای اپ حالت لایت مود اضافه
/// کنیم … تغیر بین دوحالت باید با انیمیشن و به نرمی اتفاق بیفته»).
///
/// The owner's own light-mode CSS (the two committed home frames) maps the
/// app's night palette onto a light one:
///   * page background      #141C16 → #EDEDED  («background: #EDEDED»)
///   * every card           #0F1510 → #FFFFFF  («background: #FFFFFF»)
///   * card text + icons    #FFFFFF → #141C16
///   * secondary text       #8E8E93 → #A3A3A3  («UP:» / «DOWN:» labels)
///   * status-pill text     #123E2B/#75160F → #141C16 («مــتـصـل»/«غیرفعال»)
///   * DOWN icon box        #0A4F33 → rgba(0,213,137,0.30)  (Rectangle 11)
///   * UP icon box          #3A1C1C → rgba(230,57,70,0.20)  (Rectangle 12)
///   * the green/red/gold accents stay EXACTLY as they are.
///
/// Everything the CSS does not name is DERIVED by the same rule (cards
/// white / ink #141C16 / tinted translucent icon boxes) and documented at
/// each field below.
///
/// Mechanics — the whole app reads colors through the `AethColors` getters
/// (design_tokens.dart); each getter delegates to [AethThemeSync.palette],
/// a process-wide mutable slot. The app shell owns a 420 ms tween that
/// lerps [AethPal.night] ↔ [AethPal.light] into that slot every frame and
/// rebuilds the tree — so EVERY surface (Flutter widgets and CustomPaint
/// canvases alike) cross-fades together, which a MaterialApp theme swap
/// alone can never reach.
library;

import 'package:flutter/painting.dart';

/// The two app themes. The mode itself is a user preference owned by the
/// ConnectionStore (persisted like every other setting); the palette slot
/// below is the RENDER truth the tokens read.
enum AethThemeMode { night, light }

/// v4.40 — the APPEARANCE PICK (owner round 15: «یه مکانیزم میخوام برای
/// حالت دارک و لایت اضافه کنی به اسم حالت خودکار … از ساعت 6 صبح تا 6
/// عصر حالت بایت لایت مود باشه و از ساعت 6 عصر تا 6 صبح فردا هم نایت
/// مود»): the persisted preference now has three faces — the two fixed
/// modes plus AUTO, which resolves by the local clock: 06:00–18:00 light,
/// 18:00–06:00 night. [ConnectionStore.themeMode] stays the RESOLVED mode
/// the shell's tween reads (never `auto` itself).
enum AethThemePick { night, light, auto }

/// The AUTO schedule's resolver: light between 06:00 and 18:00 local time,
/// night otherwise (the owner's own boundaries, on the minute).
AethThemeMode resolveAutoTheme(DateTime localNow) {
  final int minutes = localNow.hour * 60 + localNow.minute;
  return (minutes >= 6 * 60 && minutes < 18 * 60)
      ? AethThemeMode.light
      : AethThemeMode.night;
}

/// One resolved palette. Field-for-field the themed half of `AethColors`;
/// the accent family (green/red/gold) never changes and stays const in the
/// tokens file.
class AethPal {
  const AethPal({
    required this.bgScreen,
    required this.cardDark,
    required this.topTile,
    required this.connectBaseIdle,
    required this.connectBaseLiveTop,
    required this.connectBaseLiveBottom,
    required this.flagRing,
    required this.patternInk,
    required this.textPrimary,
    required this.textSecondary,
    required this.statLabel,
    required this.onPillConnected,
    required this.onPillDisconnected,
    required this.statDownBg,
    required this.statUpBg,
    required this.statUpBorder,
    required this.cardIconBg,
    required this.sheetSubtile,
    required this.sheetDescCard,
    required this.speedTrack,
    required this.speedTrackLive,
    required this.speedCoreRest,
    required this.speedIdleLayer,
    required this.homeIdleLayer,
    required this.homeIdleCore,
    required this.panelShadowInk,
    required this.speedIconDown,
    required this.speedIconUp,
    required this.speedTileJitter,
    required this.speedIconJitter,
    required this.speedTilePing,
    required this.speedIconPing,
    required this.stepDim,
    required this.obCtaBg,
    required this.tileShadow,
  });

  /// Screen background — night `#000000` (the owner's dark-mode round:
  /// «بکگراند کل صفحه باید کد رنگی 000000 داشته باشه») / light `#FFFFFF`
  /// (the «نمای 2» light frames, pixel-sampled).
  final Color bgScreen;

  /// Dark cards (protocol / stats / FAB column) — night `#1C1C1C` (the
  /// owner's dark-mode round: «بکگراند کارت ها باید رنگ 1C1C1C داشته
  /// باشه») / light `#F4F4F4` (owner CSS «Rectangle 13»).
  final Color cardDark;

  /// Top-bar icon tiles (Rectangle 9/17) — night `#1C1C1C` (the owner's
  /// dark-mode CSS «Group 127»/«Rectangle 9») / light `#F4F4F4`.
  final Color topTile;

  /// v5.3 — the look-2 connect button's BASE squircle («3»: 160×160 r60),
  /// now a STATE-tinted TRANSLUCENT layer (the owner's new CSS — the old
  /// solid white squircle is retired):
  ///   disconnected  light rgba(54,54,54,0.10) · night rgba(66,66,66,0.19)
  /// The alpha rides INSIDE the color so the mode tween lerps it too.
  final Color connectBaseIdle;

  /// v5.3 — the CONNECTED base: light the vertical pair
  /// rgba(26,217,149,0.10) → rgba(47,248,177,0.10) (the CSS «گرادینت سبز»
  /// at 10 %), night the flat rgba(26,217,149,0.05) (equal stops = the
  /// flat solid, so ONE two-stop shader covers every state and mode).
  final Color connectBaseLiveTop;
  final Color connectBaseLiveBottom;

  /// v5 — the selected-flag ring («Ellipse 74»: 4px `#F4F4F4` in light,
  /// `#1C1C1C` in the owner's new dark CSS).
  final Color flagRing;

  /// v5.2 — the DISCONNECTED pattern artwork's ink: the committed PNG's
  /// own `#110000` by day, WHITE at night (owner round 20: «پترن های کناری
  /// در حالت قطع اتصال دارک مود رنگشون باید سفید باشه»). A LERPED palette
  /// member by design: the ink rides the shell's own 420 ms mode tween
  /// (the round-21 fix — the first cut read the binary `AethThemeSync.light`
  /// slot through a second `Tween<Color>`, which cannot lerp and threw on
  /// every mid-transition rebuild, glitching the whole mode switch).
  final Color patternInk;

  /// Primary text / icon ink — night `#FFFFFF` / light `#141C16` (owner:
  /// «متن ها و آیکون های روی کارت … باید به رنگ 141C16 در لایت مود»).
  final Color textPrimary;

  /// Secondary/muted text — night `#8E8E93` / light `#A3A3A3` (the CSS
  /// «UP:»/«DOWN:» label color).
  final Color textSecondary;

  /// v5.3 — the look-2 «UP:»/«DOWN:» LABEL ink: the owner's new dark CSS
  /// pins it `#FFFFFF` («UP: … color: #FFFFFF»); light keeps the committed
  /// light CSS's muted `#A3A3A3`.
  final Color statLabel;

  /// Status-pill ink on the GREEN core — night `#123E2B` / light `#141C16`
  /// (CSS «مــتـصـل» color).
  final Color onPillConnected;

  /// Status-pill ink on the RED core — night `#75160F` / light `#141C16`
  /// (CSS «غیرفعال» color).
  final Color onPillDisconnected;

  /// DOWN stat icon box — night solid `#0A4F33` / light translucent
  /// rgba(0,213,137,0.30) (CSS Rectangle 11).
  final Color statDownBg;

  /// UP stat icon box — night solid `#3A1C1C` / light translucent
  /// rgba(230,57,70,0.20) (CSS Rectangle 12).
  final Color statUpBg;

  /// UP stat icon box border — night `#652325` / light a 35 % tint of the
  /// CSS red family (derived; the light CSS shows no border on the box,
  /// so it fades toward the tint, not away).
  final Color statUpBorder;

  /// Protocol-logo box inside the protocol card — night `#2D323D` (crop
  /// read) / light `#E8ECEA` (derived: a gray-green paper chip on white).
  final Color cardIconBg;

  /// The 66×66 subtile insets inside the sheet family cards — night
  /// `#1A261C` (raised) / light `#EFEFEF` (derived: an inset chip on
  /// white).
  final Color sheetSubtile;

  /// The unselected track fill (pill tracks, switches) — night `#0C120F`
  /// (the old descriptions-card fill) / light `#E4E7E5` (derived).
  final Color sheetDescCard;

  /// Speed gauge track at rest — night `#0A0F0B` (a shade darker than the
  /// bg) / light `#E0E0E0` (derived by the same relation against #EDEDED).
  final Color speedTrack;

  /// The gauge track while a phase runs — night `#16543B` / light
  /// `#C8E9DA` (derived: the pale green of the same family).
  final Color speedTrackLive;

  /// The speed button's rest core — night `#080C09` (owner CSS Rectangle
  /// 13) / light `#FFFFFF` (derived: the card family).
  final Color speedCoreRest;

  /// The speed PAGE button's idle halo/mid layers — night `#110000` (owner
  /// CSS rgba(17,0,0,α)) / light `#141C16` (the ink tint of the same α
  /// layers). The PAGE start button keeps its own previous family (owner:
  /// «دکمه تست سرعت باید به رنگ قبلیش برگرده»).
  final Color speedIdleLayer;

  /// v5.3 — the HOME speed-test button's disconnected family (the owner's
  /// new CSS «Group 13»): the α layers — light rgba(17,0,0,α) → night
  /// rgba(66,66,66,α) → and the flat core — light `#363636` / night
  /// `#424242`. Split from the page button's own [speedIdleLayer] by the
  /// same decree.
  final Color homeIdleLayer;
  final Color homeIdleCore;

  /// v5.3 — the look-2 sheet's committed shadow ink: light
  /// rgba(0,0,0,0.09) / night rgba(255,255,255,0.09) (the owner's dark
  /// CSS «box-shadow: 0px -16px 95px rgba(255,255,255,0.09)»). The alpha
  /// rides inside the color so the mode tween lerps it.
  final Color panelShadowInk;

  /// DOWN stat icon — night `#01D589` / light `#00D589` (CSS Graph Down).
  final Color speedIconDown;

  /// UP stat icon — night `#E83946` / light `#E63946` (CSS Graph Up).
  final Color speedIconUp;

  /// Jitter tile bg — night `#0A394B` / light rgba(0,143,213,0.15)
  /// (derived: the CSS icon-box tint pattern applied to the jitter blue).
  final Color speedTileJitter;

  /// Jitter tile icon — `#008FD5` both modes.
  final Color speedIconJitter;

  /// Ping tile bg — night `#3A3C17` / light rgba(230,216,58,0.18)
  /// (derived: the same tint pattern on the ping yellow).
  final Color speedTilePing;

  /// Ping tile icon — `#E6D83A` both modes.
  final Color speedIconPing;

  /// The wizard's dim stepper state — night `#15553B` / light `#CBE9DC`
  /// (derived: the pale green of that family).
  final Color stepDim;

  /// The wizard CTA fill — night `#0F1510` (owner CSS Rectangle 13) /
  /// light `#FFFFFF` (the CTA is a card; its label rides [textPrimary]).
  final Color obCtaBg;

  /// The «Rectangle 9» top-tile drop shadow — night rgba(0,0,0,0.25)
  /// 0 4 4 (the evidence-locked value), light FULLY TRANSPARENT (v4.35,
  /// owner round 11, item 1: «دو دکمه بالای تمام صفحات در حالت لایت مود
  /// نباید سایه‌ای داشته باشن»). During the mode tween the alpha lerps
  /// 64 → 0, so the shadow fades out with the same 420 ms cross-fade as
  /// every other surface.
  final Color tileShadow;

  /// The standing night palette — v5.3: the owner's dark-mode round re-cuts
  /// it («بکگراند کل صفحه 000000، بکگراند کارت ها 1C1C1C"); every value the
  /// round names is evidence-locked here, the untouched derivations keep
  /// their standing relations against the NEW black bg.
  static const AethPal night = AethPal(
    bgScreen: Color(0xFF000000),
    cardDark: Color(0xFF1C1C1C),
    topTile: Color(0xFF1C1C1C),
    // «3» disconnected: rgba(66,66,66,0.19) — α 0.19 ≈ 0x30.
    connectBaseIdle: Color(0x30424242),
    // «3» connected: rgba(26,217,149,0.05) — α 0.05 ≈ 0x0D, flat pair.
    connectBaseLiveTop: Color(0x0D1AD995),
    connectBaseLiveBottom: Color(0x0D1AD995),
    flagRing: Color(0xFF1C1C1C),
    patternInk: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF8E8E93),
    statLabel: Color(0xFFFFFFFF),
    onPillConnected: Color(0xFF123E2B),
    onPillDisconnected: Color(0xFF75160F),
    statDownBg: Color(0xFF0A4F33),
    statUpBg: Color(0xFF3A1C1C),
    statUpBorder: Color(0xFF652325),
    cardIconBg: Color(0xFF2D323D),
    sheetSubtile: Color(0xFF1A261C),
    sheetDescCard: Color(0xFF0C120F),
    speedTrack: Color(0xFF0A0F0B),
    speedTrackLive: Color(0xFF16543B),
    speedCoreRest: Color(0xFF080C09),
    speedIdleLayer: Color(0xFF110000),
    homeIdleLayer: Color(0xFF424242),
    homeIdleCore: Color(0xFF424242),
    panelShadowInk: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    speedIconDown: Color(0xFF01D589),
    speedIconUp: Color(0xFFE83946),
    speedTileJitter: Color(0xFF0A394B),
    speedIconJitter: Color(0xFF008FD5),
    speedTilePing: Color(0xFF3A3C17),
    speedIconPing: Color(0xFFE6D83A),
    stepDim: Color(0xFF15553B),
    obCtaBg: Color(0xFF1C1C1C),
    tileShadow: Color(0x40000000), // rgba(0,0,0,0.25) 0 4 4
  );

  /// The owner-CSS light palette (plus the documented derivations).
  /// v5 («نمای 2»): the committed mockups render the page PURE WHITE
  /// (`#FFFFFF` — pixel-sampled), the cards/tiles `#F4F4F4` (owner CSS
  /// «Rectangle 13» + the measured top tiles), so the light family moves
  /// from the old #EDEDED/#FFFFFF pair to #FFFFFF/#F4F4F4.
  static const AethPal light = AethPal(
    bgScreen: Color(0xFFFFFFFF),
    cardDark: Color(0xFFF4F4F4),
    topTile: Color(0xFFF4F4F4),
    // «3» disconnected: rgba(54,54,54,0.10) — α 0.10 ≈ 0x1A.
    connectBaseIdle: Color(0x1A363636),
    // «3» connected: rgba(26,217,149,0.10) → rgba(47,248,177,0.10).
    connectBaseLiveTop: Color(0x1A1AD995),
    connectBaseLiveBottom: Color(0x1A2FF8B1),
    flagRing: Color(0xFFF4F4F4),
    patternInk: Color(0xFF110000),
    textPrimary: Color(0xFF141C16),
    textSecondary: Color(0xFFA3A3A3),
    statLabel: Color(0xFFA3A3A3),
    onPillConnected: Color(0xFF141C16),
    onPillDisconnected: Color(0xFF141C16),
    statDownBg: Color(0x4D00D589), // rgba(0,213,137,0.30)
    statUpBg: Color(0x33E63946), // rgba(230,57,70,0.20)
    statUpBorder: Color(0x59E63946), // 35 % of the CSS red
    cardIconBg: Color(0xFFE8ECEA),
    sheetSubtile: Color(0xFFEFEFEF),
    sheetDescCard: Color(0xFFE4E7E5),
    speedTrack: Color(0xFFE0E0E0),
    speedTrackLive: Color(0xFFC8E9DA),
    // v4.35 (owner round 11, item 9): the light-mode start button follows
    // the owner's own CSS — core `#4C4C4C` (44 r17), the idle mid layers
    // back on the rgba(17,0,0,α) family (SAME as night), a WHITE glyph.
    speedCoreRest: Color(0xFF4C4C4C),
    speedIdleLayer: Color(0xFF110000),
    homeIdleLayer: Color(0xFF110000),
    homeIdleCore: Color(0xFF363636),
    panelShadowInk: Color(0x17000000), // rgba(0,0,0,0.09)
    speedIconDown: Color(0xFF00D589),
    speedIconUp: Color(0xFFE63946),
    speedTileJitter: Color(0x26008FD5), // 15 % of the jitter blue
    speedIconJitter: Color(0xFF008FD5),
    speedTilePing: Color(0x2EE6D83A), // 18 % of the ping yellow
    speedIconPing: Color(0xFFE6D83A),
    stepDim: Color(0xFFCBE9DC),
    obCtaBg: Color(0xFFFFFFFF),
    tileShadow: Color(0x00000000), // v4.35 — NO shadow in light mode
  );

  /// Field-for-field interpolation (the animation's per-frame work).
  static AethPal lerp(AethPal a, AethPal b, double t) => AethPal(
        bgScreen: Color.lerp(a.bgScreen, b.bgScreen, t)!,
        cardDark: Color.lerp(a.cardDark, b.cardDark, t)!,
        topTile: Color.lerp(a.topTile, b.topTile, t)!,
        connectBaseIdle: Color.lerp(a.connectBaseIdle, b.connectBaseIdle, t)!,
        connectBaseLiveTop:
            Color.lerp(a.connectBaseLiveTop, b.connectBaseLiveTop, t)!,
        connectBaseLiveBottom:
            Color.lerp(a.connectBaseLiveBottom, b.connectBaseLiveBottom, t)!,
        flagRing: Color.lerp(a.flagRing, b.flagRing, t)!,
        patternInk: Color.lerp(a.patternInk, b.patternInk, t)!,
        textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
        textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
        statLabel: Color.lerp(a.statLabel, b.statLabel, t)!,
        onPillConnected: Color.lerp(a.onPillConnected, b.onPillConnected, t)!,
        onPillDisconnected:
            Color.lerp(a.onPillDisconnected, b.onPillDisconnected, t)!,
        statDownBg: Color.lerp(a.statDownBg, b.statDownBg, t)!,
        statUpBg: Color.lerp(a.statUpBg, b.statUpBg, t)!,
        statUpBorder: Color.lerp(a.statUpBorder, b.statUpBorder, t)!,
        cardIconBg: Color.lerp(a.cardIconBg, b.cardIconBg, t)!,
        sheetSubtile: Color.lerp(a.sheetSubtile, b.sheetSubtile, t)!,
        sheetDescCard: Color.lerp(a.sheetDescCard, b.sheetDescCard, t)!,
        speedTrack: Color.lerp(a.speedTrack, b.speedTrack, t)!,
        speedTrackLive: Color.lerp(a.speedTrackLive, b.speedTrackLive, t)!,
        speedCoreRest: Color.lerp(a.speedCoreRest, b.speedCoreRest, t)!,
        speedIdleLayer: Color.lerp(a.speedIdleLayer, b.speedIdleLayer, t)!,
        homeIdleLayer: Color.lerp(a.homeIdleLayer, b.homeIdleLayer, t)!,
        homeIdleCore: Color.lerp(a.homeIdleCore, b.homeIdleCore, t)!,
        panelShadowInk: Color.lerp(a.panelShadowInk, b.panelShadowInk, t)!,
        speedIconDown: Color.lerp(a.speedIconDown, b.speedIconDown, t)!,
        speedIconUp: Color.lerp(a.speedIconUp, b.speedIconUp, t)!,
        speedTileJitter: Color.lerp(a.speedTileJitter, b.speedTileJitter, t)!,
        speedIconJitter: Color.lerp(a.speedIconJitter, b.speedIconJitter, t)!,
        speedTilePing: Color.lerp(a.speedTilePing, b.speedTilePing, t)!,
        speedIconPing: Color.lerp(a.speedIconPing, b.speedIconPing, t)!,
        stepDim: Color.lerp(a.stepDim, b.stepDim, t)!,
        obCtaBg: Color.lerp(a.obCtaBg, b.obCtaBg, t)!,
        tileShadow: Color.lerp(a.tileShadow, b.tileShadow, t)!,
      );
}

/// The process-wide palette slot every `AethColors` getter reads. The app
/// shell sets it before the first frame (the persisted mode, no animation)
/// and re-lerps it on every frame of the 420 ms mode tween.
abstract final class AethThemeSync {
  static AethPal palette = AethPal.night;

  /// v4.40 — the RESOLVED light-ness (the theme clock past its midpoint):
  /// the protocol-icon variants (owner round 16) and any other binary
  /// theme pick read this. Set by the shell's `_applyPalette`, so it
  /// cross-fades with the same tween and follows the AUTO schedule.
  static bool light = false;
}
