/// v1.0.2 motion overhaul — the 12 acceptance axes from the task brief,
/// as executable proof:
///
///  1. all EIGHT connection states carry their own visible language;
///  2. BOTH home looks agree (one shared halo + one toggle path);
///  3. the press is an immediate, springy feedback that never blocks;
///  4. state transitions crossfade (both labels mid-flight, one after);
///  5. page routes carry the style's own personality (OFF = instant);
///  6. card entrances differ by MEANING (EntranceFlavor);
///  7. the five tiers are personalities, not speed knobs (recipe table);
///  8. the master kill-switch: no ambient motion, state feedback KEPT;
///  9. the OS reduce-motion clamp (dynamic/smooth → minimal);
/// 10. direction awareness (RTL sign + locale content direction);
/// 11. rapid state changes never throw, never fake, never re-fire edges;
/// 12. controller lifecycle: clean unmount, engine abort on page dispose.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/speed_test.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/core/motion_widgets.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/widgets/connect_core.dart';
import 'package:aethone/features/speedtest/speed_test_page.dart';

/// A scripted engine for deterministic UI tests (the home-screen suite's
/// own seam).
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

/// A manual speed engine that RECORDS the abort (axis 12).
class TrackingSpeedEngine extends SpeedTestEngine {
  TrackingSpeedEngine({super.onUpdate});

  int aborts = 0;

  @override
  Future<void> run({int? proxyPort}) async {}

  @override
  void abort() {
    aborts++;
    onUpdate?.call(
      const SpeedTestSnapshot(phase: null, pingMs: 12, jitterMs: 3),
    );
  }
}

