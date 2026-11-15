// The owner's round 8 tests (2026-11-16) — the arman-vpn-client pattern:
//
//   * the loginNeedsCode wire event parses (the password mode's
//     emailed-code ask: email + method + the previous submission's
//     failure), and the result factory carries them;
//   * the granular FxA application codes parse verbatim (the arman
//     SignInError model: noAccount, wrongPassword, …);
//   * the Persian/Arabic-Indic digit normalizer (arman's _CodeDigits,
//     ported) maps every keyboard's digits to ASCII;
//   * the login screen opens on the DIRECT FORM (the reference app's
//     default sign-in) with the browser tab one tap away;
//   * the REAL engine's password mode (host binary, when present):
//     the config rejection keeps its own code, and the clean cancel
//     never leaks the password into an event.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/firefox/firefox_login.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:aethone/features/settings/firefox_login_screen.dart';

Widget _booth(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

void main() {
  group('the password mode wire protocol (1.8.0)', () {
    test('loginNeedsCode parses (email + method + lastError)', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode('{"event":"loginNeedsCode","email":"a@b.example",'
                '"verificationMethod":"email-2fa","attempt":2,'
                '"lastError":"wrongCode"}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.name, FirefoxEngineEvents.loginNeedsCode);
      expect(ev.needsCodeEmail, 'a@b.example');
      expect(ev.verificationMethod, 'email-2fa');
      expect(ev.needsCodeLastError, 'wrongCode');
      expect(ev.attempt, 2);
      expect(ev.carriesSecrets, isFalse);
      expect(ev.logLine, contains('a@b.example'));
      expect(ev.logLine, contains('wrongCode'));
    });

    test('loginNeedsCode tolerates missing/typed-wrong fields', () {
      final ev = FirefoxEngineEvent.fromJson(
        (jsonDecode('{"event":"loginNeedsCode","email":7,'
                '"verificationMethod":null}')
                as Map)
            .cast<String, dynamic>(),
      );
      expect(ev.needsCodeEmail, '');
      expect(ev.verificationMethod, '');
      expect(ev.needsCodeLastError, '');
    });

    test('the granular FxA codes parse verbatim', () {
      for (final code in [
        FirefoxEngineFailure.noAccount,
        FirefoxEngineFailure.wrongPassword,
        FirefoxEngineFailure.tooManyAttempts,
        FirefoxEngineFailure.requestBlocked,
        FirefoxEngineFailure.secondaryEmail,
        FirefoxEngineFailure.invalidEmail,
        FirefoxEngineFailure.unverifiedAccount,
        FirefoxEngineFailure.emailCaseInvalid,
        FirefoxEngineFailure.codeExpired,
        FirefoxEngineFailure.codeAttemptsExhausted,
      ]) {
        final ev = FirefoxEngineEvent.fromJson(
          (jsonDecode('{"event":"failed","code":1,'
                  '"failCode":"$code","message":"x"}')
                  as Map)
              .cast<String, dynamic>(),
        );
        expect(ev.failCode, code);
      }
    });

    test('the needsCode result factory carries the ask', () {
      final result = FirefoxLoginResult.needsCode('a@b.example', 'wrongCode');
      expect(result.state, FirefoxLoginState.needsCode);
      expect(result.email, 'a@b.example');
      expect(result.lastError, 'wrongCode');
      expect(result.isCompleted, isFalse);
      expect(result.auth, isNull);
    });
  });

  group('the code digit normalizer (arman _CodeDigits, ported)', () {
    const formatter = FirefoxLoginCodeDigits();

    String format(String text) => formatter
        .formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: text),
        )
        .text;

    test('ASCII digits pass through', () {
      expect(format('123456'), '123456');
    });

    test('Persian digits become ASCII', () {
      expect(format('۱۲۳۴۵۶'), '123456');
    });

    test('Arabic-Indic digits become ASCII', () {
      expect(format('١٢٣٤٥٦'), '123456');
    });

    test('spaces and dashes are dropped', () {
      expect(format('123 456'), '123456');
      expect(format('123-456'), '123456');
    });

    test('a mixed keyboard normalizes', () {
      expect(format('۱۲3٤5۶'), '123456');
    });
  });

  group('the login screen (the arman default: the DIRECT form)', () {
    testWidgets('opens on the form, not the browser', (tester) async {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      await tester.pumpWidget(_booth(FirefoxLoginScreen(store: store)));
      await tester.pump();
      // The form's fields are there (LTR email + password) and the
      // browser tab is one tap away — the WebView never booted.
      expect(find.byKey(const ValueKey('field-firefox-login-email')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('field-firefox-login-password')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('field-firefox-login-code')),
          findsNothing);
    });

    testWidgets('the code field appears on the needsCode ask',
        (tester) async {
      final engine = _NeedsCodeEngine();
      final store = ConnectionStore(engine: engine);
      await tester.pumpWidget(_booth(FirefoxLoginScreen(store: store)));
      await tester.pump();

      await tester.enterText(
          find.byKey(const ValueKey('field-firefox-login-email')),
          'a@b.example');
      await tester.enterText(
          find.byKey(const ValueKey('field-firefox-login-password')),
          'pw-test-1');
      await tester.tap(find.text('ورود'));
      await tester.pumpAndSettle();

      // The scripted engine asked for the code — the field appears.
      expect(find.byKey(const ValueKey('field-firefox-login-code')),
          findsOneWidget);
    });
  });

  group('the REAL engine password mode (host binary)', () {
    // The same honest gate the webchannel lifecycle tests use: the
    // suite's own skip when the host binary is absent.
    String? engineBin() {
      for (final path in [
        Platform.environment['FXV_ENGINE_BIN'],
        '${Directory.current.path}/phase1/build/host/libfirefoxvpn',
      ]) {
        if (path != null && File(path).existsSync()) return path;
      }
      return null;
    }

    test('the config rejection keeps its own code (invalidEmail)',
        () async {
      final bin = engineBin();
      if (bin == null) {
        return; // honest skip (CI builds the binary first)
      }
      final logs = <String>[];
      final client = FirefoxLoginClient(binaryPath: bin, onLog: logs.add);
      final result = await client.runPassword(
        email: 'no-at.example',
        password: 'pw',
        timeout: const Duration(seconds: 10),
      );
      expect(result.state, FirefoxLoginState.failed);
      expect(result.failCode, 'invalidEmail');
      await client.cancel();
    });

    test('the clean cancel never leaks the password', () async {
      final bin = engineBin();
      if (bin == null) {
        return; // honest skip
      }
      final logs = <String>[];
      final client = FirefoxLoginClient(binaryPath: bin, onLog: logs.add);
      final future = client.runPassword(
        email: 'cancel@example.com',
        password: 'leak-check-pw',
        timeout: const Duration(seconds: 45),
      );
      // Give the child a beat to consume the config line, then cancel.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await client.cancel();
      final result = await future;
      expect(result.state, anyOf(
        FirefoxLoginState.cancelled,
        FirefoxLoginState.failed, // a networkless runner: the call fails
      ));
      for (final line in logs) {
        expect(line, isNot(contains('leak-check-pw')));
      }
    });
  });
}

/// The scripted engine: the first password login answers the code ask.
class _NeedsCodeEngine extends EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<FirefoxLoginResult> firefoxPasswordLogin(
    String email,
    String password, {
    void Function(String line)? onLog,
  }) async =>
      FirefoxLoginResult.needsCode(email, '');

  @override
  Future<FirefoxLoginResult> firefoxPasswordLoginCode(
    String code, {
    void Function(String line)? onLog,
  }) async =>
      FirefoxLoginResult.failed('wrongCode', 'x');
}
