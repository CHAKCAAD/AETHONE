// STAGE 4 (Guardian bootstrap mission) tests: the Firefox Guardian
// Bootstrap Manager (guardian_bootstrap_manager.dart) + the Bootstrap
// Route Memory (bootstrap_route_memory.dart).
//
// What is real here:
//  * the state machine, singleflight, fast-path/discovery decisions,
//    TTL/cooldown policy, network-context isolation, walk exclusion,
//    cancellation and failure classification run against REAL manager
//    logic with injected seams (fake direct attempt / fake
//    authorization verifier / real PsiphonBootstrapProxy instances
//    built on the fake core + probe seam of stages 2/3);
//  * the route memory's persistence, atomic write, corruption
//    tolerance, TTL expiry and cooldown run against the REAL
//    filesystem (a fresh temp dir per test);
//  * the memory's JSON schema is structurally asserted to contain NO
//    secret-shaped fields (mission §7.1 forbidden-data list).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethone/connection/aether_ffi.dart';
import 'package:aethone/connection/firefox/bootstrap_route_memory.dart';
import 'package:aethone/connection/firefox/guardian_bootstrap_manager.dart';
import 'package:aethone/connection/firefox/psiphon_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gbm-stage4-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  GuardianBootstrapManager managerOf({
    required _FakeDirect direct,
    required _FakeVerifier verifier,
    _FixedContext? context,
    bool Function()? walk,
    _Harness? harness,
    Duration? ttl,
    Duration? cooldown,
    String? memoryPath,
  }) =>
      GuardianBootstrapManager(
        filesDir: tempDir.path,
        nativeLibraryDir: '/data/test/lib/arm64',
        directAttempt: direct,
        authorizationVerifier: verifier,
        networkContext: context ?? _FixedContext('wifi'),
        userWalkActive: walk,
        proxyFactory: harness?.factory,
        memoryPath: memoryPath ?? '${tempDir.path}/route-memory.json',
        routeTtl: ttl ?? kDefaultRouteTtl,
        routeCooldown: cooldown ?? kDefaultRouteCooldown,
        directTimeout: const Duration(seconds: 2),
        authorizationTimeout: const Duration(seconds: 2),
      );

  group('route memory (policy unit tests)', () {
    test('missing file loads empty; discovery keeps the default ladder',
        () async {
      final memory = await GuardianBootstrapRouteMemory.load(
        '${tempDir.path}/nothing.json',
      );
      expect(memory.validFastPathRoute('wifi'), isNull);
      expect(memory.shouldSkipDirect('wifi'), isFalse);
      expect(
        memory.discoveryOrder('wifi'),
        kDefaultDiscoveryOrder,
      );
    });

    test('corrupt file degrades to empty — never crashes, never blocks',
        () async {
      final path = '${tempDir.path}/route-memory.json';
      await File(path).writeAsString('{ this is not json');
      final memory = await GuardianBootstrapRouteMemory.load(path);
      expect(memory.validFastPathRoute('wifi'), isNull);
      // And it can be persisted over (recovered) afterwards.
      memory.recordDirectSuccess('wifi');
      await memory.persist();
      final reloaded = await GuardianBootstrapRouteMemory.load(path);
      expect(
        reloaded.validFastPathRoute('wifi'),
        GuardianBootstrapRouteKind.direct,
      );
    });

    test('discovery order: recent success first, cooldown last', () async {
      final memory = await GuardianBootstrapRouteMemory.load(
        '${tempDir.path}/m.json',
      );
      final now = DateTime.now();
      // Chain succeeded recently; standalone failed into cooldown.
      memory.recordRouteSuccess('wifi', GuardianBootstrapRouteKind.aetherPsiphonChain,
          readyMillis: 10, authMillis: 5, now: now);
      memory.recordRouteFailure('wifi', GuardianBootstrapRouteKind.psiphonOnly,
          failureKind: 'start', code: 'coreExited', now: now);
      expect(
        memory.discoveryOrder('wifi', now: now),
        [
          GuardianBootstrapRouteKind.aetherPsiphonChain,
          GuardianBootstrapRouteKind.psiphonOnly,
        ],
        reason: 'mission §4-3: the route that worked is tried first',
      );
      // A NEW success on standalone (more recent) flips the order.
      memory.recordRouteSuccess('wifi', GuardianBootstrapRouteKind.psiphonOnly,
          readyMillis: 10, authMillis: 5, now: now.add(const Duration(minutes: 1)));
      expect(
        memory.discoveryOrder('wifi', now: now.add(const Duration(minutes: 2))),
        [
          GuardianBootstrapRouteKind.psiphonOnly,
          GuardianBootstrapRouteKind.aetherPsiphonChain,
        ],
      );
    });

    test('TTL expiry returns the route to discovery', () async {
      final memory = await GuardianBootstrapRouteMemory.load(
        '${tempDir.path}/m.json',
        ttl: const Duration(hours: 24),
      );
      final now = DateTime.now();
      memory.recordRouteSuccess('wifi', GuardianBootstrapRouteKind.psiphonOnly,
          readyMillis: 1, authMillis: 1, now: now);
      memory.recordDirectRegionUnavailable('wifi', now: now);
      expect(memory.shouldSkipDirect('wifi', now: now), isTrue);
      // 25 hours later: stale data grants nothing.
      final later = now.add(const Duration(hours: 25));
      expect(memory.validFastPathRoute('wifi', now: later), isNull);
      expect(memory.shouldSkipDirect('wifi', now: later), isFalse);
    });

    test('context isolation: another context never sees this one\'s route',
        () async {
      final memory = await GuardianBootstrapRouteMemory.load(
        '${tempDir.path}/m.json',
      );
      memory.recordRouteSuccess('wifi', GuardianBootstrapRouteKind.psiphonOnly,
          readyMillis: 1, authMillis: 1);
      memory.recordDirectRegionUnavailable('wifi');
      expect(memory.validFastPathRoute('cellular'), isNull,
          reason: 'mission §7.1: no blind generalization across networks');
      expect(memory.shouldSkipDirect('cellular'), isFalse);
    });

    test('persisted JSON has NO secret-shaped fields (schema contract)',
        () async {
      final path = '${tempDir.path}/m.json';
      final memory = await GuardianBootstrapRouteMemory.load(path);
      memory.recordRouteSuccess('wifi', GuardianBootstrapRouteKind.psiphonOnly,
          readyMillis: 12, authMillis: 34);
      memory.recordDirectRegionUnavailable('wifi');
      await memory.persist();

      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw);
      expect(decoded, isA<Map>());
      expect((decoded as Map)['version'], kGuardianRouteMemoryVersion);

      // Exact-key scan against the mission's forbidden field names
      // (substring matching would flag honest keys like 'psiphonOnly').
      final forbiddenKeys = {
        'token', 'accessToken', 'refreshToken', 'proxyPass', 'session',
        'ssid', 'bssid', 'ip', 'password', 'secret', 'authorization',
        'cookies', 'headers', 'body',
      };
      void scan(Map node) {
        for (final key in node.keys) {
          expect(forbiddenKeys.contains(key.toString()), isFalse,
              reason: 'forbidden field "$key" in route memory');
          final value = node[key];
          if (value is Map) scan(value);
        }
      }

      scan(decoded);
      // And the exact allowed field set of one route's stats:
      final stats = decoded['contexts']['wifi']['routes']['psiphonOnly']
          as Map<String, dynamic>;
      expect(
        stats.keys.toSet(),
        {
          'successes', 'failures', 'lastSuccessAt', 'lastReadyMillis',
          'lastAuthMillis', 'lastFailureKind', 'lastFailureCode',
          'lastFailureAt', 'cooldownUntil',
        },
      );
    });
  });

  group('manager — direct path (mission scenario A)', () {
    test('direct success authorizes with NO bootstrap at all', () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(outcome: GuardianDirectOutcome.success),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      final session = await manager.ensureAuthorized();
      expect(session.routeKind, GuardianBootstrapRouteKind.direct);
      expect(session.endpoint, isNull);
      expect(session.timings.directMillis, isNotNull);
      expect(session.timings.bootstrapReadyMillis, isNull);
      expect(manager.state, GuardianBootstrapManagerState.authorized);
      expect(harness.factoryCalls, 0,
          reason: 'direct success must never start an engine');
      // Direct is recorded as the winning route of this context.
      final memory = await manager.memory;
      expect(memory.validFastPathRoute('wifi'),
          GuardianBootstrapRouteKind.direct);
      await manager.dispose();
    });

    test('a NON-451 direct failure fails honestly — no bootstrap loop',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.otherFailure, errorCode: '401'),
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.otherFailure, errorCode: '403'),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      await expectLater(
        manager.ensureAuthorized(),
        throwsA(isA<GuardianBootstrapException>()
            .having((e) => e.code, 'code', 'directFailed')
            .having((e) => e.message, 'message', contains('401'))),
      );
      expect(manager.state, GuardianBootstrapManagerState.failed);
      expect(manager.lastFailureCode, 'directFailed');
      expect(harness.factoryCalls, 0,
          reason: '401/403 are never region blocks — no engine ever starts');
      // A second call tries DIRECT again (not bootstrap).
      await expectLater(manager.ensureAuthorized(), throwsA(anything));
      expect(direct.calls, 2);
      expect(harness.factoryCalls, 0);
      await manager.dispose();
    });
  });

  group('manager — discovery (mission scenario B/C)', () {
    test('451 → standalone first, full state sequence, timings recorded',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final verifier = _FakeVerifier(ok: true);
      final manager = managerOf(
          direct: direct, verifier: verifier, harness: harness);
      final states = <GuardianBootstrapManagerState>[];
      final sub =
          manager.events.listen((event) => states.add(event.state));
      final session = await manager.ensureAuthorized();
      // Broadcast delivery is scheduled — flush before cancelling.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(session.routeKind, GuardianBootstrapRouteKind.psiphonOnly);
      expect(harness.modesCalled, [PsiphonBootstrapMode.psiphonOnly]);
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
      // The authorization ran THROUGH the winning route's proxy.
      expect(verifier.urlsSeen, [session.endpoint!.socksUrl]);
      expect(session.endpoint!.socksUrl, startsWith('socks5://127.0.0.1:'));
      // Mission §7.1: bootstrap-ready and authorization timings are
      // recorded SEPARATELY.
      expect(session.timings.bootstrapReadyMillis, isNotNull);
      expect(session.timings.authorizationMillis, isNotNull);
      expect(session.timings.directMillis, isNull);
      await manager.dispose();
    });

    test('standalone fails → the EXISTING chain is tried and wins',
        () async {
      final harness = _Harness(startFailures: {
        PsiphonBootstrapMode.psiphonOnly,
      });
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      final session = await manager.ensureAuthorized();
      expect(session.routeKind, GuardianBootstrapRouteKind.aetherPsiphonChain);
      expect(
        harness.modesCalled,
        [PsiphonBootstrapMode.psiphonOnly, PsiphonBootstrapMode.aetherPsiphonChain],
      );
      // The failed route is classified and cooled down; the winner is
      // remembered (adaptive §4-3).
      final memory = await manager.memory;
      final failed = memory.statsFor(
          'wifi', GuardianBootstrapRouteKind.psiphonOnly)!;
      expect(failed.lastFailureKind, 'start');
      expect(failed.cooldownUntil, isNotNull);
      expect(
        memory.discoveryOrder('wifi').first,
        GuardianBootstrapRouteKind.aetherPsiphonChain,
      );
      await manager.dispose();
    });

    test('all routes fail → allRoutesFailed with per-route classification; '
        'resources freed', () async {
      final harness = _Harness(startFailures: {
        PsiphonBootstrapMode.psiphonOnly,
        PsiphonBootstrapMode.aetherPsiphonChain,
      });
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      await expectLater(
        manager.ensureAuthorized(),
        throwsA(isA<GuardianBootstrapException>()
            .having((e) => e.code, 'code', 'allRoutesFailed')
            .having((e) => e.message, 'message', allOf(
                contains('psiphonOnly'), contains('aetherPsiphonChain')))),
      );
      expect(manager.state, GuardianBootstrapManagerState.failed);
      // No orphan engines: every started job was cancelled + freed.
      expect(harness.cancelledIds, isNotEmpty);
      expect(harness.freedIds.length, harness.cancelledIds.length);
      expect(manager.endpoint, isNull);
      await manager.dispose();
    });

    test('authorization failure is classified separately from start failure',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: false, code: 'http500'),
        harness: harness,
      );
      await expectLater(
        manager.ensureAuthorized(),
        throwsA(isA<GuardianBootstrapException>()
            .having((e) => e.code, 'code', 'allRoutesFailed')
            .having((e) => e.message, 'message', contains('authorization'))),
      );
      final memory = await manager.memory;
      expect(
        memory.statsFor('wifi', GuardianBootstrapRouteKind.psiphonOnly)!
            .lastFailureKind,
        'authorization',
        reason: 'the engine was ready; Guardian refused — mission §4-5 '
            'keeps these apart',
      );
      await manager.dispose();
    });
  });

  group('manager — singleflight and session reuse', () {
    test('concurrent ensureAuthorized calls share ONE bootstrap', () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      final results = await Future.wait([
        manager.ensureAuthorized(),
        manager.ensureAuthorized(),
        manager.ensureAuthorized(),
      ]);
      expect(harness.factoryCalls, 1,
          reason: 'mission §4-5: many Guardian requests, ONE bootstrap');
      expect(harness.totalCoreStarts, 1);
      expect({for (final session in results) session.endpoint!.port}.length, 1);
      await manager.dispose();
    });

    test('a healthy authorized session is reused without new work; a dead '
        'proxy is rebuilt', () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      final first = await manager.ensureAuthorized();
      final second = await manager.ensureAuthorized();
      expect(second.endpoint!.port, first.endpoint!.port);
      expect(harness.factoryCalls, 1);
      expect(direct.calls, 1);

      // Kill the core behind the live proxy → healthCheck goes false.
      harness.cores.first.jobs.first.error = 'core died';
      expect(await manager.healthCheck(), isFalse);
      final third = await manager.ensureAuthorized();
      expect(harness.factoryCalls, 2, reason: 'the dead proxy is rebuilt');
      expect(third.endpoint!.socksUrl, startsWith('socks5://127.0.0.1:'));
      expect(manager.state, GuardianBootstrapManagerState.authorized);
      await manager.dispose();
    });
  });

  group('manager — fast path (mission scenario G, level-two memory)', () {
    test('second connection in the same context skips the doomed direct '
        'attempt AND still verifies everything', () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final verifier = _FakeVerifier(ok: true);
      final memoryPath = '${tempDir.path}/route-memory.json';
      final manager = managerOf(
          direct: direct, verifier: verifier, harness: harness, memoryPath: memoryPath);
      await manager.ensureAuthorized(); // cold: discovery + save
      await manager.dispose();

      // "App restart": a brand-new manager over the SAME memory file.
      final harness2 = _Harness();
      final direct2 = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final verifier2 = _FakeVerifier(ok: true);
      final manager2 = managerOf(
          direct: direct2, verifier: verifier2, harness: harness2, memoryPath: memoryPath);
      final session = await manager2.ensureAuthorized();
      expect(direct2.calls, 0,
          reason: 'recent real 451 + valid saved route → fast path');
      expect(session.routeKind, GuardianBootstrapRouteKind.psiphonOnly);
      expect(
        harness2.modesCalled,
        [PsiphonBootstrapMode.psiphonOnly],
        reason: 'no scan of the other method',
      );
      // NOT blind trust: readiness + probe ran (a core job started and
      // resolved ready) and the authorization was re-verified.
      expect(harness2.totalCoreStarts, 1);
      expect(verifier2.calls, 1);
      await manager2.dispose();
    });

    test('fast-path failure → cooldown + discovery through the remaining '
        'route; memory follows the new winner', () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final memoryPath = '${tempDir.path}/route-memory.json';
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      await manager.ensureAuthorized(); // psiphonOnly wins
      await manager.dispose();

      // Restart: the saved route's authorization now fails once.
      final harness2 = _Harness();
      final direct2 = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager2 = managerOf(
        direct: direct2,
        verifier: _FakeVerifier(ok: true, failFirst: 1),
        harness: harness2,
        memoryPath: memoryPath,
      );
      final session = await manager2.ensureAuthorized();
      expect(session.routeKind, GuardianBootstrapRouteKind.aetherPsiphonChain,
          reason: 'fast path failed → discovery tried the remaining route');
      expect(
        harness2.modesCalled,
        [PsiphonBootstrapMode.psiphonOnly, PsiphonBootstrapMode.aetherPsiphonChain],
      );
      // The failed route is in cooldown; the new winner is remembered.
      final memory = await manager2.memory;
      expect(
        memory.statsFor('wifi', GuardianBootstrapRouteKind.psiphonOnly)!
            .inCooldown(DateTime.now()),
        isTrue,
      );
      expect(
        memory.validFastPathRoute('wifi'),
        GuardianBootstrapRouteKind.aetherPsiphonChain,
      );
      await manager2.dispose();
    });

    test('TTL expiry sends the next connection back to discovery '
        '(direct first)', () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final memoryPath = '${tempDir.path}/route-memory.json';
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      await manager.ensureAuthorized();
      await manager.dispose();

      // Age the saved success beyond the TTL, in the file itself.
      final file = File(memoryPath);
      final document =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final context =
          document['contexts']!['wifi']! as Map<String, dynamic>;
      (context['routes']!['psiphonOnly']! as Map<String, dynamic>)
          ['lastSuccessAt'] =
          DateTime.now().subtract(const Duration(hours: 25)).toIso8601String();
      context['lastDirectAt'] = DateTime.now()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      await file.writeAsString(jsonEncode(document));

      final harness2 = _Harness();
      final direct2 = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager2 = managerOf(
        direct: direct2,
        verifier: _FakeVerifier(ok: true),
        harness: harness2,
        memoryPath: memoryPath,
      );
      await manager2.ensureAuthorized();
      expect(direct2.calls, 1,
          reason: 'stale memory grants nothing — direct is tried first');
      await manager2.dispose();
    });

    test('another network context never reuses this one\'s fast path',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final context = _FixedContext('wifi');
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
        context: context,
      );
      await manager.ensureAuthorized();
      await manager.dispose();

      final harness2 = _Harness();
      final direct2 = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager2 = managerOf(
        direct: direct2,
        verifier: _FakeVerifier(ok: true),
        harness: harness2,
        context: _FixedContext('cellular'),
      );
      await manager2.ensureAuthorized();
      expect(direct2.calls, 1,
          reason: 'mission scenario H: no generalization across contexts');
      await manager2.dispose();
    });
  });

  group('manager — network change, release, walk exclusion', () {
    test('notifyNetworkContextChanged invalidates a foreign-context session',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final context = _FixedContext('wifi');
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
        context: context,
      );
      await manager.ensureAuthorized();
      context.id = 'cellular';
      await manager.notifyNetworkContextChanged();
      expect(manager.state, GuardianBootstrapManagerState.idle);
      expect(manager.session, isNull);
      expect(harness.cancelledIds, isNotEmpty,
          reason: 'the proxy was torn down — no orphan engines');
      // Same context again: nothing changes.
      context.id = 'cellular';
      final before = manager.state;
      await manager.notifyNetworkContextChanged();
      expect(manager.state, before);
      await manager.dispose();
    });

    test('release() after success frees the proxy; memory survives',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      await manager.ensureAuthorized();
      await manager.release();
      expect(manager.state, GuardianBootstrapManagerState.stopped);
      expect(await manager.healthCheck(), isFalse);
      expect(harness.cancelledIds, isNotEmpty);
      // The learned route survives the release (Stage 6's renewal
      // policy can fast-path the next authorization).
      final memory = await manager.memory;
      expect(memory.validFastPathRoute('wifi'),
          GuardianBootstrapRouteKind.psiphonOnly);
      await manager.dispose();
    });

    test('an active user aether walk blocks bootstrap starts (walkActive)',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      var walking = false;
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
        walk: () => walking,
      );
      walking = true;
      await expectLater(
        manager.ensureAuthorized(),
        throwsA(isA<GuardianBootstrapException>()
            .having((e) => e.code, 'code', 'walkActive')),
      );
      expect(harness.factoryCalls, 0,
          reason: 'shared process env + identity file — never race the walk');
      // The walk ending unblocks the next attempt.
      walking = false;
      final session = await manager.ensureAuthorized();
      expect(session.routeKind, GuardianBootstrapRouteKind.psiphonOnly);
      await manager.dispose();
    });
  });

  group('manager — cancellation and dispose', () {
    test('stop() during a bootstrap start cancels cleanly', () async {
      final harness = _Harness(
        probeFailFirstBy: (index) => index == 0 ? 1 << 30 : 0,
        readyBudgetMs: 400,
      );
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      final starting = manager.ensureAuthorized();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await manager.stop();
      await expectLater(
        starting,
        throwsA(isA<GuardianBootstrapException>()
            .having((e) => e.code, 'code', 'cancelled')),
      );
      expect(manager.state, GuardianBootstrapManagerState.stopped);
      expect(harness.cancelledIds, isNotEmpty);
      // A later attempt works normally — and ADAPTIVELY: the cancelled
      // start left psiphonOnly in cooldown, so discovery prefers the
      // chain (the policy working as designed, mission §4-3).
      final session = await manager.ensureAuthorized();
      expect(session.routeKind, GuardianBootstrapRouteKind.aetherPsiphonChain);
      await manager.dispose();
    });

    test('dispose closes the event stream; use after dispose is honest',
        () async {
      final harness = _Harness();
      final direct = _FakeDirect([
        const GuardianDirectResult(
            outcome: GuardianDirectOutcome.regionUnavailable),
      ]);
      final manager = managerOf(
        direct: direct,
        verifier: _FakeVerifier(ok: true),
        harness: harness,
      );
      final done = Completer<void>();
      final sub = manager.events.listen((_) {}, onDone: done.complete);
      await manager.ensureAuthorized();
      await manager.dispose();
      await done.future.timeout(const Duration(seconds: 2));
      expect(
        () => manager.ensureAuthorized(),
        throwsA(isA<GuardianBootstrapException>()
            .having((e) => e.code, 'code', 'disposed')),
      );
      await manager.stop(); // no-op, no throw
      await sub.cancel();
    });
  });
}

