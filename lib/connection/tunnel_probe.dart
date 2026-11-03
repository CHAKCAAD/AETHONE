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
  });

  /// RTT of the trace request THROUGH the tunnel (request written → first
  /// response byte received).
  final int pingMs;

  /// Exit country (ISO-3166 alpha-2, lowercase — the UI's flag code).
  final String exitCountryCode;

  final String? exitIp;

  /// `warp=on` in the trace body (WARP-family exits).
  final bool warp;
}

/// SOCKS5 + cloudflare-trace probe over `dart:io`. The CONNECT target is
/// resolved BY THE CORE (ATYP=domain) — no local DNS is used.
class TunnelProbe {
  /// Same host the pinned core uses for its own exit detection
  /// (aether/src/exitloc.rs TRACE_HOST / TRACE_PATH).
  static const String traceHost = 'www.cloudflare.com';
  static const int tracePort = 80;

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

  /// Full end-to-end probe. Throws on ANY failure — the caller decides how to
  /// surface it (connect failure vs health-probe failure).
  Future<TunnelProbeResult> trace({
    required int port,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: timeout,
    );
    try {
      final reader = _SocketReader(socket, timeout);

      // --- SOCKS5 greeting: one no-auth method ---
      socket.add(<int>[0x05, 0x01, 0x00]);
      final greet = await reader.read(2);
      if (greet[0] != 0x05 || greet[1] != 0x00) {
        throw const SocketException('socks5 greeting refused');
      }

      // --- CONNECT (ATYP=domain; the CORE resolves it through the tunnel) ---
      final name = ascii.encode(traceHost);
      socket.add(<int>[
        0x05, 0x01, 0x00, 0x03, name.length, ...name, tracePort >> 8,
        tracePort & 0xff,
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

      // --- HTTP trace through the tunnel ---
      final started = DateTime.now();
      socket.add(
        ascii.encode(
          'GET /cdn-cgi/trace HTTP/1.1\r\n'
          'Host: $traceHost\r\n'
          'User-Agent: aethone-probe/1\r\n'
          'Connection: close\r\n'
          '\r\n',
        ),
      );
      final raw = await reader.readAll();
      final ping = DateTime.now().difference(started).inMilliseconds;
      return parseBody(utf8.decode(raw), ping);
    } finally {
      socket.destroy();
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
    return TunnelProbeResult(
      pingMs: pingMs,
      exitCountryCode: loc.toLowerCase(),
      exitIp: fields['ip'],
      warp: fields['warp'] == 'on',
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

/// Sequential chunk-safe socket reader: one [StreamIterator] for the whole
/// exchange with an internal leftover buffer — bytes beyond a read are never
/// dropped.
class _SocketReader {
  _SocketReader(Socket socket, this._timeout)
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
}
