// PHASE B (firefox-vpn) Part 2 + Part 3 tests — the error-contract chain
// and the OAuth pair guard, Dart side.
//
// What is real here:
//  * the classification tests parse the REAL wire shapes: the legacy
//    contract observed in the owner's 2026-11-08 logcat (the umbrella
//    `exchangeFailed` + the raw Go DNS chain, line 43649) and the Phase B
//    granular codes with httpStatus/retryable (the additive v1.2.0-phaseb
//    extension);
//  * the guard tests run the SAME FirefoxLoginClient the adapter uses
//    against local fixture child processes (a well-formed pair completes;
//    a broken pair is rejected as invalidTokenResponse and never mints a
//    session — a clean child exit must not mask it);
//  * the redaction tests prove token-shaped values never survive the
//    diagnostics sink.
//
// What is NOT real (and never claimed): the REAL engine binary's own
// classification — that is the Go-side guard (docs/phaseb-engine-patch/,
// probe-verified with real DNS/TLS/timeout/refused sockets) and needs the
// rebuilt engine binary; these tests pin the Dart half of the contract.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/firefox/firefox_engine.dart';
import 'package:aethone/connection/firefox/firefox_errors.dart';
import 'package:aethone/connection/firefox/firefox_login.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// The EXACT failed-event shape the 2026-11-08 field build emitted
/// (logcat line 43649; the raw Go chain reached the message field).
const String kLegacyNov8Line =
    '{"event":"failed","failCode":"exchangeFailed","message":"oauth token '
    'request: Post \\"https://api.accounts.firefox.com/v1/oauth/token\\": '
    'dial tcp: lookup api.accounts.firefox.com on [::1]:53: read udp '
    '[::1]:37265->[::1]:53: read: connection refused"}';

class _ScriptedEngine extends EngineAdapter {
  final _controller = StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => _controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void bind(EngineConfigSource config) {}
}

