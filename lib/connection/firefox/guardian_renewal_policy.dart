/// GUARDIAN-BOOTSTRAP STAGE 6 — the renewal & lifecycle policy
/// (docs/performance/FIREFOX_GUARDIAN_PSIPHON_BOOTSTRAP_PROGRESS.md,
/// mission §6: «Renewal و Lifecycle کامل» + «سیاست Psiphon»).
///
/// An explicit, testable policy object fed by REAL engine events —
/// never by parsed logs, never by assumed times:
///
///  * The authorization's remaining validity comes from the pass's own
///    `exp` claim (`passExpiresAt` on the engine's `passAcquired` /
///    `renewed` events — the pinned client's claim-time-corrected
///    `ExpiresAt()`). NO hardcoded pass lifetime exists anywhere in
///    this policy.
///
///  * While a session lives on a bootstrap route (the engine was
///    spawned with `apiProxy`), that route IS the renewal path: the
///    pinned engine's renewal loop calls the same
///    `GET /api/v1/fpn/token` through the SAME installed control-plane
///    transport (Stage 5's RoutingRoundTripper seat — proven by the
///    Go renewal-loop tests). Releasing the route early would break
///    the CURRENT renewal (mission: «خاموش‌کردن Psiphon نباید باعث
///    شکست Renewal بعدی شود»), so the default is KEEP.
///
///  * Every successful renewal ROTATES the pass (a fresh raw token is
///    swapped onto the live session in-engine; the host never sees it)
///    and pushes the expiry out — the keep window re-arms. Rotation is
///    the normal steady state, not an event.
///
///  * The keep REASON ends at the pass's own expiry plus the pinned
///    engine's post-expiry renewal budget (`proxyPassRenewTimeout`,
///    2 min — controller.go; the moment the engine parks itself with
///    `renewalTimeout` when it cannot renew). That deadline — derived
///    from the real response, not assumed — is the backstop that
///    releases the bootstrap even if a session teardown was missed
///    (mission: «Psiphon بدون دلیل دائماً فعال باقی نماند»; no orphan
///    bootstrap process/listener).
///
///  * The session teardown (disconnect → `_hardCleanup` →
///    `manager.stop()`, Stage 5) is the PRIMARY release; this
///    supervisor only cancels its timer there. Engine death, quota
///    exhaustion and walk failures all funnel into that teardown —
///    the expiry deadline remains armed in between as the bound.
///
///  * Reactivation (mission: «اگر Renewal بعداً به Proxy احتیاج داشت،
///    Manager بتواند آن را مجدداً فعال کند»): `release()`/`stop()`
///    keep the manager instance, the singleflight and the file-backed
///    route memory alive, so the NEXT `ensureAuthorized()` — e.g. the
///    reconnect walk after the engine parked on renewal timeout —
///    rebuilds the route; the evidence-forwarding seam falls through
///    to the REAL probe for renewal-time calls that carry no prior
///    evidence. The supervisor deliberately does NOT auto-rebuild in
///    the background (mission §7.1: nothing runs while no one asks);
///    the reconnect walk is the ask.
///
///  * Direct-spawned sessions (`apiProxy` empty) hold no bootstrap
///    resource: the supervisor tracks their renewal facts for
///    diagnostics but never releases anything. If a direct engine's
///    renewal starts answering 451, the engine retries (30 s cadence)
///    and then parks itself (`renewalTimeout`, exit 3); the reconnect
///    walk re-runs the whole direct/bootstrap decision — the fixed
///    spawn-time `apiProxy` of the pinned engine makes an in-place
///    transport switch impossible, and faking one is forbidden.
library;

import 'dart:async';

import 'firefox_protocol.dart';

/// The grace added to the pass's own expiry before the bootstrap is
/// released: EXACTLY the pinned engine's post-expiry renewal budget
/// (`proxyPassRenewTimeout` = 2 min, internal/upstream/controller.go —
/// the budget `renew()` itself gets once the pass has expired). This
/// is a CONTRACT constant mirrored from the pinned source, not an
/// assumed lifetime; the deadline itself always comes from the real
/// response's `exp` claim.
const Duration kGuardianRenewalGrace = Duration(minutes: 2);

/// An immutable snapshot of the renewal facts (diagnostics + the
/// Stage-7 UI surfaces; contains no secrets — expiry timestamps,
/// quota strings and class codes only).
class GuardianRenewalFacts {
  const GuardianRenewalFacts({
    this.viaBootstrapProxy = false,
    this.sessionActive = false,
    this.passExpiresAt,
    this.quotaLeft = '',
    this.quotaReset = '',
    this.renewalFailures = 0,
    this.lastRenewalFailCode,
    this.lastRenewalRetryInMs = 0,
    this.releases = 0,
  });

