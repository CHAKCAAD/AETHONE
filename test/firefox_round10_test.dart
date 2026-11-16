// The owner's round 10 tests (2026-11-16) — the reference's network
// posture, completed:
//
//   * the hello-split pick persists and rides the dns config line
//     (the reference's network.hello_split; the default is sni);
//   * the settings-page location refresh is GATED to a 5-minute
//     freshness window (the owner's «تأخیر در باز شدن صفحه تنظیمات»):
//     a fresh list never re-runs the --discover walk, a stale one does;
//   * the Firefox settings page shows the account section's loading
//     affordance while the vault check runs (the owner's «اگه تاخیر
//     قابل حل نیست باید براش لودینگ گزاشته بشه»);
//   * the DNS card exposes the hello-split pill in BOTH dns modes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/features/settings/firefox_page.dart';

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

/// An adapter that COUNTS the location refreshes (the gate's proof).
class _CountingLocationsAdapter extends EngineNotWiredAdapter {
  int locationRefreshes = 0;

  @override
  Future<void> refreshFirefoxLocations() async {
    locationRefreshes++;
  }
}

/// An adapter whose session check NEVER completes — the page's loading
/// affordance must stay visible (the owner's «loading» demand).
class _HangingAccountEngine extends EngineNotWiredAdapter {
  @override
  Future<bool> firefoxHasSession() => Completer<bool>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('round 10: the hello-split pick', () {
    test('the default is sni and the unknown value degrades to it', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      expect(store.firefoxDnsHelloSplit, 'sni');
      expect(store.firefoxDnsConfig['helloSplit'], 'sni');
      store.setFirefoxDnsHelloSplit('first-byte');
      expect(store.firefoxDnsHelloSplit, 'first-byte');
      expect(store.firefoxDnsConfig['helloSplit'], 'first-byte');
      store.setFirefoxDnsHelloSplit('nope');
      expect(store.firefoxDnsHelloSplit, 'sni');
    });

    test('the pick survives a settings reload (persisted)', () async {
      // The store persists through SharedPreferences; await the ctor's
      // own restore first (the real app does), then pin the pick, let
      // the write land, reload, and expect it back.
      SharedPreferences.setMockInitialValues(const {});
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      await store.loadFirefoxDnsSettings();
      store.setFirefoxDnsHelloSplit('record');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final reloaded = ConnectionStore(engine: EngineNotWiredAdapter());
      await reloaded.loadFirefoxDnsSettings();
      expect(reloaded.firefoxDnsHelloSplit, 'record');
    });

    test('the pick rides the config line in SYSTEM mode too', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.setFirefoxDnsMode('system');
      expect(store.firefoxDnsConfig['mode'], 'system');
      expect(store.firefoxDnsConfig['helloSplit'], 'sni');
    });
  });

  group('round 10: the location refresh gate', () {
    test('a FRESH list never re-runs the discover walk', () {
      final adapter = _CountingLocationsAdapter();
      final store = ConnectionStore(engine: adapter);
      store.applyFirefoxLocations(
          ['de', 'fr'], true, DateTime.now().subtract(const Duration(minutes: 1)));
      store.refreshFirefoxLocations();
      expect(adapter.locationRefreshes, 0,
          reason: 'a list fetched a minute ago is fresh enough');
    });

    test('a STALE list re-runs the discover walk', () {
      final adapter = _CountingLocationsAdapter();
      final store = ConnectionStore(engine: adapter);
      store.applyFirefoxLocations(['de', 'fr'], false,
          DateTime.now().subtract(const Duration(minutes: 30)));
      store.refreshFirefoxLocations();
      expect(adapter.locationRefreshes, 1,
          reason: 'a half-hour-old list is stale');
    });

    test('no list at all re-runs the discover walk', () {
      final adapter = _CountingLocationsAdapter();
      final store = ConnectionStore(engine: adapter);
      store.refreshFirefoxLocations();
      expect(adapter.locationRefreshes, 1);
    });
  });

  group('round 10: the settings page affordances', () {
    testWidgets('the account section carries its loading while the check runs',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // The vault check stays in flight (the account stays unknown) —
      // the section shows its loading line, and the sign-in button only
      // lands when the check does (the owner's round-10 demand: a
      // backend operation shows its loading the moment it starts).
      final store = ConnectionStore(engine: _HangingAccountEngine());
      await tester.pumpWidget(_booth(FirefoxSettingsPage(store: store)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining('در حال بررسی حساب'),
        findsWidgets,
        reason: 'the account check must show its loading while it runs',
      );
      expect(
        find.byKey(const ValueKey('action-firefox-sign-in')),
        findsNothing,
        reason: 'the button must not render before the check lands',
      );
    });

    testWidgets('the sign-in button lands once the check completes',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      await tester.pumpWidget(_booth(FirefoxSettingsPage(store: store)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('action-firefox-sign-in')),
        findsOneWidget,
      );
      expect(
        find.textContaining('در حال بررسی حساب'),
        findsNothing,
        reason: 'the loading is gone once the state is known',
      );
    });

    testWidgets('the DNS card exposes the hello-split pill in system mode',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.setFirefoxDnsMode('system');
      await tester.pumpWidget(_booth(FirefoxSettingsPage(store: store)));
      await tester.pumpAndSettle();
      expect(
        find.text('داخل نام سرور'),
        findsOneWidget,
        reason: 'the hello split applies to the direct TLS posture in '
            'BOTH dns modes — it must render in system mode too',
      );
      // All four choices render.
      expect(find.text('بایت اول'), findsOneWidget);
      expect(find.text('دو رکورد'), findsOneWidget);
      expect(find.text('خاموش'), findsOneWidget);
    });
  });
}
