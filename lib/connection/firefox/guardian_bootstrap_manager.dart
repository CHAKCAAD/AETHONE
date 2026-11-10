/// STAGE 4 of the Guardian bootstrap mission
/// (docs/performance/FIREFOX_GUARDIAN_PSIPHON_BOOTSTRAP_PROGRESS.md) —
/// the `Firefox Guardian Bootstrap Manager`: the strategy layer that
/// decides HOW the Guardian control plane should be reached.
///
/// What it orchestrates (mission §7 diagram):
///  1. a DIRECT Guardian attempt (through a seam — Stage 5 wires the
///     real request; anything that is not a REAL 451 fails honestly
///     and never starts a bootstrap);
///  2. on a genuine region-unavailable answer: the verified bootstrap
///     routes of stages 2 and 3 — Psiphon Standalone, then the
///     project's EXISTING AETHER → PSIPHON chain — tried SEQUENTIALLY,
///     each with its own bounded budget, never in parallel;
///  3. through the winning route's local proxy: the Guardian
///     authorization (a seam — Stage 5's real request through the
///     RoutingRoundTripper's allowlist path);
///  4. a route is remembered as SUCCESSFUL only after readiness +
///     probe + authorization ALL passed (mission §4-4), so the next
///     connection in the same network context can take the Fast Path.
///
/// Level-two learning only (mission §7.1): this manager remembers
/// WHICH ROUTE worked; it never replaces psiphon's internal adaptive
/// engine (level one) and never wipes its data directory.
///
/// Hard rules implemented here:
///  * singleflight across the WHOLE operation — many Guardian requests
///    share one bootstrap (mission §4-5);
///  * ONE active bootstrap at a time; a user aether connect walk
///    blocks bootstrap starts entirely (shared process env + identity
///    file — the walk-exclusion seam);
///  * 401/403/validation/general errors are NEVER region blocks and
///    never create bootstrap loops (mission §4-2);
///  * cancellation propagates at every checkpoint and races the
///    seam awaits; stop() owns the terminal state;
///  * nothing runs in the background while no one asks (no learning,
///    no scanning — mission §7.1);
///  * the route memory is atomic, corruption-tolerant, context-scoped
///    and stores no secrets (see bootstrap_route_memory.dart).
///
/// State machine (mission §4-6, names adapted, behaviors separable;
/// the app-level VpnState model in connection_state.dart is untouched
/// — this is the Guardian sub-flow's own machine, mapped onto it by
/// Stage 5's integration):
///
///     idle → directRequest → authorized                     (direct OK)
///          → directRequest → guardian451 → bootstrapSelecting
///              → psiphonDirectStarting → psiphonDirectReady
///              → guardianAuthorizing → authorized
///          (chain variant: combinedStarting → combinedReady — the
///           mission's AETHER_UPSTREAM_STARTING + COMBINED_PSIPHON_
///           STARTING merge into one state because the pinned core
///           runs the whole chain as ONE FFI job with no Dart-side
///           boundary between the WARP leg and the psiphon child;
///           splitting it would require log parsing, which the
///           mission forbids)
///     any → stopping → stopped        (stop()/release()/dispose())
///     any failure → failed
library;

import 'dart:async';

import 'psiphon_bootstrap.dart';
import 'bootstrap_route_memory.dart';

/// The Guardian sub-flow's states (see the library comment for the
/// honest mapping onto the mission's §4-6 list).
enum GuardianBootstrapManagerState {
  idle,
  directRequest,
  guardian451,
  bootstrapSelecting,
  psiphonDirectStarting,
  psiphonDirectReady,
  combinedStarting,
  combinedReady,
  guardianAuthorizing,
  authorized,
  failed,
  stopping,
  stopped,
}

/// One typed state transition (the UI and Stage 5 never parse logs).
class GuardianBootstrapEvent {
  const GuardianBootstrapEvent(
    this.state, {
    this.routeKind,
    this.errorCode,
    this.message,
  });

  final GuardianBootstrapManagerState state;
  final GuardianBootstrapRouteKind? routeKind;
  final String? errorCode;
  final String? message;
}

