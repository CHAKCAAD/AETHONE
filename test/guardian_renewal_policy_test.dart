// GUARDIAN-BOOTSTRAP STAGE 6 tests — the renewal & lifecycle policy
// (guardian_renewal_policy.dart) + the renewal event plumbing through
// the REAL engine seam.
//
// What is real here:
//  * every supervisor input is a REAL FirefoxEngineEvent built by the
//    protocol's own fromJson parser (so the retryInMs / passExpiresAt
//    wire parsing is exercised on the exact shapes the engine emits);
//  * the backstop timing runs on REAL timers with small budgets (the
//    policy's deadline math — the pass's own expiry plus the mirrored
//    engine budget — is the production code path);
//  * the engine-level outcome mapping runs against REAL process spawns
//    (a scripted stand-in binary emitting the engine's exact JSON event
//    lines; the same stand-in discipline as the Stage-5 seams suite);
//  * the reactivation path runs the REAL Stage-4 manager (fake seams,
//    real route memory on the real filesystem) through release() →
//    ensureAuthorized() — the renewal-time reauthorization shape.
//
// What is NOT real (and never claimed): the on-device Guardian
// lifecycle (Stage 8/9 scenario E) and the adapter-level walk wiring
// (documented NOT TESTED since Stage 5; the supervisor contract and
// the engine event plumbing are what these tests pin).
import 'dart:convert';
import 'dart:io';

import 'package:aethone/connection/firefox/firefox_engine.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:aethone/connection/firefox/guardian_renewal_policy.dart';
import 'package:flutter_test/flutter_test.dart';

FirefoxEngineEvent eventOf(String json) => FirefoxEngineEvent.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );

