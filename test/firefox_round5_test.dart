// The owner's round 5 tests (2026-11-15) — the remaining-data fix, the
// DNS hardening and the loading affordances:
//
//   * FirefoxQuota.parse: the explicit quotaUnlimited flag (the `--usage`
//     role's X-Quota-Unlimited) wins alone; the metered trio parses; the
//     empty pair stays the inferred-unlimited case; garbage stays null.
//   * The store NEVER sends an invalid DNS config line (a custom provider
//     without an endpoint killed BOTH carrier modes with dnsConfigInvalid
//     and failed every DNS probe — the round's connection regression).
//   * Switching DNS providers resets the endpoint fields (a stale custom
//     endpoint must never ride the newly picked provider's defaults).
//   * The usage event parses (quotaUnlimited rides along, no secrets).
//   * The Firefox settings page renders the quota card + its refresh
//     button and the DNS test button (the scan-loading affordances).
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

  group('the store\'s DNS config line (1.7.0 — never invalid)', () {
    test('custom without an endpoint degrades to system', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'custom';
      store.firefoxDnsEndpoint = '';
      expect(store.firefoxDnsConfig['mode'], 'system');
      expect(store.firefoxDnsCustomIncomplete, isTrue);
    });

    test('custom WITH an endpoint rides the doh line', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'custom';
      store.firefoxDnsEndpoint = 'https://dns.example/dns-query';
      expect(store.firefoxDnsConfig['mode'], 'doh');
      expect(store.firefoxDnsConfig['endpoint'], 'https://dns.example/dns-query');
      expect(store.firefoxDnsCustomIncomplete, isFalse);
    });

    test('the built-in providers send mode doh with no endpoint override', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'cloudflare';
      store.firefoxDnsEndpoint = ''; // never set for built-ins
      expect(store.firefoxDnsConfig['mode'], 'doh');
      expect(store.firefoxDnsConfig['provider'], 'cloudflare');
      expect(store.firefoxDnsConfig.containsKey('endpoint'), isFalse);
    });

    test('leaving the custom provider resets the endpoint fields', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'custom';
      store.firefoxDnsEndpoint = 'https://stale.example/dns-query';
      store.setFirefoxDnsCustom('https://stale.example/dns-query', '1.1.1.1');
      store.setFirefoxDnsProvider('google');
      expect(store.firefoxDnsProvider, 'google');
      expect(store.firefoxDnsEndpoint, '');
      expect(store.firefoxDnsBootstrapIps, isEmpty);
      // The engine line lets the provider default apply (no endpoint).
      expect(store.firefoxDnsConfig.containsKey('endpoint'), isFalse);
    });

    test('staying on custom keeps the endpoint', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'custom';
      store.setFirefoxDnsCustom('https://keep.example/dns-query', '');
      store.setFirefoxDnsProvider('custom');
      expect(store.firefoxDnsEndpoint, 'https://keep.example/dns-query');
    });
  });

  group('the DNS config line (1.7.1 — round 6: malformed never rides)', () {
    // The round-6 device report: «راه‌اندازی DNS انتخاب‌شده ناموفق بود»
    // on the DNS test AND «صفحه وب در دسترس نیست» on the login page AND
    // no connection at all — one root: a MALFORMED custom endpoint or
    // junk bootstrap IPs (persisted by the earlier builds, accepted by
    // the free-text fields) made dnsresolver.Install fail in EVERY
    // role (each installs the DNS policy before any network work).
    test('a MALFORMED custom endpoint degrades to system (not just empty)',
        () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'custom';
      // No scheme / plain hostname / http — all shapes the free-text
      // field accepted.
      for (final bad in [
        'dns.example.com/dns-query',
        'http://dns.example/dns-query',
        'https://',
        'not a url at all',
      ]) {
        store.firefoxDnsEndpoint = bad;
        expect(store.firefoxDnsConfig['mode'], 'system',
            reason: '$bad must never reach the engine line');
        expect(store.firefoxDnsCustomIncomplete, isTrue,
            reason: '$bad must surface the hint');
      }
    });

    test('a VALID custom endpoint still rides after the hardening', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'custom';
      store.firefoxDnsEndpoint = 'https://1.2.3.4/dns-query';
      expect(store.firefoxDnsConfig['mode'], 'doh');
      expect(store.firefoxDnsConfig['endpoint'], 'https://1.2.3.4/dns-query');
      expect(store.firefoxDnsCustomIncomplete, isFalse);
    });

    test('junk bootstrap IPs are FILTERED, not fatal (every provider)', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'cloudflare';
      // Legacy-persisted junk (urls, words, empty-ish entries) beside
      // one real IP.
      store.firefoxDnsBootstrapIps = const [
        'https://8.8.8.8/dns-query',
        'abc',
        '1.1.1.1',
        '',
      ];
      final config = store.firefoxDnsConfig;
      expect(config['mode'], 'doh',
          reason: 'junk bootstrap entries must not kill the provider');
      expect(config['bootstrapIps'], const ['1.1.1.1']);
    });

    test('all-junk bootstrap yields no bootstrapIps key at all', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'google';
      store.firefoxDnsBootstrapIps = const ['not-an-ip', 'x.x.x.x'];
      expect(store.firefoxDnsConfig['mode'], 'doh');
      expect(store.firefoxDnsConfig.containsKey('bootstrapIps'), isFalse);
    });

    test('setFirefoxDnsCustom sanitizes junk IPs at save time', () {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.setFirefoxDnsCustom('https://dns.example/dns-query',
          '1.1.1.1, garbage, 2606:4700:4700::1111, , ok');
      expect(store.firefoxDnsBootstrapIps,
          const ['1.1.1.1', '2606:4700:4700::1111']);
    });

    test('the round-6 regression shape end-to-end: malformed persisted state',
        () {
      // Exactly what the device held: DoH + custom + a schemeless
      // endpoint + junk bootstrap, persisted by the round-4/5 build.
      // EVERY consumer (the tunnel config, the login screen's proxy
      // line, the DNS probe) reads this ONE getter — it must yield a
      // line the engine accepts.
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.firefoxDnsMode = 'doh';
      store.firefoxDnsProvider = 'custom';
      store.firefoxDnsEndpoint = 'dns.example.com/dns-query';
      store.firefoxDnsBootstrapIps = const ['junk'];
      final config = store.firefoxDnsConfig;
      expect(config['mode'], 'system');
      expect(config.containsKey('endpoint'), isFalse);
      expect(config.containsKey('bootstrapIps'), isFalse);
      expect(store.firefoxDnsCustomIncomplete, isTrue);
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

  group('the Firefox settings page (1.7.0 affordances)', () {
    testWidgets('renders the quota card + refresh and the DNS test button',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {
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
      // The DNS test button exists (its busy state rides the probe).
      expect(
        find.byKey(const ValueKey('action-firefox-dns-test')),
        findsOneWidget,
      );
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
