/// v4.19 device-test round tests — the owner's 10 real-phone reports:
///  * #3  tap-to-cancel during the engine walk (store + adapter + UI),
///  * #2  the app FOLLOWS the Aether core: a core that dies during the
///        listener wait fails the walk fast, with the CORE's own error,
///  * #4  the cold default protocol is WireGuard,
///  * #5  the wheel policy: selectable only where the pin is honored;
///        psiphon-exit modes filter to the Psiphon egress regions,
///  * #8  settings persistence round-trip (SharedPreferences mock).
library;

import 'dart:async';

import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/core_settings.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/connection/settings_persistence.dart';
import 'package:aethone/connection/transport_modes.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/widgets/hero_logo.dart';
import 'package:aethone/connection/aether_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channelName = 'aethone/engine';

/// A controllable engine: connect() walks to `connecting` and then PARKS
/// (like the real adapter waiting for the listener) until the test (or a
/// cancel) releases it.
class _ParkedEngine implements EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  Completer<void>? _walk;

  void emit(EngineEvent e) => _controller.add(e);
  bool cancelRequested = false;

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    _controller.add(const EngineStateChanged(VpnState.connecting));
    _walk = Completer<void>();
    await _walk!.future;
  }

  @override
  Future<void> disconnect() async {
    cancelRequested = true;
    _walk?.complete();
    _walk = null;
    _controller.add(const EngineStateChanged(VpnState.disconnected));
  }

  @override
  void bind(EngineConfigSource config) {}
}

/// The adapter harness of m2_engine_test: fake core + mocked channel.
class _FakeCore implements AetherCoreApi {
  _FakeCore({this.pollState = 'running', this.pollError});
  String pollState;
  String? pollError;
  final List<int> cancelled = [];
  final List<int> freed = [];
  final List<List<String>> startedArgs = [];

  @override
  int coreStart(List<String> args) {
    startedArgs.add(args);
    return 42;
  }

  @override
  AetherReply jobPoll(int id) {
    if (pollState == 'done') {
      return AetherReply(true, {
        'state': 'done',
        'result': const {'state': 'closed'},
      });
    }
    if (pollState == 'error') {
      return AetherReply(false, {'error': pollError ?? 'the core failed'});
    }
    return AetherReply(true, const {'state': 'running'});
  }

  @override
  bool jobCancel(int id) {
    cancelled.add(id);
    pollState = 'done';
    return true;
  }

  @override
  bool jobFree(int id) {
    freed.add(id);
    return true;
  }
}

void _mockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel(_channelName), (call) async {
        switch (call.method) {
          case 'paths':
            return <String, Object?>{
              'filesDir': '/data/test/files',
              'nativeLibraryDir': '/data/test/lib',
            };
          case 'vpnStatus':
            return <String, Object?>{'running': false, 'port': null};
        }
        return null; // startCoreHold / stopCoreHold / coreHoldStatus …
      });
}

