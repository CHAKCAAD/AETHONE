import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/settings_persistence.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/core/design_tokens.dart';
import 'package:aethone/features/shared/theme_toggle_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v4.34 — LIGHT MODE (owner round 10): the palette pair, the lerp the
/// shell's 420 ms tween rides, the tokens' delegation to the palette slot,
/// the store's mode + its persistence, and the sun/moon toggle tile
/// itself. If a test here fails, a light-mode mapping was changed without
/// a design decision — do NOT "fix" the test to match the new value.
void main() {
  setUp(() {
    // The palette slot is process-wide — every test starts from night.
    AethThemeSync.palette = AethPal.night;
  });

  group('the owner-CSS light palette (both home frames)', () {
    test('the named surfaces map exactly (bg / cards / ink / secondary)', () {
      const l = AethPal.light;
      // v5 («نمای 2»): the committed mockups render the page PURE WHITE
      // and the cards/tiles #F4F4F4 (owner CSS «Rectangle 13» + the
      // measured top tiles).
      expect(l.bgScreen, const Color(0xFFFFFFFF)); // «نمای 2» frames
      expect(l.cardDark, const Color(0xFFF4F4F4)); // «Rectangle 13»
      expect(l.topTile, const Color(0xFFF4F4F4)); // the measured tiles
      expect(l.textPrimary, const Color(0xFF141C16)); // «color: #141C16»
      expect(l.textSecondary, const Color(0xFFA3A3A3)); // «UP:»/«DOWN:»
      expect(l.onPillConnected, const Color(0xFF141C16)); // «مــتـصـل»
      expect(l.onPillDisconnected, const Color(0xFF141C16)); // «قــطــع!»
      // v5.3 — the look-2 connect BASE is the state-tinted translucent
      // layer now: rgba(54,54,54,.10) idle, the vertical green pair
      // rgba(26,217,149,.10) → rgba(47,248,177,.10) connected.
      expect(l.connectBaseIdle, const Color(0x1A363636));
      expect(l.connectBaseLiveTop, const Color(0x1A1AD995));
      expect(l.connectBaseLiveBottom, const Color(0x1A2FF8B1));
      expect(l.flagRing, const Color(0xFFF4F4F4)); // «Ellipse 74»
      // v5.3 — the home speed button's idle family + the sheet shadow ink.
      expect(l.homeIdleLayer, const Color(0xFF110000));
      expect(l.homeIdleCore, const Color(0xFF363636));
      expect(l.panelShadowInk, const Color(0x17000000));
    });

    test('the stat icon boxes go translucent (Rectangle 11 / 12)', () {
      const l = AethPal.light;
      // rgba(0,213,137,0.30) — the DOWN box.
      expect(l.statDownBg, const Color(0x4D00D589));
      // rgba(230,57,70,0.20) — the UP box.
      expect(l.statUpBg, const Color(0x33E63946));
    });

    test('the night palette keeps every evidence-locked value', () {
      const n = AethPal.night;
      // v5.3 — the owner's dark-mode round: «بکگراند کل صفحه باید کد رنگی
      // 000000 داشته باشه و بکگراند کارت ها باید رنگ 1C1C1C داشته باشه».
      expect(n.bgScreen, const Color(0xFF000000));
      expect(n.cardDark, const Color(0xFF1C1C1C));
      expect(n.topTile, const Color(0xFF1C1C1C));
      expect(n.textPrimary, const Color(0xFFFFFFFF));
      expect(n.textSecondary, const Color(0xFF8E8E93));
      expect(n.onPillConnected, const Color(0xFF123E2B));
      expect(n.onPillDisconnected, const Color(0xFF75160F));
      expect(n.statDownBg, const Color(0xFF0A4F33));
      expect(n.statUpBg, const Color(0xFF3A1C1C));
      expect(n.speedCoreRest, const Color(0xFF080C09));
      expect(n.obCtaBg, const Color(0xFF1C1C1C));
      // v5.3 — the new dark CSS: the connect BASE tints, the flag ring,
      // the home speed button's idle family, the WHITE sheet shadow.
      expect(n.connectBaseIdle, const Color(0x30424242));
      expect(n.connectBaseLiveTop, const Color(0x0D1AD995));
      expect(n.connectBaseLiveBottom, const Color(0x0D1AD995));
      expect(n.flagRing, const Color(0xFF1C1C1C));
      expect(n.homeIdleLayer, const Color(0xFF424242));
      expect(n.homeIdleCore, const Color(0xFF424242));
      expect(n.panelShadowInk, const Color(0x17FFFFFF));
      expect(n.statLabel, const Color(0xFFFFFFFF));
    });

    test('every field differs night → light (the tween has real work)', () {
      const n = AethPal.night;
      const l = AethPal.light;
      var same = <String>[];
      void cmp(String name, Color a, Color b) {
        if (a == b) same.add(name);
      }

      cmp('bgScreen', n.bgScreen, l.bgScreen);
      cmp('cardDark', n.cardDark, l.cardDark);
      cmp('topTile', n.topTile, l.topTile);
      cmp('connectBaseIdle', n.connectBaseIdle, l.connectBaseIdle);
      cmp('connectBaseLiveTop', n.connectBaseLiveTop, l.connectBaseLiveTop);
      cmp(
        'connectBaseLiveBottom',
        n.connectBaseLiveBottom,
        l.connectBaseLiveBottom,
      );
      cmp('flagRing', n.flagRing, l.flagRing);
      cmp('textPrimary', n.textPrimary, l.textPrimary);
      cmp('textSecondary', n.textSecondary, l.textSecondary);
      cmp('statLabel', n.statLabel, l.statLabel);
      cmp('onPillConnected', n.onPillConnected, l.onPillConnected);
      cmp('onPillDisconnected', n.onPillDisconnected, l.onPillDisconnected);
      cmp('statDownBg', n.statDownBg, l.statDownBg);
      cmp('statUpBg', n.statUpBg, l.statUpBg);
      cmp('statUpBorder', n.statUpBorder, l.statUpBorder);
      cmp('cardIconBg', n.cardIconBg, l.cardIconBg);
      cmp('sheetSubtile', n.sheetSubtile, l.sheetSubtile);
      cmp('sheetDescCard', n.sheetDescCard, l.sheetDescCard);
      cmp('speedTrack', n.speedTrack, l.speedTrack);
      cmp('speedTrackLive', n.speedTrackLive, l.speedTrackLive);
      cmp('speedCoreRest', n.speedCoreRest, l.speedCoreRest);
      cmp('homeIdleLayer', n.homeIdleLayer, l.homeIdleLayer);
      cmp('homeIdleCore', n.homeIdleCore, l.homeIdleCore);
      cmp('panelShadowInk', n.panelShadowInk, l.panelShadowInk);
      // v4.35 (owner round 11, item 9): speedIdleLayer is DELIBERATELY
      // mode-stable — the light rest button keeps the night rgba(17,0,0,α)
      // inner layers (the owner's own CSS); it joins the carve-out below.
      cmp('speedTileJitter', n.speedTileJitter, l.speedTileJitter);
      cmp('speedTilePing', n.speedTilePing, l.speedTilePing);
      cmp('stepDim', n.stepDim, l.stepDim);
      cmp('obCtaBg', n.obCtaBg, l.obCtaBg);
      cmp('tileShadow', n.tileShadow, l.tileShadow);
      expect(
        same,
        isEmpty,
        reason: 'fields identical in both modes carried no theme: $same',
      );
      // Deliberately mode-stable fields (NOT in `same`): the two icon inks
      // the CSS keeps in light mode, and — v4.35, item 9 — speedIdleLayer
      // (the rgba(17,0,0,α) rest layers, identical by the owner's light
      // CSS decree).
    });
  });

  group('AethPal.lerp — the shell tween\'s per-frame work', () {
    test('endpoints are exact', () {
      expect(
        AethPal.lerp(AethPal.night, AethPal.light, 0).bgScreen,
        AethPal.night.bgScreen,
      );
      expect(
        AethPal.lerp(AethPal.night, AethPal.light, 1).bgScreen,
        AethPal.light.bgScreen,
      );
    });

    test('the midpoint is halfway on the screen background', () {
      final mid = AethPal.lerp(AethPal.night, AethPal.light, 0.5);
      // #000000 ↔ #FFFFFF at t=.5 — channel-wise average.
      expect(mid.bgScreen, Color.lerp(
        AethPal.night.bgScreen,
        AethPal.light.bgScreen,
        0.5,
      ));
      expect(mid.bgScreen, isNot(AethPal.night.bgScreen));
      expect(mid.bgScreen, isNot(AethPal.light.bgScreen));
    });

    test('every field lerps to a real color (no nulls ever)', () {
      final mid = AethPal.lerp(AethPal.night, AethPal.light, 0.37);
      expect(mid.cardDark, isA<Color>());
      expect(mid.textPrimary, isA<Color>());
      expect(mid.onPillConnected, isA<Color>());
      expect(mid.speedTrack, isA<Color>());
      expect(mid.stepDim, isA<Color>());
    });
  });

  group('the tokens delegate to the palette slot', () {
    test('flipping the slot flips every themed token', () {
      // Night (the setUp default).
      expect(AethColors.bgScreen, AethPal.night.bgScreen);
      expect(AethColors.cardDark, AethPal.night.cardDark);
      expect(AethColors.textPrimary, AethPal.night.textPrimary);
      // Light.
      AethThemeSync.palette = AethPal.light;
      expect(AethColors.bgScreen, AethPal.light.bgScreen);
      expect(AethColors.cardDark, AethPal.light.cardDark);
      expect(AethColors.textPrimary, AethPal.light.textPrimary);
      expect(AethColors.onPillConnected, AethPal.light.onPillConnected);
      expect(AethColors.statUpBg, AethPal.light.statUpBg);
    });

    test('the accent family is mode-STABLE (const in both)', () {
      // The green/red/gold accents never re-theme — the same const the
      // night build shipped, whatever the slot says.
      AethThemeSync.palette = AethPal.light;
      expect(AethColors.accentConnected, const Color(0xFF1AD995));
      expect(AethColors.statusDisconnected, const Color(0xFFEA2323));
      expect(AethColors.goldAccent, const Color(0xFF997A35));
      expect(AethColors.pillGlowOpacity, 0.53);
      expect(AethColors.pillMidOpacity, 0.45);
      expect(AethColors.pillHaloOpacity, 0.19);
    });
  });

  group('ConnectionStore — the mode preference', () {
    ConnectionStore store() =>
        ConnectionStore(engine: EngineNotWiredAdapter());

    test('v6.1 default is light; toggle flips and notifies', () {
      final s = store();
      expect(s.themeMode, AethThemeMode.light);
      var notified = 0;
      s.addListener(() => notified++);
      s.toggleThemeMode();
      expect(s.themeMode, AethThemeMode.night);
      expect(notified, 1);
      s.toggleThemeMode();
      expect(s.themeMode, AethThemeMode.light);
      expect(notified, 2);
    });

    test('setThemeMode to the SAME mode is a silent no-op', () {
      final s = store();
      var notified = 0;
      s.addListener(() => notified++);
      s.setThemeMode(AethThemeMode.light);
      expect(notified, 0);
    });

    test('the mode persists and restores (missing key = light)', () async {
      SharedPreferences.setMockInitialValues({});
      final a = store();
      // v4.40 — the PICK owns the preference (night / light / auto);
      // [themeMode] is the resolved render mode.
      a.setThemePick(AethThemePick.night);
      await SettingsPersistence().save(a);

      final b = store();
      expect(b.themeMode, AethThemeMode.light); // before: the v6.1 default
      await SettingsPersistence().restore(b);
      expect(b.themeMode, AethThemeMode.night); // after: the saved pick
      expect(b.themePick, AethThemePick.night);
    });

    test('v4.40 — a legacy install (only the old themeMode key) seeds the '
        'pick and keeps its face', () async {
      SharedPreferences.setMockInitialValues({
        'aethone.settings.themeMode': 'light',
      });
      final b = store();
      await SettingsPersistence().restore(b);
      expect(b.themePick, AethThemePick.light);
      expect(b.themeMode, AethThemeMode.light);
    });

    test('v4.40 — AUTO resolves by the clock and follows the boundary', () {
      // The owner's schedule: 06:00–18:00 light, 18:00–06:00 night.
      expect(
        resolveAutoTheme(DateTime(2026, 11, 7, 6, 0)),
        AethThemeMode.light,
      );
      expect(
        resolveAutoTheme(DateTime(2026, 11, 7, 11, 59)),
        AethThemeMode.light,
      );
      expect(
        resolveAutoTheme(DateTime(2026, 11, 7, 17, 59)),
        AethThemeMode.light,
      );
      expect(
        resolveAutoTheme(DateTime(2026, 11, 7, 18, 0)),
        AethThemeMode.night,
      );
      expect(
        resolveAutoTheme(DateTime(2026, 11, 7, 5, 59)),
        AethThemeMode.night,
      );
      expect(
        resolveAutoTheme(DateTime(2026, 11, 7, 0, 0)),
        AethThemeMode.night,
      );
    });

    test('v4.40 — the AUTO schedule tick moves the resolved mode only at the '
        'boundary', () {
      final s = store();
      s.setThemePick(AethThemePick.auto);
      final AethThemeMode now = s.themeMode; // whatever the wall clock says
      // A same-side tick is a silent no-op.
      final sameSide = now == AethThemeMode.night
          ? DateTime(2026, 11, 7, 23, 0) // night-side too
          : DateTime(2026, 11, 7, 12, 0); // day-side too
      expect(s.applyAutoThemeSchedule(sameSide), false);
      expect(s.themeMode, now);
      // Crossing to the other side moves the mode and notifies.
      final other = now == AethThemeMode.night
          ? DateTime(2026, 11, 7, 12, 0) // daytime — light
          : DateTime(2026, 11, 7, 23, 0); // night — night
      expect(s.applyAutoThemeSchedule(other), true);
      expect(
        s.themeMode,
        now == AethThemeMode.night
            ? AethThemeMode.light
            : AethThemeMode.night,
      );
    });
  });

  group('ThemeToggleTile — the sun/moon switch itself', () {
    testWidgets('light shows the Sun glyph; a tap flips to Moon', (
      tester,
    ) async {
      final s = ConnectionStore(engine: EngineNotWiredAdapter());
      // The real app rebuilds the tree through the shell's AnimatedBuilder
      // (AethoneApp listens to the store); the tile itself is stateless —
      // mimic that listener here so the glyph refreshes on the flip.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedBuilder(
                animation: s,
                builder: (context, _) => ThemeToggleTile(
                  store: s,
                  size: 50,
                  iconSize: 24,
                  tileKey: const ValueKey('theme-tile'),
                ),
              ),
            ),
          ),
        ),
      );

      // Light (the v6.1 default): the Sun glyph (keyed true), and the
      // semantics promise a switch TO night mode.
      expect(
        find.byWidgetPredicate(
          (w) => w.key == const ValueKey<bool>(true),
        ),
        findsOneWidget,
        reason: 'light renders the sun-keyed glyph',
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains('night mode'),
        ),
        findsOneWidget,
      );
      expect(s.themeMode, AethThemeMode.light);

      // Tap the tile — the mode flips.
      await tester.tap(find.byKey(const ValueKey('theme-tile')));
      await tester.pumpAndSettle();
      expect(s.themeMode, AethThemeMode.night);
      expect(
        find.byWidgetPredicate(
          (w) => w.key == const ValueKey<bool>(false),
        ),
        findsOneWidget,
        reason: 'night renders the moon-keyed glyph',
      );
      // The semantic label tells the switcher what it does.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains('light mode'),
        ),
        findsOneWidget,
      );
      // The Sun 1 / Moon assets are the owner-named files.
      expect(AppAssets.iconSun1, contains('Sun 1.svg'));
      expect(AppAssets.iconMoon, contains('Moon.svg'));
    });
  });
}