// ---- harnesses and fakes ----------------------------------------------------

/// Configurable network context for tests.
class _FixedContext implements GuardianNetworkContextProvider {
  _FixedContext(this.id);

  String id;

  @override
  Future<String> currentContextId() async => id;
}

/// Scripted direct-attempt seam: serves queued results (last one
/// repeats), counting calls.
class _FakeDirect implements GuardianDirectAttempt {
  _FakeDirect(this.results);

  final List<GuardianDirectResult> results;
  int calls = 0;

  @override
  Future<GuardianDirectResult> attempt({Duration timeout = const Duration(seconds: 30)}) async {
    final index = calls < results.length ? calls : results.length - 1;
    calls++;
    return results[index];
  }
}

/// Scripted authorization seam: fails the first [failFirst] calls,
/// then answers [ok].
class _FakeVerifier implements GuardianAuthorizationVerifier {
  _FakeVerifier({required this.ok, this.code, this.failFirst = 0});

  final bool ok;
  final String? code;
  final int failFirst;
  final List<String> urlsSeen = [];
  int calls = 0;

  @override
  Future<GuardianAuthorizationResult> verify(
    Uri proxyUrl, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    urlsSeen.add(proxyUrl.toString());
    calls++;
    if (calls <= failFirst) {
      return GuardianAuthorizationResult(
          ok: false, code: code ?? 'authRejected');
    }
    return GuardianAuthorizationResult(ok: ok, code: code);
  }
}

