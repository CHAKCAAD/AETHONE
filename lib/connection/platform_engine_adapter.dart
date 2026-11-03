/// PlatformEngineAdapter — the M2 production adapter that wires the REAL
/// cores to the UI (architecture B+, prompt §3/§7):
///
///  * **Aether (Rust/WARP)** runs IN-PROCESS through its C API
///    (`libaether.so`, see [AetherCore]) with the exact CLI flags of the
///    pinned commit — the mapping lives in [AetherArguments] below and is
///    evidence-locked to `docs/CLI_REFERENCE.md` + `transport_modes.dart`.
///  * **zeptun (Zig/TUN)** is started by the Android `VpnService` through its
///    own JNI bridge (`libzeptun-jni.so`, class `dev.zeptun.Zeptun`) — only
///    in «تونل» mode.
///  * **Connected** is emitted ONLY after the end-to-end probe
///    ([TunnelProbe]) succeeded through the tunnel (§6.6) — the probe also
///    produces the real ping and exit-country values.
///
/// Honest gaps (documented, not hidden): SMART auto mode is not implemented
/// in the pinned core (SMART_AUTO_SPEC.md); the OS kill-switch/always-on
/// integration and the aether log line forwarding land with the diagnostics
/// step. Proxy mode serves the local SOCKS listener only.
library;

import 'dart:async';
import 'dart:io' show Platform, SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_assets.dart';
import 'aether_ffi.dart';
import 'connection_state.dart';
import 'engine.dart';
import 'tunnel_probe.dart';
import 'transport_modes.dart';

/// Builds the Aether CLI arguments (evidence-locked; pure and unit-tested).
///
/// v4.20 — the selection is TWO independent knobs (owner device test:
/// «منظورم این بود اول وایرگارد وصل شه و بعد سایفون نه اینکه کلا وایرگارد
/// به جاش وصل شه»):
///  * [protocol] — the WARP-leg tile (AUTO..MIM; WireGuard is the cold
///    default per the v4.19 decree). In a CHAIN mode this is the protocol
///    of the WARP tunnel the inner exit rides on — the core combines
///    `--protocol wg --psiphon` into "WireGuard WARP first, Psiphon over
///    it" (lib.rs L222-227: run_chain dials the held --bind listener).
///  * [chain] — the overlay family member (torChain…psiphonOnly) or null
///    for a plain connection.
class AetherArguments {
  static List<String> build({
    required ProtocolId protocol,
    ProtocolId? chain,
    String? countryCode,
    int scanSpeed = 5,
    required String filesDir,
    required String nativeLibraryDir,
  }) {
    final overlay = chain;
    final modeId = effectiveMode(protocol, overlay);
    final mode = TransportModes.byId(modeId);
    final args = <String>[
      // Listener + identity storage (writable app dir — the core creates
      // parents itself, config.rs write_private).
      '--bind', '127.0.0.1:1819',
      '--config', '$filesDir/aether/warp.toml',
      '--log-level', 'info',
      // Endpoint-scan profile («سرعت اسکن», 1..5 → the five pinned modes).
      '--scan', scanProfile(scanSpeed),
    ];

    // --- the WARP-leg protocol FIRST, then the overlay on top of it —
    // the args read exactly like the owner's decree («اول وایرگارد وصل شه
    // و بعد سایفون»): --protocol wg --psiphon = WireGuard WARP first,
    // Psiphon over it.
    args.addAll(protocolArgs(protocol, overlay));

    // --- the overlay family's own flag (cli.rs L584-600) ---
    if (overlay != null) {
      switch (overlay) {
        case ProtocolId.torChain:
          args.add('--tor');
        case ProtocolId.torReverse:
          args.add('--tor-reverse');
        case ProtocolId.torOnly:
          args.add('--tor-only');
        case ProtocolId.psiphonChain:
          args.add('--psiphon');
        case ProtocolId.psiphonReverse:
          args.add('--psiphon-reverse');
        case ProtocolId.psiphonOnly:
          args.add('--psiphon-only');
        default:
          break; // a plain tile — no overlay flag
      }
    }

    // --- tor family: the pluggable transport + a writable state dir.
    // The packaged PT is lyrebird (aether's own pt-build.sh builds
    // gitlab.torproject.org/.../lyrebird). bridges.rs search_dirs() only
    // scans DESKTOP paths (/usr/lib/tor/…, $HOME/.local/share/…) and the
    // binary is renamed liblyrebird.so for jniLibs extraction — without an
    // explicit --tor-pt the auto-bridge plan finds NO transport on Android
    // and Tor can never bootstrap (owner: «تور وصل نمیشه»). The protocol
    // claims mirror aether's own PT_BINARIES row for lyrebird
    // (bridges.rs L32-52); arti uses only the methods the binary itself
    // reports over the PT protocol, so an over-claim costs one failed
    // bridge, never a fake exit.
    if (overlay != null && overlay.isTor) {
      for (final pt in const [
        'obfs4',
        'snowflake',
        'webtunnel',
        'meek_lite',
        'obfs3',
        'scramblesuit',
      ]) {
        args.addAll(['--tor-pt', '$pt=$nativeLibraryDir/liblyrebird.so']);
      }
      // Explicit (not the warp.toml-sibling default) so tests + logs read
      // the same path the core uses.
      args.addAll(['--tor-dir', '$filesDir/aether/tor-state']);
    }

    // --- psiphon family: binary + writable state dir. The Go binary is
    // packaged renamed to libpsiphon.so so the installer extracts it with
    // the exec bit (extractNativeLibs) — evidence: psiphon.rs BINARY_NAMES
    // = psiphon-tunnel-core/psiphon and `--psiphon-bin` is "the
    // psiphon-tunnel-core binary to run" (cli.rs). v4.18 shipped
    // liblyrebird.so here — lyrebird is Tor's obfs4 PT, NOT the psiphon
    // client; fixed in v4.19 (owner device test: «از کارکرد تور و سایفون
    // مطمن نیستم»).
    if (overlay != null && overlay.isPsiphon) {
      args.addAll([
        '--psiphon-bin', '$nativeLibraryDir/libpsiphon.so',
        '--psiphon-dir', '$filesDir/aether/psiphon',
      ]);
    }

    // Country pinning — only where the core can actually honor it:
    //  * WARP-exit modes → --exit-loc (allow-list policy, exitloc.rs);
    //  * Psiphon-exit modes → --psiphon-region (lyrebird egress region);
    //  * Tor exits are what they are — passing a pin would be a lie.
    final country = countryCode?.trim().toUpperCase();
    if (country != null && country.length == 2) {
      if (mode.exitKind == ExitKind.warp) {
        args.addAll(['--exit-loc', country]);
      } else if (mode.exitKind == ExitKind.psiphonExit) {
        args.addAll(['--psiphon-region', country.toLowerCase()]);
      }
    }
    return args;
  }

