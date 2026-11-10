/// STAGES 2+3 of the Guardian bootstrap mission
/// (docs/performance/FIREFOX_GUARDIAN_PSIPHON_BOOTSTRAP_PROGRESS.md):
/// a STANDALONE Psiphon local proxy (stage 2) and the EXISTING
/// AETHER → PSIPHON combination launched for bootstrap (stage 3) — both
/// for the Firefox Guardian control plane, started through the SAME
/// in-process Aether core FFI (`aether_core_start`) the connect walk
/// uses, with NO VpnService, NO TUN and NO route changes.
///
/// What this stage deliberately does NOT do (locked scope):
///  * it never sends a Guardian request (Stage 5);
///  * it never touches the Firefox engine's control-plane transport
///    (Stage 5's RoutingRoundTripper);
///  * it never starts a second VpnService or creates a TUN device — the
///    only platform surface it uses is dart:ffi (the Aether C API) plus
///    plain loopback sockets. This file deliberately imports neither
///    `package:flutter/services.dart` nor any channel: there is no
///    MethodChannel, no `startVpn`, no `startCoreHold` in it (asserted by
///    the source-contract test in test/psiphon_bootstrap_test.dart);
///  * the AETHER→PSIPHON combination is NOT reimplemented here: the
///    chain is the pinned core's own `--psiphon` mode (see the STAGE 3
///    section below) — this file only launches and manages it.
///
/// How the proxy port is chosen (the mission's «no log parsing» rule):
///  * the pinned core DOES accept `--bind 127.0.0.1:0` (psiphon.rs
///    `run_only` resolves `listener.local_addr()`), BUT its FFI surface
///    (ffi.rs, read in full at the pin) exposes NO runtime event API and
///    NO local-addr query — `aether_job_poll` answers only
///    `running`/`done`. The effective port of a port-0 bind is therefore
///    unknowable from Dart without parsing the captured core log, which
///    the mission forbids;
///  * so the manager picks the port itself: it binds a loopback
///    `ServerSocket` on port 0, reads the OS-chosen ephemeral port,
///    releases the socket and hands the CONCRETE `--bind` address to the
///    core. The port is random per start (never one of the pinned
///    1819/1820/1821/1822 — the OS ephemeral range on Linux/Android
///    starts at 32768, and the guard below re-checks), known by
///    construction, and fail-closed: if anything takes the port in the
///    release→core-bind window, the core's `socks::bind_listener` exits
///    with its frozen wording («the socks5 listener cannot use …»), the
///    job dies, and the manager retries on a fresh port.
///
/// Readiness (the mission's «an open port is NOT ready» rule) needs ALL
/// of these witnesses, in the pinned core's own causal order:
///  1. the core job is still `running` (polled like the connect walk);
///  2. the `--bind` listener completes a full SOCKS5 greeting AND a
///     CONNECT with ATYP=domain — the core only starts relaying that
///     listener to the psiphon child AFTER it observed the child's
///     `ListeningSocksProxyPort` notice AND a `Tunnels` notice with
///     count > 0 (psiphon.rs `start()`: `tunnelled && socks_port`
///     breaks the notice loop, then `relay_to` serves the held
///     listener), so a completed handshake through the relay
///     transitively proves the psiphon tunnel is UP and its internal
///     listener is live;
///  3. the domain-name CONNECT proves remote DNS — the name is resolved
///     by psiphon through the tunnel, never locally;
///  4. a real HTTPS round trip over that tunnel (full certificate +
///     hostname verification, never weakened) proves TLS-through-proxy.
///
/// Lifecycle is single-flight by design: concurrent `start()` callers
/// share ONE core job (the mission's «multiple Guardian requests must
/// not spawn multiple Psiphons»), stop/cancel/free mirror the connect
/// walk's own core-teardown sequence, and the psiphon child cannot be
/// orphaned — the pinned core spawns it `kill_on_drop(true)` and the
/// FFI job cancel drops the `run_only`/`run_chain` future, dropping
/// the child.
///
/// STAGE 3 — the AETHER → PSIPHON chain mode
/// ([PsiphonBootstrapMode.aetherPsiphonChain]). The mission is explicit
/// («حالت‌های ترکیبی از قبل وجود دارن»): the combination ALREADY EXISTS
/// in the project — nothing about the chain itself is reimplemented
/// here. What this stage adds is a SECOND launch recipe for the SAME
/// in-process FFI core that starts the project's own `--psiphon` chain
/// mode on DEDICATED EPHEMERAL ports, plus its readiness/lifecycle
/// wiring:
///
///  * the pinned core's chain (psiphon.rs `run_chain`, L940-968): it
///    holds the `--psiphon-bind` listener from its start, waits for the
///    WARP tunnel to answer on the `--bind` listener
///    (`wait_for_proxy(through)`), then spawns psiphon with
///    `UpstreamProxyURL = socks5://<--bind>` and relays the egress
///    listener to psiphon's system-picked internal port. AETHONE dials
///    ONLY the egress; the probe, health ticker and endpoint all target
///    it — the WARP `--bind` port is never dialed by AETHONE.
///  * ports: TWO Dart-pre-bound ephemeral loopback ports (the stage-2
///    no-log-parsing rule applies twice — the FFI exposes no local-addr
///    query), always DISTINCT from each other and never 1819/1820/1821/
///    1822. Distinctness is loop-prevention leg one: the egress and the
///    WARP upstream can never be the same socket.
///  * loop prevention, the rest: the chain never passes `--upstream`
///    (only the reverse modes use one); the full `AETHER_*` wipe before
///    every start kills any leftover `AETHER_UPSTREAM` /
///    `AETHER_PSIPHON_BIND` a previous session could have left to bend
///    the chain back on itself; and the pinned core hardcodes psiphon's
///    upstream to exactly the `--bind` address — three distinct
///    addresses (bind, psiphon-internal, psiphon-bind), no cycle.
///    `AETHER → PSIPHON → AETHER` is impossible by construction.
///  * readiness: the SAME multi-witness probe, dialed at the egress. A
///    completed SOCKS5 greeting + domain CONNECT + verified TLS round
///    trip through the egress relay transitively proves the whole chain
///    is up: the core only starts relaying after `wait_for_proxy`
///    answered (WARP up) AND psiphon reported `ListeningSocksProxyPort`
///    with `Tunnels > 0` through that WARP tunnel.
///  * WARP identity: `--config` defaults to the connect walk's own
///    `$filesDir/aether/warp.toml` (identity reuse — the core never
///    re-registers an identity file that is already there), and the
///    psiphon data dir stays the DEDICATED bootstrap dir of stage 2.
///    Stage-4 input, unchanged from stage 2: a bootstrap and a USER
///    connect walk must not run simultaneously (shared process env +
///    shared identity file) — the strategy manager owns that exclusion.
///  * budget: the chain default is 330 s — the walk's own two
///    sequential phase budgets summed (WARP listener 120 s + psiphon
///    family 210 s). The core stays the authority: its own errors
///    surface through `coreExited` long before a Dart-side `notReady`.
library;

