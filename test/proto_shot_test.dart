/// Visual-capture harness for the v4.16 protocol sheet (the ui_screenshot_
/// pattern: loads the REAL fonts, disables the debug banner — it flips to
/// the top-left under RTL and reads as stray artwork — and saves PNGs to
/// /tmp/ui_shots for pixel QA against the design frame).
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
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
  @override
  void bind(EngineConfigSource config) {} // scripted — config never read
}

const _shotKey = ValueKey('proto-shot-boundary');

/// Loads the REAL IRANYekanX fonts into the test engine (harness artifact —
/// flutter_test otherwise falls back to Ahem tofu; devices unaffected).
Future<void> _loadRealFonts() async {
  const weights = [
    ('design/fonts/IRANYekanX-Light.ttf', 300),
    ('design/fonts/IRANYekanX-Regular.ttf', 400),
    ('design/fonts/IRANYekanX-Medium.ttf', 500),
    ('design/fonts/IRANYekanX-DemiBold.ttf', 600),
    ('design/fonts/IRANYekanX-Bold.ttf', 700),
    ('design/fonts/IRANYekanX-ExtraBold.ttf', 800),
  ];
  for (final (path, _) in weights) {
    final data = await rootBundle.load(path);
    final loader = FontLoader('IRANYekanX')..addFont(Future.value(data));
    await loader.load();
  }
}

Widget _shot(Widget child) => RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa'),
        supportedLocales: AethoneApp.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    );

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject(find.byKey(_shotKey)) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/ui_shots/$name.png')
        .writeAsBytes(byteData!.buffer.asUint8List());
  });
  print('SAVED /tmp/ui_shots/$name.png');
}

void main() {
  Directory('/tmp/ui_shots').createSync(recursive: true);

  testWidgets('render the protocol sheet + the descriptions popup', (
    tester,
  ) async {
    await _loadRealFonts();
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: ScriptedEngine());
    await tester.pumpWidget(_shot(HomeScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ماسک').first);
    await tester.pump();
    await tester.pumpAndSettle();
    await _capture(tester, 'proto_sheet');
    // open the psiphon family descriptions
    final card = tester.getRect(
      find.byKey(const ValueKey('proto-card-psiphon')),
    );
    await tester.tapAt(Offset(card.left + 17, card.top + 15));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, 'proto_desc');

    // close it and open a single-protocol desc (میم tile)
    await tester.tapAt(
      const Offset(201, AethGeometry.protoDescCloseTop + 15),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final mim = tester.getRect(find.byKey(const ValueKey('proto-tile-mim')));
    await tester.tapAt(Offset(mim.left + 17, mim.top + 15));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, 'proto_desc_single');
    expect(find.byType(ProtocolPage), findsOneWidget);
  });
}