/// The per-connection timing record (mission §7.1: measured
/// SEPARATELY; no numbers are ever reported without measurement).
class GuardianBootstrapTimings {
  const GuardianBootstrapTimings({
    this.directMillis,
    this.bootstrapReadyMillis,
    this.authorizationMillis,
  });

  /// The direct attempt's duration, when one was made.
  final int? directMillis;

  /// Start → endpoint ready for the WINNING bootstrap route.
  final int? bootstrapReadyMillis;

  /// Request start → Guardian answer, for the winning authorization.
  final int? authorizationMillis;
}

/// A completed authorization: which route delivered it, the local
/// proxy endpoint Stage 5's RoutingRoundTripper should dial (null for
/// the direct route), and the timings.
class GuardianBootstrapSession {
  const GuardianBootstrapSession({
    required this.routeKind,
    required this.contextId,
    required this.establishedAt,
    required this.timings,
    this.endpoint,
  });

  final GuardianBootstrapRouteKind routeKind;
  final String contextId;
  final DateTime establishedAt;
  final GuardianBootstrapTimings timings;

  /// The loopback SOCKS5 endpoint of the winning bootstrap route —
  /// `socks5://127.0.0.1:<ephemeral>` — or null when Guardian was
  /// reached directly.
  final PsiphonProxyEndpoint? endpoint;
}

/// The manager's failure taxonomy (stable codes; Stage 5 maps them
/// onto the Guardian flow's own error surfaces).
class GuardianBootstrapException implements Exception {
  const GuardianBootstrapException(this.code, [this.message]);

  /// `walkActive` — a user aether connect walk holds the process
  ///   environment/identity; bootstrap may not start.
  /// `directFailed` — the direct attempt failed with a NON-451 error
  ///   (its code rides in [message]); no bootstrap is started.
  /// `allRoutesFailed` — every route failed; per-route codes in the
  ///   message.
  /// `authorizationFailed` — no authorization seam wired (Stage 5).
  /// `cancelled` — stop() won the race.
  /// `disposed` — used after dispose().
  final String code;
  final String? message;

  @override
  String toString() =>
      'GuardianBootstrapException($code${message == null ? '' : ': $message'})';
}

// ---- seams (Stage 5 wiring points; Stage 4 tests inject fakes) --------------

/// The outcome of a direct Guardian attempt.
enum GuardianDirectOutcome {
  /// Guardian answered successfully — no bootstrap needed at all.
  success,

  /// A REAL region-unavailable answer (Stage 1's classification:
  /// a genuine Guardian endpoint + HTTP 451 + the structured code when
  /// the body parses) — the only trigger for bootstrap.
  regionUnavailable,

  /// Anything else — 401/403/validation/network/general errors. These
  /// NEVER look like region blocks and never start a bootstrap
  /// (mission §4-2).
  otherFailure,
}

class GuardianDirectResult {
  const GuardianDirectResult({
    required this.outcome,
    this.errorCode,
    this.message,
  });

  final GuardianDirectOutcome outcome;
  final String? errorCode;
  final String? message;
}

/// The direct-attempt seam. PRODUCTION (Stage 5): the real Guardian
/// request over the existing direct uTLS transport, classified with
/// Stage 1's `guardianRegionUnavailable` rules.
abstract class GuardianDirectAttempt {
  /// Must honor [timeout]. Never throws — failures come back as
  /// [GuardianDirectOutcome.otherFailure] with their code.
  Future<GuardianDirectResult> attempt({Duration timeout});
}

class GuardianAuthorizationResult {
  const GuardianAuthorizationResult({
    required this.ok,
    this.code,
    this.message,
  });

  final bool ok;
  final String? code;
  final String? message;
}

/// The authorization seam: the REAL Guardian authorization THROUGH the
/// winning bootstrap route's local proxy. PRODUCTION (Stage 5): the
/// same request the direct attempt would have made, dialed through
/// `socks5://127.0.0.1:<port>` by the RoutingRoundTripper's allowlist
/// path. A route is recorded successful ONLY when this returns ok
/// (mission §4-4 — a started process or a ready proxy is not enough).
abstract class GuardianAuthorizationVerifier {
  /// Must honor [timeout]. Never throws — failures come back with
  /// ok=false and their code (Stage 5 maps HTTP/transport errors).
  Future<GuardianAuthorizationResult> verify(
    Uri proxyUrl, {
    Duration timeout,
  });
}

