/// FirefoxLoginClient — drives the engine binary's `--login` role
/// (Phase 2 + the 1.8.0 arman-pattern round).
///
/// Spawn discipline (identical to [FirefoxVpnEngine], the phase-1
/// contract): bare argv (`binary --login` — the role flag is the ONLY
/// argument), empty environment, `includeParentEnvironment: false`. The
/// session token OR the email+password pair travels ONLY on the
/// child's stdin pipe (one JSON line); the minted OAuth pair comes back
/// ONLY on the `loginCompleted` stdout event (the secret-carrying event,
/// routed straight into the Keystore vault by the caller — never logged).
///
/// Lifecycle: one short-lived child per login attempt. [cancel] closes
/// the stdin pipe (the engine's clean-cancel gesture — it aborts even an
/// in-flight exchange call) and escalates to a kill after
/// [shutdownGrace]: no orphan survives a dismissed login page.
///
/// TWO modes (the config line's `mode` picks):
///  * webchannel — the WebChannel browser-login exchange (Phase 2).
///    The REAL browser page (accounts.firefox.com in the WebView) is
///    driven by firefox_web_channel.dart + firefox_login_screen.dart;
///    this client only speaks the engine's wire contract.
///  * password (1.8.0 — arman-vpn-client's DEFAULT sign-in pattern):
///    the direct email+password form. The engine runs the whole FxA
///    password flow; when it needs the emailed confirmation code it
///    emits `loginNeedsCode` and [runPassword] resolves with that
///    intermediate state — the child STAYS ALIVE and [submitCode]
///    answers on the same stdin pipe (the second JSON line).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'firefox_errors.dart';
import 'firefox_protocol.dart';

/// The terminal outcome types live in firefox_protocol.dart
/// ([FirefoxLoginResult] / [FirefoxLoginState]) — the wire-contract home.
///
/// One short-lived `--login` child process (which may span several
/// code-submission steps in the password mode).
class FirefoxLoginClient {
  FirefoxLoginClient({
    required this.binaryPath,
    this.shutdownGrace = const Duration(seconds: 3),
    this.onLog,
    this.dnsConfig = const {'mode': 'doh', 'provider': 'auto'},
    this.upstreamSocks,
  });

  /// Absolute path of `libfirefoxvpn.so` (nativeLibraryDir) or a host
  /// binary in tests.
  final String binaryPath;

  final Duration shutdownGrace;

  /// Redacted diagnostics sink (NEVER receives tokens or the password).
  final void Function(String line)? onLog;

  /// Same process-local resolver policy used by the Firefox engine.
  final Map<String, dynamic> dnsConfig;

  /// 1.5.0 (fix 5) — the WARP carrier the login screen brought up
  /// ('socks5://127.0.0.1:1819'): the token exchange rides it (the
  /// Fastly edge sees the WARP egress). Null/empty keeps the direct
  /// exchange — the field is validated loopback-only by the engine.
  final String? upstreamSocks;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Completer<FirefoxLoginResult>? _stepCompleter;
  bool _cancelled = false;
  FirefoxSessionAuth? _minted;

  /// A password-mode step is open (the child is alive and the host owes
  /// the engine either a code line or a cancel).
  bool get isRunning =>
      _stepCompleter != null && !_stepCompleter!.isCompleted;

  /// Runs the WebChannel login exchange: spawns the child, writes the
  /// config line (the ONLY secret-carrying write), and resolves when the
  /// child reports a terminal outcome or the [timeout] safety net fires
  /// (the engine's own verify budget is the primary bound — 300 s
  /// default; the Dart timeout is belt-and-braces so a wedged child can
  /// never hang the login page).
  Future<FirefoxLoginResult> runWebChannel({
    required String sessionToken,
    Duration timeout = const Duration(minutes: 7),
  }) {
    final result = _spawnAndStart(
      config: {
        'version': 1,
        'mode': 'webchannel',
        'sessionToken': sessionToken,
        'dns': dnsConfig,
        if (upstreamSocks != null && upstreamSocks!.isNotEmpty)
          'upstreamSocks': upstreamSocks,
      },
      timeout: timeout,
    );
    return result;
  }

  /// 1.8.0 — the arman-pattern direct sign-in: spawns the child with
  /// the email+password config line (the ONLY secret-carrying write;
  /// the password never touches argv, the environment or a log) and
  /// resolves when the child reports a terminal outcome OR asks for
  /// the emailed code ([FirefoxLoginState.needsCode] — answer it with
  /// [submitCode] on the SAME child).
  Future<FirefoxLoginResult> runPassword({
    required String email,
    required String password,
    Duration timeout = const Duration(minutes: 11),
  }) {
    final result = _spawnAndStart(
      config: {
        'version': 1,
        'mode': 'password',
        'email': email,
        'password': password,
        // The whole password walk (login + the human's code-fetch +
        // verify + mint) gets the contract's MAXIMUM budget — the 300 s
        // default fits the browser exchange, not a person reading
        // their email.
        'verifyTimeoutMs': 600000,
        'dns': dnsConfig,
        if (upstreamSocks != null && upstreamSocks!.isNotEmpty)
          'upstreamSocks': upstreamSocks,
      },
      timeout: timeout,
    );
    return result;
  }

