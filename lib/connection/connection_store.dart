/// ConnectionStore — the UI-facing orchestrator (ChangeNotifier).
///
/// Implements prompt §8 rules:
///  * ONE transition in flight; multi-tap on the connect button is harmless;
///  * engine events drive the machine; illegal transitions are surfaced as
///    failures instead of silently swallowed;
///  * health-probe failure ⇒ `reconnecting`;
///  * appearance settings (home look, animation style) live here too until
///    the settings model step (M3) adds persistence.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_assets.dart';
import '../core/motion.dart';
import 'connection_state.dart';
import 'engine.dart';

/// The two selectable home-screen looks (owner: identical logic, different
/// layout — report §11.2).
enum HomeLook { one, two }

class ConnectionStore extends ChangeNotifier {
  ConnectionStore({EngineAdapter? engine})
    : _engine = engine ?? _defaultEngine() {
    _subscription = _engine.events.listen(_onEvent);
  }

  static EngineAdapter _defaultEngine() => PreviewEngineAdapter.allowed
      ? PreviewEngineAdapter()
      : EngineNotWiredAdapter();

  final EngineAdapter _engine;
  late final StreamSubscription<EngineEvent> _subscription;

  final VpnStateMachine _machine = VpnStateMachine();

  /// Single-flight guard (prompt §8: only one transition in flight).
  bool _operationInFlight = false;

  // ---- state surface consumed by the UI ----
  VpnState get state => _machine.current;

  bool get isConnected => state == VpnState.connected;

  String? lastErrorCode;
  String? lastErrorMessage;

  int? pingMs; // null ⇒ not measured; NEVER fabricated
  int downBytes = 0;
  int upBytes = 0;
  String? exitCountryCode; // null ⇒ unknown; no flag shown

  // ---- user preferences (settings main page, step 2) ----
  // These are USER-CHOSEN values rendered by the settings status cards
  // («هر سه کارت وضعیت به دادهٔ واقعی نگاشت شدند» — phase-1 report D2).
  // M2 feeds them to the cores; the engine never writes them.

  /// Protocol selection mode — AUTO (default) or SMART
  /// (SMART_AUTO_SPEC.md: SPEC REQUIRED / NOT IMPLEMENTED in the pinned
  /// core; the UI setting exists, the core handoff is M2).
  bool protocolModeSmart = false;

  /// Routing-rules country: 'ir' (default, design shows «Iran»), 'tm',
  /// 'ru', 'cn' or null = None (phase-1 report: IR/TM/RU/CN + None).
  String? routingRegion = 'ir';

  /// Kill switch preference — ON by default (design shows «ON»).
  bool killSwitch = true;

  /// Settings setters (notify; the settings page + status cards rebuild).
  void setProtocolModeSmart(bool smart) {
    if (protocolModeSmart == smart) return;
    protocolModeSmart = smart;
    notifyListeners();
  }

  void setRoutingRegion(String? code) {
    if (routingRegion == code) return;
    routingRegion = code;
    notifyListeners();
  }

  void setKillSwitch(bool on) {
    if (killSwitch == on) return;
    killSwitch = on;
    notifyListeners();
  }

  /// The location the USER picked on the flag wheel (v4.11, defect #8).
  /// The engine-reported [exitCountryCode] stays the only "connected to X"
  /// truth; this is the selector state the core will receive in M2.
  String? selectedCountryCode;

  /// Wheel selection commit (flag snap / tap). Ignored while an operation
  /// is in flight so the selector can never fight a running transition.
  void selectCountry(String code) {
    if (_operationInFlight) return;
    if (selectedCountryCode == code) return;
    selectedCountryCode = code;
    notifyListeners();
  }

  ProtocolId selectedProtocol = ProtocolId.masque; // Aether's real default

  HomeLook homeLook = HomeLook.one;
  MotionStyle animationStyle = MotionStyle.standard;

  /// Effective style after the OS reduce-motion clamp.
  MotionStyle effectiveMotionStyle(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduce ? clampForReduceMotion(animationStyle) : animationStyle;
  }

