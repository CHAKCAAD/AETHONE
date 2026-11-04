/// The Speed Test page — v4.24 «صفحه تست سرعت», pixel-faithful to the three
/// committed design frames (قبل از شروع / در حال تست سرعت / اتمام تست
/// سرعت):
///
///  * chrome — the fixed pattern every page carries (owner decree): the
///    info tile (Telegram) visual LEFT, the AETHONE wordmark centered,
///    the back chevron tile visual RIGHT;
///  * title row — «تست سرعت» (the frame's own 26px) + the hexagon+wave
///    brand badge, centered as a group;
///  * the dial — 180° top semicircle (outer r108 / inner r87, round
///    caps), the 12-o'clock tick fading down, the number's right edge
///    PINNED at x221 with «Mbs» hanging at x228 (both frames pin them
///    there — the number grows LEFTWARD), the phase label
///    («پینگ»/«دانلود»/«آپلود») below — running only; the slot stays
///    reserved otherwise so nothing ever jumps;
///  * the 2×2 stat grid — Jiter/Ping (top), DOWN/UP (bottom), LTR-locked
///    visual positions like the bottom panel; the labels are the frame's
///    own Latin («Jiter:» — the frame's spelling, owner-swappable); the
///    glyphs are the frame's own: drop-with-rain (jitter), wifi arcs
///    (ping), the trend squares (DOWN/UP) — 26px like the frames;
///  * the button — the home Group 11 recipe (glow/halo/mid + core) with
///    a dark core at rest (the running frame lights it accent-green),
///    the hexagon+wave brand glyph inside, «شروع» / «شروع شده...» /
///    «شروع دوباره» (16px, the frame's own size) under it;
///  * the background — the home edge patterns behind (the owner's
///    per-page decree) at the frames' own strength (a quiet wash, 0.35×);
///  * the backend — [SpeedTestEngine] measures the REAL tunnel (SOCKS5 →
///    the selected mode's listener, the Zeptun endpoint); the gauge
///    carries the live phase value, the cards the honest cumulative
///    counters. A tap while running aborts (the tap-to-cancel family
///    rule); nothing is ever fabricated.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_store.dart';
import '../../connection/speed_test.dart';
import '../../connection/transport_modes.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import '../home/widgets/glow_pill.dart';
import '../home/widgets/pattern_sides.dart';
import '../settings/subpage_frame.dart'
    show openTelegramChannel, subpageEnter;

/// The family route (fade+slide, the settings/protocol recipe).
PageRouteBuilder<void> speedTestPageRoute({
  required ConnectionStore store,
  required MotionStyle style,
  SpeedTestEngine? engine,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: motionDuration(style, 380),
    reverseTransitionDuration: motionDuration(style, 320),
    pageBuilder: (_, _, _) =>
        SpeedTestPage(store: store, style: style, engine: engine),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      ),
    ),
  );
}

/// The three visual states of the page.
enum _RunState { idle, running, done }

class SpeedTestPage extends StatefulWidget {
  const SpeedTestPage({
    super.key,
    required this.store,
    required this.style,
    this.engine,
  });

  final ConnectionStore store;
  final MotionStyle style;

  /// Injectable for tests; the page builds a real one when null.
  final SpeedTestEngine? engine;

  @override
  State<SpeedTestPage> createState() => _SpeedTestPageState();
}

