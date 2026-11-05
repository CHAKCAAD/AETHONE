/// The end-to-end tunnel probe (prompt §6.6): `Connected` may only be emitted
/// after a REAL request succeeded through the tunnel. This file implements
/// that probe against Aether's local SOCKS5 listener with zero dependencies
/// (raw `dart:io` sockets):
///
///  1. TCP connect to `127.0.0.1:<port>` — proves the core's listener is up;
///  2. SOCKS5 greeting (method 0x00 — Aether answers no-auth either way) and
///     CONNECT with ATYP=domain for `www.cloudflare.com:80` — the exact host
///     the core itself uses for exit detection (exitloc.rs TRACE_HOST);
///  3. `GET /cdn-cgi/trace` — the response carries `loc=XX` (the exit
///     country) and the round trip gives a REAL ping measurement.
///
/// Nothing here is ever fabricated: a failed probe is a failed probe.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Result of one successful end-to-end probe.
class TunnelProbeResult {
  const TunnelProbeResult({
    required this.pingMs,
    required this.exitCountryCode,
    required this.exitIp,
    this.warp = false,
    this.countryIsPseudo = false,
  });

  /// RTT of the trace request THROUGH the tunnel (request written → first
  /// response byte received).
  final int pingMs;

  /// Exit country (ISO-3166 alpha-2, lowercase — the UI's flag code), OR
  /// one of [TunnelProbe.pseudoCountryCodes] verbatim when the trace
  /// answered with a GeoIP pseudo-country (see [countryIsPseudo]).
  final String exitCountryCode;

  final String? exitIp;

  /// `warp=on` in the trace body (WARP-family exits).
  final bool warp;

  /// v4.31 — true when `loc=` was a GeoIP PSEUDO-country, not a real
  /// ISO-3166 code (owner round 7: connected through a Tor exit in
  /// Austria, the header showed no flag and the raw name «T1»):
  ///  * 'T1' — the Tor network. Cloudflare's own continental field table
  ///    says it outright ("T1": Tor network — developers.cloudflare.com,
  ///    ip.src.continent values) and `/cdn-cgi/trace` answers `loc=T1`
  ///    for every Tor exit; the community has measured it on the wire
  ///    (community.cloudflare.com «How to block all traffic from Tor»;
  ///    seclists nmap-dev http-fingerprints.lua). A Tor exit in Austria
  ///    still answers T1 — the REAL country is only recoverable from the
  ///    exit relay's directory data (Onionoo `search=<ip>`, resolved
  ///    post-connect by the adapter — egress_locations.dart).
  ///  * 'A1' anonymous proxy, 'A2' satellite provider, 'O1' other country
  ///    (the MaxMind pseudo-code family Cloudflare's GeoIP feeds carry).
  /// None of these has a flag or a Persian name — displaying them raw is
  /// the bug; the UI must treat a pseudo exit as UNKNOWN until resolved.
  final bool countryIsPseudo;
}

/// SOCKS5 + cloudflare-trace probe over `dart:io`. The CONNECT target is
/// resolved BY THE CORE (ATYP=domain) — no local DNS is used.
class TunnelProbe {
  /// Same host the pinned core uses for its own exit detection
  /// (aether/src/exitloc.rs TRACE_HOST / TRACE_PATH).
  static const String traceHost = 'www.cloudflare.com';
  static const int tracePort = 80;

  /// v4.31 — the GeoIP pseudo-countries the trace can answer with INSTEAD
  /// of a real ISO-3166 code. 't1' = the Tor network (Cloudflare's own
  /// table: `"T1": Tor network`); 'a1' anonymous proxy; 'a2' satellite;
  /// 'o1' other country. See [TunnelProbeResult.countryIsPseudo].
  static const Set<String> pseudoCountryCodes = {'t1', 'a1', 'a2', 'o1'};