  /// The mode the ENGINE actually runs: the overlay when one is selected,
  /// else the leg tile (AUTO resolves to the core's own default, MASQUE).
  static ProtocolId effectiveMode(ProtocolId leg, ProtocolId? overlay) {
    if (overlay != null) return overlay;
    return leg == ProtocolId.auto ? ProtocolId.masque : leg;
  }

  /// The `--protocol` argument pair(s) for the WARP leg, mapped per overlay
  /// family (evidence: lib.rs L131-139, L203-218, L229-244; cli.rs L637-653):
  ///  * ONLY modes return before the protocol session ever runs — pass the
  ///    core default so `select_protocol()`'s INTERACTIVE menu (lib.rs
  ///    L3281-3337) can never hang the headless job;
  ///  * REVERSE modes carry TCP only: the core REFUSES the UDP-to-WARP legs
  ///    (WireGuard, GOOL Classic) with its own error and forces the HTTP/2
  ///    carrier regardless — map those legs to MASQUE honestly (the
  ///    core's own error text blesses "--masque or --gool");
  ///  * CHAIN modes take the leg VERBATIM: `--protocol wg --psiphon` is
  ///    exactly "WireGuard WARP first, Psiphon over it".
  static List<String> protocolArgs(ProtocolId leg, ProtocolId? overlay) {
    if (overlay == ProtocolId.torOnly || overlay == ProtocolId.psiphonOnly) {
      return const ['--protocol', 'masque'];
    }
    var l = leg;
    if (overlay == ProtocolId.torReverse ||
        overlay == ProtocolId.psiphonReverse) {
      if (l == ProtocolId.auto ||
          l == ProtocolId.wireguard ||
          l == ProtocolId.goolClassic) {
        l = ProtocolId.masque;
      }
    }
    return switch (l) {
      ProtocolId.wireguard => const ['--protocol', 'wg'],
      ProtocolId.gool => const ['--protocol', 'gool'],
      // GOOL classic is NOT a protocol value: parser sets
      // AETHER_PROTOCOL=gool AND AETHER_GOOL_MODE=classic (cli.rs L644-647).
      ProtocolId.goolClassic => const ['--protocol', 'gool', '--gool-classic'],
      ProtocolId.mim => const ['--protocol', 'mim'],
      // masque + auto (auto = the core's own default) + unreachable family
      // members (the overlay, not the leg, carries those) all land on the
      // core default.
      _ => const ['--protocol', 'masque'],
    };
  }

