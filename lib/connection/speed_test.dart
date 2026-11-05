/// The speed test — v4.24 «صفحه تست سرعت».
///
/// Measures the REAL tunnel throughput with zero dependencies: raw
/// `dart:io` sockets speaking SOCKS5 to the core's own listener (the
/// tunnel_probe.dart recipe), then plain HTTP/1.1 keep-alive on top.
///
///  * transport — when [SpeedTestEngine.run] gets a `proxyPort`, every
///    byte goes through the core's SOCKS5 listener for the SELECTED mode
///    (the same endpoint Zeptun dials: 1819/1820/1821, transport_modes.dart);
///    `null` measures DIRECT (the honest fallback while disconnected).
///  * endpoints — verified reachable over plain HTTP :80 (2026-11-04):
///      ping      GET   speed.cloudflare.com/__down?bytes=0
///                (200, Content-Length: 0, keep-alive — a pure round trip)
///      download  GET   speed.cloudflare.com/__down?bytes=8000000
///                (200, application/octet-stream, Content-Length: N)
///      upload    POST  speed.cloudflare.com/__up
///                (200, empty body — the response only arrives after the
///                server consumed the whole request body, so its timing is
///                the true end-to-end upload time)
///  * phases: ping (8 round trips → median ping + jitter) → download
///    (adaptive 8 MB chunks on ONE keep-alive connection, ≥8 s or ≥48 MB)
///    → upload (4 MB posts, ≥8 s or ≥16 MB; the card only steps per post —
///    the server offers no intra-post progress, nothing is invented).
///
/// NOTHING is fabricated: an aborted or failed run leaves the unmeasured
/// fields null/zero and the page renders the honest empty slots.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Which phase a running test is in.
enum SpeedTestPhase { ping, download, upload }

/// One live snapshot of the run — everything the page renders.
class SpeedTestSnapshot {
  const SpeedTestSnapshot({
    this.phase,
    this.liveMbps = 0,
    this.pingMs,
    this.jitterMs,
    this.downBytes = 0,
    this.upBytes = 0,
    this.downMbps,
    this.upMbps,
    this.failed = false,
  });

  /// null ⇒ no phase active (idle or finished).
  final SpeedTestPhase? phase;

  /// The gauge value while a download/upload phase streams (Mbps).
  final double liveMbps;

  /// Median round trip (ms) — set when the ping phase completes.
  final int? pingMs;

  /// Mean |Δ| between consecutive round trips (ms).
  final int? jitterMs;

  /// Cumulative volume pulled during THIS run (ticks inside a chunk).
  final int downBytes;

  /// Cumulative volume pushed during THIS run (steps per completed post).
  final int upBytes;

  /// v4.33 (owner round 9: «کارت دانلود و آپلود باید سرعت دانلود رو نشون
  /// بدن نه میزان دانلود») — the DOWNLOAD card's speed: the live rolling
  /// Mbps while the download phase streams, then the phase's final overall
  /// average (bytes ÷ elapsed), held through upload/finish. null ⇒ never
  /// measured.
  final double? downMbps;

  /// The UPLOAD card's speed — steps per completed post (the server offers
  /// no intra-post progress), the phase's overall average at the end.
  final double? upMbps;

  /// True when the run ended in an error (measured values stay).
  final bool failed;
}

/// Drives one speed test and reports every state change through
/// [onUpdate]. Overridable so widget tests can script a run.
class SpeedTestEngine {
  SpeedTestEngine({this.onUpdate});

  /// Assigned by the page (also re-assignable in tests).
  void Function(SpeedTestSnapshot)? onUpdate;

  bool _aborted = false;
  _Tunnel? _tunnel;

  // ---- live state (mirrored into every snapshot) ----
  SpeedTestPhase? _phase;
  double _liveMbps = 0;
  int? _pingMs;
  int? _jitterMs;
  int _downBytes = 0;
  int _downBase = 0; // completed-chunk totals inside _downBytes
  int _upBytes = 0;
  double? _downMbps;
  double? _upMbps;
  bool _failed = false;
  DateTime _lastFire = DateTime.fromMillisecondsSinceEpoch(0);

  static const String _host = 'speed.cloudflare.com';
  static const int _port = 80;

  // ---- tunables (honest defaults) ----
  static const int _pingCount = 8;
  static const int _dlChunk = 8 * 1000 * 1000; // 8 MB per GET
  static const int _dlMaxBytes = 48 * 1000 * 1000;
  static const Duration _dlMinTime = Duration(seconds: 8);
  static const int _ulChunk = 4 * 1000 * 1000; // 4 MB per POST
  static const int _ulMaxBytes = 16 * 1000 * 1000;
  static const Duration _ulMinTime = Duration(seconds: 8);
  static const Duration _readTimeout = Duration(seconds: 12);
  static const Duration _connectTimeout = Duration(seconds: 12);
  static const Duration _fireThrottle = Duration(milliseconds: 100);

