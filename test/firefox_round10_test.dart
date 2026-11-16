// The owner's round 10 tests (2026-11-16) — the reference's network
// posture, completed, carried into 2.1.0 (the DNS removal):
//
//   * the settings-page location refresh is GATED to a 5-minute
//     freshness window (the owner's «تأخیر در باز شدن صفحه تنظیمات»):
//     a fresh list never re-runs the --discover walk, a stale one does;
//   * the Firefox settings page shows the account section's loading
//     affordance while the vault check runs (the owner's «اگه تاخیر
//     قابل حل نیست باید براش لودینگ گزاشته بشه»);
//   * 2.1.0 — the hello-split pick is GONE with the whole DNS feature
//     (the owner's removal decree): the settings page renders no DNS
//     card and no hello-split pill in any mode.
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

  group('round 10 → 2.1.0: the hello-split pick is GONE with DNS', () {
    testWidgets('the settings page renders no DNS card and no hello-split pill',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {
        // Legacy keys a device may still hold — ignored entirely.
        'firefox.dns.hello_split': 'sni',
        'firefox.dns.mode': 'doh',
      });
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      await tester.pumpWidget(_booth(FirefoxSettingsPage(store: store)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pill-firefox-dns-hello-split')),
        findsNothing,
        reason: 'the hello-split pill is gone with the whole DNS card',
      );
      expect(find.byKey(const ValueKey('pill-firefox-dns-mode')),
          findsNothing);
      expect(find.byKey(const ValueKey('action-firefox-dns-test')),
          findsNothing);
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
  });
}
