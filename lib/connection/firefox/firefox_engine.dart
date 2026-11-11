/// FirefoxVpnEngine — the child-process manager for the Go engine binary
/// (`libfirefoxvpn.so`: an EXECUTABLE named after the Android
/// extractNativeLibs packaging convention, NOT a System.loadLibrary
/// library; it runs via dart:io `Process.start`, which on Android is the
/// same fork/exec ProcessBuilder uses).
///
/// Lifecycle (docs/FIREFOX_VPN_LIFECYCLE.md — the phase-1 state machine):
///
///     idle → starting → processStarted → socksReady → probing
///          → connected → stopping → stopped
///          ↘ failed (from any state)
///
/// `socksReady` is only ever set by the ENGINE's own event (the listener
/// is really bound); `connected` is NOT this class's to declare — the
/// PlatformEngineAdapter's end-to-end probe on 127.0.0.1:1822 owns that
/// (the same TunnelProbe gate as the aether family).
///
/// Security contract (docs/FIREFOX_VPN_SECURITY.md):
///  * tokens travel ONLY on the child's stdin pipe (one JSON config line);
///  * argv carries no secrets (the binary is spawned bare);
///  * the environment is passed through EXPLICITLY (empty by default) —
///    nothing inherits the app's env by accident;
///  * stdout events are parsed; `authRefreshed` goes to [onAuthRefreshed]
///    and is never logged; every other event's log rendering is redacted;
///  * stderr is captured for diagnostics but only its REDACTED lines are
///    surfaced by the adapter.
///
/// Single account, single process, single session — no pool, by decree.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'firefox_errors.dart';
import 'firefox_protocol.dart';

/// The observable states of the engine child process.
enum FirefoxEngineState {
  idle,
  starting,
  processStarted,
  socksReady,
  probing,
  connected,
  stopping,
  stopped,
  failed,
}

/// What the engine told us when it ended (terminal record).
class FirefoxEngineOutcome {
  const FirefoxEngineOutcome({
    required this.state,
    required this.exitCode,
    this.failCode = '',
    this.message = '',
    this.httpStatus = 0,
    this.retryable,
    this.failureStage = '',
  });

  final FirefoxEngineState state;
  final int exitCode;
  final String failCode;

  /// The raw engine chain — LOG-ONLY material (the adapter classifies it
  /// through [FirefoxErrors] before anything user-visible is emitted).
  final String message;

  /// PHASE B (Part 2) — the failed-event extras, passthrough from the
  /// wire (0/null on legacy engines and transport-level failures; a
  /// null retryable means "the engine did not say").
  final int httpStatus;
  final bool? retryable;

  /// Stage 9.1 — the named startup leg that failed (empty on legacy engines).
  final String failureStage;

  bool get cleanStop =>
      (state == FirefoxEngineState.stopped && exitCode == 0) ||
      failCode.isEmpty;
}

/// Spawns and supervises ONE engine child process at a time.
class FirefoxVpnEngine {
  FirefoxVpnEngine({
    required this.binaryPath,
    this.shutdownGrace = const Duration(seconds: 3),
    this.onLog,
  })  : assert(!binaryPath.contains(' ')),
        _state = FirefoxEngineState.idle;

  /// Absolute path of `libfirefoxvpn.so` (nativeLibraryDir) or a host
  /// binary in tests.
  final String binaryPath;

  /// How long to wait for the child to exit after closing its stdin
  /// before escalating to a kill (no orphan may survive a disconnect).
  final Duration shutdownGrace;

  /// Redacted diagnostics sink (NEVER receives tokens).
  final void Function(String line)? onLog;

  FirefoxEngineState _state;
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final _events = StreamController<FirefoxEngineEvent>.broadcast();
  final _outcome = Completer<FirefoxEngineOutcome>();

  /// Parsed engine events (broadcast; replay none).
  Stream<FirefoxEngineEvent> get events => _events.stream;

  FirefoxEngineState get state => _state;
  int? get pid => _process?.pid;
  bool get isAlive => _state == FirefoxEngineState.processStarted ||
      _state == FirefoxEngineState.socksReady ||
      _state == FirefoxEngineState.probing ||
      _state == FirefoxEngineState.connected;