  /// Whether the CURRENT session's engine was spawned with apiProxy
  /// (a bootstrap route exists that renewal traverses).
  final bool viaBootstrapProxy;

  /// Whether a session is attached (spawn begun, teardown not yet run).
  final bool sessionActive;

  /// The pass's own expiry (claim-time corrected by the engine); null
  /// until the first passAcquired/renewed with a parseable timestamp.
  final DateTime? passExpiresAt;

  final String quotaLeft;
  final String quotaReset;

  /// How many renewalFailed events this session saw (the engine keeps
  /// retrying — this is a health signal, not a failure state).
  final int renewalFailures;
  final String? lastRenewalFailCode;
  final int lastRenewalRetryInMs;

  /// How many times the expiry backstop released a bootstrap (0 or 1
  /// per session; diagnostics).
  final int releases;
}

/// The Stage-6 renewal & lifecycle supervisor: one per app (built with
/// the Stage-5 integration), attached per engine spawn by the adapter.
///
/// The release callback ([onBootstrapExpired]) fires AT MOST once per
/// armed window and only while a bootstrap-proxied session's pass has
/// actually expired (plus the engine's own park budget). The adapter
/// wires it to `manager.release()` — NOT `stop()`: the instance, the
/// singleflight and the route memory survive for the reactivation.
class GuardianRenewalSupervisor {
  GuardianRenewalSupervisor({
    required this.onBootstrapExpired,
    this.renewalGrace = kGuardianRenewalGrace,
    DateTime Function()? now,
    this.onLog,
  }) : _now = now ?? DateTime.now;

  /// Invoked when the expiry backstop fires (the authorization the
  /// bootstrap served has run out plus the engine's own budget). Must
  /// be idempotent and never throw.
  final Future<void> Function() onBootstrapExpired;

  /// The engine's own post-expiry budget mirrored from the pinned
  /// source (see [kGuardianRenewalGrace]).
  final Duration renewalGrace;

  final DateTime Function() _now;

  /// Redacted diagnostics sink (class codes and timestamps only).
  final void Function(String line)? onLog;

  Timer? _releaseTimer;
  bool _viaBootstrapProxy = false;
  bool _sessionActive = false;
  DateTime? _passExpiresAt;
  String _quotaLeft = '';
  String _quotaReset = '';
  int _renewalFailures = 0;
  String? _lastRenewalFailCode;
  int _lastRenewalRetryInMs = 0;
  int _releases = 0;
  bool _disposed = false;

  /// The current renewal facts (diagnostics/UI snapshot).
  GuardianRenewalFacts get facts => GuardianRenewalFacts(
        viaBootstrapProxy: _viaBootstrapProxy,
        sessionActive: _sessionActive,
        passExpiresAt: _passExpiresAt,
        quotaLeft: _quotaLeft,
        quotaReset: _quotaReset,
        renewalFailures: _renewalFailures,
        lastRenewalFailCode: _lastRenewalFailCode,
        lastRenewalRetryInMs: _lastRenewalRetryInMs,
        releases: _releases,
      );

  /// Whether the expiry backstop is currently armed (test/diagnostics
  /// observability; never a readiness signal).
  bool get releaseArmed => _releaseTimer != null;

  // ---- session lifecycle (wired by the adapter) ----------------------------

  /// A new engine spawn began. [viaBootstrapProxy] is true when the
  /// spawn carries `apiProxy` (fast path or 451 escalation): its
  /// renewal will traverse the bootstrap route, so the keep policy
  /// engages. Direct spawns keep the facts flowing but never release.
  void attachSession({required bool viaBootstrapProxy}) {
    if (_disposed) return;
    _viaBootstrapProxy = viaBootstrapProxy;
    _sessionActive = true;
    onLog?.call(
      'guardian-renewal: session attached '
      '${viaBootstrapProxy ? 'via bootstrap proxy' : 'direct'}',
    );
  }

