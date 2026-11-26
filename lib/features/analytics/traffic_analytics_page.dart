/// «تحلیل ترافیک» — Traffic Analytics (docs/traffic-analytics.md).
///
/// Four screens on the settings sub-page frame, each chart with ONE job
/// (docs/traffic-analytics-design-research.md §7):
///   * [TrafficAnalyticsPage] — range, totals, the download/upload area
///     chart, live speed, route share (donut), top apps (bars), compare,
///     measurement coverage;
///   * [TrafficAppsPage] — every app, searchable, with sparklines;
///   * [TrafficAppDetailPage] — one app: hourly / daily chart, per-route
///     split («Telegram: WARP vs WARP → Psiphon»), speeds, top domains;
///   * [TrafficRouteDetailPage] — one route: chart + the apps on it;
///   * [TrafficHistoryPage] — record on/off, domains, retention, export,
///     clear.
/// Every figure is a read of the native store; an absent figure is shown as
/// «—» / «not measured», never as zero.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../analytics/traffic_client.dart';
import '../../analytics/traffic_models.dart';
import '../../analytics/traffic_strings.dart';
import '../../connection/connection_store.dart';
import '../../connection/hybrid_routing.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controls.dart';
import '../settings/subpage_frame.dart';
import 'traffic_charts.dart';

// ---------------------------------------------------------------------------
// shared helpers
// ---------------------------------------------------------------------------

/// Content blocks read in the app language's direction (the frame itself
/// is direction-neutral; charts pin their own axis to LTR).
List<Widget> _dir(BuildContext context, List<Widget> blocks) {
  final d = appContentDirection(context);
  return [for (final b in blocks) Directionality(textDirection: d, child: b)];
}

double _sc(BuildContext c) => MediaQuery.sizeOf(c).width / AethGeometry.refWidth;

TextStyle _t(BuildContext c, double size, {FontWeight w = FontWeight.w400, Color? color, double? height}) => TextStyle(
      fontFamily: 'IRANYekanX',
      fontSize: size * _sc(c),
      fontWeight: w,
      color: color ?? AethColors.textPrimary,
      height: height,
    );

/// Route id → the name the user knows: a hybrid profile's tunnel label
/// («WARP → Psiphon»), else the protocol's own name.
String routeLabel(BuildContext context, String profile, String route) {
  final p = ProtocolId.values.where((e) => e.name == profile).firstOrNull;
  if (p == null) return route.isEmpty ? TrafficStrings.of(context).unmeasured : route;
  return HybridRouting.tunnelLabel(p, route) ?? AppStrings.of(context).protocolName(p);
}

String appLabel(BuildContext context, String app) {
  final ts = TrafficStrings.of(context);
  if (app == TrafficKeys.unattributed) return ts.unattributed;
  if (app == TrafficKeys.unmeasured) return ts.unmeasured;
  return TrafficClient.instance.labelOf(app) ?? app;
}

String _rangeName(TrafficStrings ts, TrafficRange r) => switch (r) {
      TrafficRange.today => ts.rangeToday,
      TrafficRange.last24h => ts.range24h,
      TrafficRange.last7d => ts.range7d,
      TrafficRange.last30d => ts.range30d,
      TrafficRange.thisMonth => ts.rangeThisMonth,
      TrafficRange.lastMonth => ts.rangeLastMonth,
      TrafficRange.custom => ts.rangeCustom,
    };

void _push(BuildContext context, ConnectionStore store, Widget page) {
  Navigator.of(context).push(aethPageRoute<void>(style: store.effectiveMotionStyle(context), builder: (_) => page));
}

/// The range state every analytics screen shares while it is open.
class _RangeState {
  TrafficRange range = TrafficRange.today;
  DateTimeRange? custom;

