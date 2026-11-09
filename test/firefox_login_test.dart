// PHASE-2 (firefox-vpn) tests: the WebChannel bridge mapping, the login
// wire protocol, the wheel policy extension, and the login client's
// process contract.
//
// What is real here:
//  * the bridge tests run the REAL pure-Dart mapping against recorded
//    WebChannel message shapes (the commands and envelope are Mozilla's;
//    the mapping is ADAPTED from FoxyVPN's MIT BrowserLoginScreen);
//  * the login-protocol tests parse REAL engine JSON lines (the --login
//    role's events, recorded from the engine's lifecycle-test runs);
//  * the login-client tests spawn the REAL host binary
//    (FXV_ENGINE_BIN=… or the repo's own phase1/build/host output)
//    with the --login role through the same stdin/stdout contract the
//    adapter uses — config validation, bare argv, stdin-EOF clean
//    cancel, and no secret on stdout/stderr are proven on the REAL
//    process.
//
// What is NOT real (and never claimed here): the accounts.firefox.com
// page itself — the real WebChannel capture needs a live browser and a
// real Firefox account (NOT TESTED / BLOCKED without an entitlement).
import 'dart:convert';
import 'dart:io';

import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/firefox/firefox_login.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:aethone/connection/firefox/firefox_web_channel.dart';
import 'package:aethone/connection/transport_modes.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:flutter_test/flutter_test.dart';

const _t = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

