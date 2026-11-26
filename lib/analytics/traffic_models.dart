/// Traffic Analytics — pure models and math (no Flutter, no channel), so
/// every number the dashboard shows is unit-tested
/// (test/traffic_analytics_test.dart). The data itself always comes from the
/// native meter (docs/traffic-analytics.md); nothing here invents a value:
/// a missing figure stays null and the UI says «not measured».
library;

/// Keys the native store uses for flows it could not attribute.
abstract final class TrafficKeys {
  /// A TCP flow the platform could not name an owner for (Android < 10,
  /// a socket gone before the lookup, a system flow).
  static const unattributed = '~unattributed';

  /// Bytes the engine moved that no per-flow meter carried (UDP, DNS, the
  /// tail of a session cut by a hard stop).
  static const unmeasured = '~unmeasured';

  static bool isSpecial(String app) => app.startsWith('~');
}

const int hourMs = 3600000;
const int dayMs = 86400000;

/// B / KB / MB / GB / TB with 1024 steps (what Android's own data-usage
/// screen uses) and at most 3 significant digits after the first.
String formatBytes(num? bytes, {int decimals = 1}) {
  if (bytes == null) return '—';
  var v = bytes.toDouble();
  if (v < 0) v = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  if (i == 0) return '${v.round()} B';
  final d = v >= 100 ? 0 : decimals;
  return '${v.toStringAsFixed(d)} ${units[i]}';
}

/// Bytes per second → a rate string (B/s … GB/s).
String formatRate(num? bytesPerSecond) {
  if (bytesPerSecond == null) return '—';
  return '${formatBytes(bytesPerSecond)}/s';
}

/// The range presets of the dashboard (§3.C) + a custom range.
enum TrafficRange { today, last24h, last7d, last30d, thisMonth, lastMonth, custom }

/// A concrete [from, to) window with the bucket size its charts use and the
/// window it is compared against (§7).
class RangeWindow {
  const RangeWindow(this.from, this.to, this.bucketMs, {this.previous});

  final DateTime from;
  final DateTime to;
  final int bucketMs;
  final RangeWindow? previous;

  int get fromMs => from.millisecondsSinceEpoch;
  int get toMs => to.millisecondsSinceEpoch;
  Duration get length => to.difference(from);

  /// Buckets between from and to, aligned the way the native store aligns
  /// them (local days, UTC-aligned hours — identical for whole-hour zones).
  List<int> bucketStarts(int tzOffsetMs) {
    final out = <int>[];
    var t = ((fromMs + tzOffsetMs) ~/ bucketMs) * bucketMs - tzOffsetMs;
    while (t < toMs) {
      if (t + bucketMs > fromMs) out.add(t);
      t += bucketMs;
    }
    return out;
  }

