/// v4.22 — the settings sub-pages test: every page renders its real
/// controls, every control commits to the store / CoreSettings, the
/// coreArgs folding maps the pinned CLI surface exactly, and the
/// persistence round-trips the new layers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/core_settings.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/connection/settings_persistence.dart';
import 'package:aethone/connection/transport_modes.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/settings/appearance_page.dart';
import 'package:aethone/features/settings/connection_page.dart';
import 'package:aethone/features/settings/core_page.dart';
import 'package:aethone/features/settings/general_page.dart';
import 'package:aethone/core/app_meta.dart';
import 'package:aethone/features/settings/language_page.dart';
import 'package:aethone/features/settings/psiphon_page.dart';
import 'package:aethone/features/settings/routing_page.dart';
import 'package:aethone/features/settings/security_page.dart';
import 'package:aethone/features/settings/settings_controls.dart';
import 'package:aethone/features/settings/settings_screen.dart';
import 'package:aethone/features/settings/tor_page.dart';

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

Future<void> _useReferenceSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

ConnectionStore makeStore() =>
    ConnectionStore(engine: EngineNotWiredAdapter());

void main() {
  group('routing page', () {
    testWidgets('renders and commits the area + the route lists', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(RoutingSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // The area pills — the real Persian country names + None.
      expect(find.text('ایران'), findsOneWidget);
      expect(find.text('هیچ‌کدام'), findsOneWidget);
      expect(store.routingRegion, 'ir'); // untouched default

      // Tap «هیچ‌کدام» → the store's null (= None) and the label holds.
      await tester.tap(find.text('هیچ‌کدام'));
      await tester.pumpAndSettle();
      expect(store.routingRegion, isNull);

      // The expert lists exist and commit into CoreSettings.
      await tester.enterText(
        find.byKey(const ValueKey('field-route-block')),
        'ads.example.com',
      );
      await tester.pumpAndSettle();
      expect(store.coreSettings.routeBlock, 'ads.example.com');
    });
  });

  group('general page', () {
    testWidgets('renders the real version row', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(GeneralSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // v1.0.0 (round 18): the version row shows the REAL number
      // («در قسمت تنظیمات عمومی نسخه برنامه رو بنویس طبیعتا نسخه 1.0.0
      // باید باشه»); the repo / Telegram / Instagram link rows are back
      // from the beta-window drop (this round's decree).
      expect(find.byKey(const ValueKey('nav-app-version')), findsOneWidget);
      expect(find.text(appVersion), findsOneWidget); // == '1.0.0' (fa)
      expect(find.byKey(const ValueKey('nav-repository')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-telegram')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-instagram')), findsOneWidget);
    });
  });

  group('connection page', () {
    testWidgets('segments + the core entry row (v4.40: the protocol-mode '
        'section is REMOVED by decree)', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(ConnectionSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // Tunnel mode default is proxy — flip to tunnel.
      expect(store.connectionMode, ConnectionMode.proxy);
      await tester.tap(find.byKey(const ValueKey('conn-mode-tunnel')));
      await tester.pumpAndSettle();
      expect(store.connectionMode, ConnectionMode.tunnel);

      // v4.40 (owner round 15: «حالت پروتکل در تنظیمات اتصال برنامه رو
      // کلا حذف کن») — the AUTO/SMART pills are GONE.
      expect(find.text('اسمارت'), findsNothing);
      expect(find.text('حالت پروتکل'), findsNothing);

      // The core entry row opens the core page. v4.31 added the leg /
      // IP-version / upstream sections above it — scroll it into view.
      await tester.ensureVisible(find.byKey(const ValueKey('nav-core-entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-core-entry')));
      await tester.pumpAndSettle();
      expect(find.text('فرگمنت TLS'), findsOneWidget);
    });
  });

  group('core page', () {
    testWidgets('fragment presets, expert panels, fingerprint rows', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(CoreSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // The Iran profiles are all present.
      expect(find.text('خاموش'), findsOneWidget);
      expect(find.text('استاندارد'), findsOneWidget);
      expect(find.text('متعادل'), findsOneWidget);
      expect(find.text('تهاجمی'), findsOneWidget);
      expect(find.text('سفارشی'), findsOneWidget);

      // Pick «متعادل» — the store holds it; the arg fold gets the values.
      await tester.tap(find.text('متعادل'));
      await tester.pumpAndSettle();
      expect(store.coreSettings.fragmentPreset, FragmentPreset.balanced);

      // «سفارشی» reveals the two fields.
      await tester.tap(find.text('سفارشی'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-frag-size')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('field-frag-size')),
        '25-60',
      );
      await tester.pumpAndSettle();
      expect(store.coreSettings.fragmentSize, '25-60');

      // Expert toggle reveals the TLS + engine panels (may sit below the
      // fold — scroll it into view first).
      await tester.ensureVisible(find.byKey(const ValueKey('toggle-expert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-expert')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('toggle-tls-custom')), findsOneWidget);
      expect(find.byKey(const ValueKey('pill-noize-فایروال')), findsOneWidget);

      // tlsCustom ON reveals the eight fingerprint rows + fields.
      await tester.ensureVisible(
        find.byKey(const ValueKey('toggle-tls-custom')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-tls-custom')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('toggle-tls-ext-perm')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('field-masque-sni')), findsOneWidget);

      // A fingerprint row commits.
      await tester.ensureVisible(
        find.byKey(const ValueKey('toggle-tls-grease')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-tls-grease')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.disableGrease, isTrue);

      // The keepalive stepper commits (deep in the expert engine panel).
      await tester.ensureVisible(
        find.byKey(const ValueKey('step-plus-keepalive')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('step-plus-keepalive')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.keepalive, 6);
    });
  });

  group('language page', () {
    testWidgets('the override commits and system restores null', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(LanguageSettingsPage(store: store)));
      await tester.pumpAndSettle();

      expect(store.appLocale, isNull); // follow system
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(store.appLocale, 'en');

      await tester.tap(find.text('همراه سیستم'));
      await tester.pumpAndSettle();
      expect(store.appLocale, isNull);
    });
  });

  group('appearance page', () {
    testWidgets('home look, motion, patterns switch', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(AppearanceSettingsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('نمای ۲'));
      await tester.pumpAndSettle();
      expect(store.homeLook, HomeLook.two);

      await tester.tap(find.text('نرم'));
      await tester.pumpAndSettle();
      expect(store.animationStyle, MotionStyle.smooth);

      await tester.tap(find.byKey(const ValueKey('toggle-show-patterns')));
      await tester.pumpAndSettle();
      expect(store.showPatterns, isFalse);
    });
  });

  group('security page', () {
    testWidgets('kill switch commits + the core-log row pushes', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(SecuritySettingsPage(store: store)));
      await tester.pumpAndSettle();

      expect(store.killSwitch, isTrue);
      await tester.tap(find.byKey(const ValueKey('toggle-kill-switch')));
      await tester.pumpAndSettle();
      expect(store.killSwitch, isFalse);

      // Mock the aethone/engine bridge for the core-log reader (the
      // repo's established pattern — an empty capture is the honest
      // state before the first connect).
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('aethone/engine'),
            (call) async {
              switch (call.method) {
                case 'readCoreLog':
                  return {'text': '', 'totalBytes': 0};
                case 'clearCoreLog':
                  return null;
              }
              return null;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('aethone/engine'), null);
      });

      await tester.tap(find.byKey(const ValueKey('nav-core-log')));
      // The core-log page runs a 2 s poll timer — never pumpAndSettle on
      // it (it would chase the periodic frames forever). Drive the route
      // transition + the first refresh with plain pumps instead; the
      // refresh future needs a flush frame after the transition pump.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      // No platform bridge in tests — the page shows the honest empty
      // state (never a fabricated log).
      expect(
        find.text('لاگی ثبت نشده است — متصل شوید'),
        findsOneWidget,
      );
      // Pop it via the page's own back button — dispose cancels the poll
      // timer, then settle safely.
      await tester.tap(find.byKey(const ValueKey('core-log-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('subpage-info')), findsOneWidget);
    });
  });

  group('psiphon page', () {
    testWidgets('the strip + fronting pills commit', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(PsiphonSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // AUTO first + the egress regions — anchored on AUTO by default.
      expect(find.byKey(const ValueKey('flag-pick-auto')), findsOneWidget);
      // The strip builds lazily — drag the 2nd tile into view first.
      expect(find.byKey(const ValueKey('flag-pick-at')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('flag-pick-at')));
      await tester.pumpAndSettle();
      expect(store.psiphonLocation, 'at');

      // Fronting: auto → cdn.
      expect(store.coreSettings.psiphonFronting, PsiphonFronting.auto);
      await tester.tap(find.text('فقط CDN'));
      await tester.pumpAndSettle();
      expect(
        store.coreSettings.psiphonFronting,
        PsiphonFronting.cdn,
      );
    });

    // v4.30 — owner round 6, the sync round: «از همون پرچم کشور ها که
    // در صفحه اصلی استفاده کردیم باید در تنظیمات هم استفاده کنیم».
    testWidgets('the strip mirrors the home wheel\'s LIVE egress set '
        '(round 6 sync)', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      // The network's own AvailableEgressRegions report — what the home
      // wheel offers after it arrives.
      store.applyPsiphonEgressRegions(const ['us', 'de']);
      await tester.pumpWidget(_booth(PsiphonSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // The widget's OWN codes — no lazy-build vacuity: the strip list IS
      // the live set (auto first, sorted), the exact list the home wheel
      // offers for a psiphon-exit mode.
      final strip = tester.widget<FlagPickStrip>(find.byType(FlagPickStrip));
      expect(strip.codes, const [
        LocationWheelPolicy.autoCode,
        'de',
        'us',
      ]);
      // A seed-only region is honestly GONE until the network offers it.
      expect(strip.codes, isNot(contains('at')));
    });
  });

  group('tor page', () {
    testWidgets('the exit-country strip + bridges pills commit', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(TorSettingsPage(store: store)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('flag-pick-auto')), findsOneWidget);
      // The strip builds lazily — scroll 'at' into view (early in the
      // sorted snapshot), then tap it. RTL list: forward (later items)
      // is a RIGHTWARD finger drag.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('flag-pick-at')),
        find.byType(FlagPickStrip),
        const Offset(120, 0),
      );
      // Close the drag's gesture arena before tapping (a tap straight
      // after dragUntilVisible gets eaten by the lingering recogniser).
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('flag-pick-at')));
      await tester.pumpAndSettle();
      expect(store.torLocation, 'at');

      // Bridges: auto → off; the tor log level pills commit too. (v4.31c —
      // the combined-mode base section moved onto this page, so the
      // bridges card now sits further down: bring each pill into view
      // before tapping it.)
      await tester.ensureVisible(
        find.byKey(const ValueKey('pill-bridges-بدون پل')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pill-bridges-بدون پل')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.torBridges, TorBridgePolicy.off);

      await tester.ensureVisible(
        find.byKey(const ValueKey('pill-tor-log-دیباگ')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pill-tor-log-دیباگ')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.torLog, TorLogLevel.debug);
    });

    // v4.30 — owner round 6: the settings tor picker must offer the REAL
    // Tor exit countries (the same live/snapshot list the home wheel
    // offers), never the full flag manifest again.
    testWidgets('the strip offers the REAL exit countries, never the full '
        'manifest (round 6)', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(TorSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // The widget's OWN codes — no lazy-build vacuity: the strip list IS
      // the snapshot (auto first), never the full flag manifest ('ir' has
      // no Tor exit relay — the old strip offered it dishonestly).
      var strip = tester.widget<FlagPickStrip>(find.byType(FlagPickStrip));
      expect(
        strip.codes,
        const [LocationWheelPolicy.autoCode, ...torExitCountrySnapshot],
      );
      expect(strip.codes, isNot(contains('ir')));

      // The live Onionoo swap mirrors into the strip — same source as the
      // home wheel (round 6 sync).
      store.applyTorExitCountries(const ['de', 'nl']);
      await tester.pumpAndSettle();
      strip = tester.widget<FlagPickStrip>(find.byType(FlagPickStrip));
      expect(strip.codes, const [
        LocationWheelPolicy.autoCode,
        'de',
        'nl',
      ]);
      // Snapshot-only countries are gone once the LIVE truth lands.
      expect(strip.codes, isNot(contains('jp')));
    });
  });

  group('main settings page routing (v4.22)', () {
    testWidgets('the six cards, family pills and status cards open the '
        'real pages', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(SettingsScreen(store: store)));
      await tester.pumpAndSettle();

      // Card 0 → routing page.
      await tester.tap(find.text('مسیریابی‌ها'));
      await tester.pumpAndSettle();
      expect(find.text('مسیرهای مستقیم و مسدود'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subpage-back')));
      await tester.pumpAndSettle();

      // Card 3 → language page.
      await tester.tap(find.text('تنظیمات زبان'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pill-app-locale-فارسی')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subpage-back')));
      await tester.pumpAndSettle();

      // The Psiphon pill → the psiphon page.
      await tester.tap(find.text('سایفون'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('flag-pick-auto')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subpage-back')));
      await tester.pumpAndSettle();

      // The Kill Switch status card → the security page.
      await tester.dragUntilVisible(
        find.text('Kill Switch'),
        find.byType(SettingsScreen),
        const Offset(0, -80),
      );
      await tester.tap(find.text('Kill Switch'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('toggle-kill-switch')), findsOneWidget);
    });
  });

  group('AetherArguments.coreArgs — the CLI folding', () {
    test('a fresh CoreSettings carries EXACTLY the v4.34 app defaults '
        '(HTTP/2 masque + balanced noize — owner round 10)', () {
      final args = AetherArguments.coreArgs(
        CoreSettings(),
        ProtocolId.wireguard,
        null,
      );
      // v4.34 — the app defaults deliberately differ from the core's own
      // («دیفالت مسک رو بزار روی HTTP2» + «پروفایل دیفالت حالت اغتشاش رو
      // بزار روی متعادل»); everything ELSE stays silent.
      expect(args, contains('--h2'));
      expect(args, containsAllInOrder(['--noize', 'balanced']));
      expect(args.where((a) => a.startsWith('--')).length, 2,
          reason: 'only --h2 + --noize ride a fresh object');
    });

    test('the balanced fragment profile folds size + delay', () {
      final c = CoreSettings()..fragmentPreset = FragmentPreset.balanced;
      final args = AetherArguments.coreArgs(c, ProtocolId.masque, null);
      expect(args, containsAllInOrder(['--fragment']));
      expect(
        args,
        containsAllInOrder(['--fragment-size', '40-100']),
      );
      expect(args, containsAllInOrder(['--fragment-delay', '10-20']));
    });

    test('the standard profile is the bare --fragment', () {
      final c = CoreSettings()..fragmentPreset = FragmentPreset.standard;
      final args = AetherArguments.coreArgs(c, ProtocolId.masque, null);
      expect(args, contains('--fragment'));
      expect(args.any((a) => a.startsWith('--fragment-size')), isFalse);
      expect(args.any((a) => a.startsWith('--fragment-delay')), isFalse);
    });

    test('custom TLS folds only under tlsCustom', () {
      final off = CoreSettings()..disableGrease = true;
      expect(
        AetherArguments.coreArgs(off, ProtocolId.masque, null)
            .contains('--disable-grease'),
        isFalse,
      );
      final on = CoreSettings()
        ..tlsCustom = true
        ..disableGrease = true
        ..tlsVerify = true
        ..tlsGroups = 'P-256:X25519'
        ..ciphers13 = 'TLS_AES_128_GCM_SHA256';
      final args = AetherArguments.coreArgs(on, ProtocolId.masque, null);
      expect(args, contains('--disable-grease'));
      expect(args, contains('--tls-verify'));
      expect(args, containsAllInOrder(['--tls-groups', 'P-256:X25519']));
      expect(
        args,
        containsAllInOrder(['--tls13-ciphers', 'TLS_AES_128_GCM_SHA256']),
      );
    });

    test('transport + engine fold', () {
      final c = CoreSettings()
        ..h2Transport = true
        ..quicV2 = false
        ..dns = '8.8.8.8'
        ..noize = NoizeProfile.gfw
        ..perf = PerfProfile.low
        ..logLevel = CoreLogLevel.debug
        ..keepalive = 25;
      final args = AetherArguments.coreArgs(c, ProtocolId.wireguard, null);
      expect(args, contains('--h2'));
      expect(args, contains('--no-quic-v2'));
      expect(args, containsAllInOrder(['--dns', '8.8.8.8']));
      expect(args, containsAllInOrder(['--noize', 'gfw']));
      expect(args, containsAllInOrder(['--perf', 'low']));
      expect(args, containsAllInOrder(['--log-level', 'debug']));
      expect(args, containsAllInOrder(['--keepalive', '25']));
    });

    test('keepalive skips non-WG legs', () {
      final c = CoreSettings()..keepalive = 25;
      expect(
        AetherArguments.coreArgs(c, ProtocolId.masque, null)
            .contains('--keepalive'),
        isFalse,
      );
      // ...but rides under a family chain (the WG leg under the overlay).
      expect(
        AetherArguments.coreArgs(c, ProtocolId.wireguard, ProtocolId.torChain),
        containsAllInOrder(['--keepalive', '25']),
      );
    });

    test('psiphon fronting + cdn lists fold only in the psiphon family', () {
      final c = CoreSettings()
        ..psiphonFronting = PsiphonFronting.cdn
        ..cdnSni = 'cdn.example.com'
        ..cdnIps = '104.16.0.1';
      final plain = AetherArguments.coreArgs(c, ProtocolId.wireguard, null);
      expect(plain.contains('--psiphon-mode'), isFalse);
      expect(plain.contains('--psiphon-cdn-sni'), isFalse);

      final family = AetherArguments.coreArgs(
        c,
        ProtocolId.wireguard,
        ProtocolId.psiphonChain,
      );
      expect(family, containsAllInOrder(['--psiphon-mode', 'cdn']));
      expect(
        family,
        containsAllInOrder(['--psiphon-cdn-sni', 'cdn.example.com']),
      );
      expect(
        family,
        containsAllInOrder(['--psiphon-cdn-ips', '104.16.0.1']),
      );
    });

    test('tor bridges off folds only in the tor family', () {
      final c = CoreSettings()..torBridges = TorBridgePolicy.off;
      expect(
        AetherArguments.coreArgs(c, ProtocolId.wireguard, null)
            .contains('--no-tor-bridges'),
        isFalse,
      );
      expect(
        AetherArguments.coreArgs(c, ProtocolId.wireguard, ProtocolId.torOnly)
            .contains('--no-tor-bridges'),
        isTrue,
      );
    });

    test('the routing lists fold as lists', () {
      final c = CoreSettings()
        ..routeBlock = 'ads.example.com'
        ..routeDirect = 'bank.example.com';
      final args = AetherArguments.coreArgs(c, ProtocolId.wireguard, null);
      expect(
        args,
        containsAllInOrder(['--route-block', 'ads.example.com']),
      );
      expect(
        args,
        containsAllInOrder(['--route-direct', 'bank.example.com']),
      );
    });

    test('build() with a null core stays exactly as before', () {
      final withDefault = AetherArguments.build(
        protocol: ProtocolId.wireguard,
        filesDir: '/data',
        nativeLibraryDir: '/data/lib',
      );
      // The WG mapping + listener base — nothing extra (a null core means
      // the CORE's own defaults; the v4.34 app defaults live in
      // CoreSettings, not here).
      expect(withDefault, containsAllInOrder(['--protocol', 'wg']));
      expect(withDefault.contains('--fragment'), isFalse);
      expect(withDefault.contains('--h2'), isFalse);
      expect(withDefault.contains('--noize'), isFalse);
    });
  });

  group('core settings persistence round-trip', () {
    test('save → restore keeps every layer + the language + patterns', () async {
      // The mock store is a singleton: both persistence instances read
      // and write the SAME SharedPreferences view.
      SharedPreferences.setMockInitialValues({});
      final persistence = SettingsPersistence();

      final a = makeStore();
      a.updateCore((c) {
        c.fragmentPreset = FragmentPreset.aggressive;
        c.tlsCustom = true;
        c.disableGrease = true;
        c.ciphers13 = 'TLS_AES_128_GCM_SHA256';
        c.h2Transport = true;
        c.dns = '8.8.8.8,8.8.4.4';
        c.noize = NoizeProfile.gfw;
        c.perf = PerfProfile.low;
        c.keepalive = 25;
        c.psiphonFronting = PsiphonFronting.cdn;
        c.cdnSni = 'cdn.example.com';
        c.torBridges = TorBridgePolicy.off;
        c.torLog = TorLogLevel.trace;
        c.routeBlock = 'ads.example.com';
        c.expertRevealed = true;
      });
      a.setAppLocale('en');
      a.setShowPatterns(false);
      await persistence.save(a);

      final b = makeStore();
      await persistence.restore(b);
      expect(b.coreSettings.fragmentPreset, FragmentPreset.aggressive);
      expect(b.coreSettings.tlsCustom, isTrue);
      expect(b.coreSettings.disableGrease, isTrue);
      expect(b.coreSettings.ciphers13, 'TLS_AES_128_GCM_SHA256');
      expect(b.coreSettings.h2Transport, isTrue);
      expect(b.coreSettings.dns, '8.8.8.8,8.8.4.4');
      expect(b.coreSettings.noize, NoizeProfile.gfw);
      expect(b.coreSettings.perf, PerfProfile.low);
      expect(b.coreSettings.keepalive, 25);
      expect(b.coreSettings.psiphonFronting, PsiphonFronting.cdn);
      expect(b.coreSettings.cdnSni, 'cdn.example.com');
      expect(b.coreSettings.torBridges, TorBridgePolicy.off);
      expect(b.coreSettings.torLog, TorLogLevel.trace);
      expect(b.coreSettings.routeBlock, 'ads.example.com');
      expect(b.coreSettings.expertRevealed, isTrue);
      expect(b.appLocale, 'en');
      expect(b.showPatterns, isFalse);
    });

    test('a malformed blob falls back to the defaults', () async {
      SharedPreferences.setMockInitialValues({
        'aethone.settings.coreSettings': '{not json',
      });
      final persistence = SettingsPersistence();
      final b = makeStore();
      await persistence.restore(b);
      expect(b.coreSettings.fragmentPreset, FragmentPreset.off);
      expect(b.coreSettings.tlsCustom, isFalse);
    });
  });

  // v4.31 — owner round 7 («تنظیمات بیشتر»): the new controls commit to
  // the store and render in the pages' own design language.
  group('round 7 — the settings expansion', () {
    testWidgets('tor page: manual bridges policy reveals the lines field',
        (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(TorSettingsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('pill-bridges-دستی')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pill-bridges-دستی')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.torBridges, TorBridgePolicy.custom);

      await tester.ensureVisible(
        find.byKey(const ValueKey('field-tor-bridge-lines')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-tor-bridge-lines')),
        'obfs4 1.2.3.4:443 cert=abc iat-mode=0',
      );
      await tester.pumpAndSettle();
      expect(
        store.coreSettings.torBridgeLines,
        'obfs4 1.2.3.4:443 cert=abc iat-mode=0',
      );
    });

    testWidgets('psiphon page: the ready-budget stepper commits', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(PsiphonSettingsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('step-plus-psiphon-ready-secs')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('step-plus-psiphon-ready-secs')),
      );
      await tester.pumpAndSettle();
      expect(store.coreSettings.psiphonReadySecs, 181);
    });

    testWidgets('connection page: the IP version commits (the family-leg '
        'section moved to the tor/psiphon pages — v4.31c)', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(ConnectionSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // v4.31c — the leg section is GONE from this page (owner round 8:
      // «قسمت پایه حالت های ترکیبی باید توی زیرمجموعه تنطیمات تور و سایفون
      // قرار بگیره»).
      expect(find.byKey(const ValueKey('pill-aether-leg-ماسک')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('pill-ip-version-IPv6')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pill-ip-version-IPv6')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.ipVersion, IpVersion.v6);
    });

    // v4.31c — the per-family legs (owner round 8): each family page owns
    // its own base pick, and the two are INDEPENDENT.
    testWidgets('tor page: the family-leg pills commit torLegProtocol only',
        (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(TorSettingsPage(store: store)));
      await tester.pumpAndSettle();

      expect(
        store.coreSettings.torLegProtocol,
        AetherLegProtocol.wireguard,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('pill-tor-leg-ماسک')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pill-tor-leg-ماسک')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.torLegProtocol, AetherLegProtocol.masque);
      // The OTHER family's leg is untouched — per family, not shared.
      expect(
        store.coreSettings.psiphonLegProtocol,
        AetherLegProtocol.wireguard,
      );
    });

    testWidgets('psiphon page: the family-leg pills commit '
        'psiphonLegProtocol only', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(PsiphonSettingsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('pill-psiphon-leg-ماسک')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pill-psiphon-leg-ماسک')));
      await tester.pumpAndSettle();
      expect(
        store.coreSettings.psiphonLegProtocol,
        AetherLegProtocol.masque,
      );
      expect(
        store.coreSettings.torLegProtocol,
        AetherLegProtocol.wireguard,
      );
    });

    testWidgets('core page: the expert ECH pills commit', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(CoreSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // Reveal the expert panels, then the ECH card.
      await tester.ensureVisible(find.byKey(const ValueKey('toggle-expert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-expert')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('pill-ech-mode-خودکار')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pill-ech-mode-خودکار')));
      await tester.pumpAndSettle();
      expect(store.coreSettings.echMode, EchMode.auto);
    });
  });
}
