/// Connection state machine — EXACTLY the states of prompt §8:
/// `Disconnected → Starting → WaitingForPermissions (Android/iOS only) →
/// Connecting → Connected → Reconnecting → Disconnecting → Failed`
/// plus the rules: any state may reach `Failed`; retry from `Failed` or
/// `Reconnecting` goes to `Connecting`; only ONE transition in flight;
/// `Connected` is only ever entered after the end-to-end probe succeeded
/// (that gate lives in the service layer — the machine just refuses
/// impossible jumps).
library;

/// The 8 connection states (prompt §8).
enum VpnState {
  disconnected,
  starting,
  waitingForPermissions,
  connecting,
  connected,
  reconnecting,
  disconnecting,
  failed,
}

/// Pure, side-effect-free transition table — fully unit-tested.
class VpnStateMachine {
  VpnState _current = VpnState.disconnected;

  VpnState get current => _current;

  VpnState transition(VpnState next) {
    if (!isValidTransition(_current, next)) {
      throw StateError('invalid transition: $_current → $next');
    }
    _current = next;
    return _current;
  }

  /// Any state → failed is always legal (prompt §8).
  static bool isValidTransition(VpnState from, VpnState to) {
    if (to == VpnState.failed) return true;
    return switch (from) {
      VpnState.disconnected => next(to, {
        VpnState.starting,
        VpnState.disconnecting,
      }),
      VpnState.starting => next(to, {
        VpnState.waitingForPermissions,
        VpnState.connecting,
      }),
      VpnState.waitingForPermissions => next(to, {
        VpnState.connecting,
        VpnState.disconnecting,
      }),
      VpnState.connecting => next(to, {
        VpnState.connected,
        VpnState.disconnecting,
      }),
      VpnState.connected => next(to, {
        VpnState.reconnecting,
        VpnState.disconnecting,
      }),
      // Retry from Reconnecting goes back to Connecting (prompt §8).
      VpnState.reconnecting => next(to, {
        VpnState.connecting,
        VpnState.disconnecting,
      }),
      VpnState.disconnecting => next(to, {VpnState.disconnected}),
      // Retry from Failed goes to Connecting (prompt §8).
      VpnState.failed => next(to, {
        VpnState.connecting,
        VpnState.disconnecting,
      }),
    };
  }

  static bool next(VpnState to, Set<VpnState> allowed) => allowed.contains(to);
}