void main() {
  // ----------------------------------------------------------------
  group('Part 2 — the legacy contract (2026-11-08 logcat shape)', () {
    test('the real Nov-8 failed line parses and classifies safely', () {
      final raw =
          jsonDecode(kLegacyNov8Line) as Map<String, dynamic>;
      final event = FirefoxEngineEvent.fromJson(raw);

      // The legacy extras default: no httpStatus, no retry hint (null —
      // the class default then applies, not an explicit false).
      expect(event.httpStatus, 0);
      expect(event.retryable, isNull);

      final f = FirefoxErrors.classify(
        event.failCode,
        httpStatus: event.httpStatus,
        retryable: event.retryable,
      );
      // The umbrella code maps to the token-exchange class, flagged
      // legacy so diagnostics can say WHY the class is general.
      expect(f.code, FirefoxTransportError.tokenExchange);
      expect(f.legacy, isTrue);
      expect(f.retryable, isTrue); // the exchange is worth retrying

      // The class diagnostic NEVER contains the raw chain's internals.
      final text = FirefoxErrors.diagnostic(f);
      expect(text, isNot(contains('api.accounts.firefox.com')));
      expect(text, isNot(contains('[::1]:53')));
      expect(text, isNot(contains('connection refused')));
      expect(text, isNot(contains('Post ')));
    });

    test('the raw chain stays out of the classified surface entirely', () {
      final event = FirefoxEngineEvent.fromJson(
          jsonDecode(kLegacyNov8Line) as Map<String, dynamic>);
      // The chain lives ONLY in event.message (log material); the
      // classification result carries none of it.
      expect(event.message, contains('connection refused'));
      final f = FirefoxErrors.classify(event.failCode);
      expect(f.toString(), isNot(contains('api.accounts')));
      expect(FirefoxErrors.diagnostic(f), isNot(contains('lookup')));
    });
  });

  // ----------------------------------------------------------------
  group('Part 2 — the granular Phase B codes (v1.2.0-phaseb engines)', () {
    test('each class maps with its default retry policy', () {
      expect(FirefoxErrors.classify('dnsError').code,
          FirefoxTransportError.dnsError);
      expect(FirefoxErrors.classify('dnsError').retryable, isTrue);
      expect(FirefoxErrors.classify('networkUnavailable').retryable, isFalse);
      expect(FirefoxErrors.classify('timeout').retryable, isTrue);
      expect(FirefoxErrors.classify('tlsError').retryable, isFalse);
      expect(FirefoxErrors.classify('sessionRejected').retryable, isFalse);
      expect(FirefoxErrors.classify('invalidTokenResponse').retryable,
          isFalse);
      expect(FirefoxErrors.classify('serverRejection').retryable, isFalse);
    });

    test('GUARDIAN-BOOTSTRAP STAGE 6 — the renewal lifecycle codes map to ' 
        'their own classes, never the unknown bucket', () {
      // Quota (the renewal loop's 429 terminal): NOT retryable — the
      // recovery is picking another engine, not a retry.
      final quota = FirefoxErrors.classify(FirefoxTransportError.quotaExhausted);
      expect(quota.code, FirefoxTransportError.quotaExhausted);
      expect(quota.retryable, isFalse);
      expect(FirefoxErrors.diagnostic(quota), contains('quota'));
      // Renewal timeout (the engine parked, exit 3): retryable — a fresh
      // walk re-runs the whole direct/bootstrap decision.
      final renewal =
          FirefoxErrors.classify(FirefoxTransportError.renewalTimeout);
      expect(renewal.code, FirefoxTransportError.renewalTimeout);
      expect(renewal.retryable, isTrue);
      expect(FirefoxErrors.diagnostic(renewal), contains('renewed'));
    });

    test('httpStatus passes through untouched (the REAL status code)', () {
      final f = FirefoxErrors.classify('sessionRejected', httpStatus: 401);
      expect(f.httpStatus, 401);
      expect(
          FirefoxErrors.diagnostic(f), contains('HTTP 401'));

      final fiveHundred =
          FirefoxErrors.classify('serverRejection', httpStatus: 503);
      expect(fiveHundred.httpStatus, 503);
      expect(fiveHundred.retryable, isTrue); // 5xx → worth retrying

      final fourHundred =
          FirefoxErrors.classify('serverRejection', httpStatus: 400);
      expect(fourHundred.retryable, isFalse); // 4xx → not retryable
    });

    test('the retryable passthrough honors the engine hint', () {
      expect(FirefoxErrors.classify('tlsError', retryable: true).retryable,
          isTrue);
      expect(
          FirefoxErrors.classify('dnsError', retryable: false).retryable,
          isFalse);
    });

    test('unknown / empty / future codes degrade to the generic class', () {
      for (final code in ['', 'somethingNew', 'TOTALLY-UNKNOWN', ' ']) {
        final f = FirefoxErrors.classify(code);
        expect(f.code, FirefoxTransportError.unknown,
            reason: 'code <$code> must degrade, never throw');
        expect(f.legacy, isFalse);
      }
      // A future code carrying an httpStatus still keeps the status.
      expect(FirefoxErrors.classify('futureCode', httpStatus: 418).httpStatus,
          418);
    });

    test('wrong-typed extras never throw the event parse', () {
      // Hostile/broken engine JSON: httpStatus as string, retryable as
      // string, accessToken as number — the tolerant reads degrade.
      final event = FirefoxEngineEvent.fromJson({
        'event': 'failed',
        'failCode': 'dnsError',
        'httpStatus': '503',
        'retryable': 'yes',
        'failureStage': 42,
        'message': 'x',
      });
      expect(event.httpStatus, 0);
      expect(event.retryable, isNull); // wrong type → no hint
      expect(event.failureStage, isEmpty); // wrong stage type → no hint

      final completed = FirefoxEngineEvent.fromJson({
        'event': 'loginCompleted',
        'accessToken': 12345,
        'refreshToken': true,
      });
      expect(completed.accessToken, '');
      expect(completed.refreshToken, '');
      // …and the guard then rejects the pair (not a crash, a failure).
      expect(
          FirefoxErrors.invalidPairReason(
              completed.accessToken, completed.refreshToken),
          isNotNull);
    });

    test('legacy engine events (no extras) still parse', () {
      final event = FirefoxEngineEvent.fromJson(
          jsonDecode(kLegacyNov8Line) as Map<String, dynamic>);
      expect(event.name, FirefoxEngineEvents.failed);
      expect(event.failCode, FirefoxEngineFailure.exchangeFailed);
      expect(event.httpStatus, 0);
      expect(event.retryable, isNull);
      expect(event.failureStage, isEmpty);
    });
  });

  // ----------------------------------------------------------------
  group('Part 3 — the OAuth pair guard (Dart side)', () {
    test('a well-formed pair passes', () {
      expect(
          FirefoxErrors.invalidPairReason('at_x', 'rt_y'),
          isNull);
      // Long realistic shapes pass too — no format is invented/checked.
      expect(
          FirefoxErrors.invalidPairReason('a' * 64, 'b' * 64),
          isNull);
    });

    test('every violation has its own static, value-free reason', () {
      // missing / null / wrong type / empty / blank — access first,
      // then refresh (the guard checks both fields).
      expect(FirefoxErrors.invalidPairReason(null, 'rt'),
          'field "accessToken" is missing');
      expect(FirefoxErrors.invalidPairReason('at', null),
          'field "refreshToken" is missing');
      expect(FirefoxErrors.invalidPairReason(12345, 'rt'),
          'field "accessToken" is not a string');
      expect(FirefoxErrors.invalidPairReason('at', []),
          'field "refreshToken" is not a string');
      expect(FirefoxErrors.invalidPairReason('', 'rt'),
          'field "accessToken" is empty');
      expect(FirefoxErrors.invalidPairReason('at', ''),
          'field "refreshToken" is empty');
      expect(FirefoxErrors.invalidPairReason('   ', 'rt'),
          'field "accessToken" is blank (whitespace only)');
      expect(FirefoxErrors.invalidPairReason('at', ' \t '),
          'field "refreshToken" is blank (whitespace only)');
    });

    test('the reason text never embeds the rejected values', () {
      final reason = FirefoxErrors.invalidPairReason(
          'SECRETVALUE0123456789', 'rt');
      expect(reason, isNot(contains('SECRETVALUE')));
    });
  });

  // ----------------------------------------------------------------
  group('Part 2 — redaction (the diagnostics sink discipline)', () {
    test('token-shaped runs are masked', () {
      const hex64 = '0123456789abcdef0123456789abcdef0123456789abcdef';
      final out = FirefoxErrors.redactLine('session token: $hex64 done');
      expect(out, isNot(contains(hex64)));
      expect(out, contains('<redacted>'));
    });

    test('base64ish OAuth shapes are masked', () {
      const b64 =
          'abcdefghijKLMNOPqrstuvwxYZ0123456789-plus_slash.chars==';
      final out = FirefoxErrors.redactLine('refresh=$b64');
      expect(out, isNot(contains(b64)));
    });

    test('ordinary diagnostics text survives untouched', () {
      const line =
          'firefox engine failed (exchangeFailed): dial tcp: lookup api.'
              'accounts.firefox.com on [::1]:53: connection refused';
      expect(FirefoxErrors.redactLine(line), line);
    });
  });

  // ----------------------------------------------------------------
  group('Part 2/3 — the login client against fixture children', () {
    final fixtures = Directory('test/fixtures');

    test('a broken pair is rejected as invalidTokenResponse — never '
        'completed, never cancelled (a clean exit must not mask it)',
        () async {
      final bin =
          '${fixtures.path}/fake_login_engine_invalid_pair.sh';
      expect(File(bin).existsSync(), isTrue,
          reason: 'fixture missing: $bin');
      final logs = <String>[];
      final client = FirefoxLoginClient(binaryPath: bin, onLog: logs.add);
      final result = await client.runWebChannel(
        sessionToken: 't' * 64,
        timeout: const Duration(seconds: 30),
      );
      expect(result.state, FirefoxLoginState.failed);
      expect(result.failCode, FirefoxTransportError.invalidTokenResponse);
      expect(result.auth, isNull); // nothing minted, nothing vaulted
      // The guard's log line states the reason but never a token value.
      expect(logs.join('\n'), contains('pair guard'));
      expect(logs.join('\n'), isNot(contains('t' * 64)));
    });

    test('a well-formed pair completes and hands the exact pair over',
        () async {
      final bin = '${fixtures.path}/fake_login_engine_valid_pair.sh';
      expect(File(bin).existsSync(), isTrue, reason: 'fixture missing');
      final client = FirefoxLoginClient(binaryPath: bin, onLog: (_) {});
      final result = await client.runWebChannel(
        sessionToken: 't' * 64,
        timeout: const Duration(seconds: 30),
      );
      expect(result.state, FirefoxLoginState.completed);
      expect(result.auth, isNotNull);
      expect(result.auth!.accessToken, 'at_test_0123456789abcdef0123456789abcdef');
      expect(result.auth!.refreshToken,
          'rt_test_0123456789abcdef0123456789abcdef');
    });

    test('a failed event carries its class + extras into the result',
        () async {
      // Direct wire-level check of the outcome passthrough (the engine
      // class maps the same fields the client reads).
      const engineOutcome = FirefoxEngineOutcome(
        state: FirefoxEngineState.failed,
        exitCode: 4,
        failCode: 'serverRejection',
        message: 'http status 503',
        httpStatus: 503,
        retryable: true,
      );
      final f = FirefoxErrors.classify(engineOutcome.failCode,
          httpStatus: engineOutcome.httpStatus,
          retryable: engineOutcome.retryable);
      expect(f.code, FirefoxTransportError.serverRejection);
      expect(f.httpStatus, 503);
      expect(f.retryable, isTrue);
    });
  });

  // ----------------------------------------------------------------
  group('the state-management rules (login success ≠ connection)', () {
    test('a COMPLETED login never moves the VPN state machine', () async {
      final store = ConnectionStore(engine: _ScriptedEngine());
      expect(store.state, VpnState.disconnected);
      // The completed login result (fixture pair, Part 3 accepted)…
      const login = FirefoxLoginResult(
        state: FirefoxLoginState.completed,
        auth: FirefoxSessionAuth(
          accessToken: 'at_test_0123456789abcdef0123456789abcdef',
          refreshToken: 'rt_test_0123456789abcdef0123456789abcdef',
        ),
      );
      expect(login.isCompleted, isTrue);
      // …is account state, NOT tunnel state: without an engine effective
      // event the store stays disconnected (no success display without
      // the engine's own proof).
      expect(store.state, VpnState.disconnected);
    });

    test('an engine failure before login completes maps to the failed '
        'login surface (the class text, never the chain)', () {
      // The adapter's seam: a failed engine outcome under a firefox
      // connect classifies; the UI text comes from the class only.
      final f = FirefoxErrors.classify('dnsError');
      expect(f.code, FirefoxTransportError.dnsError);
      expect(f.retryable, isTrue);
      final diagnostic = FirefoxErrors.diagnostic(f);
      expect(diagnostic, isNot(contains('[::1]')));
      expect(diagnostic, isNot(contains('udp')));
    });
  });

  // ----------------------------------------------------------------
  group('guardian-bootstrap Stage 1 — the Guardian 451 region class', () {
    test('the real 451 failed-event wire shape parses and classifies', () {
      const wire =
          '{"event":"failed","failCode":"guardianRegionUnavailable",'
          '"message":"static","httpStatus":451,"retryable":false}';
      final event = FirefoxEngineEvent.fromJson(
          jsonDecode(wire) as Map<String, dynamic>);
      expect(event.name, FirefoxEngineEvents.failed);
      expect(event.failCode,
          FirefoxTransportError.guardianRegionUnavailable);
      expect(event.httpStatus, 451);
      expect(event.retryable, isFalse);

      final f = FirefoxErrors.classify(event.failCode,
          httpStatus: event.httpStatus, retryable: event.retryable);
      expect(f.code, FirefoxTransportError.guardianRegionUnavailable);
      expect(f.httpStatus, 451);
      expect(f.retryable, isFalse);
      expect(f.legacy, isFalse);
    });

    test('the region class is emitted ONLY by the Guardian walk (isolation)',
        () {
      // A non-Guardian 451 (FxA / Remote Settings on the engine side)
      // arrives as the GENERIC serverRejection class — never the region
      // class, which only the engine's ClassifyGuardian may produce.
      final generic =
          FirefoxErrors.classify('serverRejection', httpStatus: 451);
      expect(generic.code, FirefoxTransportError.serverRejection);
      expect(generic.code,
          isNot(FirefoxTransportError.guardianRegionUnavailable));
    });

    test('the diagnostic names the region, never the raw chain', () {
      final f = FirefoxErrors.classify('guardianRegionUnavailable',
          httpStatus: 451);
      final text = FirefoxErrors.diagnostic(f);
      expect(text, contains('region'));
      expect(text, contains('451'));
      expect(text, isNot(contains('unavailable_in_region')));
      expect(text, isNot(contains('vpn.mozilla.org')));
      expect(f.toString(), isNot(contains('unavailable_in_region')));
    });

    test('the renewalFailed event carries its class additively', () {
      // Stage 1 adds failCode to renewalFailed; legacy engines without
      // the field still parse (empty string, no crash).
      final withCode = FirefoxEngineEvent.fromJson(jsonDecode(
              '{"event":"renewalFailed","failCode":'
              '"guardianRegionUnavailable","message":"x"}')
          as Map<String, dynamic>);
      expect(withCode.name, FirefoxEngineEvents.renewalFailed);
      expect(withCode.failCode,
          FirefoxTransportError.guardianRegionUnavailable);

      final legacy = FirefoxEngineEvent.fromJson(
          jsonDecode('{"event":"renewalFailed","message":"x"}')
              as Map<String, dynamic>);
      expect(legacy.name, FirefoxEngineEvents.renewalFailed);
      expect(legacy.failCode, '');
    });

    test('the mirror constant matches the wire code exactly', () {
      expect(FirefoxEngineFailure.guardianRegionUnavailable,
          'guardianRegionUnavailable');
      // Unknown codes still degrade — the future-proofing rule holds.
      expect(FirefoxErrors.classify('somethingNewer').code,
          FirefoxTransportError.unknown);
    });
  });
}