/// The non-identifying network context seam (mission §7.1: coarse,
/// low-risk, no raw SSID/BSSID/IP, no new sensitive permissions).
///
/// PRODUCTION DEFAULT ([SingleBucketNetworkContextProvider]): a single
/// bucket — the app currently ships no connectivity source, and the
/// mission explicitly allows a limited categorization when a stable
/// low-risk identifier is not available, provided the limitation is
/// documented: with one bucket, route memory is shared across ALL
/// networks, so a route that worked on one network is re-validated
/// (probe + authorization) on every use — Fast Path changes PRIORITY,
/// never readiness. Stage 5+ may wire a coarse transport category
/// (wifi/cellular) from an existing, already-permitted source.
abstract class GuardianNetworkContextProvider {
  Future<String> currentContextId();
}

class SingleBucketNetworkContextProvider
    implements GuardianNetworkContextProvider {
  const SingleBucketNetworkContextProvider();

  @override
  Future<String> currentContextId() async => 'default';
}

/// The walk-exclusion seam: TRUE while a USER aether connect walk is
/// active. The in-process core's process environment and WARP identity
/// file are shared (stages 2/3 documented constraint), so a bootstrap
/// start must never race the user's own walk. PRODUCTION (Stage 5):
/// the adapter's connecting/connected state.
typedef UserWalkGuard = bool Function();

/// The result of the direct phase inside one operation.
class _DirectRun {
  const _DirectRun({this.session, required this.elapsedMillis});

  /// Non-null when the direct attempt SUCCEEDED — the operation is
  /// complete then (no bootstrap at all, mission scenario A).
  final GuardianBootstrapSession? session;
  final int elapsedMillis;
}

/// The `Firefox Guardian Bootstrap Manager` (mission's conceptual
/// name) — one instance per app.
class GuardianBootstrapManager {
  GuardianBootstrapManager({
    required this.filesDir,
    required this.nativeLibraryDir,
    GuardianDirectAttempt? directAttempt,
    GuardianAuthorizationVerifier? authorizationVerifier,
    GuardianNetworkContextProvider? networkContext,
    UserWalkGuard? userWalkActive,
    PsiphonBootstrapProxy Function(PsiphonBootstrapMode mode)? proxyFactory,
    String? memoryPath,
    this.routeTtl = kDefaultRouteTtl,
    this.routeCooldown = kDefaultRouteCooldown,
    this.directTimeout = const Duration(seconds: 30),
    this.authorizationTimeout = const Duration(seconds: 60),
    void Function(String line)? onLog,
  })  : _directSeam = directAttempt,
        _verifierSeam = authorizationVerifier,
        _networkContext =
            networkContext ?? const SingleBucketNetworkContextProvider(),
        _userWalkActive = userWalkActive ?? (() => false),
        _proxyFactory = proxyFactory ??
            ((mode) => PsiphonBootstrapProxy(
                  filesDir: filesDir,
                  nativeLibraryDir: nativeLibraryDir,
                  mode: mode,
                )),
        _memoryPath =
            memoryPath ?? '$filesDir/guardian-bootstrap/route-memory.json',
        _logSink = onLog;

  /// The app's writable files dir (Android `Context.getFilesDir`).
  final String filesDir;

  /// The app's native library dir (packaged `libpsiphon.so` etc.).
  final String nativeLibraryDir;

  final GuardianDirectAttempt? _directSeam;
  final GuardianAuthorizationVerifier? _verifierSeam;
  final GuardianNetworkContextProvider _networkContext;
  final UserWalkGuard _userWalkActive;
  final PsiphonBootstrapProxy Function(PsiphonBootstrapMode mode) _proxyFactory;
  final String _memoryPath;
  final void Function(String line)? _logSink;

  /// Validity window of a learned route (policy constant; see
  /// bootstrap_route_memory.dart).
  final Duration routeTtl;

  /// Bounded failure cooldown (policy constant).
  final Duration routeCooldown;

  /// Budget of ONE direct attempt (the seam must honor it).
  final Duration directTimeout;

  /// Budget of ONE authorization (the seam must honor it).
  final Duration authorizationTimeout;

