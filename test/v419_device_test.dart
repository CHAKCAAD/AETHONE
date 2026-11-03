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
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/connection/settings_persistence.dart';
import 'package:aethone/connection/transport_modes.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/core/country_names.dart';
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
      // v4.20: the overlay rides on the WireGuard leg — the core-exit path
      // is identical, but the args must carry BOTH knobs.
      adapter.bind(_Cfg(selectedChain: ProtocolId.torChain));

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
    test('selectable only where the core honors the pick', () {
      expect(LocationWheelPolicy.selectable(ProtocolId.psiphonOnly), isTrue);
      expect(LocationWheelPolicy.selectable(ProtocolId.psiphonChain), isTrue);
      expect(LocationWheelPolicy.selectable(ProtocolId.psiphonReverse), isTrue);
      expect(LocationWheelPolicy.selectable(ProtocolId.torReverse), isTrue);
      // Tor-EXIT modes cannot pin an exit country (no core flag exists):
      expect(LocationWheelPolicy.selectable(ProtocolId.torOnly), isFalse);
      expect(LocationWheelPolicy.selectable(ProtocolId.torChain), isFalse);
      // WARP-family: the band is a hidden-then-connected DISPLAY.
      expect(LocationWheelPolicy.selectable(ProtocolId.wireguard), isFalse);
      expect(LocationWheelPolicy.selectable(ProtocolId.masque), isFalse);
    });

    test('only the psiphon-EXIT modes filter to the egress regions', () {
      expect(
        LocationWheelPolicy.allowedCodes(ProtocolId.psiphonChain),
        same(psiphonEgressRegions),
      );
      expect(
        LocationWheelPolicy.allowedCodes(ProtocolId.psiphonOnly),
        same(psiphonEgressRegions),
      );
      expect(LocationWheelPolicy.allowedCodes(ProtocolId.psiphonReverse), isNull);
      expect(LocationWheelPolicy.allowedCodes(ProtocolId.torChain), isNull);
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
      expect(store.wheelAllowedCodes, psiphonEgressRegions);
      store.selectProtocol(ProtocolId.torChain);
      expect(store.wheelSelectable, isFalse); // locked display, band visible
      expect(store.wheelAllowedCodes, isNull);
    });

    testWidgets(
        'a psiphon selection filters the wheel and commits the re-anchored '
        'country (the wheel shows what the core honors)', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: _ParkedEngine());
      store.selectProtocol(ProtocolId.psiphonChain);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await tester.pumpAndSettle();

      // The cold 'ir' pick is NOT an egress region → the wheel re-anchored
      // on the first allowed flag and COMMITTED it to the store.
      final committed = store.selectedCountryCode;
      expect(committed, isNotNull);
      expect(psiphonEgressRegions.contains(committed), isTrue,
          reason: committed ?? '');
      // The header renders that country's name (not ایران).
      final name = countryName(committed!);
      expect(name, isNotNull);
      expect(find.text(name!), findsOneWidget);
      expect(find.text('ایران'), findsNothing);
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

      // v4.20 migration: a v4.19 install persisted the family member as THE
      // protocol — it now lands in the chain overlay and the leg keeps its
      // WireGuard default (owner: «اول وایرگارد وصل شه و بعد سایفون»).
      expect(store.selectedChain, ProtocolId.psiphonChain);
      expect(store.effectiveProtocol, ProtocolId.psiphonChain);
      expect(store.selectedProtocol, ProtocolId.wireguard);
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

      // v4.20 — the two knobs round-trip independently.
      store.selectChain(ProtocolId.torOnly);
      store.selectProtocol(ProtocolId.gool);
      store.setConnectionMode(ConnectionMode.tunnel);
      store.setScanSpeed(3);
      store.selectCountry('nl');

      await persistence.save(store);

      final fresh = ConnectionStore(engine: _ParkedEngine());
      await persistence.restore(fresh);
      expect(fresh.selectedChain, ProtocolId.torOnly);
      expect(fresh.selectedProtocol, ProtocolId.gool);
      expect(fresh.effectiveProtocol, ProtocolId.torOnly);
      expect(fresh.connectionMode, ConnectionMode.tunnel);
      expect(fresh.scanSpeed, 3);
      expect(fresh.selectedCountryCode, 'nl');
    });
  });
}

class _Cfg implements EngineConfigSource {
  _Cfg({this.selectedChain});
  @override
  ProtocolId get selectedProtocol => ProtocolId.wireguard;

  /// v4.20 — the overlay family member (null = plain).
  @override
  final ProtocolId? selectedChain;

  @override
  ProtocolId get effectiveProtocol => selectedChain ?? selectedProtocol;
  @override
  ConnectionMode get connectionMode => ConnectionMode.proxy;
  @override
  String? get selectedCountryCode => null;
  @override
  int get scanSpeed => 5;
}
