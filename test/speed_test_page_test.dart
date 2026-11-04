/// v4.24 — the speed test page test: the page renders the three committed
/// frames' structure, a scripted engine drives the full phase sequence
/// (the honest values land in their slots), the tap-to-start/tap-to-stop
/// contract holds, and the home entry opens the REAL page while connected.
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
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/widgets/glow_pill.dart';
import 'package:aethone/features/speedtest/speed_test_page.dart';

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

/// The scripted transport engine (the home test's own seam) — walks the
/// store's machine legally into the connected pose.
class _ScriptedEngine implements EngineAdapter {
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

/// A MANUAL speed engine: run() is a no-op — the TEST drives every
/// snapshot through the page's real _onSnapshot path with emit().
class _ManualSpeedEngine extends SpeedTestEngine {
  @override
  Future<void> run({int? proxyPort}) async {}

  void emit(SpeedTestSnapshot snap) => onUpdate?.call(snap);

  @override
  void abort() {
    onUpdate?.call(
      const SpeedTestSnapshot(
        phase: null,
        pingMs: 345,
        jitterMs: 24,
        downBytes: 145 * 1024 * 1024,
        upBytes: 45 * 1024 * 1024,
      ),
    );
  }
}

void main() {
  group('idle frame', () {
    testWidgets('renders the chrome, title, dial and the empty slots',
        (tester) async {
      await _useReferenceSurface(tester);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      await tester.pumpWidget(
        _booth(SpeedTestPage(store: store, style: MotionStyle.standard)),
      );
      await tester.pumpAndSettle();

      // The title row + the fixed chrome tiles + the wordmark.
      expect(find.text('تست سرعت'), findsOneWidget);
      expect(find.byKey(const ValueKey('speed-info')), findsOneWidget);
      expect(find.byKey(const ValueKey('speed-back')), findsOneWidget);
      expect(find.text('AETHONE'), findsOneWidget);

      // The dial value + unit (the frame's own spellings).
      expect(find.text('0.0'), findsOneWidget);
      expect(find.text('Mbs'), findsOneWidget);

      // The four stat cards — labels verbatim from the frame; the slots
      // stay EMPTY before any run (never fabricated).
      expect(find.text('Jiter:'), findsOneWidget);
      expect(find.text('Ping:'), findsOneWidget);
      expect(find.text('DOWN:'), findsOneWidget);
      expect(find.text('UP:'), findsOneWidget);
      expect(find.byKey(const ValueKey('speed-card-jitter')), findsOneWidget);
      expect(find.byKey(const ValueKey('speed-card-ping')), findsOneWidget);
      expect(find.byKey(const ValueKey('speed-card-down')), findsOneWidget);
      expect(find.byKey(const ValueKey('speed-card-up')), findsOneWidget);

      // The button label in the idle state.
      expect(find.text('شروع'), findsOneWidget);
    });
  });

  group('a scripted full run', () {
    testWidgets('drives ping → download → upload → done with honest slots',
        (tester) async {
      await _useReferenceSurface(tester);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      final engine = _ManualSpeedEngine();
      await tester.pumpWidget(
        _booth(SpeedTestPage(
          store: store,
          style: MotionStyle.standard,
          engine: engine,
        )),
      );
      await tester.pumpAndSettle();

      // Idle → tap start (the button circle itself, not the caption).
      await tester.tap(find.byKey(const ValueKey('speed-start')));
      await tester.pump();
      expect(find.text('شروع شده...'), findsOneWidget);

      // The ping phase — every slot still pending.
      engine.emit(
        const SpeedTestSnapshot(phase: SpeedTestPhase.ping),
      );
      await tester.pump();
      expect(find.text('پینگ'), findsOneWidget); // the phase label
      expect(find.text('0.0'), findsOneWidget); // nothing measured yet

      // Ping lands; download streams live.
      engine.emit(
        const SpeedTestSnapshot(
          phase: SpeedTestPhase.download,
          pingMs: 345,
          jitterMs: 24,
          liveMbps: 50.4,
          downBytes: 145 * 1024 * 1024,
        ),
      );
      await tester.pump();
      expect(find.text('دانلود'), findsOneWidget);
      expect(find.text('50.4'), findsOneWidget); // the live gauge value
      expect(find.text('345'), findsOneWidget); // Ping slot
      expect(find.text('24'), findsOneWidget); // Jiter slot
      expect(find.text('145 MB'), findsOneWidget); // DOWN ticks live

      // Upload phase — the UP slot still pending.
      engine.emit(
        const SpeedTestSnapshot(
          phase: SpeedTestPhase.upload,
          pingMs: 345,
          jitterMs: 24,
          downBytes: 145 * 1024 * 1024,
          liveMbps: 12.5,
        ),
      );
      await tester.pump();
      expect(find.text('آپلود'), findsOneWidget);
      expect(find.text('45 MB'), findsNothing); // UP not measured yet

      // Finish — phase null, the done label; the gauge resets (frame).
      engine.emit(
        const SpeedTestSnapshot(
          phase: null,
          pingMs: 345,
          jitterMs: 24,
          downBytes: 145 * 1024 * 1024,
          upBytes: 45 * 1024 * 1024,
        ),
      );
      await tester.pump();
      expect(find.text('شروع دوباره'), findsOneWidget);
      expect(find.text('45 MB'), findsOneWidget);
      expect(find.text('0.0'), findsOneWidget); // the gauge resets (frame)
      expect(find.text('دانلود'), findsNothing); // no label at rest
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('tap while running aborts into the done state', (tester) async {
      await _useReferenceSurface(tester);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      final engine = _ManualSpeedEngine();
      await tester.pumpWidget(
        _booth(SpeedTestPage(
          store: store,
          style: MotionStyle.standard,
          engine: engine,
        )),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('speed-start')));
      await tester.pump();
      engine.emit(
        const SpeedTestSnapshot(
          phase: SpeedTestPhase.download,
          liveMbps: 8.1,
          downBytes: 40 * 1024 * 1024,
        ),
      );
      await tester.pump();
      expect(find.text('شروع شده...'), findsOneWidget);
      expect(find.text('8.1'), findsOneWidget);

      // Tap-to-stop: the abort snapshot lands, the page goes done with
      // whatever was measured (nothing fabricated).
      await tester.tap(find.byKey(const ValueKey('speed-start')));
      await tester.pump();
      expect(find.text('شروع دوباره'), findsOneWidget);
      expect(find.text('345'), findsOneWidget); // from the abort snapshot
      expect(find.text('145 MB'), findsOneWidget);
      expect(find.text('45 MB'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('home wiring', () {
    testWidgets('the connected home entry opens the REAL page', (tester) async {
      await _useReferenceSurface(tester);
      final engine = _ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // Walk the machine legally, exactly like the real engine would.
      await store.connect(); // store applies `starting`
      engine.emit(const EngineStateChanged(VpnState.connecting));
      // The connecting walk plays the REPEATING scan halo — bounded pumps.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      engine.emit(const EngineStateChanged(VpnState.connected));
      // Bounded pumps: the connected aura repeats forever; the entry's
      // scale-in finishes inside this window (state=400ms).
      await tester.pump(const Duration(seconds: 1));

      expect(store.state, VpnState.connected);
      expect(find.byType(SpeedTestButton), findsOneWidget);

      // v4.24 — the entry opens the REAL page (was: the placeholder sheet).
      // The layered glow group's live hit box is flaky under the harness
      // (the home tests' own warnIfMissed convention), so the WIRING is
      // pinned by invoking the entry's real onTap directly.
      tester.widget<SpeedTestButton>(find.byType(SpeedTestButton)).onTap();
      // Two pumps: the first frame starts the route's transition ticker,
      // the second carries it through (a single big pump skips it).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SpeedTestPage), findsOneWidget);
      expect(find.text('تست سرعت'), findsOneWidget);
      expect(find.text('شروع'), findsOneWidget);
      expect(find.text('تست سرعت — در گام بعدی پیاده‌سازی می‌شود'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
