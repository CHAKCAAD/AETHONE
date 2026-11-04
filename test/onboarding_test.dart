/// v4.23 — the first-run wizard («صفحه شروع») test: every step renders its
/// frame's real chrome (headings verbatim, tiles, segments, cards, pills),
/// every pick commits to the store the moment it is tapped, system BACK
/// walks the wizard to the previous step, and «برو بریم!» runs the branded
/// scanning wait, then flips the persisted onboarding flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/onboarding/onboarding_flow.dart';

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
  // The wizard's own reference frame: 402×874 (AethGeometry.refWidth).
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Motion OFF everywhere: the AnimatedSwitcher steps land instantly and the
/// scanning layer never starts its pulse ticker, so pumpAndSettle is honest.
ConnectionStore makeStore() {
  final store = ConnectionStore(engine: EngineNotWiredAdapter());
  store.animationStyle = MotionStyle.off;
  return store;
}

Future<void> _advance(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(const ValueKey('ob-cta')));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('onboarding wizard (v4.23)', () {
    testWidgets('step 1 — the language grid renders and commits live', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(OnboardingFlow(store: store)));
      await tester.pumpAndSettle();

      // The frame's chrome: heading verbatim, lockup, stepper, CTA.
      expect(find.text('زبان برنامه چی باشه؟'), findsOneWidget);
      expect(find.text('AETHONE'), findsOneWidget);
      expect(find.text('ادامه بده'), findsOneWidget);

      // All six tiles (5 flags + the gray system tile).
      for (final id in ['fa', 'tk', 'en', 'zh', 'ru', 'system']) {
        expect(
          find.byKey(ValueKey('ob-lang-$id')),
          findsOneWidget,
          reason: 'language tile $id missing',
        );
      }

      // A fresh in-memory store follows the system (null) — tapping a flag
      // commits the override, tapping the gray tile returns to null.
      expect(store.appLocale, isNull);
      await tester.tap(find.byKey(const ValueKey('ob-lang-fa')));
      await tester.pumpAndSettle();
      expect(store.appLocale, 'fa');
      await tester.tap(find.byKey(const ValueKey('ob-lang-system')));
      await tester.pumpAndSettle();
      expect(store.appLocale, isNull);

      // The CTA advances to step 2.
      await _advance(tester, 1);
      expect(find.text('ترافیک کدوم کشور مستقیم باشه؟'), findsOneWidget);
    });

    testWidgets('step 2 — the staggered routing grid commits; BACK walks', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(OnboardingFlow(store: store)));
      await tester.pumpAndSettle();
      await _advance(tester, 1);

      // The frame's five tiles: ir/tm top, none mid-left, ru/cn below.
      for (final id in ['ir', 'tm', 'none', 'ru', 'cn']) {
        expect(
          find.byKey(ValueKey('ob-route-$id')),
          findsOneWidget,
          reason: 'routing tile $id missing',
        );
      }

      // Region picks commit live; «none» stores the null.
      expect(store.routingRegion, 'ir'); // the store's own default
      await tester.tap(find.byKey(const ValueKey('ob-route-tm')));
      await tester.pumpAndSettle();
      expect(store.routingRegion, 'tm');
      await tester.tap(find.byKey(const ValueKey('ob-route-none')));
      await tester.pumpAndSettle();
      expect(store.routingRegion, isNull);

      // System BACK on step 2 walks to step 1 (the PopScope contract).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('زبان برنامه چی باشه؟'), findsOneWidget);
    });

    testWidgets('steps 3–4 — look, mode, protocol cards, scan pills', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(OnboardingFlow(store: store)));
      await tester.pumpAndSettle();

      // Step 3 — the two look previews; the check badge rides the pick.
      await _advance(tester, 2);
      expect(find.text('ضاهر دکمه اتصال چجوری باشه؟'), findsOneWidget);
      expect(store.homeLook, HomeLook.one);
      await tester.tap(find.byKey(const ValueKey('ob-look-two')));
      await tester.pumpAndSettle();
      expect(store.homeLook, HomeLook.two);

      // Step 4 — «حالت اتصال» segments, the option cards, «سرعت اسکن».
      await _advance(tester, 1);
      expect(find.text('برو بریم!'), findsOneWidget);
      expect(find.text('پروتکل اتوماتیک میخوای؟'), findsOneWidget);
      expect(find.text('اتوماتیک'), findsOneWidget);
      expect(find.text('دستی'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ob-segment-tunnel')));
      await tester.pumpAndSettle();
      expect(store.connectionMode, ConnectionMode.tunnel);

      await tester.tap(find.byKey(const ValueKey('ob-card-auto')));
      await tester.pumpAndSettle();
      expect(store.protocolModeSmart, isTrue);

      await tester.ensureVisible(find.byKey(const ValueKey('ob-scan-2')));
      await tester.tap(find.byKey(const ValueKey('ob-scan-2')));
      await tester.pumpAndSettle();
      expect(store.scanSpeed, 2);
    });

    testWidgets('«برو بریم!» — the scanning wait, then the commit', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(OnboardingFlow(store: store)));
      await tester.pumpAndSettle();
      await _advance(tester, 3); // → step 4

      expect(store.onboardingComplete, isFalse);
      await tester.tap(find.byKey(const ValueKey('ob-cta'))); // «برو بریم!»
      await tester.pump(); // the scanning layer mounts

      // The branded modal over the blurred step-4 page.
      expect(find.byKey(const ValueKey('ob-scanning-modal')), findsOneWidget);
      expect(find.text('در حال پیدا کردن بهترین راه'), findsOneWidget);
      expect(store.onboardingComplete, isFalse); // still waiting

      // The ~3 s wait fires the commit + the handover to the home route.
      await tester.pump(const Duration(milliseconds: 3300));
      expect(store.onboardingComplete, isTrue);
      await tester.pumpAndSettle(); // the home route lands (motion off)
    });
  });
}
