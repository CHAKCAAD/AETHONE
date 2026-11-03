/// M2 engine-wiring tests — the evidence-lock for the core↔UI seam:
///  * Aether argument mapping (all 11 protocol tiles, country gating, scan),
///  * zeptun TOML,
///  * the end-to-end probe against a REAL local SOCKS5 server,
///  * the PlatformEngineAdapter state walks (proxy/tunnel modes, permission
///    denial, engine death, disconnect cleanup) over a mocked
///    `aethone/engine` channel + a fake embedded core.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aethone/connection/aether_ffi.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/connection/tunnel_probe.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channelName = 'aethone/engine';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_channelName), null);
  });

  group('AetherArguments.build — protocol table (evidence-locked)', () {
    List<String> build(ProtocolId id, {String? country, int scan = 5}) =>
        AetherArguments.build(
          protocol: id,
          countryCode: country,
          scanSpeed: scan,
          filesDir: '/data/files',
          nativeLibraryDir: '/data/lib',
        );

    test('masque', () {
      expect(
        build(ProtocolId.masque),
        containsAllInOrder(['--protocol', 'masque']),
      );
    });
    test('wireguard', () {
      expect(
        build(ProtocolId.wireguard),
        containsAllInOrder(['--protocol', 'wg']),
      );
    });
    test('gool', () {
      expect(build(ProtocolId.gool), containsAllInOrder(['--protocol', 'gool']));
    });
    test('goolClassic sets BOTH the protocol and the classic submode', () {
      expect(
        build(ProtocolId.goolClassic),
        containsAllInOrder(['--protocol', 'gool', '--gool-classic']),
      );
    });
    test('mim', () {
      expect(build(ProtocolId.mim), containsAllInOrder(['--protocol', 'mim']));
    });
    test('torChain uses --tor (chain), NOT --protocol', () {
      final args = build(ProtocolId.torChain);
      expect(args, contains('--tor'));
      expect(args, isNot(contains('--protocol')));
    });
    test('torReverse', () {
      expect(build(ProtocolId.torReverse), contains('--tor-reverse'));
    });
    test('torOnly', () {
      expect(build(ProtocolId.torOnly), contains('--tor-only'));
    });
    test('psiphonChain uses --psiphon + the PT binary + the state dir', () {
      final args = build(ProtocolId.psiphonChain);
      expect(args, contains('--psiphon'));
      expect(args, containsAllInOrder(['--psiphon-bin', '/data/lib/liblyrebird.so']));
      expect(
        args,
        containsAllInOrder(['--psiphon-dir', '/data/files/aether/psiphon']),
      );
    });
    test('psiphonReverse still gets the PT binary (its exit is WARP)', () {
      final args = build(ProtocolId.psiphonReverse);
      expect(args, contains('--psiphon-reverse'));
      expect(args, containsAllInOrder(['--psiphon-bin', '/data/lib/liblyrebird.so']));
    });
    test('psiphonOnly', () {
      expect(build(ProtocolId.psiphonOnly), contains('--psiphon-only'));
    });
    test('auto falls back to the core default protocol (masque)', () {
      expect(
        build(ProtocolId.auto),
        containsAllInOrder(['--protocol', 'masque']),
      );
    });

    test('common args are always present', () {
      final args = build(ProtocolId.masque);
      expect(args, containsAllInOrder(['--bind', '127.0.0.1:1819']));
      expect(args, containsAllInOrder(['--config', '/data/files/aether/warp.toml']));
      expect(args, containsAllInOrder(['--log-level', 'info']));
      expect(args, containsAllInOrder(['--scan', 'turbo'])); // scanSpeed 5
    });
  });

  group('AetherArguments.build — country pinning is honest per exit kind', () {
    List<String> build(ProtocolId id, String country) => AetherArguments.build(
      protocol: id,
      countryCode: country,
      filesDir: '/f',
      nativeLibraryDir: '/l',
    );

    test('WARP-exit mode pins --exit-loc (uppercased)', () {
      expect(
        build(ProtocolId.masque, 'de'),
        containsAllInOrder(['--exit-loc', 'DE']),
      );
      expect(
        build(ProtocolId.wireguard, 'nl'),
        containsAllInOrder(['--exit-loc', 'NL']),
      );
      // psiphonReverse exits through WARP → exit-loc applies.
      expect(
        build(ProtocolId.psiphonReverse, 'de'),
        containsAllInOrder(['--exit-loc', 'DE']),
      );
    });

    test('Psiphon-exit mode pins --psiphon-region (lowercased)', () {
      expect(
        build(ProtocolId.psiphonChain, 'de'),
        containsAllInOrder(['--psiphon-region', 'de']),
      );
      expect(
        build(ProtocolId.psiphonOnly, 'de'),
        containsAllInOrder(['--psiphon-region', 'de']),
      );
    });

    test('Tor exits are NOT pinned (would be a lie)', () {
      final args = build(ProtocolId.torChain, 'de');
      expect(args, isNot(contains('--exit-loc')));
      expect(args, isNot(contains('--psiphon-region')));
    });
  });

  group('AetherArguments.scanProfile — «سرعت اسکن» 1..5', () {
    test('5=turbo 4=balanced 3=thorough 2=verified 1=ironclad; clamped', () {
      expect(AetherArguments.scanProfile(5), 'turbo');
      expect(AetherArguments.scanProfile(4), 'balanced');
      expect(AetherArguments.scanProfile(3), 'thorough');
      expect(AetherArguments.scanProfile(2), 'verified');
      expect(AetherArguments.scanProfile(1), 'ironclad');
      expect(AetherArguments.scanProfile(99), 'turbo');
      expect(AetherArguments.scanProfile(0), 'ironclad');
    });
  });

  group('ZeptunConfigToml.build', () {
    test('mobile preset + socks5 handler on the given port + fake-IP DNS', () {
      final toml = ZeptunConfigToml.build(socksPort: 1820);
      expect(toml, contains('preset = "mobile"'));
      expect(toml, contains('kind = "socks5"'));
      expect(toml, contains('server = "127.0.0.1:1820"'));
      expect(toml, contains('fake_ip = true'));
    });
  });

  group('TunnelProbe.parseBody', () {
    const body = 'fl=x\nh=www.cloudflare.com\nip=162.158.1.1\nts=1700000000.000\n'
        'visit_scheme=https\nuag=test\ncolo=FRA\nloc=DE\ntls=TLSv1.3\n'
        'sni=plaintext\nwarp=on\ngateway=off\nrbi=off\nkex=X25519\n';

    test('parses exit country, ip, warp and lowercases the code', () {
      final r = TunnelProbe.parseBody(body, 123);
      expect(r.exitCountryCode, 'de');
      expect(r.exitIp, '162.158.1.1');
      expect(r.warp, isTrue);
      expect(r.pingMs, 123);
    });

    test('parses an HTTP-wrapped trace body', () {
      final r = TunnelProbe.parseBody(
        'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$body',
        7,
      );
      expect(r.exitCountryCode, 'de');
      expect(r.pingMs, 7);
    });

    test('a body without loc= fails the probe (never fabricated)', () {
      expect(
        () => TunnelProbe.parseBody('fl=x\nip=1.2.3.4\n', 5),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('TunnelProbe against a REAL local SOCKS5 listener', () {
    test('listener readiness', () async {
      final server = await _FakeSocks5Server().start();
      try {
        expect(await TunnelProbe.isListenerReady(server.port), isTrue);
        expect(await TunnelProbe.waitForListener(server.port), isTrue);
      } finally {
        await server.dispose();
      }
      expect(await TunnelProbe.isListenerReady(1), isFalse);
    });

    test('full probe: SOCKS5 CONNECT (domain) + trace → ping + exit country', () async {
      final server = await _FakeSocks5Server().start();
      try {
        final result = await TunnelProbe().trace(port: server.port);
        expect(result.exitCountryCode, 'de');
        expect(result.warp, isTrue);
        expect(result.pingMs, greaterThanOrEqualTo(0));
        // The CONNECT request dialed the DOMAIN through the proxy.
        expect(server.lastConnectTarget, 'www.cloudflare.com');
        expect(server.lastConnectWasDomain, isTrue);
      } finally {
        await server.dispose();
      }
    });

    test('a SOCKS5 server that refuses CONNECT fails the probe', () async {
      final bad = await _FakeSocks5Server(refuseConnect: true).start();
      try {
        await expectLater(
          TunnelProbe().trace(port: bad.port),
          throwsA(isA<SocketException>()),
        );
      } finally {
        await bad.dispose();
      }
    });
  });

  group('PlatformEngineAdapter — state walks (mocked channel, fake core)', () {
    late _FakeSocks5Server listener;

    setUp(() async {
      // The adapter uses the evidence-locked ports; masque = 1819.
      listener = await _FakeSocks5Server().startOn(1819);
    });

    tearDown(() async {
      await listener.dispose();
    });

    void mockChannel({
      Map<Object?, Object?> Function()? prepareVpn,
      void Function(int port)? onStartVpn,
      bool Function()? onStopVpn,
      Map<Object?, Object?> Function()? counters,
    }) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_channelName), (call) async {
            switch (call.method) {
              case 'paths':
                return <String, Object?>{
                  'filesDir': '/data/test/files',
                  'nativeLibraryDir': '/data/test/lib',
                };
              case 'prepareVpn':
                return prepareVpn?.call() ??
                    <String, Object?>{'needsPermission': false};
              case 'startVpn':
                final port = (call.arguments as Map?)?['port'] as int? ?? 1819;
                onStartVpn?.call(port);
                // The real service establishes the TUN + zeptun and THEN
                // emits 'up' — the mock mirrors that timing.
                Timer(const Duration(milliseconds: 150), () {
                  unawaited(emitTunnelEvent({'event': 'up', 'port': port}));
                });
                return null;
              case 'stopVpn':
                onStopVpn?.call();
                return null;
              case 'vpnStatus':
                return <String, Object?>{'running': false, 'port': null};
              case 'zeptunCounters':
                return counters?.call() ??
                    <String, Object?>{'rxBytes': 111, 'txBytes': 222};
            }
            return null;
          });
    }

    List<VpnState> statesOf(List<EngineEvent> events) =>
        events.whereType<EngineStateChanged>().map((e) => e.state).toList();

    test('proxy mode: connecting → connected ONLY via the probe; core args locked', () async {
      mockChannel();
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.proxy,
          selectedCountryCode: 'de',
        ),
      );

      await adapter.connect();
      // The adapter's broadcast controller delivers asynchronously — drain
      // the microtask queue before asserting on emitted events.
      await pumpEventQueue();

      expect(statesOf(events), [VpnState.connecting, VpnState.connected]);
      final stats = events.whereType<EngineStatsUpdated>().single;
      expect(stats.exitCountryCode, 'de');
      expect(stats.pingMs, isNotNull);

      // The core received the evidence-locked argument set.
      expect(core.startedArgs.single, containsAllInOrder(['--protocol', 'masque']));
      expect(core.startedArgs.single, containsAllInOrder(['--exit-loc', 'DE']));
      expect(
        core.startedArgs.single,
        containsAllInOrder(['--config', '/data/test/files/aether/warp.toml']),
      );

      // Steady state: the ticker refreshes REAL stats (job alive + probe).
      await adapter.debugTick();
      await pumpEventQueue();
      expect(events.whereType<EngineStatsUpdated>().length, 2);

      // Disconnect: job cancelled + freed; no VPN to stop in proxy mode.
      await adapter.disconnect();
      await pumpEventQueue();
      expect(core.cancelled, [42]);
      expect(core.freed, [42]);
      expect(statesOf(events).last, VpnState.disconnected);
    });

    test('tunnel mode: permission → VpnService → zeptun counters in stats', () async {
      var stopped = false;
      final startedPorts = <int>[];
      mockChannel(
        onStartVpn: startedPorts.add,
        onStopVpn: () => stopped = true,
      );
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      // The service comes up shortly after startVpn (as the real one does);
      // the mock emits 'up' 150 ms later — pump real time until connected.
      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await pumpEventQueue();

      expect(startedPorts, [1819]);
      expect(statesOf(events), [VpnState.connecting, VpnState.connected]);

      await adapter.debugTick();
      await pumpEventQueue();
      final stats = events.whereType<EngineStatsUpdated>();
      // TUN tx (222) = download; TUN rx (111) = upload.
      expect(stats.last.downBytes, 222);
      expect(stats.last.upBytes, 111);

      await adapter.disconnect();
      await pumpEventQueue();
      expect(stopped, isTrue);
      expect(core.freed, [42]);
      expect(statesOf(events).last, VpnState.disconnected);
    });

    test('VPN permission denial → failed(vpnPermissionDenied), nothing started', () async {
      var vpnStarted = false;
      mockChannel(
        prepareVpn: () => {'needsPermission': true},
        onStartVpn: (_) => vpnStarted = true,
      );
      // Deny after a short delay (the user tapped "cancel").
      Timer(const Duration(milliseconds: 100), () {
        emitTunnelEvent({'event': 'permission', 'granted': false});
      });

      final adapter = PlatformEngineAdapter(coreFactory: _FakeCore.new);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      await adapter.connect();
      await pumpEventQueue();

      expect(vpnStarted, isFalse);
      expect(statesOf(events), [
        VpnState.waitingForPermissions,
        VpnState.failed,
      ]);
      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.errorCode, 'vpnPermissionDenied');
    });

    test('engine death while connected → failed + tunnel torn down', () async {
      var stopped = false;
      mockChannel(onStopVpn: () => stopped = true);
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.connected);

      // The core exits on its own → the adapter must stop faking.
      core.pollState = 'done';
      await adapter.debugTick();
      await pumpEventQueue();

      expect(stopped, isTrue);
      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.state, VpnState.failed);
      expect(failure.errorCode, 'engineClosed');
    });

    test('missing native core → honest failure (libraryMissing), never fake', () async {
      mockChannel();
      final adapter = PlatformEngineAdapter(); // no factory: real AetherCore
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.proxy,
        ),
      );

      await adapter.connect();
      await pumpEventQueue();

      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.state, VpnState.failed);
      expect(failure.errorCode, 'libraryMissing');
    });
  });
}