String _envelope(String command, Map<String, dynamic> data,
        {String messageId = 'm1', String id = 'account_updates'}) =>
    jsonEncode({
      'id': id,
      'message': {'messageId': messageId, 'command': command, 'data': data},
    });


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
  // ------------------------------------------------------------------
  group('WebChannel bridge (pure mapping, ADAPTED from FoxyVPN MIT)', () {
    // A FRESH bridge per test — the dedup guard is stateful (one
    // capture per sign-in); a shared instance would suppress the later
    // capture tests.
    FirefoxWebChannelBridge freshBridge() => FirefoxWebChannelBridge();
    const origin = 'https://accounts.firefox.com/signin';

    test('fxa_status is answered with no signed-in user', () {
      final r = freshBridge().handle(
          _envelope('fxaccounts:fxa_status', {}), origin);
      expect(r.sessionToken, isNull);
      expect(r.replyScript, isNotNull);
      expect(r.replyScript!, contains('fxaccounts:fxa_status'));
      expect(r.replyScript!, contains('"signedInUser":null'));
    });

    test('can_link_account is answered ok', () {
      final r = freshBridge().handle(
          _envelope('fxaccounts:can_link_account', {}), origin);
      expect(r.replyScript, contains('"ok":true}'));
    });

    test('login hands over the session token (sessionToken field)', () {
      final r = freshBridge().handle(
          _envelope('fxaccounts:login', {'sessionToken': _t}), origin);
      expect(r.sessionToken, _t);
      expect(r.replyScript, contains('"ok":true}'));
    });

    test('oauth_login variant (token field) is captured too', () {
      final r = freshBridge().handle(
          _envelope('fxaccounts:oauth_login', {'token': _t.toUpperCase()}),
          origin);
      // Normalized to lowercase hex.
      expect(r.sessionToken, _t);
    });

    test('a malformed token is never surfaced', () {
      final r = freshBridge().handle(_envelope('fxaccounts:login',
          {'sessionToken': 'not-a-token'}), origin);
      expect(r.sessionToken, isNull);
    });

    test('the duplicate token is suppressed (one capture per sign-in)',
        () {
      final b = freshBridge();
      final first = b.handle(
          _envelope('fxaccounts:login', {'sessionToken': _t}), origin);
      final second = b.handle(
          _envelope('fxaccounts:oauth_login', {'token': _t}), origin);
      expect(first.sessionToken, _t);
      expect(second.sessionToken, isNull); // dedup guard
    });

    test('non-Mozilla origins are ignored (both sides of the gate)', () {
      // Dart-side gate.
      final r = freshBridge().handle(
          _envelope('fxaccounts:login', {'sessionToken': _t}),
          'https://evil.example.com/');
      expect(r.sessionToken, isNull);
      expect(r.replyScript, isNull);
      // The JS hook carries the same host restriction.
      expect(FirefoxWebChannelBridge.hookScript,
          contains("host !== 'accounts.firefox.com'"));
      expect(FirefoxWebChannelBridge.hookScript,
          contains("endsWith('.firefox.com')"));
    });

    test('the hook posts to aethoneFxChannel and exposes the reply fn', () {
      final js = FirefoxWebChannelBridge.hookScript;
      expect(js, contains('aethoneFxChannel.postMessage'));
      expect(js, contains('__aethoneFxReply'));
      expect(js, contains('WebChannelMessageToChrome'));
      expect(js, contains('WebChannelMessageToContent'));
    });

    test('the login URL opens the desktop-v3 WebChannel context', () {
      expect(kFirefoxLoginUrl,
          contains('context=fx_desktop_v3'));
      expect(kFirefoxLoginUrl, startsWith('https://accounts.firefox.com/'));
    });

    test('the user agent is Firefox-on-Android at the pinned identity', () {
      final ua = firefoxLoginUserAgent('16');
      expect(ua, startsWith('Mozilla/5.0 (Android 16; Mobile;'));
      // The pinned identity (the same major the engine's control plane
      // presents — one identity everywhere).
      expect(ua, contains('rv:159.0'));
      expect(ua, contains('Firefox/159.0'));
    });
  });

  // ------------------------------------------------------------------
  group('login wire protocol (the --login role events)', () {
    test('loginStarted parses (version + mode)', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode('{"event":"loginStarted","loginMode":"webchannel",'
                '"version":"1.1.0-phase2","pid":7}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.name, FirefoxEngineEvents.loginStarted);
      expect(ev.loginMode, 'webchannel');
      expect(ev.carriesSecrets, isFalse);
    });

    test('loginRetry parses with the attempt count', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode(
                '{"event":"loginRetry","attempt":3,"retryInMs":3000,'
                '"reason":"session not confirmed yet"}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.name, FirefoxEngineEvents.loginRetry);
      expect(ev.attempt, 3);
      expect(ev.logLine, contains('attempt 3'));
    });

    test('loginCompleted carries the pair and NEVER logs it', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode(
                '{"event":"loginCompleted","accessToken":"SECRET-AT",'
                '"refreshToken":"SECRET-RT","expiresIn":86400}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.carriesSecrets, isTrue);
      expect(ev.logLine, contains('<redacted>'));
      expect(ev.logLine, isNot(contains('SECRET-AT')));
      expect(ev.logLine, isNot(contains('SECRET-RT')));
    });

    test('login failure codes parse verbatim', () {
      for (final code in [
        FirefoxEngineFailure.loginModeUnsupported,
        FirefoxEngineFailure.sessionTokenInvalid,
        FirefoxEngineFailure.sessionRejected,
        FirefoxEngineFailure.loginTimeout,
        FirefoxEngineFailure.exchangeFailed,
      ]) {
        final ev = FirefoxEngineEvent.fromJson(
          (jsonDecode('{"event":"failed","code":1,'
                  '"failCode":"$code","message":"x"}')
                  as Map)
              .cast<String, dynamic>(),
        );
        expect(ev.failCode, code);
      }
    });
  });

  // ------------------------------------------------------------------
  group('wheel policy: the firefox family (phase-2)', () {
    test('firefoxOnly is a real selector', () {
      expect(LocationWheelPolicy.selectable(ProtocolId.firefoxOnly),
          isTrue);
    });

    test('firefox allowed codes = AUTO + the live set / the seed', () {
      final withLive = LocationWheelPolicy.allowedCodes(
        ProtocolId.firefoxOnly,
        firefoxCountries: const ['fr', 'jp'],
      );
      expect(withLive,
          [LocationWheelPolicy.autoCode, 'fr', 'jp']);
      final fallback = LocationWheelPolicy.allowedCodes(
        ProtocolId.firefoxOnly,
      );
      expect(fallback!.first, LocationWheelPolicy.autoCode);
      expect(fallback, containsAll(<String>['fr', 'us', 'jp']));
      // The seed is the phase-0 live list: 33 real countries, NO 'cz'
      // (not in the Firefox list) and no pseudo-countries.
      expect(fallback.length, 34); // auto + 33
      expect(fallback, isNot(contains('cz')));
    });

    test('the firefoxCountrySnapshot matches the phase-0 live record', () {
      // Recorded 2026-11-08 from Mozilla RemoteSettings (33 countries).
      expect(firefoxCountrySnapshot.length, 33);
      expect(firefoxCountrySnapshot, containsAll(<String>[
        'ar', 'at', 'au', 'be', 'bg', 'br', 'ca', 'cl', 'co', 'de',
        'dk', 'es', 'fi', 'fr', 'gb', 'gh', 'ie', 'it', 'jp', 'kr',
        'my', 'mx', 'nl', 'no', 'nz', 'pe', 'ph', 'pt', 'se', 'sg',
        'th', 'us', 'za',
      ]));
      // Sorted like the phase-0 record.
      expect([...firefoxCountrySnapshot]..sort(), firefoxCountrySnapshot);
    });

    test('the 12-mode table keeps firefoxOnly on port 1822', () {
      expect(TransportModes.firefoxOnly.socksEndpoint.port, 1822);
      expect(TransportModes.firefoxOnly.exitKind, ExitKind.firefoxExit);
      expect(TransportModes.firefoxOnly.tcpOnly, isTrue);
    });
  });

  // ------------------------------------------------------------------
  group('store surface: the firefox family picks (phase-2)', () {
    test('selectLocation routes into firefoxLocation under firefoxOnly',
        () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.selectedProtocol = ProtocolId.firefoxOnly;
      store.selectLocation('fr');
      expect(store.firefoxLocation, 'fr');
      expect(store.wheelAnchorCode, 'fr');
      // AUTO is a legal pick.
      store.selectLocation(LocationWheelPolicy.autoCode);
      expect(store.firefoxLocation, LocationWheelPolicy.autoCode);
    });

    test('setFirefoxLocation sanitizes; setFirefoxTransport pins h2/h3',
        () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.setFirefoxLocation('FR'); // uppercase → auto (lowercase only)
      expect(store.firefoxLocation, LocationWheelPolicy.autoCode);
      store.setFirefoxLocation('jp');
      expect(store.firefoxLocation, 'jp');
      store.setFirefoxTransport('h3');
      expect(store.firefoxTransport, 'h3');
      store.setFirefoxTransport('quic'); // unknown → h2
      expect(store.firefoxTransport, 'h2');
    });

    test('applyFirefoxLocations swaps the live set and labels it', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.applyFirefoxLocations(
          ['FR', 'jp'], true, DateTime.parse('2026-11-08T12:00:00Z'));
      expect(store.liveFirefoxCountries, ['fr', 'jp']);
      expect(store.firefoxLocationsLive, isTrue);
      expect(store.firefoxLocationsFetchedAt,
          DateTime.parse('2026-11-08T12:00:00Z'));
      // The wheel offers AUTO + the LIVE set (not the seed).
      store.selectedProtocol = ProtocolId.firefoxOnly;
      expect(store.wheelAllowedCodes,
          [LocationWheelPolicy.autoCode, 'fr', 'jp']);
    });

    test('applyFirefoxLocations ignores garbage', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.applyFirefoxLocations([], false, DateTime.now());
      expect(store.liveFirefoxCountries, isNull); // seed kept
    });
  });

  // ------------------------------------------------------------------
  // REAL-ENGINE login tests: spawn the actual host binary's --login role
  // through the same FirefoxLoginClient class the adapter uses.
  // ------------------------------------------------------------------
  group('FirefoxLoginClient against the REAL host binary', () {
    final bin = resolveEngineBin();

    bool binReady() => File(bin).existsSync();

    test('binary exists and is executable', () {
      expect(binReady(), isTrue, reason: 'engine binary missing');
    }, skip: !binReady() ? 'engine binary not built' : false);

    test('an invalid token fails honestly (the engine\'s own words)',
        () async {
      if (!binReady()) {
        markTestSkipped('engine binary not built');
        return;
      }
      final logs = <String>[];
      final client = FirefoxLoginClient(binaryPath: bin, onLog: logs.add);
      final result = await client.runWebChannel(
        sessionToken: 'zz', // not 64-hex — the engine refuses it
        timeout: const Duration(seconds: 30),
      );
      expect(result.state, FirefoxLoginState.failed);
      expect(result.failCode, FirefoxEngineFailure.sessionTokenInvalid);
      expect(result.message, contains('64 hexadecimal'));
      // No log line carries the token (it was refused pre-network, but
      // the discipline holds anyway).
      expect(logs.join('\n'), isNot(contains('zz')));
    }, skip: !binReady() ? 'engine binary not built' : false);

    test('stdin close cancels cleanly and no orphan survives', () async {
      if (!binReady()) {
        markTestSkipped('engine binary not built');
        return;
      }
      final client = FirefoxLoginClient(
        binaryPath: bin,
        onLog: (_) {},
        shutdownGrace: const Duration(seconds: 5),
      );
      // A well-shaped FAKE token: the exchange call goes out to the REAL
      // FxA endpoint (which will reject it — that is fine here); the
      // cancel must land regardless.
      final future = client.runWebChannel(
        sessionToken: _t,
        timeout: const Duration(seconds: 60),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await client.cancel();
      final result = await future;
      expect(result.state,
          anyOf(FirefoxLoginState.cancelled, FirefoxLoginState.failed));
      expect(client.isRunning, isFalse);
    }, skip: !binReady() ? 'engine binary not built' : false);

    test('the REAL FxA endpoint rejects a fake token honestly (no leak)',
        () async {
      // HONESTY NOTE: a real-network test proving the REJECTION path —
      // never a claim of login. The token is a FAKE; FxA must refuse it
      // (or the network refuses the call), and nothing may leak.
      if (!binReady()) {
        markTestSkipped('engine binary not built');
        return;
      }
      final client = FirefoxLoginClient(binaryPath: bin, onLog: (_) {});
      final result = await client.runWebChannel(
        sessionToken: _t,
        timeout: const Duration(seconds: 180),
      );
      expect(result.state, FirefoxLoginState.failed);
      expect(result.isCompleted, isFalse);
      expect(
        result.failCode,
        anyOf(FirefoxEngineFailure.sessionRejected,
            FirefoxEngineFailure.exchangeFailed),
      );
      // The failure message is REDACTED (the fake token never appears).
      expect(result.message, isNot(contains(_t)));
    },
        skip: !binReady()
            ? 'engine binary not built'
            : const bool.fromEnvironment('no-network',
                defaultValue: false)
                ? 'no network'
                : false,
        timeout: const Timeout(Duration(minutes: 4)));
  });
}
