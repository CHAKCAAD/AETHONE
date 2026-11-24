/// v6 — the login visual-capture harness («صفحه ورود»): renders each of
/// the five login steps to PNG so the sheet/notch/indicator geometry, the
/// flag circles, the look previews and the nav pills can be verified
/// against the committed frames (ورود1..ورود5). Local-only tooling (zz_
/// prefix; it only writes /tmp).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/onboarding/login_flow.dart';

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

void main() {
  Directory('/tmp/ui_shots').createSync(recursive: true);

  testWidgets('render the five login steps to PNG (v6)', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: EngineNotWiredAdapter());
    store.animationStyle = MotionStyle.off;
    // ورود4's own state: the look step ships the GLOW button picked (the
    // fresh-install default the restore applies — the bare test store
    // starts at look one).
    store.homeLook = HomeLook.two;
    await tester.pumpWidget(_booth(LoginFlow(store: store)));
    await tester.runAsync(_loadRealFonts);
    await tester.pumpAndSettle();

    await _save(tester, 'login_step1');
    for (var step = 2; step <= 5; step++) {
      await tester.tap(find.byKey(const ValueKey('login-next')));
      await tester.pumpAndSettle();
      await _save(tester, 'login_step$step');
    }
  });
}
