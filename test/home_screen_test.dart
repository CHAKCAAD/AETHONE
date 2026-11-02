import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/widgets/bottom_panel.dart';
import 'package:aethone/features/home/widgets/location_header.dart';

/// A scripted engine for deterministic UI tests — the same seam the preview
/// adapter uses, but fully controlled by the test.
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

void main() {
  // Emulate the design reference frame (402x874 logical @ dpr 3) — the
  // default 800x600 test surface is not the layout the design targets.
  Future<void> useReferenceSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
      'disconnected home shows غیرفعال pill, offline in the ping slot, '
      'greyscale locked wheel (NO blur)', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('غیرفعال'), findsOneWidget);
    // v4.11 defect #9: «آفلاین» lives in the SAME slot as the connected
    // ping (exactly one instance) — it no longer overlays the flag wheel.
    expect(find.text('آفلاین'), findsOneWidget);
    expect(find.text('146 ms'), findsNothing); // ping only when connected
    // v4.11 defect #14: the wheel is greyscale-locked for normal protocols
    // while disconnected — a ColorFiltered (saturation-0) layer, no blur.
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets(
      'after engine reports connected: متصل pill, ping, speed button',
      (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // Walk the machine legally, exactly like the real engine would.
    await store.connect(); // store applies `starting`
    engine.emit(const EngineStateChanged(VpnState.connecting));
    // The connecting walk plays the REPEATING scan halo (v4.11 defect #10),
    // so settle with bounded pumps instead of pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connected));
    engine.emit(const EngineStatsUpdated(
      pingMs: 146,
      downBytes: 145 * 1024 * 1024,
      upBytes: 45 * 1024 * 1024,
      exitCountryCode: 'ir',
    ));
    await tester.pumpAndSettle();

    expect(store.state, VpnState.connected);
    expect(find.text('متصل'), findsOneWidget);
    expect(find.text('غیرفعال'), findsNothing);
    expect(find.text('146 ms'), findsOneWidget);
    expect(find.text('145 MB'), findsOneWidget);
    expect(find.text('45 MB'), findsOneWidget);
  });

  testWidgets('unwired engine fails honestly instead of faking connected',
      (tester) async {
    await useReferenceSurface(tester);
    final store = ConnectionStore(engine: EngineNotWiredAdapter());
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    await store.connect();
    await tester.pumpAndSettle();

    expect(store.state, VpnState.failed);
    expect(store.lastErrorCode, 'engineNotWired');
    expect(find.text('خطا'), findsOneWidget);
    expect(find.text('متصل'), findsNothing);
  });

  testWidgets('multi-tap on connect is safe (single-flight)', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // Rapid multi-tap: store-level single-flight means only one walk starts.
    await store.connect();
    await store.connect();
    await store.connect();
    // `starting` plays the repeating scan halo — bounded pumps, not settle.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // Still in a legal, non-corrupted state — no StateError thrown, machine
    // holds `starting` (engine here never reports further).
    expect(store.state, VpnState.starting);
  });

  // v4.11 defect #11: the FAB is SWIPE-ONLY — up connects, down disconnects,
  // a plain tap never toggles.
  testWidgets('FAB ignores taps and connects on swipe UP', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    final fabCenter = tester.getCenter(find.byType(FabColumn));

    // A tap must do NOTHING.
    await tester.tap(find.byType(FabColumn), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.state, VpnState.disconnected);

    // Swipe UP (finger moves from the FAB towards the top) with explicit
    // event timestamps so the velocity tracker sees a real fling.
    var t = 200;
    final gesture = await tester.startGesture(fabCenter);
    for (var i = 0; i < 6; i++) {
      t += 16;
      await gesture.moveBy(const Offset(0, -40), timeStamp: Duration(milliseconds: t));
    }
    t += 16;
    await gesture.up(timeStamp: Duration(milliseconds: t));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.state, VpnState.starting);
  });

  testWidgets('FAB swipe DOWN while connected disconnects', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // Walk to connected legally (disconnected→connected directly is refused
    // by the state machine by design).
    await store.connect();
    engine.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connected));
    await tester.pumpAndSettle();
    expect(store.state, VpnState.connected);

    var t = 200;
    final fabCenter = tester.getCenter(find.byType(FabColumn));
    final gesture = await tester.startGesture(fabCenter);
    for (var i = 0; i < 6; i++) {
      t += 16;
      await gesture.moveBy(const Offset(0, 40), timeStamp: Duration(milliseconds: t));
    }
    t += 16;
    await gesture.up(timeStamp: Duration(milliseconds: t));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.state, VpnState.disconnecting);
  });

  // v4.10 pixel-fidelity locks: the first device build mirrored the panel
  // under the Persian RTL locale and bidi-flipped the Latin fragments.
  testWidgets(
      'bottom panel geometry: DOWN left of UP, FAB column on the right, '
      'LTR-locked labels never bidi-flip', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    final down = tester.getTopLeft(find.text('DOWN:'));
    final up = tester.getTopLeft(find.text('UP:'));
    // DOWN card is the visual LEFT card, UP the visual RIGHT one — the
    // reference arrangement, directionality-locked against RTL mirroring.
    expect(down.dx, lessThan(up.dx));
    expect(down.dy, greaterThan(0));

    // The Latin value renders digits-first ("0 MB"), never "MB 0".
    expect(find.text('0 MB'), findsNWidgets(2));

    // The protocol card shows the SELECTED protocol's name, not the generic
    // word (owner prompt: the chosen protocol's logo/name shows on the card).
    expect(find.text('ماسک'), findsOneWidget);
    expect(find.text('پروتکل'), findsNothing);
  });

  testWidgets('connected ping renders digits-first ("146 ms") in the '
      'compact location row', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    await store.connect();
    engine.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connected));
    engine.emit(const EngineStatsUpdated(
      pingMs: 146,
      downBytes: 0,
      upBytes: 0,
      exitCountryCode: 'ir',
    ));
    await tester.pumpAndSettle();

    final ping = tester.getTopLeft(find.text('146 ms'));
    final mapIcon = tester.getCenter(find.byType(LocationHeader));
    // Ping sits RIGHT of the map icon column (visual layout, LTR-locked).
    expect(ping.dx, greaterThan(mapIcon.dx));
  });
}