import 'dart:async';
import 'dart:io';

import '../aether_ffi.dart';
import '../tunnel_probe.dart';
import '../../core/app_assets.dart';
// Environment hygiene: the in-process core reads the PROCESS env, so a
// previous aether session's leftovers (AETHER_UPSTREAM, AETHER_PSIPHON_
// BIND, …) must be wiped before every bootstrap start — the same
// discipline as the connect walk (v4.21 engineClosed fix).
import '../aether_env.dart' as aether_env;

/// The pinned listener map this bootstrap must never collide with
/// (transport_modes.dart + docs/CLI_REFERENCE.md): 1819 = aether `--bind`,
/// 1820 = `--tor-bind`, 1821 = `--psiphon-bind` (chain egress),
/// 1822 = the Firefox engine SOCKS. Ephemeral OS picks start at 32768 on
/// Linux/Android, so the guard below is a belt-and-braces contract, not
/// the actual defense.
const Set<int> kPinnedAethonePorts = <int>{1819, 1820, 1821, 1822};

/// Which of the mission's bootstrap routes this manager launches. Both
/// are the SAME in-process FFI core (`aether_core_start`); the modes are
/// the pinned core's own — `--psiphon-only` (stage 2) and the existing
/// `--psiphon` chain over the WARP `--bind` leg (stage 3). The mode is
/// fixed at construction: stage 4's strategy manager constructs one
/// manager per route decision and owns the ordering between them.
enum PsiphonBootstrapMode {
  /// Stage 2 — `--psiphon-only`: psiphon alone, no tunnel underneath.
  psiphonOnly,

  /// Stage 3 — the project's EXISTING `AETHER → PSIPHON` combination
  /// (`--psiphon`): the WARP tunnel comes up on `--bind` first, psiphon
  /// is dialed through it, and the usable egress is `--psiphon-bind`.
  aetherPsiphonChain,
}

/// Lifecycle states of the standalone bootstrap proxy. Stage 4's
/// Guardian Bootstrap Manager maps these onto its own state machine;
/// the names stay intentionally plain and behavior-separable.
enum PsiphonBootstrapState {
  /// Never started, or fully stopped after a clean [PsiphonBootstrapProxy.stop].
  idle,

  /// A core job is coming up; readiness is being probed.
  starting,

  /// The proxy answered the full probe; the endpoint is usable.
  ready,

  /// A stop/cancel is tearing the core job down.
  stopping,

  /// Terminal: the core died, timed out or failed to start.
  failed,
}

/// One state transition of the bootstrap proxy (typed event — the UI and
/// Stage 4 never parse log lines).
class PsiphonBootstrapEvent {
  const PsiphonBootstrapEvent(this.state, {this.errorCode, this.message});

  final PsiphonBootstrapState state;

  /// Set when [state] is [PsiphonBootstrapState.failed].
  final String? errorCode;

  final String? message;
}

/// The usable local proxy endpoint (loopback only, by construction).
class PsiphonProxyEndpoint {
  const PsiphonProxyEndpoint({required this.host, required this.port});

  /// Always the IPv4 loopback — the core binds what `--bind` names and
  /// this manager only ever names loopback.
  final String host;
  final int port;

  /// The URL Stage 5's RoutingRoundTripper will dial
  /// (`socks5://127.0.0.1:<port>` — remote DNS: names are resolved by
  /// psiphon, so socks5 and socks5h behave identically here).
  String get socksUrl => 'socks5://$host:$port';

  @override
  String toString() => 'PsiphonProxyEndpoint($socksUrl)';
}

/// Error taxonomy of the bootstrap proxy (stable codes; Stage 4 maps
/// them onto the Guardian flow's own failures).
class PsiphonBootstrapException implements Exception {
  const PsiphonBootstrapException(this.code, [this.message]);

  /// `libraryMissing` — libaether.so is not packaged in this build.
  /// `coreStartFailed` — the FFI rejected the argument list.
  /// `portConflict` — every port attempt hit a taken port.
  /// `coreExited` — the core job ended before readiness (carries the
  ///   core's own error, never a generic timeout).
  /// `notReady` — the ready budget ran out with the core still running.
  /// `cancelled` — stop() won the race with start().
  /// `disposed` — used after dispose().
  /// `notStarted` — an operation needing a live proxy found none.
  final String code;
  final String? message;

  @override
  String toString() =>
      'PsiphonBootstrapException($code${message == null ? '' : ': $message'})';
}