  /// The reusable zero-payload (cloudflare discards the body; only the
  /// length and timing matter).
  final Uint8List _ulPayload = Uint8List(_ulChunk);

  /// Aborts the in-flight run (page dispose / tap-to-stop). The sockets
  /// die immediately; [run]'s future completes with whatever was measured.
  void abort() {
    _aborted = true;
    _tunnel?.destroy();
  }

  /// One full test. `proxyPort` = the mode's SOCKS5 listener (null ⇒
  /// direct). Never throws — failures land in `failed: true`. The FIRST
  /// snapshot fires only after the tunnel is up (phase ping); the caller
  /// owns any pre-run reset — the page clears optimistically on the tap.
  Future<void> run({int? proxyPort}) async {
    _aborted = false;
    _tunnel = null;
    _phase = null;
    _liveMbps = 0;
    _pingMs = null;
    _jitterMs = null;
    _downBytes = 0;
    _downBase = 0;
    _upBytes = 0;
    _downMbps = null;
    _upMbps = null;
    _failed = false;

    _Tunnel? tunnel;
    try {
      tunnel = await _Tunnel.connect(
        proxyPort,
        _host,
        _port,
        connectTimeout: _connectTimeout,
        readTimeout: _readTimeout,
      );
      if (_aborted) return;
      _tunnel = tunnel;

      // ---- phase 1: ping + jitter ----
      _phase = SpeedTestPhase.ping;
      _liveMbps = 0;
      _fire(force: true);
      final rtts = <int>[];
      for (var i = 0; i < _pingCount && !_aborted; i++) {
        final rtt = await _roundTrip(tunnel);
        if (_aborted) return;
        rtts.add(rtt);
      }
      if (rtts.isNotEmpty) {
        final sorted = rtts.toList()..sort();
        _pingMs = sorted[sorted.length ~/ 2]; // median — outlier-proof
        var sumDelta = 0;
        for (var i = 1; i < rtts.length; i++) {
          sumDelta += (rtts[i] - rtts[i - 1]).abs();
        }
        _jitterMs = rtts.length > 1 ? (sumDelta / (rtts.length - 1)).round() : 0;
        _liveMbps = 0;
        _fire(force: true);
      }

      // ---- phase 2: download ----
      if (!_aborted) {
        _phase = SpeedTestPhase.download;
        _liveMbps = 0;
        _fire(force: true);
        final started = DateTime.now();
        while (!_aborted) {
          final got = await _downloadChunk(tunnel);
          if (_aborted) return;
          if (got <= 0) break;
          final elapsed = DateTime.now().difference(started);
          if (_downBytes >= _dlMaxBytes || elapsed >= _dlMinTime) break;
        }
        // v4.33 — the card's SPEED: the phase's final overall average
        // (bytes×8 ÷ elapsed µs = Mbps), held through the phases after it.
        final dt = DateTime.now().difference(started).inMicroseconds;
        if (_downBytes > 0 && dt > 0) {
          _downMbps = _downBytes * 8 / dt;
        }
        _liveMbps = 0;
        _fire(force: true);
      }

      // ---- phase 3: upload ----
      if (!_aborted) {
        _phase = SpeedTestPhase.upload;
        _liveMbps = 0;
        _fire(force: true);
        final started = DateTime.now();
        while (!_aborted) {
          final put = await _uploadChunk(tunnel);
          if (_aborted) return;
          if (put <= 0) break;
          final elapsed = DateTime.now().difference(started);
          if (_upBytes >= _ulMaxBytes || elapsed >= _ulMinTime) break;
        }
        // v4.33 — the upload card's final overall average.
        final dt = DateTime.now().difference(started).inMicroseconds;
        if (_upBytes > 0 && dt > 0) {
          _upMbps = _upBytes * 8 / dt;
        }
        _liveMbps = 0;
        _fire(force: true);
      }
    } on Object {
      // A read/connect timeout or a dead tunnel — the run ends with
      // whatever was honestly measured (nothing fabricated).
      if (!_aborted) _failed = true;
    } finally {
      _phase = null;
      _liveMbps = 0;
      tunnel?.destroy();
      _tunnel = null;
      _fire(force: true);
    }
  }

  /// One `GET __down?bytes=0` round trip on the shared connection.
  Future<int> _roundTrip(_Tunnel t) async {
    final t0 = DateTime.now();
    await t.request(
      'GET /__down?bytes=0 HTTP/1.1\r\n'
      'Host: $_host\r\n'
      'User-Agent: aethone-speedtest/1\r\n'
      'Connection: keep-alive\r\n'
      '\r\n',
    );
    final head = await t.readResponseHead();
    if (head.status != 200) {
      throw HttpException('ping: status ${head.status}');
    }
    await t.drainBody(head.contentLength);
    return DateTime.now().difference(t0).inMilliseconds;
  }

