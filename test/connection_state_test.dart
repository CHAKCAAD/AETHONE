import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/connection/connection_state.dart';

/// The exact state set of prompt §8 — 8 states, no more, no less.
void main() {
  group('state set', () {
    test('has exactly the 8 prompt-§8 states', () {
      expect(ConnectionState.values.length, 8);
      expect(ConnectionState.values, containsAll(<ConnectionState>[
        ConnectionState.disconnected,
        ConnectionState.starting,
        ConnectionState.waitingForPermissions,
        ConnectionState.connecting,
        ConnectionState.connected,
        ConnectionState.reconnecting,
        ConnectionState.disconnecting,
        ConnectionState.failed,
      ]));
    });
  });

  group('legal happy paths', () {
    test('cold connect walk (no permissions)', () {
      final m = ConnectionStateMachine();
      expect(m.transition(ConnectionState.starting), ConnectionState.starting);
      expect(m.transition(ConnectionState.connecting), ConnectionState.connecting);
      expect(m.transition(ConnectionState.connected), ConnectionState.connected);
    });

    test('cold connect walk with permissions (Android/iOS)', () {
      final m = ConnectionStateMachine();
      m.transition(ConnectionState.starting);
      expect(
        m.transition(ConnectionState.waitingForPermissions),
        ConnectionState.waitingForPermissions,
      );
      m.transition(ConnectionState.connecting);
      m.transition(ConnectionState.connected);
    });

    test('health failure: connected → reconnecting → connecting → connected',
        () {
      final m = ConnectionStateMachine();
      m
        ..transition(ConnectionState.starting)
        ..transition(ConnectionState.connecting)
        ..transition(ConnectionState.connected)
        ..transition(ConnectionState.reconnecting);
      // Retry from Reconnecting goes to Connecting (prompt §8).
      m.transition(ConnectionState.connecting);
      m.transition(ConnectionState.connected);
    });

    test('user disconnect from any active state', () {
      final m = ConnectionStateMachine();
      m
        ..transition(ConnectionState.starting)
        ..transition(ConnectionState.connecting)
        ..transition(ConnectionState.connected)
        ..transition(ConnectionState.disconnecting);
      expect(
        m.transition(ConnectionState.disconnected),
        ConnectionState.disconnected,
      );
    });

    test('retry from failed goes to connecting (prompt §8)', () {
      final m = ConnectionStateMachine();
      m.transition(ConnectionState.starting);
      m.transition(ConnectionState.failed);
      m.transition(ConnectionState.connecting);
    });

    test('any state can reach failed (prompt §8)', () {
      for (final from in ConnectionState.values) {
        for (var i = 0; i < ConnectionState.values.length; i++) {
          // Build a machine that lands exactly on `from` via its own path.
          final m = ConnectionStateMachine();
          final reached = _forceState(m, from);
          expect(reached, isTrue, reason: 'setup for $from failed');
          expect(
            ConnectionStateMachine.isValidTransition(
              m.current,
              ConnectionState.failed,
            ),
            isTrue,
            reason: '$from → failed must be legal',
          );
        }
      }
    });
  });

  group('illegal jumps are refused', () {
    test('disconnected cannot jump to connected', () {
      expect(
        ConnectionStateMachine.isValidTransition(
          ConnectionState.disconnected,
          ConnectionState.connected,
        ),
        isFalse,
      );
    });

    test('disconnected cannot jump to connecting (must pass starting)', () {
      expect(
        ConnectionStateMachine.isValidTransition(
          ConnectionState.disconnected,
          ConnectionState.connecting,
        ),
        isFalse,
      );
    });

    test('connected cannot go back to starting', () {
      expect(
        ConnectionStateMachine.isValidTransition(
          ConnectionState.connected,
          ConnectionState.starting,
        ),
        isFalse,
      );
    });

    test('machine throws StateError on illegal transition', () {
      final m = ConnectionStateMachine();
      expect(() => m.transition(ConnectionState.connected),
          throwsA(isA<StateError>()));
    });

    test('waitingForPermissions is only reachable from starting', () {
      for (final from in ConnectionState.values) {
        final legal = ConnectionStateMachine.isValidTransition(
          from,
          ConnectionState.waitingForPermissions,
        );
        expect(legal, from == ConnectionState.starting,
            reason: '$from → waitingForPermissions');
      }
    });
  });
}

/// Drives the machine onto [target] through a legal path.
bool _forceState(ConnectionStateMachine m, ConnectionState target) {
  switch (target) {
    case ConnectionState.disconnected:
      return true; // initial
    case ConnectionState.starting:
      m.transition(ConnectionState.starting);
      return true;
    case ConnectionState.waitingForPermissions:
      m
        ..transition(ConnectionState.starting)
        ..transition(ConnectionState.waitingForPermissions);
      return true;
    case ConnectionState.connecting:
      m
        ..transition(ConnectionState.starting)
        ..transition(ConnectionState.connecting);
      return true;
    case ConnectionState.connected:
      m
        ..transition(ConnectionState.starting)
        ..transition(ConnectionState.connecting)
        ..transition(ConnectionState.connected);
      return true;
    case ConnectionState.reconnecting:
      _forceState(m, ConnectionState.connected);
      m.transition(ConnectionState.reconnecting);
      return true;
    case ConnectionState.disconnecting:
      _forceState(m, ConnectionState.connected);
      m.transition(ConnectionState.disconnecting);
      return true;
    case ConnectionState.failed:
      m.transition(ConnectionState.failed);
      return true;
  }
}