/// The readiness probe seam. The PRODUCTION implementation is
/// [SocksTlsReadyProbe] — a real SOCKS5 handshake, a domain CONNECT and
/// a verified TLS round trip. The seam exists so the MANAGER's lifecycle
/// logic is unit-testable without a live psiphon; the real probe has its
/// own real-socket tests (see test/psiphon_bootstrap_test.dart).
abstract class PsiphonReadyProbe {
  /// Throws on ANY failure — a caught exception means "not ready yet",
  /// never a silent pass. Must never weaken TLS verification.
  Future<void> verify({required int port, required Duration timeout});
}

/// The production readiness probe: reuses the app's own SOCKS5 client
/// ([TunnelProbe.socksConnect] — the same handshake the connect walk's
/// end-to-end probe uses) and then upgrades the tunnel to TLS with
/// `SecureSocket.secure` (full platform trust store + hostname
/// verification; `onBadCertificate` is deliberately never passed).
///
/// The default trace target is the same host the pinned core itself uses
/// for exit detection (exitloc.rs TRACE_HOST): www.cloudflare.com.
class SocksTlsReadyProbe implements PsiphonReadyProbe {
  const SocksTlsReadyProbe({
    this.traceHost = TunnelProbe.traceHost,
    this.tracePort = 443,
  });

  final String traceHost;
  final int tracePort;

  @override
  Future<void> verify({required int port, required Duration timeout}) async {
    // Witnesses 2+3: SOCKS5 greeting + CONNECT with ATYP=domain (the
    // name is resolved BY the tunnel, proving remote DNS). A bound but
    // not-yet-relaying listener makes this hang until `timeout` — that
    // is the honest "open port is not ready" failure.
    final tunnel = await TunnelProbe.socksConnect(
      port: port,
      host: traceHost,
      dstPort: tracePort,
      timeout: timeout,
    );
    SecureSocket? tls;
    try {
      // Witness 4: TLS through the tunnel, verification fully ON.
      //
      // CRITICAL (empirically pinned in the Stage-2 live tests):
      // `SecureSocket.secure` is called on the socket DIRECTLY, NOT on
      // `tunnel.detach()` — detach() cancels the handshake reader's
      // stream subscription, and cancelling an ACTIVE subscription on a
      // dart:io Socket terminates the socket's READ side (writes still
      // flow): the adopted-by-TLS subscription then reports EOF and the
      // handshake dies with «Connection terminated during handshake»
      // before the ClientHello ever leaves. With the subscription left
      // alive-and-paused (the StreamIterator pauses between reads),
      // `_detachRaw` hands the very subscription to the TLS layer and
      // the handshake completes. The same latent defect sits in the
      // egress_locations Onionoo path (detach→secure, silently caught,
      // always answered by the ip-api HTTP fallback) — recorded in the
      // progress file for the owner; NOT changed in this stage.
      tls = await SecureSocket.secure(tunnel.socket, host: traceHost)
          .timeout(timeout);
      tls.write(
        'GET /cdn-cgi/trace HTTP/1.1\r\n'
        'Host: $traceHost\r\n'
        'User-Agent: aethone-bootstrap-probe/1\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await tls.flush().timeout(timeout);
      final status = await _readStatusLine(tls, timeout);
      final code = int.tryParse(
        status.split(' ').length > 1 ? status.split(' ')[1] : '',
      );
      if (code == null || code < 200 || code >= 400) {
        throw SocketException(
          'trace through the proxy answered "$status"',
        );
      }
    } finally {
      // tls first: after secure() adopted the socket's subscription, the
      // tunnel reader is inert; destroying the TLS layer is the teardown.
      tls?.destroy();
      tunnel.destroy();
    }
  }

  /// Reads the first line of the HTTP response (up to `\r\n`), bounded
  /// by [timeout]. Any TLS/decode failure throws — never a pass.
  static Future<String> _readStatusLine(
    SecureSocket tls,
    Duration timeout,
  ) async {
    final completer = Completer<String>();
    late StreamSubscription<List<int>> subscription;
    final bytes = <int>[];
    subscription = tls.listen(
      (chunk) {
        if (completer.isCompleted) return;
        bytes.addAll(chunk);
        final text = String.fromCharCodes(bytes);
        final end = text.indexOf('\r\n');
        if (end >= 0) {
          completer.complete(text.substring(0, end));
        } else if (bytes.length > 8192) {
          completer.completeError(
            const SocketException('trace response status line too long'),
          );
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            const SocketException('trace response closed before a status line'),
          );
        }
      },
      cancelOnError: true,
    );
    try {
      return await completer.future.timeout(timeout);
    } finally {
      unawaited(subscription.cancel());
    }
  }
}

/// The standalone-or-chain Psiphon bootstrap proxy manager (stage 2+3
/// deliverable).
///
/// One instance owns at most ONE Aether core job. Construction is cheap;
/// [start] is single-flight (concurrent callers share one future), and
/// [stop]/[dispose] are idempotent. The manager never sees credentials
/// of any kind, so it has nothing to leak.
class PsiphonBootstrapProxy {
  PsiphonBootstrapProxy({
    required this.filesDir,
    required this.nativeLibraryDir,
    this.mode = PsiphonBootstrapMode.psiphonOnly,
    this.warpConfigPath,
    this.warpProtocol = ProtocolId.wireguard,
    this.scanProfile = 'turbo',
    this._psiphonBinPath,
    this._coreFactory,
    PsiphonReadyProbe? probe,
    this.readyBudget,
    this.probeTimeout = const Duration(seconds: 15),
    this.probeRetryInterval = const Duration(seconds: 2),
    this.healthInterval = const Duration(seconds: 15),
    this.cancelGrace = const Duration(seconds: 5),
    this.portFreeBudget = const Duration(seconds: 4),
    this.maxPortRetries = 3,
    this._onLog,
  }) : _probe = probe ?? const SocksTlsReadyProbe();

  /// The app's writable files dir (Android `Context.getFilesDir`) — the
  /// bootstrap data directory lives under it.
  final String filesDir;

  /// The app's native library dir (`nativeLibraryDir`) — where the
  /// packaged `libpsiphon.so` and `libaether.so` live.
  final String nativeLibraryDir;

