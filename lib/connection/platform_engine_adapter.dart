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
class AetherArguments {
  /// [filesDir] is the app's writable files dir; [nativeLibraryDir] holds the
  /// packaged native libraries (lyrebird lives there).
  static List<String> build({
    required ProtocolId protocol,
    String? countryCode,
    int scanSpeed = 5,
    required String filesDir,
    required String nativeLibraryDir,
  }) {
    // AUTO (the sheet's default mode) means the core's own default protocol
    // — MASQUE; TransportModes carries no row for the synthetic `auto` enum
    // member (the switch below emits the matching --protocol masque args).
    final mode = protocol == ProtocolId.auto
        ? TransportModes.masque
        : TransportModes.byId(protocol);
    final args = <String>[
      // Listener + identity storage (writable app dir — the core creates
      // parents itself, config.rs write_private).
      '--bind', '127.0.0.1:1819',
      '--config', '$filesDir/aether/warp.toml',
      '--log-level', 'info',
      // Endpoint-scan profile («سرعت اسکن», 1..5 → the five pinned modes).
      '--scan', scanProfile(scanSpeed),
    ];

    // Protocol family (cli.rs parser arms; transport_modes.dart cliValue).
    switch (protocol) {
      case ProtocolId.masque:
        args.addAll(['--protocol', 'masque']);
      case ProtocolId.wireguard:
        args.addAll(['--protocol', 'wg']);
      case ProtocolId.gool:
        args.addAll(['--protocol', 'gool']);
      case ProtocolId.goolClassic:
        // GOOL classic is NOT a protocol value: parser sets
        // AETHER_PROTOCOL=gool AND AETHER_GOOL_MODE=classic (cli.rs L644-647).
        args.addAll(['--protocol', 'gool', '--gool-classic']);
      case ProtocolId.mim:
        args.addAll(['--protocol', 'mim']);
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
      case ProtocolId.auto:
        // AUTO defaults to the core's own default protocol (MASQUE).
        args.addAll(['--protocol', 'masque']);
    }

    // Psiphon modes need the PT binary + a writable state dir. The packaged
    // lyrebird is renamed lib*.so so the installer extracts it with the exec
    // bit (extractNativeLibs).
    if (mode.exitKind == ExitKind.psiphonExit ||
        protocol == ProtocolId.psiphonReverse) {
      args.addAll([
        '--psiphon-bin', '$nativeLibraryDir/liblyrebird.so',
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

  /// Listener-ready budget: first-run WARP registration + endpoint scanning
  /// legitimately take tens of seconds on a real device.
  static const Duration _listenerBudget = Duration(seconds: 120);
  static const Duration _tunnelUpBudget = Duration(seconds: 30);
  static const Duration _probeTimeout = Duration(seconds: 20);
  static const Duration _permissionBudget = Duration(seconds: 180);

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

    final protocol = config.selectedProtocol;
    // AUTO (the sheet's default mode) connects on the core's own default
    // protocol — MASQUE; TransportModes has no row for the synthetic
    // `auto` enum member.
    final mode = protocol == ProtocolId.auto
        ? TransportModes.masque
        : TransportModes.byId(protocol);
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

    // --- 2. Aether in-process (embedded core, architecture B+).
    _emitState(VpnState.connecting);
    final core = _core =
        _coreFactory == null ? AetherCore.open() : _coreFactory();
    final paths = await _paths();
    _jobId = core.coreStart(
      AetherArguments.build(
        protocol: protocol,
        countryCode: config.selectedCountryCode,
        scanSpeed: config.scanSpeed,
        filesDir: paths.filesDir,
        nativeLibraryDir: paths.nativeLibraryDir,
      ),
    );

    // --- 3. Wait for the SOCKS listener of the SELECTED mode (no fallback,
    // no guessing — prompt §12-الحاقیه).
    final ready = await TunnelProbe.waitForListener(
      _activePort,
      timeout: _listenerBudget,
    );
    if (!ready) {
      await _hardCleanup();
      _emitFail(
        'engineStartTimeout',
        'the core did not serve 127.0.0.1:$_activePort within '
        '$_listenerBudget',
      );
      return;
    }

    // --- 4. Tunnel mode: VpnService → TUN fd → zeptun (JNI bridge).
    if (tunnel) {
      _tunnelUp = Completer<bool>();
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
      if (!up) {
        await _hardCleanup();
        _emitFail('tunnelStartFailed', 'zeptun did not come up');
        return;
      }
    }

    // --- 5. End-to-end probe — the ONLY path to Connected (§6.6).
    try {
      final result = await TunnelProbe().trace(
        port: _activePort,
        timeout: _probeTimeout,
      );
      _emit(
        EngineStatsUpdated(
          pingMs: result.pingMs,
          exitCountryCode: result.exitCountryCode,
        ),
      );
      _emitState(VpnState.connected);
    } catch (e) {
      await _hardCleanup();
      _emitFail('endToEndProbeFailed', e.toString());
      return;
    }

    // --- 6. Steady state: stats + health (§6 health probe ⇒ reconnecting).
    _startTicker();
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
    }
    _emitFail(code, message);
  }

  /// Full teardown: zeptun (via the service) + aether job. Safe to call in
  /// any state, twice, or when nothing is running.
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
            _tunnelUp?.complete(true);
          case 'down':
          case 'revoked':
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

  /// If the Flutter engine was restarted while the foreground service kept
  /// the tunnel alive, resume the honest state instead of showing
  /// `disconnected` while the device is actually tunnelled.
  Future<void> _resyncAfterRestart() async {
    if (!Platform.isAndroid) return;
    try {
      final status =
          await _channel.invokeMethod<Map<Object?, Object?>>('vpnStatus') ??
          const {};
      if (status['running'] != true) return;
      final port = (status['port'] as num?)?.toInt() ?? 1819;
      if (!await TunnelProbe.isListenerReady(port)) {
        // Service alive but the core is gone — stop the zombie service; the
        // user reconnects through the normal flow.
        await _channel.invokeMethod<void>('stopVpn');
        return;
      }
      final result = await TunnelProbe().trace(port: port);
      _activePort = port;
      _activeMode = ConnectionMode.tunnel;
      // Legal walk for a resume: starting → connecting → connected (§8).
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
    } on PlatformException {
      // platform not ready yet — the next connect() will sort it out
    } on SocketException {
      // probe failed — treat as not connected
    }
  }

  @visibleForTesting
  Future<void> debugTick() => _tick();
}

class _PlatformPaths {
  const _PlatformPaths({required this.filesDir, required this.nativeLibraryDir});

  final String filesDir;
  final String nativeLibraryDir;
}