  RangeWindow get window => windowFor(range, customFrom: custom?.start, customTo: custom?.end);
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.state, required this.onChanged});
  final _RangeState state;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    final recipe = MotionScope.of(context).recipe;
    return SizedBox(
      height: 34 * s,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final r in TrafficRange.values)
            Padding(
              padding: EdgeInsetsDirectional.only(end: 6 * s),
              child: GestureDetector(
                key: ValueKey('traffic-range-${r.name}'),
                onTap: () async {
                  if (r == TrafficRange.custom) {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: now.subtract(const Duration(days: 3650)),
                      lastDate: now,
                      initialDateRange: state.custom,
                    );
                    if (picked == null) return;
                    state.custom = picked;
                  }
                  state.range = r;
                  onChanged();
                },
                child: AnimatedContainer(
                  duration: Duration(milliseconds: recipe.controlMs),
                  curve: recipe.controlCurve,
                  padding: EdgeInsets.symmetric(horizontal: 13 * s, vertical: 7 * s),
                  decoration: BoxDecoration(
                    color: state.range == r ? AethColors.accentConnected : AethColors.sheetDescCard,
                    borderRadius: BorderRadius.circular(14 * s),
                  ),
                  child: Text(
                    _rangeName(ts, r),
                    style: _t(context, 11.5,
                        w: state.range == r ? FontWeight.w700 : FontWeight.w600,
                        color: state.range == r ? AethColors.onCoreDark : AethColors.textPrimary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small stat cell: caption over a value (LTR number).
class _Stat extends StatelessWidget {
  const _Stat(this.caption, this.value, {this.dot, this.big = false});
  final String caption;
  final String value;
  final Color? dot;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(width: 7 * s, height: 7 * s, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            SizedBox(width: 5 * s),
          ],
          Text(caption, style: _t(context, 10, color: AethColors.textSecondary)),
        ]),
        SizedBox(height: 4 * s),
        Text(value, textDirection: TextDirection.ltr, style: _t(context, big ? 22 : 14, w: FontWeight.w700)),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6 * s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? Icons.info_outline_rounded, size: 14 * s, color: AethColors.textSecondary),
        SizedBox(width: 6 * s),
        Expanded(child: Text(text, style: _t(context, 10.5, color: AethColors.textSecondary, height: 1.6))),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 22 * s),
      child: Column(children: [
        Icon(Icons.insights_rounded, size: 30 * s, color: AethColors.textSecondary.withValues(alpha: 0.5)),
        SizedBox(height: 10 * s),
        Text(title, textAlign: TextAlign.center, style: _t(context, 13, w: FontWeight.w600)),
        if (body != null) ...[
          SizedBox(height: 4 * s),
          Text(body!, textAlign: TextAlign.center, style: _t(context, 10.5, color: AethColors.textSecondary, height: 1.6)),
        ],
      ]),
    );
  }
}

class AppIconBox extends StatelessWidget {
  const AppIconBox({super.key, required this.app, this.size = 34});
  final String app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final d = size * s;
    Widget fallback() => Container(
          width: d,
          height: d,
          decoration: BoxDecoration(color: AethColors.sheetDescCard, borderRadius: BorderRadius.circular(d * 0.32)),
          child: Icon(
            app == TrafficKeys.unattributed ? Icons.help_outline_rounded : Icons.apps_rounded,
            size: d * 0.5,
            color: AethColors.textSecondary,
          ),
        );
    return FutureBuilder<Uint8List?>(
      future: TrafficClient.instance.iconOf(app),
      builder: (context, snap) {
        final b = snap.data;
        if (b == null) return fallback();
        return ClipRRect(
          borderRadius: BorderRadius.circular(d * 0.28),
          child: Image.memory(b, width: d, height: d, gaplessPlayback: true, filterQuality: FilterQuality.medium),
        );
      },
    );
  }
}

String _axisLabel(int t, int bucketMs, {bool tooltip = false}) {
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  String two(int v) => v.toString().padLeft(2, '0');
  if (bucketMs < dayMs) {
    return tooltip ? '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:00' : '${two(d.hour)}:00';
  }
  return tooltip ? '${d.year}-${two(d.month)}-${two(d.day)}' : '${d.month}/${d.day}';
}

/// «● 760 MB  ● 50 MB» — download (green) and upload (red) without
/// arrow glyphs (IRANYekanX has none, and arrows flip in RTL).
class _DU extends StatelessWidget {
  const _DU(this.down, this.up);
  final num down;
  final num up;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    Widget one(Color c, num v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 5 * s, height: 5 * s, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          SizedBox(width: 4 * s),
          Text(formatBytes(v), textDirection: TextDirection.ltr, style: _t(context, 9.5, color: AethColors.textSecondary)),
        ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      one(TrafficPalette.down, down),
      SizedBox(width: 10 * s),
      one(TrafficPalette.up, up),
    ]);
  }
}

/// The totals card: download / upload / total + average and peak speed.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.sum});
  final TrafficSummary sum;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    return SubSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Stat(ts.total, formatBytes(sum.total), big: true),
        SizedBox(height: 14 * s),
        Row(children: [
          Expanded(child: _Stat(ts.download, formatBytes(sum.down), dot: TrafficPalette.down)),
          Expanded(child: _Stat(ts.upload, formatBytes(sum.up), dot: TrafficPalette.up)),
        ]),
        const SubSectionDivider(),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _Stat(ts.avgSpeed, sum.average == null ? '—' : formatRate(sum.average))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ts.peakSpeed, style: _t(context, 10, color: AethColors.textSecondary)),
              SizedBox(height: 4 * s),
              if (sum.peakDown + sum.peakUp == 0)
                Text('—', style: _t(context, 14, w: FontWeight.w700))
              else ...[
                _PeakLine(TrafficPalette.down, sum.peakDown),
                _PeakLine(TrafficPalette.up, sum.peakUp),
              ],
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _PeakLine extends StatelessWidget {
  const _PeakLine(this.color, this.value);
  final Color color;
  final int value;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    return Row(children: [
      Container(width: 6 * s, height: 6 * s, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      SizedBox(width: 6 * s),
      Text(formatRate(value), textDirection: TextDirection.ltr, style: _t(context, 13, w: FontWeight.w700)),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.window, required this.sum});
  final RangeWindow window;
  final TrafficSummary sum;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    final pts = downsample(fillSeries(window, sum.series, firstRecord: sum.firstRecord), 48);
    return SubSectionCard(
      padding: EdgeInsets.fromLTRB(12 * s, 14 * s, 14 * s, 10 * s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(ts.usageOverTime, style: _t(context, 12.5, w: FontWeight.w700)),
          const Spacer(),
          _Legend(color: TrafficPalette.down, label: ts.download),
          SizedBox(width: 10 * s),
          _Legend(color: TrafficPalette.up, label: ts.upload),
        ]),
        SizedBox(height: 12 * s),
        if (pts.isEmpty || sum.total == 0)
          _Empty(title: ts.noData, body: ts.noDataBody)
        else
          TrafficAreaChart(
            points: pts,
            bucketMs: window.bucketMs,
            downLabel: ts.download,
            upLabel: ts.upload,
            xLabel: (t, {tooltip = false}) => _axisLabel(t, window.bucketMs, tooltip: tooltip),
          ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8 * s, height: 3 * s, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      SizedBox(width: 4 * s),
      Text(label, style: _t(context, 10, color: AethColors.textSecondary)),
    ]);
  }
}

