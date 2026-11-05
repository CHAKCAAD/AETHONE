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
import 'package:aethone/connection/speed_test.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/speedtest/speed_test_page.dart';

// ignore_for_file: avoid_print

const _shotKey = Key('ui-shot');

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
      home: RepaintBoundary(key: _shotKey, child: child),
    );

Future<void> _save(WidgetTester tester, String name) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

class ScriptedTransport implements EngineAdapter {
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

class _ManualEngine extends SpeedTestEngine {
  @override
  Future<void> run({int? proxyPort}) async {}

  void emit(SpeedTestSnapshot snap) => onUpdate?.call(snap);
}

void main() {
  Directory('/tmp/ui_shots').createSync(recursive: true);

  testWidgets('render the speed test page states to PNG', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    // The committed design frames carry a 24px status-bar zone above the
    // top bar (the tiles sit at y36 in every frame — on device SafeArea
    // provides it); simulate it so the shots line up with the frames.
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);

    final transport = ScriptedTransport();
    final store = ConnectionStore(engine: transport);
    final engine = _ManualEngine();
    await tester.pumpWidget(_booth(SpeedTestPage(
      store: store,
      style: MotionStyle.standard,
      engine: engine,
    )));
    await tester.runAsync(_loadRealFonts);
    // The page is entered while CONNECTED (the home entry shows then) —
    // walk the store legally so the patterns render the GREEN variant.
    await store.connect();
    transport.emit(const EngineStateChanged(VpnState.connecting));
    await tester.pump(const Duration(milliseconds: 100));
    transport.emit(const EngineStateChanged(VpnState.connected));
    await tester.pump(const Duration(milliseconds: 100));

    // idle — «قبل از شروع»
    await _save(tester, 'speed_idle');

    // running — the «در حال تست سرعت» frame's own values
    await tester.tap(find.byKey(const ValueKey('speed-start')));
    await tester.pump();
    engine.emit(const SpeedTestSnapshot(
      phase: SpeedTestPhase.download,
      pingMs: 345,
      jitterMs: 24,
      liveMbps: 50.4,
      downBytes: 145 * 1024 * 1024,
      downMbps: 50.4,
    ));
    await _save(tester, 'speed_running');

    // done — the «اتمام تست سرعت» frame's own values
    engine.emit(const SpeedTestSnapshot(
      phase: null,
      pingMs: 345,
      jitterMs: 24,
      downBytes: 145 * 1024 * 1024,
      upBytes: 45 * 1024 * 1024,
      downMbps: 23.4,
      upMbps: 5.6,
    ));
    await _save(tester, 'speed_done');
  });
}