  /// Which existing core mode this manager launches (stage 2 standalone
  /// or stage 3 chain). Fixed at construction; see the enum.
  final PsiphonBootstrapMode mode;

  /// Chain mode only — the WARP identity/config file the core reads
  /// (`--config`). Default: the connect walk's own
  /// `$filesDir/aether/warp.toml` (identity reuse; the core never
  /// re-registers an identity that is already there). Ignored in
  /// [PsiphonBootstrapMode.psiphonOnly] (only mode does no WARP work).
  final String? warpConfigPath;

  /// Chain mode only — the WARP leg protocol tile
  /// ([ProtocolId.wireguard] is the app's cold default, per the v4.19
  /// decree). Mapped exactly like the connect walk's leg for a
  /// `psiphonChain` overlay (equivalence-tested against
  /// `AetherArguments.protocolArgs`). Ignored in standalone mode.
  final ProtocolId warpProtocol;

  /// Chain mode only — the endpoint-scan profile handed to `--scan`
  /// (one of the five pinned profiles; `turbo` is the app's own
  /// default, the fastest first hit — the right shape for a bootstrap,
  /// and `--quick-reconnect` reuses the cached verified gateway when
  /// one exists, which is the mission's warm-path spirit at the core's
  /// own level). Validated at build time.
  final String scanProfile;

  /// Explicit psiphon binary path override (tests / exotic layouts).
  /// Default: `$nativeLibraryDir/libpsiphon.so` (the jniLibs name the
  /// installer extracts with the exec bit — psiphon.rs BINARY_NAMES).
  final String? _psiphonBinPath;

  /// The dart:ffi core seam. Production: [AetherCore.open] (the
  /// process-global library). Tests inject a fake.
  final AetherCoreApi Function()? _coreFactory;

  /// The readiness probe (production: [SocksTlsReadyProbe]).
  final PsiphonReadyProbe _probe;

  /// Whole-of-start budget override (core job spawn → full probe);
  /// null = the mode's own default. The standalone default mirrors the
  /// connect walk's psiphon family budget (210 s, deliberately above
  /// the pinned core's OWN `AETHER_PSIPHON_READY_SECS` default of 180 s
  /// so the core's «psiphon did not come up in time» surfaces first).
  /// The chain default is 330 s — the walk's two sequential phase
  /// budgets summed (WARP listener 120 s + psiphon family 210 s). The
  /// core stays the authority in both modes: its own errors surface
  /// through `coreExited` long before a Dart-side `notReady`.
  final Duration? readyBudget;

  /// The mode-aware effective start budget (see [readyBudget]).
  Duration get effectiveReadyBudget =>
      readyBudget ??
      (mode == PsiphonBootstrapMode.aetherPsiphonChain
          ? const Duration(seconds: 330)
          : const Duration(seconds: 210));

  /// Per-attempt probe timeout. A bound-but-not-yet-relaying listener
  /// (the core holds `--bind` from its start; the relay to the psiphon
  /// child begins only after the child's tunnel is up) makes the SOCKS
  /// greeting hang until this expires — the retry loop then re-probes.
  final Duration probeTimeout;

  /// Pause between probe attempts while the tunnel comes up.
  final Duration probeRetryInterval;

  /// Light health-cadence while ready: job-liveness + listener-alive.
  /// (The full probe runs on demand via [healthCheck].)
  final Duration healthInterval;

  /// How long stop() waits for the cancelled job to reach `done` before
  /// freeing the registry entry (the connect walk's _cancelGrace).
  final Duration cancelGrace;

  /// How long stop() waits for the listener port to refuse connections
  /// (bind-race hygiene for the NEXT start — the walk's _portFreeBudget).
  final Duration portFreeBudget;

  /// Extra port re-picks after a bind conflict before giving up.
  final int maxPortRetries;

  /// Debug/diagnostic line sink. Never receives secrets (the manager
  /// handles none). Off by default — nothing is logged by default.
  final void Function(String line)? _onLog;

  // ---- state ---------------------------------------------------------------

  final StreamController<PsiphonBootstrapEvent> _events =
      StreamController<PsiphonBootstrapEvent>.broadcast();

  PsiphonBootstrapState _state = PsiphonBootstrapState.idle;
  AetherCoreApi? _core;
  int? _jobId;
  int? _port;

  /// Chain mode only: the WARP-leg `--bind` port of the running job
  /// (never dialed by AETHONE; tracked only so stop() can wait for the
  /// listener to come free for the NEXT start). Null in standalone.
  int? _warpPort;
  Timer? _healthTicker;
  Future<PsiphonProxyEndpoint>? _starting;
  bool _stopRequested = false;
  bool _disposed = false;
  String? _lastFailureCode;

  /// Typed state transitions (broadcast; never log lines).
  Stream<PsiphonBootstrapEvent> get events => _events.stream;

  PsiphonBootstrapState get state => _state;

  /// The usable endpoint once [state] is ready; null otherwise.
  PsiphonProxyEndpoint? get endpoint => _state == PsiphonBootstrapState.ready
      ? PsiphonProxyEndpoint(host: '127.0.0.1', port: _port!)
      : null;

  /// The code of the last failure (diagnostics; null when none).
  String? get lastFailureCode => _lastFailureCode;

  // ---- argument building (pure; evidence-locked to the pin) ----------------

  /// The bootstrap data directory: DEDICATED and STABLE —
  /// `$filesDir/aether/psiphon-bootstrap`, deliberately NOT the
  /// user-facing modes' `$filesDir/aether/psiphon`
  /// (platform_engine_adapter AetherArguments). Two psiphon children on
  /// one data directory is unsafe (psiphon-tunnel-core assumes a single
  /// owner of its DataRootDirectory); the dedicated path also keeps the
  /// bootstrap's learned server list/tactics across runs without ever
  /// touching the user session's data.
  String get dataDir => '$filesDir/aether/psiphon-bootstrap';

