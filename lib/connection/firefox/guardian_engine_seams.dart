/// GUARDIAN-BOOTSTRAP STAGE 5 — the REAL implementations of the Stage-4
/// seams (docs/performance/FIREFOX_GUARDIAN_PSIPHON_BOOTSTRAP_PROGRESS.md,
/// mission §5-4): the direct attempt and the through-the-proxy
/// authorization are REAL Guardian requests, made by the SAME engine
/// binary the tunnel walk spawns, in its new `--guardian-probe` role.
///
/// Why an engine probe and not a Dart HTTP client: the Guardian
/// control-plane transport (the pinned client's shared uTLS Firefox
/// ClientHello + the Stage-5 RoutingRoundTripper) lives INSIDE the Go
/// engine — reimplementing it in Dart would replace the existing
/// uTLS base for no reason (mission §5-2) and drift from the
/// production path. The probe role runs the production walk itself
/// (`AcquireInitialPass`: FetchProxyPass with the same-account FxA
/// recovery), through the same transport decision the tunnel role
/// would use — so a probe success IS an authorization, never a health
/// ping (mission §4-4).
///
/// The three pieces:
///  * [EngineGuardianProbe] — spawns `libfirefoxvpn --guardian-probe`
///    with or without `apiProxy`, classifies the outcome with Stage 1's
///    taxonomy (`guardianRegionUnavailable` is the ONLY region block);
///  * [EngineGuardianDirectAttempt] / [EngineGuardianAuthorizationVerifier]
///    — the seam adapters over the probe;
///  * [EvidenceForwardingGuardianDirectAttempt] — the one-shot carrier
///    for direct evidence the walk ALREADY collected (the main engine's
///    own 451): the manager's flow stays intact while the doomed
///    duplicate direct probe is skipped.
///
/// Security contract (unchanged from the engine's): argv carries only
/// the fixed role flag; every secret rides the stdin pipe; the
/// `authRefreshed` pair goes straight to the vault callback and is
/// never logged; every log line passes the engine's redaction.
library;

import 'dart:async';

import 'firefox_engine.dart';
import 'firefox_protocol.dart';
import 'firefox_errors.dart';
import '../../core/app_assets.dart';
import 'bootstrap_route_memory.dart';
import 'guardian_bootstrap_manager.dart';

/// The classified outcome of one probe run (Stage 1's taxonomy).
enum GuardianProbeKind {
  /// The authorization succeeded — a real pass was acquired.
  passAcquired,

  /// A REAL Guardian region block (HTTP 451 through the engine's
  /// Stage-1 classification) — the only bootstrap trigger.
  regionUnavailable,

  /// DNS/network/timeout from Remote Settings or Guardian with no
  /// HTTP response.
  transportUnavailable,

  /// HTTP rejection, quota, validation or authentication failure.
  otherFailure,

  /// The probe exceeded its budget; the process was stopped (no orphan).
  timeout,
}

class GuardianProbeResult {
  const GuardianProbeResult({
    required this.kind,
    this.failCode,
    this.message,
    this.failureStage = '',
    this.httpStatus = 0,
  });

  final GuardianProbeKind kind;

  /// The engine's own classified failCode on failures (the stable
  /// fferr codes — `guardianRegionUnavailable`, `sessionRejected`,
  /// `quotaExhausted`, …); null on success.
  final String? failCode;

  final String? message;
  final String failureStage;
  final int httpStatus;
}

bool _isBootstrapEligibleTransportFailure(
  String failCode,
  String failureStage,
  int httpStatus,
) {
  if (httpStatus != 0) return false;
  if (failureStage != 'remoteSettingsDiscovery' &&
      failureStage != 'guardianPass') {
    return false;
  }
  return failCode == FirefoxTransportError.timeout ||
      failCode == FirefoxTransportError.dnsError ||
      failCode == FirefoxTransportError.networkUnavailable;
}

/// Spawns the engine's `--guardian-probe` role and classifies the
/// outcome. One process per call — probes are short-lived by design
/// (no listener, no session, nothing to pool).
class EngineGuardianProbe {
  EngineGuardianProbe({
    required this.binaryPath,
    required this.authProvider,
    this.guardian = 'https://vpn.mozilla.org',
    this.transport = 'h2',
    this.logLevel = 'normal',
    this.onAuthRefreshed,
    this.onLog,
    this.shutdownGrace = const Duration(seconds: 3),
  });

  /// Absolute path of the engine binary (nativeLibraryDir on Android,
  /// a host binary in tests).
  final String binaryPath;

  /// Fresh auth for each probe (the vault read — tokens may have been
  /// refreshed since the last call).
  final Future<FirefoxSessionAuth> Function() authProvider;

  final String guardian;
  final String transport;
  final String logLevel;

  /// The probe's same-account recovery can refresh the OAuth pair —
  /// it goes STRAIGHT to the vault, never to a log.
  final void Function(FirefoxSessionAuth refreshed)? onAuthRefreshed;

  /// Redacted diagnostics sink (the engine's own lines; never tokens).
  final void Function(String line)? onLog;

  final Duration shutdownGrace;

