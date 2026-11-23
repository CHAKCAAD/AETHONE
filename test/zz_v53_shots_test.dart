// Visual QA shots for the v5.3 round (the owner's dark-mode + stillness
// decrees) — NOT a regression test: dumps PNGs into /tmp/ui_shots for
// human-eye inspection.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/features/home/home_screen.dart';

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
  @override
  void bind(EngineConfigSource config) {}
}

Widget _booth(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RepaintBoundary(key: const Key('shot'), child: child),
    );

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject(find.byKey(const Key('shot'))) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('/tmp/ui_shots').create(recursive: true);
    await File('/tmp/ui_shots/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('the v5.3 state matrix — looks × modes × connection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final light in [false, true]) {
      AethThemeSync.palette = light ? AethPal.light : AethPal.night;
      AethThemeSync.light = light;
      final tag = light ? 'light' : 'night';

      // ---- LOOK 2, DISCONNECTED ----
      final engine = ScriptedEngine();
      final store = ConnectionStore(engine: engine)..setHomeLook(HomeLook.two);
      await tester.pumpWidget(_booth(HomeScreen(store: store)));
      await _settleImages(tester);
      await _shot(tester, 'v53_look2_${tag}_disconnected');

      // ---- LOOK 2, CONNECTED (walk → up, with live stats) ----
      await store.connect();
      engine.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump(const Duration(milliseconds: 300));
      engine.emit(const EngineStateChanged(VpnState.connected));
      engine.emit(const EngineStatsUpdated(
        pingMs: 146,
        downBytes: 148480 * 1024,
        upBytes: 46080 * 1024,
        exitCountryCode: 'ir',
      ));
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The roulette's landing swaps NEW flag Image widgets in — give the
      // real decode pipeline its window before the shot.
      await _settleImages(tester);
      await _shot(tester, 'v53_look2_${tag}_connected');

      // ---- LOOK 1, CONNECTED (the white FAB glyph, the KB cards) ----
      final engine1 = ScriptedEngine();
      final store1 = ConnectionStore(engine: engine1);
      await tester.pumpWidget(_booth(HomeScreen(store: store1)));
      await _settleImages(tester);
      await store1.connect();
      engine1.emit(const EngineStateChanged(VpnState.connecting));
      await tester.pump(const Duration(milliseconds: 300));
      engine1.emit(const EngineStateChanged(VpnState.connected));
      engine1.emit(const EngineStatsUpdated(
        pingMs: 146,
        downBytes: 148480 * 1024,
        upBytes: 46080 * 1024,
        exitCountryCode: 'ir',
      ));
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _settleImages(tester);
      await _shot(tester, 'v53_look1_${tag}_connected');
    }
  });
}