Widget _booth(Widget child) => MaterialApp(
  locale: const Locale('fa'),
  supportedLocales: const [Locale('fa')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_channelName), null);
  });

  group('#4 — the cold default protocol is WireGuard (owner decree)', () {
    test('fresh store starts on wireguard, not the core default masque', () {
      final store = ConnectionStore(engine: _ParkedEngine());
      expect(store.selectedProtocol, ProtocolId.wireguard);
    });
  });

  group('#3 — tap-to-cancel during the engine walk', () {
    test('disconnect while connecting cancels the pending connection', () async {
      final engine = _ParkedEngine();
      final store = ConnectionStore(engine: engine);
      final walk = store.connect();
      await pumpEventQueue();
      expect(store.state, VpnState.connecting);

      await store.disconnect();
      await pumpEventQueue();
      await walk;

      expect(engine.cancelRequested, isTrue);
      expect(store.state, VpnState.disconnected);
      expect(store.lastErrorCode, isNull); // a cancel is NOT a failure
    });

    test('a stale `connected` emission during the cancel is dropped',
        () async {
      final engine = _ParkedEngine();
      final store = ConnectionStore(engine: engine);
      final walk = store.connect();
      await pumpEventQueue();
      expect(store.state, VpnState.connecting);

      final cancel = store.disconnect();
      // The walk's in-flight emission races the cancel (the event-loop
      // window between the adapter checkpoint and its emit): it must never
      // land as an illegalTransition failure.
      engine.emit(const EngineStateChanged(VpnState.connected));
      await pumpEventQueue();
      await cancel;
      await walk;

      expect(store.state, VpnState.disconnected);
      expect(store.lastErrorCode, isNull);
    });

    test('multi-tap during the cancel is harmless', () async {
      final engine = _ParkedEngine();
      final store = ConnectionStore(engine: engine);
      final walk = store.connect();
      await pumpEventQueue();

      final first = store.disconnect();
      await store.disconnect(); // re-entrancy guard: no-op
      await first;
      await walk;

      expect(store.state, VpnState.disconnected);
    });

    testWidgets('a tap on the hero logo during connecting cancels (owner #3)',
        (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final engine = _ParkedEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      final walk = store.connect();
      // `connecting` plays the repeating scan halo — bounded pumps.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.state, VpnState.connecting);

      await tester.tap(find.byType(HeroLogo), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      // The cancel landed (the parked engine releases synchronously, so the
      // machine may already be through disconnecting → disconnected).
      expect(
        store.state,
        anyOf(VpnState.disconnecting, VpnState.disconnected),
      );

      await walk;
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.state, VpnState.disconnected);
      expect(store.lastErrorCode, isNull);
    });
  });

  group('#2 — the app follows the Aether core (fail fast, core error)', () {
    List<VpnState> statesOf(List<EngineEvent> events) =>
        events.whereType<EngineStateChanged>().map((e) => e.state).toList();

    test('a core that exits during the listener wait fails with coreExited',
        () async {
      _mockChannel();
      final core = _FakeCore(pollState: 'done'); // dies immediately
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(_Cfg());

      await adapter.connect();
      await pumpEventQueue();

      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.state, VpnState.failed);
      expect(failure.errorCode, 'coreExited');
      expect(failure.message, contains('closed'));
      // The dead core's job was still cleaned up.
      expect(core.freed, [42]);
    });

    test('the CORE\'s own error text is surfaced, not a generic timeout',
        () async {
      _mockChannel();
      final core = _FakeCore(pollState: 'error', pollError: 'warp registration failed');
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      // v4.21: the single-knob selection — torChain carries the fixed
      // WireGuard leg inside the adapter (the v4.20 two-knob split was
      // reverted), so the args still read `--protocol wg --tor`.
      adapter.bind(_Cfg(selectedProtocol: ProtocolId.torChain));

      await adapter.connect();
      await pumpEventQueue();

      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.state, VpnState.failed);
      expect(failure.errorCode, 'coreExited');
      expect(failure.message, contains('warp registration failed'));
      // torChain walks on the 1820 listener, and the core still received
      // the full v4.20 argument set (leg + overlay + PT + state dir).
      expect(
        core.startedArgs.single,
        containsAllInOrder(['--protocol', 'wg', '--tor']),
      );
      expect(
        core.startedArgs.single,
        contains('--tor-pt'),
      );
    });

    test('a user cancel mid-walk ends disconnected with NO late failure',
        () async {
      _mockChannel();
      final core = _FakeCore(); // healthy core, but nothing listens on 1819
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(_Cfg());

      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 120));

      await adapter.disconnect(); // the store's cancel path
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.disconnected);

      // Drain the cancelled walk: it must stay SILENT (no timeout failure,
      // no connected) — the cancel owns the terminal state.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      await pumpEventQueue();
      expect(events.whereType<EngineStateChanged>().last.state,
          VpnState.disconnected);
      expect(
        events.whereType<EngineStateChanged>().where(
              (e) => e.state == VpnState.failed,
            ),
        isEmpty,
      );
    });
  });

  group('#5 — the per-protocol wheel policy', () {
    test('selectable for BOTH families (v4.21 owner decree)', () {
      expect(LocationWheelPolicy.selectable(ProtocolId.psiphonOnly), isTrue);
      expect(LocationWheelPolicy.selectable(ProtocolId.psiphonChain), isTrue);
      expect(LocationWheelPolicy.selectable(ProtocolId.psiphonReverse), isTrue);
      expect(LocationWheelPolicy.selectable(ProtocolId.torReverse), isTrue);
      // v4.21 — the tor family is a REAL selector too (owner: «در حالت تور
      // انتخاب لوکیشن باید فعال باشه، چرا پرچم ها نشون داده نمیشن؟»); the
      // core has no tor exit pin, so the pick is a remembered display
      // anchor that locks on the engine-reported exit once connected.
      expect(LocationWheelPolicy.selectable(ProtocolId.torOnly), isTrue);
      expect(LocationWheelPolicy.selectable(ProtocolId.torChain), isTrue);
      // WARP-family: the band is a hidden-then-connected DISPLAY.
      expect(LocationWheelPolicy.selectable(ProtocolId.wireguard), isFalse);
      expect(LocationWheelPolicy.selectable(ProtocolId.masque), isFalse);
    });

    test('only the psiphon-EXIT modes filter to the egress regions (+auto)', () {
      // v4.21 — the exact list carries the AUTO entry FIRST.
      final psiphonChain =
          LocationWheelPolicy.allowedCodes(ProtocolId.psiphonChain)!;
      expect(psiphonChain.first, LocationWheelPolicy.autoCode);
      expect(psiphonChain, containsAll(psiphonEgressRegions));
      expect(psiphonChain.length, psiphonEgressRegions.length + 1);
      expect(
        LocationWheelPolicy.allowedCodes(ProtocolId.psiphonOnly),
        same(psiphonChain),
      );
      // The reverse modes + the tor family run on the FULL manifest with
      // the auto entry prepended by the wheel.
      expect(LocationWheelPolicy.allowedCodes(ProtocolId.psiphonReverse), isNull);
      expect(LocationWheelPolicy.allowedCodes(ProtocolId.torChain), isNull);
      expect(LocationWheelPolicy.autoEntry(ProtocolId.torChain), isTrue);
      expect(LocationWheelPolicy.autoEntry(ProtocolId.psiphonReverse), isTrue);
      expect(LocationWheelPolicy.autoEntry(ProtocolId.psiphonChain), isFalse);
      expect(LocationWheelPolicy.autoEntry(ProtocolId.wireguard), isFalse);
    });

    test('psiphon region list is sane: lowercase 2-letter, no Iran egress',
        () {
      for (final r in psiphonEgressRegions) {
        expect(r.length, 2, reason: r);
        expect(r, r.toLowerCase(), reason: r);
      }
      expect(psiphonEgressRegions.contains('ir'), isFalse);
      // Well-known Psiphon egress anchors are present.
      for (final anchor in ['us', 'ca', 'gb', 'de', 'nl', 'se', 'sg', 'jp']) {
        expect(psiphonEgressRegions.contains(anchor), isTrue, reason: anchor);
      }
    });

    test('store getters follow the selected protocol', () {
      final store = ConnectionStore(engine: _ParkedEngine());
      expect(store.wheelSelectable, isFalse); // wireguard default
      store.selectProtocol(ProtocolId.psiphonChain);
      expect(store.wheelSelectable, isTrue);
      expect(store.wheelAllowedCodes?.first, LocationWheelPolicy.autoCode);
      expect(store.wheelAllowedCodes, containsAll(psiphonEgressRegions));
      expect(store.wheelAutoEntry, isFalse); // the list carries auto itself
      store.selectProtocol(ProtocolId.torChain);
      expect(store.wheelSelectable, isTrue); // v4.21: tor is a selector too
      expect(store.wheelAllowedCodes, isNull); // full manifest
      expect(store.wheelAutoEntry, isTrue); // auto prepended by the wheel
      // The per-family anchors (v4.21).
      expect(store.wheelAnchorCode, LocationWheelPolicy.autoCode);
      store.psiphonLocation = 'de';
      store.selectProtocol(ProtocolId.psiphonOnly);
      expect(store.wheelAnchorCode, 'de');
      store.torLocation = 'nl';
      store.selectProtocol(ProtocolId.torReverse);
      expect(store.wheelAnchorCode, 'nl');
    });

    testWidgets(
        'a psiphon selection shows the AUTO-anchored wheel (v4.21: the pick '
        'is remembered per family, auto = the core\'s own choice)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: _ParkedEngine());
      store.selectProtocol(ProtocolId.psiphonChain);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // The cold anchor is the family's remembered pick — AUTO by default
      // (owner: «راستی برای سایفون و تور به انتخاب خودکار هم باید بزاریم»).
      expect(store.psiphonLocation, LocationWheelPolicy.autoCode);
      // The header renders «خودکار» (the AUTO sentinel), not ایران.
      expect(find.text('خودکار'), findsOneWidget);
      expect(find.text('ایران'), findsNothing);

      // A committed pick is remembered on the family field.
      store.selectLocation('de');
      await tester.pumpAndSettle();
      expect(store.psiphonLocation, 'de');
      expect(find.text('آلمان'), findsOneWidget);

      // Switching to the tor family anchors on ITS pick (per-family
      // memory, owner: «اپ باید انتخاب لوکیشن سایفون و تور رو یادش بمونه»).
      store.selectProtocol(ProtocolId.torChain);
      await tester.pumpAndSettle();
      expect(store.torLocation, LocationWheelPolicy.autoCode);
      expect(find.text('خودکار'), findsOneWidget);
      // …and switching back keeps the psiphon pick.
      store.selectProtocol(ProtocolId.psiphonChain);
      await tester.pumpAndSettle();
      expect(find.text('آلمان'), findsOneWidget);
    });
  });

  group('#8 — settings persistence', () {
    test('restore applies remembered values; garbage falls back safely',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aethone.settings.protocol': 'psiphonChain',
        'aethone.settings.connectionMode': 'tunnel',
        'aethone.settings.scanSpeed': 2,
        'aethone.settings.selectedCountry': 'de',
        'aethone.settings.protocolModeSmart': true,
        'aethone.settings.routingRegion': 'tm',
        'aethone.settings.killSwitch': false,
        'aethone.settings.homeLook': 'two',
        'aethone.settings.motionStyle': 'smooth',
      });
      final persistence = SettingsPersistence();
      final store = ConnectionStore(engine: _ParkedEngine());
      await persistence.restore(store);

      // v4.21 migration: a v4.19/v4.20 install that persisted a family
      // member (in `protocol` for v4.19, in `chain` for v4.20) restores it
      // as THE single-knob protocol — the fixed WireGuard leg rides inside
      // the adapter (owner: «لطفا به حالت قبل برشگردون»).
      expect(store.selectedProtocol, ProtocolId.psiphonChain);
      expect(store.effectiveProtocol, ProtocolId.psiphonChain);
      expect(store.connectionMode, ConnectionMode.tunnel);
      expect(store.scanSpeed, 2);
      expect(store.selectedCountryCode, 'de');
      expect(store.protocolModeSmart, isTrue);
      expect(store.routingRegion, 'tm');
      expect(store.killSwitch, isFalse);
      expect(store.homeLook, HomeLook.two);
      expect(store.animationStyle, MotionStyle.smooth);
    });

    test('unknown enum names and out-of-range values keep the defaults',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aethone.settings.protocol': 'bogus',
        'aethone.settings.connectionMode': 'ssh',
        'aethone.settings.scanSpeed': 99,
        'aethone.settings.selectedCountry': 'IRAN',
        'aethone.settings.homeLook': 'three',
      });
      final persistence = SettingsPersistence();
      final store = ConnectionStore(engine: _ParkedEngine());
      await persistence.restore(store);

      expect(store.selectedProtocol, ProtocolId.wireguard); // v4.19 default
      expect(store.connectionMode, ConnectionMode.proxy);
      expect(store.scanSpeed, 5);
      expect(store.selectedCountryCode, isNull);
      expect(store.homeLook, HomeLook.one);
    });

    test('save → fresh restore round-trips the user choices', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = ConnectionStore(engine: _ParkedEngine());
      final persistence = SettingsPersistence();
      await persistence.restore(store);

      // v4.21 — the single knob + the per-family locations round-trip.
      store.selectProtocol(ProtocolId.torOnly);
      store.setConnectionMode(ConnectionMode.tunnel);
      store.setScanSpeed(3);
      store.selectCountry('nl');
      store.psiphonLocation = 'de';
      store.torLocation = 'auto';

      await persistence.save(store);

      final fresh = ConnectionStore(engine: _ParkedEngine());
      await persistence.restore(fresh);
      expect(fresh.selectedProtocol, ProtocolId.torOnly);
      expect(fresh.effectiveProtocol, ProtocolId.torOnly);
      expect(fresh.connectionMode, ConnectionMode.tunnel);
      expect(fresh.scanSpeed, 3);
      expect(fresh.selectedCountryCode, 'nl');
      expect(fresh.psiphonLocation, 'de');
      expect(fresh.torLocation, 'auto');
    });

    test('v4.21 — a v4.20 chain overlay migrates into the single knob',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        // A v4.20 install: the WARP leg in `protocol`, the family in
        // `chain` — the overlay was the effective mode, so it wins.
        'aethone.settings.protocol': 'wireguard',
        'aethone.settings.chain': 'torChain',
      });
      final persistence = SettingsPersistence();
      final store = ConnectionStore(engine: _ParkedEngine());
      await persistence.restore(store);

      expect(store.selectedProtocol, ProtocolId.torChain);
      expect(store.effectiveProtocol, ProtocolId.torChain);
    });
  });
}

class _Cfg implements EngineConfigSource {
  _Cfg({ProtocolId? selectedProtocol})
      : selectedProtocol = selectedProtocol ?? ProtocolId.wireguard;
  @override
  final ProtocolId selectedProtocol;

  @override
  ConnectionMode get connectionMode => ConnectionMode.proxy;
  @override
  String? get selectedCountryCode => null;
  @override
  String get psiphonLocation => 'auto';
  @override
  String get torLocation => 'auto';
  @override
  int get scanSpeed => 5;

  /// v4.22 — the fine-grained core layer (the fake runs the defaults).
  @override
  CoreSettings get coreSettings => CoreSettings();
}
