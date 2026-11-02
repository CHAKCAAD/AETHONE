import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/connection/connection_state.dart';

/// The exact state set of prompt §8 — 8 states, no more, no less.
void main() {
  group('state set', () {
    test('has exactly the 8 prompt-§8 states', () {
      expect(VpnState.values.length, 8);
      expect(VpnState.values, containsAll(<VpnState>[
        VpnState.disconnected,
        VpnState.starting,
        VpnState.waitingForPermissions,
        VpnState.connecting,
        VpnState.connected,
        VpnState.reconnecting,
        VpnState.disconnecting,
        VpnState.failed,
      ]));
    });
  });

  group('legal happy paths', () {
    test('cold connect walk (no permissions)', () {
      final m = VpnStateMachine();
      expect(m.transition(VpnState.starting), VpnState.starting);
      expect(m.transition(VpnState.connecting), VpnState.connecting);
      expect(m.transition(VpnState.connected), VpnState.connected);
    });

    test('cold connect walk with permissions (Android/iOS)', () {
      final m = VpnStateMachine();
      m.transition(VpnState.starting);
      expect(
        m.transition(VpnState.waitingForPermissions),
        VpnState.waitingForPermissions,
      );
      m.transition(VpnState.connecting);
      m.transition(VpnState.connected);
    });

    test('health failure: connected → reconnecting → connecting → connected',
        () {
      final m = VpnStateMachine();
      m
        ..transition(VpnState.starting)
        ..transition(VpnState.connecting)
        ..transition(VpnState.connected)
        ..transition(VpnState.reconnecting);
      // Retry from Reconnecting goes to Connecting (prompt §8).
      m.transition(VpnState.connecting);
      m.transition(VpnState.connected);
    });

    test('user disconnect from any active state', () {
      final m = VpnStateMachine();
      m
        ..transition(VpnState.starting)
        ..transition(VpnState.connecting)
        ..transition(VpnState.connected)
        ..transition(VpnState.disconnecting);
      expect(
        m.transition(VpnState.disconnected),
        VpnState.disconnected,
      );
    });

    test('retry from failed goes to connecting (prompt §8)', () {
      final m = VpnStateMachine();
      m.transition(VpnState.starting);
      m.transition(VpnState.failed);
      m.transition(VpnState.connecting);
    });

    test('any state can reach failed (prompt §8)', () {
      for (final from in VpnState.values) {
        for (var i = 0; i < VpnState.values.length; i++) {
          // Build a machine that lands exactly on `from` via its own path.
          final m = VpnStateMachine();
          final reached = _forceState(m, from);
          expect(reached, isTrue, reason: 'setup for $from failed');
          expect(
            VpnStateMachine.isValidTransition(
              m.current,
              VpnState.failed,
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
        VpnStateMachine.isValidTransition(
          VpnState.disconnected,
          VpnState.connected,
        ),
        isFalse,
      );
    });

    test('disconnected cannot jump to connecting (must pass starting)', () {
      expect(
        VpnStateMachine.isValidTransition(
          VpnState.disconnected,
          VpnState.connecting,
        ),
        isFalse,
      );
    });

    test('connected cannot go back to starting', () {
      expect(
        VpnStateMachine.isValidTransition(
          VpnState.connected,
          VpnState.starting,
        ),
        isFalse,
      );
    });

    test('machine throws StateError on illegal transition', () {
      final m = VpnStateMachine();
      expect(() => m.transition(VpnState.connected),
          throwsA(isA<StateError>()));
    });

    test('waitingForPermissions is only reachable from starting', () {
      for (final from in VpnState.values) {
        final legal = VpnStateMachine.isValidTransition(
          from,
          VpnState.waitingForPermissions,
        );
        expect(legal, from == VpnState.starting,
            reason: '$from → waitingForPermissions');
      }
    });
  });
}

/// Drives the machine onto [target] through a legal path.
bool _forceState(VpnStateMachine m, VpnState target) {
  switch (target) {
    case VpnState.disconnected:
      return true; // initial
    case VpnState.starting:
      m.transition(VpnState.starting);
      return true;
    case VpnState.waitingForPermissions:
      m
        ..transition(VpnState.starting)
        ..transition(VpnState.waitingForPermissions);
      return true;
    case VpnState.connecting:
      m
        ..transition(VpnState.starting)
        ..transition(VpnState.connecting);
      return true;
    case VpnState.connected:
      m
        ..transition(VpnState.starting)
        ..transition(VpnState.connecting)
        ..transition(VpnState.connected);
      return true;
    case VpnState.reconnecting:
      _forceState(m, VpnState.connected);
      m.transition(VpnState.reconnecting);
      return true;
    case VpnState.disconnecting:
      _forceState(m, VpnState.connected);
      m.transition(VpnState.disconnecting);
      return true;
    case VpnState.failed:
      m.transition(VpnState.failed);
      return true;
  }
}
