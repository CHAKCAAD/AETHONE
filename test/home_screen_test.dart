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
import 'package:aethone/features/home/widgets/location_header.dart'
    show FlagSaturation;
import 'package:aethone/core/app_assets.dart' show ProtocolId;
import 'package:aethone/connection/transport_modes.dart' show LocationWheelPolicy;

/// A scripted engine for deterministic UI tests — the same seam the preview
/// adapter uses, but fully controlled by the test.
class ScriptedEngine extends EngineAdapter {
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
  @override
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

void main() {
  // Emulate the design reference frame (402x874 logical @ dpr 3) — the
  // default 800x600 test surface is not the layout the design targets.
  Future<void> useReferenceSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  // v5 (owner round 19): «قسمت نمایش پروتکل باید در زمانی که پروتکل های
  // غیر از سایفون و تور انتخاب میشود در حالت قطع سیاه و سفید باشند و
  // نباید قابلیت انتخاب پروتکل یا همون جابه جایی بین نقشه کشور هارو
  // داشته باشه و باید قفل باشه» — the v4.15 HIDE rule is RETIRED: for
  // non-Tor/Psiphon protocols the location band stays ON SCREEN while
  // disconnected, GREYSCALE + locked (the CSS «قطع» frame).
  testWidgets('disconnected home shows غیرفعال pill (the v6 look-1 CSS); '
      'MASQUE keeps the location band GREYSCALE + locked (v5 round 19)', (
    tester,
  ) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // v6 (owner round 23) — LOOK 1's disconnected label is the new CSS's
    // own «غیرفعال» (look 2 keeps «قــطــع!»).
    expect(find.text('غیرفعال'), findsOneWidget);
    // The band is FULLY laid out (never zero-height anymore)…
    expect(tester.getSize(find.byKey(const ValueKey('location-band'))).height,
        greaterThan(100.0));
    // …and its wheel rides the constant ColorFiltered saturation seam in
    // the GREYSCALE pose (locked + disconnected).
    final saturation = tester.widget<FlagSaturation>(
      find.byKey(const ValueKey('flag-saturation')),
    );
    expect(saturation.grayscale, isTrue);
    expect(find.byType(BackdropFilter), findsNothing);
    // The disconnected ping slot reads «آفلاین» — ping only when connected.
    expect(find.text('146 ms'), findsNothing);
    expect(find.text('آفلاین'), findsOneWidget);
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
    // v8a: the Hyper-Text decode rides a 16 ms periodic timer — a bare
    // pump() first LANDS the stats rebuild (a big timed pump consumes its
    // whole window BEFORE that frame), then the timed pumps carry the
    // decode out (SILK 480 ms).
    await tester.pump();
    // v4.12: the connected idle motion repeats forever — bounded pumps.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));

    expect(store.state, VpnState.connected);
    expect(find.text('مــتـصـل'), findsOneWidget);
    expect(find.text('غیرفعال'), findsNothing);
    expect(find.text('146 ms'), findsOneWidget);
    // Round 24 — the unit ladder: 145 MB reads as «145.0MB» on the DOWN
    // card (past 1000 KB the counter rolls into MB — one decimal).
    expect(find.text('145.0MB'), findsOneWidget);
    expect(find.text('45.0MB'), findsOneWidget);
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
    expect(find.text('مــتـصـل'), findsNothing);
  });

