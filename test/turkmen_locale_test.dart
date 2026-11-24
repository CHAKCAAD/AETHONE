// v4.42 — the Turkmen locale regression tests: the v4.41 approach
// (mapping 'tk' onto the English MATERIAL locale while keeping the tk
// AppStrings table) was self-defeating — AppStrings resolves through
// the MATERIAL locale, read 'en', and rendered English forever (the
// owner's report: «زبان ترکمنی اپ کار نمیکنه و به جاش زبان انگلیسی
// نمایش داده میشه»). tk is now a first-class Locale with fallback
// delegates feeding the framework widgets their English strings.
import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/l10n/app_strings.dart';

void main() {
  testWidgets(
    'the tk pick renders TURKMEN strings through the real shell (v4.42)',
    (tester) async {
      // The app's own phone geometry (the onboarding layout overflows
      // the default 800x600 test surface).
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.onboardingComplete = false; // the wizard is the first surface
      store.setAppLocale('tk');
      await tester.pumpWidget(AethoneApp(store: store));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // The login's own «بعدی» pill — TURKMEN, never the English
      // fallback the v4.41 mapping produced.
      final tk = AppStrings.forLocale('tk');
      expect(find.text(tk.loginNext), findsWidgets);
      expect(
          find.text(AppStrings.forLocale('en').loginNext), findsNothing);
    },
  );

  testWidgets(
    'the framework widgets still localize under tk (the fallback delegates)',
    (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.onboardingComplete = false;
      store.setAppLocale('tk');
      await tester.pumpWidget(AethoneApp(store: store));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // The Material/Widgets/Cupertino localization objects must EXIST
      // under the tk locale (the delegates load the English resources —
      // without them the shell would crash on the first tooltip). The
      // probe element must sit BELOW the MaterialApp's own Localizations
      // tree (the MaterialApp element itself is above it).
      final element = tester.element(
        find.text(AppStrings.forLocale('tk').loginNext).first,
      );
      expect(MaterialLocalizations.of(element), isNotNull);
      expect(Localizations.of<WidgetsLocalizations>(
          element, WidgetsLocalizations), isNotNull);
      expect(Localizations.of<CupertinoLocalizations>(
          element, CupertinoLocalizations), isNotNull);
    },
  );

  test('AppStrings resolves the tk table natively', () {
    // The table itself (the v4.41 work, kept): forLocale('tk') is the
    // Turkmen map, and a tk-AMBIENT resolution picks it.
    final tk = AppStrings.forLocale('tk');
    expect(tk.loginLanguageTitle, 'Programma dili');
    expect(AppStrings.forLocale('en').loginLanguageTitle,
        isNot(tk.loginLanguageTitle));
  });
}
