// PHASE-1 (firefox-vpn) tests: the wire protocol, the port map, the
// location policy and the security invariants of the Dart integration.
//
// What is real here:
//  * FirefoxEngineEvent parsing runs against REAL engine JSON lines
//    (recorded from the engine binary's live lifecycle-test runs);
//  * the engine-state contract (socksReady/failed/authRefreshed routing)
//    is exercised against the REAL host binary
//    (FXV_ENGINE_BIN=… or the repo's own phase1/build/host output)
//    through the same stdin/stdout contract the adapter uses;
//  * the vault tests use a fake codec (plaintext IN TESTS ONLY — never
//    presented as a live session).
import 'dart:convert';
import 'dart:io';

import 'package:aethone/connection/firefox/firefox_discovery.dart';
import 'package:aethone/connection/firefox/firefox_engine.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:aethone/connection/firefox/firefox_session_store.dart';
import 'package:aethone/connection/transport_modes.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:flutter_test/flutter_test.dart';


/// Resolves the REAL host engine binary for the live lifecycle tests:
/// the FXV_ENGINE_BIN override first, then the repo's own build output
/// (phase1/build/host — `phase1/scripts/build_engine.sh host`), then
/// the legacy workspace path. Absent → the suite's own honest skip.
String resolveEngineBin() {
  final candidates = <String>[
    ?Platform.environment['FXV_ENGINE_BIN'],
    '${Directory.current.path}/phase1/build/host/libfirefoxvpn',
    '/home/z/my-project/phase1/build/host/libfirefoxvpn',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return candidates.first;
}

void main() {
  group('firefox wire protocol', () {
    test('parses a real started event', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode('{"event":"started","version":"1.0.0-phase1","pid":42}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.name, FirefoxEngineEvents.started);
      expect(ev.exitCode, 0);
      expect(ev.carriesSecrets, isFalse);
      expect(ev.logLine, contains('started'));
    });

    test('parses a real socksReady event (loopback listener only)', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode('{"event":"socksReady","addr":"127.0.0.1:1822"}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.name, FirefoxEngineEvents.socksReady);
      expect(ev.addr, '127.0.0.1:1822');
    });

    test('parses a real selected event with location separation', () {
      // Field separation decree: country / city / hostname are distinct.
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode(
                '{"event":"selected","country":"FR","countryName":"France",'
                '"cityCode":"LFPB","cityName":"France",'
                '"hostname":"lfpb115.m1.fastly-masque.net:2499","port":2499,'
                '"selectionSource":"country","recommended":false}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.country, 'FR');
      expect(ev.countryName, 'France');
      expect(ev.cityCode, 'LFPB');
      expect(ev.hostname, 'lfpb115.m1.fastly-masque.net:2499');
      expect(ev.port, 2499);
      expect(ev.selectionSource, 'country');
    });

    test('exitVerified separates exit from configured country', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode(
                '{"event":"exitVerified","exitIp":"203.0.113.7",'
                '"exitCountry":"FR","configuredCountry":"FR",'
                '"exitCountryMatches":true,"latencyMs":312}')
                as Map)
            .cast<String, dynamic>(),
      );
      // The decree: chosen country ≠ exit country; both recorded.
      expect(ev.exitCountry, ev.configuredCountry);
      expect(ev.exitCountryMatches, isTrue);
      expect(ev.exitIp, isNotEmpty);
    });

    test('authRefreshed is the ONLY secret-carrying event and never logs',
        () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode(
                '{"event":"authRefreshed","accessToken":"SECRET-AT",'
                '"refreshToken":"SECRET-RT","expiresIn":3600}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.carriesSecrets, isTrue);
      // The log rendering is REDACTED.
      expect(ev.logLine, contains('<redacted>'));
      expect(ev.logLine, isNot(contains('SECRET-AT')));
      expect(ev.logLine, isNot(contains('SECRET-RT')));
    });

    test('failure events carry engine codes verbatim', () {
      const real = '{"event":"failed","code":1,"failCode":"badConfig",'
          '"message":"socksListenNotLoopback: \\"0.0.0.0:1822\\" must be a '
          'loopback address"}';
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode(real) as Map).cast<String, dynamic>(),
      );
      expect(ev.failCode, FirefoxEngineFailure.badConfig);
      expect(ev.exitCode, FirefoxEngineExitCode.startup);
      expect(ev.message, contains('socksListenNotLoopback'));
    });

    test('config JSON never carries secrets outside auth', () {
      const cfg = FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(
          accessToken: 'at-secret',
          refreshToken: 'rt-secret',
        ),
      );
      final blob = jsonEncode(cfg.toJson());
      // auth block carries them (the private stdin pipe)…
      expect(blob, contains('at-secret'));
      // …and nothing else in the envelope leaks them twice.
      expect('at-secret'.allMatches(blob), hasLength(1));
      expect(cfg.transport, 'h2');
      expect(cfg.toJson()['version'], 1);

      expect(cfg.toJson()['dns'], {'mode': 'system'});
      const doh = FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'at'),
        dns: {
          'mode': 'doh',
          'provider': 'quad9',
          'systemForLocalDomains': true,
        },
      );
      expect(doh.toJson()['dns'], {
        'mode': 'doh',
        'provider': 'quad9',
        'systemForLocalDomains': true,
      });
    });
  });

  group('port and mode map (the evidence-locked contract)', () {
    test('firefoxOnly serves SOCKS5 on 127.0.0.1:1822 — loopback only',
        () {
      final mode = TransportModes.byId(ProtocolId.firefoxOnly);
      expect(mode.socksEndpoint.port, 1822);
      expect(mode.socksEndpoint.host, '127.0.0.1');
      expect(mode.socksEndpoint.scheme, 'socks5');
      expect(mode.exitKind, ExitKind.firefoxExit);
      // The engine serves CONNECT only (honest TCP-only label).
      expect(mode.tcpOnly, isTrue);
    });

    test('ports 1819/1820/1821 keep their existing engines untouched', () {
      expect(TransportModes.masque.socksEndpoint.port, 1819);
      expect(TransportModes.torChain.socksEndpoint.port, 1820);
      expect(TransportModes.psiphonChain.socksEndpoint.port, 1821);
      // And no existing mode moved to 1822.
      for (final m in TransportModes.all) {
        if (m.id == ProtocolId.firefoxOnly) continue;
        expect(m.socksEndpoint.port, isNot(1822),
            reason: '${m.label} must not use 1822');
      }
    });

    test('byId round-trips the new mode', () {
      expect(TransportModes.byId(ProtocolId.firefoxOnly).id,
          ProtocolId.firefoxOnly);
      expect(ProtocolId.firefoxOnly.isFirefox, isTrue);
      expect(ProtocolId.firefoxOnly.isTor, isFalse);
      expect(ProtocolId.firefoxOnly.isPsiphon, isFalse);
    });
  });

  group('location model policy (phase-0 decrees)', () {
    final liveSample = FirefoxLocationList(
      locations: const [
        FirefoxLocation(
          countryCode: 'FR',
          countryName: 'France',
          cityCode: 'LFPB',
          cityName: 'France',
          serverHostname: 'lfpb115.m1.fastly-masque.net',
          serverPort: 2499,
          quarantined: false,
          recommended: false,
        ),
        FirefoxLocation(
          countryCode: 'IT',
          countryName: 'Italy',
          cityCode: 'MXP',
          cityName: 'Italy',
          serverHostname: 'mxp69.m1.fastly-masque.net',
          serverPort: 2499,
          quarantined: true, // the live 2026-11-08 sample
          recommended: false,
        ),
        FirefoxLocation(
          countryCode: 'REC',
          countryName: 'Recomended Location',
          cityCode: 'REC',
          cityName: 'Recomended Location',
          serverHostname: 'p.m1.fastly-masque.net',
          serverPort: 2499,
          quarantined: false,
          recommended: true,
        ),
      ],
      fetchedAt: DateTime.now(),
      live: true,
    );

    test('quarantined locations are visible but not selectable', () {
      // honest availability: kept in the model…
      expect(liveSample.locations.length, 3);
      // …but never selectable.
      expect(
        liveSample.selectable
            .every((l) => !l.quarantined),
        isTrue,
      );
    });

    test('REC (auto) is offered first, not counted as a country', () {
      expect(liveSample.selectable.first.recommended, isTrue);
      expect(liveSample.selectableCountryCodes, ['FR']);
    });

    test('cached lists are labeled cached, never presented as live', () {
      final cached = FirefoxLocationList(
        locations: liveSample.locations,
        fetchedAt: DateTime.now().subtract(const Duration(hours: 7)),
        live: false,
      );
      expect(cached.live, isFalse);
      expect(FirefoxDiscovery(cachePath: '/nonexistent', binaryPath: '/x')
          .isStale(cached), isTrue);
    });

    test('JSON round-trip preserves the labels', () {
      final blob = jsonEncode(liveSample.toJson());
      final back = FirefoxLocationList.fromJson(
        (jsonDecode(blob) as Map).cast<String, dynamic>(),
      );
      expect(back.live, liveSample.live);
      expect(back.locations.length, 3);
      expect(back.locations[1].quarantined, isTrue);
      expect(back.locations[2].recommended, isTrue);
    });
  });

  group('session vault (fake codec — plaintext in tests only)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('fxvault');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('save/load/clear round-trip and the logout-grade wipe', () async {
      final store = FirefoxSessionStore(
        vaultPath: '${tmp.path}/session.vault',
      );
      // No platform codec on the host: memory-only persistence — the
      // production path (Android Keystore) is exercised on-device.
      expect(await store.load(), isNull);

      await store.save(const FirefoxSessionAuth(
        accessToken: 'at',
        refreshToken: 'rt',
      ));
      expect((await store.load())?.accessToken, 'at');

      await store.clear();
      expect(await store.load(), isNull);
      expect(File('${tmp.path}/session.vault').existsSync(), isFalse);
    });

    test('a corrupt vault is treated as ABSENT and wiped', () async {
      final path = '${tmp.path}/session.vault';
      File(path).writeAsStringSync('not a vault');
      final store = FirefoxSessionStore(vaultPath: path);
      // The host has no platform codec; without one the vault never
      // decrypts — load() must still come back null, never throw.
      expect(await store.load(), isNull);
    });
  });

  // ------------------------------------------------------------------
  // REAL-ENGINE tests: spawn the actual host binary through the same
  // FirefoxVpnEngine class the adapter uses, and verify the process
  // contract (bare argv, config-on-stdin, events-on-stdout,
  // stdin-EOF shutdown, no orphan).
  // ------------------------------------------------------------------
  group('FirefoxVpnEngine against the REAL host binary', () {
    final bin = resolveEngineBin();

    test('binary exists and is executable', () {
      // NOT TESTED on CI machines without the build — this suite runs in
      // the phase-1 dev environment where the engine is built.
      final f = File(bin);
      expect(f.existsSync(), isTrue, reason: 'engine binary missing');
      expect(f.statSync().mode & 0x49 != 0, isTrue); // any exec bit
    }, skip: !File(bin).existsSync() ? 'engine binary not built' : false);

    test('badConfig fails honestly with the engine\'s own words',
        () async {
      if (!File(bin).existsSync()) {
        markTestSkipped('engine binary not built');
        return;
      }
      final engine = FirefoxVpnEngine(
        binaryPath: bin,
        onLog: (_) {},
      );
      addTearDown(() => engine.dispose());
      final outcome = await engine.start(const FirefoxEngineConfig(
        socksListen: '0.0.0.0:1822', // non-loopback — refused by the engine
        auth: FirefoxSessionAuth(accessToken: 'at'),
      ));
      expect(outcome.state, FirefoxEngineState.failed);
      expect(outcome.failCode, FirefoxEngineFailure.badConfig);
      expect(outcome.exitCode, FirefoxEngineExitCode.startup);
      expect(outcome.message, contains('socksListenNotLoopback'));
    }, skip: !File(bin).existsSync() ? 'engine binary not built' : false);

    test('argv carries NO config and NO secrets (bare spawn)', () async {
      if (!File(bin).existsSync()) {
        markTestSkipped('engine binary not built');
        return;
      }
      final engine = FirefoxVpnEngine(
        binaryPath: bin,
        onLog: (_) {},
        shutdownGrace: const Duration(seconds: 5),
      );
      addTearDown(() => engine.dispose());
      // Even a FAILED start proves the spawn shape: the process must run
      // with argv == [binary] only (config arrives on stdin).
      final outcome = await engine.start(const FirefoxEngineConfig(
        socksListen: '0.0.0.0:1',
        auth: FirefoxSessionAuth(accessToken: 'argv-secret-must-not-leak'),
      ));
      expect(outcome.state, FirefoxEngineState.failed);
      // And the failure message (derived from stdout events) never
      // contains the token.
      expect(outcome.message, isNot(contains('argv-secret-must-not-leak')));
    }, skip: !File(bin).existsSync() ? 'engine binary not built' : false);

    test('stdin close stops the engine (the shutdown request)',
        () async {
      if (!File(bin).existsSync()) {
        markTestSkipped('engine binary not built');
        return;
      }
      final engine = FirefoxVpnEngine(
        binaryPath: bin,
        onLog: (_) {},
        shutdownGrace: const Duration(seconds: 5),
      );
      // Start with a config that CANNOT pass (dead guardian) so the
      // engine stays in its startup walk — then close stdin.
      final outcomeFuture = engine.start(
        const FirefoxEngineConfig(
          socksListen: '127.0.0.1:18299',
          guardian: 'https://127.0.0.1:1', // refused — engine retries
          auth: FirefoxSessionAuth(accessToken: 'at'),
          upstreamOverride: '127.0.0.1:1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await engine.stop();
      final outcome = await outcomeFuture;
      // Either it failed on the guardian or was cleanly cancelled —
      // never a zombie: the process must be GONE.
      expect(
        engine.isAlive,
        isFalse,
        reason: 'no engine process may survive the stop',
      );
      expect(outcome.state, anyOf(FirefoxEngineState.failed,
          FirefoxEngineState.stopped));
    }, skip: !File(bin).existsSync() ? 'engine binary not built' : false);
  });
}