  /// Builds the pinned core's CLI for `--psiphon-only` (translated to
  /// `AETHER_*` env vars by the core's own cli.rs parser):
  ///  * `--bind 127.0.0.1:<port>` — the loopback listener the core
  ///    holds from its start and relays to the psiphon child once the
  ///    child's tunnel is up (psiphon.rs `run_only`);
  ///  * `--psiphon-only` — no WARP/Aether tunnel underneath, no
  ///    UpstreamProxyURL, the child dials out itself with its ADAPTIVE
  ///    engine (server/protocol/tactics selection all left to
  ///    psiphon-tunnel-core: `--psiphon-mode` unset = auto);
  ///  * `--psiphon-bin` / `--psiphon-dir` — the packaged binary and the
  ///    dedicated stable data dir.
  ///
  /// Deliberately absent (each with its pin-locked reason):
  ///  * `--config` — only-mode returns before any WARP identity work
  ///    (lib.rs: psiphon::run_only at the top of run_with);
  ///  * `--upstream` — no Aether carrier in standalone mode;
  ///  * `--psiphon-bind`/`--psiphon-http` — chain-mode listener / extra
  ///    HTTP listener; the Guardian transport consumes socks5, and one
  ///    listener is the whole standalone surface;
  ///  * `--psiphon-region` — adaptive egress, no manual pin;
  ///  * `--scan`/`--quick-reconnect`/`-4` — WARP-scan-only flags, and
  ///    only mode never prompts on stdin (select_ip_version is called
  ///    only on the WARP paths, after the only-mode early return).
  static List<String> buildArgs({
    required int port,
    required String filesDir,
    required String nativeLibraryDir,
    String? psiphonBinPath,
  }) =>
      [
        '--bind', '127.0.0.1:$port',
        '--log-level', 'info',
        '--psiphon-only',
        '--psiphon-bin',
        psiphonBinPath ?? '$nativeLibraryDir/libpsiphon.so',
        '--psiphon-dir', '$filesDir/aether/psiphon-bootstrap',
      ];

  /// Builds the pinned core's CLI for the EXISTING `AETHER → PSIPHON`
  /// combination (stage 3) — the same flag family the connect walk's
  /// `psiphonChain` mode passes (AetherArguments.build + cli.rs), on
  /// DEDICATED ephemeral ports instead of the walk's fixed 1819/1821:
  ///  * `--bind 127.0.0.1:<bindPort>` — the WARP-leg socks listener the
  ///    core serves once the tunnel is up; in the chain it is ONLY the
  ///    upstream psiphon dials through (run_chain's `through`), never
  ///    dialed by AETHONE itself;
  ///  * `--psiphon-bind 127.0.0.1:<psiphonBindPort>` — the chain egress
  ///    listener, held from the core's start and relayed to psiphon's
  ///    internal listener once the whole chain is up. THE usable proxy
  ///    surface (the endpoint this manager exposes);
  ///  * `--config <warp.toml>` — the WARP identity/config, defaulting to
  ///    the walk's own file (identity reuse; the core never re-registers
  ///    an identity that is already there);
  ///  * `--scan <profile>` + `--quick-reconnect` — the walk's own two
  ///    determinism pins for the WARP leg: the scan profile is fixed
  ///    (never the interactive «Choose [1-5]»), and a cached VERIFIED
  ///    gateway is reused without rescanning (non-TTY stdin already
  ///    defaults to yes — this pins it explicitly);
  ///  * `--protocol <leg>` — the WARP leg, mapped exactly like the walk's
  ///    (see [warpProtocolArgs]);
  ///  * `--psiphon` — THE chain flag itself (cli.rs: plain `--psiphon` =
  ///    carry psiphon inside the tunnel; AETHER_PSIPHON=chain in the
  ///    core's own mode() test spellings «1/on/chain/yes»);
  ///  * `--psiphon-bin` / `--psiphon-dir` — the packaged binary and the
  ///    SAME dedicated stable bootstrap data dir as stage 2.
  ///
  /// Deliberately absent (each pin-locked):
  ///  * `--upstream` — only the reverse modes use one; run_chain sets
  ///    psiphon's upstream itself, to exactly the `--bind` address.
  ///    Passing one could only bend the chain back on itself;
  ///  * `--psiphon-http` — one SOCKS5 egress is the whole bootstrap
  ///    surface;
  ///  * `--psiphon-region` / `--psiphon-mode` — adaptive egress, no
  ///    manual pin (the mission's rule);
  ///  * `--exit-loc` — the WARP leg's exit country is not pinned either;
  ///  * `-4`/`-6`/`--dual` — no IP-version pin; the core picks.
  static List<String> buildChainArgs({
    required int bindPort,
    required int psiphonBindPort,
    required String filesDir,
    required String nativeLibraryDir,
    String? psiphonBinPath,
    String? warpConfigPath,
    ProtocolId warpProtocol = ProtocolId.wireguard,
    String scanProfile = 'turbo',
  }) {
    const pinnedProfiles = {
      'turbo',
      'balanced',
      'thorough',
      'verified',
      'ironclad',
    };
    if (!pinnedProfiles.contains(scanProfile)) {
      throw ArgumentError.value(
        scanProfile,
        'scanProfile',
        'must be one of the five pinned profiles (CLI_REFERENCE #28-33)',
      );
    }
    return [
      '--bind', '127.0.0.1:$bindPort',
      '--config', warpConfigPath ?? '$filesDir/aether/warp.toml',
      '--log-level', 'info',
      '--scan', scanProfile,
      '--quick-reconnect',
      ...warpProtocolArgs(warpProtocol),
      '--psiphon',
      '--psiphon-bind', '127.0.0.1:$psiphonBindPort',
      '--psiphon-bin',
      psiphonBinPath ?? '$nativeLibraryDir/libpsiphon.so',
      '--psiphon-dir', '$filesDir/aether/psiphon-bootstrap',
    ];
  }

