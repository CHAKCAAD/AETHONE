import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/features/settings/appearance_page.dart';
import 'package:aethone/features/settings/connection_page.dart';
import 'package:aethone/features/settings/core_page.dart';
import 'package:aethone/features/settings/general_page.dart';
import 'package:aethone/features/settings/psiphon_page.dart';
import 'package:aethone/features/settings/routing_page.dart';
import 'package:aethone/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: avoid_print

/// v1.1.0 settings redesign — renders every redesigned settings page to
/// PNG (visual verification harness, not a golden assertion). Output:
/// /tmp/settings_shots/. Run: flutter test test/zz_settings_redesign_shots_test.dart
class _Engine extends EngineAdapter {
  final StreamController<EngineEvent> c =
      StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => c.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void bind(EngineConfigSource config) {}
}

const _key = Key('shot');

Future<void> _fonts() async {
  for (final f in [
    'Light', 'Regular', 'Medium', 'DemiBold', 'Bold', 'ExtraBold',
  ]) {
    final data = await rootBundle.load('design/fonts/IRANYekanX-$f.ttf');
    await (FontLoader('IRANYekanX')..addFont(Future.value(data))).load();
  }
}

Widget _booth(Widget child, String locale) => MaterialApp(
      locale: Locale(locale),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RepaintBoundary(key: _key, child: child),
    );

Future<void> _save(WidgetTester t, String name) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.runAsync(() async {
    final b = t.renderObject(find.byKey(_key)) as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/settings_shots/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
  print('SAVED $name');
}

void main() {
  Directory('/tmp/settings_shots').createSync(recursive: true);
  final h = double.tryParse(Platform.environment['SHOT_H'] ?? '') ?? 1500;

  testWidgets('settings redesign shots', (t) async {
    t.view.physicalSize = Size(402, h);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    addTearDown(() {
      AethThemeSync.palette = AethPal.night;
      AethThemeSync.light = false;
    });
    final locale = Platform.environment['SHOT_LOCALE'] ?? 'fa';
    for (final light in [false, true]) {
      AethThemeSync.palette = light ? AethPal.light : AethPal.night;
      AethThemeSync.light = light;
      final sfx = '${light ? 'light' : 'night'}_$locale';
      final engine = _Engine();
      final store = ConnectionStore(engine: engine);
      store.setThemeMode(light ? AethThemeMode.light : AethThemeMode.night);
      await t.pumpWidget(_booth(const SizedBox(), locale));
      unawaited(store.connect());
      engine.c.add(const EngineStateChanged(VpnState.connecting));
      await t.pump(const Duration(milliseconds: 50));
      engine.c.add(const EngineStateChanged(VpnState.connected));
      await t.pump(const Duration(milliseconds: 50));
      final pages = <String, Widget>{
        'main': SettingsScreen(store: store),
        'connection': ConnectionSettingsPage(store: store),
        'look': AppearanceSettingsPage(store: store),
        'routing': RoutingSettingsPage(store: store),
        'general': GeneralSettingsPage(store: store),
        'psiphon': PsiphonSettingsPage(store: store),
        'core': CoreSettingsPage(store: store),
      };
      for (final e in pages.entries) {
        await t.pumpWidget(_booth(e.value, locale));
        await t.runAsync(_fonts);
        await _save(t, '${e.key}_$sfx');
        if (e.key == 'main') {
          await t.enterText(
            find.byKey(const ValueKey('settings-search')),
            locale == 'fa' ? 'مسیر' : 'rout',
          );
          await _save(t, 'search_$sfx');
        }
        await t.pumpWidget(const SizedBox());
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
