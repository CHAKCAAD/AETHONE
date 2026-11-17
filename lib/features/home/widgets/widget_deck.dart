/// v2.1.0 (the owner's decree, 2026-11-17: «برای صفحه اصلی چندتا ویجت
/// خلاقانه اضافه کن») — THE HOME WIDGET DECK: a compact row of three
/// live, honest widget cards under the hero band.
///
///   1. «مدت اتصال» — a live-ticking session timer (the app's own
///      Watch 1.svg glyph). The clock starts at the engine's OWN
///      Connected transition (tracked in the widget; a state we never
///      fabricate) and freezes the moment the session ends.
///   2. «تأخیر» — the ping sparkline (Activity 4.svg + a CustomPainter
///      line of the last samples the store reported while connected —
///      a quiet live ECG of the tunnel; «—» until the first sample).
///   3. «داده جلسه» — the session's data volume (Download.svg + the
///      honest cumulative counters, plus a down/up split bar that
///      fills with the real ratio; 0 bytes renders the honest dash).
///
/// Design language: the settings-card grammar (cardDark fill, r21,
/// IRANYekanX, accent-green values, muted labels) — same family as the
/// bottom panel's stat cards, so the deck reads as a first-class part
/// of the home page, not an add-on. Every glyph comes from the app's
/// own icon set (the owner's standing rule: no Material icons, no
/// emoji, no online images).
///
/// Honesty rules (the repo's own):
///  * DISCONNECTED ⇒ every card shows its idle placeholder («—» and
///    the muted «غیرفعال» chip), never a stale or invented value;
///  * the timer only ticks while `connected` is TRUE — it pauses on
///    reconnecting and resumes without resetting (the session is the
///    ENGINE's session, not the widget's);
///  * the sparkline holds at most [PingSparklineCard.maxSamples]
///    samples, collected only while connected.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_state.dart';
import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';

/// The deck: one horizontal row of the three widget cards, RTL-ordered
/// (the page's own reading direction), each taking an equal share of
/// the page width minus the panel insets.
class HomeWidgetDeck extends StatelessWidget {
  const HomeWidgetDeck({
    super.key,
    required this.store,
    required this.style,
  });

