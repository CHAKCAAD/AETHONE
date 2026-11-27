// Family Shield phase 2.1 — the app side of the loopback gate:
//  * AetherArguments carries `--loopback-gate <file>` only when the walk armed
//    a session (never the secret itself);
//  * TunnelProbe.socksConnect authenticates with the session credentials when
//    a listener demands RFC 1929, and still works against a no-auth listener.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aethone/core/app_assets.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/connection/tunnel_probe.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-connection SOCKS5 server: [requireAuth] demands RFC 1929 with
/// aethone/[secret]; records what the client offered and sent.
class _AuthServer {
  _AuthServer({required this.requireAuth, required this.secret});
  final bool requireAuth;
  final String secret;
  late ServerSocket server;
  List<int> offered = const [];
  String? userSeen;
  bool authOk = false;

  Future<int> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) async {
      final buf = BytesBuilder();
      final it = StreamIterator<Uint8List>(s);
      Future<List<int>> need(int n) async {
        while (buf.length < n) {
          if (!await it.moveNext()) throw const SocketException('eof');
          buf.add(it.current);
        }
        final all = buf.takeBytes();
        buf.add(all.sublist(n));
        return all.sublist(0, n);
      }

      try {
        final head = await need(2);
        offered = await need(head[1]);
        if (requireAuth) {
          if (!offered.contains(2)) {
            s.add(const [5, 0xff]);
            await s.close();
            return;
          }
          s.add(const [5, 2]);
          final h = await need(2);
          final user = ascii.decode(await need(h[1]));
          final pl = (await need(1))[0];
          final pass = ascii.decode(await need(pl));
          userSeen = user;
          authOk = user == 'aethone' && pass == secret;
          s.add([1, authOk ? 0 : 1]);
          if (!authOk) {
            await s.close();
            return;
          }
        } else {
          s.add(const [5, 0]);
        }
        final req = await need(5);
        await need(req[4] + 2);
        s.add(const [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
        await s.flush();
      } catch (_) {
        s.destroy();
      }
    });
    return server.port;
  }
}

void main() {
  tearDown(() => TunnelProbe.sessionCredentials = null);

  test('AetherArguments: --loopback-gate only when a session is armed', () {
    final plain = AetherArguments.build(
      protocol: ProtocolId.masque,
      filesDir: '/f',
      nativeLibraryDir: '/l',
    );
    expect(plain.contains('--loopback-gate'), isFalse);
    final gated = AetherArguments.build(
      protocol: ProtocolId.masque,
      filesDir: '/f',
      nativeLibraryDir: '/l',
      loopbackGateFile: '/f/nobackup/loopback-gate/secret',
    );
    final i = gated.indexOf('--loopback-gate');
    expect(i, greaterThanOrEqualTo(0));
    expect(gated[i + 1], '/f/nobackup/loopback-gate/secret');
    // everything else is identical to the ungated list
    expect(gated.sublist(0, i), plain);
  });

  test('socksConnect authenticates when the listener demands it', () async {
    final secret = 'ab' * 32;
    final srv = _AuthServer(requireAuth: true, secret: secret);
    final port = await srv.start();
    TunnelProbe.sessionCredentials = SocksCredentials('aethone', secret);
    final t = await TunnelProbe.socksConnect(
      port: port,
      host: 'www.cloudflare.com',
      dstPort: 80,
      timeout: const Duration(seconds: 5),
    );
    t.socket.destroy();
    expect(srv.offered, [0, 2]);
    expect(srv.authOk, isTrue);
    await srv.server.close();
  });

  test('without credentials an auth-only listener is refused', () async {
    final srv = _AuthServer(requireAuth: true, secret: 'cd' * 32);
    final port = await srv.start();
    await expectLater(
      TunnelProbe.socksConnect(
        port: port,
        host: 'www.cloudflare.com',
        dstPort: 80,
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<SocketException>()),
    );
    expect(srv.offered, [0]);
    await srv.server.close();
  });

  test('wrong credentials are refused', () async {
    final srv = _AuthServer(requireAuth: true, secret: 'cd' * 32);
    final port = await srv.start();
    TunnelProbe.sessionCredentials = SocksCredentials('aethone', 'ab' * 32);
    await expectLater(
      TunnelProbe.socksConnect(
        port: port,
        host: 'www.cloudflare.com',
        dstPort: 80,
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<SocketException>()),
    );
    expect(srv.authOk, isFalse);
    await srv.server.close();
  });

  test('credentials offered to a no-auth listener (Aether own-process) still connect', () async {
    final srv = _AuthServer(requireAuth: false, secret: '');
    final port = await srv.start();
    TunnelProbe.sessionCredentials = SocksCredentials('aethone', 'ab' * 32);
    final t = await TunnelProbe.socksConnect(
      port: port,
      host: 'www.cloudflare.com',
      dstPort: 80,
      timeout: const Duration(seconds: 5),
    );
    t.socket.destroy();
    expect(srv.offered, [0, 2]);
    expect(srv.userSeen, isNull);
    await srv.server.close();
  });
}
