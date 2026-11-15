/// FirefoxLoginClient — drives the engine binary's `--login` role
/// (Phase 2): the WebChannel browser-login exchange.
///
/// Spawn discipline (identical to [FirefoxVpnEngine], the phase-1
/// contract): bare argv (`binary --login` — the role flag is the ONLY
/// argument), empty environment, `includeParentEnvironment: false`. The
/// session token captured by the WebChannel bridge travels ONLY on the
/// child's stdin pipe (one JSON line); the minted OAuth pair comes back
/// ONLY on the `loginCompleted` stdout event (the secret-carrying event,
/// routed straight into the Keystore vault by the caller — never logged).
///
/// Lifecycle: one short-lived child per login attempt. [cancel] closes
/// the stdin pipe (the engine's clean-cancel gesture — it aborts even an
/// in-flight exchange call) and escalates to a kill after
/// [shutdownGrace]: no orphan survives a dismissed login page.
///
/// The REAL browser page (accounts.firefox.com in the WebView) is driven
/// by firefox_web_channel.dart + firefox_login_screen.dart; this client
/// only speaks the engine's wire contract.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'firefox_errors.dart';
import 'firefox_protocol.dart';

/// The terminal outcome types live in firefox_protocol.dart
/// ([FirefoxLoginResult] / [FirefoxLoginState]) — the wire-contract home.
///
/// One short-lived `--login` child process.
class FirefoxLoginClient {
  FirefoxLoginClient({
    required this.binaryPath,
    this.shutdownGrace = const Duration(seconds: 3),
    this.onLog,
    this.dnsConfig = const {'mode': 'system'},
  });

  /// Absolute path of `libfirefoxvpn.so` (nativeLibraryDir) or a host
  /// binary in tests.
  final String binaryPath;

  final Duration shutdownGrace;

  /// Redacted diagnostics sink (NEVER receives tokens).
  final void Function(String line)? onLog;

  /// Same process-local resolver policy used by the Firefox engine.
  final Map<String, dynamic> dnsConfig;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Completer<FirefoxLoginResult>? _completer;
  bool _cancelled = false;

  bool get isRunning => _completer != null && !_completer!.isCompleted;

