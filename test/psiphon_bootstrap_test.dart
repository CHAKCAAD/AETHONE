// STAGE 2+3 (Guardian bootstrap mission) tests: the standalone Psiphon
// local proxy manager AND the existing AETHER → PSIPHON combination
// launched for bootstrap (lib/connection/firefox/psiphon_bootstrap.dart).
//
// What is real here:
//  * the argument build is asserted against the PINNED core's semantics
//    (psiphon-only mode; chain mode = the walk's own --psiphon flags on
//    dedicated ephemeral ports; no upstream/region/shape pinning);
//  * the port allocation, the SOCKS5+TLS readiness probe and the
//    «an open port is NOT ready» rule run against REAL dart:io sockets;
//  * the LIVE probe tests drive the full real handshake (SOCKS5 →
//    domain CONNECT → verified TLS → HTTP trace) through local relay
//    stand-ins to the real trace host — the stage-3 one traverses the
//    WHOLE simulated chain (egress → psiphon-sim → warp-sim) — skipped
//    honestly when this machine is offline;
//  * the chain's leg mapping is EQUIVALENCE-LOCKED against the connect
//    walk's own AetherArguments.protocolArgs for a psiphonChain overlay;
//  * the manager lifecycle (singleflight, port-conflict retry, crash,
//    cancellation, timeout, dispose) runs against a fake core +
//    injectable probe seam — the same convention as the connect walk's
//    m2_engine_test.dart fakes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aethone/connection/aether_ffi.dart';
import 'package:aethone/connection/firefox/psiphon_bootstrap.dart';
import 'package:aethone/connection/core_settings.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> main() async {
  // LIVE-test gate, computed ONCE before the declarations (skip: needs
  // its value at declaration time): can this machine reach the real
  // trace host directly? Offline dev boxes / firewalled CI skip the live
  // probe honestly instead of failing it.
  final liveNet = await _canReachTraceHost();

  group('source contract (no VpnService / no TUN / no platform channel)', () {
    test('the manager never touches a channel, a VPN service or a TUN', () {
      final source = File(
        '${Directory.current.path}/lib/connection/firefox/psiphon_bootstrap.dart',
      );
      expect(source.existsSync(), isTrue,
          reason: 'the manager source must exist at the pinned path');
      // Strip comment lines first — the DOC comments name the forbidden
      // symbols when explaining their absence; only CODE is contracted.
      final code = source
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final forbidden in [
        'MethodChannel',
        'invokeMethod',
        'startVpn',
        'startCoreHold',
        'VpnService',
        'prepareVpn',
        'NetworkInterface', // no route/TUN manipulation either
      ]) {
        expect(code, isNot(contains(forbidden)),
            reason: '$forbidden must never appear in the bootstrap manager');
      }
    });
  });

  group('bootstrap argument build (evidence-locked to the pin)', () {
    test('psiphon-only on a loopback bind with the packaged binary', () {
      final args = PsiphonBootstrapProxy.buildArgs(
        port: 45678,
        filesDir: '/data/app/files',
        nativeLibraryDir: '/data/app/lib/arm64',
      );
      expect(args, containsAllInOrder(['--bind', '127.0.0.1:45678']));
      expect(args, contains('--psiphon-only'));
      expect(
        args,
        containsAllInOrder(
            ['--psiphon-bin', '/data/app/lib/arm64/libpsiphon.so']),
      );
      expect(
        args,
        containsAllInOrder(
            ['--psiphon-dir', '/data/app/files/aether/psiphon-bootstrap']),
      );
      expect(args, containsAllInOrder(['--log-level', 'info']));
      // The bind is LOOPBACK ONLY (mission §11: the proxy must never be
      // reachable off-device).
      final bind = args[args.indexOf('--bind') + 1];
      expect(bind.startsWith('127.0.0.1:'), isTrue);
    });

    test('no carrier, no chain listener, no manual protocol/region pin', () {
      final args = PsiphonBootstrapProxy.buildArgs(
        port: 45678,
        filesDir: '/f',
        nativeLibraryDir: '/l',
      );
      // No Aether/WARP upstream (standalone = the child dials out itself).
      expect(args, isNot(contains('--upstream')));
      // No chain-mode egress listener (that is Stage 3's --psiphon-bind).
      expect(args, isNot(contains('--psiphon-bind')));
      // No extra HTTP listener: one SOCKS5 listener is the whole surface.
      expect(args, isNot(contains('--psiphon-http')));
      // ADAPTIVE connection: no egress region and no shape pinning —
      // server/protocol/tactics selection stays inside psiphon itself.
      expect(args, isNot(contains('--psiphon-region')));
      expect(args, isNot(contains('--psiphon-mode')));
      // No WARP identity work happens in only mode (lib.rs returns at
      // psiphon::run_only before any scan/registration) — no --config,
      // no scan profile, no quick-reconnect, no IP-version pin.
      expect(args, isNot(contains('--config')));
      expect(args, isNot(contains('--scan')));
      expect(args, isNot(contains('--quick-reconnect')));
      expect(args, isNot(contains('-4')));
      expect(args, isNot(contains('-6')));
      expect(args, isNot(contains('--dual')));
    });

    test('the data directory is dedicated, not the user modes\' one', () {
      // The user-facing psiphon family modes run
      // --psiphon-dir <filesDir>/aether/psiphon (AetherArguments.build);
      // the bootstrap must never share it — two psiphon children on one
      // data directory is unsafe (single-owner DataRootDirectory).
      final args = PsiphonBootstrapProxy.buildArgs(
        port: 1,
        filesDir: '/files',
        nativeLibraryDir: '/lib',
      );
      final dir = args[args.indexOf('--psiphon-dir') + 1];
      expect(dir, '/files/aether/psiphon-bootstrap');
      expect(dir == '/files/aether/psiphon', isFalse);
    });
  });

  group('ephemeral port allocation', () {
    test('picks a free loopback port outside the pinned map', () async {
      final port = await PsiphonBootstrapProxy.pickFreeLoopbackPort();
      expect(port, greaterThan(1024));
      expect(port, lessThan(65536));
      expect(kPinnedAethonePorts.contains(port), isFalse,
          reason: 'never 1819/1820/1821/1822 — the user modes own those');
      // The port really is free after the pick (the socket was released):
      // binding it again must succeed.
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await server.close();
    });

    test('two picks are OS-ephemeral (distinct with overwhelming odds)',
        () async {
      final picks = <int>{
        for (var i = 0; i < 8; i++) await PsiphonBootstrapProxy.pickFreeLoopbackPort(),
      };
      expect(picks.length, greaterThan(1),
          reason: 'the pick is per-start random, never a fixed constant');
    });
  });

  group('real readiness probe (real sockets)', () {
    test('an open port that never speaks SOCKS5 is NOT ready', () async {
      // The mission's rule: «بازشدن Port به‌تنهایی Ready محسوب نمی‌شود».
      // This listener accepts TCP (the port is open!) and then stays
      // silent — exactly the core's held-but-not-yet-relayed bind
      // listener. The probe must fail, not pass.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final subscriptions = <StreamSubscription<Socket>>[];
      subscriptions.add(
        server.listen((socket) {
          // accept and say nothing — the honest "not ready" state
        }, onError: (Object _) {}),
      );
      try {
        await expectLater(
          const SocksTlsReadyProbe().verify(
            port: server.port,
            timeout: const Duration(milliseconds: 400),
          ),
          throwsA(isA<SocketException>()),
        );
      } finally {
        await server.close();
        for (final s in subscriptions) {
          await s.cancel();
        }
      }
    });

    test('LIVE: the full SOCKS5→CONNECT→verified-TLS probe to the real '
        'trace host (through a direct-forwarding relay)', () async {
      final relay = await _DirectSocksRelay.start();
      try {
        await const SocksTlsReadyProbe().verify(
          port: relay.port,
          timeout: const Duration(seconds: 20),
        );
        // Reaching here means: SOCKS5 greeting OK, DOMAIN CONNECT OK
        // (remote resolution semantics), TLS verified against the real
        // trust store, and an HTTP 2xx/3xx status came back.
        expect(relay.lastConnectedHost, 'www.cloudflare.com');
        expect(relay.lastConnectWasDomain, isTrue);
      } finally {
        await relay.dispose();
      }
    }, skip: liveNet ? false : 'no direct network access from this machine');
  });

  group('manager lifecycle (fake core + probe seam)', () {
    test('start waits for the probe, records the pinned-only args and '
        'resolves with the endpoint (port readback)', () async {
      final core = _FakeCore();
      final probe = _FakeProbe(failFirst: 2); // two honest "not yet"s
      final manager = _manager(core, probe);
      final states = <PsiphonBootstrapState>[];
      final sub = manager.events.listen((e) => states.add(e.state));

      final endpoint = await manager.start();
      try {
        // Broadcast-stream delivery can lag the producing future's
        // resumption by one turn under flutter_test — flush the queue
        // before asserting on recorded events.
        await Future<void>.delayed(Duration.zero);
        expect(manager.state, PsiphonBootstrapState.ready);
        expect(endpoint.socksUrl, 'socks5://127.0.0.1:${endpoint.port}');
        // ONE core job, in only mode, on the endpoint's port.
        expect(core.startedArgs.length, 1);
        final args = core.startedArgs.single;
        expect(args, contains('--psiphon-only'));
        final bindPort =
            int.parse(args[args.indexOf('--bind') + 1].split(':').last);
        expect(bindPort, endpoint.port,
            reason: 'the endpoint is the port handed to --bind '
                '(known by construction, never parsed from logs)');
        expect(kPinnedAethonePorts.contains(bindPort), isFalse);
        // The probe retried before succeeding (the wait is real).
        expect(probe.calls, greaterThanOrEqualTo(3));
        expect(probe.portsSeen.toSet(), {endpoint.port});
        expect(states.first, PsiphonBootstrapState.starting);
        expect(states.last, PsiphonBootstrapState.ready);
      } finally {
        await sub.cancel();
        await manager.dispose();
      }
    });

    test('singleflight: concurrent starts share ONE core job', () async {
      final core = _FakeCore();
      final probe = _FakeProbe(failFirst: 3);
      final manager = _manager(core, probe);

      final a = manager.start();
      final b = manager.start();
      expect(identical(a, b), isTrue,
          reason: 'the same future — no second Psiphon for a concurrent '
              'Guardian request');
      final endpoint = await a;
      await b.catchError((_) => endpoint);
      expect(core.startedArgs.length, 1);
      expect(manager.state, PsiphonBootstrapState.ready);
      await manager.dispose();
    });

    test('a start while ready returns the endpoint without a new core job',
        () async {
      final core = _FakeCore();
      final manager = _manager(core, _FakeProbe());
      final first = await manager.start();
      final second = await manager.start();
      expect(second.port, first.port);
      expect(core.startedArgs.length, 1);
      await manager.dispose();
    });

    test('bind conflict during the hand-off retried on a fresh port',
        () async {
      // Fail only the FIRST spawned job with the pinned core's frozen
      // conflict wording (socks.rs bind_listener) — the port was taken
      // in the release→bind window.
      var firstJob = true;
      final core = _FakeCore(onStart: (job) {
        if (firstJob) {
          firstJob = false;
          job.error = 'the socks5 listener cannot use 127.0.0.1:51000: '
              'Address already in use (os error 98); another program '
              'already listens there, so stop it or choose another port '
              'with --bind';
        }
      });
      final probe = _FakeProbe();
      final manager = _manager(core, probe);

      final endpoint = await manager.start();
      expect(core.startedArgs.length, 2,
          reason: 'the conflict consumed one attempt, the retry started '
              'a fresh core');
      final firstPort = int.parse(core.startedArgs[0]
          [core.startedArgs[0].indexOf('--bind') + 1]
          .split(':')
          .last);
      final secondPort = int.parse(core.startedArgs[1]
          [core.startedArgs[1].indexOf('--bind') + 1]
          .split(':')
          .last);
      expect(firstPort, isNot(equals(secondPort)));
      expect(endpoint.port, secondPort);
      expect(manager.state, PsiphonBootstrapState.ready);
      // The dead first job was cancelled and freed (no registry leak).
      expect(core.cancelled, contains(1));
      expect(core.freed, contains(1));
      await manager.dispose();
    });

    test('the core\'s own error fails the start verbatim (coreExited)',
        () async {
      final core = _FakeCore(onStart: (job) {
        job.error = 'psiphon did not come up in time; it may be blocked '
            'on this network';
      });
      final manager = _manager(core, _FakeProbe());
      await expectLater(
        manager.start(),
        throwsA(
          isA<PsiphonBootstrapException>()
              .having((e) => e.code, 'code', 'coreExited')
              .having((e) => e.message, 'message',
                  contains('blocked on this network')),
        ),
      );
      expect(manager.state, PsiphonBootstrapState.failed);
      expect(manager.lastFailureCode, 'coreExited');
      await manager.dispose();
    });

    test('a core that exits cleanly during the wait is coreExited too',
        () async {
      final core = _FakeCore(onStart: (job) {
        job.done = true; // result.state = closed
      });
      final manager = _manager(core, _FakeProbe());
      await expectLater(
        manager.start(),
        throwsA(
          isA<PsiphonBootstrapException>()
              .having((e) => e.code, 'code', 'coreExited')
              .having((e) => e.message, 'message',
                  contains('the core exited on its own')),
        ),
      );
      await manager.dispose();
    });

    test('ready-budget exhaustion fails notReady and cleans the job up',
        () async {
      final core = _FakeCore();
      final manager = _manager(core, _FakeProbe.alwaysFailing(),
          readyBudget: const Duration(milliseconds: 150));
      await expectLater(
        manager.start(),
        throwsA(
          isA<PsiphonBootstrapException>()
              .having((e) => e.code, 'code', 'notReady'),
        ),
      );
      expect(manager.state, PsiphonBootstrapState.failed);
      expect(core.cancelled, isNotEmpty,
          reason: 'the still-running job was cancelled, not orphaned');
      expect(core.freed, isNotEmpty,
          reason: 'the registry entry was freed');
      await manager.dispose();
    });

    test('stop during start cancels cleanly and is NOT a failure',
        () async {
      final core = _FakeCore();
      final manager = _manager(core, _FakeProbe.alwaysFailing(),
          readyBudget: const Duration(seconds: 10));
      final startFuture = manager.start();
      // Give the wait loop a few probe cycles, then stop.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await manager.stop();
      await expectLater(
        startFuture,
        throwsA(
          isA<PsiphonBootstrapException>()
              .having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      expect(manager.state, PsiphonBootstrapState.idle,
          reason: 'a user stop owns the terminal state — never "failed"');
      expect(core.cancelled, isNotEmpty);
      await manager.dispose();
    });

    test('stop when ready tears the job down; stop is idempotent',
        () async {
      final core = _FakeCore();
      final manager = _manager(core, _FakeProbe());
      await manager.start();
      await manager.stop();
      expect(manager.state, PsiphonBootstrapState.idle);
      expect(manager.endpoint, isNull);
      expect(core.cancelled, [1]);
      expect(core.freed, [1]);
      await manager.stop(); // idempotent — no crash, no double event
      expect(core.freed, [1]);
      await manager.dispose();
    });

    test('restart picks a fresh port and keeps the persistent data dir',
        () async {
      final core = _FakeCore();
      final manager = _manager(core, _FakeProbe());
      await manager.start();
      await manager.stop();
      final second = await manager.restart();
      expect(core.startedArgs.length, 2);
      String dirOf(List<String> args) =>
          args[args.indexOf('--psiphon-dir') + 1];
      expect(dirOf(core.startedArgs[0]), dirOf(core.startedArgs[1]),
          reason: 'the stable bootstrap data dir persists across '
              'restarts (psiphon keeps its learned server list)');
      int portOf(List<String> args) =>
          int.parse(args[args.indexOf('--bind') + 1].split(':').last);
      expect(portOf(core.startedArgs[0]), isNot(equals(second.port)),
          reason: 'a restart re-picks the ephemeral port');
      await manager.dispose();
    });

    test('a core crash while ready flips the state via the health ticker',
        () async {
      final core = _FakeCore();
      final manager = _manager(core, _FakeProbe(),
          healthInterval: const Duration(milliseconds: 30));
      final failures = <PsiphonBootstrapEvent>[];
      final sub = manager.events.listen((e) {
        if (e.state == PsiphonBootstrapState.failed) failures.add(e);
      });
      await manager.start();
      expect(manager.state, PsiphonBootstrapState.ready);

      // The core job dies on its own (the pinned psiphon child stopping
      // ends the run_only future, which ends the job with an error).
      core.jobs.single.error = 'psiphon stopped: exit status 1';

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(manager.state, PsiphonBootstrapState.failed);
      expect(manager.lastFailureCode, 'coreDied');
      expect(failures, isNotEmpty);
      expect(failures.last.errorCode, 'coreDied');
      expect(failures.last.message, contains('psiphon stopped'));
      await sub.cancel();
      await manager.dispose();
    });

    test('healthCheck: full probe on demand; false never lies', () async {
      final core = _FakeCore();
      final probe = _FakeProbe();
      final manager = _manager(core, probe);
      expect(await manager.healthCheck(), isFalse,
          reason: 'not ready → false, never a fake pass');
      await manager.start();
      expect(await manager.healthCheck(), isTrue);
      expect(probe.calls, greaterThanOrEqualTo(2));
      // A degraded probe answers false WITHOUT failing the manager —
      // the caller (Stage 4/6) owns the policy.
      probe.failFromNowOn();
      expect(await manager.healthCheck(), isFalse);
      expect(manager.state, PsiphonBootstrapState.ready);
      await manager.dispose();
    });

    test('dispose closes the event stream; use after dispose is honest',
        () async {
      final core = _FakeCore();
      final manager = _manager(core, _FakeProbe());
      await manager.start();
      final done = Completer<void>();
      final sub = manager.events.listen((_) {}, onDone: done.complete);
      await manager.dispose();
      await done.future.timeout(const Duration(seconds: 2));
      expect(manager.state, PsiphonBootstrapState.idle);
      expect(core.freed, isNotEmpty);
      expect(
        () => manager.start(),
        throwsA(
          isA<PsiphonBootstrapException>()
              .having((e) => e.code, 'code', 'disposed'),
        ),
      );
      // Callbacks after dispose must never crash (mission §2-7):
      await manager.stop(); // no-op, no throw
      await sub.cancel();
    });
  });

  group('chain argument build (stage 3 — evidence-locked to the pin)', () {
    test('the EXISTING combination, launched on dedicated ephemeral ports',
        () {
      final args = PsiphonBootstrapProxy.buildChainArgs(
        bindPort: 45678,
        psiphonBindPort: 45679,
        filesDir: '/data/app/files',
        nativeLibraryDir: '/data/app/lib/arm64',
      );
      // The WARP-leg listener (psiphon's upstream — never dialed by
      // AETHONE) and the CHAIN EGRESS (the usable endpoint).
      expect(args, containsAllInOrder(['--bind', '127.0.0.1:45678']));
      expect(
          args, containsAllInOrder(['--psiphon-bind', '127.0.0.1:45679']));
      // THE chain flag — the project's existing combination, launched
      // verbatim (cli.rs: plain --psiphon; the core's own mode() test
      // spellings «1/on/chain/yes» all map to Chain).
      expect(args, contains('--psiphon'));
      expect(args, isNot(contains('--psiphon-only')));
      expect(args, isNot(contains('--psiphon-reverse')));
      // The WARP identity defaults to the walk's own file (reuse — the
      // core never re-registers an identity that is already there).
      expect(
        args,
        containsAllInOrder(['--config', '/data/app/files/aether/warp.toml']),
      );
      // The walk's own determinism pins for the WARP leg.
      expect(args, containsAllInOrder(['--scan', 'turbo']));
      expect(args, contains('--quick-reconnect'));
      expect(args, containsAllInOrder(['--protocol', 'wg']));
      expect(
        args,
        containsAllInOrder(
            ['--psiphon-bin', '/data/app/lib/arm64/libpsiphon.so']),
      );
      // The DEDICATED bootstrap data dir (NOT the user modes' one).
      expect(
        args,
        containsAllInOrder(
            ['--psiphon-dir', '/data/app/files/aether/psiphon-bootstrap']),
      );
      expect(args, containsAllInOrder(['--log-level', 'info']));
    });

    test('custom WARP identity, scan profile and leg are honored', () {
      final args = PsiphonBootstrapProxy.buildChainArgs(
        bindPort: 45678,
        psiphonBindPort: 45679,
        filesDir: '/f',
        nativeLibraryDir: '/l',
        warpConfigPath: '/f/aether/warp-alt.toml',
        scanProfile: 'verified',
        warpProtocol: ProtocolId.mim,
      );
      expect(
          args, containsAllInOrder(['--config', '/f/aether/warp-alt.toml']));
      expect(args, containsAllInOrder(['--scan', 'verified']));
      expect(args, containsAllInOrder(['--protocol', 'mim']));
    });

    test('a scan profile outside the pinned five is rejected', () {
      expect(
        () => PsiphonBootstrapProxy.buildChainArgs(
          bindPort: 1,
          psiphonBindPort: 2,
          filesDir: '/f',
          nativeLibraryDir: '/l',
          scanProfile: 'ultra',
        ),
        throwsArgumentError,
      );
    });

    test('no upstream, no loop-bending flags, no shape/region pin', () {
      final args = PsiphonBootstrapProxy.buildChainArgs(
        bindPort: 45678,
        psiphonBindPort: 45679,
        filesDir: '/f',
        nativeLibraryDir: '/l',
      );
      // Loop prevention: never an --upstream (run_chain sets psiphon's
      // upstream itself, to exactly --bind; an upstream could only bend
      // the chain back on itself).
      expect(args, isNot(contains('--upstream')));
      expect(args, isNot(contains('--psiphon-http')));
      expect(args, isNot(contains('--psiphon-region')));
      expect(args, isNot(contains('--psiphon-mode')));
      expect(args, isNot(contains('--exit-loc')));
      expect(args, isNot(contains('-4')));
      expect(args, isNot(contains('-6')));
      expect(args, isNot(contains('--dual')));
    });

    test("the leg mapping IS the walk's own (equivalence-locked)", () {
      // For EVERY protocol tile, the bootstrap chain's --protocol args
      // must equal what the connect walk itself passes for a
      // psiphonChain overlay — the chain is the walk's mode, launched.
      for (final leg in ProtocolId.values) {
        expect(
          PsiphonBootstrapProxy.warpProtocolArgs(leg),
          AetherArguments.protocolArgs(leg, ProtocolId.psiphonChain),
          reason: 'leg $leg must map exactly like the walk does',
        );
      }
    });

    test('the persisted Psiphon leg setting reaches the chain protocol flag', () {
      for (final setting in AetherLegProtocol.values) {
        final selectedLeg = AetherArguments.legProtocolId(setting);
        final args = PsiphonBootstrapProxy.buildChainArgs(
          bindPort: 45678,
          psiphonBindPort: 45679,
          filesDir: '/f',
          nativeLibraryDir: '/l',
          warpProtocol: selectedLeg,
        );
        expect(
          args,
          containsAllInOrder(
            AetherArguments.protocolArgs(selectedLeg, ProtocolId.psiphonChain),
          ),
          reason: 'the bootstrap chain must use the user-selected $setting leg',
        );
      }
      final masque = AetherArguments.legProtocolId(AetherLegProtocol.masque);
      final masqueArgs = PsiphonBootstrapProxy.buildChainArgs(
        bindPort: 45678,
        psiphonBindPort: 45679,
        filesDir: '/f',
        nativeLibraryDir: '/l',
        warpProtocol: masque,
      );
      expect(masqueArgs, containsAllInOrder(['--protocol', 'masque']));
    });

    test('two distinct loopback ports, never the pinned map', () async {
      for (var i = 0; i < 4; i++) {
        final (bind, egress) =
            await PsiphonBootstrapProxy.pickTwoDistinctLoopbackPorts();
        expect(bind, isNot(egress),
            reason: 'the egress and the WARP upstream must never share '
                'a socket');
        expect(kPinnedAethonePorts.contains(bind), isFalse);
        expect(kPinnedAethonePorts.contains(egress), isFalse);
      }
    });

    test('chain default budget = the walk\'s two phases summed (330 s); '
        'an explicit override wins; standalone stays 210 s', () {
      PsiphonBootstrapProxy neverStarted({
        PsiphonBootstrapMode? mode,
        Duration? budget,
      }) =>
          PsiphonBootstrapProxy(
            filesDir: '/f',
            nativeLibraryDir: '/l',
            mode: mode ?? PsiphonBootstrapMode.psiphonOnly,
            coreFactory: () => throw StateError('never started'),
            readyBudget: budget,
          );

      expect(
          neverStarted(mode: PsiphonBootstrapMode.aetherPsiphonChain)
              .effectiveReadyBudget,
          const Duration(seconds: 330));
      expect(
          neverStarted(
            mode: PsiphonBootstrapMode.aetherPsiphonChain,
            budget: const Duration(seconds: 90),
          ).effectiveReadyBudget,
          const Duration(seconds: 90));
      expect(neverStarted().effectiveReadyBudget,
          const Duration(seconds: 210));
    });
  });

  group('chain manager lifecycle (fake core + probe seam)', () {
    test('chain start hands the core BOTH concrete ports and probes the '
        'EGRESS only', () async {
      final core = _FakeCore();
      final probe = _FakeProbe(failFirst: 1);
      final manager = _chainManager(core, probe);
      final endpoint = await manager.start().timeout(const Duration(seconds: 5));
      final args = core.startedArgs.single;
      final bindPort =
          int.parse(args[args.indexOf('--bind') + 1].split(':').last);
      final egressPort =
          int.parse(args[args.indexOf('--psiphon-bind') + 1].split(':').last);
      expect(bindPort, isNot(egressPort));
      // The probe dialed ONLY the egress — the WARP-leg bind port is
      // the chain's internal upstream, never AETHONE's proxy target.
      expect(probe.portsSeen, isNotEmpty);
      expect(probe.portsSeen, everyElement(egressPort));
      expect(endpoint.port, egressPort);
      expect(endpoint.socksUrl, 'socks5://127.0.0.1:$egressPort');
      expect(manager.state, PsiphonBootstrapState.ready);
      await manager.stop();
    });

    test('chain singleflight: concurrent starts share ONE core job',
        () async {
      final core = _FakeCore();
      final manager = _chainManager(core, _FakeProbe());
      final results = await Future.wait([
        manager.start(),
        manager.start(),
        manager.start(),
      ]).timeout(const Duration(seconds: 5));
      expect(core.jobs.length, 1);
      expect({for (final e in results) e.port}.length, 1);
      await manager.stop();
    });

    test('chain restart: fresh distinct ports, same dedicated data dir',
        () async {
      final core = _FakeCore();
      final manager = _chainManager(core, _FakeProbe());
      final first = await manager.start().timeout(const Duration(seconds: 5));
      await manager.stop();
      final second = await manager.restart().timeout(const Duration(seconds: 5));
      expect(core.startedArgs.length, 2);
      int bindOf(List<String> a) =>
          int.parse(a[a.indexOf('--bind') + 1].split(':').last);
      int egressOf(List<String> a) =>
          int.parse(a[a.indexOf('--psiphon-bind') + 1].split(':').last);
      final a1 = core.startedArgs[0];
      final a2 = core.startedArgs[1];
      expect(bindOf(a1), isNot(egressOf(a1)));
      expect(bindOf(a2), isNot(egressOf(a2)));
      expect(first.port, isNot(second.port));
      // The psiphon data dir (its learned servers/tactics) persists
      // across restarts — never wiped, never the user modes' one.
      final dir1 = a1[a1.indexOf('--psiphon-dir') + 1];
      final dir2 = a2[a2.indexOf('--psiphon-dir') + 1];
      expect(dir1, dir2);
      expect(dir2, '/data/test/files/aether/psiphon-bootstrap');
      await manager.stop();
    });

    test('chain bind conflict during the hand-off retried on fresh ports',
        () async {
      var job = 0;
      final core = _FakeCore(onStart: (j) {
        job++;
        if (job == 1) {
          // The pinned core's frozen bind_listener wording (socks.rs):
          // either of the chain's two listeners can lose the race.
          j.error = 'the psiphon socks5 listener cannot use '
              '127.0.0.1:44444: another program already listens there';
        }
      });
      final manager = _chainManager(core, _FakeProbe());
      final endpoint = await manager.start().timeout(const Duration(seconds: 5));
      expect(core.startedArgs.length, 2);
      expect(manager.state, PsiphonBootstrapState.ready);
      expect(endpoint.port, greaterThan(0));
      await manager.stop();
    });

    test('chain core failure is coreExited, verbatim', () async {
      final core = _FakeCore(
          onStart: (j) => j.error = 'warp registration failed: api unreachable');
      final manager = _chainManager(core, _FakeProbe());
      await expectLater(
        manager.start(),
        throwsA(isA<PsiphonBootstrapException>()
            .having((e) => e.code, 'code', 'coreExited')
            .having((e) => e.message, 'message',
                contains('warp registration failed'))),
      );
      expect(manager.state, PsiphonBootstrapState.failed);
      expect(manager.lastFailureCode, 'coreExited');
      expect(core.cancelled, isNotEmpty);
    });

    test('stop during chain start cancels cleanly and is NOT a failure',
        () async {
      final core = _FakeCore();
      final manager = _chainManager(core, _FakeProbe.alwaysFailing());
      final starting = manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await manager.stop();
      await expectLater(
        starting,
        throwsA(isA<PsiphonBootstrapException>()
            .having((e) => e.code, 'code', 'cancelled')),
      );
      expect(manager.state, PsiphonBootstrapState.idle);
      expect(core.cancelled, isNotEmpty);
      expect(core.freed, isNotEmpty);
    });
  });

  group('chain path proof (real sockets — the Dart-side half of 3-6)', () {
    // The pinned core's half is SOURCE-LOCKED: run_chain (psiphon.rs
    // L940-968) hardcodes psiphon's UpstreamProxyURL to exactly the
    // --bind listener and relays --psiphon-bind to psiphon's internal
    // port. What this test proves is the DART-side half: traffic that
    // enters at the egress traverses EVERY intermediate hop and reaches
    // the real internet — no bypass, no loop. The full on-device proof
    // is stage 9's scenario C.
    test('LIVE: probe through the full simulated chain '
        '(egress → psiphon-sim → warp-sim → real TLS)', () async {
      // warp-sim: the WARP leg — "exits to the open internet" (direct).
      final warpSim = await _DirectSocksRelay.start();
      // psiphon-sim: dials its targets THROUGH the warp leg, exactly
      // like the real psiphon does under UpstreamProxyURL=socks5://<bind>.
      final psiphonSim =
          await _DirectSocksRelay.start(upstreamSocksPort: warpSim.port);
      // egress: the core's byte-for-byte relay (socks::forward stand-in)
      // from --psiphon-bind to psiphon's internal listener.
      final egress = await _RawForwarder.start(toPort: psiphonSim.port);
      try {
        await const SocksTlsReadyProbe().verify(
          port: egress.port,
          timeout: const Duration(seconds: 25),
        );
        // Reaching here means: SOCKS5 greeting OK, DOMAIN CONNECT OK,
        // TLS verified against the real trust store, and an HTTP 2xx/3xx
        // status came back — THROUGH the whole simulated chain.
        // The DOMAIN CONNECT survived both hops (remote-DNS semantics
        // end-to-end) and every hop SAW the traffic (no bypass):
        expect(warpSim.lastConnectedHost, 'www.cloudflare.com');
        expect(warpSim.lastConnectWasDomain, isTrue);
        expect(psiphonSim.lastConnectedHost, 'www.cloudflare.com');
        expect(psiphonSim.connections, greaterThanOrEqualTo(1));
        expect(warpSim.connections, greaterThanOrEqualTo(1));
        expect(egress.connections, greaterThanOrEqualTo(1));
      } finally {
        await egress.dispose();
        await psiphonSim.dispose();
        await warpSim.dispose();
      }
    }, skip: liveNet ? false : 'no direct network access from this machine');
  });
}

// ---- test doubles -----------------------------------------------------------

PsiphonBootstrapProxy _manager(
  _FakeCore core,
  PsiphonReadyProbe probe, {
  Duration? readyBudget,
  Duration? healthInterval,
}) =>
    PsiphonBootstrapProxy(
      filesDir: '/data/test/files',
      nativeLibraryDir: '/data/test/lib/arm64',
      coreFactory: () => core,
      probe: probe,
      readyBudget: readyBudget ?? const Duration(seconds: 5),
      probeTimeout: const Duration(milliseconds: 40),
      probeRetryInterval: const Duration(milliseconds: 10),
      healthInterval: healthInterval ?? const Duration(seconds: 15),
      cancelGrace: const Duration(milliseconds: 300),
      portFreeBudget: const Duration(milliseconds: 300),
    );

/// The stage-3 flavor of [_manager]: same seams, CHAIN mode.
PsiphonBootstrapProxy _chainManager(
  _FakeCore core,
  PsiphonReadyProbe probe, {
  Duration? readyBudget,
}) =>
    PsiphonBootstrapProxy(
      filesDir: '/data/test/files',
      nativeLibraryDir: '/data/test/lib/arm64',
      mode: PsiphonBootstrapMode.aetherPsiphonChain,
      coreFactory: () => core,
      probe: probe,
      readyBudget: readyBudget ?? const Duration(seconds: 5),
      probeTimeout: const Duration(milliseconds: 40),
      probeRetryInterval: const Duration(milliseconds: 10),
      healthInterval: const Duration(seconds: 15),
      cancelGrace: const Duration(milliseconds: 300),
      portFreeBudget: const Duration(milliseconds: 300),
    );

/// Fake embedded core: records every argument list, one job per start.
class _FakeCore implements AetherCoreApi {
  _FakeCore({this.onStart});

  /// Per-start behavior hook (fail the first job, mark it done, …).
  final void Function(_FakeJob job)? onStart;
  final List<_FakeJob> jobs = [];
  final List<int> cancelled = [];
  final List<int> freed = [];
  final List<List<String>> startedArgs = [];

  @override
  int coreStart(List<String> args) {
    final job = _FakeJob(args);
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
    cancelled.add(id);
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
    freed.add(id);
    return true;
  }
}

class _FakeJob {
  _FakeJob(this.args);

  final List<String> args;
  bool done = false;
  String? error;
  Map<String, Object?>? result;
}

/// Fake probe seam: fails the first [failFirst] calls, then passes;
/// [alwaysFailing] / [failFromNowOn] model a never-ready / degraded
/// tunnel.
class _FakeProbe implements PsiphonReadyProbe {
  _FakeProbe({this.failFirst = 0});

  factory _FakeProbe.alwaysFailing() => _FakeProbe(failFirst: 1 << 30);

  int failFirst;
  int calls = 0;
  final List<int> portsSeen = [];

  void failFromNowOn() => failFirst = (1 << 30) + calls + 1;

  @override
  Future<void> verify({required int port, required Duration timeout}) async {
    portsSeen.add(port);
    calls++;
    if (calls <= failFirst) {
      throw const SocketException('the tunnel is not ready yet');
    }
  }
}

/// One-shot direct reachability check for the LIVE probe test's skip
/// gate (4 s budget; destroys the probe socket immediately).
Future<bool> _canReachTraceHost() async {
  try {
    final socket = await Socket.connect(
      'www.cloudflare.com',
      443,
      timeout: const Duration(seconds: 4),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// A REAL SOCKS5 server that forwards each CONNECT to the real target
/// DIRECTLY (no tunnel): the stand-in "psiphon" for the LIVE probe test.
/// It speaks the exact wire protocol the pinned core's relay serves, so
/// the probe's handshake, domain CONNECT and TLS layers all run for real.
/// The client-side reader is NEVER re-subscribed (dart:io socket streams
/// are single-subscription): the same StreamIterator reads the handshake
/// and then pumps client→upstream for the tunnel's lifetime.
///
/// Stage 3: [upstreamSocksPort] turns it into the CHAIN's "psiphon" —
/// every target is then dialed THROUGH the SOCKS5 upstream at that port
/// (exactly what the real psiphon does under run_chain's
/// UpstreamProxyURL=socks5://<--bind>), with the SAME single-reader
/// discipline on the upstream socket.
class _DirectSocksRelay {
  _DirectSocksRelay._(this._server, {this.upstreamSocksPort});

  final ServerSocket _server;
  final List<Socket> _clients = [];
  final List<Socket> _upstreams = [];
  final List<StreamSubscription<Socket>> _accepts = [];

  /// When set: dial every CONNECT through this SOCKS5 port instead of
  /// directly (the chain's psiphon leg).
  final int? upstreamSocksPort;

  String? lastConnectedHost;
  bool lastConnectWasDomain = false;
  int connections = 0;

  int get port => _server.port;

  static Future<_DirectSocksRelay> start({int? upstreamSocksPort}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _DirectSocksRelay._(server, upstreamSocksPort: upstreamSocksPort);
    relay._accepts.add(server.listen(
      (socket) => relay._handle(socket),
      onError: (Object _) {},
    ));
    return relay;
  }

  Future<void> dispose() async {
    await _server.close();
    for (final s in _accepts) {
      await s.cancel();
    }
    for (final s in _clients) {
      s.destroy();
    }
    for (final s in _upstreams) {
      s.destroy();
    }
  }

  Future<void> _handle(Socket client) async {
    _clients.add(client);
    connections++;
    final reader = StreamIterator<Uint8List>(client);
    final buffer = <int>[];
    var handedOff = false;
    try {
      // --- greeting [VER NMETHODS METHODS...] → [VER METHOD=00] ---
      // (the probe sends exactly [05 01 00])
      while (buffer.length < 3) {
        if (!await reader.moveNext()) return;
        buffer.addAll(reader.current);
      }
      if (buffer[0] != 0x05) return;
      client.add(const <int>[0x05, 0x00]);
      await client.flush();
      buffer.removeRange(0, 3);

      // --- CONNECT request, buffered until fully parseable ---
      (String, int, bool)? connect;
      while (connect == null) {
        connect = _takeConnect(buffer);
        if (connect == null) {
          if (!await reader.moveNext()) return;
          buffer.addAll(reader.current);
        }
      }
      final (host, port, wasDomain) = connect;
      lastConnectedHost = host;
      lastConnectWasDomain = wasDomain;

      final warpPort = upstreamSocksPort;
      if (warpPort != null) {
        // The chain's psiphon leg: dial the target THROUGH the SOCKS5
        // upstream at 127.0.0.1:warpPort (run_chain:
        // UpstreamProxyURL=socks5://<--bind>), then relay both ways.
        final upstream = await Socket.connect('127.0.0.1', warpPort,
            timeout: const Duration(seconds: 10));
        _upstreams.add(upstream);
        final upReader = StreamIterator<Uint8List>(upstream);
        final pending = BytesBuilder();
        try {
          // --- greeting [VER NMETHODS METHODS...] → [VER METHOD=00] ---
          upstream.add(const <int>[0x05, 0x01, 0x00]);
          final greet = await _readExact(upReader, pending, 2);
          if (greet[0] != 0x05 || greet[1] != 0x00) {
            throw const SocketException('upstream socks5 greeting refused');
          }
          final name = ascii.encode(host);
          upstream.add(<int>[
            0x05, 0x01, 0x00, 0x03, name.length, ...name, port >> 8,
            port & 0xff,
          ]);
          final head = await _readExact(upReader, pending, 4);
          if (head[0] != 0x05 || head[1] != 0x00) {
            throw const SocketException('upstream socks5 CONNECT failed');
          }
          final skip = switch (head[3]) {
            0x01 => 4,
            0x03 => (await _readExact(upReader, pending, 1))[0],
            0x04 => 16,
            _ => 4,
          };
          if (skip > 0) await _readExact(upReader, pending, skip);
          await _readExact(upReader, pending, 2);
        } catch (_) {
          upstream.destroy();
          return;
        }
        client.add(
            const <int>[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await client.flush();
        handedOff = true;
        if (buffer.isNotEmpty) {
          upstream.add(buffer);
          await upstream.flush();
        }
        unawaited(_pumpReader(reader, upstream));
        unawaited(_pumpIterator(upReader, client));
        return;
      }

      final upstream = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));
      _upstreams.add(upstream);
      client.add(
          const <int>[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await client.flush();
      handedOff = true;

      // Bytes the client pipelined behind the CONNECT (an early TLS
      // ClientHello) belong to the tunnel — forward them first.
      if (buffer.isNotEmpty) {
        upstream.add(buffer);
        await upstream.flush();
      }
      // The SAME iterator keeps reading the client side (never a second
      // subscription); the upstream side is a fresh plain stream.
      unawaited(_pumpReader(reader, upstream));
      unawaited(_pumpStream(upstream, client));
    } catch (_) {
      // listener-check connections (connect + destroy) land here — fine
    } finally {
      if (!handedOff) {
        await reader.cancel();
        client.destroy();
      }
    }
  }

  /// Client → upstream through the handshake's own iterator.
  Future<void> _pumpReader(
      StreamIterator<Uint8List> reader, Socket to) async {
    try {
      while (await reader.moveNext()) {
        to.add(reader.current);
        await to.flush();
      }
    } catch (_) {
      // a probe that destroyed its side lands here — fine
    } finally {
      to.destroy();
    }
  }

  /// Upstream → client over the upstream's own (never-subscribed) stream.
  Future<void> _pumpStream(Socket from, Socket to) async {
    try {
      await for (final chunk in from) {
        to.add(chunk);
        await to.flush();
      }
    } catch (_) {
      // half-close on error is fine for a probe
    } finally {
      to.destroy();
    }
  }

  /// Upstream → client through the SOCKS-dial path's own iterator (the
  /// single subscription on that socket — same discipline as
  /// [_pumpReader], mirrored for the upstream side).
  Future<void> _pumpIterator(StreamIterator<Uint8List> from, Socket to) async {
    try {
      while (await from.moveNext()) {
        to.add(from.current);
        await to.flush();
      }
    } catch (_) {
      // a probe that destroyed its side lands here — fine
    } finally {
      to.destroy();
    }
  }

  /// Chunk-safe exact read for the SOCKS-dial handshake: buffers into
  /// [pending] so a short chunk never splits a field.
  static Future<List<int>> _readExact(
    StreamIterator<Uint8List> iterator,
    BytesBuilder pending,
    int count,
  ) async {
    while (pending.length < count) {
      if (!await iterator.moveNext()) {
        throw const SocketException('upstream closed mid-handshake');
      }
      pending.add(iterator.current);
    }
    final all = pending.takeBytes();
    final rest = all.length - count;
    if (rest > 0) {
      pending.add(all.sublist(count));
    }
    return all.sublist(0, count);
  }

  /// Parses + REMOVES one complete CONNECT request from [buffer]; null
  /// while incomplete. Returns (host, port, wasDomain).
  (String, int, bool)? _takeConnect(List<int> buffer) {
    if (buffer.length < 5) return null;
    final atyp = buffer[3];
    int need;
    switch (atyp) {
      case 0x01:
        need = 10;
      case 0x03:
        // VER(1)+CMD(1)+RSV(1)+ATYP(1)+LEN(1)+name(len)+port(2) = 7+len.
        need = 7 + buffer[4];
      case 0x04:
        need = 22;
      default:
        return null; // unsupported — drop
    }
    if (buffer.length < need) return null;
    String host;
    var wasDomain = false;
    if (atyp == 0x03) {
      final len = buffer[4];
      host = ascii.decode(buffer.sublist(5, 5 + len));
      wasDomain = true;
    } else {
      host = buffer.sublist(4, 8).join('.');
    }
    final port = (buffer[need - 2] << 8) | buffer[need - 1];
    buffer.removeRange(0, need);
    return (host, port, wasDomain);
  }
}

/// The pinned core's socks::forward stand-in (the chain's egress relay):
/// binds loopback and passes every accepted socket BYTE-FOR-BYTE to
/// 127.0.0.1:toPort — no protocol of its own, exactly like the core's
/// relay from --psiphon-bind to psiphon's internal listener.
class _RawForwarder {
  _RawForwarder._(this._server, this.toPort);

  final ServerSocket _server;
  final int toPort;
  final List<Socket> _clients = [];
  final List<Socket> _upstreams = [];
  final List<StreamSubscription<Socket>> _accepts = [];
  int connections = 0;

  int get port => _server.port;

  static Future<_RawForwarder> start({required int toPort}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final forwarder = _RawForwarder._(server, toPort);
    forwarder._accepts.add(server.listen(
      (socket) => forwarder._handle(socket),
      onError: (Object _) {},
    ));
    return forwarder;
  }

  Future<void> dispose() async {
    await _server.close();
    for (final s in _accepts) {
      await s.cancel();
    }
    for (final s in _clients) {
      s.destroy();
    }
    for (final s in _upstreams) {
      s.destroy();
    }
  }

  Future<void> _handle(Socket client) async {
    connections++;
    _clients.add(client);
    try {
      final upstream = await Socket.connect('127.0.0.1', toPort,
          timeout: const Duration(seconds: 10));
      _upstreams.add(upstream);
      unawaited(_pump(client, upstream));
      unawaited(_pump(upstream, client));
    } catch (_) {
      client.destroy();
    }
  }

  Future<void> _pump(Socket from, Socket to) async {
    try {
      await for (final chunk in from) {
        to.add(chunk);
        await to.flush();
      }
    } catch (_) {
      // a probe that destroyed its side lands here — fine
    } finally {
      to.destroy();
    }
  }
}
