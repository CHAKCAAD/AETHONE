/// Traffic Analytics — the Flutter side of the native contract
/// (docs/traffic-analytics.md §5). Every call goes to the Android meter
/// (TrafficMeter.kt / TrafficStore.kt) over the app's engine channel; on a
/// platform without it (desktop, tests) every read answers «unavailable»,
/// never a made-up figure.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'traffic_models.dart';

class TrafficClient {
  TrafficClient({MethodChannel? channel}) : _ch = channel ?? const MethodChannel('aethone/engine');

  final MethodChannel _ch;

  static final TrafficClient instance = TrafficClient();

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<TrafficSummary?> query(
    RangeWindow w, {
    String? profile,
    String? app,
    String? route,
    bool compare = false,
    bool appSeries = false,
  }) async {
    if (!supported) return null;
    final q = w.toQuery(profile: profile, app: app, route: route);
    if (compare && w.previous != null) q['compareWith'] = w.previous!.toQuery();
    if (appSeries) q['appSeries'] = true;
    final raw = await _ch.invokeMethod<String>('trafficQuery', {'query': jsonEncode(q)});
    if (raw == null) return null;
    return TrafficSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<LiveTraffic> live() async {
    if (!supported) return LiveTraffic.stopped;
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('trafficLive');
    return m == null ? LiveTraffic.stopped : LiveTraffic.fromMap(m);
  }

  Future<Map<String, Object?>> config({bool? enabled, bool? domains, int? retentionDays}) async {
    if (!supported) return const {'enabled': false};
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('trafficConfig', {
      'enabled': ?enabled,
      'domains': ?domains,
      'retentionDays': ?retentionDays,
    });
    return {for (final e in (m ?? const {}).entries) e.key as String: e.value};
  }

  Future<void> clear() async {
    if (!supported) return;
    await _ch.invokeMethod<Object?>('trafficClear');
  }

  /// Opens the system «save as» picker and writes the export there.
  Future<bool> export(String format) async {
    if (!supported) return false;
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('trafficExport', {'format': format});
    return m?['ok'] == true;
  }

  final Map<String, String> _labels = {};
  final Map<String, Future<Uint8List?>> _icons = {};

  String? labelOf(String app) => _labels[app];

  /// App labels for packages (installed apps only; others keep their id).
  Future<void> resolveLabels(Iterable<String> apps) async {
    if (!supported) return;
    final missing = [for (final a in apps) if (!TrafficKeys.isSpecial(a) && !_labels.containsKey(a)) a];
    if (missing.isEmpty) return;
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('trafficLabels', {'apps': missing});
    m?.forEach((k, v) => _labels[k as String] = v as String);
    for (final a in missing) {
      _labels.putIfAbsent(a, () => a);
    }
  }

  /// The real launcher icon (the existing per-app tunneling icon call).
  Future<Uint8List?> iconOf(String app) {
    if (!supported || TrafficKeys.isSpecial(app) || app.startsWith('uid:')) return Future.value(null);
    return _icons.putIfAbsent(
      app,
      () => _ch.invokeMethod<Uint8List>('appIcon', {'package': app}).catchError((_) => null),
    );
  }
}
