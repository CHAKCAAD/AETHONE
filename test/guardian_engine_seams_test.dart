// GUARDIAN-BOOTSTRAP STAGE 5 tests — the REAL engine seams
// (guardian_engine_seams.dart): the direct attempt and the
// through-the-proxy authorization run the engine binary's
// `--guardian-probe` role through the SAME stdin-config/stdout-events
// contract the production walk uses.
//
// What is real here:
//  * REAL process spawns (a scripted stand-in binary standing in for
//    libfirefoxvpn.so — it reads the ONE config line from stdin and
//    emits the engine's exact JSON event lines; the seam cannot tell
//    the difference);
//  * the full §5-4 sequence with REAL spawns on both sides of the
//    bootstrap: the direct probe returns a REAL classified 451, and
//    the through-the-proxy verification only succeeds when the seam
//    actually put `apiProxy` on the wire (the stand-in's behavior is
//    keyed on that field);
//  * the apiProxy serialization contract (omitted when empty);
//  * the evidence-forwarding seam's one-shot semantics.
//
// The stand-in needs /bin/bash (the suite skips honestly where it is
// absent — the CI runners and this sandbox have it).
import 'dart:io';

import 'package:aethone/connection/firefox/bootstrap_route_memory.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:aethone/connection/firefox/guardian_bootstrap_manager.dart';
import 'package:aethone/connection/firefox/guardian_engine_seams.dart';
import 'package:aethone/connection/firefox/psiphon_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a stand-in engine binary with the given scripted behavior
/// and returns its executable path.
Future<String> writeProbeBinary(
  Directory dir,
  String behavior,
) async {
  final behaviors = <String, String>{
    // The REAL region block: started + the Stage-1 class + exit 1.
    '451': '''
IFS= read -r line
echo '{"event":"started","message":"1.2.0-phaseb guardian-probe","pid":'\\''\$\$'\\''}'
echo '{"event":"failed","failCode":"guardianRegionUnavailable","httpStatus":451,"retryable":false,"message":"guardian returned HTTP 451","code":1}'
exit 1
''',
    // A successful authorization: started + passAcquired + clean exit.
    'ok': '''
IFS= read -r line
echo '{"event":"started","message":"1.2.0-phaseb guardian-probe","pid":'\\''\$\$'\\''}'
echo '{"event":"passAcquired","passExpiresAt":"2026-11-11T00:00:00Z","quotaLeft":"498","quotaReset":"2026-12-01T00:00:00Z"}'
exit 0
''',
    // Behavior keyed on the WIRE: 451 without apiProxy, a real
    // authorization WITH it — proving the seam serializes apiProxy.
    'proxyKeyed': '''
IFS= read -r line
echo '{"event":"started","message":"1.2.0-phaseb guardian-probe","pid":'\\''\$\$'\\''}'
if printf '%s' "\$line" | grep -q '"apiProxy":"socks5://'; then
  echo '{"event":"passAcquired","passExpiresAt":"2026-11-11T00:00:00Z","quotaLeft":"497","quotaReset":"2026-12-01T00:00:00Z"}'
  exit 0
fi
echo '{"event":"failed","failCode":"guardianRegionUnavailable","httpStatus":451,"retryable":false,"message":"guardian returned HTTP 451","code":1}'
exit 1
''',
    // Garbage output + a non-zero exit (no failed event at all).
    'garbage': '''
IFS= read -r line
echo 'not json at all'
exit 3
''',
    // Hangs forever — the seam's timeout must stop it (no orphan).
    'hang': '''
IFS= read -r line
sleep 30
exit 0
''',
    // Same-account recovery + success — the refreshed pair must reach
    // the vault callback and never a log.
    'refresh': '''
IFS= read -r line
echo '{"event":"started","message":"1.2.0-phaseb guardian-probe","pid":'\\''\$\$'\\''}'
echo '{"event":"authRefreshed","accessToken":"at-shape-only","refreshToken":"rt-shape-only","expiresIn":3600,"obtainedAt":"2026-11-10T12:00:00Z"}'
echo '{"event":"passAcquired","passExpiresAt":"2026-11-11T00:00:00Z","quotaLeft":"496","quotaReset":"2026-12-01T00:00:00Z"}'
exit 0
''',
  };
  final body = behaviors[behavior]!;
  final file = File('${dir.path}/probe-$behavior.sh');
  await file.writeAsString('#!/bin/bash\n$body\n', flush: true);
  final result = Process.runSync('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    throw StateError('chmod failed: ${result.stderr}');
  }
  return file.path;
}

Future<FirefoxSessionAuth> authOf() async => const FirefoxSessionAuth(
      accessToken: 'probe-access-shape',
      refreshToken: 'probe-refresh-shape',
    );