  /// True once the core's SOCKS5 listener accepts a TCP connection.
  static Future<bool> isListenerReady(
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: timeout,
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Waits until the listener accepts (first-run WARP registration and
  /// endpoint scanning legitimately take tens of seconds).
  static Future<bool> waitForListener(
    int port, {
    Duration timeout = const Duration(seconds: 120),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await isListenerReady(port)) return true;
      await Future<void>.delayed(interval);
    }
    return false;
  }

  /// v4.31 — the shared SOCKS5 CONNECT handshake: opens `host:dstPort`
  /// through the core's listener on `port` (greeting → CONNECT, the
  /// target resolved BY THE CORE, ATYP=domain) and returns the tunnel
  /// — the socket PLUS its single sequential reader (a dart:io socket
  /// stream is single-subscription: the handshake's reader is the ONLY
  /// one the tunnel's lifetime may ever create; [SocksTunnel.detach]
  /// hands the raw socket to TLS with the subscription released).
  /// Throws on any failure (the socket is destroyed then). Used by
  /// [trace] and by the Onionoo exit-country resolution
  /// (egress_locations.dart) alike.
  static Future<SocksTunnel> socksConnect({
    required int port,
    required String host,
    required int dstPort,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: timeout,
    );
    try {
      final reader = SocksReader(socket, timeout);

      // --- SOCKS5 greeting: one no-auth method ---
      socket.add(<int>[0x05, 0x01, 0x00]);
      final greet = await reader.read(2);
      if (greet[0] != 0x05 || greet[1] != 0x00) {
        throw const SocketException('socks5 greeting refused');
      }

      // --- CONNECT (ATYP=domain; the CORE resolves it through the tunnel) ---
      final name = ascii.encode(host);
      socket.add(<int>[
        0x05, 0x01, 0x00, 0x03, name.length, ...name, dstPort >> 8,
        dstPort & 0xff,
      ]);
      final head = await reader.read(4);
      if (head[0] != 0x05 || head[1] != 0x00) {
        throw SocketException('socks5 CONNECT failed (code ${head[1]})');
      }
      var skip = 0;
      switch (head[3]) {
        case 0x01:
          skip = 4;
        case 0x03:
          skip = (await reader.read(1))[0];
        case 0x04:
          skip = 16;
        default:
          throw SocketException('socks5 bad ATYP ${head[3]}');
      }
      if (skip > 0) await reader.read(skip);
      await reader.read(2); // bound port
      return SocksTunnel(socket, reader);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  /// Full end-to-end probe. Throws on ANY failure — the caller decides how to
  /// surface it (connect failure vs health-probe failure).
  Future<TunnelProbeResult> trace({
    required int port,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final tunnel = await socksConnect(
      port: port,
      host: traceHost,
      dstPort: tracePort,
      timeout: timeout,
    );
    try {
      // --- HTTP trace through the tunnel ---
      final started = DateTime.now();
      tunnel.socket.add(
        ascii.encode(
          'GET /cdn-cgi/trace HTTP/1.1\r\n'
          'Host: $traceHost\r\n'
          'User-Agent: aethone-probe/1\r\n'
          'Connection: close\r\n'
          '\r\n',
        ),
      );
      final raw = await tunnel.readAll();
      final ping = DateTime.now().difference(started).inMilliseconds;
      return parseBody(utf8.decode(raw), ping);
    } finally {
      tunnel.destroy();
    }
  }

  /// Parses the /cdn-cgi/trace body (`fl=…\nloc=XX\nip=…\nwarp=on…`).
  @visibleForTesting
  static TunnelProbeResult parseBody(String body, int pingMs) {
    Map<String, String> fields;
    if (body.contains('HTTP/')) {
      final split = body.indexOf('\r\n\r\n');
      if (split < 0) {
        throw const SocketException('trace response had no body');
      }
      fields = _parseKv(body.substring(split + 4));
    } else {
      fields = _parseKv(body);
    }
    final loc = fields['loc'];
    if (loc == null || loc.length != 2) {
      throw const SocketException('trace response carried no loc=');
    }
    final code = loc.toLowerCase();
    return TunnelProbeResult(
      pingMs: pingMs,
      exitCountryCode: code,
      exitIp: fields['ip'],
      warp: fields['warp'] == 'on',
      countryIsPseudo: pseudoCountryCodes.contains(code),
    );
  }

  static Map<String, String> _parseKv(String body) {
    final fields = <String, String>{};
    for (final line in body.split('\n')) {
      final eq = line.indexOf('=');
      if (eq > 0) {
        fields[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
      }
    }
    return fields;
  }
}

/// A connected SOCKS5 tunnel (v4.31): the raw socket plus THE one
/// sequential reader its stream may ever have (dart:io socket streams are
/// single-subscription — a second reader would throw "Stream has already
/// been listened to", the bug the naive shared-handshake refactor had).
class SocksTunnel {
  SocksTunnel(this.socket, SocksReader reader) : _reader = reader;

  /// The raw, connected socket (no TLS).
  final Socket socket;
  final SocksReader _reader;

  /// Reads exactly [count] bytes (buffered, chunk-safe).
  Future<List<int>> read(int count) => _reader.read(count);

  /// Reads everything until the peer closes (Connection: close).
  Future<List<int>> readAll() => _reader.readAll();

  /// Releases the stream subscription and returns the RAW socket — for
  /// wrapping the tunnel in TLS (`SecureSocket.secure`). The caller owns
  /// the descriptor from here on; [destroy] on a detached tunnel only
  /// releases the (already released) reader.
  Socket detach() {
    unawaited(_reader.cancel());
    return socket;
  }

  /// Tears the tunnel down (reader + socket). Safe after [detach].
  void destroy() {
    unawaited(_reader.cancel());
    socket.destroy();
  }
}

/// Sequential chunk-safe socket reader: one [StreamIterator] for the whole
/// exchange with an internal leftover buffer — bytes beyond a read are never
/// dropped. Public because [SocksTunnel] exposes it in its construction
/// seam (socksConnect) — the whole tunnel is one library-internal surface.
class SocksReader {
  SocksReader(Socket socket, this._timeout)
    : _iterator = StreamIterator<Uint8List>(socket);

  final Duration _timeout;
  final StreamIterator<Uint8List> _iterator;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _buffered = 0;

  Future<List<int>> read(int count) async {
    while (_buffered < count) {
      if (!await _next()) {
        throw const SocketException('socket closed mid-read');
      }
      final chunk = _iterator.current;
      _buffer.add(chunk);
      _buffered += chunk.length;
    }
    // BytesBuilder.takeBytes drains; rebuild the remainder explicitly.
    final all = _buffer.takeBytes();
    _buffered = all.length - count;
    if (_buffered > 0) {
      _buffer.add(all.sublist(count));
    }
    return all.sublist(0, count);
  }

  /// Reads everything until the peer closes (Connection: close).
  Future<List<int>> readAll() async {
    while (await _next()) {
      final chunk = _iterator.current;
      if (chunk.isNotEmpty) {
        _buffer.add(chunk);
      }
    }
    return _buffer.takeBytes();
  }

  /// `moveNext` raced against the probe timeout (this SDK's StreamIterator
  /// has no timeout parameter of its own).
  Future<bool> _next() {
    return _iterator.moveNext().timeout(_timeout, onTimeout: () {
      throw const SocketException('probe read timeout');
    });
  }

  /// v4.31 — releases the stream subscription (mandatory before the socket
  /// changes hands — e.g. into `SecureSocket.secure`); no-op when the
  /// stream already ended.
  Future<void> cancel() => _iterator.cancel();
}
