/// v4.16 — regression tests for the REAL protocol-selection surface,
/// pixel-faithful to «صفحه شناور انتخاب پروتکل صفحه اصلی.jpg».
/// v4.17 — the surface is a FULL PAGE (owner: «در یک صفحه جدا مثل صفحه
/// اصلی تنظیمات قرار بدیم»): the tests track the page chrome, the yellow-
/// underline Material fix, the live mode/pill binding, the family-card
/// breathing and the enlarged ⓘ / × hit targets.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/core/design_tokens.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/protocol_sheet/protocol_sheet.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ScriptedEngine extends EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => _controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  @override
  @override
  void bind(EngineConfigSource config) {} // scripted — config never read
}

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

/// Opens the home, taps the protocol card, rides out the entry cascade.
Future<void> _openPage(WidgetTester tester, ConnectionStore store) async {
  await tester.pumpWidget(_booth(HomeScreen(store: store)));
  await tester.pumpAndSettle();
  // The home protocol card shows the selected protocol's own name — the
  // v4.19 cold default is WIREGUARD (owner device-test decree #4).
  await tester.tap(find.text('وایرگارد').first);
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _tapAndAutoPop(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump(); // selection frame
  await tester.pump(const Duration(milliseconds: 320)); // auto-pop delay
  await tester.pumpAndSettle(); // reverse transition
}

void main() {
  testWidgets(
      'the protocol PAGE opens from the home protocol card and shows all 12 '
      'protocols + the three sections + the page chrome (v4.17)', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openPage(tester, store);

    // The page chrome: title + back/info tiles (settings-page style).
    expect(find.text('انتخاب پروتکل'), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-page-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-page-info')), findsOneWidget);
    // v4.19 (#10): the owner swapped the sides — the tiles exchanged their
    // visual slots. The chrome row lays out under the app's RTL
    // directionality (first Row child = visual RIGHT): the BACK tile now
    // takes the visual RIGHT slot and the INFO (Telegram) tile the LEFT.
    final backX = tester.getCenter(find.byKey(const ValueKey('proto-page-back'))).dx;
    final infoX = tester.getCenter(find.byKey(const ValueKey('proto-page-info'))).dx;
    expect(backX, greaterThan(infoX));

    // Section headings (verbatim frame text).
    expect(find.text('حالت اتصال'), findsOneWidget);
    expect(find.text('پروتکل'), findsWidgets);
    expect(find.text('سرعت اسکن'), findsOneWidget);

    // The mode segments (frame: تونل right / پروکسی left, proxy selected).
    expect(find.text('تونل'), findsOneWidget);
    expect(find.text('پروکسی'), findsOneWidget);

    // All 12 protocols: 6 tiles («اتوماتیک» is the frame's own wording) +
    // the 2 family labels. The pills are unlabeled per the frame.
    expect(find.text('اتوماتیک'), findsOneWidget);
    expect(find.text('وایرگارد'), findsOneWidget);
    expect(find.text('گول'), findsOneWidget);
    expect(find.text('گول کلاسیک'), findsOneWidget);
    expect(find.text('میم'), findsOneWidget);
    expect(find.text('سایفون'), findsOneWidget);
    expect(find.text('تور'), findsOneWidget);
    // 5 unlabeled pills.
    expect(find.byKey(const ValueKey('proto-pill-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-pill-5')), findsOneWidget);

    // RTL grid order (frame row 1): اتوماتیک rightmost, وایرگارد leftmost.
    final auto = tester.getCenter(find.text('اتوماتیک'));
    final masqueTile = tester.getCenter(find.byKey(
      const ValueKey('proto-tile-masque'),
    ));
    final wg = tester.getCenter(find.text('وایرگارد'));
    expect(auto.dx, greaterThan(masqueTile.dx));
    expect(masqueTile.dx, greaterThan(wg.dx));

    // Geometry spot checks (the view is 402 logical px — 1:1 with the
    // reference frame): headings, segments, cards, pills.
    final seg = tester.getCenter(find.text('تونل'));
    expect(
      seg.dy,
      closeTo(AethGeometry.protoSegmentTop + AethGeometry.protoSegmentH / 2, 3),
    );
    expect(
      tester.getCenter(find.text('پروکسی')).dx,
      lessThan(seg.dx), // پروکسی on the visual LEFT (frame order)
    );

    final psy = tester.getRect(
      find.byKey(const ValueKey('proto-card-psiphon')),
    );
    expect(psy.top, closeTo(AethGeometry.protoCardTopPsiphon, 2));
    expect(psy.height, closeTo(AethGeometry.protoCardH, 2));
    // v4.17: the family cards breathe (h 116) and the tor card follows.
    final tor = tester.getRect(
      find.byKey(const ValueKey('proto-card-tor')),
    );
    expect(
      tor.top,
      closeTo(
        AethGeometry.protoCardTopPsiphon + AethGeometry.protoCardH + 15,
        2,
      ),
    );

    final p5 = tester.getRect(find.byKey(const ValueKey('proto-pill-5')));
    expect(p5.top, closeTo(AethGeometry.protoPillTop, 2));
    // The pills row is CENTERED (frame x33..367) — pill 5 right edge ≈367.
    expect(p5.right, closeTo(367, 3));

    // v4.19: the app's cold DEFAULT is WireGuard (owner decree #4 — until
    // the settings redesign ships), so ITS tile renders selected (green).
    // The design mock merely shows WireGuard picked; report table 11 still
    // documents MASQUE as the CORE's own default (the AUTO tile path).
    final wgContainer = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('proto-tile-wireguard')),
        matching: find.byType(AnimatedContainer),
      ).first,
    );
    expect(
      (wgContainer.decoration as BoxDecoration).color,
      AethColors.accentConnected,
    );
  });

  testWidgets(
      'tapping a tile commits the protocol and AUTO-POPS back to the home '
      '(owner: «بعد از انتخاب پروتکل به صورت خودکار کاربر باید به صفحه اول '
      'بازگردد»)', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openPage(tester, store);

    await _tapAndAutoPop(tester, find.byKey(const ValueKey('proto-tile-wireguard')));

    expect(store.selectedProtocol, ProtocolId.wireguard);
    // Back on the home page: the protocol card now shows the new name and
    // the page is gone.
    expect(find.byType(ProtocolPage), findsNothing);
    expect(find.text('وایرگارد'), findsWidgets);
  });

  testWidgets('a subtile selection (psiphon chain) works the same', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openPage(tester, store);

    await _tapAndAutoPop(
      tester,
      find.byKey(const ValueKey('proto-subtile-psiphonChain')),
    );

    // v4.21 — the SINGLE-KNOB commit (owner: the v4.20 leg/overlay split
    // was reverted, «لطفا به حالت قبل برشگردون»): the subtile IS the
    // protocol; there is no separate overlay state.
    expect(store.selectedProtocol, ProtocolId.psiphonChain);
    expect(store.effectiveProtocol, ProtocolId.psiphonChain);
    expect(find.byType(ProtocolPage), findsNothing);
  });

  testWidgets(
      'v4.21 — the single knob REPLACES the previous selection: a plain '
      'tile after a family member clears the family mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openPage(tester, store);

    await _tapAndAutoPop(
      tester,
      find.byKey(const ValueKey('proto-subtile-psiphonChain')),
    );
    expect(store.selectedProtocol, ProtocolId.psiphonChain);
    expect(store.effectiveProtocol, ProtocolId.psiphonChain);

    // The home card now names the family mode — re-open through it, then
    // pick a plain tile: the plain protocol REPLACES the family mode (the
    // v4.20 "overlay survives a leg change" behavior is gone).
    await tester.tap(find.text('سایفون').first);
    await tester.pump();
    await tester.pumpAndSettle();
    await _tapAndAutoPop(tester, find.byKey(const ValueKey('proto-tile-masque')));
    expect(store.selectedProtocol, ProtocolId.masque);
    expect(store.effectiveProtocol, ProtocolId.masque);
  });

  testWidgets(
      'the mode segments and the scan pills apply INSTANTLY (v4.17: the page '
      'listens to the store — no protocol pick needed first) and stay open',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openPage(tester, store);
    expect(store.connectionMode, ConnectionMode.proxy); // frame default
    expect(store.scanSpeed, 5); // frame default

    await tester.tap(find.text('تونل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.connectionMode, ConnectionMode.tunnel);
    // v4.17 LIVE binding: the tunnel segment is the SELECTED (green) one
    // without any protocol pick.
    final tunnelContainer = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text('تونل'),
        matching: find.byType(AnimatedContainer),
      ).first,
    );
    expect(
      (tunnelContainer.decoration as BoxDecoration).color,
      AethColors.accentConnected,
    );
    // Still open — the page did not pop.
    expect(find.byType(ProtocolPage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proto-pill-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.scanSpeed, 2);
    // The tapped pill turns green instantly too.
    final pill2 = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('proto-pill-2')),
        matching: find.byType(AnimatedContainer),
      ).first,
    );
    expect(
      (pill2.decoration as BoxDecoration).color,
      AethColors.accentConnected,
    );
    expect(find.byType(ProtocolPage), findsOneWidget);
  });

  testWidgets(
      'the v4.17 heading badges: Swap 1 on «پروتکل», Scan 1 on «سرعت اسکن», '
      'Password 1 on «حالت اتصال»', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openPage(tester, store);

    bool badgeLoaded(String asset) => find
        .byWidgetPredicate(
          (w) =>
              w is SvgPicture &&
              w.bytesLoader is SvgAssetLoader &&
              (w.bytesLoader as SvgAssetLoader).assetName == asset,
        )
        .evaluate()
        .isNotEmpty;

    expect(badgeLoaded(AppAssets.iconSwap1), isTrue,
        reason: '«پروتکل» badge = Swap 1.svg (v4.17 #8)');
    expect(badgeLoaded(AppAssets.iconScan1), isTrue,
        reason: '«سرعت اسکن» badge = Scan 1.svg (v4.17 #7)');
    expect(badgeLoaded(AppAssets.iconPassword1), isTrue,
        reason: '«حالت اتصال» badge = Password 1.svg');
  });

  testWidgets(
      'v4.17: the page renders under a Material — no unmaterialed-text '
      'yellow underline (the double yellow lines under every text on the '
      'v4.16 sheet are gone)', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openPage(tester, store);

    // The page content must sit under a Material ancestor (the Scaffold).
    final titleFinder = find.text('انتخاب پروتکل');
    expect(titleFinder, findsOneWidget);
    final context = tester.element(titleFinder);
    expect(Material.maybeOf(context), isNotNull);
  });
}