  /// «سرعت اسکن» 1..5 → the five pinned scan profiles (CLI_REFERENCE #28-33).
  /// 5 = fastest (turbo, the sheet's default) … 1 = deepest (ironclad).
  static String scanProfile(int speed) => switch (speed.clamp(1, 5)) {
    5 => 'turbo',
    4 => 'balanced',
    3 => 'thorough',
    2 => 'verified',
    _ => 'ironclad',
  };
}

/// The zeptun TOML handed to `nativeStart` (zeptun config keys, frozen pin:
/// preset mobile + socks5 handler + fake-IP DNS = remote resolution through
/// the core; the fd is injected by the JNI bridge itself).
class ZeptunConfigToml {
  static String build({required int socksPort}) => '''
preset = "mobile"

[handler]
kind = "socks5"

[handler.socks5]
server = "127.0.0.1:$socksPort"

[dns]
fake_ip = true
''';
}

/// The production adapter. Talks to the platform over the `aethone/engine`
/// MethodChannel (see MainActivity.kt / AethoneVpnService.kt) and to Aether
/// over dart:ffi. One active connection at a time; disconnect always cleans
/// BOTH engines even if connect failed halfway.
class PlatformEngineAdapter implements EngineAdapter {
  PlatformEngineAdapter({Duration? statsInterval, this._coreFactory})
    : _statsInterval = statsInterval ?? const Duration(seconds: 5);

  static const MethodChannel _channel = MethodChannel('aethone/engine');

  /// Listener-bind budget: the core binds its listeners at START for every
  /// mode (lib.rs L128) — this wait is a cheap sanity bound; the real
  /// end-to-end wait lives in the probe-retry loop below.
  static const Duration _listenerBudget = Duration(seconds: 120);
  static const Duration _tunnelUpBudget = Duration(seconds: 30);
  static const Duration _probeTimeout = Duration(seconds: 20);
  static const Duration _permissionBudget = Duration(seconds: 180);
  /// v4.19 — how often the connect walk re-checks the core's health while
  /// waiting (owner device test #2: the app must FOLLOW the core — a core
  /// that dies during registration must fail the walk with the CORE's own
  /// error, not a generic listener timeout).
  static const Duration _coreHealthInterval = Duration(seconds: 1);

  /// v4.20 — pause between end-to-end probe attempts. The chain/only
  /// listeners are held-bound BEFORE their inner protocol is ready (a
  /// SOCKS greeting on them simply hangs — socks.rs L1931 test) — the walk
  /// RETRIES the probe until the mode's own ready budget runs out instead
  /// of failing on the first 20 s attempt (owner: «تور وصل نمیشه»,
  /// «سایفون وصل نمیشه» — both were this walk bug, not core failures).
  static const Duration _probeRetryInterval = Duration(seconds: 2);

  /// The end-to-end ready budget per effective mode, mirroring the core's
  /// own timeouts (psiphon.rs READY_TIMEOUT 180 s; tor.rs DIRECT_PROBE 75 s
  /// + BRIDGE_PROBE 360 s; plain WARP = registration + scan ≈ listener
  /// budget).
  static Duration readyBudget(ProtocolId mode) => switch (mode) {
    ProtocolId.torChain ||
    ProtocolId.torReverse ||
    ProtocolId.torOnly => const Duration(seconds: 360),
    ProtocolId.psiphonChain ||
    ProtocolId.psiphonReverse ||
    ProtocolId.psiphonOnly => const Duration(seconds: 210),
    _ => const Duration(seconds: 120),
  };

  final Duration _statsInterval;
  final AetherCoreApi Function()? _coreFactory;
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  EngineConfigSource? _config;
  AetherCoreApi? _core;
  int? _jobId;
  Timer? _ticker;
  int _probeStrikes = 0;
  bool _connecting = false;
  bool _disconnecting = false;
  Completer<bool>? _tunnelUp;

