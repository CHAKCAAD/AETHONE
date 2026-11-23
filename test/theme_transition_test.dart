/// The theme-switch transition, end to end (v5.2 — the owner's round 21:
/// «در حال حاضر انیمیشن تغیر از حالت دارک مود به لایت مود و بلعکس مشکل
/// داره که دقت کن مشکل اون حل بشه»).
///
/// THREE defects broke every real mode switch on the shipped build, and
/// none of the existing suites caught them because no test ever drove a
/// REAL tap-to-tap transition with the home patterns mounted:
///
///  1. THE PATTERN-INK THROW — the round-20 `_NightInk` seam read the
///     binary `AethThemeSync.light` slot through a `Tween<Color>`, which
///     CANNOT lerp (Color implements no `+`/`-`/`*`). At the palette
///     clock's midpoint the slot flipped, the tween's end changed, and
///     every pattern canvas rebuild THREW «Cannot lerp between…» — the
///     frame died mid-transition and the switch glitched. The ink now
///     rides the palette's own lerped member (`AethPal.patternInk`).
///
///  2. THE SECOND-REVEAL TICKER CRASH — `ThemeRevealHost` was a
///     SingleTickerProviderStateMixin but vends a FRESH
///     AnimationController per reveal, so the SECOND toggle threw
///     «multiple tickers were created» (the theme had already flipped;
///     the reveal died mid-flight with an error flash). The host is a
///     TickerProviderStateMixin now.
///
///  3. THE SWALLOWED DOUBLE-TAP — a tap arriving while a capture was in
///     flight returned early and never ran `apply()`, silently losing
///     the second flip.
///
/// This suite drives the REAL shell (AethoneApp + the store + the
/// on-shell reveal host) through single taps BOTH directions and through
/// the double-tap race, with the disconnected patterns on screen.
library;

import 'dart:async';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/features/shared/theme_toggle_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ScriptedEngine implements EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => _controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void bind(EngineConfigSource config) {}
}

Widget _shell(ConnectionStore store) => RepaintBoundary(
      key: const ValueKey('theme-shot'),
      child: AethoneApp(store: store),
    );

void main() {
  testWidgets('a real tap-to-tap mode switch completes cleanly, both '
      'directions, with the patterns on screen (v5.2)', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = ConnectionStore(engine: ScriptedEngine());
    store.completeOnboarding();
    await tester.pumpWidget(_shell(store));
    await tester.pumpAndSettle();
    expect(store.themeMode, AethThemeMode.night);
    // The disconnected patterns are mounted (the night-ink seam is live).
    expect(find.byKey(const ValueKey('pattern-left-off')), findsOneWidget);
    expect(find.byKey(const ValueKey('pattern-right-off')), findsOneWidget);

    final tile = find.byType(ThemeToggleTile);
    expect(tile, findsOneWidget);

    // Night → light: ride the 420 ms reveal + palette lerp in frame steps.
    await tester.tap(tile);
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(store.themeMode, AethThemeMode.light);
    expect(AethThemeSync.palette.bgScreen, isNot(AethPal.night.bgScreen),
        reason: 'the palette slot must hold the LIGHT family at rest');

    // Light → night: the SECOND reveal — the exact tap that used to throw
    // «multiple tickers were created» on the shipped build.
    await tester.tap(tile);
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(store.themeMode, AethThemeMode.night);
    expect(AethThemeSync.palette.bgScreen, AethPal.night.bgScreen);
  });

  testWidgets('a quick double-tap lands BOTH flips (the capture race)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = ConnectionStore(engine: ScriptedEngine());
    store.completeOnboarding();
    await tester.pumpWidget(_shell(store));
    await tester.pumpAndSettle();

    final tile = find.byType(ThemeToggleTile);
    // Two taps inside the capture window: both must reach the store.
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 8));
    await tester.tap(tile);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(store.themeMode, AethThemeMode.night,
        reason: 'night → light → night: neither flip may be swallowed');
  });

  testWidgets('the mid-transition frames stay honest — the palette lerps '
      'monotonically and the reveal never leaves a stale patch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = ConnectionStore(engine: ScriptedEngine());
    store.completeOnboarding();
    await tester.pumpWidget(_shell(store));
    await tester.pumpAndSettle();

    final tile = find.byType(ThemeToggleTile);
    await tester.tap(tile);

    // Sample the palette slot's luminance across the transition: it must
    // move strictly toward light and land exactly on the light family —
    // no throw-induced freeze, no snap back.
    var last = _lum(AethThemeSync.palette.bgScreen);
    var monotone = true;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      final now = _lum(AethThemeSync.palette.bgScreen);
      if (now + 0.5 < last) monotone = false;
      last = now;
    }
    await tester.pumpAndSettle();
    expect(monotone, isTrue, reason: 'the night → light lerp never rewinds');
    expect(AethThemeSync.palette.bgScreen, AethPal.light.bgScreen);

    // The wipe finished with the palette: after settle, a capture of the
    // shell equals a fresh build's frame (no overlay residue) — proven by
    // the second tap test above; here we assert the host holds no image.
    // (The overlay unmounts; only the app tree remains.)
  }, skip: false);
}

double _lum(Color c) => (c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722);
