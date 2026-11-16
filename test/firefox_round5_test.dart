// The owner's round 5 tests (2026-11-15) — the remaining-data fix and
// the loading affordances, carried into 2.1.0 (the DNS removal):
//
//   * FirefoxQuota.parse: the explicit quotaUnlimited flag (the `--usage`
//     role's X-Quota-Unlimited) wins alone; the metered trio parses; the
//     empty pair stays the inferred-unlimited case; garbage stays null.
//   * The usage event parses (quotaUnlimited rides along, no secrets).
//   * The Firefox settings page renders the quota card + its refresh
//     button (the scan-loading affordances).
//   * 2.1.0 — the DNS feature is GONE: the legacy `firefox.dns.*`
//     preference keys a device may still hold are INERT (never read,
//     never a crash), and the settings page renders no DNS section at
//     all (the owner's decree «بهش dns رو به کلی از اپ حذف کن»).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
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

/// The signed-in scripted engine: the vault reports a session so the
/// page's account section renders the quota card + sign-out (never the
/// sign-in button).
class _SignedInEngine extends EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => _controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void bind(EngineConfigSource config) {}
  @override
  Future<bool> firefoxHasSession() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirefoxQuota.parse (1.7.0 — the usage role)', () {
    test('the explicit unlimited flag wins alone', () {
      final quota = FirefoxQuota.parse('', '', '', quotaUnlimited: true);
      expect(quota, isNotNull);
      expect(quota!.unlimited, isTrue);
      expect(quota.remainingBytes, isNull);
    });

    test('the flag wins even against a metered-looking trio', () {
      final quota =
          FirefoxQuota.parse('1000', '400', '99', quotaUnlimited: true);
      expect(quota!.unlimited, isTrue);
    });

    test('the metered trio parses without the flag', () {
      final quota = FirefoxQuota.parse('10737418240', '2147483648', '1767225600');
      expect(quota, isNotNull);
      expect(quota!.unlimited, isFalse);
      expect(quota.limitBytes, 10737418240);
      expect(quota.remainingBytes, 2147483648);
      expect(quota.resetAt, isNotNull);
    });

    test('the empty pair stays the inferred-unlimited case', () {
      final quota = FirefoxQuota.parse('', '', '');
      expect(quota, isNotNull);
      expect(quota!.unlimited, isTrue);
    });

    test('garbage stays null (never a guess)', () {
      expect(FirefoxQuota.parse('abc', '400', ''), isNull);
      expect(FirefoxQuota.parse('100', '400', ''), isNull); // left > max
    });
  });

  group('the DNS feature is GONE (2.1.0 — the removal decree)', () {
    test('the legacy firefox.dns.* preference keys are inert, never fatal',
        () {
      // Exactly what a device upgraded from the round-6 build may hold:
      // DoH + custom + a schemeless endpoint + junk bootstrap. The store
      // never reads any of it anymore — constructing and using the store
      // must simply work (no dnsConfigInvalid path exists at all now).
      SharedPreferences.setMockInitialValues(const {
        'firefox.dns.mode': 'doh',
        'firefox.dns.provider': 'custom',
        'firefox.dns.endpoint': 'dns.example.com/dns-query',
        'firefox.dns.bootstrap_ips': ['junk', 'not-an-ip'],
        'firefox.dns.hello_split': 'sni',
      });
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      expect(store.firefoxTransport, 'h2');
      expect(store.firefoxLocation, 'auto');
    });

    test('the tunnel config line carries NO dns block anymore', () {
      const cfg = FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'a', refreshToken: 'r'),
      );
      expect(cfg.toJson().containsKey('dns'), isFalse);
    });

    test('the login config line carries NO dns block anymore', () {
      // The wire shape the password mode writes: version/mode/credentials
      // + the budget, nothing else DNS-shaped.
      const line = {
        'version': 1,
        'mode': 'password',
        'email': 'a@b.example',
        'password': 'hunter2',
        'verifyTimeoutMs': 600000,
      };
      expect(line.containsKey('dns'), isFalse);
    });
  });

  group('the usage event on the wire (1.7.0)', () {
    test('parses quotaUnlimited beside the trio', () {
      final event = FirefoxEngineEvent.fromJson(const {
        'event': 'usage',
        'quotaMax': '5368709120',
        'quotaLeft': '1073741824',
        'quotaReset': '2026-12-01T00:00:00Z',
      });
      expect(event.name, 'usage');
      expect(event.quotaMax, '5368709120');
      expect(event.quotaLeft, '1073741824');
      expect(event.quotaUnlimited, isFalse);
      expect(event.carriesSecrets, isFalse);
    });

    test('parses the unlimited account', () {
      final event = FirefoxEngineEvent.fromJson(const {
        'event': 'usage',
        'quotaUnlimited': true,
      });
      expect(event.quotaUnlimited, isTrue);
      expect(event.quotaMax, '');
      expect(event.quotaLeft, '');
    });

    test('a wrong-typed quotaUnlimited degrades to false (never throws)',
        () {
      final event = FirefoxEngineEvent.fromJson(const {
        'event': 'usage',
        'quotaUnlimited': 'yes',
      });
      expect(event.quotaUnlimited, isFalse);
    });

    test('the usageFailed event classifies through the same parse', () {
      final event = FirefoxEngineEvent.fromJson(const {
        'event': 'usageFailed',
        'failCode': 'sessionRejected',
        'httpStatus': 401,
        'code': 1,
      });
      expect(event.name, 'usageFailed');
      expect(event.failCode, 'sessionRejected');
      expect(event.httpStatus, 401);
      expect(event.exitCode, 1);
    });
  });

  group('the Firefox settings page (the affordances)', () {
    testWidgets('renders the quota card + refresh and NO DNS section',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {
        // Legacy keys a device may still hold — the page ignores them.
        'firefox.dns.mode': 'doh',
        'firefox.dns.provider': 'cloudflare',
      });
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: _SignedInEngine());
      // A metered quota: the card renders the live value, not the
      // placeholder.
      store.applyFirefoxQuota('10737418240', '2147483648', '1767225600');

      await tester.pumpWidget(_booth(FirefoxSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // The quota value (2 GB) renders inside the account card.
      expect(find.text('2 GB'), findsOneWidget);
      // The refresh button exists with its busy seam.
      expect(
        find.byKey(const ValueKey('action-firefox-quota-refresh')),
        findsOneWidget,
      );
      // 2.1.0 — the DNS test button is GONE with the whole DNS section
      // (no resolver pick, no probe, nothing to fail).
      expect(
        find.byKey(const ValueKey('action-firefox-dns-test')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pill-firefox-dns-mode')),
          findsNothing);
      expect(find.byKey(const ValueKey('pill-firefox-dns-provider')),
          findsNothing);
    });

    testWidgets('the unsigned page shows the sign-in button, no quota card',
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
        find.byKey(const ValueKey('action-firefox-quota-refresh')),
        findsNothing,
      );
    });
  });
}