  /// v4.20 — the platform's own reason a tunnel came down during the walk
  /// ("establish-failed", "start-threw:…", zeptun rc…) — carried into the
  /// tunnelStartFailed message so the failed screen can NAME the stage
  /// (owner: the tunnel failure was previously an anonymous miss).
  String? _tunnelDownReason;

  /// v4.20 — liveness of the tunnel leg while the walk is in flight: a
  /// service that dies between 'up' and Connected must NOT be papered over
  /// by a probe that only ever tests the LOCAL SOCKS listener.
  bool _tunnelAlive = false;
  Completer<bool>? _permissionAnswer;
  int _activePort = 1819;
  ConnectionMode _activeMode = ConnectionMode.proxy;

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  void bind(EngineConfigSource config) {
    _config = config;
    _channel.setMethodCallHandler(_onPlatformCall);
    _resyncAfterRestart();
  }

  @override
  Future<void> connect() async {
    if (_connecting) return;
    _connecting = true;
    _disconnecting = false;
    _probeStrikes = 0;
    _coreFailureDuringStart = null;
    try {
      await _connectInner();
    } on AetherFfiException catch (e) {
      _emitFail(e.code, e.message);
    } catch (e) {
      _emitFail('engineException', e.toString());
    } finally {
      _connecting = false;
    }
  }