  /// Runs the WebChannel login exchange: spawns the child, writes the
  /// config line (the ONLY secret-carrying write), and resolves when the
  /// child reports a terminal outcome or the [timeout] safety net fires
  /// (the engine's own verify budget is the primary bound — 300 s
  /// default; the Dart timeout is belt-and-braces so a wedged child can
  /// never hang the login page).
  Future<FirefoxLoginResult> runWebChannel({
    required String sessionToken,
    Duration timeout = const Duration(minutes: 7),
  }) async {
    if (isRunning) {
      throw StateError('a login attempt is already running');
    }
    final completer = Completer<FirefoxLoginResult>();
    _completer = completer;
    _cancelled = false;

    FirefoxSessionAuth? minted;
    String failCode = '';
    String failMessage = '';

    // Spawn BARE: argv = [binary, --login]. The session token never
    // touches argv or the environment.
    late final Process process;
    try {
      process = await Process.start(
        binaryPath,
        const ['--login'],
        environment: const {},
        includeParentEnvironment: false,
      );
    } catch (e) {
      _completer = null;
      return FirefoxLoginResult.failed(
        'spawnFailed',
        'could not start the Firefox VPN login engine: $e',
      );
    }
    _process = process;

    void resolve(FirefoxLoginResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.isEmpty || !line.startsWith('{')) return;
        Map<String, dynamic>? raw;
        try {
          final decoded = jsonDecode(line);
          raw = decoded is Map<String, dynamic> ? decoded : null;
        } catch (_) {
          raw = null;
        }
        if (raw == null) return;
        final event = FirefoxEngineEvent.fromJson(raw);
        if (event.carriesSecrets) {
          // PRIVATE: the minted pair — held for the caller's vault; the
          // log rendering is redacted (never the tokens).
          //
          // PHASE B (Part 3) — the pair guard: "completed" requires BOTH
          // tokens to be real strings, non-empty and non-blank (the same
          // rule as the engine's Go guard — defense in depth: a broken
          // or hostile engine event can never mint a garbage session).
          final guardReason = FirefoxErrors.invalidPairReason(
            event.accessToken,
            event.refreshToken,
          );
          if (guardReason != null) {
            onLog?.call(FirefoxErrors.redactLine(
                'firefox-login: loginCompleted rejected by the pair guard '
                '($guardReason)'));
            // Terminal, honest failure — NOT "cancelled": the exchange
            // itself answered with an unusable pair.
            resolve(FirefoxLoginResult.failed(
              FirefoxTransportError.invalidTokenResponse,
              guardReason,
            ));
            return;
          }
          final obtained = event.obtainedAt ?? DateTime.now();
          minted = FirefoxSessionAuth(
            accessToken: event.accessToken,
            refreshToken: event.refreshToken,
            expiresAt: event.expiresIn > 0
                ? obtained.add(Duration(seconds: event.expiresIn))
                : null,
          );
          onLog?.call(event.logLine);
          if (event.name == FirefoxEngineEvents.loginCompleted) {
            resolve(FirefoxLoginResult(
              state: FirefoxLoginState.completed,
              auth: minted,
            ));
          }
          return;
        }
        onLog?.call(FirefoxErrors.redactLine(event.logLine));
        if (event.name == FirefoxEngineEvents.failed) {
          failCode = event.failCode;
          failMessage = event.message;
        }
      },
      onError: (Object error) {
        onLog?.call('firefox-login: stdout error (redacted): $error');
      },
    );

    _stderrSub = process.stderr.listen((chunk) {
      final text = utf8.decode(chunk, allowMalformed: true).trim();
      if (text.isNotEmpty && onLog != null) {
        for (final line in text.split('\n')) {
          onLog!.call('firefox-login[stderr]: $line');
        }
      }
    });

    // The one private write: the session token on the stdin pipe. The
    // pipe STAYS OPEN (closing it is the cancel gesture).
    process.stdin.writeln(jsonEncode({
      'version': 1,
      'mode': 'webchannel',
      'sessionToken': sessionToken,
      'dns': dnsConfig,
    }));

    unawaited(process.exitCode.then((code) {
      if (minted != null) {
        resolve(FirefoxLoginResult(
          state: FirefoxLoginState.completed,
          auth: minted,
        ));
      } else if (_cancelled || code == 0) {
        resolve(FirefoxLoginResult.cancelled());
      } else {
        resolve(FirefoxLoginResult.failed(
          failCode.isEmpty ? 'engineExited:$code' : failCode,
          failMessage.isEmpty
              ? 'the login engine exited on its own (code $code)'
              : failMessage,
        ));
      }
    }));

    return completer.future.timeout(timeout, onTimeout: () async {
      onLog?.call('firefox-login: timeout; cancelling the engine');
      await cancel();
      return FirefoxLoginResult.failed(
        'loginTimeout',
        'the login exchange did not finish in time',
      );
    });
  }

  /// Clean cancel: close the stdin pipe (the engine's cancel gesture),
  /// await its exit bounded by [shutdownGrace], then kill — no orphan
  /// survives a dismissed login page. Idempotent.
  Future<void> cancel() async {
    _cancelled = true;
    final process = _process;
    if (process == null) return;
    try {
      await process.stdin.close();
    } catch (_) {
      // already closed / broken pipe
    }
    try {
      await process.exitCode.timeout(shutdownGrace, onTimeout: () {
        process.kill();
        return -1;
      });
    } catch (_) {
      process.kill();
    }
    await _teardown();
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(FirefoxLoginResult.cancelled());
    }
  }

  Future<void> _teardown() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
  }
}