  Map<String, Object?> toQuery({int? tzOffsetMs, String? profile, String? app, String? route}) => {
        'from': fromMs,
        'to': toMs,
        'bucketMs': bucketMs,
        'tzOffsetMs': tzOffsetMs ?? from.timeZoneOffset.inMilliseconds,
        'profile': ?profile,
        'app': ?app,
        'route': ?route,
      };
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// [now] is injectable for tests.
RangeWindow windowFor(TrafficRange r, {DateTime? now, DateTime? customFrom, DateTime? customTo}) {
  final n = now ?? DateTime.now();
  final hourEnd = DateTime(n.year, n.month, n.day, n.hour + 1);
  switch (r) {
    case TrafficRange.today:
      final f = _day(n);
      final t = f.add(const Duration(days: 1));
      return RangeWindow(f, t, hourMs,
          previous: RangeWindow(f.subtract(const Duration(days: 1)), f, hourMs));
    case TrafficRange.last24h:
      final f = hourEnd.subtract(const Duration(hours: 24));
      return RangeWindow(f, hourEnd, hourMs,
          previous: RangeWindow(f.subtract(const Duration(hours: 24)), f, hourMs));
    case TrafficRange.last7d:
      final t = _day(n).add(const Duration(days: 1));
      final f = t.subtract(const Duration(days: 7));
      return RangeWindow(f, t, dayMs,
          previous: RangeWindow(f.subtract(const Duration(days: 7)), f, dayMs));
    case TrafficRange.last30d:
      final t = _day(n).add(const Duration(days: 1));
      final f = t.subtract(const Duration(days: 30));
      return RangeWindow(f, t, dayMs,
          previous: RangeWindow(f.subtract(const Duration(days: 30)), f, dayMs));
    case TrafficRange.thisMonth:
      final f = DateTime(n.year, n.month);
      final t = DateTime(n.year, n.month + 1);
      return RangeWindow(f, t, dayMs, previous: RangeWindow(DateTime(n.year, n.month - 1), f, dayMs));
    case TrafficRange.lastMonth:
      final f = DateTime(n.year, n.month - 1);
      final t = DateTime(n.year, n.month);
      return RangeWindow(f, t, dayMs, previous: RangeWindow(DateTime(n.year, n.month - 2), f, dayMs));
    case TrafficRange.custom:
      final f = _day(customFrom ?? n);
      final t = _day(customTo ?? n).add(const Duration(days: 1));
      final len = t.difference(f);
      final bucket = len.inHours <= 48 ? hourMs : dayMs;
      return RangeWindow(f, t, bucket, previous: RangeWindow(f.subtract(len), f, bucket));
  }
}

/// One chart bucket. [up]/[down] are measured per-flow bytes; [unmeasured]
/// the engine bytes no flow meter carried in that bucket.
class TrafficPoint {
  const TrafficPoint(this.t, this.up, this.down, [this.unmeasured = 0]);
  final int t;
  final int up;
  final int down;
  final int unmeasured;
  int get total => up + down;
}

/// Fills the buckets the store returned no row for with ZERO: a bucket in
/// the window with no row is a measured period with no traffic only when
/// metering covered it — the dashboard shows the coverage separately
/// ([TrafficSummary.firstRecord]); buckets before the first record are
/// dropped instead of drawn as zero.
List<TrafficPoint> fillSeries(RangeWindow w, List<TrafficPoint> rows, {int? tzOffsetMs, int? firstRecord, DateTime? now}) {
  final tz = tzOffsetMs ?? w.from.timeZoneOffset.inMilliseconds;
  final byT = {for (final p in rows) p.t: p};
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final out = <TrafficPoint>[];
  for (final t in w.bucketStarts(tz)) {
    if (t > nowMs) break; // the future is not "zero"
    if (firstRecord != null && t + w.bucketMs <= firstRecord && !byT.containsKey(t)) continue;
    out.add(byT[t] ?? TrafficPoint(t, 0, 0));
  }
  return out;
}

class AppUsage {
  const AppUsage({required this.app, required this.up, required this.down, required this.flows, this.routes = 0});
  final String app;
  final int up;
  final int down;
  final int flows;
  final int routes;
  int get total => up + down;

  factory AppUsage.fromJson(Map<String, dynamic> j) => AppUsage(
        app: j['app'] as String,
        up: (j['up'] as num).toInt(),
        down: (j['down'] as num).toInt(),
        flows: (j['flows'] as num? ?? 0).toInt(),
        routes: (j['routes'] as num? ?? 0).toInt(),
      );
}

class RouteUsage {
  const RouteUsage({required this.profile, required this.route, required this.up, required this.down, required this.flows, required this.apps});
  final String profile;
  final String route;
  final int up;
  final int down;
  final int flows;
  final int apps;
  int get total => up + down;
  String get key => '$profile/$route';