void main() {
  final bashExists = File('/bin/bash').existsSync();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gbm-stage5-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<EngineGuardianProbe> probeOf(String behavior) async =>
      EngineGuardianProbe(
        binaryPath: await writeProbeBinary(tempDir, behavior),
        authProvider: authOf,
        logLevel: 'quiet',
      );

  group('apiProxy serialization (the engine config contract)', () {
    test('omitted when empty — legacy engines never see the field', () {
      final json = const FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'at', refreshToken: 'rt'),
      ).toJson();
      expect(json.containsKey('apiProxy'), isFalse);
    });

    test('present when set — the exact URL on the wire', () {
      final json = const FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'at', refreshToken: 'rt'),
        apiProxy: 'socks5://127.0.0.1:1999',
      ).toJson();
      expect(json['apiProxy'], 'socks5://127.0.0.1:1999');
    });
  }, skip: !bashExists ? 'no /bin/bash for the stand-in binary' : false);

  group('the engine probe seam (real process spawns)', () {
    test('direct 451 surfaces as the REAL region-unavailable class',
        () async {
      final result = await (await probeOf('451'))
          .probe(timeout: const Duration(seconds: 10));
      expect(result.kind, GuardianProbeKind.regionUnavailable);
      expect(result.failCode, 'guardianRegionUnavailable');
    });

    test('a successful walk reports passAcquired', () async {
      final result = await (await probeOf('ok'))
          .probe(timeout: const Duration(seconds: 10));
      expect(result.kind, GuardianProbeKind.passAcquired);
    });

    test('the apiProxy REALLY rides the wire (behavior keyed on it)',
        () async {
      final probe = await probeOf('proxyKeyed');
      // Without apiProxy: the stand-in answers with the 451 class.
      final direct = await probe.probe(timeout: const Duration(seconds: 10));
      expect(direct.kind, GuardianProbeKind.regionUnavailable);
      // With apiProxy: the stand-in authorizes — the seam must have
      // serialized the local proxy URL into the config line.
      final proxied = await probe.probe(
        apiProxy: 'socks5://127.0.0.1:1999',
        timeout: const Duration(seconds: 10),
      );
      expect(proxied.kind, GuardianProbeKind.passAcquired);
    });

    test('garbage + non-zero exit is an otherFailure, never a 451',
        () async {
      final result = await (await probeOf('garbage'))
          .probe(timeout: const Duration(seconds: 10));
      expect(result.kind, GuardianProbeKind.otherFailure);
      expect(result.failCode, isNot('guardianRegionUnavailable'));
    });

    test('a hung probe honors its budget and is stopped (no orphan)',
        () async {
      final started = DateTime.now();
      final result = await (await probeOf('hang'))
          .probe(timeout: const Duration(milliseconds: 900));
      final elapsed = DateTime.now().difference(started);
      expect(result.kind, GuardianProbeKind.timeout);
      expect(elapsed.inSeconds, lessThan(10));
    });

    test('the same-account refresh reaches the vault callback',
        () async {
      final refreshed = <FirefoxSessionAuth>[];
      final probe = EngineGuardianProbe(
        binaryPath: await writeProbeBinary(tempDir, 'refresh'),
        authProvider: authOf,
        logLevel: 'quiet',
        onAuthRefreshed: refreshed.add,
      );
      final result = await probe.probe(timeout: const Duration(seconds: 10));
      expect(result.kind, GuardianProbeKind.passAcquired);
      expect(refreshed, hasLength(1));
      expect(refreshed.single.accessToken, 'at-shape-only');
    });
  }, skip: !bashExists ? 'no /bin/bash for the stand-in binary' : false);

  group('the seam adapters over the probe', () {
    test('EngineGuardianDirectAttempt maps the taxonomy', () async {
      final direct =
          EngineGuardianDirectAttempt(probe: await probeOf('451'));
      final result = await direct.attempt(timeout: const Duration(seconds: 10));
      expect(result.outcome, GuardianDirectOutcome.regionUnavailable);
      expect(result.errorCode, 'guardianRegionUnavailable');
    });

    test('EngineGuardianAuthorizationVerifier reports ok only through '
        'the proxy', () async {
      final verifier = EngineGuardianAuthorizationVerifier(
          probe: await probeOf('proxyKeyed'));
      final result = await verifier.verify(
        Uri.parse('socks5://127.0.0.1:1999'),
        timeout: const Duration(seconds: 10),
      );
      expect(result.ok, isTrue);
    });
  }, skip: !bashExists ? 'no /bin/bash for the stand-in binary' : false);

  group('evidence forwarding (the walk\'s own direct answer)', () {
    test('forwarded evidence is consumed exactly once', () async {
      var innerCalls = 0;
      final forwarding = EvidenceForwardingGuardianDirectAttempt(
        inner: _CountingDirect(() => innerCalls++),
      );
      forwarding.forward(const GuardianDirectResult(
        outcome: GuardianDirectOutcome.regionUnavailable,
        errorCode: 'guardianRegionUnavailable',
      ));
      final first = await forwarding.attempt(timeout: const Duration(seconds: 1));
      expect(first.outcome, GuardianDirectOutcome.regionUnavailable);
      final second = await forwarding.attempt(timeout: const Duration(seconds: 1));
      expect(second.outcome, GuardianDirectOutcome.otherFailure);
      expect(innerCalls, 1); // the fallback ran the second time
    });

    test('no evidence and no inner seam degrades honestly', () async {
      final forwarding = EvidenceForwardingGuardianDirectAttempt();
      final result = await forwarding.attempt(timeout: const Duration(seconds: 1));
      expect(result.outcome, GuardianDirectOutcome.otherFailure);
      expect(result.errorCode, 'directUnavailable');
    });

    test('GUARDIAN-BOOTSTRAP STAGE 6 — the renewal-time reauthorization '
        'falls through to the REAL inner probe (a spawn with no prior '
        'evidence)', () async {
      // The renewal-time ensureAuthorized has no forwarded evidence (the
      // walk's own 451 was consumed long ago) — the seam must run the
      // REAL engine probe, and a healthy direct answer means NO
      // bootstrap is started (mission §4-2: only a REAL 451 triggers).
      final probe = await probeOf('ok');
      final forwarding = EvidenceForwardingGuardianDirectAttempt(
        inner: EngineGuardianDirectAttempt(probe: probe),
      );
      final result =
          await forwarding.attempt(timeout: const Duration(seconds: 10));
      expect(result.outcome, GuardianDirectOutcome.success,
          reason: 'the real probe ran and Guardian answered');
      expect(result.errorCode, isNull);
    });
  });

  group('the full §5-4 flow with REAL spawns on both sides', () {
    test('451 direct → bootstrap → through-the-proxy authorization',
        () async {
      final probe = await probeOf('proxyKeyed');
      final startedPorts = <int>[];
      final manager = GuardianBootstrapManager(
        filesDir: tempDir.path,
        nativeLibraryDir: '/data/test/lib/arm64',
        directAttempt: EngineGuardianDirectAttempt(probe: probe),
        authorizationVerifier:
            EngineGuardianAuthorizationVerifier(probe: probe),
        proxyFactory: (mode) => _ScriptedProxy(1999, startedPorts),
        memoryPath: '${tempDir.path}/route-memory.json',
        directTimeout: const Duration(seconds: 10),
        authorizationTimeout: const Duration(seconds: 10),
      );
      addTearDown(manager.dispose);

      final states = <GuardianBootstrapManagerState>[];
      final subscription =
          manager.events.listen((event) => states.add(event.state));
      addTearDown(subscription.cancel);

      final session = await manager.ensureAuthorized();
      // The broadcast controller delivers asynchronously — flush the
      // queued transitions before asserting the walk.
      await pumpEventQueue();

      // The winning session: psiphon standalone, the scripted local
      // proxy's endpoint, both timings measured.
      expect(session.routeKind, GuardianBootstrapRouteKind.psiphonOnly);
      expect(session.endpoint?.socksUrl, 'socks5://127.0.0.1:1999');
      expect(session.timings.directMillis, isNotNull);
      expect(session.timings.bootstrapReadyMillis, isNotNull);
      expect(session.timings.authorizationMillis, isNotNull);
      expect(startedPorts, [1999]);

      // The honest state machine walk (mission §4-6): direct → 451 →
      // selecting → starting → ready → authorizing → authorized.
      expect(
        states,
        containsAllInOrder([
          GuardianBootstrapManagerState.directRequest,
          GuardianBootstrapManagerState.guardian451,
          GuardianBootstrapManagerState.bootstrapSelecting,
          GuardianBootstrapManagerState.psiphonDirectStarting,
          GuardianBootstrapManagerState.psiphonDirectReady,
          GuardianBootstrapManagerState.guardianAuthorizing,
          GuardianBootstrapManagerState.authorized,
        ]),
      );

      // A FULL success (readiness + probe + authorization through the
      // real spawn) makes the route Fast-Path eligible (§4-4).
      expect(await manager.fastPathEligible(), isTrue);
    });
  }, skip: !bashExists ? 'no /bin/bash for the stand-in binary' : false);
}

class _CountingDirect implements GuardianDirectAttempt {
  _CountingDirect(this.onCall);

  final void Function() onCall;

  @override
  Future<GuardianDirectResult> attempt(
      {Duration timeout = const Duration(seconds: 30)}) async {
    onCall();
    return const GuardianDirectResult(
        outcome: GuardianDirectOutcome.otherFailure, errorCode: 'counted');
  }
}

/// A stand-in bootstrap proxy: no core, no listener — just the
/// endpoint contract the manager and the verify seam consume.
class _ScriptedProxy extends PsiphonBootstrapProxy {
  _ScriptedProxy(this.port, this.startedPorts)
      : super(
          filesDir: '/data/test/files',
          nativeLibraryDir: '/data/test/lib/arm64',
          mode: PsiphonBootstrapMode.psiphonOnly,
        );

  final int port;
  final List<int> startedPorts;

  @override
  Future<PsiphonProxyEndpoint> start() async {
    startedPorts.add(port);
    return PsiphonProxyEndpoint(host: '127.0.0.1', port: port);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<bool> healthCheck() async => true;
}
