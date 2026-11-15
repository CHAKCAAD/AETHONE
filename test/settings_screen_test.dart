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

  testWidgets('settings page renders the design structure '
      '(top bar, 6 cards, 2 pills, status, core log)', (tester) async {
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

    // Section heading — v4.15 #5: «وضعیت پیشرفته» → «وضعیت پیکربندی».
    expect(find.text('وضعیت پیکربندی'), findsOneWidget);

    // v1.5.0 (fix 1) — the «آدرس هسته ها» section MOVED to the general
    // settings page: neither the heading nor the pills live here anymore.
    expect(find.text('آدرس هسته ها'), findsNothing);

    // Status values — the REAL store defaults (ON / Iran / the selected
    // protocol's own name — v4.40: the AUTO/SMART protocol-mode row is
    // retired, the card shows the protocol itself).
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('Iran'), findsOneWidget);
    expect(find.text('وایرگارد'), findsOneWidget); // default protocol name

    // The Firefox pill's remaining-data slot (fix 3): never-known quota
    // renders the honest placeholder, never a made-up number.
    expect(find.text('حجم باقی‌مانده'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('status cards follow the REAL store state', (tester) async {
    await useReferenceSurface(tester);
    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    // Defaults — the protocol card renders the SELECTED protocol's own
    // name (v4.40: the AUTO/SMART mode row is retired by decree).
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('وایرگارد'), findsOneWidget);

    // Flip every preference — the cards must re-render.
    store.setKillSwitch(false);
    store.selectProtocol(ProtocolId.torOnly);
    store.setRoutingRegion(null);
    await tester.pumpAndSettle();

    expect(find.text('OFF'), findsOneWidget);
    // «تور» twice: the Tor PILL (standing) + the protocol status card
    // (v4.40: the card shows the selected protocol's own name).
    expect(find.text('تور'), findsNWidgets(2));
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

    // The core-log entry exists below the fold — drag up to reveal it
    // (v1.5.0: the server pills moved to the general settings page).
    await tester.drag(find.byType(SettingsScreen), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('settings-core-log-card')),
        findsOneWidget);
  });

  testWidgets('the Firefox pill quota slot follows the store state '
      '(fix 3: metered / unlimited / re-render)', (tester) async {
    await useReferenceSurface(tester);
    final store = makeStore();
    await tester.pumpWidget(_booth(SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    // Metered: 5 GB of 10 GB left → «5 GB» in the accent-green value.
    store.applyFirefoxQuota('10737418240', '5368709120', '1735689600');
    await tester.pumpAndSettle();
    expect(find.text('حجم باقی‌مانده'), findsOneWidget);
    expect(find.text('5 GB'), findsOneWidget);

    // Unlimited: the empty pair is the no-metered-quota case.
    store.applyFirefoxQuota('', '', '');
    await tester.pumpAndSettle();
    expect(find.text('نامحدود'), findsOneWidget);
    expect(find.text('5 GB'), findsNothing);

    // Sub-GB metering renders MB (the bottom panel's own grammar).
    store.applyFirefoxQuota('536870912', '268435456', '');
    await tester.pumpAndSettle();
    expect(find.text('256 MB'), findsOneWidget);
  });
}