  factory RouteUsage.fromJson(Map<String, dynamic> j) => RouteUsage(
        profile: j['profile'] as String,
        route: j['route'] as String,
        up: (j['up'] as num).toInt(),
        down: (j['down'] as num).toInt(),
        flows: (j['flows'] as num? ?? 0).toInt(),
        apps: (j['apps'] as num? ?? 0).toInt(),
      );
}

class DomainUsage {
  const DomainUsage(this.domain, this.up, this.down);
  final String domain;
  final int up;
  final int down;
  int get total => up + down;
}

/// Average speed = bytes / ACTIVE seconds (seconds with traffic, 2-second
/// windows), never bytes / wall-clock (which would report an idle day as a
/// slow day). Null when nothing was active.
double? averageSpeed(int bytes, int activeSeconds) =>
    activeSeconds <= 0 ? null : bytes / activeSeconds;

/// Shares of a set of totals, in input order; empty when the sum is 0 (a
/// donut of nothing is not drawn).
List<double> shares(List<int> totals) {
  final sum = totals.fold<int>(0, (a, b) => a + b);
  if (sum <= 0) return const [];
  return [for (final t in totals) t / sum];
}

/// Percent change; null when there is no previous figure to compare with
/// (never a fake +∞ % or a fake 0 %).
double? percentChange(int current, int? previous) {
  if (previous == null || previous <= 0) return null;
  return (current - previous) * 100 / previous;
}

class TrafficSummary {
  TrafficSummary({
    required this.series,
    required this.apps,
    required this.routes,
    required this.up,
    required this.down,
    required this.unmeasuredUp,
    required this.unmeasuredDown,
    required this.flows,
    required this.peakDown,
    required this.peakUp,
    required this.activeSeconds,
    required this.domains,
    required this.firstRecord,
    this.compare,
    this.appChanges = const [],
    this.appSeries = const {},
  });

  final List<TrafficPoint> series;
  final List<AppUsage> apps;
  final List<RouteUsage> routes;
  final int up;
  final int down;
  final int unmeasuredUp;
  final int unmeasuredDown;
  final int flows;
  final int peakDown;
  final int peakUp;
  final int activeSeconds;
  final List<DomainUsage> domains;
  final int? firstRecord;
  final TrafficSummary? compare;
  final List<(String app, int current, int previous)> appChanges;
  /// app → (bucket start ms → bytes), for the list sparklines.
  final Map<String, Map<int, int>> appSeries;

  int get total => up + down;
  int get unmeasured => unmeasuredUp + unmeasuredDown;
  bool get hasHistory => firstRecord != null;
  bool get isEmpty => total == 0 && unmeasured == 0;
  double? get averageDown => averageSpeed(down, activeSeconds);
  double? get averageUp => averageSpeed(up, activeSeconds);
  double? get average => averageSpeed(total, activeSeconds);

  /// Bytes the attributed apps carried vs the unattributed bucket.
  int get unattributed {
    for (final a in apps) {
      if (a.app == TrafficKeys.unattributed) return a.total;
    }
    return 0;
  }

  /// Does the previous window have enough history to compare against? It
  /// must start at or after the first record (else part of it predates
  /// metering and a «−100 %» would be a lie).
  static bool comparable(RangeWindow prev, int? firstRecord) =>
      firstRecord != null && firstRecord <= prev.fromMs;