  /// One `GET __down?bytes=8M` chunk; ticks the cumulative counter and the
  /// live gauge (rolling 1.5 s window) as the body streams.
  Future<int> _downloadChunk(_Tunnel t) async {
    await t.request(
      'GET /__down?bytes=$_dlChunk HTTP/1.1\r\n'
      'Host: $_host\r\n'
      'User-Agent: aethone-speedtest/1\r\n'
      'Connection: keep-alive\r\n'
      '\r\n',
    );
    final head = await t.readResponseHead();
    if (head.status != 200) {
      throw HttpException('download: status ${head.status}');
    }
    final expect = head.contentLength;
    if (expect == 0) return 0;
    final windowTimes = <DateTime>[];
    final windowBytes = <int>[];
    await t.streamBody(expect, onChunk: (chunkTotal) {
      _downBytes = _downBase + chunkTotal; // cumulative card ticks live
      final now = DateTime.now();
      windowTimes.add(now);
      windowBytes.add(_downBytes);
      while (windowTimes.length > 2 &&
          now.difference(windowTimes.first) >
              const Duration(milliseconds: 1500)) {
        windowTimes.removeAt(0);
        windowBytes.removeAt(0);
      }
      final span = now.difference(windowTimes.first).inMicroseconds;
      if (span > 0) {
        _liveMbps = (windowBytes.last - windowBytes.first) / span * 8;
        // v4.33 — the speed card rides the same rolling window live.
        _downMbps = _liveMbps;
      }
      _fire();
    });
    final chunkTotal = _downBytes - _downBase;
    _downBase = _downBytes;
    _fire(force: true);
    return chunkTotal;
  }

  /// One `POST /__up` chunk (4 MB); the response lands after the server
  /// consumed the body, so its timing is the real upload time.
  Future<int> _uploadChunk(_Tunnel t) async {
    final t0 = DateTime.now();
    await t.upload(
      'POST /__up HTTP/1.1\r\n'
      'Host: $_host\r\n'
      'User-Agent: aethone-speedtest/1\r\n'
      'Content-Type: application/octet-stream\r\n'
      'Content-Length: ${_ulPayload.length}\r\n'
      'Connection: keep-alive\r\n'
      '\r\n',
      _ulPayload,
    );
    final head = await t.readResponseHead();
    if (head.status != 200) {
      throw HttpException('upload: status ${head.status}');
    }
    await t.drainBody(head.contentLength);
    final dt = DateTime.now().difference(t0);
    _upBytes += _ulPayload.length;
    if (dt.inMicroseconds > 0) {
      _liveMbps = _ulPayload.length / dt.inMicroseconds * 8;
      // v4.33 — the upload card steps per completed post.
      _upMbps = _liveMbps;
    }
    _fire(force: true);
    return _ulPayload.length;
  }

  /// Emits a snapshot (throttled unless forced).
  void _fire({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastFire) < _fireThrottle) return;
    _lastFire = now;
    onUpdate?.call(
      SpeedTestSnapshot(
        phase: _phase,
        liveMbps: _liveMbps,
        pingMs: _pingMs,
        jitterMs: _jitterMs,
        downBytes: _downBytes,
        upBytes: _upBytes,
        downMbps: _downMbps,
        upMbps: _upMbps,
        failed: _failed,
      ),
    );
  }
}

/// The response head of one HTTP exchange.
class _RespHead {
  const _RespHead(this.status, this.contentLength);
  final int status;
  final int contentLength;
}

/// A SOCKS5-tunneled (or direct) HTTP/1.1 connection with keep-alive.
class _Tunnel {
  _Tunnel._(this._socket, this._iterator, this._readTimeout);

  final Socket _socket;
  final StreamIterator<Uint8List> _iterator;
  final Duration _readTimeout;
  final BytesBuilder _leftover = BytesBuilder(copy: false);
  int _leftoverLen = 0;

