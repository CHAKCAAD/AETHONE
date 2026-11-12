/// Owns the temporary DNS-aware CONNECT proxy used by Firefox's Android
/// sign-in WebView. The Go child applies the selected process-local resolver;
/// AndroidX ProxyController is installed only after the listener is ready.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class FirefoxWebViewDnsProxy {
  FirefoxWebViewDnsProxy({
    MethodChannel channel = const MethodChannel('aethone/engine'),
  }) : _channel = channel;

  static const Duration _startupTimeout = Duration(seconds: 20);
  static const Duration _shutdownGrace = Duration(seconds: 3);

  final MethodChannel _channel;

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  Future<void>? _startFuture;
  Future<void>? _stopFuture;

  bool _stopRequested = false;
  bool _proxyOverrideActive = false;
  String? resolver;

  Future<void> start(Map<String, dynamic> dnsConfig) {
    if (_startFuture != null) {
      return _startFuture!;
    }
    final future = _startInternal(dnsConfig);
    _startFuture = future;
    return future;
  }

  Future<void> _startInternal(Map<String, dynamic> dnsConfig) async {
    final paths = await _channel.invokeMapMethod<String, dynamic>('paths');
    if (_stopRequested) {
      throw StateError('Firefox WebView DNS proxy start was cancelled');
    }
    final libraryDir = paths?['nativeLibraryDir'] as String? ?? '';
    if (libraryDir.isEmpty) {
      throw StateError('Firefox native library directory is unavailable');
    }

    final process = await Process.start(
      '$libraryDir/libfirefoxvpn.so',
      const ['--webview-proxy'],
      environment: const {},
      includeParentEnvironment: false,
    );
    _process = process;

    final ready = Completer<Map<String, dynamic>>();
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.isEmpty || !line.startsWith('{')) return;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, dynamic>) return;
          if (decoded['event'] == 'webViewProxyReady' && !ready.isCompleted) {
            ready.complete(decoded);
          } else if (decoded['event'] == 'webViewProxyFailed' &&
              !ready.isCompleted) {
            ready.completeError(
              StateError('Firefox WebView DNS proxy failed to initialize'),
            );
          }
        } catch (_) {
          // Non-JSON stdout is ignored; the role's terminal event is JSON.
        }
      },
      onError: (Object error) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Firefox WebView proxy output failed'));
        }
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('Firefox WebView proxy exited before becoming ready'),
          );
        }
      },
    );

    // Drain stderr so the child can never block on a full pipe. The Go role
    // emits no request hostnames, credentials, cookies or page contents.
    _stderrSubscription = process.stderr.listen((_) {});
    unawaited(process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('Firefox WebView proxy exited before ready (code $code)'),
        );
      }
    }));

    process.stdin.writeln(jsonEncode({'dns': dnsConfig}));
    await process.stdin.flush();

    final event = await ready.future.timeout(_startupTimeout);
    if (_stopRequested) {
      throw StateError('Firefox WebView DNS proxy start was cancelled');
    }
    final address = event['addr'] as String? ?? '';
    final proxy = Uri.tryParse('http://$address');
    if (proxy == null ||
        proxy.host != '127.0.0.1' ||
        proxy.port < 1 ||
        proxy.port > 65535) {
      throw StateError('Firefox WebView proxy returned an invalid loopback address');
    }

    try {
      // This native call completes only after AndroidX confirms that the
      // ProxyController override has been applied. The caller loads the
      // first page only after this method returns.
      await _channel.invokeMethod<void>(
        'setFirefoxWebViewProxy',
        {'host': proxy.host, 'port': proxy.port},
      ).timeout(const Duration(seconds: 10));
      _proxyOverrideActive = true;
    } catch (_) {
      // A channel error/timeout can race the native callback. Clear
      // defensively before allowing the child listener to be stopped.
      try {
        await _channel
            .invokeMethod<void>('clearFirefoxWebViewProxy')
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      rethrow;
    }

    if (_stopRequested) {
      throw StateError('Firefox WebView DNS proxy start was cancelled');
    }
    resolver = event['resolver'] as String? ?? 'selected Firefox DNS resolver';
  }

  /// Clear the app-WebView override first, wait for AndroidX to acknowledge
  /// it, then send EOF to the Go role and reap the child process.
  Future<void> stop() {
    _stopRequested = true;
    return _stopFuture ??= _stopInternal();
  }

  Future<void> _stopInternal() async {
    try {
      await _startFuture?.timeout(_startupTimeout + const Duration(seconds: 12));
    } catch (_) {
      // Startup may have failed; cleanup below is still mandatory.
    }

    if (_proxyOverrideActive) {
      try {
        await _channel
            .invokeMethod<void>('clearFirefoxWebViewProxy')
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // The Go process is still stopped below. MainActivity also performs
        // a final clear on Activity teardown as a second cleanup boundary.
      } finally {
        _proxyOverrideActive = false;
      }
    }

    final process = _process;
    if (process != null) {
      try {
        await process.stdin.close();
      } catch (_) {
        // Already closed or the child already exited.
      }
      try {
        await process.exitCode.timeout(_shutdownGrace, onTimeout: () {
          process.kill();
          return -1;
        });
      } catch (_) {
        process.kill();
      }
    }

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _process = null;
  }
}
