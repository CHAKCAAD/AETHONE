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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  final ConnectionStateMachine _machine = ConnectionStateMachine();

  /// Single-flight guard (prompt §8: only one transition in flight).
  bool _operationInFlight = false;

  // ---- state surface consumed by the UI ----
  ConnectionState get state => _machine.current;

  bool get isConnected => state == ConnectionState.connected;

  String? lastErrorCode;
  String? lastErrorMessage;

  int? pingMs; // null ⇒ not measured; NEVER fabricated
  int downBytes = 0;
  int upBytes = 0;
  String? exitCountryCode; // null ⇒ unknown; no flag shown

  ProtocolId selectedProtocol = ProtocolId.masque; // Aether's real default

  HomeLook homeLook = HomeLook.one;
  AnimationStyle animationStyle = AnimationStyle.standard;

  /// Effective style after the OS reduce-motion clamp.
  AnimationStyle effectiveAnimationStyle(BuildContext context) {
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
    if (state == ConnectionState.connected ||
        state == ConnectionState.connecting ||
        state == ConnectionState.starting ||
        state == ConnectionState.waitingForPermissions ||
        state == ConnectionState.disconnecting) {
      return;
    }
    _operationInFlight = true;
    notifyListeners();
    try {
      switch (state) {
        case ConnectionState.failed:
        case ConnectionState.reconnecting:
          _apply(ConnectionState.connecting);
        default:
          _apply(ConnectionState.starting);
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
    if (state == ConnectionState.disconnected ||
        state == ConnectionState.disconnecting) {
      return;
    }
    _operationInFlight = true;
    notifyListeners();
    try {
      _apply(ConnectionState.disconnecting);
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
    if (state == ConnectionState.failed || state == ConnectionState.reconnecting) {
      await connect();
    }
  }

  void setHomeLook(HomeLook look) {
    if (homeLook == look) return;
    homeLook = look;
    notifyListeners();
  }

  void setAnimationStyle(AnimationStyle style) {
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
        if (eventState == ConnectionState.failed) {
          _fail(errorCode: errorCode, message: message);
        } else {
          _apply(eventState);
        }
      case EngineHealthProbeFailed():
        if (state == ConnectionState.connected) {
          _apply(ConnectionState.reconnecting);
        }
      case EngineEndpointChanged():
        // TODO(M2): track active endpoint for the ActiveTransportSession.
        break;
      case EngineStatsUpdated(:final pingMs, :final downBytes,
            :final upBytes, :final exitCountryCode):
        this.pingMs = pingMs;
        this.downBytes = downBytes;
        this.upBytes = upBytes;
        this.exitCountryCode = exitCountryCode;
      case EngineLogLine():
        break; // structured logging lands with the diagnostics page
    }
    notifyListeners();
  }

  void _apply(ConnectionState next) {
    // Dedupe: adapters may re-report the state the store already entered.
    if (next == _machine.current) return;
    if (!ConnectionStateMachine.isValidTransition(_machine.current, next)) {
      // An illegal jump is a bug in the adapter: fail loudly, never fake.
      _fail(
        errorCode: 'illegalTransition',
        message: '${_machine.current} → $next refused by the state machine',
      );
      return;
    }
    if (next == ConnectionState.disconnected ||
        next == ConnectionState.connecting) {
      // Leaving/never-reaching connected ⇒ no stale ping/exit data.
      pingMs = null;
      exitCountryCode = null;
      downBytes = 0;
      upBytes = 0;
    }
    _machine.transition(next);
  }

  void _fail({String? errorCode, String? message}) {
    lastErrorCode = errorCode;
    lastErrorMessage = message;
    // any → failed is always legal (prompt §8).
    _machine.transition(ConnectionState.failed);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