  /// Runs one probe. [apiProxy] empty = the direct uTLS transport;
  /// non-empty = the Stage-5 RoutingRoundTripper routes the allowlisted
  /// Guardian request through that local proxy (FxA and Remote Settings
  /// stay direct inside the engine).
  Future<GuardianProbeResult> probe({
    String apiProxy = '',
    required Duration timeout,
  }) async {
    final FirefoxSessionAuth auth;
    try {
      auth = await authProvider();
    } catch (_) {
      return const GuardianProbeResult(
          kind: GuardianProbeKind.otherFailure, failCode: 'authUnavailable');
    }

    final engine = FirefoxVpnEngine(
      binaryPath: binaryPath,
      shutdownGrace: shutdownGrace,
      onLog: onLog,
    );
    var sawPassAcquired = false;
    try {
      final outcome = engine.start(
        FirefoxEngineConfig(
          // The probe binds NOTHING — the loopback placeholder only
          // satisfies the config contract (the engine validates it is
          // a loopback listen and never binds it in this role).
          socksListen: '127.0.0.1:0',
          auth: auth,
          guardian: guardian,
          transport: transport,
          logLevel: logLevel,
          apiProxy: apiProxy,
        ),
        args: const ['--guardian-probe'],
        onAuthRefreshed: onAuthRefreshed,
      );

      final passAcquired = Completer<void>();
      late final StreamSubscription<FirefoxEngineEvent> subscription;
      subscription = engine.events.listen((event) {
        if (event.name == FirefoxEngineEvents.passAcquired &&
            !passAcquired.isCompleted) {
          sawPassAcquired = true;
          passAcquired.complete();
        }
      });

      FirefoxEngineOutcome? result;
      try {
        result = await outcome.timeout(timeout, onTimeout: () {
          return const FirefoxEngineOutcome(
            state: FirefoxEngineState.failed,
            exitCode: -1,
            failCode: 'probeTimeout',
            message: 'the guardian probe exceeded its budget',
          );
        });
      } finally {
        await subscription.cancel();
      }

      if (result.state == FirefoxEngineState.failed) {
        if (result.failCode == 'probeTimeout') {
          return const GuardianProbeResult(
            kind: GuardianProbeKind.timeout,
            failCode: 'timeout',
            failureStage: 'remoteSettingsDiscovery',
          );
        }
        if (result.failCode ==
            FirefoxEngineFailure.guardianRegionUnavailable) {
          return GuardianProbeResult(
            kind: GuardianProbeKind.regionUnavailable,
            failCode: result.failCode,
            message: result.message,
            failureStage: result.failureStage,
            httpStatus: result.httpStatus,
          );
        }
        return GuardianProbeResult(
          kind: _isBootstrapEligibleTransportFailure(
                  result.failCode, result.failureStage, result.httpStatus)
              ? GuardianProbeKind.transportUnavailable
              : GuardianProbeKind.otherFailure,
          failCode: result.failCode.isEmpty ? 'unknown' : result.failCode,
          message: result.message,
          failureStage: result.failureStage,
          httpStatus: result.httpStatus,
        );
      }
      // A clean exit: success ONLY with the engine's own passAcquired
      // event — never a bare exit code (no fake readiness).
      if (sawPassAcquired || passAcquired.isCompleted) {
        return const GuardianProbeResult(kind: GuardianProbeKind.passAcquired);
      }
      return const GuardianProbeResult(
        kind: GuardianProbeKind.otherFailure,
        failCode: 'probeNoResult',
        message: 'the probe exited without a passAcquired event',
      );
    } catch (error) {
      return GuardianProbeResult(
        kind: GuardianProbeKind.otherFailure,
        failCode: 'engineSpawnFailed',
        message: '$error',
      );
    } finally {
      // No orphan process survives a probe — clean stop drains the
      // engine's own graceful path and escalates to a kill if needed.
      try {
        await engine.stop();
      } catch (_) {
        // already torn down
      }
      await engine.dispose();
    }
  }
}

/// The REAL direct-attempt seam (Stage 4's `GuardianDirectAttempt`):
/// the Guardian request over the engine's direct uTLS transport.
class EngineGuardianDirectAttempt implements GuardianDirectAttempt {
  EngineGuardianDirectAttempt({required this.probe});

  final EngineGuardianProbe probe;

  @override
  Future<GuardianDirectResult> attempt({Duration timeout = const Duration(seconds: 30)}) async {
    final result = await probe.probe(timeout: timeout);
    switch (result.kind) {
      case GuardianProbeKind.passAcquired:
        return const GuardianDirectResult(
            outcome: GuardianDirectOutcome.success);
      case GuardianProbeKind.regionUnavailable:
        return GuardianDirectResult(
          outcome: GuardianDirectOutcome.regionUnavailable,
          errorCode: result.failCode ?? 'guardianRegionUnavailable',
          message: result.message,
        );
      case GuardianProbeKind.timeout:
      case GuardianProbeKind.transportUnavailable:
        return GuardianDirectResult(
          outcome: GuardianDirectOutcome.transportUnavailable,
          errorCode: result.failCode ?? 'timeout',
          message: result.message,
        );
      case GuardianProbeKind.otherFailure:
        return GuardianDirectResult(
          outcome: GuardianDirectOutcome.otherFailure,
          errorCode: result.failCode ?? 'unknown',
          message: result.message,
        );
    }
  }
}