  /// 1.8.0 — answers the engine's `loginNeedsCode` ask with the code
  /// the user typed (the second stdin line; the child stays alive
  /// between the ask and this answer). Resolves with the next terminal
  /// outcome or the NEXT ask (a wrong code re-asks with
  /// `lastError: 'wrongCode'`).
  Future<FirefoxLoginResult> submitCode(
    String code, {
    Duration timeout = const Duration(minutes: 7),
  }) {
    final step = _stepCompleter;
    final process = _process;
    if (step == null || step.isCompleted || process == null) {
      return Future.value(FirefoxLoginResult.failed(
        'engineExited',
        'the login engine is not waiting for a code',
      ));
    }
    final next = _stepCompleter = Completer<FirefoxLoginResult>();
    // The ONLY write of this step: the code line (never a secret).
    try {
      process.stdin.writeln(jsonEncode({'code': code}));
    } catch (e) {
      return Future.value(FirefoxLoginResult.failed(
        'engineExited',
        'could not send the code to the login engine: $e',
      ));
    }
    return next.future.timeout(timeout, onTimeout: () async {
      onLog?.call('firefox-login: timeout; cancelling the engine');
      await cancel();
      return FirefoxLoginResult.failed(
        'loginTimeout',
        'the code was not accepted in time',
      );
    });
  }

  Future<FirefoxLoginResult> _spawnAndStart({
    required Map<String, dynamic> config,
    required Duration timeout,
  }) async {
    if (isRunning) {
      throw StateError('a login attempt is already running');
    }
    final completer = _stepCompleter = Completer<FirefoxLoginResult>();
    _cancelled = false;
    _minted = null;

    String failCode = '';
    String failMessage = '';

    // Spawn BARE: argv = [binary, --login]. The credentials never
    // touch argv or the environment.
    late final Process process;
    try {
      process = await Process.start(
        binaryPath,
        const ['--login'],
        environment: const {},
        includeParentEnvironment: false,
      );
    } catch (e) {
      _stepCompleter = null;
      return FirefoxLoginResult.failed(
        'spawnFailed',
        'could not start the Firefox VPN login engine: $e',
      );
    }
    _process = process;

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
            _resolveStep(FirefoxLoginResult.failed(
              FirefoxTransportError.invalidTokenResponse,
              guardReason,
            ));
            return;
          }
          final obtained = event.obtainedAt ?? DateTime.now();
          _minted = FirefoxSessionAuth(
            accessToken: event.accessToken,
            refreshToken: event.refreshToken,
            expiresAt: event.expiresIn > 0
                ? obtained.add(Duration(seconds: event.expiresIn))
                : null,
          );
          onLog?.call(event.logLine);
          if (event.name == FirefoxEngineEvents.loginCompleted) {
            _resolveStep(FirefoxLoginResult(
              state: FirefoxLoginState.completed,
              auth: _minted,
            ));
          }
          return;
        }
        // 1.8.0 — the password mode's emailed-code ask: an INTERMEDIATE
        // step, never terminal. The child stays alive; the host answers
        // with submitCode (or cancel).
        if (event.name == FirefoxEngineEvents.loginNeedsCode) {
          onLog?.call(FirefoxErrors.redactLine(event.logLine));
          _resolveStep(FirefoxLoginResult.needsCode(
            event.needsCodeEmail,
            event.needsCodeLastError,
          ));
          return;
        }
        onLog?.call(FirefoxErrors.redactLine(event.logLine));
        if (event.name == FirefoxEngineEvents.failed) {
          failCode = event.failCode;
          failMessage = event.message;
          _resolveStep(FirefoxLoginResult.failed(failCode, failMessage));
          return;
        }
        if (event.name == FirefoxEngineEvents.stopping) {
          // The engine's own shutdown gesture (a cancel in flight).
          return;
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

    // The one private write of the first step: the config line on the
    // stdin pipe. The pipe STAYS OPEN (closing it is the cancel gesture,
    // and in the password mode it also carries the code line).
    process.stdin.writeln(jsonEncode(config));

    unawaited(process.exitCode.then((code) {
      final minted = _minted;
      if (minted != null) {
        _resolveStep(FirefoxLoginResult(
          state: FirefoxLoginState.completed,
          auth: minted,
        ));
      } else if (_cancelled || code == 0) {
        _resolveStep(FirefoxLoginResult.cancelled());
      } else {
        _resolveStep(FirefoxLoginResult.failed(
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

  /// Resolves the CURRENT step (whichever completer is armed) — the
  /// password mode re-arms a fresh step per code submission.
  void _resolveStep(FirefoxLoginResult result) {
    final step = _stepCompleter;
    if (step != null && !step.isCompleted) {
      step.complete(result);
    }
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
    _resolveStep(FirefoxLoginResult.cancelled());
  }

  Future<void> _teardown() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
  }
}
