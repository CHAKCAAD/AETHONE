import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/features/settings/settings_screen.dart';

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
  // The design reference frame (402×874 @ dpr 3).
  Future<void> useReferenceSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  ConnectionStore makeStore() =>
      ConnectionStore(engine: EngineNotWiredAdapter());

  testWidgets('v1.1.0 control center: hero, quick controls, search, '
      'categories, protocols, support', (tester) async {
    await useReferenceSurface(tester);
    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('تنظیمات'), findsOneWidget);
    // v1.1.0 round 2 — the hero/quick-controls block is removed.
    expect(find.byKey(const ValueKey('settings-hero')), findsNothing);
    expect(find.byKey(const ValueKey('quick-kill-switch')), findsNothing);
    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
    // Four merged categories (security folded into connection, language
    // into look).
    expect(find.text('اتصال و امنیت'), findsOneWidget);
    expect(find.text('مسیریابی‌ها'), findsOneWidget);
    expect(find.text('ظاهر و زبان'), findsOneWidget);
    expect(find.text('تنظیمات عمومی'), findsOneWidget);
    expect(find.text('تنظیمات زبان'), findsNothing);
    expect(find.text('تنظیمات امنیت'), findsNothing);
    for (final k in [
      'settings-proto-psiphon',
      'settings-proto-tor',
      'settings-proto-lantern',
      'settings-proto-core',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    // Support & diagnostics moved to the general page.
    expect(find.byKey(const ValueKey('settings-core-log-card')), findsNothing);
    expect(AppAssets.iconSearch, contains('Search 1.svg'));
  });

  testWidgets('summaries follow the REAL store state', (tester) async {
    await useReferenceSurface(tester);
    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    store.setKillSwitch(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Kill Switch روشن'), findsOneWidget);

    store.setKillSwitch(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Kill Switch خاموش'), findsOneWidget);
  });

  testWidgets('settings page is scrollable on a short viewport',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 560 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('settings-proto-core')),
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    expect(find.byKey(const ValueKey('settings-proto-core')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

