import 'package:aethone/analytics/traffic_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('picks the unit by 1024 steps', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(320 * 1024 * 1024), '320 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
    test('null is «—», never zero', () {
      expect(formatBytes(null), '—');
      expect(formatRate(null), '—');
      expect(formatRate(2048), '2.0 KB/s');
    });
    test('negative input clamps to 0 B', () => expect(formatBytes(-5), '0 B'));
  });

  group('speeds', () {
    test('average uses active seconds only', () {
      expect(averageSpeed(1000, 10), 100);
      expect(averageSpeed(1000, 0), isNull);
    });
  });

  group('shares', () {
    test('route shares sum to 1', () {
      final s = shares([300, 100]);
      expect(s, [0.75, 0.25]);
    });
    test('nothing → no donut', () => expect(shares([0, 0]), isEmpty));
  });

  group('percentChange', () {
    test('up and down', () {
      expect(percentChange(150, 100), 50);
      expect(percentChange(50, 100), -50);
    });
    test('no previous figure → unknown, never ±100 %', () {
      expect(percentChange(100, null), isNull);
      expect(percentChange(100, 0), isNull);
    });
    test('comparable only when the previous window is fully recorded', () {
      final w = windowFor(TrafficRange.today, now: DateTime(2026, 11, 26, 14));
      final prev = w.previous!;
      expect(TrafficSummary.comparable(prev, null), isFalse);
      expect(TrafficSummary.comparable(prev, prev.fromMs + hourMs), isFalse);
      expect(TrafficSummary.comparable(prev, prev.fromMs), isTrue);
    });
  });

  group('windows', () {
    final now = DateTime(2026, 11, 26, 14, 24);
    test('today: local midnight to midnight, hourly, vs yesterday', () {
      final w = windowFor(TrafficRange.today, now: now);
      expect(w.from, DateTime(2026, 11, 26));
      expect(w.to, DateTime(2026, 11, 27));
      expect(w.bucketMs, hourMs);
      expect(w.previous!.from, DateTime(2026, 11, 25));
    });
    test('last 24 h ends at the end of the current hour', () {
      final w = windowFor(TrafficRange.last24h, now: now);
      expect(w.to, DateTime(2026, 11, 26, 15));
      expect(w.length, const Duration(hours: 24));
    });
    test('7 / 30 days are daily', () {
      expect(windowFor(TrafficRange.last7d, now: now).bucketMs, dayMs);
      expect(windowFor(TrafficRange.last30d, now: now).length.inDays, 30);
    });
    test('this month vs last month', () {
      final w = windowFor(TrafficRange.thisMonth, now: now);
      expect(w.from, DateTime(2026, 11));
      expect(w.to, DateTime(2026, 12));
      expect(w.previous!.from, DateTime(2026, 10));
      final l = windowFor(TrafficRange.lastMonth, now: now);
      expect(l.from, DateTime(2026, 10));
      expect(l.to, DateTime(2026, 11));
    });
    test('custom ≤ 48 h is hourly, longer daily', () {
      expect(windowFor(TrafficRange.custom, now: now, customFrom: now, customTo: now).bucketMs, hourMs);
      expect(
        windowFor(TrafficRange.custom, now: now, customFrom: DateTime(2026, 11, 1), customTo: now).bucketMs,
        dayMs,
      );
    });
    test('bucket starts cover the window exactly (24 hourly buckets in a day)', () {
      final w = windowFor(TrafficRange.today, now: now);
      final b = w.bucketStarts(0);
      expect(b.length, 24);
      expect(b.first, w.fromMs);
    });
  });

  group('series', () {
    final w = RangeWindow(DateTime.utc(2026, 11, 26), DateTime.utc(2026, 11, 27), hourMs);
    test('missing buckets inside recorded history are zero, the future is not drawn', () {
      final t0 = w.fromMs;
      final s = fillSeries(w, [TrafficPoint(t0 + 2 * hourMs, 10, 20)],
          tzOffsetMs: 0, firstRecord: t0, now: DateTime.fromMillisecondsSinceEpoch(t0 + 5 * hourMs + 1));
      expect(s.length, 6);
      expect(s[2].down, 20);
      expect(s[0].total, 0);
    });
    test('buckets before the first record are dropped, not zero', () {
      final t0 = w.fromMs;
      final s = fillSeries(w, const [],
          tzOffsetMs: 0, firstRecord: t0 + 3 * hourMs, now: DateTime.fromMillisecondsSinceEpoch(t0 + 5 * hourMs + 1));
      expect(s.first.t, t0 + 3 * hourMs);
    });
    test('downsampling sums bytes (a spike keeps its volume)', () {
      final pts = [for (var i = 0; i < 100; i++) TrafficPoint(i, 1, i == 50 ? 1000 : 0)];
      final d = downsample(pts, 10);
      expect(d.length, 10);
      expect(d.fold<int>(0, (a, p) => a + p.down), 1000);
      expect(d.fold<int>(0, (a, p) => a + p.up), 100);
    });
  });

  group('store payload', () {
    final json = {
      'series': [
        {'t': 0, 'up': 10, 'down': 90, 'unmeasured': 5},
      ],
      'apps': [
        {'app': 'org.telegram.messenger', 'up': 24, 'down': 320, 'flows': 7, 'routes': 2},
        {'app': TrafficKeys.unattributed, 'up': 1, 'down': 9, 'flows': 1, 'routes': 1},
      ],
      'routes': [
        {'profile': 'psiphonChain', 'route': 'warp', 'up': 15, 'down': 200, 'flows': 5, 'apps': 1},
        {'profile': 'psiphonChain', 'route': 'psiphon', 'up': 10, 'down': 129, 'flows': 3, 'apps': 1},
      ],
      'up': 25,
      'down': 329,
      'unmeasuredUp': 3,
      'unmeasuredDown': 7,
      'flows': 8,
      'peakDown': 5000,
      'peakUp': 400,
      'activeS': 10,
      'firstRecord': 0,
      'appSeries': {
        'org.telegram.messenger': {'0': 344},
      },
    };
    final s = TrafficSummary.fromJson(json);
    test('apps and routes reconcile: no double counting across hops', () {
      final appsTotal = s.apps.fold<int>(0, (a, x) => a + x.total);
      final routesTotal = s.routes.fold<int>(0, (a, x) => a + x.total);
      expect(appsTotal, s.total);
      expect(routesTotal, s.total);
    });
    test('unattributed and unmeasured are kept apart from apps', () {
      expect(s.unattributed, 10);
      expect(s.unmeasured, 10);
      expect(s.apps.any((a) => a.app == TrafficKeys.unmeasured), isFalse);
    });
    test('average = total / active seconds', () => expect(s.average, 35.4));
    test('app series parse', () => expect(s.appSeries['org.telegram.messenger']![0], 344));
    test('no history → not comparable', () {
      final e = TrafficSummary.fromJson({'firstRecord': null});
      expect(e.hasHistory, isFalse);
      expect(e.isEmpty, isTrue);
    });
  });

  group('live', () {
    test('parses rates and the newest sample', () {
      final l = LiveTraffic.fromMap({
        'running': true,
        'enabled': true,
        'profile': 'masque',
        'routes': ['masque'],
        'down': [1, 2, 3],
        'up': [4, 5, 6],
        'routeRates': {
          'masque': [10, 20],
        },
        'appRates': {
          'org.telegram.messenger': [1, 2],
        },
        'openFlows': 4,
      });
      expect(l.downNow, 3);
      expect(l.upNow, 6);
      expect(l.routeRates['masque'], (10, 20));
      expect(l.openFlows, 4);
    });
    test('stopped is not zero speed: running=false', () {
      expect(LiveTraffic.fromMap({'running': false}).running, isFalse);
    });
  });
}