  // ---- state ---------------------------------------------------------------

  final StreamController<GuardianBootstrapEvent> _events =
      StreamController<GuardianBootstrapEvent>.broadcast();

  final StreamController<void> _stopSignal =
      StreamController<void>.broadcast();

  GuardianBootstrapManagerState _state = GuardianBootstrapManagerState.idle;

  /// The single in-flight operation (singleflight across the WHOLE
  /// flow — mission §4-5: many Guardian requests, one bootstrap).
  Future<GuardianBootstrapSession>? _op;

  GuardianBootstrapSession? _session;
  PsiphonBootstrapProxy? _activeProxy;
  Future<GuardianBootstrapRouteMemory>? _memoryLoading;
  bool _disposed = false;
  bool _stopRequested = false;
  String? _lastFailureCode;

  /// Typed state transitions (broadcast; never log lines).
  Stream<GuardianBootstrapEvent> get events => _events.stream;

  GuardianBootstrapManagerState get state => _state;

  /// The current session once [state] is authorized; null otherwise.
  GuardianBootstrapSession? get session => _session;

  /// The winning route's local proxy endpoint (null for direct).
  PsiphonProxyEndpoint? get endpoint => _session?.endpoint;

  /// The code of the last failure (diagnostics; null when none).
  String? get lastFailureCode => _lastFailureCode;

  /// The route memory (loaded lazily, once; corruption-tolerant).
  Future<GuardianBootstrapRouteMemory> get memory {
    final loading = _memoryLoading;
    if (loading != null) return loading;
    final future = GuardianBootstrapRouteMemory.load(
      _memoryPath,
      ttl: routeTtl,
      cooldown: routeCooldown,
      onLog: _logSink,
    );
    _memoryLoading = future;
    return future;
  }

  // ---- main entry ----------------------------------------------------------

  /// Ensures a Guardian authorization exists, building one if needed.
  ///
  /// Singleflight: concurrent callers share ONE operation (the future
  /// is installed synchronously — no await before it, so there is no
  /// race window). A healthy current session in the same network
  /// context is reused without any new work.
  Future<GuardianBootstrapSession> ensureAuthorized() {
    if (_disposed) {
      throw const GuardianBootstrapException('disposed');
    }
    final inFlight = _op;
    if (inFlight != null) return inFlight;
    final operation = _runOperationWithReuse();
    _op = operation;
    return operation;
  }

  Future<GuardianBootstrapSession> _runOperationWithReuse() async {
    try {
      // Session reuse: authorized + same context + (for bootstrap
      // routes) a live, probe-verified proxy. A direct-route session
      // holds no resource — re-run direct (cheap, honest about
      // reachability).
      if (_state == GuardianBootstrapManagerState.authorized) {
        final session = _session;
        if (session != null) {
          final contextNow = await _networkContext.currentContextId();
          if (contextNow == session.contextId) {
            if (session.routeKind == GuardianBootstrapRouteKind.direct) {
              // fall through to a fresh direct run
            } else {
              final proxy = _activeProxy;
              if (proxy != null && await proxy.healthCheck()) {
                return session;
              }
              await _teardownProxy(); // died — rebuild
              _session = null;
            }
          } else {
            // Context changed: re-evaluate fresh, never blindly reuse
            // the old network's data (mission §7.1).
            await _teardownProxy();
            _session = null;
          }
        }
      }
      return await _runOperation();
    } finally {
      _op = null;
    }
  }