  factory TrafficSummary.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num? ?? 0).toInt();
    final appSeries = <String, Map<int, int>>{};
    final as = j['appSeries'];
    if (as is Map) {
      as.forEach((k, v) => appSeries[k as String] = {
            for (final e in (v as Map).entries) int.parse(e.key.toString()): (e.value as num).toInt(),
          });
    }
    return TrafficSummary(
      series: [
        for (final p in (j['series'] as List? ?? const []))
          TrafficPoint(
            (p['t'] as num).toInt(),
            (p['up'] as num).toInt(),
            (p['down'] as num).toInt(),
            (p['unmeasured'] as num? ?? 0).toInt(),
          ),
      ],
      apps: [for (final a in (j['apps'] as List? ?? const [])) AppUsage.fromJson(Map<String, dynamic>.from(a as Map))],
      routes: [for (final r in (j['routes'] as List? ?? const [])) RouteUsage.fromJson(Map<String, dynamic>.from(r as Map))],
      up: n('up'),
      down: n('down'),
      unmeasuredUp: n('unmeasuredUp'),
      unmeasuredDown: n('unmeasuredDown'),
      flows: n('flows'),
      peakDown: n('peakDown'),
      peakUp: n('peakUp'),
      activeSeconds: n('activeS'),
      domains: [
        for (final d in (j['domains'] as List? ?? const []))
          DomainUsage(d['domain'] as String, (d['up'] as num).toInt(), (d['down'] as num).toInt()),
      ],
      firstRecord: (j['firstRecord'] as num?)?.toInt(),
      compare: j['compare'] is Map ? TrafficSummary.fromJson(Map<String, dynamic>.from(j['compare'] as Map)) : null,
      appChanges: [
        for (final c in (j['appChanges'] as List? ?? const []))
          (c['app'] as String, (c['current'] as num).toInt(), (c['previous'] as num).toInt()),
      ],
      appSeries: appSeries,
    );
  }
}

/// One Live Traffic snapshot (§6): the engine's last 60 one-second samples
/// and the last 2-second window per route / app.
class LiveTraffic {
  const LiveTraffic({
    required this.running,
    required this.enabled,
    this.profile,
    this.routes = const [],
    this.down = const [],
    this.up = const [],
    this.routeRates = const {},
    this.appRates = const {},
    this.openFlows = 0,
    this.startedAt,
  });

  final bool running;
  final bool enabled;
  final String? profile;
  final List<String> routes;
  final List<int> down;
  final List<int> up;
  final Map<String, (int up, int down)> routeRates;
  final Map<String, (int up, int down)> appRates;
  final int openFlows;
  final int? startedAt;

  int get downNow => down.isEmpty ? 0 : down.last;
  int get upNow => up.isEmpty ? 0 : up.last;

  static const stopped = LiveTraffic(running: false, enabled: true);

  factory LiveTraffic.fromMap(Map<dynamic, dynamic> m) {
    Map<String, (int, int)> rates(Object? v) {
      final out = <String, (int, int)>{};
      if (v is Map) {
        for (final e in v.entries) {
          final l = e.value as List;
          out[e.key as String] = ((l[0] as num).toInt(), (l[1] as num).toInt());
        }
      }
      return out;
    }

    return LiveTraffic(
      running: m['running'] == true,
      enabled: m['enabled'] != false,
      profile: m['profile'] as String?,
      routes: [for (final r in (m['routes'] as List? ?? const [])) r as String],
      down: [for (final x in (m['down'] as List? ?? const [])) (x as num).toInt()],
      up: [for (final x in (m['up'] as List? ?? const [])) (x as num).toInt()],
      routeRates: rates(m['routeRates']),
      appRates: rates(m['appRates']),
      openFlows: (m['openFlows'] as num? ?? 0).toInt(),
      startedAt: (m['startedAt'] as num?)?.toInt(),
    );
  }
}

/// Downsamples a long series to at most [maxPoints] buckets by summing
/// neighbours (bytes stay bytes: a merged bucket carries the sum, never an
/// average that would under-report a spike's volume).
List<TrafficPoint> downsample(List<TrafficPoint> s, int maxPoints) {
  if (s.length <= maxPoints || maxPoints < 2) return s;
  final step = (s.length / maxPoints).ceil();
  final out = <TrafficPoint>[];
  for (var i = 0; i < s.length; i += step) {
    var up = 0, down = 0, un = 0;
    for (var j = i; j < i + step && j < s.length; j++) {
      up += s[j].up;
      down += s[j].down;
      un += s[j].unmeasured;
    }
    out.add(TrafficPoint(s[i].t, up, down, un));
  }
  return out;
}
