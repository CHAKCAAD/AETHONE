import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
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

  testWidgets('settings page renders the design structure '
      '(top bar, 6 cards, 2 pills, status, server)', (tester) async {
    await useReferenceSurface(tester);
    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    // Top bar: title.
    expect(find.text('تنظیمات'), findsOneWidget);

    // The six category cards (fa, verbatim from the design frame).
    expect(find.text('مسیریابی‌ها'), findsOneWidget);
    expect(find.text('تنظیمات عمومی'), findsOneWidget);
    expect(find.text('تنظیمات اتصال'), findsOneWidget);
    expect(find.text('تنظیمات زبان'), findsOneWidget);
    expect(find.text('تنظیمات ظاهری'), findsOneWidget);
    expect(find.text('تنظیمات امنیت'), findsOneWidget);

    // The two wide protocol pills — v4.15 #8: renamed «تنظیمات سایفون» →
    // «سایفون» and «تنظیمات تور» → «تور» (owner's own words).
    expect(find.text('سایفون'), findsOneWidget);
    expect(find.text('تور'), findsOneWidget);

    // Section headings — v4.15 #5/#6: «وضعیت پیشرفته» → «وضعیت پیکربندی»,
    // «آدرس سرور اصلی» → «آدرس هسته ها».
    expect(find.text('وضعیت پیکربندی'), findsOneWidget);
    expect(find.text('آدرس هسته ها'), findsOneWidget);

    // Status values — the REAL store defaults (ON / Iran / AUTO).
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('Iran'), findsOneWidget);
    expect(find.text('AUTO / SMART'), findsOneWidget);

    // Server pills.
    expect(find.text('Zeptun Tunnel'), findsOneWidget);
    expect(find.text('Aether Core'), findsOneWidget);
  });

  testWidgets('status cards follow the REAL store state', (tester) async {
    await useReferenceSurface(tester);
    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    // Defaults — the protocol card renders the mode's Latin name exactly
    // like the frame («AUTO / SMART»).
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('AUTO / SMART'), findsOneWidget);

    // Flip every preference — the cards must re-render.
    store.setKillSwitch(false);
    store.setProtocolModeSmart(true);
    store.setRoutingRegion(null);
    await tester.pumpAndSettle();

    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('SMART'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('ON'), findsNothing);
  });

  testWidgets('settings page is scrollable and headings stay intact '
      'on a short viewport', (tester) async {
    // A short surface forces the scroll — nothing may overflow.
    tester.view.physicalSize = const Size(402 * 3, 500 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The server pills exist below the fold — drag up to reveal them.
    await tester.drag(find.byType(SettingsScreen), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Zeptun Tunnel'), findsOneWidget);
    expect(find.text('Aether Core'), findsOneWidget);
  });
}