  // ---- actions ----

  /// Connect. Multi-tap safe: while an operation is in flight, subsequent
  /// taps are ignored (they do NOT queue a second transition).
  /// Retry from `failed`/`reconnecting` enters `connecting` directly
  /// (prompt §8: «از Failed یا Reconnecting هنگام تلاش مجدد به Connecting برو»).
  Future<void> connect() async {
    if (_operationInFlight) return;
    if (state == VpnState.connected ||
        state == VpnState.connecting ||
        state == VpnState.starting ||
        state == VpnState.waitingForPermissions ||
        state == VpnState.disconnecting) {
      return;
    }
    _operationInFlight = true;
    notifyListeners();
    try {
      switch (state) {
        case VpnState.failed:
        case VpnState.reconnecting:
          _apply(VpnState.connecting);
        default:
          _apply(VpnState.starting);
      }
      await _engine.connect();
    } catch (e) {
      _fail(errorCode: 'engineException', message: e.toString());
    } finally {
      _operationInFlight = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_operationInFlight) return;
    if (state == VpnState.disconnected || state == VpnState.disconnecting) {
      return;
    }
    _operationInFlight = true;
    notifyListeners();
    try {
      _apply(VpnState.disconnecting);
      await _engine.disconnect();
    } catch (e) {
      _fail(errorCode: 'engineException', message: e.toString());
    } finally {
      _operationInFlight = false;
      notifyListeners();
    }
  }

  /// Retry from Failed/Reconnecting → Connecting (prompt §8).
  Future<void> retry() async {
    if (state == VpnState.failed || state == VpnState.reconnecting) {
      await connect();
    }
  }

  void setHomeLook(HomeLook look) {
    if (homeLook == look) return;
    homeLook = look;
    notifyListeners();
  }

  void setMotionStyle(MotionStyle style) {
    if (animationStyle == style) return;
    animationStyle = style;
    notifyListeners();
  }

  // ---- engine event mapping ----

  void _onEvent(EngineEvent event) {
    switch (event) {
      case EngineStateChanged(
        state: final eventState,
        errorCode: final errorCode,
        message: final message,
      ):
        if (eventState == VpnState.failed) {
          _fail(errorCode: errorCode, message: message);
        } else {
          _apply(eventState);
        }
      case EngineHealthProbeFailed():
        if (state == VpnState.connected) {
          _apply(VpnState.reconnecting);
        }
      case EngineEndpointChanged():
        // TODO(M2): track active endpoint for the ActiveTransportSession.
        break;
      case EngineStatsUpdated(
        :final pingMs,
        :final downBytes,
        :final upBytes,
        :final exitCountryCode,
      ):
        this.pingMs = pingMs;
        this.downBytes = downBytes;
        this.upBytes = upBytes;
        this.exitCountryCode = exitCountryCode;
      case EngineLogLine():
        break; // structured logging lands with the diagnostics page
    }
    notifyListeners();
  }

  void _apply(VpnState next) {
    // Dedupe: adapters may re-report the state the store already entered.
    if (next == _machine.current) return;
    if (!VpnStateMachine.isValidTransition(_machine.current, next)) {
      // An illegal jump is a bug in the adapter: fail loudly, never fake.
      _fail(
        errorCode: 'illegalTransition',
        message: '${_machine.current} → $next refused by the state machine',
      );
      return;
    }
    if (next == VpnState.disconnected || next == VpnState.connecting) {
      // Leaving/never-reaching connected ⇒ no stale ping/exit data.
      pingMs = null;
      exitCountryCode = null;
      downBytes = 0;
      upBytes = 0;
    }
    _machine.transition(next);
    if (next == VpnState.connected) {
      // Owner v4.12: a SMALL haptic pulse the moment the connection really
      // lands (state-machine-verified, never on a fake/optimistic path).
      HapticFeedback.mediumImpact();
    }
  }

  void _fail({String? errorCode, String? message}) {
    lastErrorCode = errorCode;
    lastErrorMessage = message;
    // any → failed is always legal (prompt §8).
    _machine.transition(VpnState.failed);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