  testWidgets(
      'v4.20 — the FAILED state names its stage: the error code rides under '
      'the pill and the details sheet (tap) shows code + message', (
    tester,
  ) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // Drive the walk to failed with a REAL device-style failure.
    await store.connect();
    engine.emit(
      const EngineStateChanged(
        VpnState.failed,
        errorCode: 'tunnelStartFailed',
        message: 'start-threw:UnsatisfiedLinkError',
      ),
    );
    await tester.pumpAndSettle();

    expect(store.state, VpnState.failed);
    // The caption under the pill names the engine's own error code.
    expect(find.text('کد خطا: tunnelStartFailed'), findsOneWidget);

    // Tapping it opens the details sheet with the code + full message.
    await tester.tap(find.text('کد خطا: tunnelStartFailed'));
    await tester.pumpAndSettle();
    expect(find.text('جزئیات خطا'), findsOneWidget);
    expect(find.text('tunnelStartFailed'), findsOneWidget);
    expect(find.text('start-threw:UnsatisfiedLinkError'), findsOneWidget);
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

    expect(find.byType(ConnectButtonGlow), findsOneWidget);
    await tester.tap(find.byType(ConnectButtonGlow), warnIfMissed: false);
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

      // The Latin value renders digits-first ("0KB"→"--" idle, digits
      // first once live), never bidi-flipped. v5.3 — the idle pose is the
      // honest dash exactly like «نمای 2»'s readouts (the MB format is
      // retired).
      expect(find.text('--'), findsNWidgets(2));

      // The protocol card shows the SELECTED protocol's name, not the generic
      // word (owner prompt: the chosen protocol's logo/name shows on the card).
      // v1.0.1: the cold default is MASQUE, so the card renders ماسک.
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
    // v4.21 — frame-stepped pumps: the connected frame renders first (the
    // roulette is scheduled at ITS post-frame), then the 2.6 s spin runs
    // out in ~frame-sized steps (a single huge pump lands the whole
    // DrivenScrollActivity on one ticker tick — v4.15.1 lesson).
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // v8a — the LAST name change (the roulette's landing sync) starts a
    // fresh Hyper-Text decode; give it its SILK window before reading the
    // header geometry.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

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
    store.selectedProtocol = ProtocolId.psiphonChain;
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    await store.connect();
    engine.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connected));
    // The roulette is queued (stale target = the AUTO anchor). MID-SPIN the
    // real core reports its exit country — a DIFFERENT one.
    await tester.pump(const Duration(milliseconds: 200));
    engine.emit(
      const EngineStatsUpdated(
        pingMs: 90,
        downBytes: 0,
        upBytes: 0,
        exitCountryCode: 'nl',
      ),
    );
    // Ride out the re-spun roulette (2.6 s from the retarget) + the
    // connected idle motion (repeats forever) — ~frame-sized steps
    // (v4.15.1 lesson). v8a: the +4 steps carry the landing's fresh
    // Hyper-Text decode out (SILK 480 ms after the LAST name change).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Landed on the REAL exit country, not the stale target (nl is a
    // psiphon egress region, so it exists in the filtered wheel).
    expect(find.text('هلند'), findsOneWidget);
    // The user's selector was NEVER overwritten by mid-spin countries —
    // the epoch protocol's no-op guarantee on superseded spins. v4.21:
    // the family pick stays the remembered AUTO (owner: «اپ باید انتخاب
    // لوکیشن سایفون و تور رو یادش بمونه»).
    expect(store.psiphonLocation, LocationWheelPolicy.autoCode);
    expect(store.selectedCountryCode, isNull);
  });

  // v4.12: the flag wheel is INFINITE — at any resting position flags exist
  // on BOTH the left and the right edge (owner: «همیشه پرچم هم سمت راست
  // وجود داشته باشه هم سمت چپ»), and it still selects for Tor/Psiphon.
  testWidgets('infinite wheel: flags on both edges; Psiphon can select '
      'by drag; MASQUE wheel is display-only', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    store.selectedProtocol = ProtocolId.psiphonChain;
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // v4.21: the psiphon wheel is the AUTO-anchored family selector
    // (auto first, then the egress regions).
    expect(find.text('خودکار'), findsOneWidget);
    expect(store.psiphonLocation, LocationWheelPolicy.autoCode);

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

    // Psiphon = selectable: drag one pitch left → the next entry centers
    // and its NAME (not the code) shows in the header. Small stepped moves
    // with pumps keep the release velocity ≈ 0 (no fling past the neighbor).
    // v4.21: from AUTO the next entry is 'at' (اتریش).
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
    expect(find.text('اتریش'), findsOneWidget); // auto + 1 = 'at'
    expect(store.psiphonLocation, 'at');

    // Display-only protocol: MASQUE — v4.15: the band is HIDDEN while
    // disconnected (zero height behind a clip; NeverScrollable), so a drag
    // can NEVER change the selection. (A UniqueKey forces a fresh
    // LocationHeader state — pumpWidget alone would reuse the previous
    // screen's header state.)
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

  // v5 regression (owner round 19): for a non-Tor/Psiphon protocol
  // (MASQUE = the default) the location band stays GREYSCALE + locked
  // while disconnected and returns to FULL COLOUR on connect, acting as
  // the location display — with the exit country centred at FULL opacity
  // and the side falloff per the owner CSS Group 9 (52@1.0 / 42@0.5 /
  // 35@0.2).
  testWidgets('MASQUE: band greyscale while disconnected, colours on '
      'connect with the exit location (v5 greyscale lock)', (tester) async {
    await useReferenceSurface(tester);
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    // MASQUE is the store default — no protocol change needed.
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // Greyscale + locked while disconnected.
    expect(
      tester.getSize(find.byKey(const ValueKey('location-band'))).height,
      greaterThan(100.0),
    );
    expect(
      tester
          .widget<FlagSaturation>(
            find.byKey(const ValueKey('flag-saturation')),
          )
          .grayscale,
      isTrue,
    );

    await store.connect();
    engine.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connected));
    engine.emit(
      const EngineStatsUpdated(
        pingMs: 90,
        downBytes: 0,
        upBytes: 0,
        exitCountryCode: 'de',
      ),
    );
    // Ride out the 420 ms greyscale release + the 2.6 s connect roulette
    // in ~frame-sized steps (the v4.15.1 fake-clock lesson).
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('location-band'))).height,
      greaterThan(100.0),
      reason: 'the band stays laid out through the release',
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // v8a — the landing's fresh Hyper-Text decode (name + ping) gets
    // its SILK window before the assertions read the resolved texts.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The band now displays the engine-reported exit location.
    expect(find.text('آلمان'), findsOneWidget);
    expect(find.text('90 ms'), findsOneWidget);
    // v5: the seam is a CONSTANT tree — the wrapper stays mounted but its
    // target flips to full colour on the connect edge.
    expect(
      tester
          .widget<FlagSaturation>(
            find.byKey(const ValueKey('flag-saturation')),
          )
          .grayscale,
      isFalse,
    );
  });

  // -------------------------------------------------------------------
  // v5 (owner round 19, the «نمای 2» redesign) — the look-2 home layout.
  // -------------------------------------------------------------------
  group('v5 — the look-2 «نمای 2» redesign', () {
    testWidgets(
        'the pill rides ABOVE the connect button; the stats row and the '
        'protocol card ride the curved sheet; no FAB column', (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.setHomeLook(HomeLook.two);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // The pill sits ABOVE the connect button (the v4.x order reversed).
      final pill = tester.getCenter(find.byType(StatusPill));
      final button = tester.getCenter(find.byType(ConnectButtonGlow));
      expect(pill.dy, lessThan(button.dy));

      // The stats row flanks the Speed Test entry: DOWN left, UP right,
      // the speed group dead-centre (LTR-locked, never mirrored).
      final down = tester.getTopLeft(find.text('DOWN:'));
      final up = tester.getTopLeft(find.text('UP:'));
      expect(down.dy, greaterThan(button.dy),
          reason: 'stats sit below the hero');
      expect(down.dx, lessThan(up.dx));
      final speed = tester.getCenter(find.byType(SpeedTestButton));
      expect((speed.dx - 201).abs(), lessThan(2.0),
          reason: 'the speed group is screen-centred');
      expect(find.byType(HomeStatsRow), findsOneWidget);

      // The flag wheel + country row ride BELOW the stats row, the
      // protocol card last; the look-1 FAB column is absent.
      final band =
          tester.getTopLeft(find.byKey(const ValueKey('location-band')));
      expect(band.dy, greaterThan(down.dy));
      // v1.0.1 (carried by the motion-line merge): the cold default is
      // MASQUE, so the look-2 card renders ماسک — same as look 1.
      expect(find.text('ماسک'), findsOneWidget);
      expect(find.byType(FabColumn), findsNothing);

      // The connect button keeps the reference width (160 design px).
      expect(tester.getSize(find.byType(ConnectButtonGlow)).width,
          closeTo(160, 1.0));
    });

    testWidgets(
        'disconnected: the speed entry stays on screen in its dark pose '
        '(v5 — it no longer vanishes), the pill reads قــطــع!', (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.setHomeLook(HomeLook.two);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // Look 2 keeps the entry mounted while disconnected (the CSS
      // «حالت قطع» dark family) — look 1 keeps its hide rule.
      expect(find.byType(SpeedTestButton), findsOneWidget);
      expect(
          tester
              .widget<SpeedTestButton>(find.byType(SpeedTestButton))
              .connected,
          isFalse);
      expect(find.text('قــطــع!'), findsOneWidget);

      // The MASQUE band is greyscale + locked (round 19).
      expect(
        tester
            .widget<FlagSaturation>(
              find.byKey(const ValueKey('flag-saturation')),
            )
            .grayscale,
        isTrue,
      );
      // A drag on the locked wheel never changes the selection.
      final masqueCenter = tester.getCenter(find.byType(PageView).first);
      final drag = await tester.startGesture(masqueCenter);
      for (var i = 0; i < 5; i++) {
        await drag.moveBy(const Offset(-24, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('ایران'), findsOneWidget); // selection unchanged
    });

    testWidgets('connected look-2: the pill reads مــتـصـل and the band colours',
        (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.setHomeLook(HomeLook.two);
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
          downBytes: 145 * 1024 * 1024,
          upBytes: 45 * 1024 * 1024,
          exitCountryCode: 'ir',
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('مــتـصـل'), findsOneWidget);
      expect(find.text('146 ms'), findsOneWidget);
      // The stats row renders the live counters on the sheet (the round-24
      // unit ladder: «145.0MB» / «45.0MB» — past 1000 KB it rolls into MB).
      expect(find.text('145.0MB'), findsOneWidget);
      expect(find.text('45.0MB'), findsOneWidget);
      expect(
        tester
            .widget<FlagSaturation>(
              find.byKey(const ValueKey('flag-saturation')),
            )
            .grayscale,
        isFalse,
      );
      // The speed entry is live again.
      expect(
          tester
              .widget<SpeedTestButton>(find.byType(SpeedTestButton))
              .connected,
          isTrue);
    });
  });

  // -------------------------------------------------------------------
  // v4.30 — owner device-test round 6, the SYNC round:
  // «قسمت انتخاب لوکیشن در صفحه اصلی و قسمت انتخاب لوکیشن در تنظیمات تور
  // و سایفون باهم همگام نیستن … هرچقدر تغیر بدی لوکیشن رو تغیر نمیده».
  // -------------------------------------------------------------------
  group('v4.30 round 6 — the location sync regressions', () {
    testWidgets('a TAP on a side flag COMMITS the pick (was: display-only '
        '— آمریکا tap connected صربستان)', (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.selectedProtocol = ProtocolId.psiphonChain;
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // The wheel anchors on AUTO; 'at' (اتریش) sits one pitch away —
      // visible and tappable.
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              (w.image as AssetImage).assetName ==
                  'design/flags_png/at.png',
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // THE regression: the tap's settle-commit was dead code (the
      // ScrollEndNotification fires while the tap's own spin still holds
      // `_programmatic`), so the store kept the previous pick — the
      // connect pinned the OLD region and the wheel followed the ENGINE's
      // exit instead (owner: picked آمریکا, got صربستان).
      expect(store.psiphonLocation, 'at');
      expect(find.text('اتریش'), findsOneWidget);
    });

    testWidgets('a tor exit OUTSIDE the offered set shows its real flag '
        '(was: the AUTO globe)', (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.selectedProtocol = ProtocolId.torOnly;
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      await store.connect();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump(const Duration(milliseconds: 300));
      engine.emit(const EngineStateChanged(VpnState.connected));
      await tester.pump(const Duration(milliseconds: 200));
      // A running exit relay in a country the offered set does NOT
      // contain ('ru' is not in torExitCountrySnapshot) — the engine
      // truth is never fake, the display must follow it.
      engine.emit(
        const EngineStatsUpdated(
          pingMs: 120,
          downBytes: 0,
          upBytes: 0,
          exitCountryCode: 'ru',
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // v8a — +4 steps: the follow-spin's landing decode (روسیه).
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // The header shows the REAL exit — NOT the AUTO globe (the old
      // _indexOf fallback parked the wheel on index 0).
      expect(find.text('روسیه'), findsOneWidget);
      expect(find.text('خودکار'), findsNothing);
      // The remembered pick is never touched by the display follow.
      expect(store.torLocation, LocationWheelPolicy.autoCode);
    });

    testWidgets('after a session the wheel re-anchors on the remembered '
        'pick (the disconnect edge)', (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.selectedProtocol = ProtocolId.psiphonChain;
      store.setPsiphonLocation('de'); // the settings-path pick (آلمان)
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.text('آلمان'), findsOneWidget);

      // A session whose REAL exit was somewhere else entirely.
      await store.connect();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump(const Duration(milliseconds: 300));
      engine.emit(const EngineStateChanged(VpnState.connected));
      engine.emit(
        const EngineStatsUpdated(
          pingMs: 90,
          downBytes: 0,
          upBytes: 0,
          exitCountryCode: 'nl',
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('هلند'), findsOneWidget); // followed the exit

      // Disconnect: the walk goes disconnecting → disconnected (the real
      // adapter order — connected → disconnected is an illegal jump in the
      // state machine). The wheel returns to the PICK, so what it shows
      // while disconnected is what the next connect will pin.
      await store.disconnect();
      engine.emit(const EngineStateChanged(VpnState.disconnected));
      await tester.pumpAndSettle();
      expect(find.text('آلمان'), findsOneWidget);
      expect(store.psiphonLocation, 'de');
    });

    // v4.31 — the Tor pseudo-country round (owner: «قسمت نمایش پروتکل برای
    // پرچمی نشون نداد و اسمش رو هم T1 نوشته بود»): the trace answers
    // loc=T1 for EVERY Tor exit, so the adapter strips the exit to null
    // (no flag, no «T1» name) and the wheel keeps the honest anchor until
    // the post-connect Onionoo resolution lands with the REAL country.
    testWidgets('a Tor pseudo exit (T1) shows the anchor until the '
        'resolution lands, then follows it', (tester) async {
      await useReferenceSurface(tester);
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine);
      store.selectedProtocol = ProtocolId.torOnly; // pick = auto
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      await store.connect();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump(const Duration(milliseconds: 300));
      engine.emit(const EngineStateChanged(VpnState.connected));
      // The adapter already stripped loc=T1 to null (statsEvent) — no
      // «T1» anywhere, the AUTO anchor stays.
      engine.emit(
        const EngineStatsUpdated(pingMs: 210, downBytes: 0, upBytes: 0),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // v8a — +4 steps: the connect roulette's landing re-syncs the name
      // slot (a fresh Hyper-Text decode even when the text lands on the
      // SAME anchor word — the change event fires on the sync rebuild).
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('T1'), findsNothing);
      expect(find.text('خودکار'), findsOneWidget);
      expect(store.exitCountryCode, isNull);

      // The resolution lands (Onionoo said the exit relay is in Austria).
      engine.emit(const EngineExitCountryResolved('at'));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // v8a — +4 steps for the follow-spin's decode, same reason.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(store.exitCountryCode, 'at');
      expect(find.text('اتریش'), findsOneWidget);

      // A late resolution from a dead session must never park a flag on
      // the disconnected home screen (the store applies it ONLY while
      // connected).
      await store.disconnect();
      engine.emit(const EngineStateChanged(VpnState.disconnected));
      await tester.pumpAndSettle();
      engine.emit(const EngineExitCountryResolved('nl'));
      await tester.pumpAndSettle();
      expect(store.exitCountryCode, isNull);
    });

    // ----------------------------------------------------------------
    // v2.1.0's THE HOME WIDGET DECK is RETIRED (v5.3 — the owner:
    // «در نمای 1 جدولی که مدت اتصال، تاخیر و داده جلسه رو نمایش میده
    // باید کلا از اپ حذف بشه»): the session timer, the ping sparkline and
    // the session-data card are gone from the app, and their tests went
    // with them.
    // ----------------------------------------------------------------
  });
}