/// Simulates the platform→Dart direction (Kotlin emits `onTunnelEvent`).
Future<void> emitTunnelEvent(Map<String, Object?> args) async {
  final data = const StandardMethodCodec()
      .encodeMethodCall(MethodCall('onTunnelEvent', args));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_channelName, data, (ByteData? _) {});
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A minimal REAL-socket SOCKS5 server: greeting → CONNECT (ATYP=domain) →
/// serves the cloudflare-trace body. [refuseConnect] makes it answer REP≠0.
class _FakeSocks5Server {
  _FakeSocks5Server({this.refuseConnect = false});

  final bool refuseConnect;
  ServerSocket? _server;
  int get port => _server!.port;
  String? lastConnectTarget;
  bool lastConnectWasDomain = false;

  Future<_FakeSocks5Server> start() => startOn(0);

  Future<_FakeSocks5Server> startOn(int port) async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handle, onError: (Object _) {});
    return this;
  }

  Future<void> dispose() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _handle(Socket socket) async {
    final reader = StreamIterator<Uint8List>(socket);
    try {
      // --- greeting [VER NMETHODS METHODS...] → [VER METHOD] ---
      if (!await reader.moveNext()) return;
      socket.add(const <int>[0x05, 0x00]);
      await socket.flush();

      // --- CONNECT request ---
      if (!await reader.moveNext()) return;
      final req = reader.current;
      if (req.length < 5) return;
      final atyp = req[3];
      String target;
      if (atyp == 0x03) {
        final len = req[4];
        target = ascii.decode(req.sublist(5, 5 + len));
        lastConnectWasDomain = true;
      } else if (atyp == 0x01) {
        target = req.sublist(4, 8).join('.');
        lastConnectWasDomain = false;
      } else {
        return;
      }
      lastConnectTarget = target;

      if (refuseConnect) {
        socket.add(const <int>[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        await socket.close();
        return;
      }
      socket.add(const <int>[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await socket.flush();

      // --- HTTP request until the blank line, then the trace body ---
      final http = BytesBuilder();
      while (await reader.moveNext()) {
        http.add(reader.current);
        final text = ascii.decode(http.toBytes(), allowInvalid: true);
        if (text.contains('\r\n\r\n') || text.length > 4096) break;
      }
      socket.add(
        ascii.encode(
          'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n'
          '\r\nfl=x\nh=www.cloudflare.com\nip=162.158.1.1\ncolo=FRA\nloc=DE\n'
          'tls=TLSv1.3\nsni=plaintext\nwarp=on\ngateway=off\nrbi=off\nkex=X25519\n',
        ),
      );
      await socket.flush();
      await socket.close();
    } catch (_) {
      // A listener-check connection (connect + destroy) lands here — fine.
    } finally {
      await reader.cancel();
      socket.destroy();
    }
  }
}

/// Fake embedded core: records the arguments, plays a job state.
class _FakeCore implements AetherCoreApi {
  List<List<String>> startedArgs = [];
  String pollState = 'running';
  String? pollError;
  final List<int> cancelled = [];
  final List<int> freed = [];

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
    pollState = 'done'; // cooperative cancel lands
    return true;
  }

  @override
  bool jobFree(int id) {
    freed.add(id);
    return true;
  }
}

/// A config source with fixed user choices (interface getter names).
class _FixedConfig implements EngineConfigSource {
  _FixedConfig({
    ProtocolId? selectedProtocol,
    ConnectionMode? connectionMode,
    this.selectedCountryCode,
  }) : selectedProtocol = selectedProtocol ?? ProtocolId.masque,
       connectionMode = connectionMode ?? ConnectionMode.proxy;

  @override
  final ProtocolId selectedProtocol;
  @override
  final ConnectionMode connectionMode;
  @override
  final String? selectedCountryCode;

  @override
  int get scanSpeed => 5;
}
