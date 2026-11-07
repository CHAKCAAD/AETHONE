/// v4.33 — onboarding visual-capture harness (the owner's round-9 reports
/// were all about these four pages): renders each wizard step to PNG so the
/// heading sizes, the CTA restyle and the look previews can be verified
/// against the committed frames. Local-only tooling (zz_ prefix: excluded
/// from the CI's --exclude-tags? no — it runs, but it only writes /tmp).
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
import 'package:aethone/features/onboarding/onboarding_flow.dart';

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

  testWidgets('render the four wizard steps to PNG (v4.33)', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: EngineNotWiredAdapter());
    store.animationStyle = MotionStyle.off;
    await tester.pumpWidget(_booth(OnboardingFlow(store: store)));
    await tester.runAsync(_loadRealFonts);
    await tester.pumpAndSettle();

    await _save(tester, 'ob_step1');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('ob-cta')));
      await tester.pumpAndSettle();
    }
    await _save(tester, 'ob_step3');
    await tester.tap(find.byKey(const ValueKey('ob-cta')));
    await tester.pumpAndSettle();
    // v4.40 — the AUTO/SMART option cards are gone (owner round 15); the
    // step-4 frame is the mode segments + the scan pills.
    await tester.ensureVisible(find.byKey(const ValueKey('ob-scan-2')));
    await _save(tester, 'ob_step4_top');
  });
}
