// STAGE 2 (Guardian bootstrap mission) tests: the standalone Psiphon
// local proxy manager (lib/connection/firefox/psiphon_bootstrap.dart).
//
// What is real here:
//  * the argument build is asserted against the PINNED core's semantics
//    (psiphon-only mode; no chain/upstream/region/protocol pinning);
//  * the port allocation, the SOCKS5+TLS readiness probe and the
//    «an open port is NOT ready» rule run against REAL dart:io sockets;
//  * the LIVE probe test drives the full real handshake (SOCKS5 →
//    domain CONNECT → verified TLS → HTTP trace) through a local
//    direct-forwarding SOCKS5 relay to the real trace host — skipped
//    honestly when this machine is offline;
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
class _DirectSocksRelay {
  _DirectSocksRelay._(this._server);

  final ServerSocket _server;
  final List<Socket> _clients = [];
  final List<Socket> _upstreams = [];
  final List<StreamSubscription<Socket>> _accepts = [];

  String? lastConnectedHost;
  bool lastConnectWasDomain = false;

  int get port => _server.port;

  static Future<_DirectSocksRelay> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _DirectSocksRelay._(server);
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