  void _setState(FirefoxEngineState next) {
    _state = next;
    onLog?.call('firefox-engine: state → ${next.name}');
  }

  /// Starts the engine: spawns the binary, writes the config line on the
  /// PRIVATE stdin pipe, and begins consuming stdout events.
  ///
  /// [args] carries FIXED ROLE FLAGS only (e.g. `--guardian-probe` — the
  /// engine's own argv modes). The security contract is unchanged: argv
  /// never carries secrets; every secret still travels on the stdin
  /// pipe. The default (empty argv) is the bare tunnel-role spawn of
  /// every previous version.
  ///
  /// [onAuthRefreshed] receives the refreshed same-account OAuth pair
  /// (private channel — the caller persists it in the Keystore store).
  ///
  /// Returns the future of the process's terminal outcome (failed /
  /// stopped); the CALLER decides how to map it to the UI states.
  Future<FirefoxEngineOutcome> start(
    FirefoxEngineConfig config, {
    void Function(FirefoxSessionAuth refreshed)? onAuthRefreshed,
    Map<String, String> environment = const {},
    List<String> args = const [],
  }) async {
    if (isAlive || _state == FirefoxEngineState.starting) {
      throw StateError('firefox engine already running (state: $_state)');
    }
    _setState(FirefoxEngineState.starting);

    // Spawn with FIXED ROLE FLAGS ONLY: argv = [binary, --role...]. The
    // Go engine reads its whole configuration from the stdin line —
    // nothing secret can leak into /proc/<pid>/cmdline or the process
    // environment.
    final process = await Process.start(
      binaryPath,
      args,
      environment: environment,
      includeParentEnvironment: false,
    );
    _process = process;
    _setState(FirefoxEngineState.processStarted);

    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        final raw = _decode(line);
        if (raw == null) return;
        final event = FirefoxEngineEvent.fromJson(raw);
        if (event.carriesSecrets) {
          // PRIVATE: straight to the store callback; never to the log.
          //
          // PHASE B (Part 3) — the pair guard on the refresh path too: a
          // broken refresh response NEVER overwrites the vault's live
          // pair (the old pair stays; the raw reason goes to the log,
          // redacted). Same rule as the login client's guard.
          final guardReason = FirefoxErrors.invalidPairReason(
            event.accessToken,
            event.refreshToken,
          );
          if (guardReason != null) {
            onLog?.call(FirefoxErrors.redactLine(
                'firefox-engine: authRefreshed rejected by the pair guard '
                '($guardReason) — keeping the stored pair'));
          } else {
            onAuthRefreshed?.call(FirefoxSessionAuth(
              accessToken: event.accessToken,
              refreshToken: event.refreshToken,
            ));
          }
        } else {
          onLog?.call(FirefoxErrors.redactLine(event.logLine));
        }
        switch (event.name) {
          case FirefoxEngineEvents.socksReady:
            if (_state == FirefoxEngineState.processStarted ||
                _state == FirefoxEngineState.starting) {
              _setState(FirefoxEngineState.socksReady);
            }
          case FirefoxEngineEvents.failed:
            _finish(FirefoxEngineOutcome(
              state: FirefoxEngineState.failed,
              exitCode: event.exitCode,
              failCode: event.failCode,
              message: event.message,
              httpStatus: event.httpStatus,
              retryable: event.retryable,
              failureStage: event.failureStage,
            ));
          case FirefoxEngineEvents.quotaExhausted:
            // GUARDIAN-BOOTSTRAP STAGE 6 (renewal & lifecycle): the
            // engine reports quota exhaustion as its OWN terminal event
            // (initial-pass walk AND the renewal loop's park path —
            // ExitQuota), never as a `failed` event. Without this case
            // the outcome fell through to the bare exit-code mapping
            // (`engineExited:2`) and the walk's quota branch never
            // fired; now the owner's «pick another engine» surface is
            // reachable from BOTH death points.
            _finish(FirefoxEngineOutcome(
              state: FirefoxEngineState.failed,
              exitCode: event.exitCode != 0
                  ? event.exitCode
                  : FirefoxEngineExitCode.quota,
              failCode: FirefoxEngineFailure.quotaExhausted,
              message: event.message.isNotEmpty
                  ? event.message
                  : 'the account\'s monthly proxy quota is exhausted',
            ));
          default:
            break;
        }
        _events.add(event);
      },
      onDone: () {
        // stdout EOF: the engine exited; wait() resolves the outcome.
      },
      onError: (Object error) {
        onLog?.call('firefox-engine: stdout error (redacted): $error');
      },
    );

    _stderrSub = process.stderr.listen(
      (chunk) {
        // Redacted engine logs (the engine itself never writes tokens to
        // stderr — belt and braces: nothing forwards raw bytes).
        final text = utf8.decode(chunk, allowMalformed: true).trim();
        if (text.isNotEmpty && onLog != null) {
          for (final line in text.split('\n')) {
            onLog!.call('firefox-engine[stderr]: $line');
          }
        }
      },
    );

    // The config line — the one private write carrying the tokens.
    final blob = jsonEncode(config.toJson());
    process.stdin.writeln(blob);
    // stdin STAYS OPEN: closing it is the shutdown request.

    unawaited(process.exitCode.then((code) {
      // Map exit → outcome unless a terminal event already resolved it.
      if (!_outcome.isCompleted) {
        _finish(FirefoxEngineOutcome(
          state: code == 0
              ? FirefoxEngineState.stopped
              : FirefoxEngineState.failed,
          exitCode: code,
          failCode: code == 0
              ? ''
              : 'engineExited:$code',
          message: code == 0
              ? ''
              : 'the engine process exited on its own (code $code)',
        ));
      }
    }));

    return _outcome.future;
  }

  static Map<String, dynamic>? _decode(String line) {
    if (line.isEmpty || !line.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(line);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _finish(FirefoxEngineOutcome outcome) {
    if (_outcome.isCompleted) return;
    _setState(outcome.state);
    _outcome.complete(outcome);
  }

  /// Graceful stop: close the stdin pipe (the engine's shutdown request),
  /// await its clean exit, escalate to kill after [shutdownGrace].
  /// Idempotent; safe when never started.
  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      _setState(FirefoxEngineState.stopped);
      return;
    }
    if (_state != FirefoxEngineState.failed) {
      _setState(FirefoxEngineState.stopping);
    }
    try {
      await process.stdin.close();
    } catch (_) {
      // already closed / broken pipe
    }
    try {
      await process.exitCode.timeout(shutdownGrace, onTimeout: () {
        // No orphan survives a disconnect.
        onLog?.call('firefox-engine: grace expired; killing pid '
            '${process.pid}');
        process.kill();
        return -1;
      });
    } catch (_) {
      process.kill();
    }
    try {
      await _outcome.future.timeout(shutdownGrace);
    } catch (_) {
      _finish(const FirefoxEngineOutcome(
        state: FirefoxEngineState.stopped,
        exitCode: -1,
      ));
    }
    await _teardown();
    _setState(FirefoxEngineState.stopped);
  }

  Future<void> _teardown() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
  }

  /// Waits for the engine to report `socksReady` (bounded).
  Future<bool> waitForSocksReady(Duration timeout) async {
    if (_state == FirefoxEngineState.socksReady ||
        _state == FirefoxEngineState.probing ||
        _state == FirefoxEngineState.connected) {
      return true;
    }
    try {
      await events
          .firstWhere((e) => e.name == FirefoxEngineEvents.socksReady)
          .timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Marks the session probing/connected (adapter-driven — the probe owns
  /// Connected, not the engine).
  void markProbing() {
    if (_state == FirefoxEngineState.socksReady) {
      _setState(FirefoxEngineState.probing);
    }
  }

  void markConnected() {
    if (_state == FirefoxEngineState.probing ||
        _state == FirefoxEngineState.socksReady) {
      _setState(FirefoxEngineState.connected);
    }
  }

  /// The terminal outcome future (completes when the process ends).
  Future<FirefoxEngineOutcome> get outcome => _outcome.future;

  /// Releases the event stream (called by the adapter's dispose path).
  Future<void> dispose() async {
    await stop();
    if (!_outcome.isCompleted) {
      _finish(const FirefoxEngineOutcome(
        state: FirefoxEngineState.stopped,
        exitCode: 0,
      ));
    }
    await _events.close();
  }
}