  /// The WARP-leg `--protocol` pair(s) for the chain, mirroring the
  /// connect walk's own mapping for a `psiphonChain` overlay
  /// (`AetherArguments.protocolArgs(leg, ProtocolId.psiphonChain)` —
  /// CHAIN modes take the leg VERBATIM; auto and the family members
  /// fall to the core default masque). Kept as a separate copy so the
  /// bootstrap does not import the whole platform adapter; the
  /// equivalence is LOCKED by a test that loops over every [ProtocolId]
  /// and compares the two mappings.
  static List<String> warpProtocolArgs(ProtocolId leg) => switch (leg) {
        ProtocolId.wireguard => const ['--protocol', 'wg'],
        ProtocolId.gool => const ['--protocol', 'gool'],
        // GOOL classic is not a protocol value: the parser sets
        // AETHER_PROTOCOL=gool AND AETHER_GOOL_MODE=classic (cli.rs).
        ProtocolId.goolClassic => const [
            '--protocol',
            'gool',
            '--gool-classic',
          ],
        ProtocolId.mim => const ['--protocol', 'mim'],
        _ => const ['--protocol', 'masque'],
      };

  /// Picks a free loopback port by asking the OS (bind :0, read the
  /// port, release). The pinned listener map {1819..1822} is skipped
  /// defensively — the OS ephemeral range already excludes it on every
  /// supported platform, but the contract is cheap to assert where the
  /// port is chosen rather than where it is used.
  ///
  /// The release→core-bind window is a genuine (tiny) race; it is
  /// fail-closed by the core (bind_listener exits with its frozen
  /// «cannot use … already listens there» wording, the job dies) and
  /// retried by [start] with a fresh port.
  static Future<int> pickFreeLoopbackPort() async {
    for (var attempt = 0; attempt < 16; attempt++) {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      if (!kPinnedAethonePorts.contains(port)) return port;
    }
    throw const PsiphonBootstrapException(
      'portConflict',
      'the OS kept offering pinned ports — refusing to guess one',
    );
  }

  /// Chain mode's TWO ports: the WARP-leg `--bind` and the chain egress
  /// `--psiphon-bind`, pre-bound on loopback and ALWAYS DISTINCT from
  /// each other (loop-prevention leg one: the egress and the WARP
  /// upstream can never be the same socket, so the chain can never fold
  /// back onto itself) and from the pinned user-mode map.
  static Future<(int, int)> pickTwoDistinctLoopbackPorts() async {
    for (var attempt = 0; attempt < 16; attempt++) {
      final first = await pickFreeLoopbackPort();
      final second = await pickFreeLoopbackPort();
      if (second != first) return (first, second);
    }
    throw const PsiphonBootstrapException(
      'portConflict',
      'the OS would not name two distinct ports — refusing to guess',
    );
  }

  // ---- lifecycle -----------------------------------------------------------

  /// Starts the bootstrap proxy (standalone or chain, per [mode]) and
  /// resolves with its endpoint once the FULL readiness probe passed.
  /// Single-flight: concurrent callers share one core job and one
  /// future (the mission's one-bootstrap rule). After a failure the
  /// next [start] may be called again (Stage 4 owns the retry policy
  /// and cooldowns).
  Future<PsiphonProxyEndpoint> start() {
    if (_disposed) {
      throw const PsiphonBootstrapException('disposed');
    }
    final existing = _starting;
    if (existing != null) return existing;
    if (_state == PsiphonBootstrapState.ready) {
      return Future.value(endpoint);
    }
    _stopRequested = false;
    final future = _doStart();
    _starting = future;
    return future;
  }

  Future<PsiphonProxyEndpoint> _doStart() async {
    _setState(PsiphonBootstrapState.starting);
    _lastFailureCode = null;
    try {
      final endpoint = await _startInner();
      _setState(PsiphonBootstrapState.ready);
      _startHealthTicker();
      return endpoint;
    } on PsiphonBootstrapException catch (error) {
      // A stop() that won the race owns the terminal state — the start
      // future still fails with `cancelled` for anyone holding it, but
      // the state machine must not record a user stop as a failure.
      if (error.code != 'cancelled') {
        _lastFailureCode = error.code;
        _setState(
          PsiphonBootstrapState.failed,
          errorCode: error.code,
          message: error.message,
        );
      }
      rethrow;
    } finally {
      _starting = null;
    }
  }

