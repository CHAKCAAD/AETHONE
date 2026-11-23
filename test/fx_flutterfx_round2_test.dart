import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_assets.dart' show ProtocolId;
import 'package:aethone/features/home/home_screen.dart';

/// The flutterfx round 2 — the owner's three decrees, as v5.3 re-pins
/// them:
///  1. look 1's connecting state carries NO logo animation any more (the
///     spark march is RETIRED — the owner: «در نمای 1 انیمیشن روی دکمه
///     اتصال وسط صفحه باید حذف بشه»); the logo is a STATIC pose machine:
///     0° ⇄ the connected −58° ([AnimatedRotation]);
///  2. the flag wheel gets the CIRCLES-SELECTOR arrival (the centered flag
///     pops on the demo's overshoot spring; the neighbours are shoved out);
///  3. the look-2 connect button's tap ripple is REALLY visible (covered
///     by test/fx_ripple_visibility_test.dart — pixel-counted there).
class ScriptedEngine implements EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  void emit(EngineEvent e) => _controller.add(e);

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void bind(EngineConfigSource config) {}
}

Widget _booth(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );


double? _heroTurns(WidgetTester tester) {
  final rotations = find.byType(AnimatedRotation).evaluate();
  if (rotations.isEmpty) return null;
  return (rotations.first.widget as AnimatedRotation).turns;
}

void main() {
  // ------------------------------------------------------------------
  // 1. The look-1 hero is a STATIC pose machine (v5.3 — the spark march
  //    is retired; only the 0° ⇄ −58° pose crossfade remains).
  // ------------------------------------------------------------------
  group('HomeScreen look 1 — the static hero (v5.3)', () {
    testWidgets('connecting: the logo holds its pose (no march); '
        'connected: it lands on −58° and never loops', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();
      expect(store.homeLook == HomeLook.one, isTrue); // the default look
      expect(_heroTurns(tester), 0, reason: 'the disconnected pose is 0°');

      // Walk the machine legally, exactly like the real engine would.
      await store.connect(); // store applies `starting`
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midWalk = _heroTurns(tester);
      expect(midWalk, 0,
          reason: 'the march is retired — the walk holds the pose');
      await tester.pump(const Duration(milliseconds: 350));
      expect(_heroTurns(tester), 0,
          reason: 'still no march at the walk\u2019s end');

      engine.emit(const EngineStateChanged(VpnState.connected));
      // The landing tween (the pose crossfade) runs out inside the pumps,
      // then NOTHING loops — pumpAndSettle completes.
      await tester.pumpAndSettle();
      expect(
        _heroTurns(tester),
        closeTo(-58 / 360, 1e-9),
        reason: 'the connected pose lands (the v4.17 −58° rule)',
      );
      final settled = _heroTurns(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_heroTurns(tester), settled,
          reason: 'nothing loops once the walk is over (house rule)');
    });
  });

  // ------------------------------------------------------------------
  // 2. The flag wheel — the circles-selector arrival (flutterfx port).
  // ------------------------------------------------------------------
  group('The flag wheel — the circles-selector arrival', () {
    Future<List<double>> flagGaps(WidgetTester tester) async {
      final xs = <double>[];
      for (final candidate in find.byType(Image).evaluate()) {
        final box = candidate.renderObject as RenderBox;
        final center = box.localToGlobal(box.size.center(Offset.zero));
        if (center.dy < 260) xs.add(center.dx); // the flags band only
      }
      xs.sort();
      return [
        for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1],
      ];
    }

    testWidgets(
        'a settled selection keeps the neighbours shoved out (the demo\'s '
        'displacement; the centre rests on the committed 52)',
        (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.selectedProtocol = ProtocolId.psiphonChain;
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // Drag one pitch left (the slow stepped move keeps the release from
      // flinging) — the AUTO entry's next neighbour (اتریش) centres.
      final wheelCenter = tester.getCenter(find.byType(PageView).first);
      final drag = await tester.startGesture(wheelCenter);
      for (var i = 0; i < 3; i++) {
        await drag.moveBy(const Offset(-24, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await drag.moveBy(const Offset(-6, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('اتریش'), findsOneWidget); // the selection moved

      // The circles-selector's live displacement: the two INNER gaps
      // (centre ↔ ±1) widen past the pitch (72 + the shove), the OUTER
      // gaps sit below it (±1 ↔ ±2 at half the falloff).
      final gaps = await flagGaps(tester);
      expect(gaps, isNotEmpty);
      final inner = gaps
          .where((g) => g > 74)
          .length;
      expect(inner, greaterThanOrEqualTo(2),
          reason:
              'the ±1 flags are shoved outward: inner gaps ≈ 78, got $gaps');
      expect(
        gaps.every((g) => g > 60 && g < 90),
        isTrue,
        reason: 'the strip stays composed (no wild displacements): $gaps',
      );

      // The centered flag itself rests EXACTLY on the committed 52 —
      // the frames own the steady state, the pop owns the arrival.
      final sizes = <double>[];
      for (final candidate in find.byType(Image).evaluate()) {
        final box = candidate.renderObject as RenderBox;
        final center = box.localToGlobal(box.size.center(Offset.zero));
        if (center.dy < 260) sizes.add(box.size.width);
      }
      sizes.sort();
      expect(sizes.last, closeTo(52, 1.5),
          reason: 'the centered flag rests on the committed 52');
    });

    testWidgets('OFF parks the springs — the strip stays at its pitch',
        (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.selectedProtocol = ProtocolId.psiphonChain;
      store.setAnimationsEnabled(false); // the kill-switch
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      final gaps = await flagGaps(tester);
      expect(gaps, isNotEmpty);
      expect(
        gaps.every((g) => (g - 72).abs() < 2.0),
        isTrue,
        reason: 'no shove, no pop — the committed pitch everywhere: $gaps',
      );
    });
  });
}
