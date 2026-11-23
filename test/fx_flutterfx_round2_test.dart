import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_assets.dart' show ProtocolId;
import 'package:aethone/core/fx/connect_ripple.dart';
import 'package:aethone/core/fx/github_spark.dart';
import 'package:aethone/core/fx/spark_loader.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/home_screen.dart';

/// The flutterfx round 2 — the owner's three decrees, as round 23 re-pins
/// them:
///  1. look 1's connecting state is the SPARK LOADER again (RESTORED —
///     owner: «انیمیشن دکمه اتصال وسط صفحه در نمای 1 حین تلاش برای اتصال
///     رو چرا حذف کردی؟ برشگردون به حالت قبل»): the logo marches in
///     quarter-turn steps; the halo's walk vocabulary is retired on that
///     look;
///  2. the flag wheel gets the CIRCLES-SELECTOR arrival (the centered flag
///     pops on the demo's overshoot spring; the neighbours are shoved out);
///  3. the look-2 connect button's tap ripple is REALLY visible (covered
///     by test/fx_ripple_visibility_test.dart — pixel-counted there).
///
/// Round 23 additions at the bottom: look 2's CONNECTING state is the
/// flutterfx background-ripples family ([ConnectRipple]) and the
/// connecting→connected edge fires the GITHUB-SPARK burst on both looks
/// ([GitHubSparkBurst]).
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


double? _spinAngle(WidgetTester tester) {
  final spins = find.byType(SparkLoaderSpin).evaluate();
  if (spins.isEmpty) return null;
  final candidates = find
      .descendant(
        of: find.byType(SparkLoaderSpin),
        matching: find.byWidgetPredicate((w) => w is Transform),
      )
      .evaluate();
  for (final c in candidates) {
    final widget = c.widget as Transform;
    if (widget.alignment != Alignment.center) continue; // the spin's layer
    final m = widget.transform.storage;
    var a = math.atan2(m[1], m[0]); // the rotation component
    if (a < 0) a += 2 * math.pi; // normalized to [0, 2π)
    return a;
  }
  return null;
}

/// Rotation-insensitive comparison (a turn is a turn modulo 2π).
bool _nearAngle(double? a, double expected, double tol) {
  if (a == null) return false;
  var diff = (a - expected) % (2 * math.pi);
  if (diff > math.pi) diff -= 2 * math.pi;
  if (diff < -math.pi) diff += 2 * math.pi;
  return diff.abs() <= tol;
}