  Future<PsiphonProxyEndpoint> _startInner() async {
    // The core handle: production opens the process-global library ONCE
    // (AetherCore.open is a singleton); tests inject their factory.
    final AetherCoreApi core;
    try {
      core = _coreFactory == null ? AetherCore.open() : _coreFactory();
    } on AetherFfiException catch (error) {
      _log('the embedded core is unavailable: ${error.code}');
      throw PsiphonBootstrapException(
        error.code == 'libraryMissing' ? 'libraryMissing' : 'coreStartFailed',
        error.message,
      );
    }

    // Environment hygiene — the SAME discipline as the connect walk
    // (v4.21): the in-process core's parser only SETS `AETHER_*` vars,
    // so leftovers of a previous session (AETHER_UPSTREAM,
    // AETHER_PSIPHON_BIND, AETHER_PSIPHON_HTTP, …) would silently change
    // this job's mode. The fresh arg list re-sets exactly what ONLY mode
    // reads; everything else must be unset.
    //
    // NOTE (Stage 4 input, documented honestly): the process env is
    // shared, so a bootstrap start must not race a USER aether connect
    // walk — the Stage 4 manager owns that exclusion. The Guardian flow
    // this serves runs the Firefox engine (a child process), where no
    // aether core job exists at all.
    aether_env.clearAetherEnvironment();

    for (var attempt = 0; attempt <= maxPortRetries; attempt++) {
      if (_stopRequested) {
        throw const PsiphonBootstrapException('cancelled');
      }
      // Mode-specific launch recipe: the argument list, the port the
      // readiness probe dials (the ENDPOINT), and — in chain mode —
      // the WARP-leg bind port that must come free again on stop.
      final List<String> args;
      final int endpointPort;
      final int? warpPort;
      switch (mode) {
        case PsiphonBootstrapMode.psiphonOnly:
          final port = await pickFreeLoopbackPort();
          args = buildArgs(
            port: port,
            filesDir: filesDir,
            nativeLibraryDir: nativeLibraryDir,
            psiphonBinPath: _psiphonBinPath,
          );
          endpointPort = port;
          warpPort = null;
        case PsiphonBootstrapMode.aetherPsiphonChain:
          final (bind, egress) = await pickTwoDistinctLoopbackPorts();
          args = buildChainArgs(
            bindPort: bind,
            psiphonBindPort: egress,
            filesDir: filesDir,
            nativeLibraryDir: nativeLibraryDir,
            psiphonBinPath: _psiphonBinPath,
            warpConfigPath: warpConfigPath,
            warpProtocol: warpProtocol,
            scanProfile: scanProfile,
          );
          endpointPort = egress;
          warpPort = bind;
      }
      final int jobId;
      try {
        jobId = core.coreStart(args);
      } on AetherFfiException catch (error) {
        _log('core start rejected: ${error.code}');
        throw PsiphonBootstrapException(
          error.code == 'libraryMissing' ? 'libraryMissing' : 'coreStartFailed',
          error.message,
        );
      }
      _core = core;
      _jobId = jobId;
      _port = endpointPort;
      _warpPort = warpPort;
      _log(
        mode == PsiphonBootstrapMode.aetherPsiphonChain
            ? 'core job $jobId started (aether→psiphon chain: warp '
                '127.0.0.1:$warpPort, egress 127.0.0.1:$endpointPort)'
            : 'core job $jobId started on 127.0.0.1:$endpointPort '
                '(psiphon-only)',
      );

      final outcome = await _waitUntilReady(endpointPort);
      if (outcome.ready) {
        return PsiphonProxyEndpoint(host: '127.0.0.1', port: endpointPort);
      }
      // The outcome carries why this attempt died; a bind conflict is
      // the retriable one (another process took a port in the
      // release→bind window — either of the chain's two).
      await _teardownJob();
      if (outcome.portConflict && attempt < maxPortRetries) {
        _log('a port was taken during hand-off; re-picking');
        continue;
      }
      throw PsiphonBootstrapException(outcome.code, outcome.message);
    }
    // Unreachable — every iteration returns or throws — but the analyzer
    // cannot prove it across the bounded for loop.
    throw const PsiphonBootstrapException(
      'portConflict',
      'no free loopback port accepted the hand-off',
    );
  }