/// Loads a [TrafficSummary] for the current range and re-loads on change.
mixin _Loader<W extends StatefulWidget> on State<W> {
  final _RangeState range = _RangeState();
  TrafficSummary? sum;
  bool loading = true;
  Object? error;
  int _gen = 0;

  Future<TrafficSummary?> fetch(RangeWindow w);

  Future<void> reload() async {
    final g = ++_gen;
    setState(() => loading = true);
    try {
      final r = await fetch(range.window);
      if (r != null) {
        await TrafficClient.instance.resolveLabels([
          ...r.apps.map((a) => a.app),
          ...r.appChanges.map((c) => c.$1),
        ]);
      }
      if (!mounted || g != _gen) return;
      setState(() {
        sum = r;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted || g != _gen) return;
      setState(() {
        error = e;
        loading = false;
      });
    }
  }
}

List<Widget> _statusBlocks(BuildContext context, {required bool loading, required Object? error, required TrafficSummary? sum}) {
  final ts = TrafficStrings.of(context);
  if (!TrafficClient.instance.supported) return [SubSectionCard(child: _Empty(title: ts.unsupported))];
  if (error != null) return [SubSectionCard(child: _Empty(title: ts.errorLoading, body: '$error'))];
  if (sum == null) {
    return [
      SubSectionCard(
        child: _Empty(title: loading ? ts.loading : ts.noData),
      ),
    ];
  }
  return const [];
}

// ---------------------------------------------------------------------------
// The dashboard
// ---------------------------------------------------------------------------

class TrafficAnalyticsPage extends StatefulWidget {
  const TrafficAnalyticsPage({super.key, required this.store});
  final ConnectionStore store;

  @override
  State<TrafficAnalyticsPage> createState() => _TrafficAnalyticsPageState();
}

class _TrafficAnalyticsPageState extends State<TrafficAnalyticsPage> with _Loader {
  Timer? _livePoll;
  LiveTraffic _live = LiveTraffic.stopped;
  int? _selRoute;
  int _liveTicks = 0;

  @override
  Future<TrafficSummary?> fetch(RangeWindow w) => TrafficClient.instance.query(w, compare: true);

  @override
  void initState() {
    super.initState();
    unawaited(reload());
    unawaited(_pollLive());
    // one channel read per second while the page is visible; the native
    // side keeps the samples, so a missed tick loses nothing.
    _livePoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollLive());
  }

  Future<void> _pollLive() async {
    try {
      final l = await TrafficClient.instance.live();
      if (!mounted) return;
      final wasRunning = _live.running;
      setState(() => _live = l);
      if (l.running && l.appRates.isNotEmpty) unawaited(TrafficClient.instance.resolveLabels(l.appRates.keys));
      // totals follow the live session (every 15 s, the native flush cadence)
      _liveTicks++;
      if ((l.running && _liveTicks % 15 == 0) || (wasRunning && !l.running)) unawaited(reload());
    } catch (_) {}
  }

  @override
  void dispose() {
    _livePoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ts = TrafficStrings.of(context);
    final s = _sc(context);
    final store = widget.store;
    return SubPageFrame(
      store: store,
      title: ts.title,
      icon: AppAssets.iconGraphUp,
      subtitle: ts.subtitle,
      children: () {
        final w = range.window;
        final x = sum;
        return _dir(context, [
          _RangeChips(state: range, onChanged: () => unawaited(reload())),
          SizedBox(height: 14 * s),
          ..._statusBlocks(context, loading: loading, error: error, sum: x),
          if (x != null) ...[
            _TotalsCard(sum: x),
            SizedBox(height: 12 * s),
            _ChartCard(window: w, sum: x),
          ],
          const SubSectionGap.cardToHeading(),
          SubSectionHeading(icon: AppAssets.iconActivity4, title: ts.live),
          const SubSectionGap.headingToCard(),
          _LiveCard(live: _live),
          if (x != null && x.routes.isNotEmpty) ...[
            const SubSectionGap.cardToHeading(),
            SubSectionHeading(icon: AppAssets.iconArrowSwapHorizontal, title: ts.routes),
            const SubSectionGap.headingToCard(),
            _RoutesCard(
              sum: x,
              selected: _selRoute,
              onSelect: (i) => setState(() => _selRoute = _selRoute == i ? null : i),
              onOpen: (r) => _push(context, store, TrafficRouteDetailPage(store: store, route: r, initialRange: range.range, custom: range.custom)),
            ),
          ],
          if (x != null && x.apps.isNotEmpty) ...[
            const SubSectionGap.cardToHeading(),
            SubSectionHeading(icon: AppAssets.iconFilter5, title: ts.apps),
            const SubSectionGap.headingToCard(),
            _TopAppsCard(
              sum: x,
              onOpen: (a) => _push(context, store, TrafficAppDetailPage(store: store, app: a, initialRange: range.range, custom: range.custom)),
              onAll: () => _push(context, store, TrafficAppsPage(store: store, initialRange: range.range, custom: range.custom)),
            ),
          ],
          if (x != null && !x.isEmpty) ...[
            const SubSectionGap.cardToHeading(),
            SubSectionHeading(icon: AppAssets.iconGraphDown, title: ts.compare),
            const SubSectionGap.headingToCard(),
            _CompareCard(sum: x, window: w, rangeName: _rangeName(ts, range.range)),
            const SubSectionGap.cardToHeading(),
            _CoverageCard(sum: x),
          ],
          const SubSectionGap.cardToHeading(),
          SubSectionCard(
            child: SettingNavRow(
              keyId: 'traffic-history',
              icon: AppAssets.iconFilter1,
              title: ts.history,
              description: ts.historyDesc,
              onTap: () => _push(context, store, TrafficHistoryPage(store: store, onChanged: () => unawaited(reload()))),
            ),
          ),
          SizedBox(height: 24 * s),
        ]);
      },
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live});
  final LiveTraffic live;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    if (!live.running) {
      return SubSectionCard(child: _Note(live.enabled ? ts.liveOff : ts.liveDisabled, icon: Icons.wifi_off_rounded));
    }
    final apps = live.appRates.entries.where((e) => e.value.$1 + e.value.$2 > 0).toList()
      ..sort((a, b) => (b.value.$1 + b.value.$2).compareTo(a.value.$1 + a.value.$2));
    final routes = live.routeRates.entries.where((e) => e.value.$1 + e.value.$2 > 0).toList();
    return SubSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _Stat(ts.download, formatRate(live.downNow), dot: TrafficPalette.down)),
          Expanded(child: _Stat(ts.upload, formatRate(live.upNow), dot: TrafficPalette.up)),
          Expanded(child: _Stat(ts.total, formatRate(live.downNow + live.upNow))),
        ]),
        SizedBox(height: 12 * s),
        LiveSpeedChart(down: live.down, up: live.up),
        SizedBox(height: 10 * s),
        Wrap(spacing: 8 * s, runSpacing: 6 * s, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${ts.activeRoutes}:', style: _t(context, 10.5, color: AethColors.textSecondary)),
          if (routes.isEmpty) Text('—', style: _t(context, 10.5)),
          for (final e in routes)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
              decoration: BoxDecoration(color: AethColors.sheetDescCard, borderRadius: BorderRadius.circular(10 * s)),
              child: Text(routeLabel(context, live.profile ?? '', e.key),
                  textDirection: TextDirection.ltr, style: _t(context, 10.5, w: FontWeight.w600)),
            ),
          Text('${live.openFlows} ${ts.openFlows}', style: _t(context, 10.5, color: AethColors.textSecondary)),
        ]),
        if (apps.isNotEmpty) ...[
          SizedBox(height: 8 * s),
          Text(ts.activeApps, style: _t(context, 10.5, color: AethColors.textSecondary)),
          SizedBox(height: 6 * s),
          Wrap(spacing: 8 * s, runSpacing: 6 * s, children: [
            for (final e in apps.take(6))
              Row(mainAxisSize: MainAxisSize.min, children: [
                AppIconBox(app: e.key, size: 20),
                SizedBox(width: 5 * s),
                Text('${appLabel(context, e.key)} ', style: _t(context, 10.5, w: FontWeight.w600)),
                Text(formatRate(e.value.$1 + e.value.$2), textDirection: TextDirection.ltr, style: _t(context, 10, color: AethColors.textSecondary)),
              ]),
          ]),
        ],
      ]),
    );
  }
}