  Future<void> _connectInner() async {
    final config = _config;
    if (config == null) {
      _emitFail('notBound', 'the adapter was never bound to a config source');
      return;
    }

    // Stale-state hygiene: never start a second core over a live one.
    await _hardCleanup();

    // v4.20 — the two selection knobs combine into the mode the engine
    // runs: the overlay (tor/psiphon family) rides on top of the WARP-leg
    // protocol tile (owner: «اول وایرگارد وصل شه و بعد سایفون»).
    final protocol = config.selectedProtocol;
    final overlay = config.selectedChain;
    final modeId = AetherArguments.effectiveMode(protocol, overlay);
    final mode = TransportModes.byId(modeId);
    final tunnel = config.connectionMode == ConnectionMode.tunnel;
    _activeMode = config.connectionMode;
    _activePort = mode.socksEndpoint.port;

    // --- 1. VPN permission (tunnel mode only) — asked BEFORE any core work
    // so a denial wastes no registration. The store is in `starting`.
    if (tunnel && !await _ensureVpnPermission()) {
      if (!_disconnecting) {
        _emitFail('vpnPermissionDenied', 'the VPN permission was not granted');
      } else {
        _emitState(VpnState.disconnected);
      }
      return;
    }

    // --- 1b. v4.20 (tunnel mode): the VpnService comes up FIRST, before the
    // core work. A foreground-service start is only legal while the app is
    // visible — the old order (core → up-to-120 s listener wait → startVpn)
    // raced the user backgrounding/locking the screen mid-walk and died
    // with ForegroundServiceStartNotAllowedException (owner: «اپ هنوز هم در
    // حالت تونل مشکل داره و وصل نمیشه»). zeptun tolerates a not-yet-serving
    // SOCKS target exactly like the core tolerates early clients (the
    // greeting is held), so bringing the TUN up early is safe — it is the
    // standard "connecting…" state every VPN app shows.
    if (tunnel) {
      _tunnelUp = Completer<bool>();
      _tunnelDownReason = null;
      _tunnelAlive = false;
      try {
        await _channel.invokeMethod<void>('startVpn', {'port': _activePort});
      } on PlatformException catch (e) {
        await _hardCleanup();
        _emitFail('vpnStartFailed', '${e.code}: ${e.message}');
        return;
      } on MissingPluginException {
        await _hardCleanup();
        _emitFail(
          'platformBridgeMissing',
          'the aethone/engine platform channel is not available in this build',
        );
        return;
      }
      final up = await _tunnelUp!.future.timeout(_tunnelUpBudget, onTimeout: () {
        return false;
      });
      _tunnelUp = null;
      _tunnelAlive = up;
      if (!up) {
        if (_disconnecting) return; // cancelled mid-tunnel (#3)
        await _hardCleanup();
        _emitFail(
          'tunnelStartFailed',
          _tunnelDownReason ?? 'zeptun did not come up',
        );
        return;
      }
    }

    // --- 2. Aether in-process (embedded core, architecture B+).
    _emitState(VpnState.connecting);
    final core = _core =
        _coreFactory == null ? AetherCore.open() : _coreFactory();
    final paths = await _paths();
    _jobId = core.coreStart(
      AetherArguments.build(
        protocol: protocol,
        chain: overlay,
        countryCode: config.selectedCountryCode,
        scanSpeed: config.scanSpeed,
        filesDir: paths.filesDir,
        nativeLibraryDir: paths.nativeLibraryDir,
      ),
    );

    // --- 2b. v4.19 (#7): proxy mode has no VpnService to hold the process,
    // so swiping the app away used to kill the in-process core. A tiny
    // foreground service (CoreHoldService) pins the process for the session
    // and is torn down on disconnect. The tunnel mode already has
    // AethoneVpnService in the foreground.
    if (!tunnel) {
      try {
        await _channel.invokeMethod<void>(
          'startCoreHold',
          {'port': _activePort},
        );
      } on PlatformException {
        // Hold failed — proxy still works while the app is foregrounded;
        // the honest resync on the next start reports the truth.
      } on MissingPluginException {
        // no platform (tests) — nothing to hold
      }
    }

    // --- 3. Wait for the SOCKS listener of the SELECTED mode (no fallback,
    // no guessing — prompt §12-الحاقیه). v4.19 (#2): while waiting, the
    // walk FOLLOWS the core — a job that exits on its own fails the walk
    // immediately with the core's own error (the core is the authority,
    // owner: «اپ باید تابع هسته ایتر باشه و ناموفق بودن اتصال رو از هسته
    // ایتر بگیره و منتظر اتصال هسته ایتر باشه»), and a user cancel aborts
    // the wait right away (#3).
    final ready = await _waitForListenerFollowingCore(
      _activePort,
      timeout: _listenerBudget,
    );
    if (!_disconnecting && !ready) {
      await _hardCleanup();
      if (_coreFailureDuringStart != null) {
        _emitFail('coreExited', _coreFailureDuringStart);
      } else {
        _emitFail(
          'engineStartTimeout',
          'the core did not serve 127.0.0.1:$_activePort within '
          '$_listenerBudget',
        );
      }
      return;
    }
    _coreFailureDuringStart = null;
    if (_disconnecting) return; // cancel owns the terminal state (#3)

    // --- 4. End-to-end probe with RETRIES — the ONLY path to Connected
    // (§6.6). v4.20: a single 20 s attempt failed every mode whose inner
    // protocol legitimately bootstraps slower than that (Psiphon up to 180 s,
    // Tor 75 s direct + up to 360 s over bridges) because aether binds the
    // listeners BEFORE the data path exists. The loop retries the probe
    // within the mode's own budget while still FOLLOWING the core — a core
    // that dies fails the walk immediately with its own error.
    final stats = await _probeUntilReadyFollowingCore(
      _activePort,
      budget: readyBudget(modeId),
    );
    if (_disconnecting) return; // cancelled during the probe (#3)
    if (stats == null) {
      await _hardCleanup();
      if (_coreFailureDuringStart != null) {
        _emitFail('coreExited', _coreFailureDuringStart);
      } else {
        _emitFail(
          'endToEndProbeFailed',
          'the ${mode.label} data path did not answer through '
          '127.0.0.1:$_activePort within ${readyBudget(modeId).inSeconds} s '
          '(the chained protocol can legitimately take tens of seconds to '
          'bootstrap)',
        );
      }
      return;
    }
    // v4.20 — the probe only ever tests the LOCAL SOCKS listener; a tunnel
    // leg that died between 'up' and here must never be papered over with
    // a fake Connected.
    if (tunnel && !_tunnelAlive) {
      await _hardCleanup();
      _emitFail(
        'tunnelDiedDuringWalk',
        _tunnelDownReason ?? 'the VPN service went down mid-connection',
      );
      return;
    }
    _emit(stats);
    _emitState(VpnState.connected);

    // --- 5. Steady state: stats + health (§6 health probe ⇒ reconnecting).
    _startTicker();
  }

  /// v4.19 (#2) — the core's last words when it died during the listener
  /// wait ("connection failure comes FROM the core").
  String? _coreFailureDuringStart;

