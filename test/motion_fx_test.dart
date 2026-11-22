/// v8a (owner round 18) — the four animation decrees, regression-pinned
/// on the motion line (feature/motion-phase3, r109 base):
///
///  1. SHIMMER BUTTON — the behind-the-button AURORA of the connected
///     state is RETIRED (the halo is wired with hideConnectedAura: true
///     for BOTH looks); the connected idle life rides the button's OWN
///     EDGE ([ShimmerEdge]) instead; disconnected renders no edge.
///  2. HYPER TEXT — the country-name and ping texts DECODE on change
///     (scramble → resolve); OFF lands instantly; the resting render is
///     the plain text.
///  3. CIRCLE SELECTOR — the selected protocol tile springs up and
///     PUSHES its row siblings aside for the impulse, then everything
///     settles back to the committed geometry; OFF never travels.
///  4. THE GREEN DRIFT EVERYWHERE — the home screen's connected-state
///     animation (the smoke field + the pattern drift) now lives on the
///     OTHER pages too (the protocol page pinned here), under the home
///     rule ([ConnectionStore.patternsAlive]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/fx/smoke_burst.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/protocol_sheet/protocol_sheet.dart';
import 'package:aethone/features/home/widgets/connect_core.dart';
import 'package:aethone/features/home/widgets/shimmer_edge.dart';
import 'package:aethone/features/shared/circle_selector.dart';
import 'package:aethone/features/shared/hyper_text.dart';

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
  void bind(EngineConfigSource config) {} // scripted — config never read
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

Future<void> _useReferenceSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Walks the machine legally into `connected` and lands the stats frame
/// with a bare pump() — the v8a lesson: the Hyper-Text decode timer only
/// arms once the stats rebuild has LANDED, so the caller owns the timed
/// pumps after this.
Future<void> _connect(
  WidgetTester tester,
  ScriptedEngine engine,
  ConnectionStore store, {
  String exitCode = 'ir',
}) async {
  await store.connect();
  engine.emit(const EngineStateChanged(VpnState.connecting));
  await tester.pump(const Duration(milliseconds: 300));
  engine.emit(const EngineStateChanged(VpnState.connected));
  engine.emit(
    EngineStatsUpdated(
      pingMs: 146,
      downBytes: 0,
      upBytes: 0,
      exitCountryCode: exitCode,
    ),
  );
  // A bare pump lands the connected frame; the caller then owns the
  // timed pumps (the decode/roulette windows).
  await tester.pump();
}