  /// One engine event (the supervisor filters the renewal lifecycle
  /// names; everything else is ignored). The adapter forwards the
  /// events of the CURRENT spawn only.
  void onEngineEvent(FirefoxEngineEvent event) {
    if (_disposed) return;
    switch (event.name) {
      case FirefoxEngineEvents.passAcquired:
      case FirefoxEngineEvents.renewed:
        _onPassLifecycle(
          expiresAt: event.passExpiresAt,
          quotaLeft: event.quotaLeft,
          quotaReset: event.quotaReset,
          rotation: event.name == FirefoxEngineEvents.renewed,
        );
      case FirefoxEngineEvents.renewalFailed:
        _renewalFailures++;
        _lastRenewalFailCode =
            event.failCode.isEmpty ? null : event.failCode;
        _lastRenewalRetryInMs = event.retryInMs;
        onLog?.call(
          'guardian-renewal: renewal failed '
          '(${_lastRenewalFailCode ?? 'unclassified'}), '
          'engine retries in ${event.retryInMs} ms',
        );
      case FirefoxEngineEvents.quotaExhausted:
        // Terminal for the ENGINE (it parks with exit 2); the teardown
        // owns the release. The expiry backstop stays armed as the
        // bound in case the teardown never arrives.
        onLog?.call('guardian-renewal: quota exhausted — the engine is '
            'parking; the teardown owns the bootstrap release');
      default:
        break;
    }
  }

  /// The engine process is gone (outcome resolved — clean stop, walk
  /// failure, crash, park). The supervisor does NOT release here: the
  /// walk may respawn through the same route (the §5-4 escalation),
  /// and every death path funnels into the adapter's `_hardCleanup`,
  /// which is the single owner of the teardown. The expiry backstop
  /// stays armed — it is precisely the bound for a missed teardown.
  void onEngineGone() {
    if (_disposed) return;
    _sessionActive = false;
    onLog?.call('guardian-renewal: engine gone — teardown owns the '
        'release; the expiry backstop stays armed');
  }

  /// The DEFINITIVE session end (the adapter's `_hardCleanup`): the
  /// bootstrap is being stopped with the session it served (Stage 5);
  /// the supervisor cancels its backstop — nothing may fire after the
  /// teardown. A later walk re-attaches and re-arms from its own real
  /// events.
  void onSessionTeardown() {
    if (_disposed) return;
    _cancelTimer();
    _sessionActive = false;
    _viaBootstrapProxy = false;
    onLog?.call('guardian-renewal: session torn down — backstop cancelled');
  }

  /// Releases the supervisor itself (app shutdown): cancel the timer;
  /// no orphan timer survives the object.
  void dispose() {
    _cancelTimer();
    _disposed = true;
  }

  // ---- internals ------------------------------------------------------------

  void _onPassLifecycle({
    required String expiresAt,
    required String quotaLeft,
    required String quotaReset,
    required bool rotation,
  }) {
    _quotaLeft = quotaLeft;
    _quotaReset = quotaReset;
    final parsed = DateTime.tryParse(expiresAt);
    if (parsed == null) {
      // A legacy/hostile engine without a parseable timestamp: keep the
      // facts, arm NOTHING (an assumed deadline is forbidden — the
      // teardown path remains the only release).
      onLog?.call(
        'guardian-renewal: ${rotation ? 'rotation' : 'pass acquired'} '
        'without a parseable expiry — backstop not armed',
      );
      return;
    }
    _passExpiresAt = parsed;
    if (!_viaBootstrapProxy) {
      onLog?.call(
        'guardian-renewal: ${rotation ? 'pass rotated' : 'pass acquired'}, '
        'expiry $expiresAt — direct session, nothing to keep',
      );
      return;
    }
    _armBackstop(parsed, rotation: rotation);
  }

  void _armBackstop(DateTime expiry, {required bool rotation}) {
    _cancelTimer();
    final now = _now();
    final deadline = expiry.add(renewalGrace);
    var wait = deadline.difference(now);
    if (wait.isNegative) wait = Duration.zero;
    onLog?.call(
      'guardian-renewal: ${rotation ? 'rotation re-armed' : 'backstop armed'}'
      ' — keep the bootstrap until the pass expires '
      '(${deadline.difference(now).isNegative ? 'already expired' : '${deadline.difference(now).inMinutes} min left'} '
      'plus the engine\'s own ${renewalGrace.inMinutes} min budget)',
    );
    _releaseTimer = Timer(wait, _onDeadline);
  }

  Future<void> _onDeadline() async {
    _releaseTimer = null;
    if (_disposed) return;
    _releases++;
    onLog?.call(
      'guardian-renewal: the authorization expired (plus the engine\'s '
      'own budget) — releasing the bootstrap; a later authorization '
      'rebuilds it on demand',
    );
    try {
      await onBootstrapExpired();
    } catch (error) {
      // The callback's own error never leaves an armed timer behind.
      onLog?.call('guardian-renewal: release callback failed: $error');
    }
  }

  void _cancelTimer() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }
}