class _SpeedTestPageState extends State<SpeedTestPage> {
  late final SpeedTestEngine _engine;
  _RunState _state = _RunState.idle;
  SpeedTestSnapshot _snap = const SpeedTestSnapshot();

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? SpeedTestEngine();
    _engine.onUpdate = _onSnapshot;
  }



  void _onSnapshot(SpeedTestSnapshot snap) {
    if (!mounted) return;
    setState(() {
      _snap = snap;
      if (snap.phase != null) {
        _state = _RunState.running;
      } else if (_state == _RunState.running) {
        // Finished, aborted or failed — the same honest end; whatever
        // was measured stays on the cards, nothing invented.
        _state = _RunState.done;
      }
    });
  }

  void _tapButton() {
    switch (_state) {
      case _RunState.idle:
      case _RunState.done:
        // The page owns the pre-run reset (the engine's first fire lands
        // only after the tunnel is up — see run()'s doc).
        setState(() {
          _state = _RunState.running;
          _snap = const SpeedTestSnapshot(phase: SpeedTestPhase.ping);
        });
        _engine.run(proxyPort: _proxyPort());
      case _RunState.running:
        _engine.abort(); // tap-to-stop — the connect button's family rule
    }
  }

  /// The selected mode's own listener — the endpoint Zeptun dials; null
  /// (direct) while disconnected, the honest fallback.
  int? _proxyPort() {
    if (!widget.store.isConnected) return null;
    return TransportModes.byId(widget.store.effectiveProtocol)
        .socksEndpoint
        .port;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => Scaffold(
        backgroundColor: AethColors.bgScreen,
        body: Stack(
          children: [
            // The home patterns behind (the owner's per-page decree),
            // gated by the appearance switch; alive while a test runs —
            // at the speed frames' own quiet strength (v4.24.1: the
            // frames' wash peaks ΔL≈8–14, the home composition ≈33–40).
            if (widget.store.showPatterns)
              Positioned.fill(
                child: Opacity(
                  opacity: AethGeometry.speedPatternOpacity,
                  child: PatternSides(
                    connected: widget.store.isConnected,
                    style: widget.style,
                    active: _state == _RunState.running,
                    stage: PatternStage.home,
                  ),
                ),
              ),
            SafeArea(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          AethGeometry.pageHPadding * _scale(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: AethGeometry.topSafeExtraGap * _scale(context),
                        ),
                        subpageEnter(context, 0, const _SpeedTopBar()),
                        _gap(context, AethGeometry.speedGapTopbarToTitle),
                        subpageEnter(context, 1, const _TitleRow()),
                        _gap(context, AethGeometry.speedGapTitleToDial),
                        subpageEnter(
                          context,
                          2,
                          _DialZone(state: _state, snap: _snap),
                        ),
                        _gap(context, AethGeometry.speedGapDialToCards),
                        subpageEnter(
                          context,
                          3,
                          _StatGrid(snap: _snap, state: _state),
                        ),
                        _gap(context, AethGeometry.speedGapCardsToButton),
                        subpageEnter(
                          context,
                          4,
                          _StartButton(
                            running: _state == _RunState.running,
                            style: widget.style,
                            label: _buttonLabel(),
                            onTap: _tapButton,
                          ),
                        ),
                        SizedBox(height: 40 * _scale(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buttonLabel() {
    final strings = AppStrings.of(context);
    return switch (_state) {
      _RunState.idle => strings.speedStart,
      _RunState.running => strings.speedStarted,
      _RunState.done => strings.speedRestart,
    };
  }
}

/// The reference-pixel scale every block below uses.
double _scale(BuildContext context) =>
    MediaQuery.sizeOf(context).width / AethGeometry.refWidth;

Widget _gap(BuildContext context, double ref) =>
    SizedBox(height: ref * _scale(context));

// ---------------------------------------------------------------------
// The chrome: info tile LEFT · wordmark centered · back tile RIGHT.
// ---------------------------------------------------------------------

class _SpeedTopBar extends StatelessWidget {
  const _SpeedTopBar();

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    final tile = AethGeometry.topTileSize * s;
    return SizedBox(
      height: tile,
      child: Row(
        children: [
          _TopTile(
            key: const ValueKey('speed-info'),
            asset: AppAssets.iconInformationCircle,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Telegram channel',
            onTap: openTelegramChannel,
          ),
          const Spacer(),
          // The home wordmark lockup: the brand mark 38 behind the letters.
          Stack(
            alignment: Alignment.center,
            children: [
              SvgPicture.asset(
                AppAssets.brandMark,
                width: AethGeometry.brandMarkSize * s,
                height: AethGeometry.brandMarkSize * s,
                fit: BoxFit.contain,
              ),
              Text(
                'AETHONE',
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w700,
                  fontSize: AethGeometry.wordmarkFontSize * s,
                  letterSpacing: AethGeometry.wordmarkLetterSpacing * s,
                  color: AethColors.textPrimary,
                ),
              ),
            ],
          ),
          const Spacer(),
          _TopTile(
            key: const ValueKey('speed-back'),
            asset: AppAssets.iconRight2,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// The owner «Rectangle 9» tile — identical to the settings/home bars.
class _TopTile extends StatelessWidget {
  const _TopTile({
    super.key,
    required this.asset,
    required this.size,
    required this.iconSize,
    required this.semanticLabel,
    this.onTap,
  });

  final String asset;
  final double size;
  final double iconSize;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AethColors.topTile,
            borderRadius:
                BorderRadius.circular(AethGeometry.topTileRadius * s),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000), // rgba(0,0,0,0.25) 0 4 4
                offset: Offset(0, 4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              asset,
              width: iconSize,
              height: iconSize,
              colorFilter: const ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The title row: «تست سرعت» + the brand badge, centered as a group.
// ---------------------------------------------------------------------

class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = _scale(context);
    final badge = AethGeometry.speedTitleBadge * s;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.speedTestTitle,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              // The frame's own cut: 28px at a LIGHTER weight (its ink
              // density measures ≈18% vs w700's ≈26% — a wide, thin title).
              fontWeight: FontWeight.w500,
              fontSize: AethGeometry.speedTitleSize * s,
              color: AethColors.textPrimary,
            ),
          ),
          SizedBox(width: AethGeometry.speedTitleBadgeGap * s),
          // The frame's own badge: the hexagon+wave brand mark (the same
          // glyph that rides the start button's core), white like the
          // text — owner-swappable like every glyph on the page.
          SizedBox(
            width: badge,
            height: badge * 27 / 24, // the glyph's own aspect
            child: SvgPicture.asset(
              AppAssets.iconHexWave,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The dial zone: arc + tick + value/unit + phase label — one FIXED box.
// ---------------------------------------------------------------------

class _DialZone extends StatelessWidget {
  const _DialZone({required this.state, required this.snap});

  final _RunState state;
  final SpeedTestSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    final strings = AppStrings.of(context);
    final running = state == _RunState.running;

    final phaseLabel = switch (snap.phase) {
      SpeedTestPhase.ping => strings.speedPhasePing,
      SpeedTestPhase.download => strings.speedPhaseDownload,
      SpeedTestPhase.upload => strings.speedPhaseUpload,
      null => null,
    };

    return SizedBox(
      height: AethGeometry.speedDialZoneH * s,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 216 * s,
                height: 118.5 * s,
                child: CustomPaint(
                  painter: _DialPainter(
                    track: running
                        ? AethColors.speedTrackLive
                        : AethColors.speedTrack,
                    fill: running ? snap.liveMbps / 100 : 0,
                    tick: running
                        ? AethColors.accentConnected
                        : AethColors.speedTrack,
                  ),
                ),
              ),
            ),
          ),
          // The value row — the number's right edge PINNED (x221 ref)
          // with «Mbs» hanging after it (x228): both frames pin the unit
          // there, so the number grows LEFTWARD as it widens. The whole
          // group is right-anchored (the zone runs x33–369; the group's
          // right edge is the frame's x252).
          Positioned(
            // 92 = the frame's y365 ink minus the font's ~5px internal
            // leading (top:97 put the ink at y371).
            top: 92 * s,
            right: AethGeometry.speedValueRightInset * s,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _gaugeValue(),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w700,
                    fontSize: AethGeometry.speedValueSize * s,
                    color: AethColors.textPrimary,
                  ),
                ),
                SizedBox(width: AethGeometry.speedValueGap * s),
                Text(
                  'Mbs', // the frame's own unit spelling — owner-swappable
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w400,
                    fontSize: AethGeometry.speedUnitSize * s,
                    color: AethColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // The phase label — running only; the slot stays reserved
          // otherwise so the cards below never move.
          if (phaseLabel != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  phaseLabel,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w700,
                    fontSize: AethGeometry.speedPhaseLabelSize * s,
                    color: AethColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _gaugeValue() {
    final v = state == _RunState.running ? snap.liveMbps : 0.0;
    if (v <= 0) return '0.0';
    if (v >= 999) return '999';
    return v.toStringAsFixed(1);
  }
}

/// The dial: a 180° top semicircle (r97.5 centerline, stroke 21, round
/// caps), the fill as a sweep gradient (dark tail at 180° → bright head
/// at the leading edge — full scale 100 Mbs, the frame's own 50.4 sits
/// at half the arc), the 12-o'clock tick fading downward.
class _DialPainter extends CustomPainter {
  _DialPainter({required this.track, required this.fill, required this.tick});

  final Color track;
  final double fill; // 0..1 of the semicircle
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    const cx = 108.0; // the painter box is 216×118.5; the dial center x
    const stroke =
        AethGeometry.speedDialOuterR - AethGeometry.speedDialInnerR;
    // The centerline circle's bounding box (108±97.5) — const-friendly.
    const rect = Rect.fromLTWH(10.5, 10.5, 195, 195);

    // Track: the full 180° top semicircle (π → 2π through 12 o'clock).
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    // Fill: from the 180° end (dark tail) over the top to the head —
    // the running frame's own gradient, only when there is progress.
    final p = fill.clamp(0.0, 1.0);
    if (p > 0.004) {
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: math.pi * (1 + p),
          colors: [AethColors.speedFillTail, AethColors.speedFillHead],
        ).createShader(rect);
      canvas.drawArc(rect, math.pi, math.pi * p, false, fillPaint);
    }

    // The 12-o'clock tick: solid at its top, fading to nothing downward.
    const tickRect = Rect.fromLTWH(
      cx - AethGeometry.speedTickW / 2,
      AethGeometry.speedTickTop,
      AethGeometry.speedTickW,
      AethGeometry.speedTickH,
    );
    final tickPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [tick, tick.withValues(alpha: 0)],
      ).createShader(tickRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        tickRect,
        const Radius.circular(AethGeometry.speedTickW / 2),
      ),
      tickPaint,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.track != track || old.fill != fill || old.tick != tick;
}

// ---------------------------------------------------------------------
// The 2×2 stat grid — LTR-locked visual positions (the bottom panel's
// own rule): Jiter left / Ping right, DOWN left / UP right.
// ---------------------------------------------------------------------

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.snap, required this.state});

  final SpeedTestSnapshot snap;
  final _RunState state;

  // The frame's own glyphs — each with the frame's own size (the graphs'
  // rounded square measures 26px, the drop-with-rain and the wifi arcs
  // ≈22px; owner-swappable by editing this table):
  //   jitter (drop + rain)  -> Drop Rain (design/speed_glyphs — traced)
  //   ping (wifi arcs)      -> Wifi
  //   down (trend square)   -> Graph Down (the home panel's own pairing)
  //   up (trend square)     -> Graph Up
  static const String _jitterIcon = AppAssets.iconDropRain;
  static const String _pingIcon = AppAssets.iconWifi;
  static const String _downIcon = AppAssets.iconGraphDown;
  static const String _upIcon = AppAssets.iconGraphUp;
  static const double _jitterIconSize = AethGeometry.speedIconJitterSize;
  static const double _pingIconSize = AethGeometry.speedIconPingSize;
  static const double _graphIconSize = AethGeometry.speedIconGraphSize;

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SpeedStatCard(
                key: const ValueKey('speed-card-jitter'),
                icon: _jitterIcon,
                iconSize: _jitterIconSize,
                tileColor: AethColors.speedTileJitter,
                iconColor: AethColors.speedIconJitter,
                label: 'Jiter:', // the frame's own spelling — owner-swappable
                value: _cardValue(_CardSlot.jitter),
              ),
            ),
            SizedBox(width: AethGeometry.speedCardGapX * s),
            Expanded(
              child: _SpeedStatCard(
                key: const ValueKey('speed-card-ping'),
                icon: _pingIcon,
                iconSize: _pingIconSize,
                tileColor: AethColors.speedTilePing,
                iconColor: AethColors.speedIconPing,
                label: 'Ping:',
                value: _cardValue(_CardSlot.ping),
              ),
            ),
          ],
        ),
        SizedBox(height: AethGeometry.speedCardGapY * s),
        Row(
          children: [
            Expanded(
              child: _SpeedStatCard(
                key: const ValueKey('speed-card-down'),
                icon: _downIcon,
                iconSize: _graphIconSize,
                tileColor: AethColors.statDownBg,
                iconColor: AethColors.speedIconDown,
                label: 'DOWN:',
                value: _cardValue(_CardSlot.down),
              ),
            ),
            SizedBox(width: AethGeometry.speedCardGapX * s),
            Expanded(
              child: _SpeedStatCard(
                key: const ValueKey('speed-card-up'),
                icon: _upIcon,
                iconSize: _graphIconSize,
                tileColor: AethColors.statUpBg,
                iconColor: AethColors.speedIconUp,
                label: 'UP:',
                value: _cardValue(_CardSlot.up),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The honest slot value: measured ⇒ the number; pending mid-run ⇒ the
  /// frame's own «...»; never measured ⇒ empty (the idle frame's slots).
  String _cardValue(_CardSlot slot) {
    final running = state == _RunState.running;
    switch (slot) {
      case _CardSlot.ping:
        final v = snap.pingMs;
        if (v != null) return '$v';
        return running ? '...' : '';
      case _CardSlot.jitter:
        final v = snap.jitterMs;
        if (v != null) return '$v';
        return running ? '...' : '';
      case _CardSlot.down:
        if (snap.downBytes > 0) return _mb(snap.downBytes);
        return running ? '...' : '';
      case _CardSlot.up:
        if (snap.upBytes > 0) return _mb(snap.upBytes);
        return running ? '...' : '';
    }
  }

  /// «145 MB» — the bottom panel's own formatter.
  static String _mb(int bytes) => '${bytes ~/ (1024 * 1024)} MB';
}

enum _CardSlot { ping, jitter, down, up }

class _SpeedStatCard extends StatelessWidget {
  const _SpeedStatCard({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.tileColor,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final String icon;
  final double iconSize;
  final Color tileColor;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    final tile = AethGeometry.speedTileSize * s;
    return Container(
      height: AethGeometry.speedCardH * s,
      decoration: BoxDecoration(
        color: AethColors.cardDark,
        borderRadius: BorderRadius.circular(AethRadius.card * s),
      ),
      padding:
          EdgeInsets.symmetric(horizontal: AethGeometry.speedTileInset * s),
      child: Row(
        children: [
          Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius:
                  BorderRadius.circular(AethGeometry.speedTileRadius * s),
            ),
            child: Center(
              child: SvgPicture.asset(
                icon,
                width: iconSize * s,
                height: iconSize * s,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            ),
          ),
          SizedBox(width: AethGeometry.speedTileGap * s),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w400,
                        fontSize: AethGeometry.speedCardLabelSize * s,
                        letterSpacing: 0.5,
                        color: AethColors.textSecondary,
                      ),
                    ),
                    Text(
                      value,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w700,
                        fontSize: AethGeometry.speedCardValueSize * s,
                        color: AethColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The start button: the home Group 11 layers, a dark core at rest, the
// accent-green core while running; the label rides under the group.
// ---------------------------------------------------------------------

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.running,
    required this.style,
    required this.label,
    required this.onTap,
  });

  final bool running;
  final MotionStyle style;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    final duration = motionDuration(style, MotionDurations.state);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey('speed-start'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: AethGeometry.speedGroupSize * s,
            height: AethGeometry.speedGroupSize * s,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // The three soft layers — the frame's idle halo is a
                // quiet bloom (measured ≈#133C2C 20px out from the core),
                // never a saturated ring; running carries the full group.
                LayerStack(
                  scale: s,
                  color: AethColors.accentConnected,
                  layers: [
                    LayerSpec(
                      width: AethGeometry.speedGroupSize,
                      height: AethGeometry.speedGroupSize,
                      radius: AethRadius.speedGlow,
                      opacity: running ? 0.34 : 0.10,
                      blurSigma: AethGeometry.speedGlowBlur,
                    ),
                    LayerSpec(
                      width: AethGeometry.speedHaloSize,
                      height: AethGeometry.speedHaloSize,
                      radius: AethRadius.speedHalo,
                      opacity: running ? 0.19 : 0.05,
                    ),
                    LayerSpec(
                      width: AethGeometry.speedMidSize,
                      height: AethGeometry.speedMidSize,
                      radius: AethRadius.speedMid,
                      opacity: running ? 0.45 : 0.07,
                    ),
                    // The layout box taker (44 core) — the real core is
                    // the AnimatedContainer above it.
                    const LayerSpec(
                      width: AethGeometry.speedCoreSize,
                      height: AethGeometry.speedCoreSize,
                      radius: AethRadius.speedCore,
                      opacity: 0,
                    ),
                  ],
                ),
                // The core + the brand glyph (the hexagon+wave mark —
                // the frame's own), animated with the state.
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOut,
                  width: AethGeometry.speedCoreSize * s,
                  height: AethGeometry.speedCoreSize * s,
                  decoration: BoxDecoration(
                    color: running
                        ? AethColors.accentConnected
                        : AethColors.speedCoreRest,
                    borderRadius:
                        BorderRadius.circular(AethRadius.speedCore * s),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      AppAssets.iconHexWave,
                      width: AethGeometry.speedButtonIcon * s,
                      height: AethGeometry.speedButtonIcon * s * 27 / 24,
                      fit: BoxFit.contain,
                      colorFilter: ColorFilter.mode(
                        running
                            ? AethColors.onCoreDark
                            : AethColors.textPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The frame's label sits 2px below the glow box's bottom edge
        // (ink y787 vs box y785) — i.e. INSIDE the 96px glow box by the
        // font's own leading. A translate (not a gap) rides the ink up
        // without breaking the column's constraints.
        Transform.translate(
          offset: Offset(0, AethGeometry.speedGapButtonToLabel * s),
          child: Text(
            label,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w500,
              fontSize: AethGeometry.speedButtonLabelSize * s,
              color: AethColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