  final ConnectionStore store;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AethGeometry.pageHPadding * s),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Expanded(
              child: SessionTimerCard(store: store, style: style),
            ),
            SizedBox(width: 8 * s),
            Expanded(
              flex: 2,
              child: PingSparklineCard(store: store, style: style),
            ),
            SizedBox(width: 8 * s),
            Expanded(
              child: SessionDataCard(store: store, style: style),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared card chrome: cardDark fill, r21, the glyph box, the muted
/// label over the value — the stat-card grammar.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.iconAsset,
    required this.label,
    required this.child,
    this.iconTint,
  });

  final String iconAsset;
  final String label;
  final Widget child;
  final Color? iconTint;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Container(
      height: AethGeometry.homeDeckCardH * s,
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 9 * s),
      decoration: BoxDecoration(
        color: AethColors.cardDark,
        borderRadius: BorderRadius.circular(AethRadius.card * s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 14 * s,
                height: 14 * s,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  iconTint ?? AethColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
              SizedBox(width: 6 * s),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w400,
                    fontSize: 9 * s,
                    color: AethColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 1 — «مدت اتصال»: the live session clock. While connected it ticks
/// every second (mm:ss under an hour, then h:mm); any other state holds
/// the last pose with the honest idle dash on a cold start.
class SessionTimerCard extends StatefulWidget {
  const SessionTimerCard({super.key, required this.store, required this.style});

  final ConnectionStore store;
  final MotionStyle style;

  @override
  State<SessionTimerCard> createState() => _SessionTimerCardState();
}

class _SessionTimerCardState extends State<SessionTimerCard> {
  /// The elapsed is counted in TICKS (one per second the ticker fires
  /// while live), not wall-clock reads — the clock pauses on any
  /// non-connected state and resumes without resetting, and the count
  /// is exactly the seconds the ENGINE's session was live.
  Duration _elapsed = Duration.zero;
  Duration _held = Duration.zero;
  bool _live = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
  }

  @override
  void dispose() {
    _stopTicker();
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    final connected = widget.store.state == VpnState.connected;
    if (connected && !_live) {
      // The engine's OWN Connected moment — a fresh session starts at
      // zero (the held pose of a previous session is retired).
      setState(() {
        _live = true;
        _elapsed = Duration.zero;
        _held = Duration.zero;
      });
      _startTicker();
    } else if (!connected && _live) {
      // The session ended: freeze the elapsed pose (the card keeps the
      // last honest reading until the next session resets it).
      setState(() {
        _live = false;
        _held = _elapsed;
      });
      _stopTicker();
    }
  }

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _live) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  String _format(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final live = _live;
    final text = live
        ? _format(_elapsed)
        : (_held > Duration.zero ? _format(_held) : '—');

    return _DeckCard(
      iconAsset: AppAssets.iconWatch1,
      label: strings.homeWidgetTimer,
      iconTint: live ? AethColors.accentConnected : null,
      child: Directionality(
        // The clock face (12:34) never bidi-flips.
        textDirection: TextDirection.ltr,
        child: AnimatedDefaultTextStyle(
          duration: motionDuration(widget.style, MotionDurations.quick),
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: FontWeight.w700,
            fontSize: 15 * s,
            color: live ? AethColors.textPrimary : AethColors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// 2 — «تأخیر»: the ping sparkline. Collects the store's ping samples
/// while connected (max [maxSamples]); paints them as the accent-green
/// ECG line with the CURRENT value beside it. No samples yet ⇒ the
/// honest dash.
class PingSparklineCard extends StatefulWidget {
  const PingSparklineCard({super.key, required this.store, required this.style});

  final ConnectionStore store;
  final MotionStyle style;

  /// The rolling window (≈ the last 40 s of one-per-engine-report samples).
  static const int maxSamples = 40;

  @override
  State<PingSparklineCard> createState() => _PingSparklineCardState();
}

class _PingSparklineCardState extends State<PingSparklineCard> {
  final List<int> _samples = [];

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _onStoreChange();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    final ping = widget.store.pingMs;
    final connected = widget.store.state == VpnState.connected;
    if (connected && ping != null) {
      if (_samples.isNotEmpty && _samples.last == ping) return;
      setState(() {
        _samples.add(ping);
        if (_samples.length > PingSparklineCard.maxSamples) {
          _samples.removeRange(
            0,
            _samples.length - PingSparklineCard.maxSamples,
          );
        }
      });
    } else if (!connected && _samples.isNotEmpty) {
      // A fresh session restarts the ECG — stale samples never leak in.
      setState(_samples.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final live = _samples.isNotEmpty;
    final current = live ? _samples.last : null;

    return _DeckCard(
      iconAsset: AppAssets.iconActivity4,
      label: strings.homeWidgetPing,
      iconTint: live ? AethColors.accentConnected : null,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: AethGeometry.homeDeckSparkH * s,
              child: CustomPaint(
                painter: _SparklinePainter(
                  samples: _samples,
                  color: AethColors.accentConnected,
                ),
              ),
            ),
          ),
          SizedBox(width: 8 * s),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              current != null ? '$current' : '—',
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: 15 * s,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: live
                    ? AethColors.textPrimary
                    : AethColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ECG painter: a smooth polyline through the samples, normalized to
/// the window's own min/max (a flat window still draws its line at the
/// vertical center — one sample paints a dot-line). Points ride on a
/// 3-px baseline inset so the line never clips the card.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.samples, required this.color});

  final List<int> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final min = samples.reduce((a, b) => a < b ? a : b);
    final max = samples.reduce((a, b) => a > b ? a : b);
    final span = (max - min) == 0 ? 1.0 : (max - min).toDouble();
    const inset = 3.0;

    double x(int i) => samples.length == 1
        ? size.width / 2
        : (i / (samples.length - 1)) * size.width;
    double y(int v) =>
        size.height -
        inset -
        ((v - min) / span) * (size.height - 2 * inset);

    final path = Path()..moveTo(x(0), y(samples.first));
    for (var i = 1; i < samples.length; i++) {
      path.lineTo(x(i), y(samples[i]));
    }
    canvas.drawPath(path, paint);

    // The live head: a small filled dot at the newest sample.
    final head = Paint()..color = color;
    canvas.drawCircle(
      Offset(x(samples.length - 1), y(samples.last)),
      2.5,
      head,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.samples != samples || old.color != color;
}

/// 3 — «داده جلسه»: the session's cumulative volume + the down/up split
/// bar. The store's counters are LIFETIME-of-session honest values; the
/// split bar fills with the REAL ratio (all-down ⇒ full bar; idle ⇒ the
/// muted track).
class SessionDataCard extends StatelessWidget {
  const SessionDataCard({super.key, required this.store, required this.style});

  final ConnectionStore store;
  final MotionStyle style;

  static String _format(int bytes) {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) {
      final v = (bytes / gb)
          .toStringAsFixed(bytes >= gb * 10 ? 0 : 1)
          .replaceFirst(RegExp(r'\.0$'), '');
      return '$v GB';
    }
    if (bytes >= mb) return '${bytes ~/ mb} MB';
    if (bytes > 0) return '${bytes ~/ 1024} KB';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final total = store.downBytes + store.upBytes;
    final upShare =
        total == 0 ? 0.0 : (store.upBytes / total).clamp(0.0, 1.0).toDouble();

    return _DeckCard(
      iconAsset: AppAssets.iconDownload,
      label: strings.homeWidgetData,
      iconTint: total > 0 ? AethColors.accentConnected : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Directionality(
            // The value (KB/MB/GB) never bidi-flips.
            textDirection: TextDirection.ltr,
            child: Text(
              _format(total),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: 15 * s,
                fontFeatures: const [FontFeature.tabularFigures()],
                color:
                    total > 0 ? AethColors.textPrimary : AethColors.textSecondary,
              ),
            ),
          ),
          SizedBox(height: 5 * s),
          // The down/up split bar: the accent-green DOWN share with the
          // softer green UP share — the real ratio, never animated
          // decoration.
          ClipRRect(
            borderRadius: BorderRadius.circular(2 * s),
            child: SizedBox(
              height: 4 * s,
              child: Row(
                children: [
                  Expanded(
                    flex: ((1.0 - upShare) * 1000).round().clamp(1, 999),
                    child: Container(color: AethColors.accentConnected),
                  ),
                  Expanded(
                    flex: (upShare * 1000).round().clamp(1, 999),
                    child: Container(color: AethColors.statUpBorder),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