class _RoutesCard extends StatelessWidget {
  const _RoutesCard({required this.sum, required this.selected, required this.onSelect, required this.onOpen});
  final TrafficSummary sum;
  final int? selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<RouteUsage> onOpen;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    final routes = sum.routes;
    final colors = [for (var i = 0; i < routes.length; i++) TrafficPalette.route(i)];
    final sel = selected != null && selected! < routes.length ? routes[selected!] : null;
    final share = shares(routes.map((r) => r.total).toList());
    return SubSectionCard(
      child: Column(children: [
        Center(
          child: TrafficDonut(
            values: routes.map((r) => r.total).toList(),
            colors: colors,
            selected: selected,
            center: formatBytes(sel?.total ?? sum.total),
            caption: sel == null ? ts.total : routeLabel(context, sel.profile, sel.route),
          ),
        ),
        SizedBox(height: 12 * s),
        for (var i = 0; i < routes.length; i++) ...[
          if (i > 0) const SubSectionDivider(),
          GestureDetector(
            key: ValueKey('traffic-route-${routes[i].key}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpen(routes[i]),
            onLongPress: () => onSelect(i),
            child: Row(children: [
              Container(width: 10 * s, height: 10 * s, decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle)),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(routeLabel(context, routes[i].profile, routes[i].route),
                      textDirection: TextDirection.ltr, style: _t(context, 12.5, w: FontWeight.w700)),
                  SizedBox(height: 2 * s),
                  Wrap(spacing: 10 * s, children: [
                    _DU(routes[i].down, routes[i].up),
                    Text('${routes[i].flows} ${ts.flows} • ${routes[i].apps} ${ts.appsUsing}',
                        style: _t(context, 9.5, color: AethColors.textSecondary)),
                  ]),
                ]),
              ),
              Text(share.isEmpty ? '—' : '${(share[i] * 100).toStringAsFixed(share[i] < 0.1 ? 1 : 0)}%',
                  textDirection: TextDirection.ltr, style: _t(context, 12, w: FontWeight.w700)),
              SizedBox(width: 6 * s),
              SvgGlyph(asset: AppAssets.iconLeft2, size: 16 * s, color: AethColors.textSecondary),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.max, required this.onTap, this.spark});
  final AppUsage app;
  final int max;
  final VoidCallback onTap;
  final List<int>? spark;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final special = TrafficKeys.isSpecial(app.app);
    return GestureDetector(
      key: ValueKey('traffic-app-${app.app}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4 * s),
        child: Row(children: [
          AppIconBox(app: app.app),
          SizedBox(width: 10 * s),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(appLabel(context, app.app),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(context, 12.5, w: FontWeight.w700, color: special ? AethColors.textSecondary : null)),
                ),
                if (spark != null && spark!.where((v) => v > 0).length > 1) ...[
                  TrafficSparkline(values: spark!),
                  SizedBox(width: 8 * s),
                ],
                Text(formatBytes(app.total), textDirection: TextDirection.ltr, style: _t(context, 12, w: FontWeight.w700)),
              ]),
              SizedBox(height: 6 * s),
              TrafficHBar(down: app.down, up: app.up, max: max),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TopAppsCard extends StatelessWidget {
  const _TopAppsCard({required this.sum, required this.onOpen, required this.onAll});
  final TrafficSummary sum;
  final ValueChanged<String> onOpen;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    final top = sum.apps.take(5).toList();
    final max = top.isEmpty ? 1 : top.first.total;
    return SubSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final a in top) _AppRow(app: a, max: max, onTap: () => onOpen(a.app)),
        ...[
          const SubSectionDivider(),
          GestureDetector(
            key: const ValueKey('traffic-all-apps'),
            behavior: HitTestBehavior.opaque,
            onTap: onAll,
            child: Row(children: [
              Text('${ts.allApps} (${sum.apps.length})', style: _t(context, 12, w: FontWeight.w600)),
              const Spacer(),
              SvgGlyph(asset: AppAssets.iconLeft2, size: 16 * s, color: AethColors.textSecondary),
            ]),
          ),
        ],
        // every byte unattributed = the platform could not name owners
        // (Android < 10): say why instead of an empty app list.
        if (sum.total > 0 && sum.unattributed == sum.total) _Note(ts.android10),
      ]),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.sum, required this.window, required this.rangeName});
  final TrafficSummary sum;
  final RangeWindow window;
  final String rangeName;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    final prev = window.previous;
    final ok = prev != null && sum.compare != null && TrafficSummary.comparable(prev, sum.firstRecord);
    final pct = ok ? percentChange(sum.total, sum.compare!.total) : null;
    return SubSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(ts.vsPrevious, style: _t(context, 12, w: FontWeight.w600))),
          if (pct != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
              decoration: BoxDecoration(
                color: (pct >= 0 ? TrafficPalette.up : TrafficPalette.down).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10 * s),
              ),
              child: Text(
                '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(pct.abs() < 10 ? 1 : 0)}%',
                textDirection: TextDirection.ltr,
                style: _t(context, 11, w: FontWeight.w700, color: pct >= 0 ? TrafficPalette.upDeep : AethColors.onCoreDark),
              ),
            ),
        ]),
        SizedBox(height: 8 * s),
        if (!ok)
          _Note(ts.notEnoughHistory)
        else ...[
          CompareBars(
            current: sum.total,
            previous: sum.compare!.total,
            currentLabel: rangeName,
            previousLabel: ts.previous,
          ),
          if (sum.appChanges.isNotEmpty) ...[
            const SubSectionDivider(),
            Text(ts.biggestChanges, style: _t(context, 10.5, color: AethColors.textSecondary)),
            SizedBox(height: 6 * s),
            for (final c in sum.appChanges.take(3))
              Padding(
                padding: EdgeInsets.symmetric(vertical: 3 * s),
                child: Row(children: [
                  AppIconBox(app: c.$1, size: 22),
                  SizedBox(width: 8 * s),
                  Expanded(child: Text(appLabel(context, c.$1), maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(context, 11.5, w: FontWeight.w600))),
                  Text(
                    '${formatBytes(c.$3)} → ${formatBytes(c.$2)}',
                    textDirection: TextDirection.ltr,
                    style: _t(context, 10.5, color: AethColors.textSecondary),
                  ),
                ]),
              ),
          ],
        ],
      ]),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.sum});
  final TrafficSummary sum;

  @override
  Widget build(BuildContext context) {
    final ts = TrafficStrings.of(context);
    final s = _sc(context);
    return SubSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(ts.coverage, style: _t(context, 12, w: FontWeight.w700)),
        SizedBox(height: 6 * s),
        Row(children: [
          Expanded(child: _Stat(ts.unattributed, sum.unattributed == 0 ? '0 B' : formatBytes(sum.unattributed))),
          Expanded(child: _Stat(ts.unmeasured, formatBytes(sum.unmeasured))),
        ]),
        _Note(ts.unattributedHint),
        _Note(ts.unmeasuredHint),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// All apps
// ---------------------------------------------------------------------------

class TrafficAppsPage extends StatefulWidget {
  const TrafficAppsPage({super.key, required this.store, this.initialRange = TrafficRange.today, this.custom});
  final ConnectionStore store;
  final TrafficRange initialRange;
  final DateTimeRange? custom;

  @override
  State<TrafficAppsPage> createState() => _TrafficAppsPageState();
}

class _TrafficAppsPageState extends State<TrafficAppsPage> with _Loader {
  final TextEditingController _q = TextEditingController();
  int _shown = 40;

  @override
  Future<TrafficSummary?> fetch(RangeWindow w) => TrafficClient.instance.query(w, appSeries: true);

  @override
  void initState() {
    super.initState();
    range.range = widget.initialRange;
    range.custom = widget.custom;
    unawaited(reload());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ts = TrafficStrings.of(context);
    final s = _sc(context);
    return SubPageFrame(
      store: widget.store,
      title: ts.allApps,
      children: () {
        final x = sum;
        final w = range.window;
        final q = _q.text.trim().toLowerCase();
        final apps = (x?.apps ?? const <AppUsage>[])
            .where((a) => q.isEmpty || a.app.toLowerCase().contains(q) || appLabel(context, a.app).toLowerCase().contains(q))
            .toList();
        final max = apps.isEmpty ? 1 : apps.map((a) => a.total).reduce((a, b) => a > b ? a : b);
        final buckets = w.bucketStarts(w.from.timeZoneOffset.inMilliseconds);
        return _dir(context, [
          _RangeChips(state: range, onChanged: () => unawaited(reload())),
          SizedBox(height: 12 * s),
          SettingField(
            label: ts.searchApps,
            hint: ts.searchApps,
            initial: '',
            keyId: 'traffic-search',
            onChanged: (v) => setState(() => _q.text = v),
          ),
          SizedBox(height: 12 * s),
          ..._statusBlocks(context, loading: loading, error: error, sum: x),
          if (x != null)
            SubSectionCard(
              child: apps.isEmpty
                  ? _Empty(title: ts.noData)
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final a in apps.take(_shown))
                        _AppRow(
                          app: a,
                          max: max,
                          spark: x.appSeries[a.app] == null ? null : [for (final b in buckets) x.appSeries[a.app]![b] ?? 0],
                          onTap: () => _push(context, widget.store,
                              TrafficAppDetailPage(store: widget.store, app: a.app, initialRange: range.range, custom: range.custom)),
                        ),
                      if (apps.length > _shown)
                        TextButton(onPressed: () => setState(() => _shown += 40), child: Text('+${apps.length - _shown}', style: _t(context, 12))),
                    ]),
            ),
          SizedBox(height: 24 * s),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// One app
// ---------------------------------------------------------------------------

class TrafficAppDetailPage extends StatefulWidget {
  const TrafficAppDetailPage({super.key, required this.store, required this.app, this.initialRange = TrafficRange.today, this.custom});
  final ConnectionStore store;
  final String app;
  final TrafficRange initialRange;
  final DateTimeRange? custom;

  @override
  State<TrafficAppDetailPage> createState() => _TrafficAppDetailPageState();
}

class _TrafficAppDetailPageState extends State<TrafficAppDetailPage> with _Loader {
  bool _daily = false;
  TrafficSummary? _alt;

  RangeWindow get _chartWindow {
    final w = range.window;
    if (_daily) {
      if (w.bucketMs == dayMs) return w;
      final t = DateTime(w.to.year, w.to.month, w.to.day).add(const Duration(days: 1));
      return RangeWindow(t.subtract(const Duration(days: 30)), t, dayMs);
    }
    if (w.bucketMs == hourMs) return w;
    return windowFor(TrafficRange.last24h);
  }

  @override
  Future<TrafficSummary?> fetch(RangeWindow w) async {
    final main = await TrafficClient.instance.query(w, app: widget.app);
    final cw = _chartWindow;
    _alt = (cw.fromMs == w.fromMs && cw.bucketMs == w.bucketMs) ? main : await TrafficClient.instance.query(cw, app: widget.app);
    return main;
  }

  @override
  void initState() {
    super.initState();
    range.range = widget.initialRange;
    range.custom = widget.custom;
    _daily = range.window.bucketMs == dayMs;
    unawaited(reload());
  }

  @override
  Widget build(BuildContext context) {
    final ts = TrafficStrings.of(context);
    final s = _sc(context);
    final special = TrafficKeys.isSpecial(widget.app);
    return SubPageFrame(
      store: widget.store,
      title: appLabel(context, widget.app),
      children: () {
        final x = sum;
        return _dir(context, [
          Row(children: [
            AppIconBox(app: widget.app, size: 44),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(appLabel(context, widget.app), style: _t(context, 15, w: FontWeight.w700)),
                Text(special ? ts.unattributedHint : widget.app,
                    textDirection: TextDirection.ltr, style: _t(context, 10, color: AethColors.textSecondary)),
              ]),
            ),
          ]),
          SizedBox(height: 14 * s),
          _RangeChips(state: range, onChanged: () => unawaited(reload())),
          SizedBox(height: 12 * s),
          ..._statusBlocks(context, loading: loading, error: error, sum: x),
          if (x != null) ...[
            _TotalsCard(sum: x),
            SizedBox(height: 12 * s),
            SettingPills<bool>(
              keyId: 'traffic-app-granularity',
              options: [(false, ts.hourly), (true, ts.daily)],
              selected: _daily,
              onSelect: (v) {
                _daily = v;
                unawaited(reload());
              },
            ),
            SizedBox(height: 10 * s),
            if (_alt != null) _ChartCard(window: _chartWindow, sum: _alt!),
            const SubSectionGap.cardToHeading(),
            SubSectionHeading(icon: AppAssets.iconArrowSwapHorizontal, title: ts.byRoute),
            const SubSectionGap.headingToCard(),
            _SplitTable(
              rows: [
                for (final r in x.routes) (routeLabel(context, r.profile, r.route), r.down, r.up, r.flows),
              ],
              onTap: (i) => _push(context, widget.store,
                  TrafficRouteDetailPage(store: widget.store, route: x.routes[i], initialRange: range.range, custom: range.custom)),
            ),
            if (x.domains.isNotEmpty) ...[
              const SubSectionGap.cardToHeading(),
              SubSectionHeading(icon: AppAssets.iconSearch, title: ts.topDomains),
              const SubSectionGap.headingToCard(),
              _SplitTable(rows: [for (final d in x.domains.take(10)) (d.domain, d.down, d.up, null)]),
            ],
          ],
          SizedBox(height: 24 * s),
        ]);
      },
    );
  }
}

/// label | ↓ | ↑ rows (the «Telegram: WARP / WARP → Psiphon» table).
class _SplitTable extends StatelessWidget {
  const _SplitTable({required this.rows, this.onTap});
  final List<(String, int, int, int?)> rows;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final s = _sc(context);
    final ts = TrafficStrings.of(context);
    if (rows.isEmpty) return SubSectionCard(child: _Empty(title: ts.noData));
    TextStyle head = _t(context, 10, color: AethColors.textSecondary);
    return SubSectionCard(
      child: Column(children: [
        Row(children: [
          const Expanded(child: SizedBox()),
          SizedBox(width: 78 * s, child: Text(ts.download, textAlign: TextAlign.end, style: head)),
          SizedBox(width: 70 * s, child: Text(ts.upload, textAlign: TextAlign.end, style: head)),
        ]),
        SizedBox(height: 6 * s),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SubSectionDivider(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null ? null : () => onTap!(i),
            child: Row(children: [
              Expanded(
                child: Text(rows[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left,
                    style: _t(context, 12, w: FontWeight.w700)),
              ),
              SizedBox(
                width: 78 * s,
                child: Text(formatBytes(rows[i].$2),
                    textAlign: TextAlign.end, textDirection: TextDirection.ltr, style: _t(context, 11.5, color: TrafficPalette.down, w: FontWeight.w600)),
              ),
              SizedBox(
                width: 70 * s,
                child: Text(formatBytes(rows[i].$3),
                    textAlign: TextAlign.end, textDirection: TextDirection.ltr, style: _t(context, 11.5, color: TrafficPalette.up, w: FontWeight.w600)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// One route
// ---------------------------------------------------------------------------

class TrafficRouteDetailPage extends StatefulWidget {
  const TrafficRouteDetailPage({super.key, required this.store, required this.route, this.initialRange = TrafficRange.today, this.custom});
  final ConnectionStore store;
  final RouteUsage route;
  final TrafficRange initialRange;
  final DateTimeRange? custom;

  @override
  State<TrafficRouteDetailPage> createState() => _TrafficRouteDetailPageState();
}

class _TrafficRouteDetailPageState extends State<TrafficRouteDetailPage> with _Loader {
  @override
  Future<TrafficSummary?> fetch(RangeWindow w) =>
      TrafficClient.instance.query(w, profile: widget.route.profile, route: widget.route.route);

  @override
  void initState() {
    super.initState();
    range.range = widget.initialRange;
    range.custom = widget.custom;
    unawaited(reload());
  }

  @override
  Widget build(BuildContext context) {
    final ts = TrafficStrings.of(context);
    final s = _sc(context);
    final name = routeLabel(context, widget.route.profile, widget.route.route);
    return SubPageFrame(
      store: widget.store,
      title: name,
      children: () {
        final x = sum;
        final w = range.window;
        final max = x == null || x.apps.isEmpty ? 1 : x.apps.first.total;
        return _dir(context, [
          _RangeChips(state: range, onChanged: () => unawaited(reload())),
          SizedBox(height: 12 * s),
          ..._statusBlocks(context, loading: loading, error: error, sum: x),
          if (x != null) ...[
            _TotalsCard(sum: x),
            SizedBox(height: 8 * s),
            Text('${x.flows} ${ts.flows}   •   ${x.apps.where((a) => !TrafficKeys.isSpecial(a.app)).length} ${ts.appsUsing}',
                style: _t(context, 10.5, color: AethColors.textSecondary)),
            SizedBox(height: 10 * s),
            _ChartCard(window: w, sum: x),
            const SubSectionGap.cardToHeading(),
            SubSectionHeading(icon: AppAssets.iconFilter5, title: ts.byApp),
            const SubSectionGap.headingToCard(),
            SubSectionCard(
              child: x.apps.isEmpty
                  ? _Empty(title: ts.noData)
                  : Column(children: [
                      for (final a in x.apps)
                        _AppRow(
                          app: a,
                          max: max,
                          onTap: () => _push(context, widget.store,
                              TrafficAppDetailPage(store: widget.store, app: a.app, initialRange: range.range, custom: range.custom)),
                        ),
                    ]),
            ),
          ],
          SizedBox(height: 24 * s),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// History & export
// ---------------------------------------------------------------------------

class TrafficHistoryPage extends StatefulWidget {
  const TrafficHistoryPage({super.key, required this.store, this.onChanged});
  final ConnectionStore store;
  final VoidCallback? onChanged;

  @override
  State<TrafficHistoryPage> createState() => _TrafficHistoryPageState();
}

class _TrafficHistoryPageState extends State<TrafficHistoryPage> {
  Map<String, Object?> _cfg = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool? enabled, bool? domains, int? retention}) async {
    final c = await TrafficClient.instance.config(enabled: enabled, domains: domains, retentionDays: retention);
    if (mounted) setState(() => _cfg = c);
  }

  void _toast(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final ts = TrafficStrings.of(context);
    final s = _sc(context);
    final retention = (_cfg['retentionDays'] as num?)?.toInt() ?? 90;
    return SubPageFrame(
      store: widget.store,
      title: ts.history,
      icon: AppAssets.iconFilter1,
      subtitle: ts.historyDesc,
      children: () => _dir(context, [
        SubSectionCard(
          child: Column(children: [
            SettingToggleRow(
              keyId: 'traffic-record',
              title: ts.recordUsage,
              description: '${ts.recordUsageDesc} ${ts.appliesNextConnect}',
              value: _cfg['enabled'] != false,
              onChanged: (v) => unawaited(_load(enabled: v)),
            ),
            const SubSectionDivider(),
            SettingToggleRow(
              keyId: 'traffic-domains',
              title: ts.recordDomains,
              description: ts.recordDomainsDesc,
              value: _cfg['domains'] != false,
              onChanged: (v) => unawaited(_load(domains: v)),
            ),
          ]),
        ),
        const SubSectionGap.cardToHeading(),
        SubSectionHeading(icon: AppAssets.iconFilter5, title: ts.retention),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingPills<int>(
            keyId: 'traffic-retention',
            options: [(30, ts.days(30)), (90, ts.days(90)), (365, ts.days(365)), (0, ts.forever)],
            selected: retention,
            onSelect: (v) => unawaited(_load(retention: v)),
          ),
        ),
        const SubSectionGap.cardToHeading(),
        SubSectionCard(
          child: Column(children: [
            SettingNavRow(
              keyId: 'traffic-export-csv',
              icon: AppAssets.iconDownload,
              title: ts.exportCsv,
              onTap: () async => _toast(await TrafficClient.instance.export('csv') ? ts.exported : ts.exportFailed),
            ),
            const SubSectionDivider(),
            SettingNavRow(
              keyId: 'traffic-export-json',
              icon: AppAssets.iconDownload,
              title: ts.exportJson,
              onTap: () async => _toast(await TrafficClient.instance.export('json') ? ts.exported : ts.exportFailed),
            ),
            const SubSectionDivider(),
            SettingNavRow(
              keyId: 'traffic-clear',
              icon: AppAssets.iconOff,
              title: ts.clearHistory,
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: AethColors.cardDark,
                    content: Text(ts.clearConfirm, style: _t(c, 13)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ts.cancel, style: _t(c, 12))),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(ts.clear, style: _t(c, 12, w: FontWeight.w700, color: TrafficPalette.upDeep)),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await TrafficClient.instance.clear();
                widget.onChanged?.call();
                _toast(ts.cleared);
              },
            ),
          ]),
        ),
        SizedBox(height: 24 * s),
      ]),
    );
  }
}