  /// v4.20 — one core-liveness poll. Returns the core's own error when the
  /// job has ended (done/failed/poll-threw), null while it runs. Shared by
  /// the listener wait and the probe-retry loop.
  String? _pollCoreOnce() {
    final jobId = _jobId;
    final core = _core;
    if (core == null || jobId == null) return null;
    try {
      final poll = core.jobPoll(jobId);
      if (poll.body['state'] == 'done') {
        final result = poll.body['result'];
        final inner = result is Map ? result['state'] : null;
        return inner == null
            ? (poll.error ?? 'the core exited on its own')
            : 'the core exited on its own (state: $inner)';
      }
      if (!poll.ok) {
        return poll.error;
      }
    } on AetherFfiException catch (e) {
      return e.message ?? e.code;
    }
    return null;
  }

  /// The listener wait of the v4.19 walk: polls the listener AND the core's
  /// job liveness. Returns true when the listener is up; when the core
  /// exits first, records its own error in [_coreFailureDuringStart] and
  /// returns false. Aborts on cancel (#3).
  Future<bool> _waitForListenerFollowingCore(
    int port, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_disconnecting) return false;
      if (await TunnelProbe.isListenerReady(port)) return true;
      // Core liveness — the core owns the truth about its own failure.
      final failure = _pollCoreOnce();
      if (failure != null) {
        _coreFailureDuringStart = failure;
        return false;
      }
      await Future<void>.delayed(_coreHealthInterval);
    }
    return false;
  }

  /// v4.20 — the end-to-end probe RETRY loop (the single-shot probe failed
  /// every slow-bootstrapping mode: chain listeners are bound before their
  /// inner protocol exists, so the first SOCKS greeting simply hangs until
  /// the 20 s probe timeout). Retries within [budget] while following the
  /// core: a job that dies fails the walk immediately with the core's own
  /// error; a cancel aborts at the next checkpoint. Returns the successful
  /// probe's stats, or null (budget exhausted / core died / cancelled).
  Future<EngineStatsUpdated?> _probeUntilReadyFollowingCore(
    int port, {
    required Duration budget,
  }) async {
    final deadline = DateTime.now().add(budget);
    while (true) {
      if (_disconnecting) return null;
      try {
        final result = await TunnelProbe().trace(
          port: port,
          timeout: _probeTimeout,
        );
        return EngineStatsUpdated(
          pingMs: result.pingMs,
          exitCountryCode: result.exitCountryCode,
        );
      } catch (_) {
        // Probe failed — the core may have died; it owns the failure truth.
        final failure = _pollCoreOnce();
        if (failure != null) {
          _coreFailureDuringStart = failure;
          return null;
        }
        if (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(_probeRetryInterval);
          continue;
        }
        return null; // budget exhausted — honest timeout, not a fake exit
      }
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    // Release anyone still waiting on connect-phase events.
    _tunnelUp?.complete(false);
    _permissionAnswer?.complete(false);
    await _hardCleanup();
    if (!_controller.isClosed) {
      _emitState(VpnState.disconnected);
    }
    _disconnecting = false;
  }

  // ---- helpers -------------------------------------------------------------

  void _emit(EngineEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void _emitState(VpnState state) =>
      _emit(EngineStateChanged(state));

  void _emitFail(String code, String? message) =>
      _emit(EngineStateChanged(VpnState.failed, errorCode: code, message: message));

  Future<_PlatformPaths> _paths() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('paths');
    if (raw == null) {
      throw const AetherFfiException('pathsMissing', 'paths returned null');
    }
    return _PlatformPaths(
      filesDir: raw['filesDir'] as String? ?? '',
      nativeLibraryDir: raw['nativeLibraryDir'] as String? ?? '',
    );
  }

  /// Asks the platform whether the VPN consent is needed; when it is, waits
  /// for the user's answer (surfaced as `waitingForPermissions` first).
  Future<bool> _ensureVpnPermission() async {
    final Map<Object?, Object?> answer;
    try {
      answer =
          await _channel.invokeMethod<Map<Object?, Object?>>('prepareVpn') ??
          const {};
    } on MissingPluginException {
      _emitFail(
        'platformBridgeMissing',
        'the aethone/engine platform channel is not available in this build',
      );
      return false;
    }
    if (answer['needsPermission'] != true) return true;

    _emitState(VpnState.waitingForPermissions);
    _permissionAnswer = Completer<bool>();
    final granted = await _permissionAnswer!.future.timeout(
      _permissionBudget,
      onTimeout: () => false,
    );
    _permissionAnswer = null;
    return granted;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_statsInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_disconnecting) return;
    final core = _core;
    final jobId = _jobId;

    // 1. Core liveness (only when WE spawned the job this Dart lifetime; a
    //    resumed session has no job id and relies on the health probe).
    if (core != null && jobId != null) {
      try {
        final poll = core.jobPoll(jobId);
        final state = poll.body['state'];
        if (state == 'done') {
          final result = poll.body['result'];
          final inner = result is Map ? result['state'] : null;
          await _onEngineDied(
            inner == 'stopped' ? 'engineStopped' : 'engineClosed',
            'the core exited on its own (state: $inner)',
          );
          return;
        }
        if (!poll.ok) {
          await _onEngineDied('engineFailed', poll.error);
          return;
        }
      } on AetherFfiException {
        await _onEngineDied('enginePollFailed', 'job poll threw');
        return;
      }
    }

    // 2. Real stats: zeptun counters (tunnel mode) + a fresh end-to-end
    //    probe for ping/exit-country.
    int? rxBytes;
    int? txBytes;
    if (_activeMode == ConnectionMode.tunnel) {
      try {
        final counters =
            await _channel.invokeMethod<Map<Object?, Object?>>(
              'zeptunCounters',
            ) ??
            const {};
        rxBytes = (counters['rxBytes'] as num?)?.toInt();
        txBytes = (counters['txBytes'] as num?)?.toInt();
      } on PlatformException {
        // The service may be mid-stop; stats are best-effort, the health
        // probe below is the authority.
      }
    }
    try {
      final result = await TunnelProbe().trace(
        port: _activePort,
        timeout: _probeTimeout,
      );
      _probeStrikes = 0;
      _emit(
        EngineStatsUpdated(
          pingMs: result.pingMs,
          exitCountryCode: result.exitCountryCode,
          downBytes:
              (txBytes ?? 0) < 0
                  ? 0
                  : txBytes ?? 0, // TUN tx = into the device = download
          upBytes:
              (rxBytes ?? 0) < 0 ? 0 : rxBytes ?? 0, // TUN rx = upload
        ),
      );
    } catch (_) {
      _probeStrikes++;
      if (_probeStrikes >= 2) {
        _probeStrikes = 0;
        _emit(const EngineHealthProbeFailed());
      }
    }
  }

  /// The core died while we believed we were connected: stop faking, tear
  /// everything down, report failed (any → failed is legal, §8).
  Future<void> _onEngineDied(String code, String? message) async {
    _ticker?.cancel();
    _ticker = null;
    _jobId = null;
    if (_activeMode == ConnectionMode.tunnel) {
      try {
        await _channel.invokeMethod<void>('stopVpn');
      } on PlatformException {
        // already down — nothing else to do
      }
    } else {
      // v4.19 (#7): release the proxy hold too — a dead core must not keep
      // the process pinned.
      try {
        await _channel.invokeMethod<void>('stopCoreHold');
      } on PlatformException {
        // already down
      }
    }
    _emitFail(code, message);
  }

  /// Full teardown: zeptun (via the service) + the core-hold service (proxy)
  /// + aether job. Safe to call in any state, twice, or when nothing is
  /// running.
  Future<void> _hardCleanup() async {
    _ticker?.cancel();
    _ticker = null;
    _tunnelUp?.complete(false);
    _tunnelUp = null;
    _permissionAnswer?.complete(false);
    _permissionAnswer = null;
    if (_activeMode == ConnectionMode.tunnel) {
      try {
        await _channel.invokeMethod<void>('stopVpn');
      } on PlatformException {
        // already stopped
      } on MissingPluginException {
        // no platform (tests) — nothing to stop
      }
    } else {
      // v4.19 (#7): proxy mode — release the process hold so an idle app
      // costs nothing in the background.
      try {
        await _channel.invokeMethod<void>('stopCoreHold');
      } on PlatformException {
        // already stopped
      } on MissingPluginException {
        // no platform (tests)
      }
    }
    final jobId = _jobId;
    final core = _core;
    _jobId = null;
    if (jobId != null && core != null) {
      try {
        core.jobCancel(jobId);
        // Cooperative cancel: give the runtime a moment, then free the
        // registry entry either way (free cancels again by contract).
        for (var i = 0; i < 10; i++) {
          final poll = core.jobPoll(jobId);
          if (poll.body['state'] == 'done') break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        core.jobFree(jobId);
      } on AetherFfiException {
        // job already gone
      }
    }
  }

  // ---- platform → Dart -----------------------------------------------------

  Future<void> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onTunnelEvent':
        final args = (call.arguments as Map?)?.cast<Object?, Object?>();
        final event = args?['event'] as String?;
        switch (event) {
          case 'up':
            _tunnelAlive = true;
            _tunnelUp?.complete(true);
          case 'down':
          case 'revoked':
            // v4.20 — keep the platform's own reason (establish-failed,
            // start-threw:<Ex>, destroy…) for the failed screen, and track
            // the leg's liveness for the walk's post-probe honesty check.
            _tunnelAlive = false;
            _tunnelDownReason = (args?['reason'] as String?) ?? event;
            _tunnelUp?.complete(false);
            // Revocation while connected is a user-side kill: surface it
            // immediately instead of waiting for the next health probe.
            if (!_connecting && !_disconnecting) {
              _ticker?.cancel();
              _ticker = null;
              _jobId = null;
              _emitFail(
                'tunnelRevoked',
                'the VPN was revoked (system UI or another VPN took over)',
              );
            }
          case 'permission':
            _permissionAnswer?.complete(args?['granted'] == true);
        }
      default:
        throw MissingPluginException(
          'unknown aethone/engine method: ${call.method}',
        );
    }
  }

  /// If the Flutter engine was restarted while a foreground service kept
  /// the session alive, resume the honest state instead of showing
  /// `disconnected` while the device is actually tunnelled/proxied.
  /// v4.19 (#7): BOTH holders are recognized — AethoneVpnService (tunnel)
  /// and CoreHoldService (proxy) — so re-entering the app after swiping it
  /// away shows the TRUE state (owner: «وقتی وارد اپ میشم مجدد میره رو حالت
  /// اتصال مجدد»). Proxy resume relies on the in-process core still
  /// listening on the held port (same process — CoreHoldService kept it
  /// alive); if the listener is gone the session is honestly dead.
  Future<void> _resyncAfterRestart() async {
    if (!Platform.isAndroid) return;
    try {
      final status =
          await _channel.invokeMethod<Map<Object?, Object?>>('vpnStatus') ??
          const {};
      if (status['running'] == true) {
        final port = (status['port'] as num?)?.toInt() ?? 1819;
        if (!await TunnelProbe.isListenerReady(port)) {
          // Service alive but the core is gone — stop the zombie service; the
          // user reconnects through the normal flow.
          await _channel.invokeMethod<void>('stopVpn');
          return;
        }
        await _resumeSession(port, ConnectionMode.tunnel);
        return;
      }
      // Proxy mode: the core-hold service keeps the process (and the
      // in-process core) alive after the app was swiped away.
      final hold =
          await _channel.invokeMethod<Map<Object?, Object?>>('coreHoldStatus') ??
          const {};
      if (hold['running'] != true) return;
      final port = (hold['port'] as num?)?.toInt() ?? 1819;
      if (!await TunnelProbe.isListenerReady(port)) {
        // Process alive but the core is gone — release the hold; the user
        // reconnects through the normal flow.
        await _channel.invokeMethod<void>('stopCoreHold');
        return;
      }
      await _resumeSession(port, ConnectionMode.proxy);
    } on PlatformException {
      // platform not ready yet — the next connect() will sort it out
    } on SocketException {
      // probe failed — treat as not connected
    }
  }

  /// The shared resume walk (legal per §8: starting → connecting →
  /// connected) once a live listener on [port] was proven.
  Future<void> _resumeSession(int port, ConnectionMode mode) async {
    final result = await TunnelProbe().trace(port: port);
    _activePort = port;
    _activeMode = mode;
    _emitState(VpnState.starting);
    _emitState(VpnState.connecting);
    _emit(
      EngineStatsUpdated(
        pingMs: result.pingMs,
        exitCountryCode: result.exitCountryCode,
      ),
    );
    _emitState(VpnState.connected);
    _startTicker();
  }

  @visibleForTesting
  Future<void> debugTick() => _tick();
}

class _PlatformPaths {
  const _PlatformPaths({required this.filesDir, required this.nativeLibraryDir});

  final String filesDir;
  final String nativeLibraryDir;
}
