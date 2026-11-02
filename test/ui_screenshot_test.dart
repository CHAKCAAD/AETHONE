import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/features/home/home_screen.dart';

// ignore_for_file: avoid_print

/// Renders the home screen to PNG files (NOT a golden assertion — a visual
/// verification harness for the pixel-fidelity fixes). Output goes to
/// /tmp/ui_shots/. Run: flutter test test/ui_screenshot_test.dart
class ScriptedEngine implements EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  void emit(EngineEvent e) => _controller.add(e);

  @override
  Stream<EngineEvent> get events => _controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
}

const _shotKey = Key('ui-shot');

/// Loads the REAL IRANYekanX fonts into the test engine so text renders
/// with true glyphs (otherwise flutter_test falls back to Ahem tofu —
/// a test-harness artifact, devices are unaffected).
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

Widget _booth(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RepaintBoundary(
        key: _shotKey,
        child: child,
      ),
    );

Future<void> _save(WidgetTester tester, String name) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Real-async window: lets pending asset decodes (pattern/flag PNGs)
  // deliver their frames — fake-async alone never completes them.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  print('CAPTURE $name');
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

  testWidgets('render disconnected + connected home screens to PNG',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.runAsync(_loadRealFonts);
    await _save(tester, 'home_disconnected');

    print('CONNECTING...');
    await store.connect();
    engine.emit(const EngineStateChanged(VpnState.connecting));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    print('EMIT CONNECTED');
    engine.emit(const EngineStateChanged(VpnState.connected));
    engine.emit(const EngineStatsUpdated(
      pingMs: 146,
      downBytes: 145 * 1024 * 1024,
      upBytes: 425 * 1024 * 1024,
      exitCountryCode: 'ir',
    ));
    await _save(tester, 'home_connected');
    expect(store.isConnected, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