  /// The start wait: follows the core (its own exit fails the wait with
  /// the CORE's words) while retrying the full readiness probe until the
  /// budget runs out. A stop() request aborts at the next checkpoint.
  Future<_WaitOutcome> _waitUntilReady(int port) async {
    final budget = effectiveReadyBudget;
    final deadline = DateTime.now().add(budget);
    while (true) {
      if (_stopRequested) {
        return const _WaitOutcome(
          ready: false,
          code: 'cancelled',
          message: 'stop() was requested during start',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        return _WaitOutcome(
          ready: false,
          code: 'notReady',
          message: 'the proxy did not pass the readiness probe within '
              '$budget (the core job was still running)',
        );
      }
      // Core liveness first — the core owns the truth about its own
      // failure (the connect walk's _pollCoreOnce discipline).
      final failure = _pollCoreOnce();
      if (failure != null) {
        // The pinned core's frozen bind-conflict wording (socks.rs
        // bind_listener): «the socks5 listener cannot use <addr>: …».
        // Evidence-locked string match, same convention as the egress
        // harvest's frozen-core line match.
        final conflict = failure.contains('listener cannot use');
        return _WaitOutcome(
          ready: false,
          code: conflict ? 'portConflict' : 'coreExited',
          message: failure,
          portConflict: conflict,
        );
      }
      try {
        await _probe.verify(port: port, timeout: probeTimeout);
        return const _WaitOutcome(ready: true, code: '', message: '');
      } catch (error) {
        // Not ready yet — a bound-but-unrelayed listener hangs here
        // until the probe timeout. Keep following the core.
        await Future<void>.delayed(probeRetryInterval);
      }
    }
  }

  /// One core-liveness poll: null while the job runs, the core's own
  /// error/reason once it ended (mirrors the walk's _pollCoreOnce).
  String? _pollCoreOnce() {
    final core = _core;
    final jobId = _jobId;
    if (core == null || jobId == null) return null;
    try {
      final poll = core.jobPoll(jobId);
      if (poll.body['state'] == 'done') {
        return poll.error ?? _describeJobOutcome(poll.body);
      }
      if (!poll.ok) {
        return poll.error;
      }
    } on AetherFfiException catch (error) {
      return error.message ?? error.code;
    }
    return null;
  }

  /// The honest reason a done job ended (same reading as the walk's
  /// describeJobOutcome: a normal stop carries result.state, a failed
  /// core carries result.error / ok=false).
  static String _describeJobOutcome(Map<Object?, Object?> body) {
    final result = body['result'];
    if (result is Map) {
      final inner = result['state'];
      if (inner is String) {
        return inner == 'stopped'
            ? 'the core was stopped (state: $inner)'
            : 'the core exited on its own (state: $inner)';
      }
      final error = result['error'];
      if (error is String && error.isNotEmpty) {
        return 'the core failed: $error';
      }
    }
    return 'the core exited on its own (state: null)';
  }

  /// Cancels the core job, waits (bounded) for it to reach `done`, frees
  /// the registry entry, then waits (bounded) for the listener ports to
  /// refuse connections — the connect walk's own stop sequence, applied
  /// to BOTH chain ports (the egress AND the WARP-leg bind) when the
  /// chain mode is running. The psiphon child is killed by the core
  /// itself (kill_on_drop on the dropped run_only/run_chain future), so
  /// no orphan process can survive this.
  Future<void> _teardownJob() async {
    _healthTicker?.cancel();
    _healthTicker = null;
    final core = _core;
    final jobId = _jobId;
    final port = _port;
    final warpPort = _warpPort;
    _core = null;
    _jobId = null;
    if (core != null && jobId != null) {
      try {
        core.jobCancel(jobId);
        final deadline = DateTime.now().add(cancelGrace);
        while (DateTime.now().isBefore(deadline)) {
          final poll = core.jobPoll(jobId);
          if (!poll.ok || poll.body['state'] == 'done') break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        core.jobFree(jobId);
      } on AetherFfiException {
        // the job was already gone from the registry
      }
    }
    // The egress first (standalone's only port; the chain's user-facing
    // one), then the chain's WARP-leg bind — bind-race hygiene for the
    // NEXT start, exactly like the walk's _portFreeBudget.
    await _awaitPortFree(port);
    await _awaitPortFree(warpPort);
  }

  /// Waits (bounded by [portFreeBudget]) for [port] to stop accepting
  /// connections; a null or already-refused port returns at once.
  Future<void> _awaitPortFree(int? port) async {
    if (port == null) return;
    final deadline = DateTime.now().add(portFreeBudget);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (!await TunnelProbe.isListenerReady(port)) break;
      } catch (_) {
        break; // refused — already free
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Stops the proxy. Idempotent; safe to call while a start is still
  /// in flight (the start future then fails with `cancelled`, and this
  /// call owns the terminal state — the walk's own disconnect rule).
  Future<void> stop() async {
    if (_disposed) return;
    _stopRequested = true;
    if (_state == PsiphonBootstrapState.ready ||
        _state == PsiphonBootstrapState.starting) {
      _setState(PsiphonBootstrapState.stopping);
    }
    final starting = _starting;
    if (starting != null) {
      // Let the in-flight start observe the request and unwind (its own
      // finally clears _starting). Its failure is expected — swallow.
      try {
        await starting;
      } catch (_) {
        // the cancelled start's own error — stop owns the terminal state
      }
    }
    await _teardownJob();
    _port = null;
    _warpPort = null;
    if (_state == PsiphonBootstrapState.idle) {
      _stopRequested = false;
      return;
    }
    if (_state != PsiphonBootstrapState.failed) {
      _setState(PsiphonBootstrapState.idle);
    }
    _stopRequested = false;
  }

  /// Stop + start again (a fresh port is picked; the data directory —
  /// and with it psiphon's learned server list and tactics — persists).
  Future<PsiphonProxyEndpoint> restart() async {
    if (_disposed) {
      throw const PsiphonBootstrapException('disposed');
    }
    await stop();
    return start();
  }

  /// On-demand FULL health check (core alive + listener + the complete
  /// SOCKS/TLS probe). The periodic ticker is deliberately lighter; this
  /// is the "prove it right now" call for Stage 4/6 renewal decisions.
  Future<bool> healthCheck() async {
    if (_disposed || _state != PsiphonBootstrapState.ready) return false;
    final port = _port;
    if (port == null) return false;
    final failure = _pollCoreOnce();
    if (failure != null) {
      _fail('coreDied', failure);
      return false;
    }
    try {
      await _probe.verify(port: port, timeout: probeTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Releases everything. Callbacks/streams after dispose are inert by
  /// construction (the ticker is cancelled, the event stream closed and
  /// every emitter is guarded).
  Future<void> dispose() async {
    if (_disposed) return;
    try {
      // Stop FIRST, then mark disposed: stop() is a no-op once
      // _disposed is set, so the order is what actually tears the core
      // job down (the pinned suite caught the inverted order).
      await stop();
    } catch (_) {
      // stop never throws in practice; belt and braces for dispose
    }
    _disposed = true;
    await _events.close();
  }

  // ---- internals -----------------------------------------------------------

  /// Light periodic health while ready: job liveness + the bound
  /// listener accepting TCP. A failure of either flips the state to
  /// failed (typed event) — Stage 4 decides what that means for the
  /// Guardian flow. Never re-enters; paused during stop.
  void _startHealthTicker() {
    _healthTicker?.cancel();
    _healthTicker = Timer.periodic(healthInterval, (_) => _healthTick());
  }

  Future<void> _healthTick() async {
    if (_disposed || _state != PsiphonBootstrapState.ready) return;
    final failure = _pollCoreOnce();
    if (failure != null) {
      _fail('coreDied', failure);
      return;
    }
    final port = _port;
    if (port == null) return;
    if (!await TunnelProbe.isListenerReady(port)) {
      _fail(
        'listenerDead',
        'the local proxy listener on 127.0.0.1:$port stopped accepting',
      );
    }
  }

  void _fail(String code, String message) {
    _lastFailureCode = code;
    unawaited(_teardownJob().then((_) {
      _port = null;
      _warpPort = null;
      _setState(
        PsiphonBootstrapState.failed,
        errorCode: code,
        message: message,
      );
    }));
  }

  void _setState(PsiphonBootstrapState state,
      {String? errorCode, String? message}) {
    _state = state;
    if (_disposed || _events.isClosed) return;
    _events.add(PsiphonBootstrapEvent(state, errorCode: errorCode,
        message: message));
  }

  void _log(String line) => _onLog?.call(line);
}

/// Internal result of the start wait.
class _WaitOutcome {
  const _WaitOutcome({
    required this.ready,
    required this.code,
    required this.message,
    this.portConflict = false,
  });

  final bool ready;
  final String code;
  final String message;
  final bool portConflict;
}
