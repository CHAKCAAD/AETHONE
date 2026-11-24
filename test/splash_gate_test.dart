/// v6.1 — the SPLASH GATE's own suite («اسپلش اسکرین»): the factory
/// LIGHT face renders the beat PURE WHITE with the app logo centred at
/// [AethGeometry.splashLogoSize]; a night pick renders the app's own dark
/// face («اسپلش اسکرین هم باید از تم تبعیت کنه»); the master kill-switch
/// mounts no overlay at all; and while the beat plays the child beneath
/// stays mounted and TAPPABLE (the overlay is IgnorePointer — art never
/// holds the first screen hostage).
library;

import 'dart:async';

import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/core/design_tokens.dart';
import 'package:aethone/features/shared/splash_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdleEngine implements EngineAdapter {
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

void main() {
  // The shell owns the palette slot in the real app (AethoneApp applies the
  // restored mode before the first frame); these tests drive it directly
  // the same way, and put it back for the suites that follow.
  final savedPalette = AethThemeSync.palette;
  final savedLight = AethThemeSync.light;
  tearDown(() {
    AethThemeSync.palette = savedPalette;
    AethThemeSync.light = savedLight;
  });

  testWidgets('the factory light face: pure white, the logo centred at '
      'the token size, then the beat yields', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AethThemeSync.palette = AethPal.light;
    AethThemeSync.light = true;

    final store = ConnectionStore(engine: _IdleEngine());
    await tester.pumpWidget(
      MaterialApp(
        home: SplashGate(
          store: store,
          child: const Scaffold(
            body: Center(child: Text('first-screen')),
          ),
        ),
      ),
    );

    // Frame one: the splash surface is up — PURE WHITE (the owner's
    // decree, brighter than the light bgScreen #EDEDED) — carrying the
    // logo at the measured size, dead centre.
    expect(find.byKey(const ValueKey('splash-surface')), findsOneWidget);
    final surface = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('splash-surface')),
    );
    expect(surface.color, const Color(0xFFFFFFFF));

    final logo = find.byType(SvgPicture);
    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size(140, 140));
    expect(
      tester.getCenter(logo),
      const Offset(201, 437),
      reason: '«لوگو اپ رو هم در وسط صفحه» — dead centre',
    );

    // The beat runs out and the overlay unmounts, never to return.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('splash-surface')), findsNothing);
    expect(find.text('first-screen'), findsOneWidget);
  });

  testWidgets('a night pick: the splash follows the app theme (the dark '
      'face, never white)', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AethThemeSync.palette = AethPal.night;
    AethThemeSync.light = false;

    final store = ConnectionStore(engine: _IdleEngine());
    store.setThemePick(AethThemePick.night);
    await tester.pumpWidget(
      MaterialApp(
        home: SplashGate(
          store: store,
          child: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('splash-surface')), findsOneWidget);
    final surface = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('splash-surface')),
    );
    expect(surface.color, AethPal.night.bgScreen);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('splash-surface')), findsNothing);
  });

  testWidgets('the kill-switch (animations off): no splash layer at all',
      (tester) async {
    final store = ConnectionStore(engine: _IdleEngine());
    store.setAnimationsEnabled(false);
    await tester.pumpWidget(
      MaterialApp(
        home: SplashGate(
          store: store,
          child: const Scaffold(
            body: Center(child: Text('first-screen')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('splash-surface')), findsNothing);
    expect(find.text('first-screen'), findsOneWidget);
  });

  testWidgets('while the beat plays the child beneath stays tappable '
      '(the overlay never swallows a touch)', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AethThemeSync.palette = AethPal.light;
    AethThemeSync.light = true;

    var taps = 0;
    final store = ConnectionStore(engine: _IdleEngine());
    await tester.pumpWidget(
      MaterialApp(
        home: SplashGate(
          store: store,
          child: Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('first-screen-button'),
                onPressed: () => taps++,
                child: const Text('first-screen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('splash-surface')), findsOneWidget);

    // The splash is UP — the tap must reach the button underneath.
    await tester.tap(find.byKey(const ValueKey('first-screen-button')));
    await tester.pump();
    expect(taps, 1);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('splash-surface')), findsNothing);
  });

  test('the token: the logo rides the splash geometry (the ~35 % face)',
      () {
    expect(AethGeometry.splashLogoSize, 140);
    // Light face: PURE WHITE — the owner's decree, brighter than the light
    // bgScreen #EDEDED. Night face: the app's own dark screen family.
    AethThemeSync.palette = AethPal.light;
    AethThemeSync.light = true;
    expect(AethColors.splashBg, const Color(0xFFFFFFFF));
    AethThemeSync.palette = AethPal.night;
    AethThemeSync.light = false;
    expect(AethColors.splashBg, AethPal.night.bgScreen);
  });
}