Widget _booth(Widget child, {Locale locale = const Locale('fa')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

Future<void> useReferenceSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  // ---------------------------------------------------------------------
  // Axis 1 — the eight states each carry their own words + glyph + one
  // shared halo stage; the three middle states no longer fold into
  // «قــطــع!» (the audit's dead-middle finding).
  // ---------------------------------------------------------------------
  group('axis 1 — all eight states speak', () {
    testWidgets('the walk drives every state with its own pill label',
        (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      Future<void> at(
        VpnState state,
        String label, {
        EngineEvent? emit,
      }) async {
        if (emit != null) engine.emit(emit);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 500));
        expect(store.state, state, reason: label);
        expect(find.text(label), findsOneWidget);
        // ONE shared halo stage mounts in every state — never two.
        expect(find.byType(ConnectHalo), findsOneWidget);
      }

      expect(store.state, VpnState.disconnected);
      // v6 — look 1's disconnected label is the new CSS's «غیرفعال».
      await at(VpnState.disconnected, 'غیرفعال');

      await store.connect();
      await at(VpnState.starting, 'در حال شروع');
      await at(
        VpnState.waitingForPermissions,
        'در انتظار مجوز',
        emit: const EngineStateChanged(VpnState.waitingForPermissions),
      );
      await at(
        VpnState.connecting,
        'در حال اتصال',
        emit: const EngineStateChanged(VpnState.connecting),
      );
      await at(
        VpnState.connected,
        'مــتـصـل',
        emit: const EngineStateChanged(VpnState.connected),
      );
      await at(
        VpnState.reconnecting,
        'اتصال مجدد',
        emit: const EngineStateChanged(VpnState.reconnecting),
      );
      await at(
        VpnState.connecting,
        'در حال اتصال',
        emit: const EngineStateChanged(VpnState.connecting),
      );
      await at(
        VpnState.connected,
        'مــتـصـل',
        emit: const EngineStateChanged(VpnState.connected),
      );
      await store.disconnect();
      await at(VpnState.disconnecting, 'در حال قطع');
      await at(
        VpnState.disconnected,
        'غیرفعال', // v6 — look 1's own disconnected word
        emit: const EngineStateChanged(VpnState.disconnected),
      );

      // any → failed is legal; the caption + its own words appear.
      await store.connect();
      await tester.pump(const Duration(milliseconds: 100));
      await at(
        VpnState.failed,
        'خطا',
        emit: const EngineStateChanged(VpnState.failed),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Axis 2 — both looks mount the SAME halo director and agree on the
  // connect action.
  // ---------------------------------------------------------------------
  group('axis 2 — both looks agree', () {
    for (final look in HomeLook.values) {
      testWidgets('look ${look.name}: one halo, same words, same toggle',
          (tester) async {
        await useReferenceSurface(tester);
        final engine = ScriptedEngine();
        final store = ConnectionStore(engine: engine);
        store.setHomeLook(look);
        await tester.pumpWidget(_booth(HomeScreen(store: store)));
        await tester.pumpAndSettle();

        expect(find.byType(ConnectHalo), findsOneWidget);
        // v6 — look 1's own «غیرفعال» / look 2's «قــطــع!».
        expect(
          find.text(look == HomeLook.one ? 'غیرفعال' : 'قــطــع!'),
          findsOneWidget,
        );

        // The central control of EITHER look routes through the one
        // toggle: tap → starting (tap-to-connect), tap → cancel.
        final center = find.descendant(
          of: find.byType(ConnectShake),
          matching: find.byType(PressSpring),
        );
        expect(center, findsOneWidget);
        await tester.tap(center, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
        expect(store.state, VpnState.starting);

        await tester.tap(center, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
        expect(store.state, VpnState.disconnecting);
      });
    }
  });

  // ---------------------------------------------------------------------
  // Axis 3 — the press: immediate squash, spring return, action fires.
  // ---------------------------------------------------------------------
  group('axis 3 — the press feels alive', () {
    testWidgets('squash lands instantly, springs back, never blocks',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_booth(PressSpring(
        style: MotionStyle.standard,
        onTap: () => taps++,
        child: const SizedBox(width: 100, height: 100),
      )));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(PressSpring)));
      // A fresh ticker's first frame lands at elapsed zero — prime it,
      // then advance the full squash window.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // SILK squashes to its recipe's pressScale.
      final ours = find.descendant(
        of: find.byType(PressSpring),
        matching: find.byType(Transform),
      );
      final transform = tester.widget<Transform>(ours);
      expect(transform.transform.entry(0, 0), closeTo(0.96, 0.001));

      await gesture.up();
      await tester.pump();
      // SILK's spring (350/26) crosses rest at ~174 ms and peaks its hair
      // of overshoot at ~291 ms — read it at the peak.
      await tester.pump(const Duration(milliseconds: 300));
      // The spring return OVERSHOOTS past rest (scale > 1) — the visible
      // life the old linear 120 ms swap could never show.
      final mid =
          tester.widget<Transform>(ours);
      expect(mid.transform.entry(0, 0), greaterThan(1.0));
      await tester.pumpAndSettle();
      final rest =
          tester.widget<Transform>(ours);
      // The spring parks at rest within its own decay tolerance.
      expect(rest.transform.entry(0, 0), closeTo(1.0, 0.001));
      expect(taps, 1);
    });

    testWidgets('OFF never squashes but the tap still fires', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_booth(PressSpring(
        style: MotionStyle.off,
        onTap: () => taps++,
        child: const SizedBox(width: 100, height: 100),
      )));
      await tester.tap(find.byType(PressSpring), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(taps, 1);
      expect(find.byType(Transform), findsNothing);
    });
  });

  // ---------------------------------------------------------------------
  // Axis 4 — state transitions crossfade (both labels mid-flight, one
  // after the settle) — never a raw pop.
  // ---------------------------------------------------------------------
  group('axis 4 — transitions crossfade', () {
    testWidgets('pill swap: both labels mid-flight, one after settle',
        (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      await store.connect();
      await tester.pump(const Duration(milliseconds: 80));
      // Mid-crossfade: the old and the new label co-exist briefly
      // (v6 — look 1's disconnected word is «غیرفعال» now).
      expect(find.text('غیرفعال'), findsOneWidget);
      expect(find.text('در حال شروع'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('در حال شروع'), findsOneWidget);
      expect(find.text('غیرفعال'), findsNothing);
    });

    testWidgets('stat values land softly, exactly one text per value',
        (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // v5.3 — the KB grammar: zero renders the honest '--' on BOTH
      // look-1 cards (the whole-megabyte format and the round-12 widget
      // deck's session-data total are both retired).
      expect(find.text('--'), findsNWidgets(2));

      // The stats tick lands a NEW value: the look-1 DOWN card decodes it
      // character by character ([HyperText], the ping readout's own walk —
      // v5.2), so MID-decode nothing has landed; after the style's own
      // window exactly one '148480KB' reads (145 MB in the KB grammar,
      // «میزان دانلود و آپلود باید از کیلوبایت ثبت بشه نه از مگابایت»).
      engine.emit(const EngineStatsUpdated(downBytes: 145 * 1024 * 1024));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('148480KB'), findsNothing,
          reason: 'mid-decode — the walk has not resolved yet');
      // The decode rides a raw 16 ms Timer.periodic — pumpAndSettle
      // cannot advance it (a timer is not a frame) — so the style's own
      // window is pumped explicitly: 480 ms of decode + a tick for the
      // resolved-target commit.
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('148480KB'), findsOneWidget);
      expect(find.text('--'), findsOneWidget); // the UP card
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------
  // Axis 5 — page routes: the style's own personality, OFF = instant.
  // ---------------------------------------------------------------------
  group('axis 5 — page route personalities', () {
    test('transition durations follow the style multiplier', () {
      final cases = {
        MotionStyle.standard: 380,
        MotionStyle.smooth: 570,
        MotionStyle.dynamic: 304,
        MotionStyle.minimal: 152,
        MotionStyle.off: 0,
      };
      for (final e in cases.entries) {
        final route = aethPageRoute<void>(
          style: e.key,
          builder: (_) => const SizedBox(),
        );
        expect(
          route.transitionDuration.inMilliseconds,
          e.value,
          reason: e.key.name,
        );
      }
      // The exit is faster than the entry (the global spec's rule 1).
      final silk = aethPageRoute<void>(
        style: MotionStyle.standard,
        builder: (_) => const SizedBox(),
      );
      expect(
        silk.reverseTransitionDuration.inMilliseconds,
        lessThan(silk.transitionDuration.inMilliseconds),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Axis 6 — card entrances differ by MEANING (the EntranceFlavor table).
  // ---------------------------------------------------------------------
  group('axis 6 — entrances differ by meaning', () {
    test('the flavor math bends the recipe per card type', () {
      // Action cards reach out (a zoom even on the zoom-less SILK)…
      expect(
        EntranceFlavor.action.scaleFrom(MotionStyle.standard.recipe.blockScaleFrom),
        0.97,
      );
      // …data cards stay calm, status surfaces only fade…
      expect(EntranceFlavor.stat.scaleFrom(0.965), 1.0);
      expect(EntranceFlavor.status.rise(22), 0);
      expect(EntranceFlavor.stat.rise(22), closeTo(13.2, 0.01));
      // …and router rows arrive from the reading direction.
      expect(EntranceFlavor.route.slideDxRef, greaterThan(0));
      expect(EntranceFlavor.standard.slideDxRef, 0);
      // Onboarding tiles rise the most (the wizard's playful step).
      expect(
        EntranceFlavor.onboarding.rise(22),
        greaterThan(EntranceFlavor.action.rise(22)),
      );
    });

    testWidgets('motionCascade without a route renders the child untouched',
        (tester) async {
      const child = SizedBox(width: 10, height: 10);
      await tester.pumpWidget(_booth(Builder(
        builder: (context) =>
            motionCascade(context, MotionStyle.smooth, 3, child),
      )));
      expect(find.byWidget(child), findsOneWidget);
      expect(find.byType(Opacity), findsNothing);
    });
  });

  // ---------------------------------------------------------------------
  // Axis 7 — the five tiers are personalities (the v1.0.2 recipe table).
  // ---------------------------------------------------------------------
  group('axis 7 — tier personalities', () {
    test('the connect choreography differs per tier (not just speed)', () {
      final r = {
        for (final s in MotionStyle.values) s: s.recipe,
      };
      // The march tempo: SPRING is the fastest, TIDE the slowest.
      expect(r[MotionStyle.dynamic]!.connectMarchMs, 800);
      expect(r[MotionStyle.smooth]!.connectMarchMs, 1800);
      expect(r[MotionStyle.standard]!.connectMarchMs, 1200);
      expect(r[MotionStyle.minimal]!.connectMarchMs, 900);
      // The seek rhythm is DISTINCT from the march in every living tier
      // (OFF silences both — that is its own personality).
      for (final s in MotionStyle.values.where((s) => s != MotionStyle.off)) {
        expect(
          r[s]!.connectSeekMs,
          greaterThan(r[s]!.connectMarchMs),
          reason: s.name,
        );
      }
      // The press depth: SPRING squeezes deepest, OFF not at all.
      expect(r[MotionStyle.dynamic]!.pressScale, 0.94);
      expect(r[MotionStyle.off]!.pressScale, 1.0);
      // The celebration + shake + resize + dial — all zero under OFF.
      final off = r[MotionStyle.off]!;
      expect(off.celebrationMs, 0);
      expect(off.shakeAmpRef, 0);
      expect(off.sectionResizeMs, 0);
      expect(off.dialMs, 0);
      // The v4.25 baselines stay VERBATIM (additive-only promise).
      expect(r[MotionStyle.standard]!.blockRise, 22);
      expect(r[MotionStyle.smooth]!.blockScaleFrom, 0.965);
      expect(r[MotionStyle.dynamic]!.staggerStep, 0.05);
      expect(r[MotionStyle.minimal]!.controlMs, 90);
    });
  });

  // ---------------------------------------------------------------------
  // Axis 8 — the master kill-switch: nothing ambient moves, the state
  // feedback stays, operations still work.
  // ---------------------------------------------------------------------
  group('axis 8 — the master kill-switch', () {
    testWidgets('OFF settles even while connected; feedback stays',
        (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // Walk to connected, then kill the animations.
      await store.connect();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump(const Duration(milliseconds: 100));
      engine.emit(const EngineStateChanged(VpnState.connected));
      await tester.pump(const Duration(milliseconds: 100));
      store.setAnimationsEnabled(false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        store.effectiveMotionStyle(
          tester.element(find.byType(Scaffold)),
        ),
        MotionStyle.off,
      );
      // The halo paints NOTHING under OFF — which means the connected
      // home now SETTLES (no forever-tickers anywhere).
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // The state feedback is KEPT (the accessibility requirement).
      expect(find.text('مــتـصـل'), findsOneWidget);

      // Operations still answer: tap → disconnect works instantly.
      await tester.tap(
        find.descendant(
          of: find.byType(ConnectShake),
          matching: find.byType(PressSpring),
        ),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.state, VpnState.disconnecting);
    });
  });

  // ---------------------------------------------------------------------
  // Axis 9 — the OS reduce-motion clamp.
  // ---------------------------------------------------------------------
  group('axis 9 — reduce motion', () {
    // The probe rebuilds on store changes and carries its own MediaQuery
    // BELOW the MaterialApp (the app rebuilds the one above `home` from
    // the window).
    Widget probe(ConnectionStore store) => AnimatedBuilder(
          animation: store,
          builder: (context, _) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) => Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  store.effectiveMotionStyle(context).name,
                  key: const ValueKey('probe'),
                ),
              ),
            ),
          ),
        );

    testWidgets('dynamic/smooth clamp to minimal; standard/off stay',
        (tester) async {
      final store = ConnectionStore(engine: ScriptedEngine());
      await tester.pumpWidget(_booth(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: probe(store),
      )));
      // (inside `home`, so the MaterialApp's own MediaQuery does not
      // shadow the override)

      for (final (style, expected) in const [
        (MotionStyle.dynamic, 'minimal'),
        (MotionStyle.smooth, 'minimal'),
        (MotionStyle.standard, 'standard'),
        (MotionStyle.minimal, 'minimal'),
      ]) {
        store.setMotionStyle(style);
        await tester.pump();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('probe'))).data,
          expected,
          reason: style.name,
        );
      }

      // The master switch outranks the OS setting.
      store.setAnimationsEnabled(false);
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('probe'))).data,
        'off',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Axis 10 — direction awareness.
  // ---------------------------------------------------------------------
  group('axis 10 — RTL/LTR awareness', () {
    testWidgets('the horizontal sign follows the ambient direction',
        (tester) async {
      late int sign;
      await tester.pumpWidget(_booth(Builder(
        builder: (context) {
          sign = horizontalSign(context).round();
          return const SizedBox();
        },
      )));
      expect(sign, -1, reason: 'fa booth is RTL');

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            sign = horizontalSign(context).round();
            return const SizedBox();
          },
        ),
      ));
      expect(sign, 1, reason: 'en booth is LTR');
    });

    testWidgets('the content direction follows the LOCALE, not the frame',
        (tester) async {
      late TextDirection dir;
      Widget read() => Builder(
            builder: (context) {
              dir = appContentDirection(context);
              return const SizedBox();
            },
          );
      // Raw [Localizations] widgets — every locale rides the always-
      // supported DefaultWidgetsLocalizations delegate, tk included.
      Widget raw(Locale l) => Localizations(
            locale: l,
            delegates: const [DefaultWidgetsLocalizations.delegate],
            child: read(),
          );
      await tester.pumpWidget(raw(const Locale('fa')));
      expect(dir, TextDirection.rtl, reason: 'fa');
      for (final code in ['en', 'ru', 'zh', 'tk']) {
        await tester.pumpWidget(raw(Locale(code)));
        expect(dir, TextDirection.ltr, reason: code);
      }
    });
  });

  // ---------------------------------------------------------------------
  // Axis 11 — rapid state changes: never throw, never fake, never
  // re-fire the one-shot edges.
  // ---------------------------------------------------------------------
  group('axis 11 — rapid state changes', () {
    testWidgets('a burst of legal transitions stays honest',
        (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // disconnected → starting → connecting → disconnected → starting →
      // failed → (retry) connecting → connected — one frame each.
      await store.connect();
      await tester.pump();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump();
      await store.disconnect();
      await tester.pump();
      engine.emit(const EngineStateChanged(VpnState.disconnected));
      await tester.pump();
      await store.connect();
      await tester.pump();
      engine.emit(const EngineStateChanged(VpnState.failed));
      await tester.pump();
      expect(store.state, VpnState.failed);
      expect(find.text('خطا'), findsOneWidget);

      // Retry goes straight to connecting (prompt §8).
      await store.connect();
      await tester.pump();
      expect(store.state, VpnState.connecting);
      engine.emit(const EngineStateChanged(VpnState.connected));
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.state, VpnState.connected);

      // A stats re-notify while connected changes only the numbers.
      engine.emit(const EngineStatsUpdated(pingMs: 120));
      await tester.pump();
      expect(store.state, VpnState.connected);
      expect(find.text('مــتـصـل'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // Axis 12 — controller lifecycle: clean unmount, engine abort on
  // dispose (the audit's real leak fix).
  // ---------------------------------------------------------------------
  group('axis 12 — lifecycle', () {
    testWidgets('a connected home unmounts cleanly', (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      await store.connect();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump(const Duration(milliseconds: 100));
      engine.emit(const EngineStateChanged(VpnState.connected));
      await tester.pump(const Duration(milliseconds: 100));

      // Forever-tickers are running (halo loop, breath, hero breath)…
      // …and the tree unmounts without a single disposed-setState.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the speed page detaches + aborts its engine on dispose',
        (tester) async {
      await useReferenceSurface(tester);
      final store = ConnectionStore(engine: ScriptedEngine());
      final engine = TrackingSpeedEngine();
      await tester.pumpWidget(_booth(SpeedTestPage(
        store: store,
        style: MotionStyle.standard,
        engine: engine,
      )));
      await tester.pumpAndSettle();
      expect(engine.aborts, 0);

      // While mounted, the engine's snapshots reach the page live (the
      // page owns the onUpdate seam — a ping phase renders its label).
      engine.onUpdate?.call(
        const SpeedTestSnapshot(phase: SpeedTestPhase.ping),
      );
      await tester.pump();
      expect(find.text('پینگ'), findsOneWidget);

      // Leave the page mid-flow: dispose must detach the callback and
      // stop the measurement (the engine's own documented contract).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.aborts, 1);
      expect(engine.onUpdate, isNull);

      // A late emit is a harmless no-op — the callback is gone.
      engine.onUpdate?.call(const SpeedTestSnapshot(phase: null));
      expect(tester.takeException(), isNull);
    });
  });
}
