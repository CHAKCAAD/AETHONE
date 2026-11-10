// GUARDIAN-BOOTSTRAP STAGE 7 — the Flutter-level surface of the mission
// (mission «مرحله هفتم» / Flutter Tests):
//   * the firefox walk's failure classes render HONESTLY at the widget
//     level — the region-unavailable (451) class and the Stage-6
//     lifecycle classes (quota, renewal timeout) carry their own code +
//     diagnostic under the status pill and in the details sheet;
//   * NO FALSE SUCCESS: a failed walk never shows the connected pill
//     (the store's state machine is the only gate, the same rule the
//     walk's end-to-end probe enforces at the engine level);
//   * every classified Firefox failure maps to a NON-EMPTY localized
//     string in ALL FIVE locales — including the two Stage-6 classes
//     that had diagnostics but no localized text before this stage.
//
// What these tests deliberately do NOT do (honest scope, recorded in
// the progress file): granular bootstrap SUB-states (checking / starting
// psiphon / trying combined / authorizing) are not wired to any widget
// by design — the bootstrap is an internal phase of the firefox connect
// walk; the UI contract is the walk's own states + the classified
// failure surface tested here. Wiring sub-state chips would be new UI
// work for the owner to request, not a test-stage change.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/firefox/firefox_errors.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/l10n/app_strings.dart';

/// The same scripted engine seam home_screen_test.dart uses — a fully
/// controlled event source for the store.
class _ScriptedEngine extends EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  void emit(EngineEvent e) => _controller.add(e);

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void bind(EngineConfigSource config) {} // scripted — config never read
}

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
  // Emulate the design reference frame (402x874 logical @ dpr 3) — the
  // same helper home_screen_test.dart uses; the default 800x600 test
  // surface is not the layout the design targets.
  Future<void> useReferenceSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
      'GUARDIAN-BOOTSTRAP STAGE 7 — the 451 region failure renders the '
      'honest failed surface (code + diagnostic under the pill, in the '
      'sheet) and NEVER the connected pill', (tester) async {
    await useReferenceSurface(tester);
    final engine = _ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // A firefox walk that exhausted the bootstrap ladder: the adapter's
    // fail() pair for the 451 class (the exact strings the walk emits).
    const code = 'firefoxTransport:${FirefoxEngineFailure.guardianRegionUnavailable}';
    final message = FirefoxErrors.diagnostic(
      FirefoxErrors.classify(
        FirefoxEngineFailure.guardianRegionUnavailable,
        httpStatus: 451,
      ),
    );
    await store.connect();
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(EngineStateChanged(
      VpnState.failed,
      errorCode: code,
      message: message,
    ));
    await tester.pumpAndSettle();

    // NO FALSE SUCCESS: the failed walk never shows the connected pill.
    expect(store.state, VpnState.failed);
    expect(find.text('متصل'), findsNothing);
    expect(find.text('خطا'), findsOneWidget);

    // The caption names the classified code (never the raw chain, never
    // a host, never a token — the classification is the UI contract).
    expect(find.text('کد خطا: $code'), findsOneWidget);

    // The details sheet carries the code + the static diagnostic.
    await tester.tap(find.text('کد خطا: $code'));
    await tester.pumpAndSettle();
    expect(find.text('جزئیات خطا'), findsOneWidget);
    expect(find.text(code), findsWidgets);
    expect(find.textContaining('not available in this region'), findsOneWidget);
  });

  testWidgets(
      'GUARDIAN-BOOTSTRAP STAGE 7 — the Stage-6 quota class renders its '
      'own code (pick-another-engine), not the region class', (tester) async {
    await useReferenceSurface(tester);
    final engine = _ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.pumpAndSettle();

    // The adapter's own quota pair (platform_engine_adapter: the quota
    // walk fails with the dedicated code so the user can pick another
    // engine — never a silent fallback).
    const code = 'firefoxQuotaExhausted';
    final message = FirefoxErrors.diagnostic(
      FirefoxErrors.classify(FirefoxEngineFailure.quotaExhausted),
    );
    await store.connect();
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 100));
    engine.emit(EngineStateChanged(
      VpnState.failed,
      errorCode: code,
      message: message,
    ));
    await tester.pumpAndSettle();

    expect(store.state, VpnState.failed);
    expect(find.text('متصل'), findsNothing);
    expect(find.text('کد خطا: $code'), findsOneWidget);
    // The sheet carries the quota diagnostic — its own text, never the
    // region one.
    await tester.tap(find.text('کد خطا: $code'));
    await tester.pumpAndSettle();
    expect(find.text('جزئیات خطا'), findsOneWidget);
    expect(find.textContaining('quota is exhausted'), findsOneWidget);
    expect(find.textContaining('not available in this region'), findsNothing);
  });

  test('GUARDIAN-BOOTSTRAP STAGE 7 — every classified firefox failure maps '
      'to its own non-empty localized text in ALL FIVE locales (the two '
      'Stage-6 classes included)', () {
    const locales = ['fa', 'en', 'ru', 'zh', 'tk'];
    // Every class FirefoxErrors.classify can emit for a UI consumer.
    final classes = <String>[
      FirefoxTransportError.dnsError,
      FirefoxTransportError.networkUnavailable,
      FirefoxTransportError.timeout,
      FirefoxTransportError.tlsError,
      FirefoxTransportError.sessionRejected,
      FirefoxTransportError.tokenExchange,
      FirefoxTransportError.invalidTokenResponse,
      FirefoxTransportError.serverRejection,
      FirefoxTransportError.guardianRegionUnavailable,
      FirefoxTransportError.quotaExhausted,
      FirefoxTransportError.renewalTimeout,
    ];
    for (final locale in locales) {
      final strings = AppStrings.forLocale(locale);
      final generic = strings.firefoxLoginFailed;
      for (final code in classes) {
        final text = strings.firefoxErrorText(code);
        expect(text.trim().isNotEmpty, isTrue,
            reason: '$locale: $code must have localized text');
        expect(text == generic, isFalse,
            reason: '$locale: $code must map to its OWN text, not the '
                'generic login-failed fallback');
      }
      // The two Stage-7 l10n keys exist as first-class getters too.
      expect(strings.firefoxErrQuotaExhausted.trim().isNotEmpty, isTrue);
      expect(strings.firefoxErrRenewalTimeout.trim().isNotEmpty, isTrue);
    }
  });
}