/// The REAL authorization seam (Stage 4's `GuardianAuthorizationVerifier`):
/// the SAME Guardian request dialed through the winning bootstrap
/// route's local proxy by the engine's RoutingRoundTripper.
class EngineGuardianAuthorizationVerifier
    implements GuardianAuthorizationVerifier {
  EngineGuardianAuthorizationVerifier({required this.probe});

  final EngineGuardianProbe probe;

  @override
  Future<GuardianAuthorizationResult> verify(
    Uri proxyUrl, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await probe.probe(
      apiProxy: proxyUrl.toString(),
      timeout: timeout,
    );
    return GuardianAuthorizationResult(
      ok: result.kind == GuardianProbeKind.passAcquired,
      code: result.failCode ?? switch (result.kind) {
        GuardianProbeKind.passAcquired => 'ok',
        _ => 'unknown',
      },
      message: result.message,
    );
  }
}

/// The one-shot evidence carrier for direct answers the walk ALREADY
/// collected: the firefox walk's main engine spawn performs the real
/// direct Guardian request itself, so on a 451 the manager must not
/// repeat it. [forward] installs the classified result; the next
/// [attempt] consumes it (exactly once) and later calls fall through
/// to the inner attempt (the real probe — e.g. Stage 6's renewal-time
/// reauthorization, which has no prior evidence).
class EvidenceForwardingGuardianDirectAttempt implements GuardianDirectAttempt {
  EvidenceForwardingGuardianDirectAttempt({this.inner});

  /// The real direct attempt used once no forwarded evidence remains.
  final GuardianDirectAttempt? inner;

  GuardianDirectResult? _pending;

  /// Installs a classified direct answer produced by a REAL direct
  /// Guardian request that already happened (the walk's engine spawn).
  void forward(GuardianDirectResult evidence) => _pending = evidence;

  @override
  Future<GuardianDirectResult> attempt({Duration timeout = const Duration(seconds: 30)}) async {
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      return pending;
    }
    final real = inner;
    if (real == null) {
      return const GuardianDirectResult(
        outcome: GuardianDirectOutcome.otherFailure,
        errorCode: 'directUnavailable',
        message: 'no forwarded evidence and no direct attempt wired',
      );
    }
    return real.attempt(timeout: timeout);
  }
}

/// The assembled Stage-5 integration: the one-per-app manager wired to
/// the REAL engine seams, plus the evidence carrier the firefox walk
/// feeds its own 451 into.
class GuardianBootstrapEngineIntegration {
  GuardianBootstrapEngineIntegration._(
    this.manager,
    this.directEvidence,
  );

  /// The manager (singleflight, route memory, state machine — Stage 4).
  final GuardianBootstrapManager manager;

  /// The one-shot direct-evidence carrier (see
  /// [EvidenceForwardingGuardianDirectAttempt]).
  final EvidenceForwardingGuardianDirectAttempt directEvidence;

  /// Builds the full integration: the manager with the real engine
  /// probe seams, the single-bucket network context (the documented
  /// Stage-4 limitation stands until a permitted coarse source is
  /// wired), and the walk-exclusion guard.
  static GuardianBootstrapEngineIntegration build({
    required String filesDir,
    required String nativeLibraryDir,
    required Future<FirefoxSessionAuth> Function() authProvider,
    String guardian = 'https://vpn.mozilla.org',
    UserWalkGuard? userWalkActive,
    ProtocolId Function()? chainProtocolProvider,
    void Function(FirefoxSessionAuth refreshed)? onAuthRefreshed,
    void Function(String line)? onLog,
    Duration routeTtl = kDefaultRouteTtl,
    Duration routeCooldown = kDefaultRouteCooldown,
  }) {
    final probe = EngineGuardianProbe(
      binaryPath: '$nativeLibraryDir/libfirefoxvpn.so',
      authProvider: authProvider,
      guardian: guardian,
      onAuthRefreshed: onAuthRefreshed,
      onLog: onLog,
    );
    final directEvidence = EvidenceForwardingGuardianDirectAttempt(
      inner: EngineGuardianDirectAttempt(probe: probe),
    );
    final manager = GuardianBootstrapManager(
      filesDir: filesDir,
      nativeLibraryDir: nativeLibraryDir,
      directAttempt: directEvidence,
      authorizationVerifier: EngineGuardianAuthorizationVerifier(
        probe: probe,
      ),
      userWalkActive: userWalkActive,
      chainProtocolProvider: chainProtocolProvider,
      directTimeout: const Duration(seconds: 4),
      standaloneReadyBudget: const Duration(seconds: 30),
      routeTtl: routeTtl,
      routeCooldown: routeCooldown,
      onLog: onLog,
    );
    return GuardianBootstrapEngineIntegration._(manager, directEvidence);
  }
}