/// Builds REAL PsiphonBootstrapProxy instances on the stage-2/3 fake
/// core + probe seams, with per-test scripted failures:
///  * [startFailures] — modes whose core job dies immediately;
///  * [probeFailFirstBy] — probe failures per factory index (index 0 =
///    the first created proxy), for never-ready / cancellation tests;
///  * [readyBudgetMs] — the per-proxy start budget.
class _Harness {
  _Harness({
    this.startFailures = const {},
    this.probeFailFirstBy,
    this.readyBudgetMs = 2000,
  });

  final Set<PsiphonBootstrapMode> startFailures;
  final int Function(int factoryIndex)? probeFailFirstBy;
  final int readyBudgetMs;

  final List<PsiphonBootstrapMode> modesCalled = [];
  final List<_MCore> cores = [];
  final List<int> cancelledIds = [];
  final List<int> freedIds = [];

  int get factoryCalls => modesCalled.length;
  int get totalCoreStarts =>
      cores.fold(0, (sum, core) => sum + core.startedArgs.length);

  PsiphonBootstrapProxy factory(PsiphonBootstrapMode mode) {
    final index = modesCalled.length;
    modesCalled.add(mode);
    final core = _MCore(
      onStart: startFailures.contains(mode)
          ? (job) => job.error = 'the core refused to start ($mode)'
          : null,
    )
      ..cancelledListener = cancelledIds
      ..freedListener = freedIds;
    cores.add(core);
    final probe = _MProbe(failFirst: probeFailFirstBy?.call(index) ?? 0);
    return PsiphonBootstrapProxy(
      filesDir: '/data/test/files',
      nativeLibraryDir: '/data/test/lib/arm64',
      mode: mode,
      coreFactory: () => core,
      probe: probe,
      readyBudget: Duration(milliseconds: readyBudgetMs),
      probeTimeout: const Duration(milliseconds: 40),
      probeRetryInterval: const Duration(milliseconds: 10),
      healthInterval: const Duration(seconds: 15),
      cancelGrace: const Duration(milliseconds: 150),
      portFreeBudget: const Duration(milliseconds: 150),
    );
  }
}

