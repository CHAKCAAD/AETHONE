import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/connection/aether_env.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';

/// v4.21 — the engineClosed fix (owner device-test round 3: «فقط بار اول
/// وصل میشن … دیگه هیچ پروتکلی متصل نمیشه … ارورش هم اینه: engineClosed /
/// the core exited on its own (state: null)»).
///
/// ROOT CAUSE: the in-process Aether core translates every CLI flag into an
/// `AETHER_*` env var via std::env::set_var (cli.rs) and NEVER clears them,
/// so session N+1 inherited session N's mode — notably the core's own
/// reverse-mode leftovers AETHER_UPSTREAM + AETHER_MASQUE_HTTP2 pointing at
/// the dead carrier of the previous session — and died during startup. The
/// fix clears the whole inventory before every coreStart.
void main() {
  group('aetherEnvVars — the pinned core\'s env inventory', () {
    test('no duplicates', () {
      expect(aetherEnvVars.toSet().length, aetherEnvVars.length);
    });

    test('carries the mode-critical variables of the frozen pin', () {
      // The exact variables the owner's failed second connects inherited:
      // the core's own reverse-mode set_var calls (lib.rs L215-216) and the
      // family selects (cli.rs L584-600).
      const critical = [
        'AETHER_UPSTREAM',
        'AETHER_MASQUE_HTTP2',
        'AETHER_PSIPHON',
        'AETHER_TOR',
        'AETHER_PROTOCOL',
        'AETHER_PSIPHON_REGION',
        'AETHER_PSIPHON_BIN',
        'AETHER_PSIPHON_DIR',
        'AETHER_TOR_PT',
        'AETHER_TOR_DIR',
        'AETHER_EXIT_LOC',
        'AETHER_SOCKS',
        'AETHER_CONFIG',
        'AETHER_SCAN',
        'AETHER_LOG_LEVEL',
        'AETHER_GOOL_MODE',
        'AETHER_TOR_BIND',
        'AETHER_PSIPHON_BIND',
      ];
      for (final name in critical) {
        expect(aetherEnvVars, contains(name), reason: 'missing: $name');
      }
    });

    test('every entry is a well-formed AETHER_* name', () {
      for (final name in aetherEnvVars) {
        expect(name.startsWith('AETHER_'), isTrue, reason: name);
        expect(name.contains(' '), isFalse, reason: name);
      }
    });
  });

  group('clearAetherEnvironment — process hygiene (libc round-trip)', () {
    // The test runner has a libc (Linux/macOS) with setenv/unsetenv/getenv,
    // so the FFI round-trip is exercised for real.
    test('planted variables are gone after the cleanup', () {
      const planted = 'AETHER_PSIPHON';
      expect(setAetherEnvVar(planted, 'chain'), isTrue);
      expect(aetherEnvVar(planted), 'chain');

      final removed = clearAetherEnvironment();
      expect(removed, greaterThanOrEqualTo(1));
      expect(aetherEnvVar(planted), isNull);
    });

    test('cleanup is idempotent (second run removes nothing)', () {
      clearAetherEnvironment();
      final second = clearAetherEnvironment();
      expect(aetherEnvVar('AETHER_PSIPHON'), isNull);
      expect(second, greaterThanOrEqualTo(0)); // never throws
    });
  });

  group('describeJobOutcome — the honest exit reason (v4.21)', () {
    test('a FAILED job surfaces the core\'s own error text', () {
      // The exact shape ffi.rs produces for a failed core:
      // {"ok":true,"state":"done","result":{"ok":false,"error":"…"}} — the
      // old code read result.state, found null and printed the anonymous
      // "(state: null)" message, swallowing the real reason.
      final body = <Object?, Object?>{
        'state': 'done',
        'result': <Object?, Object?>{
          'ok': false,
          'error': 'cannot bind 127.0.0.1:1819: address already in use',
        },
      };
      expect(
        PlatformEngineAdapter.describeJobOutcome(body),
        contains('address already in use'),
      );
      expect(PlatformEngineAdapter.describeJobOutcome(body), startsWith('the core failed'));
    });

    test('a normal stop keeps the state wording', () {
      expect(
        PlatformEngineAdapter.describeJobOutcome(const {
          'state': 'done',
          'result': {'state': 'stopped'},
        }),
        contains('stopped'),
      );
      expect(
        PlatformEngineAdapter.describeJobOutcome(const {
          'state': 'done',
          'result': {'state': 'closed'},
        }),
        contains('closed'),
      );
    });

    test('a resultless job falls back to the honest anonymous line', () {
      expect(
        PlatformEngineAdapter.describeJobOutcome(const {'state': 'done'}),
        'the core exited on its own (state: null)',
      );
    });
  });
}
