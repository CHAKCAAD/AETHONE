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
enum ConnectionState {
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
class ConnectionStateMachine {
  ConnectionState _current = ConnectionState.disconnected;

  ConnectionState get current => _current;

  ConnectionState transition(ConnectionState next) {
    if (!isValidTransition(_current, next)) {
      throw StateError('invalid transition: $_current → $next');
    }
    _current = next;
    return _current;
  }

  /// Any state → failed is always legal (prompt §8).
  static bool isValidTransition(ConnectionState from, ConnectionState to) {
    if (to == ConnectionState.failed) return true;
    return switch (from) {
      ConnectionState.disconnected =>
        next(to, {ConnectionState.starting, ConnectionState.disconnecting}),
      ConnectionState.starting => next(to, {
          ConnectionState.waitingForPermissions,
          ConnectionState.connecting,
        }),
      ConnectionState.waitingForPermissions => next(to, {
          ConnectionState.connecting,
          ConnectionState.disconnecting,
        }),
      ConnectionState.connecting => next(to, {
          ConnectionState.connected,
          ConnectionState.disconnecting,
        }),
      ConnectionState.connected => next(to, {
          ConnectionState.reconnecting,
          ConnectionState.disconnecting,
        }),
      // Retry from Reconnecting goes back to Connecting (prompt §8).
      ConnectionState.reconnecting => next(to, {
          ConnectionState.connecting,
          ConnectionState.disconnecting,
        }),
      ConnectionState.disconnecting =>
        next(to, {ConnectionState.disconnected}),
      // Retry from Failed goes to Connecting (prompt §8).
      ConnectionState.failed => next(to, {
          ConnectionState.connecting,
          ConnectionState.disconnecting,
        }),
    };
  }

  static bool next(ConnectionState to, Set<ConnectionState> allowed) =>
      allowed.contains(to);
}