  Future<GuardianBootstrapSession> _runOperation() async {
    final contextId = await _networkContext.currentContextId();
    final routeMemory = await memory;
    _checkStop();

    // Fast Path eligibility (mission §4-2): a valid saved BOOTSTRAP
    // route plus recent REAL 451 evidence — then the doomed direct
    // attempt is skipped. Anything less: direct first.
    final savedRoute = routeMemory.validFastPathRoute(contextId);
    final skipDirect = savedRoute != null &&
        savedRoute != GuardianBootstrapRouteKind.direct &&
        routeMemory.shouldSkipDirect(contextId);

    if (!skipDirect) {
      final directRun = await _runDirect(contextId, routeMemory);
      final directSession = directRun.session;
      if (directSession != null) {
        return directSession;
      }
      // A REAL 451 — recorded by _runDirect; continue to bootstrap.
    } else if (_userWalkActive()) {
      // Skipping direct means starting a bootstrap right away — under
      // an active user walk that is forbidden (walk exclusion).
      throw _fail(const GuardianBootstrapException(
        'walkActive',
        'a user aether connect walk is active; bootstrap may not start',
      ));
    }

    _setState(GuardianBootstrapManagerState.guardian451);
    _setState(GuardianBootstrapManagerState.bootstrapSelecting);
    final order = _orderedRoutes(routeMemory, contextId, savedRoute);
    final perRoute = <String>[];
    for (final kind in order) {
      _checkStop();
      if (_userWalkActive()) {
        throw _fail(const GuardianBootstrapException(
          'walkActive',
          'a user aether connect walk is active; bootstrap may not start',
        ));
      }
      final attempt =
          await _tryRoute(kind, contextId, routeMemory, perRoute);
      if (attempt != null) {
        return attempt;
      }
    }
    throw _fail(GuardianBootstrapException(
      'allRoutesFailed',
      perRoute.join('; '),
    ));
  }

  /// The direct phase. Returns the completed session on success (no
  /// bootstrap is started — mission scenario A) or marks the 451
  /// evidence and returns without a session.
  Future<_DirectRun> _runDirect(
    String contextId,
    GuardianBootstrapRouteMemory routeMemory,
  ) async {
    final direct = _directSeam;
    if (direct == null) {
      throw _fail(const GuardianBootstrapException(
        'directFailed',
        'no direct attempt seam wired (Stage 5 wires the real request)',
      ));
    }
    _setState(GuardianBootstrapManagerState.directRequest);
    final stopwatch = Stopwatch()..start();
    final result = await _raceStop(direct.attempt(timeout: directTimeout));
    stopwatch.stop();
    _checkStop();
    switch (result.outcome) {
      case GuardianDirectOutcome.success:
        routeMemory.recordDirectSuccess(contextId);
        await routeMemory.persist();
        _lastFailureCode = null;
        _setState(GuardianBootstrapManagerState.authorized,
            routeKind: GuardianBootstrapRouteKind.direct);
        final session = GuardianBootstrapSession(
          routeKind: GuardianBootstrapRouteKind.direct,
          contextId: contextId,
          establishedAt: DateTime.now(),
          timings: GuardianBootstrapTimings(
            directMillis: stopwatch.elapsedMilliseconds,
          ),
        );
        _session = session;
        return _DirectRun(
            session: session, elapsedMillis: stopwatch.elapsedMilliseconds);
      case GuardianDirectOutcome.regionUnavailable:
        routeMemory.recordDirectRegionUnavailable(contextId);
        await routeMemory.persist();
        return _DirectRun(elapsedMillis: stopwatch.elapsedMilliseconds);
      case GuardianDirectOutcome.otherFailure:
        routeMemory.recordDirectOtherFailure(contextId);
        await routeMemory.persist();
        throw _fail(GuardianBootstrapException(
          'directFailed',
          '${result.errorCode ?? 'unknown'}'
          '${result.message == null ? '' : ': ${result.message}'}',
        ));
    }
  }

