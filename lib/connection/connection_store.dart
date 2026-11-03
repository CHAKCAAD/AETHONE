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
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_assets.dart';
import '../core/motion.dart';
import 'connection_state.dart';
import 'engine.dart';
import 'platform_engine_adapter.dart';
import 'transport_modes.dart';

/// The two selectable home-screen looks (owner: identical logic, different
/// layout — report §11.2).
enum HomeLook { one, two }

class ConnectionStore extends ChangeNotifier implements EngineConfigSource {
  ConnectionStore({EngineAdapter? engine})
    : _engine = engine ?? _defaultEngine() {
    // The platform adapter reads the user's live configuration through this
    // read-only view (M2 seam — see [EngineConfigSource]).
    _engine.bind(this);
    _subscription = _engine.events.listen(_onEvent);
  }

  /// Engine selection order (M2):
  ///  1. PREVIEW_MODE (debug CI builds only) → the honest simulator;
  ///  2. Android → the REAL platform adapter (embedded Aether via FFI +
  ///     zeptun via the VpnService JNI bridge);
  ///  3. everything else (desktop, tests, web) → fails honestly with
  ///     `engineNotWired` instead of ever pretending to be connected.
  static EngineAdapter _defaultEngine() {
    if (PreviewEngineAdapter.allowed) return PreviewEngineAdapter();
    if (!kIsWeb && Platform.isAndroid) return PlatformEngineAdapter();
    return EngineNotWiredAdapter();
  }

  final EngineAdapter _engine;
  late final StreamSubscription<EngineEvent> _subscription;

  final VpnStateMachine _machine = VpnStateMachine();

  /// Single-flight guard (prompt §8: only one transition in flight).
  bool _operationInFlight = false;

  /// v4.19 (#3) — re-entrancy guard of the CANCELLING disconnect: a tap on
  /// the connect button while the engine walk is in flight must reach the
  /// engine even though [_operationInFlight] is held by that walk.
  bool _cancelling = false;

  /// v4.19 (#3) — a cancel was executed and no new connect has started
  /// since: progress emissions from the aborted walk (already in flight
  /// when the cancel landed) are dropped, even after the machine reached
  /// `disconnected` — a cancelled session must never end in a fake
  /// `failed(illegalTransition)`. Cleared by the next user connect.
  bool _cancelledWalk = false;

  /// The states a tap-to-cancel may interrupt (the engine walk in flight).
  static const Set<VpnState> _cancelableStates = {
    VpnState.starting,
    VpnState.waitingForPermissions,
    VpnState.connecting,
  };

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
  /// truth; this is the selector state the core consumes (M2).
  @override
  String? selectedCountryCode;

  /// v4.20 — the wheel policy follows the EFFECTIVE mode (the overlay when
  /// one is selected, else the leg tile): the psiphon family filters the
  /// flags to its egress regions, everything else shows the full manifest.
  bool get wheelSelectable =>
      LocationWheelPolicy.selectable(effectiveProtocol);

  /// null = the whole flag manifest (design/flags_png).
  List<String>? get wheelAllowedCodes =>
      LocationWheelPolicy.allowedCodes(effectiveProtocol);

  /// Wheel selection commit (flag snap / tap). Ignored while an operation
  /// is in flight so the selector can never fight a running transition.
  void selectCountry(String code) {
    if (_operationInFlight) return;
    if (selectedCountryCode == code) return;
    selectedCountryCode = code;
    notifyListeners();
  }

  /// v4.19 — the app's DEFAULT WARP-leg protocol is WireGuard (owner
  /// device-test decree #4: «حالا که هنوز بخش تنظیمات رو طراحی نکردیم حالت
  /// دیفالت تور اور وارپ رو بزار روی پروتکل وایرگارد»). The sheet's AUTO
  /// tile still selects the core's own default (MASQUE) explicitly — only
  /// the cold default changed.
  ///
  /// v4.20 — this is now the WARP-LEG knob ONLY (owner: «اول وایرگارد وصل
  /// شه و بعد سایفون»): a chain selection ([selectedChain]) rides on top
  /// of this leg instead of replacing it. The engine combines both
  /// (`--protocol wg --psiphon` = WireGuard WARP first, Psiphon over it).
  @override
  ProtocolId selectedProtocol = ProtocolId.wireguard;

