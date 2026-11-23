// Visual QA shots for the flutterfx round 2 — NOT a regression test:
// dumps three PNGs into /tmp/ui_shots for human-eye inspection.
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
import 'package:aethone/core/app_assets.dart' show ProtocolId;
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

void main() {
  testWidgets('three visual QA shots', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // ---- 1. LOOK 1 CONNECTING — the STATIC hero (v5.3: the spark march
    // is retired; the walk holds the 0° pose), no halo ----
    final engine = ScriptedEngine();
    final store = ConnectionStore(engine: engine);
    await tester.pumpWidget(_booth(HomeScreen(store: store)));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 800))); // let assets decode
    await tester.pumpAndSettle();
    await store.connect();
    engine.emit(const EngineStateChanged(VpnState.connecting));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _shot(tester, 'round2_look1_connecting_static');

    // Land connected (the −58° pose) for the after-shot.
    engine.emit(const EngineStateChanged(VpnState.connected));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _shot(tester, 'round2_look1_connected_landed');

    // ---- 2. THE WHEEL — psiphon, dragged one pitch: the shove at rest ----
    final engine2 = ScriptedEngine();
    final store2 = ConnectionStore(engine: engine2);
    store2.selectedProtocol = ProtocolId.psiphonChain;
    await tester.pumpWidget(_booth(HomeScreen(store: store2)));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 800))); // let assets decode
    await tester.pumpAndSettle();
    final wheelCenter = tester.getCenter(find.byType(PageView).first);
    final drag = await tester.startGesture(wheelCenter);
    for (var i = 0; i < 3; i++) {
      await drag.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await drag.moveBy(const Offset(-6, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('اتریش'), findsOneWidget); // the drag committed
    await _shot(tester, 'round2_wheel_shove_resting');

    // ---- 3. LOOK 2 — the connect button's ripple burst mid-flight ----
    final engine3 = ScriptedEngine();
    final store3 = ConnectionStore(engine: engine3);
    store3.setHomeLook(HomeLook.two);
    await tester.pumpWidget(_booth(HomeScreen(store: store3)));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 800))); // let assets decode
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HomeScreen), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 140));
    await _shot(tester, 'round2_look2_ripple_burst');
    for (var i = 0; i < 40 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