  /// One bootstrap route attempt: start (its own readiness probe is
  /// inside stages 2/3), then authorization through the endpoint.
  /// Returns the session on success, null to try the next route.
  Future<GuardianBootstrapSession?> _tryRoute(
    GuardianBootstrapRouteKind kind,
    String contextId,
    GuardianBootstrapRouteMemory routeMemory,
    List<String> perRoute,
  ) async {
    final verifier = _verifierSeam;
    if (verifier == null) {
      throw _fail(const GuardianBootstrapException(
        'authorizationFailed',
        'no authorization seam wired (Stage 5 wires the real request)',
      ));
    }
    final mode = kind == GuardianBootstrapRouteKind.psiphonOnly
        ? PsiphonBootstrapMode.psiphonOnly
        : PsiphonBootstrapMode.aetherPsiphonChain;
    _setState(
      mode == PsiphonBootstrapMode.psiphonOnly
          ? GuardianBootstrapManagerState.psiphonDirectStarting
          : GuardianBootstrapManagerState.combinedStarting,
      routeKind: kind,
    );
    final proxy = _proxyFactory(mode);
    final readyStopwatch = Stopwatch()..start();
    try {
      final endpoint = await proxy.start();
      readyStopwatch.stop();
      _checkStop();
      _activeProxy = proxy;
      _setState(
        mode == PsiphonBootstrapMode.psiphonOnly
            ? GuardianBootstrapManagerState.psiphonDirectReady
            : GuardianBootstrapManagerState.combinedReady,
        routeKind: kind,
      );
      _setState(
        GuardianBootstrapManagerState.guardianAuthorizing,
        routeKind: kind,
      );
      final authStopwatch = Stopwatch()..start();
      final result = await _raceStop(
        verifier.verify(
          Uri.parse(endpoint.socksUrl),
          timeout: authorizationTimeout,
        ),
      );
      authStopwatch.stop();
      _checkStop();
      if (!result.ok) {
        perRoute.add('$kind authorization: ${result.code ?? 'unknown'}');
        routeMemory.recordRouteFailure(
          contextId,
          kind,
          failureKind: 'authorization',
          code: result.code,
        );
        await routeMemory.persist();
        await _teardownProxy();
        return null; // next route
      }
      // FULL success — the only thing that makes a route Fast-Path
      // eligible (readiness + probe + authorization, mission §4-4).
      routeMemory.recordRouteSuccess(
        contextId,
        kind,
        readyMillis: readyStopwatch.elapsedMilliseconds,
        authMillis: authStopwatch.elapsedMilliseconds,
      );
      await routeMemory.persist();
      _lastFailureCode = null;
      _setState(GuardianBootstrapManagerState.authorized, routeKind: kind);
      final session = GuardianBootstrapSession(
        routeKind: kind,
        contextId: contextId,
        establishedAt: DateTime.now(),
        timings: GuardianBootstrapTimings(
          bootstrapReadyMillis: readyStopwatch.elapsedMilliseconds,
          authorizationMillis: authStopwatch.elapsedMilliseconds,
        ),
        endpoint: endpoint,
      );
      _session = session;
      return session;
    } on GuardianBootstrapException {
      rethrow; // cancellation / walk refusal — stop() owns the state
    } catch (error) {
      // A start/probe failure of this route: classified, recorded with
      // a bounded cooldown, and the next route is tried (mission §4-5:
      // psiphon failure vs authorization failure stay separate).
      perRoute.add('$kind start: $error');
      routeMemory.recordRouteFailure(
        contextId,
        kind,
        failureKind: 'start',
        code: (error is PsiphonBootstrapException) ? error.code : 'unknown',
      );
      await routeMemory.persist();
      await proxy.stop();
      return null;
    }
  }

  /// Routes for this call: the memory's adaptive discovery order, with
  /// the valid Fast-Path route (if any) hoisted to the front.
  List<GuardianBootstrapRouteKind> _orderedRoutes(
    GuardianBootstrapRouteMemory routeMemory,
    String contextId,
    GuardianBootstrapRouteKind? savedRoute,
  ) {
    final order = routeMemory.discoveryOrder(contextId);
    if (savedRoute == null || savedRoute == GuardianBootstrapRouteKind.direct) {
      return order;
    }
    return [
      savedRoute,
      ...order.where((kind) => kind != savedRoute),
    ];
  }

  // ---- lifecycle ------------------------------------------------------------

  /// Full on-demand health check of the current session: for a
  /// bootstrap route, the proxy's own multi-witness probe (core alive
  /// + SOCKS5 + TLS round trip — stages 2/3); a direct session holds
  /// no resource, so it reports true (its re-validation IS the next
  /// direct attempt). An UNHEALTHY authorized session is invalidated
  /// on the spot — the next [ensureAuthorized] rebuilds it instead of
  /// trusting a second, possibly raced check.
  Future<bool> healthCheck() async {
    if (_disposed || _state != GuardianBootstrapManagerState.authorized) {
      return false;
    }
    final session = _session;
    if (session == null) return false;
    if (session.routeKind == GuardianBootstrapRouteKind.direct) return true;
    final proxy = _activeProxy;
    final healthy = proxy != null && await proxy.healthCheck();
    if (!healthy) {
      await _teardownProxy();
      _session = null;
      _setState(GuardianBootstrapManagerState.idle);
    }
    return healthy;
  }