  /// Opens the transport: SOCKS5 CONNECT through `proxyPort`, or a direct
  /// TCP socket when null.
  static Future<_Tunnel> connect(
    int? proxyPort,
    String host,
    int port, {
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async {
    if (proxyPort == null) {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      return _Tunnel._(socket, StreamIterator(socket), readTimeout);
    }
    final socket = await Socket.connect('127.0.0.1', proxyPort,
        timeout: connectTimeout);
    final self = _Tunnel._(socket, StreamIterator(socket), readTimeout);
    try {
      // --- SOCKS5 greeting: one no-auth method ---
      socket.add(<int>[0x05, 0x01, 0x00]);
      final greet = await self._read(2);
      if (greet[0] != 0x05 || greet[1] != 0x00) {
        throw const SocketException('socks5 greeting refused');
      }
      // --- CONNECT (ATYP=domain; the CORE resolves it through the tunnel) ---
      final name = host.codeUnits;
      socket.add(<int>[
        0x05, 0x01, 0x00, 0x03, name.length, ...name, //
        port >> 8, port & 0xff,
      ]);
      final head = await self._read(4);
      if (head[0] != 0x05 || head[1] != 0x00) {
        throw SocketException('socks5 CONNECT failed (code ${head[1]})');
      }
      var skip = 0;
      switch (head[3]) {
        case 0x01:
          skip = 4;
        case 0x03:
          skip = (await self._read(1))[0];
        case 0x04:
          skip = 16;
        default:
          throw SocketException('socks5 bad ATYP ${head[3]}');
      }
      if (skip > 0) await self._read(skip);
      await self._read(2); // bound port
    } on Object {
      socket.destroy();
      rethrow;
    }
    self._leftover.clear();
    self._leftoverLen = 0;
    return self;
  }

  void destroy() => _socket.destroy();

  /// Writes one request head (no body).
  Future<void> request(String head) async {
    _socket.add(head.codeUnits);
    await _socket.flush();
  }

  /// Writes a request head + body in one flight.
  Future<void> upload(String head, Uint8List body) async {
    _socket.add(head.codeUnits);
    _socket.add(body);
    await _socket.flush();
  }

  /// Reads exactly [count] bytes (handshake / framing).
  Future<List<int>> _read(int count) async {
    while (_leftoverLen < count) {
      if (!await _next()) {
        throw const SocketException('tunnel closed mid-read');
      }
      final chunk = _iterator.current;
      _leftover.add(chunk);
      _leftoverLen += chunk.length;
    }
    final all = _leftover.takeBytes();
    _leftoverLen = all.length - count;
    if (_leftoverLen > 0) _leftover.add(all.sublist(count));
    return all.sublist(0, count);
  }

  Future<bool> _next() {
    return _iterator.moveNext().timeout(_readTimeout, onTimeout: () {
      throw const SocketException('tunnel read timeout');
    });
  }

  /// Reads one response's status line + headers (keep-alive framing).
  Future<_RespHead> readResponseHead() async {
    final acc = <int>[];
    if (_leftoverLen > 0) {
      acc.addAll(_leftover.takeBytes());
      _leftoverLen = 0;
    }
    var term = _findHeadEnd(acc);
    while (term < 0) {
      if (!await _next()) {
        throw const SocketException('tunnel closed mid-headers');
      }
      acc.addAll(_iterator.current);
      if (acc.length > 1 << 20) {
        throw const HttpException('response head too large');
      }
      term = _findHeadEnd(acc);
    }
    final headText = String.fromCharCodes(acc.sublist(0, term));
    final rest = acc.sublist(term + 4);
    if (rest.isNotEmpty) {
      _leftover.add(rest);
      _leftoverLen += rest.length;
    }
    final lines = headText.split('\r\n');
    final statusLine = lines.first;
    final parts = statusLine.split(' ');
    final status = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    var len = 0;
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim().toLowerCase();
      if (key == 'content-length') {
        len = int.tryParse(line.substring(colon + 1).trim()) ?? 0;
      }
    }
    return _RespHead(status, len);
  }

  /// Index of the `\r\n\r\n` head terminator, or -1.
  static int _findHeadEnd(List<int> bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 0x0d &&
          bytes[i + 1] == 0x0a &&
          bytes[i + 2] == 0x0d &&
          bytes[i + 3] == 0x0a) {
        return i;
      }
    }
    return -1;
  }

  /// Consumes a body of [expect] bytes, reporting the running total per
  /// data event (live progress). Completes when the body is fully read.
  Future<void> streamBody(
    int expect, {
    required void Function(int chunkTotal) onChunk,
  }) async {
    var total = _leftoverLen;
    if (total >= expect) {
      // Whole body already buffered — one callback, keep the remainder.
      onChunk(expect);
      final all = _leftover.takeBytes();
      _leftoverLen = all.length - expect;
      if (_leftoverLen > 0) _leftover.add(all.sublist(expect));
      return;
    }
    if (total > 0) onChunk(total);
    while (total < expect) {
      if (!await _next()) {
        throw const SocketException('tunnel closed mid-body');
      }
      total += _iterator.current.length;
      onChunk(total < expect ? total : expect);
    }
    _leftover.clear();
    _leftoverLen = 0;
  }

  /// Reads and discards a (short) body of [expect] bytes.
  Future<void> drainBody(int expect) async {
    if (expect <= 0) return;
    await streamBody(expect, onChunk: (_) {});
  }
}
