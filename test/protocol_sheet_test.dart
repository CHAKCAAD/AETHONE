/// v4.16 — regression tests for the REAL protocol-selection sheet
/// (pixel-faithful to «صفحه شناور انتخاب پروتکل صفحه اصلی.jpg»).
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

class ScriptedEngine implements EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => _controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
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
Future<void> _openSheet(WidgetTester tester, ConnectionStore store) async {
  await tester.pumpWidget(_booth(HomeScreen(store: store)));
  await tester.pumpAndSettle();
  // The home protocol card shows the selected protocol's own name (masque
  // default) — that card IS the sheet's entry point.
  await tester.tap(find.text('ماسک').first);
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
      'the sheet opens from the home protocol card and shows all 12 '
      'protocols + the three sections (v4.16 frame layout)', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openSheet(tester, store);

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
    // reference frame): handle, segments, pills, cards.
    final handle = tester.getRect(find.byKey(const ValueKey('proto-handle')));
    expect(handle.top, closeTo(AethGeometry.protoHandleTop - 15, 2));
    final bar = tester.getRect(
      find.byKey(const ValueKey('proto-handle-bar')),
    );
    expect(bar.width, closeTo(AethGeometry.protoHandleW, 2));
    expect(bar.height, closeTo(AethGeometry.protoHandleH, 2));
    expect(bar.top, closeTo(AethGeometry.protoHandleTop, 2));

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

    final p5 = tester.getRect(find.byKey(const ValueKey('proto-pill-5')));
    expect(p5.top, closeTo(AethGeometry.protoPillTop, 2));
    // The pills row is CENTERED (frame x33..367) — pill 5 right edge ≈367.
    expect(p5.right, closeTo(367, 3));

    // The frame ships the DEFAULT (masque) selected → its tile is green
    // (the design's وایرگارد is just the mock's state; the app's default is
    // Aether's real default = masque — report table 11).
    final masqueContainer = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('proto-tile-masque')),
        matching: find.byType(AnimatedContainer),
      ).first,
    );
    expect(
      (masqueContainer.decoration as BoxDecoration).color,
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
    await _openSheet(tester, store);

    await _tapAndAutoPop(tester, find.byKey(const ValueKey('proto-tile-wireguard')));

    expect(store.selectedProtocol, ProtocolId.wireguard);
    // Back on the home page: the protocol card now shows the new name and
    // the sheet is gone.
    expect(find.byType(ProtocolSheetPage), findsNothing);
    expect(find.text('وایرگارد'), findsWidgets);
  });

  testWidgets('a subtile selection (psiphon chain) works the same', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openSheet(tester, store);

    await _tapAndAutoPop(
      tester,
      find.byKey(const ValueKey('proto-subtile-psiphonChain')),
    );

    expect(store.selectedProtocol, ProtocolId.psiphonChain);
    expect(find.byType(ProtocolSheetPage), findsNothing);
  });

  testWidgets(
      'the mode segments and the scan pills update the store WITHOUT '
      'closing (v4.16: only PROTOCOL selection auto-returns)', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openSheet(tester, store);
    expect(store.connectionMode, ConnectionMode.proxy); // frame default
    expect(store.scanSpeed, 5); // frame default

    await tester.tap(find.text('تونل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.connectionMode, ConnectionMode.tunnel);
    // Still open — the sheet did not pop.
    expect(find.byType(ProtocolSheetPage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proto-pill-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.scanSpeed, 2);
    expect(find.byType(ProtocolSheetPage), findsOneWidget);
  });

  testWidgets(
      'the ⓘ opens the family descriptions (3 blocks, verbatim §11) and '
      'the × closes it', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openSheet(tester, store);

    // The psiphon card ⓘ sits at the card's top-left (11,9 inset + 6).
    final card = tester.getRect(
      find.byKey(const ValueKey('proto-card-psiphon')),
    );
    await tester.tapAt(Offset(card.left + 17, card.top + 15));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    // The 3 family descriptions (owner §11, verbatim).
    expect(
      find.textContaining('اتصال مستقیماً از طریق Psiphon'),
      findsOneWidget,
    );
    expect(
      find.textContaining('ابتدا تونل Aether برقرار می‌شود'),
      findsOneWidget,
    );
    expect(find.textContaining('ابتدا اتصال از طریق Psiphon'), findsOneWidget);

    // × closes (the button is Ø22 centered at x201, y206..228).
    await tester.tapAt(
      const Offset(201, AethGeometry.protoDescCloseTop + 11),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.textContaining('اتصال مستقیماً از طریق Psiphon'), findsNothing);
    // The sheet itself is still there.
    expect(find.byType(ProtocolSheetPage), findsOneWidget);
  });

  testWidgets('a single-protocol ⓘ shows one description block', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await _openSheet(tester, store);

    final tile = tester.getRect(
      find.byKey(const ValueKey('proto-tile-masque')),
    );
    await tester.tapAt(Offset(tile.left + 17, tile.top + 15));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.textContaining('اتصال رمزگذاری‌شده'), findsOneWidget);
    expect(find.textContaining('ابتدا تونل Aether'), findsNothing);
  });
}