/// Minimal copy of the stage-2/3 fake core (one job per start,
/// per-start behavior hook, shared cancel/free listeners).
class _MCore implements AetherCoreApi {
  _MCore({this.onStart});

  final void Function(_MJob job)? onStart;
  final List<List<String>> startedArgs = [];
  final List<_MJob> jobs = [];
  late final List<int> cancelledListener;
  late final List<int> freedListener;

  @override
  int coreStart(List<String> args) {
    final job = _MJob(args);
    jobs.add(job);
    startedArgs.add(args);
    onStart?.call(job);
    return jobs.length;
  }

  @override
  AetherReply jobPoll(int id) {
    if (id < 1 || id > jobs.length) {
      return AetherReply(false, {'error': 'there is no job $id'});
    }
    final job = jobs[id - 1];
    if (job.error != null) {
      return AetherReply(false, {'error': job.error});
    }
    if (job.done) {
      return AetherReply(true, {
        'state': 'done',
        'result': job.result ?? const {'state': 'closed'},
      });
    }
    return AetherReply(true, const {'state': 'running'});
  }

  @override
  bool jobCancel(int id) {
    cancelledListener.add(id);
    if (id >= 1 && id <= jobs.length) {
      final job = jobs[id - 1];
      if (!job.done && job.error == null) {
        job.done = true;
        job.result = const {'state': 'stopped'};
      }
    }
    return true;
  }

  @override
  bool jobFree(int id) {
    freedListener.add(id);
    return true;
  }
}

class _MJob {
  _MJob(this.args);

  final List<String> args;
  bool done = false;
  String? error;
  Map<String, Object?>? result;
}

/// Minimal fake probe: fails the first [failFirst] calls, then passes.
class _MProbe implements PsiphonReadyProbe {
  _MProbe({this.failFirst = 0});

  final int failFirst;
  int calls = 0;

  @override
  Future<void> verify({required int port, required Duration timeout}) async {
    calls++;
    if (calls <= failFirst) {
      throw const SocketException('not ready yet');
    }
  }
}