  /// Releases the bootstrap proxy AFTER a successful authorization
  /// (Stage 6 owns WHEN this happens — the renewal policy). The route
  /// memory survives.
  Future<void> release() async {
    if (_disposed) return;
    await _teardownProxy();
    _session = null;
    if (_state == GuardianBootstrapManagerState.authorized) {
      _setState(GuardianBootstrapManagerState.stopping);
      _setState(GuardianBootstrapManagerState.stopped);
    }
  }

  /// Stops everything: an in-flight operation fails with `cancelled`
  /// at its next checkpoint (or the seam-await race), the active proxy
  /// is torn down, and the state reaches `stopped`.
  Future<void> stop() async {
    if (_disposed) return;
    _stopRequested = true;
    if (!_events.isClosed) _stopSignal.add(null);
    if (_state != GuardianBootstrapManagerState.idle &&
        _state != GuardianBootstrapManagerState.stopped) {
      _setState(GuardianBootstrapManagerState.stopping);
    }
    final op = _op;
    if (op != null) {
      try {
        await op;
      } catch (_) {
        // the cancelled operation's own error — stop owns the terminal
      }
    }
    await _teardownProxy();
    _session = null;
    if (_state != GuardianBootstrapManagerState.idle) {
      _setState(GuardianBootstrapManagerState.stopped);
    }
    _stopRequested = false;
  }

  /// Network-change notification (mission §7.1: a change forces
  /// re-evaluation, never blind reuse). If the context REALLY changed,
  /// the current session is invalidated (proxy stopped, state idle);
  /// the memory is kept — the next [ensureAuthorized] re-evaluates it
  /// in the new context.
  Future<void> notifyNetworkContextChanged() async {
    if (_disposed) return;
    if (_state != GuardianBootstrapManagerState.authorized) return;
    final session = _session;
    if (session == null) return;
    final contextNow = await _networkContext.currentContextId();
    if (contextNow != session.contextId) {
      await _teardownProxy();
      _session = null;
      _setState(GuardianBootstrapManagerState.idle);
      _logSink?.call('network context changed — session invalidated');
    }
  }

  /// Releases everything and closes the event stream. Callbacks and
  /// streams after dispose are inert by construction.
  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await stop();
    } catch (_) {
      // stop never throws in practice; belt and braces
    }
    _disposed = true;
    await _events.close();
    await _stopSignal.close();
  }

  // ---- internals ------------------------------------------------------------

  void _checkStop() {
    if (_stopRequested || _disposed) {
      throw const GuardianBootstrapException('cancelled');
    }
  }

  /// Races [future] against a stop request so cancellation reaches an
  /// in-flight seam await without waiting for the seam's own timeout.
  /// The seam contract already demands timeout-honoring behavior; this
  /// is the manager's own propagation layer (mission §4-5).
  Future<T> _raceStop<T>(Future<T> future) async {
    if (_stopRequested) {
      throw const GuardianBootstrapException('cancelled');
    }
    final completer = Completer<T>();
    late final StreamSubscription<void> subscription;
    subscription = _stopSignal.stream.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          const GuardianBootstrapException('cancelled'),
        );
      }
    });
    unawaited(future.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    ));
    try {
      return await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  GuardianBootstrapException _fail(GuardianBootstrapException error) {
    _lastFailureCode = error.code;
    _setState(
      GuardianBootstrapManagerState.failed,
      errorCode: error.code,
      message: error.message,
    );
    return error;
  }

  Future<void> _teardownProxy() async {
    final proxy = _activeProxy;
    _activeProxy = null;
    if (proxy != null) {
      try {
        await proxy.stop();
      } catch (_) {
        // a torn-down proxy's own error — nothing left to do
      }
    }
  }

  void _setState(
    GuardianBootstrapManagerState state, {
    GuardianBootstrapRouteKind? routeKind,
    String? errorCode,
    String? message,
  }) {
    _state = state;
    if (_disposed || _events.isClosed) return;
    _events.add(GuardianBootstrapEvent(
      state,
      routeKind: routeKind,
      errorCode: errorCode,
      message: message,
    ));
  }
}
