import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/features/home/home_screen.dart';
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
      'disconnected home shows غیرفعال pill, offline blur, no ping',
      (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('غیرفعال'), findsOneWidget);
    expect(find.text('آفلاین'), findsWidgets); // header + blur overlay
    expect(find.text('146 ms'), findsNothing); // ping only when connected
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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    // Still in a legal, non-corrupted state — no StateError thrown, machine
    // holds `starting` (engine here never reports further).
    expect(store.state, VpnState.starting);
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
    await tester.pumpAndSettle();
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