void main() {
  // -------------------------------------------------------------------
  // The recipe tokens (the v8a contract).
  // -------------------------------------------------------------------
  group('v8a recipe tokens', () {
    test('every style carries the shimmer/hyper/circle trio', () {
      for (final style in MotionStyle.values) {
        final r = style.recipe;
        if (style == MotionStyle.off) {
          expect(r.shimmerMs, 0, reason: '$style OFF keeps the edge still');
          expect(r.hyperTextMs, 0, reason: '$style OFF lands text instantly');
          expect(r.circleSelectMs, 0);
          expect(r.circleSelectGrow, 0);
          expect(r.circleSelectPush, 0);
        } else {
          expect(r.shimmerMs, greaterThan(0));
          expect(r.hyperTextMs, greaterThan(0));
          expect(r.circleSelectMs, greaterThan(0));
          expect(r.circleSelectGrow, greaterThan(0));
          expect(r.circleSelectPush, greaterThan(0));
        }
      }
    });

    test('the SILK baseline (the owner-approved feel)', () {
      final r = MotionStyle.standard.recipe;
      expect(r.shimmerMs, 3200);
      expect(r.hyperTextMs, 480);
      expect(r.circleSelectMs, 380);
      expect(r.circleSelectGrow, 0.10);
      expect(r.circleSelectPush, 8);
    });

    test('the personalities retune the trio (TIDE slower, SPRING snappier)',
        () {
      expect(MotionStyle.smooth.recipe.shimmerMs, 4800);
      expect(MotionStyle.smooth.recipe.hyperTextMs, 720);
      expect(MotionStyle.dynamic.recipe.circleSelectMs, 320);
      expect(MotionStyle.dynamic.recipe.circleSelectGrow, 0.12);
      expect(MotionStyle.minimal.recipe.hyperTextMs, 192);
    });
  });

  // -------------------------------------------------------------------
  // The Circle-Selector math.
  // -------------------------------------------------------------------
  group('circle selector math', () {
    const curve = CircleImpulseCurve();

    test('the impulse leaves from and returns to zero', () {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 0);
      // The parametric domain is [0,1] (Curve's contract); the endpoints
      // are the rest guarantees the row's Transform decays through.
      expect(curve.transform(0.999), lessThan(0.05));
      expect(curve.transform(0.001), lessThan(0.2));
    });

    test('the impulse overshoots above 1 mid-flight (the spring feel)', () {
      var peak = 0.0;
      for (var t = 0.0; t <= 1.0; t += 0.01) {
        peak = peak < curve.transform(t) ? curve.transform(t) : peak;
      }
      expect(peak, greaterThan(1.0));
    });

    test('the falloff: distance 1 full, each further step 68%', () {
      expect(circleFalloff(0.3), 1);
      expect(circleFalloff(1), closeTo(1.0, 1e-9));
      expect(circleFalloff(2), closeTo(0.68, 1e-9));
      expect(circleFalloff(3), closeTo(0.4624, 1e-9));
    });
  });

  // -------------------------------------------------------------------
  // HYPER TEXT — the decode.
  // -------------------------------------------------------------------
  group('hyper text', () {
    testWidgets('decodes a changed text, then rests on the exact target',
        (tester) async {
      String text = 'ایران';
      late StateSetter setOuter;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return _booth(Scaffold(body: HyperText(text,
              style: MotionStyle.standard)));
        },
      ));
      await tester.pumpAndSettle();
      expect(find.text('ایران'), findsOneWidget);

      setOuter(() => text = 'آمریکا');
      await tester.pump(); // land the rebuild
      await tester.pump(const Duration(milliseconds: 96));
      // Mid-decode: NOT the target — the frontier is partway (5 chars,
      // step 1/3 per 16 ms tick at SILK 480: 6 ticks ≈ 2 chars in).
      expect(find.text('آمریکا'), findsNothing);
      // A space always renders verbatim (never a scramble slot).
      setOuter(() => text = '146 ms');
      await tester.pump(); // land the rebuild (supersedes the old run)
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('146 ms'), findsOneWidget);
    });

    testWidgets('OFF lands the new text instantly (accessibility clamp)',
        (tester) async {
      String text = 'ایران';
      late StateSetter setOuter;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return _booth(Scaffold(
              body: HyperText(text, style: MotionStyle.off)));
        },
      ));
      await tester.pumpAndSettle();
      setOuter(() => text = 'آمریکا');
      await tester.pump();
      expect(find.text('آمریکا'), findsOneWidget);
      await tester.pumpAndSettle(); // no timer was ever armed
    });

    testWidgets('an empty target lands instantly (nothing to decode)',
        (tester) async {
      String text = '146 ms';
      late StateSetter setOuter;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return _booth(Scaffold(body: HyperText(text,
              style: MotionStyle.standard)));
        },
      ));
      await tester.pumpAndSettle();
      setOuter(() => text = '');
      await tester.pump();
      expect(find.text(''), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  // -------------------------------------------------------------------
  // SHIMMER EDGE — the connected button's own edge.
  // -------------------------------------------------------------------
  group('shimmer edge (the connect button)', () {
    testWidgets('look 1: no edge disconnected — the edge appears connected '
        'and repeats (bounded pumps); the aura is retired', (tester) async {
      await _useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // Disconnected: NOTHING rides the hero (the frames' contract).
      expect(find.byType(ShimmerEdge), findsNothing);

      await _connect(tester, engine, store);
      // Bounded pumps — the shimmer laps forever.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('connect-shimmer')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('connect-shimmer')), findsOneWidget);

      // v8a decree 1 — the connected AURORA behind the button is RETIRED
      // on BOTH looks: the halo director is wired with the suppression.
      final halo = tester.widget<ConnectHalo>(find.byType(ConnectHalo));
      expect(halo.hideConnectedAura, isTrue,
          reason: 'the behind-the-button aurora is retired app-wide');
    });

    testWidgets('look 2: the edge rides the Group-45 core squircle',
        (tester) async {
      await _useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine)
        ..setHomeLook(HomeLook.two);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.byType(ShimmerEdge), findsNothing);

      await _connect(tester, engine, store);
      await tester.pump(const Duration(milliseconds: 300));
      final edge = find.byKey(const ValueKey('connect-shimmer'));
      expect(edge, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(edge, findsOneWidget);

      final halo = tester.widget<ConnectHalo>(find.byType(ConnectHalo));
      expect(halo.hideConnectedAura, isTrue);
    });

    testWidgets('OFF style: the static edge stays, nothing repeats — '
        'pumpAndSettle settles', (tester) async {
      await _useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine)
        ..animationStyle = MotionStyle.off;
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      await _connect(tester, engine, store);
      // The OFF recipe keeps the edge as status feedback (no motion):
      // the whole connected tree settles — no repeating ticker anywhere.
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connect-shimmer')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // CIRCLE SELECTOR — the protocol page rows.
  // -------------------------------------------------------------------
  group('circle selector (the protocol page)', () {
    testWidgets('the protocol page: selecting a tile PUSHES its row '
        'siblings apart mid-impulse', (tester) async {
      await _useReferenceSurface(tester);
      final store = ConnectionStore(engine: ScriptedEngine());
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // Open the REAL protocol page (the home card names the MASQUE
      // cold default; the tap opens the page).
      await tester.tap(find.text('ماسک').first);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(ProtocolPage), findsOneWidget);

      // Row 2 (visual right→left): گول · گول کلاسیک · میم. Selecting میم
      // (the visual LEFT tile) must push گول AWAY from it — to the RIGHT.
      final gool = find.byKey(const ValueKey('proto-tile-gool'));
      final restGool = tester.getTopLeft(gool).dx;

      await tester.tap(find.text('میم'));
      await tester.pump(); // the selection frame
      await tester.pump(const Duration(milliseconds: 150)); // mid-impulse
      expect(
        tester.getTopLeft(gool).dx,
        greaterThan(restGool),
        reason: 'the sibling is pushed AWAY from the selected tile',
      );
      // Ride out the auto-pop (300 ms) + the reverse transition.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    });

    testWidgets('a bare row: the push grows, then settles back to the '
        'committed geometry', (tester) async {
      int? selected;
      late StateSetter setOuter;
      const style = MotionStyle.standard;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return _booth(Scaffold(
            body: Center(
              child: CircleSelectRow(
                style: style,
                rtl: true,
                selectedIndex: selected,
                children: const [
                  SizedBox(
                      key: ValueKey('box-0'),
                      width: 80,
                      height: 80,
                      child: ColoredBox(color: Colors.red)),
                  SizedBox(
                      key: ValueKey('box-1'),
                      width: 80,
                      height: 80,
                      child: ColoredBox(color: Colors.green)),
                  SizedBox(
                      key: ValueKey('box-2'),
                      width: 80,
                      height: 80,
                      child: ColoredBox(color: Colors.blue)),
                ],
              ),
            ),
          ));
        },
      ));
      await tester.pumpAndSettle();

      final box0 = find.byKey(const ValueKey('box-0'));
      final box2 = find.byKey(const ValueKey('box-2'));
      final rest0 = tester.getTopLeft(box0).dx;
      final rest2 = tester.getTopLeft(box2).dx;

      // Select the MIDDLE box: both flanks are pushed AWAY (rtl row ⇒
      // box-0 lives at the visual RIGHT, box-2 at the visual LEFT).
      setOuter(() => selected = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150)); // mid-impulse
      expect(tester.getTopLeft(box0).dx, greaterThan(rest0));
      expect(tester.getTopLeft(box2).dx, lessThan(rest2));

      // The impulse decays: the row settles back to its committed slots.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(box0).dx, rest0);
      expect(tester.getTopLeft(box2).dx, rest2);
    });

    testWidgets('OFF style: the selection lands without any travel',
        (tester) async {
      // A bare row under OFF — the page-level variant cannot hold still
      // for a position read: OFF's zero auto-pop delay pops the page on
      // the very next frame, so every tile rides the reverse transition.
      int? selected;
      late StateSetter setOuter;
      const style = MotionStyle.off;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return _booth(Scaffold(
            body: Center(
              child: CircleSelectRow(
                style: style,
                rtl: true,
                selectedIndex: selected,
                children: const [
                  SizedBox(
                      key: ValueKey('box-0'),
                      width: 80,
                      height: 80,
                      child: ColoredBox(color: Colors.red)),
                  SizedBox(
                      key: ValueKey('box-1'),
                      width: 80,
                      height: 80,
                      child: ColoredBox(color: Colors.green)),
                  SizedBox(
                      key: ValueKey('box-2'),
                      width: 80,
                      height: 80,
                      child: ColoredBox(color: Colors.blue)),
                ],
              ),
            ),
          ));
        },
      ));
      await tester.pumpAndSettle();

      final box0 = find.byKey(const ValueKey('box-0'));
      final box1 = find.byKey(const ValueKey('box-1'));
      final box2 = find.byKey(const ValueKey('box-2'));
      final rest0 = tester.getTopLeft(box0).dx;
      final rest1 = tester.getTopLeft(box1).dx;
      final rest2 = tester.getTopLeft(box2).dx;

      setOuter(() => selected = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getTopLeft(box0).dx,
        rest0,
        reason: 'OFF never travels — the row stays at rest',
      );
      expect(tester.getTopLeft(box1).dx, rest1);
      expect(tester.getTopLeft(box2).dx, rest2);
      await tester.pumpAndSettle();
    });
  });

  // -------------------------------------------------------------------
  // THE GREEN DRIFT EVERYWHERE — the other pages' ambience goes alive.
  // -------------------------------------------------------------------
  group('the green connected-state animation on the other pages', () {
    testWidgets('the protocol page smokes + drifts while connected (the '
        'home rule) and rests static while disconnected', (tester) async {
      await _useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // Disconnected: the protocol page's patterns are STATIC — the page
      // settles (no repeating sway ticker) and NO smoke mounts.
      await tester.tap(find.text('ماسک').first);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(ProtocolPage), findsOneWidget);
      expect(find.byType(SmokeField), findsNothing);
      final staticA = tester
          .getTopLeft(find.byKey(const ValueKey('pattern-left-off')))
          .dy;
      await tester.pump(const Duration(seconds: 1));
      final staticB = tester
          .getTopLeft(find.byKey(const ValueKey('pattern-left-off')))
          .dy;
      expect(staticB, staticA, reason: 'disconnected ⇒ no drift');

      // Leave the page, connect, come back: the SAME page now smokes and
      // drifts.
      await tester.tap(find.byKey(const ValueKey('proto-page-back')));
      await tester.pump();
      await tester.pumpAndSettle();
      await _connect(tester, engine, store);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('ماسک').first);
      await tester.pump();
      // Bounded pumps ONLY — the connected page's ambience (smoke +
      // patterns + the home behind it) repeats forever; pumpAndSettle
      // would never settle.
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ProtocolPage), findsOneWidget);
      expect(find.byType(SmokeField), findsOneWidget,
          reason: 'the home screen\'s green smoke now lives here too');

      final aliveA = tester
          .getTopLeft(find.byKey(const ValueKey('pattern-left-on')))
          .dy;
      await tester.pump(const Duration(seconds: 1));
      final aliveB = tester
          .getTopLeft(find.byKey(const ValueKey('pattern-left-on')))
          .dy;
      await tester.pump(const Duration(seconds: 1));
      final aliveC = tester
          .getTopLeft(find.byKey(const ValueKey('pattern-left-on')))
          .dy;
      expect(
        <double>{aliveA, aliveB, aliveC}.length,
        greaterThan(1),
        reason: 'connected ⇒ the green patterns drift like the home screen',
      );
    });
  });
}
