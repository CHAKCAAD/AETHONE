/// v6 — the first-run login («صفحه ورود») test: the five steps render
/// their frames' real chrome (the notch indicator, the glyph tile, the
/// verbatim titles, the flag circles, the look previews, the nav pills),
/// every pick commits to the store the moment it is tapped, system BACK
/// walks the login backwards, and «بریم!» flips the persisted onboarding
/// flag and hands the navigator to the home screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/onboarding/login_flow.dart';

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
  // The login's own reference frame: 402×874 (AethGeometry.refWidth).
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Motion OFF everywhere: the switchers, cascades and pill morphs land
/// instantly, so pumpAndSettle is honest (the video player never
/// initializes under the test host — the poster fallback renders instead).
ConnectionStore makeStore() {
  final store = ConnectionStore(engine: EngineNotWiredAdapter());
  store.animationStyle = MotionStyle.off;
  return store;
}

Future<void> _advance(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(const ValueKey('login-next')));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('login flow (v6 «صفحه ورود»)', () {
    testWidgets('step 1 — the welcome frame: title, description, بعدی', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(LoginFlow(store: store)));
      await tester.pumpAndSettle();

      // The frame's chrome: the notch indicator, the glyph tile, the
      // verbatim title + description, the single «بعدی» pill.
      expect(find.byType(LoginStepIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('login-icon-box')), findsOneWidget);
      expect(find.text('برای ماجراجویی آماده‌ای؟'), findsOneWidget);
      expect(
        find.textContaining('در چند قدم ساده، با امکانات AETHONE آشنا شو'),
        findsOneWidget,
      );
      expect(find.text('بعدی'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-prev')), findsNothing);
      expect(find.byKey(const ValueKey('login-go')), findsNothing);

      // The CTA advances to the language step.
      await _advance(tester, 1);
      expect(find.text('زبان برنامه'), findsOneWidget);
    });

    testWidgets('step 2 — the five language circles commit live', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(LoginFlow(store: store)));
      await tester.pumpAndSettle();
      await _advance(tester, 1);

      // The frame's five circles: us/tm/ir on the top row, ru/cn below.
      for (final id in ['en', 'tk', 'fa', 'ru', 'zh']) {
        expect(
          find.byKey(ValueKey('login-lang-$id')),
          findsOneWidget,
          reason: 'language circle $id missing',
        );
      }
      expect(find.text('زبان برنامه'), findsOneWidget);
      // The middle steps carry the pill PAIR.
      expect(find.byKey(const ValueKey('login-prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-next')), findsOneWidget);

      // A fresh in-memory store follows the system (null) — the frame's
      // own display default is 'fa' (the restore's fresh-install pick);
      // tapping a flag commits the override the moment it lands.
      expect(store.appLocale, isNull);
      await tester.tap(find.byKey(const ValueKey('login-lang-tk')));
      await tester.pumpAndSettle();
      expect(store.appLocale, 'tk');
      await tester.tap(find.byKey(const ValueKey('login-lang-fa')));
      await tester.pumpAndSettle();
      expect(store.appLocale, 'fa');

      // System BACK on step 2 walks to the welcome step (the PopScope
      // contract).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('برای ماجراجویی آماده‌ای؟'), findsOneWidget);
    });

    testWidgets('step 3 — the four routing circles commit live', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(LoginFlow(store: store)));
      await tester.pumpAndSettle();
      await _advance(tester, 2);

      expect(find.text('منطقه مسیریابی'), findsOneWidget);
      for (final id in ['tm', 'ir', 'ru', 'cn']) {
        expect(
          find.byKey(ValueKey('login-route-$id')),
          findsOneWidget,
          reason: 'routing circle $id missing',
        );
      }

      // Region picks commit live; the store's own default is 'ir'.
      expect(store.routingRegion, 'ir');
      await tester.tap(find.byKey(const ValueKey('login-route-tm')));
      await tester.pumpAndSettle();
      expect(store.routingRegion, 'tm');
      await tester.tap(find.byKey(const ValueKey('login-route-ir')));
      await tester.pumpAndSettle();
      expect(store.routingRegion, 'ir');
    });

    testWidgets('step 4 — the two look previews commit live', (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(LoginFlow(store: store)));
      await tester.pumpAndSettle();
      await _advance(tester, 3);

      expect(find.text('ضاهر برنامه'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('login-look-two')),
        findsOneWidget,
        reason: 'the look-2 glow preview is missing',
      );
      expect(
        find.byKey(const ValueKey('login-look-one')),
        findsOneWidget,
        reason: 'the look-1 hero logo preview is missing',
      );

      // The pick commits the moment it lands (the store's own default is
      // look one).
      expect(store.homeLook, HomeLook.one);
      await tester.tap(find.byKey(const ValueKey('login-look-two')));
      await tester.pumpAndSettle();
      expect(store.homeLook, HomeLook.two);
      await tester.tap(find.byKey(const ValueKey('login-look-one')));
      await tester.pumpAndSettle();
      expect(store.homeLook, HomeLook.one);
    });

    testWidgets('«بریم!» — the commit and the handover to home', (
      tester,
    ) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(LoginFlow(store: store)));
      await tester.pumpAndSettle();
      await _advance(tester, 4);

      // The done frame: the verbatim title, the single «بریم!» pill.
      expect(find.text('اتمام راه اندازی!'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-go')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-prev')), findsNothing);

      expect(store.onboardingComplete, isFalse);
      await tester.tap(find.byKey(const ValueKey('login-go')));
      await tester.pump();

      // The commit fires immediately; the home route lands (motion off).
      expect(store.onboardingComplete, isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
