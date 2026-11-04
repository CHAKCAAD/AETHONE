import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/features/settings/appearance_page.dart';

Widget booth(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RepaintBoundary(key: const Key('shot'), child: child),
    );

void main() {
  testWidgets('render the appearance page (v4.25)', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = ConnectionStore(engine: EngineNotWiredAdapter());
    await tester.pumpWidget(booth(AppearanceSettingsPage(store: store)));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Scroll to the animation section (it sits below the home-look card).
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          tester.renderObject(find.byKey(const Key('shot')))
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/ui_shots/appearance_v425.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
    // ignore: avoid_print
    print('SAVED appearance_v425.png');
    expect(find.text('حداقلی'), findsOneWidget);
    expect(find.text('خاموش کردن همهٔ انیمیشن‌ها'), findsOneWidget);
  });
}
