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
import 'package:aethone/features/home/widgets/glow_pill.dart';
import 'package:aethone/core/app_assets.dart' show ProtocolId;

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

  testWidgets('disconnected home shows غیرفعال pill, offline in the ping slot, '
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

  testWidgets('after engine reports connected: متصل pill, ping, speed button', (
    tester,
  ) async {
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
    engine.emit(
      const EngineStatsUpdated(
        pingMs: 146,
        downBytes: 145 * 1024 * 1024,
        upBytes: 45 * 1024 * 1024,
        exitCountryCode: 'ir',
      ),
    );
    // v4.12: the connected idle aura repeats forever — bounded pumps.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));

    expect(store.state, VpnState.connected);
    expect(find.text('متصل'), findsOneWidget);
    expect(find.text('غیرفعال'), findsNothing);
    expect(find.text('146 ms'), findsOneWidget);
    expect(find.text('145 MB'), findsOneWidget);
    expect(find.text('45 MB'), findsOneWidget);
  });

  testWidgets('unwired engine fails honestly instead of faking connected', (
    tester,
  ) async {
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

  // v4.12 (owner: «دکمه اتصال رو به حالت کلیک قبلش برگردون، نمیخوام حالت
  // سوییپ داشته باشه»): the FAB answers a plain tap again — tap connects.
  testWidgets('FAB tap connects (back to click, no swipe)', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FabColumn), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.state, VpnState.starting);
  });

  testWidgets('FAB tap while connected disconnects', (tester) async {
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
    // v4.12: bounded pumps (the connected idle aura never settles).
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.state, VpnState.connected);

    await tester.tap(find.byType(FabColumn), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.state, VpnState.disconnecting);
  });

  // v4.12: the look-2 CENTER button also answers a tap (tap = toggle).
  testWidgets('look-2 center button tap connects', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    store.setHomeLook(HomeLook.two);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.byType(GlowCircle), findsOneWidget);
    await tester.tap(find.byType(GlowCircle), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.state, VpnState.starting);
  });

  // v4.10 pixel-fidelity locks: the first device build mirrored the panel
  // under the Persian RTL locale and bidi-flipped the Latin fragments.
  testWidgets(
    'bottom panel geometry: DOWN left of UP, FAB column on the right, '
    'LTR-locked labels never bidi-flip',
    (tester) async {
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
    },
  );

  testWidgets('connected ping renders around the CENTRED map icon '
      '(name left · icon at exact centre · ping right, v4.13)', (tester) async {
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
    engine.emit(
      const EngineStatsUpdated(
        pingMs: 146,
        downBytes: 0,
        upBytes: 0,
        exitCountryCode: 'ir',
      ),
    );
    // v4.13: the connect ROULETTE spins the wheel for ~2.6 s before it lands
    // on the exit country; the aura keeps repeating forever — bounded pumps
    // past BOTH.
    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pump(const Duration(milliseconds: 100));

    final name = tester.getTopLeft(find.text('ایران'));
    final ping = tester.getTopLeft(find.text('146 ms'));
    // Cluster order: country name · map icon · ping (ping right of name).
    expect(ping.dx, greaterThan(name.dx));
    // v4.13 (owner round-4 #1): the map icon sits at the EXACT screen centre
    // and the ping starts to its RIGHT — never left of the centre line.
    final mapIcon = tester.getCenter(
      find.byKey(const ValueKey('location-map-icon')),
    );
    expect((mapIcon.dx - 201).abs(), lessThan(2.0),
        reason: 'the map icon must be at the exact screen centre');
    expect(ping.dx, greaterThan(mapIcon.dx));
    expect(name.dx, lessThan(mapIcon.dx));
  });

  // v4.13.1 regression (owner round-4 #6, real-core demand: «بعد از اتصال
  // هسته ها این مورد باید به درستی کار کند»): a late exit-country report
  // DURING the connect roulette must RE-SPIN it to the REAL location — it
  // never lands on the stale target and never writes mid-spin countries
  // into the store selector (the engine owns the connected location).
  testWidgets('late exit-country report mid-roulette re-spins to the real '
      'location; store selector untouched', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    store.selectCountry('ir');
    store.selectedProtocol = ProtocolId.psiphonChain;
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    await store.connect();
    engine.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connected));
    // The roulette is queued (stale target 'ir'). MID-SPIN the real core
    // reports its exit country — a DIFFERENT one.
    await tester.pump(const Duration(milliseconds: 800));
    engine.emit(
      const EngineStatsUpdated(
        pingMs: 90,
        downBytes: 0,
        upBytes: 0,
        exitCountryCode: 'nl',
      ),
    );
    // Ride out the re-spun roulette (2.6 s from the retarget) + the aura
    // (repeats forever) — bounded pumps.
    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pump(const Duration(milliseconds: 100));

    // Landed on the REAL exit country, not the stale target.
    expect(find.text('هلند'), findsOneWidget);
    // The user's selector was NEVER overwritten by mid-spin countries —
    // the epoch protocol's no-op guarantee on superseded spins.
    expect(store.selectedCountryCode, 'ir');
  });

  // v4.12: the flag wheel is INFINITE — at any resting position flags exist
  // on BOTH the left and the right edge (owner: «همیشه پرچم هم سمت راست
  // وجود داشته باشه هم سمت چپ»), and it still selects for Tor/Psiphon.
  testWidgets('infinite wheel: flags on both edges; Psiphon can select '
      'by drag; MASQUE wheel is display-only', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    store.selectCountry('ir');
    store.selectedProtocol = ProtocolId.psiphonChain;
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // Flags on BOTH edges of the viewport.
    final xs = <double>[];
    for (final candidate in find.byType(Image).evaluate()) {
      final box = candidate.renderObject as RenderBox;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      if (center.dy < 260) xs.add(center.dx); // the flags band only
    }
    expect(
      xs,
      hasLength(greaterThanOrEqualTo(5)),
      reason: 'the flags band renders ~6 visible flags',
    );
    expect(
      xs.where((x) => x < 60),
      isNotEmpty,
      reason: 'a flag must exist at the LEFT edge',
    );
    expect(
      xs.where((x) => x > 342),
      isNotEmpty,
      reason: 'a flag must exist at the RIGHT edge',
    );

    // Psiphon = selectable: drag one pitch left → the next country centers
    // and its NAME (not the code) shows in the header. Small stepped moves
    // with pumps keep the release velocity ≈ 0 (no fling past the neighbor).
    final wheelCenter = tester.getCenter(find.byType(PageView).first);
    final drag = await tester.startGesture(wheelCenter);
    for (var i = 0; i < 3; i++) {
      await drag.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await drag.moveBy(const Offset(-6, 0));
    // v4.13: let the pointer velocity decay so the release does not fling —
    // PageView snaps to the NEAREST page (one pitch), exactly like a slow
    // human drag.
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text('ایسلند'), findsOneWidget); // 'ir' + 1 = 'is'

    // Display-only protocol: MASQUE — the wheel is locked (greyscale,
    // NeverScrollable) and a drag NEVER changes the selection. (A UniqueKey
    // forces a fresh LocationHeader state — pumpWidget alone would reuse the
    // previous screen's header state.)
    final masqueStore = ConnectionStore(engine: engine);
    masqueStore.selectedProtocol = ProtocolId.masque;
    await tester.pumpWidget(_booth(HomeScreen(
      key: UniqueKey(),
      store: masqueStore,
    )));
    await tester.pumpAndSettle();
    final lockedWheelCenter = tester.getCenter(find.byType(PageView).first);
    final drag2 = await tester.startGesture(lockedWheelCenter);
    for (var i = 0; i < 5; i++) {
      await drag2.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await drag2.up();
    await tester.pumpAndSettle();
    expect(find.text('ایران'), findsOneWidget); // selection unchanged
  });
}