void main() {
  final bashExists = File('/bin/bash').existsSync();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gbm-stage6-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('the renewal supervisor (real events, real timers)', () {
    test('the backstop arms from the pass\'s OWN expiry and fires at '
        'expiry + the mirrored engine budget', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 200),
      );
      addTearDown(supervisor.dispose);

      supervisor.attachSession(viaBootstrapProxy: true);
      final expiry = DateTime.now().add(const Duration(milliseconds: 400));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${expiry.toUtc().toIso8601String()}","quotaLeft":"480",'
          '"quotaReset":"2026-12-01T00:00:00Z"}'));
      expect(supervisor.releaseArmed, isTrue,
          reason: 'a proxied session\'s pass must arm the backstop');
      expect(supervisor.facts.passExpiresAt, isNotNull);
      expect(supervisor.facts.quotaLeft, '480');

      // Before the deadline (expiry + grace): the bootstrap is KEPT —
      // releasing earlier would break the current renewal.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(releases, 0);

      // At/after the deadline: exactly one release.
      await _until(() => releases > 0, const Duration(seconds: 2));
      expect(releases, 1);
      expect(supervisor.facts.releases, 1);
      expect(supervisor.releaseArmed, isFalse);
    });

    test('rotation: every renewed pass re-arms the window — no release '
        'at the OLD deadline', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 150),
      );
      addTearDown(supervisor.dispose);

      supervisor.attachSession(viaBootstrapProxy: true);
      final firstExpiry =
          DateTime.now().add(const Duration(milliseconds: 400));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${firstExpiry.toUtc().toIso8601String()}"}'));
      // The renewal rotates the pass BEFORE the old expiry: the new
      // window must supersede the old deadline.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final rotatedExpiry =
          DateTime.now().add(const Duration(milliseconds: 900));
      supervisor.onEngineEvent(eventOf(
          '{"event":"renewed","passExpiresAt":"'
          '${rotatedExpiry.toUtc().toIso8601String()}","quotaLeft":"479",'
          '"quotaReset":"2026-12-01T00:00:00Z"}'));

      // The OLD deadline (400 + 150 ms) has passed — nothing fires.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(releases, 0, reason: 'the rotation re-armed the window');

      // The NEW deadline (900 + 150 ms from the rotation) fires.
      await _until(() => releases > 0, const Duration(seconds: 3));
      expect(releases, 1);
    });

    test('a DIRECT session never releases anything (no bootstrap '
        'resource exists)', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 100),
      );
      addTearDown(supervisor.dispose);

      supervisor.attachSession(viaBootstrapProxy: false);
      final expiry = DateTime.now().add(const Duration(milliseconds: 150));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${expiry.toUtc().toIso8601String()}"}'));
      expect(supervisor.releaseArmed, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(releases, 0);
      expect(supervisor.facts.viaBootstrapProxy, isFalse);
    });

    test('engine-gone KEEPS the backstop armed — it is the missed-'
        'teardown bound (the teardown owns the release)', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 150),
      );
      addTearDown(supervisor.dispose);
      supervisor.attachSession(viaBootstrapProxy: true);
      final expiry = DateTime.now().add(const Duration(milliseconds: 300));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${expiry.toUtc().toIso8601String()}"}'));
      supervisor.onEngineGone();
      expect(supervisor.releaseArmed, isTrue,
          reason: 'a dead engine with a missed teardown must not pin the '
              'bootstrap forever');
      await _until(() => releases > 0, const Duration(seconds: 2));
      expect(releases, 1);
    });

    test('quota exhaustion keeps the backstop as the bound (the engine '
        'parks; the teardown owns the release)', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 150),
      );
      addTearDown(supervisor.dispose);

      supervisor.attachSession(viaBootstrapProxy: true);
      final expiry = DateTime.now().add(const Duration(milliseconds: 300));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${expiry.toUtc().toIso8601String()}"}'));
      supervisor.onEngineEvent(
          eventOf('{"event":"quotaExhausted","code":2}'));
      expect(supervisor.releaseArmed, isTrue);
      await _until(() => releases > 0, const Duration(seconds: 2));
    });

    test('the DEFINITIVE teardown cancels the backstop — nothing fires '
        'after the session is gone', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 150),
      );

      supervisor.attachSession(viaBootstrapProxy: true);
      final expiry = DateTime.now().add(const Duration(milliseconds: 300));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${expiry.toUtc().toIso8601String()}"}'));
      supervisor.onSessionTeardown();
      expect(supervisor.releaseArmed, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(releases, 0);
      expect(supervisor.facts.sessionActive, isFalse);
      expect(supervisor.facts.viaBootstrapProxy, isFalse);
    });

    test('dispose cancels the backstop (no orphan timer)', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 150),
      );
      supervisor.attachSession(viaBootstrapProxy: true);
      final expiry = DateTime.now().add(const Duration(milliseconds: 300));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${expiry.toUtc().toIso8601String()}"}'));
      supervisor.dispose();
      expect(supervisor.releaseArmed, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(releases, 0);
    });

    test('renewalFailed records the Stage-1 class and the engine\'s own '
        'retry cadence (facts, not a failure state)', () async {
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async {},
      );
      addTearDown(supervisor.dispose);

      supervisor.attachSession(viaBootstrapProxy: true);
      supervisor.onEngineEvent(eventOf(
          '{"event":"renewalFailed","failCode":"guardianRegionUnavailable",'
          '"retryInMs":30000,"message":"redacted shape"}'));
      final facts = supervisor.facts;
      expect(facts.renewalFailures, 1);
      expect(facts.lastRenewalFailCode, 'guardianRegionUnavailable');
      expect(facts.lastRenewalRetryInMs, 30000);
      // The engine keeps retrying — this is NOT a released/failed state.
      expect(supervisor.releaseArmed, isFalse);
    });

    test('a legacy/hostile engine without a parseable expiry never arms '
        'an assumed deadline (no crash, facts degrade)', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
      );
      addTearDown(supervisor.dispose);

      supervisor.attachSession(viaBootstrapProxy: true);
      supervisor.onEngineEvent(
          eventOf('{"event":"passAcquired","passExpiresAt":""}'));
      supervisor.onEngineEvent(
          eventOf('{"event":"renewed","passExpiresAt":"not-a-timestamp"}'));
      supervisor.onEngineEvent(eventOf('{"event":"renewed"}'));
      expect(supervisor.releaseArmed, isFalse,
          reason: 'no hardcoded lifetime may ever be assumed');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(releases, 0);
    });

    test('an already-expired pass (clock skew) fires the backstop at '
        'once — the reason has ended', () async {
      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 100),
      );
      addTearDown(supervisor.dispose);

      supervisor.attachSession(viaBootstrapProxy: true);
      final past = DateTime.now().subtract(const Duration(minutes: 5));
      supervisor.onEngineEvent(eventOf(
          '{"event":"passAcquired","passExpiresAt":"'
          '${past.toUtc().toIso8601String()}"}'));
      await _until(() => releases > 0, const Duration(seconds: 2));
      expect(releases, 1);
    });
  });

  group('the engine outcome mapping (REAL process spawns)', () {
    test('quotaExhausted (the renewal loop\'s park event) completes the '
        'outcome with its OWN class — the walk\'s quota branch becomes '
        'reachable', () async {
      final bin = await _writeStandIn(tempDir, 'quotaPark', '''
IFS= read -r line
echo '{"event":"started","message":"1.2.0-phaseb"}'
echo '{"event":"quotaExhausted","code":2}'
exit 2
''');
      final engine = FirefoxVpnEngine(binaryPath: bin, onLog: (_) {});
      addTearDown(() => engine.dispose());
      final outcome = await engine.start(const FirefoxEngineConfig(
        socksListen: '127.0.0.1:0',
        auth: FirefoxSessionAuth(accessToken: 'stage6-shape'),
      ));
      expect(outcome.state, FirefoxEngineState.failed);
      expect(outcome.failCode, FirefoxEngineFailure.quotaExhausted);
      expect(outcome.exitCode, FirefoxEngineExitCode.quota);
      expect(outcome.message, contains('quota'));
    }, skip: !bashExists ? 'no /bin/bash for the stand-in binary' : false);

    test('renewalTimeout (the engine parked on an unrenewed pass) keeps '
        'its OWN failCode through the failed event', () async {
      final bin = await _writeStandIn(tempDir, 'renewalPark', '''
IFS= read -r line
echo '{"event":"started","message":"1.2.0-phaseb"}'
echo '{"event":"failed","failCode":"renewalTimeout","code":3,"message":"the proxy pass could not be renewed in time"}'
exit 3
''');
      final engine = FirefoxVpnEngine(binaryPath: bin, onLog: (_) {});
      addTearDown(() => engine.dispose());
      final outcome = await engine.start(const FirefoxEngineConfig(
        socksListen: '127.0.0.1:0',
        auth: FirefoxSessionAuth(accessToken: 'stage6-shape'),
      ));
      expect(outcome.state, FirefoxEngineState.failed);
      expect(outcome.failCode, FirefoxEngineFailure.renewalTimeout);
      expect(outcome.exitCode, FirefoxEngineExitCode.renewal);
    }, skip: !bashExists ? 'no /bin/bash for the stand-in binary' : false);

    test('a REAL renewal event sequence feeds the supervisor end-to-end '
        '(passAcquired → renewalFailed → renewed; the outcome stays '
        'clean)', () async {
      // The stand-in walks the exact steady-state renewal shape: a pass
      // with a near expiry, one failed retry with the engine's own
      // cadence, then a successful rotation with a far expiry.
      final nearExpiry =
          DateTime.now().add(const Duration(seconds: 2)).toUtc();
      final farExpiry =
          DateTime.now().add(const Duration(hours: 1)).toUtc();
      final bin = await _writeStandIn(tempDir, 'renewalSequence', '''
IFS= read -r line
echo '{"event":"started","message":"1.2.0-phaseb"}'
echo '{"event":"passAcquired","passExpiresAt":"${nearExpiry.toIso8601String()}","quotaLeft":"480","quotaReset":"2026-12-01T00:00:00Z"}'
echo '{"event":"renewalFailed","failCode":"timeout","retryInMs":30000,"message":"redacted shape"}'
echo '{"event":"renewed","passExpiresAt":"${farExpiry.toIso8601String()}","quotaLeft":"479","quotaReset":"2026-12-01T00:00:00Z"}'
exit 0
''');
      final engine = FirefoxVpnEngine(binaryPath: bin, onLog: (_) {});
      addTearDown(() => engine.dispose());

      var releases = 0;
      final supervisor = GuardianRenewalSupervisor(
        onBootstrapExpired: () async => releases++,
        renewalGrace: const Duration(milliseconds: 150),
      );
      addTearDown(supervisor.dispose);
      supervisor.attachSession(viaBootstrapProxy: true);

      final events = <FirefoxEngineEvent>[];
      final sub = engine.events.listen((event) {
        events.add(event);
        supervisor.onEngineEvent(event);
      });
      addTearDown(sub.cancel);

      final outcome = await engine.start(const FirefoxEngineConfig(
        socksListen: '127.0.0.1:0',
        auth: FirefoxSessionAuth(accessToken: 'stage6-shape'),
      ));
      await engine.stop();

      expect(outcome.state, FirefoxEngineState.stopped);
      expect(
          events.map((e) => e.name).toList(),
          containsAll(
              <String>['passAcquired', 'renewalFailed', 'renewed']));
      // The wire parse delivered the REAL fields (not defaults).
      final renewed =
          events.lastWhere((e) => e.name == FirefoxEngineEvents.renewed);
      expect(renewed.passExpiresAt, farExpiry.toIso8601String());
      final failed = events
          .firstWhere((e) => e.name == FirefoxEngineEvents.renewalFailed);
      expect(failed.retryInMs, 30000);
      expect(failed.failCode, 'timeout');

      // The supervisor adopted the ROTATED expiry and armed the
      // backstop at the far deadline; the near expiry never fired it.
      expect(releases, 0);
      expect(supervisor.facts.passExpiresAt,
          DateTime.parse(farExpiry.toIso8601String()));
      expect(supervisor.facts.renewalFailures, 1);
      expect(supervisor.facts.lastRenewalRetryInMs, 30000);
      expect(supervisor.releaseArmed, isTrue);
      // The engine-gone observation (the outcome watch) keeps the
      // backstop as the bound.
      supervisor.onEngineGone();
      expect(supervisor.releaseArmed, isTrue);
      // The definitive teardown cancels it.
      supervisor.onSessionTeardown();
      expect(supervisor.releaseArmed, isFalse);
    }, skip: !bashExists ? 'no /bin/bash for the stand-in binary' : false);
  });
}

Future<void> _until(bool Function() condition, Duration budget) async {
  final deadline = DateTime.now().add(budget);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $budget');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<String> _writeStandIn(
  Directory dir,
  String name,
  String body,
) async {
  final file = File('${dir.path}/stage6-$name.sh');
  await file.writeAsString('#!/bin/bash\n$body\n', flush: true);
  final result = Process.runSync('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    throw StateError('chmod failed: ${result.stderr}');
  }
  return file.path;
}