  /// v4.20 — the overlay family member (torChain…psiphonOnly) committed on
  /// a protocol-sheet family card, or null = plain connection. Independent
  /// of [selectedProtocol]: picking «سایفون روی وارپ» keeps the WireGuard
  /// leg selected underneath it.
  @override
  ProtocolId? selectedChain;

  /// The mode the ENGINE runs and the UI shows: the overlay when one is
  /// selected, else the leg tile.
  @override
  ProtocolId get effectiveProtocol => selectedChain ?? selectedProtocol;

  /// v4.16 — protocol (leg) selection with notify (the sheet binds here;
  /// tapping a tile commits the leg and auto-pops back to the home — the
  /// chain selection is deliberately untouched).
  void selectProtocol(ProtocolId id) {
    if (selectedProtocol == id) return;
    selectedProtocol = id;
    notifyListeners();
  }

  /// v4.20 — overlay (chain) selection with notify. Tapping the ACTIVE
  /// sub-tile again clears the overlay (back to the plain leg) — that is
  /// the sheet's only "off" affordance until the deferred page redesign.
  void selectChain(ProtocolId? id) {
    if (selectedChain == id) return;
    selectedChain = id;
    notifyListeners();
  }

  /// v4.16 — «حالت اتصال» (تونل/پروکسی). Default proxy per the sheet frame;
  /// the engine consumes it (M2 — see [ConnectionMode]).
  @override
  ConnectionMode connectionMode = ConnectionMode.proxy;

  void setConnectionMode(ConnectionMode mode) {
    if (connectionMode == mode) return;
    connectionMode = mode;
    notifyListeners();
  }

  /// v4.16 — «سرعت اسکن» 1..5 (the sheet frame ships the widest pill = 5
  /// selected). The engine consumes it (M2 — scan profile).
  @override
  int scanSpeed = 5;

  void setScanSpeed(int level) {
    final clamped = level.clamp(1, 5);
    if (scanSpeed == clamped) return;
    scanSpeed = clamped;
    notifyListeners();
  }

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
    // A fresh user intent supersedes any cancelled-walk residue.
    _cancelledWalk = false;
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

  /// Disconnect — or, while the engine walk (starting/…/connecting) is in
  /// flight, CANCEL the pending connection (owner device test #3: «حین
  /// اتصال کاربر باید بتونه اتصال رو کنسل کنه»). The state machine allows
  /// every walk state → disconnecting, and the platform adapter aborts its
  /// walk at the next checkpoint; the cancel owns the terminal state.
  Future<void> disconnect() async {
    if (_cancelling) return;
    final current = state;
    if (current == VpnState.disconnected || current == VpnState.disconnecting) {
      return;
    }
    final isCancel = _cancelableStates.contains(current);
    // A cancel interrupts the in-flight walk ON PURPOSE; a plain disconnect
    // (from connected/failed/reconnecting) still honors the single-flight
    // guard so it can never race a connect that is not running.
    if (!isCancel && _operationInFlight) return;
    _cancelling = isCancel;
    if (isCancel) _cancelledWalk = true;
    _operationInFlight = true;
    notifyListeners();
    try {
      _apply(VpnState.disconnecting);
      await _engine.disconnect();
    } catch (e) {
      _fail(errorCode: 'engineException', message: e.toString());
    } finally {
      _operationInFlight = false;
      _cancelling = false;
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
        // v4.19 (#3) — a cancelled walk's stale emission must never fight
        // the cancel: between the adapter's _disconnecting checkpoint and
        // its emission there is an unavoidable event-loop window, and the
        // emission may even land AFTER the machine already reached
        // `disconnected`. While disconnecting — or after a cancel until a
        // fresh connect starts — progress emissions from the aborted walk
        // are dropped; the cancel owns the terminal state (otherwise the
        // late `connected` would land as an illegalTransition failure).
        final cancelResidue = _cancelledWalk &&
            (_machine.current == VpnState.disconnecting ||
                _machine.current == VpnState.disconnected);
        if ((cancelResidue || _machine.current == VpnState.disconnecting) &&
            (eventState == VpnState.connected ||
                eventState == VpnState.connecting ||
                eventState == VpnState.starting ||
                eventState == VpnState.waitingForPermissions)) {
          break;
        }
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
