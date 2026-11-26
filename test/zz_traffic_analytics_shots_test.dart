import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/features/analytics/traffic_analytics_page.dart';
import 'package:aethone/analytics/traffic_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: avoid_print

/// Traffic Analytics — renders the screens to PNG for visual review
/// (/tmp/traffic_shots/). TEST FIXTURE ONLY: the channel below is a mock
/// with hand-written numbers so the layout can be judged; the app itself
/// never ships or shows fixture data (lib/ has none).
class _Engine extends EngineAdapter {
  final StreamController<EngineEvent> c = StreamController<EngineEvent>.broadcast();
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
const _mb = 1024 * 1024;

Future<void> _fonts() async {
  for (final f in ['Light', 'Regular', 'Medium', 'DemiBold', 'Bold', 'ExtraBold']) {
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
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.runAsync(() async {
    final b = t.renderObject(find.byKey(_key)) as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/traffic_shots/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  print('SAVED $name');
}

Map<String, Object?> _fixture(Map<String, dynamic> q) {
  final w = windowFor(TrafficRange.today, now: DateTime(2026, 11, 26, 14, 30));
  final series = [
    for (var h = 0; h < 15; h++)
      {
        't': w.fromMs + h * hourMs,
        'down': [0, 0, 0, 0, 0, 0, 0, 12, 48, 96, 30, 22, 140, 88, 64][h] * _mb,
        'up': [0, 0, 0, 0, 0, 0, 0, 2, 6, 9, 3, 4, 21, 8, 7][h] * _mb,
        'unmeasured': 0,
      },
  ];
  final app = q['app'] as String?;
  if (app != null) {
    return {
      'series': series,
      'apps': [
        {'app': app, 'up': 35 * _mb, 'down': 440 * _mb, 'flows': 212, 'routes': 2},
      ],
      'routes': [
        {'profile': 'psiphonChain', 'route': 'warp', 'up': 24 * _mb, 'down': 320 * _mb, 'flows': 150, 'apps': 1},
        {'profile': 'psiphonChain', 'route': 'psiphon', 'up': 11 * _mb, 'down': 120 * _mb, 'flows': 62, 'apps': 1},
      ],
      'up': 35 * _mb, 'down': 440 * _mb, 'unmeasuredUp': 0, 'unmeasuredDown': 0, 'flows': 212,
      'peakDown': 3 * _mb, 'peakUp': 400 * 1024, 'activeS': 1900, 'firstRecord': w.fromMs - 40 * dayMs,
      'domains': [
        {'domain': 'cdn4.telegram.org', 'up': 5 * _mb, 'down': 260 * _mb},
        {'domain': 'web.telegram.org', 'up': 20 * _mb, 'down': 120 * _mb},
      ],
    };
  }
  return {
    'series': series,
    'apps': [
      {'app': 'org.telegram.messenger', 'up': 35 * _mb, 'down': 440 * _mb, 'flows': 212, 'routes': 2},
      {'app': 'com.google.android.youtube', 'up': 9 * _mb, 'down': 300 * _mb, 'flows': 80, 'routes': 1},
      {'app': 'com.instagram.android', 'up': 14 * _mb, 'down': 120 * _mb, 'flows': 96, 'routes': 1},
      {'app': 'com.whatsapp', 'up': 6 * _mb, 'down': 40 * _mb, 'flows': 40, 'routes': 1},
      {'app': TrafficKeys.unattributed, 'up': 1 * _mb, 'down': 3 * _mb, 'flows': 12, 'routes': 2},
    ],
    'routes': [
      {'profile': 'psiphonChain', 'route': 'warp', 'up': 50 * _mb, 'down': 760 * _mb, 'flows': 330, 'apps': 4},
      {'profile': 'psiphonChain', 'route': 'psiphon', 'up': 15 * _mb, 'down': 143 * _mb, 'flows': 110, 'apps': 2},
    ],
    'up': 65 * _mb, 'down': 903 * _mb, 'unmeasuredUp': 1 * _mb, 'unmeasuredDown': 6 * _mb, 'flows': 440,
    'peakDown': 5 * _mb, 'peakUp': 900 * 1024, 'activeS': 5400, 'firstRecord': w.fromMs - 40 * dayMs,
    'compare': {'up': 50 * _mb, 'down': 700 * _mb, 'series': <Object>[], 'apps': <Object>[], 'routes': <Object>[], 'firstRecord': w.fromMs - 40 * dayMs},
    'appChanges': [
      {'app': 'com.google.android.youtube', 'current': 309 * _mb, 'previous': 120 * _mb},
      {'app': 'org.telegram.messenger', 'current': 475 * _mb, 'previous': 390 * _mb},
    ],
  };
}

void main() {
  Directory('/tmp/traffic_shots').createSync(recursive: true);

  testWidgets('traffic analytics shots', (t) async {
    t.view.physicalSize = const Size(402, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    addTearDown(() {
      AethThemeSync.palette = AethPal.night;
      AethThemeSync.light = false;
    });
    var tick = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('aethone/engine'), (call) async {
      switch (call.method) {
        case 'trafficQuery':
          final q = jsonDecode((call.arguments as Map)['query'] as String) as Map<String, dynamic>;
          return jsonEncode(_fixture(q));
        case 'trafficLive':
          tick++;
          return {
            'running': true,
            'enabled': true,
            'profile': 'psiphonChain',
            'routes': ['psiphon', 'warp'],
            'down': [for (var i = 0; i < 60; i++) ((1 + (i % 9)) * 180 * 1024 + tick)],
            'up': [for (var i = 0; i < 60; i++) ((1 + (i % 5)) * 30 * 1024)],
            'routeRates': {
              'warp': [40000, 900000],
              'psiphon': [9000, 200000],
            },
            'appRates': {
              'org.telegram.messenger': [30000, 700000],
              'com.google.android.youtube': [10000, 400000],
            },
            'openFlows': 37,
          };
        case 'trafficLabels':
          return {
            'org.telegram.messenger': 'Telegram',
            'com.google.android.youtube': 'YouTube',
            'com.instagram.android': 'Instagram',
            'com.whatsapp': 'WhatsApp',
          };
        case 'trafficConfig':
          return {'enabled': true, 'domains': true, 'retentionDays': 90};
        default:
          return null;
      }
    });
    final locale = Platform.environment['SHOT_LOCALE'] ?? 'fa';
    for (final light in [false, true]) {
      AethThemeSync.palette = light ? AethPal.light : AethPal.night;
      AethThemeSync.light = light;
      final sfx = '${light ? 'light' : 'night'}_$locale';
      final store = ConnectionStore(engine: _Engine());
      store.setThemeMode(light ? AethThemeMode.light : AethThemeMode.night);
      final pages = <String, Widget>{
        'dashboard': TrafficAnalyticsPage(store: store),
        'app_telegram': TrafficAppDetailPage(store: store, app: 'org.telegram.messenger'),
        'history': TrafficHistoryPage(store: store),
      };
      for (final e in pages.entries) {
        await t.pumpWidget(_booth(e.value, locale));
        await t.runAsync(_fonts);
        await _save(t, '${e.key}_$sfx');
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 2));
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