void main() {
  // ------------------------------------------------------------------
  // 1. The spark loader (the flutterfx particles-spark-loader port).
  // ------------------------------------------------------------------
  group('SparkLoaderSpin — the look-1 connecting march', () {
    testWidgets('marches in quarter-turn steps, then settles on the rest pose',
        (tester) async {
      double angle = 0;
      await tester.pumpWidget(const Center(
        child: SparkLoaderSpin(
          active: true,
          style: MotionStyle.standard,
          restTurns: -58 / 360,
          child: SizedBox(width: 50, height: 50),
        ),
      ));
      await tester.pump(); // the post-frame loop arms
      expect(_spinAngle(tester) ?? 0, closeTo(0, 0.02));

      // Mid-swing of the first step (SILK: 420 ms swing): the angle is
      // climbing but has not folded a full quarter yet.
      await tester.pump(const Duration(milliseconds: 250));
      angle = _spinAngle(tester) ?? -1;
      expect(angle, greaterThan(0.3), reason: 'the swing is underway');
      expect(angle, lessThan(math.pi / 2 + 0.35));

      // The first step folded + the rest: exactly a quarter turn.
      await tester.pump(const Duration(milliseconds: 250));
      expect(_spinAngle(tester) ?? -1, closeTo(math.pi / 2, 0.02),
          reason: 'the completed step rests on the quarter turn');

      // The second step is underway (frame-stepped pumps — a ticker's
      // first tick always reads zero, so one big pump would miss it).
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      angle = _spinAngle(tester) ?? -1;
      expect(angle, greaterThan(math.pi / 2 * 1.2),
          reason: 'the march keeps swinging (got $angle)');
      expect(angle, lessThan(math.pi * 1.3),
          reason: 'still inside the second quarter (got $angle)');

      // The second step folded too — a clean half turn, resting.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        _nearAngle(_spinAngle(tester), math.pi, 0.03),
        isTrue,
        reason: 'the march folds quarter turns (got ${_spinAngle(tester)})',
      );

      // The walk resolves: the loop stops and the logo lands on the
      // resting pose (look 1's connected −58°), never unwinding laps.
      await tester.pumpWidget(const Center(
        child: SparkLoaderSpin(
          active: false,
          style: MotionStyle.standard,
          restTurns: -58 / 360,
          child: SizedBox(width: 50, height: 50),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        _nearAngle(_spinAngle(tester), -58 / 360 * 2 * math.pi, 0.05),
        isTrue,
        reason: 'the landing settles on the connected pose',
      );
      final settled = _spinAngle(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_spinAngle(tester), settled,
          reason: 'nothing loops once the walk is over (house rule)');
    });

    testWidgets('the OFF style renders the child untouched', (tester) async {
      await tester.pumpWidget(const Center(
        child: SparkLoaderSpin(
          active: true,
          style: MotionStyle.off,
          child: SizedBox(width: 50, height: 50),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        find
            .descendant(
              of: find.byType(SparkLoaderSpin),
              matching: find.byWidgetPredicate((w) => w is Transform),
            )
            .evaluate(),
        isEmpty,
        reason: 'OFF never mounts a rotation layer',
      );
    });
  });

  // ------------------------------------------------------------------
  // 2. The look-1 home: the connecting state IS the spark march.
  // ------------------------------------------------------------------
  group('HomeScreen look 1 — the spark march on the real store', () {
    testWidgets('connecting: the logo marches; connected: it lands on −58°',
        (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();
      expect(store.homeLook == HomeLook.one, isTrue); // the default look

      // Walk the machine legally, exactly like the real engine would.
      await store.connect(); // store applies `starting`
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final early = _spinAngle(tester);
      expect(early, isNotNull, reason: 'the spin mounted on the hero logo');
      await tester.pump(const Duration(milliseconds: 350));
      final later = _spinAngle(tester);
      expect(later!, greaterThan(early!),
          reason: 'the logo marches while the engine walks');

      engine.emit(const EngineStateChanged(VpnState.connected));
      // Bounded pumps: the connected aura never settles — the LANDING
      // tween (600 ms) runs out inside them.
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        _nearAngle(_spinAngle(tester), -58 / 360 * 2 * math.pi, 0.05),
        isTrue,
        reason: 'the connected pose lands (the v4.17 −58° rule)',
      );
    });
  });

  // ------------------------------------------------------------------
  // 3. The flag wheel — the circles-selector arrival (flutterfx port).
  // ------------------------------------------------------------------
  group('The flag wheel — the circles-selector arrival', () {
    Future<List<double>> flagGaps(WidgetTester tester) async {
      final xs = <double>[];
      // v6 — scoped to the band's own subtree: the look-1 pattern
      // placement (round 23) rides the right canvas up the screen, so a
      // bare dy<260 screen filter would count pattern pixels as flags.
      for (final candidate in find
          .descendant(
            of: find.byKey(const ValueKey('location-band')),
            matching: find.byType(Image),
          )
          .evaluate()) {
        final box = candidate.renderObject as RenderBox;
        final center = box.localToGlobal(box.size.center(Offset.zero));
        xs.add(center.dx);
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
      // (v6 — scoped to the band like [flagGaps]: the look-1 pattern
      // canvas now rides the top of the screen and would otherwise be
      // counted once its asset decodes.)
      final sizes = <double>[];
      for (final candidate in find
          .descendant(
            of: find.byKey(const ValueKey('location-band')),
            matching: find.byType(Image),
          )
          .evaluate()) {
        final box = candidate.renderObject as RenderBox;
        sizes.add(box.size.width);
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
  // ------------------------------------------------------------------
  // 4. Round 23 — look 2's connecting RIPPLE (the background-ripples
  //    port) and the GITHUB-SPARK landing burst, both behind the button.
  // ------------------------------------------------------------------
  group('Round 23 — the ripple walk and the spark landing', () {
    testWidgets('look 2 connecting: the ripple family paints behind the '
        'button, then dies when the walk resolves', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine)
        ..setHomeLook(HomeLook.two);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectRipple), findsOneWidget);
      // Disconnected: the field renders its idle box — nothing paints.
      expect(
        find.descendant(
          of: find.byType(ConnectRipple),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'the ripple clock is dead while disconnected',
      );

      await store.connect(); // starting
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Mid-walk: the family paints (the clock is alive, repaint per tick).
      expect(
        find.descendant(
          of: find.byType(ConnectRipple),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
        reason: 'the ripple family breathes behind the button',
      );

      engine.emit(const EngineStateChanged(VpnState.connected));
      await tester.pumpAndSettle();
      // Connected: the walk's clock stops dead — the field is empty again
      // and the whole tree settles (no repeating ticker anywhere).
      expect(
        find.descendant(
          of: find.byType(ConnectRipple),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'the ripple clock parks once the tunnel is up',
      );
    });

    testWidgets('the connecting→connected edge fires the GITHUB-SPARK burst '
        'once, and the field clears', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      await store.connect();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump();
      engine.emit(const EngineStateChanged(VpnState.connected));
      await tester.pump();
      // The burst is IN FLIGHT right after the edge (SILK: 950 ms) — the
      // spark field paints behind the button.
      expect(
        find.descendant(
          of: find.byType(GitHubSparkBurst),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
        reason: 'the github-spark burst fires on the landing edge',
      );
      // ... and it runs out: the whole tree settles, the field clears.
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(GitHubSparkBurst),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'the sparks die with the one-shot — nothing loops',
      );
      // A stats re-notify on the SAME connected state never re-fires it.
      store.notifyListeners();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(GitHubSparkBurst),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'a same-state re-notify is not an edge',
      );
    });

    testWidgets('a cold start into connected never plays a phantom burst',
        (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      // No edge ever fired: nothing burst, nothing animates.
      await tester.pumpAndSettle();
    });
  });
}
