/// The home "glow" family — status pill, Speed Test button and the look-2
/// circular connect button.
///
/// v5 (owner round 19, the «نمای 2» redesign) — all three compositions are
/// re-cut from the owner's NEW committed CSS (the ZIP frames «نمای 2-متصل»
/// and «نمای 2-قطع», 402×874 @3×):
///
/// Status pill («Group 8»/«لایه 1») — ONE solid gradient layer, 126×30 r9:
///   connected    linear-gradient(266.14deg, #2FF8B1 → #1AD995)
///                (right-light → left-deep; pixel-verified on the frame)
///   disconnected linear-gradient(180deg, #FF5B5E → #FF383C)
///   content: the Shield Tick glyph 20×20 + the 16px/600 label, both WHITE
///   («color: #FFFFFF»). The v4.11 three-layer halo stack + the soft green
///   under-shadow are RETIRED — the redesign pill is a single crisp chip.
///
/// Speed Test («Group 13») — three crisp layers, no blurred glow:
///   74×74 r32 rgba(26,217,149,.19) / 62×62 r27 rgba(26,217,149,.45) /
///   44×44 r17 #1AD995 + the Activity 4 glyph 28×28 in WHITE.
///   Disconnected («حالت قطع»): the SAME geometry on the idle family —
///   rgba(17,0,0,.19) / rgba(17,0,0,.45) / #363636 — the button stays on
///   screen in a dark, disabled pose (the old build hid it entirely).
///
/// Connect button («Group 45», re-cut round 23) — three crisp squircles:
///   «3» 160×160 r62, rgba(47,248,177,0.16) connected /
///       rgba(234,35,35,0.16) disconnected
///   «4» 132×132 r46, rgba(47,248,177,0.45) / rgba(234,35,35,0.45)
///   «1» 108.17² r41, gradient 180deg #2FF8B1→#1AD995 (connected) /
///       #FF5B5E→#FF383C (disconnected)
///   Off glyph 48×48, 3.5px WHITE in both states.
///
/// v6 (owner round 23) — the LOOK-1 status pill is its OWN composition
/// (the new CSS «Group 119», 140×38 at left:131 top:605): the THREE-LAYER
/// chip — 140×38 r13 rgba(26,217,149,.19) · 132.88×32 r11
/// rgba(26,217,149,.45) · 125.76×26 r9 with the FLAT #1AD995 core when
/// connected; the same geometry on the red family (rgba(234,35,35,α) +
/// the 180° red gradient core) when not, the content ink on the palette's
/// own pill members and the Shield stroke #800000 on red.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_state.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/fx/tap_ripple.dart';
import '../../../core/motion.dart';
import '../../../core/motion_widgets.dart';
import '../../../l10n/app_strings.dart';
import 'connect_core.dart';

/// One concentric layer of a glow group.
class LayerSpec {
  const LayerSpec({
    required this.width,
    required this.height,
    required this.radius,
    required this.opacity,
    this.blurSigma = 0,
    this.dy = 0,
    this.color,
    this.gradient,
  });

  /// Size in design px (scaled by [LayerStack.scale] at paint time).
  final double width;
  final double height;
  final double radius;
  final double opacity;

  /// Gaussian sigma (design px); 0 = crisp.
  final double blurSigma;

  /// Vertical offset from the group center (design px) — used by soft
  /// under-shadows.
  final double dy;

  /// v5 — an optional per-layer color override (the idle speed button's
  /// #363636 core over its rgba(17,0,0,α) halo/mid needs a second ink).
  /// Null = the stack's own [LayerStack.color].
  final Color? color;

  /// v5.2 (owner round 21) — an optional per-layer VERTICAL gradient; when
  /// set it replaces the flat color (the green/red gradient family the
  /// redesign carries on every green/red element). Equal stops paint the
  /// flat solid, so a crossfade tween can drive ONE shader end to end.
  final List<Color>? gradient;
}

/// Paints a stack of concentric rounded-rect layers, bottom-first.
class LayerStack extends StatelessWidget {
  const LayerStack({
    super.key,
    required this.scale,
    required this.color,
    required this.layers,
    this.clipOut = false,
  });

  final double scale;
  final Color color;

  /// Bottom-first layer list. The widget's layout size is taken from the
  /// LAST (topmost/core) layer.
  final List<LayerSpec> layers;

  /// When true, blur spill beyond the widget bounds is clipped.
  final bool clipOut;

  @override
  Widget build(BuildContext context) {
    final core = layers.last;
    return CustomPaint(
      size: Size(core.width * scale, core.height * scale),
      painter: _LayerStackPainter(this),
    );
  }
}

class _LayerStackPainter extends CustomPainter {
  _LayerStackPainter(this.widget);

  final LayerStack widget;

  @override
  bool shouldRepaint(_LayerStackPainter oldDelegate) =>
      oldDelegate.widget.color != widget.color ||
      oldDelegate.widget.scale != widget.scale ||
      oldDelegate.widget.layers != widget.layers;

  @override
  void paint(Canvas canvas, Size size) {
    final s = widget.scale;
    final center = Offset(size.width / 2, size.height / 2);
    for (final spec in widget.layers) {
      final rect = Rect.fromCenter(
        center: Offset(center.dx, center.dy + spec.dy * s),
        width: spec.width * s,
        height: spec.height * s,
      );
      final paint = Paint();
      final gradient = spec.gradient;
      if (gradient != null && gradient.length >= 2) {
        // v5.2 — the vertical gradient sweep (the redesign's green/red
        /// family); equal stops paint the flat solid.
        paint.shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            gradient[0].withValues(alpha: spec.opacity),
            gradient[1].withValues(alpha: spec.opacity),
          ],
        );
      } else {
        paint.color =
            (spec.color ?? widget.color).withValues(alpha: spec.opacity);
      }
      if (spec.blurSigma > 0) {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          spec.blurSigma * s,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(spec.radius * s)),
        paint,
      );
    }
  }
}

/// Status pill — TWO compositions, one widget ([layered]):
///
///  * LOOK 2 (default, `layered: false`) — the v5 single gradient chip,
///    126×30 r9, with the WHITE Shield glyph + label.
///
///  * LOOK 1 (`layered: true`, owner round 23) — the three-layer 140×38
///    chip («Group 119»): halo 140×38 r13 α.19 · mid 132.88×32 r11 α.45 ·
///    core 125.76×26 r9 (FLAT #1AD995 connected / the 180° red gradient
///    disconnected), the label is the state's own word
///    («مــتـصـل» / «غیرفعال» / «در حال اتصال» …). Round 24 — the content
///    ink is WHITE on BOTH families (the owner: «متن و آیکون دکمه نمایش
///    وضعیت اتصال باید رنگ سفید داشته باشه» — the retired palette-ink
///    pair #141C16/#75160F and the #800000 shield stroke are gone).
///
/// Content row keeps the INHERITED (RTL) directionality — under the fa
/// locale it lays out like the reference frames: text visual-left, shield
/// visual-right. The CONNECTING icon stays the set's Send glyph (v4.15
/// #6), Shield Cross for disconnected/failed/reconnecting, Shield Tick
/// when connected.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.state,
    required this.style,
    this.layered = false,
  });

  final VpnState state;
  final MotionStyle style;

  /// v6 — the LOOK-1 three-layer composition (see the class doc).
  final bool layered;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.quick);

    final connected = state == VpnState.connected;
    // v1.0.2 — all EIGHT states carry their own words + glyph (the three
    // previously-unlabelled middle states — starting / waiting / —
    // disconnecting — folded into «غیرفعال» before; the audit's dead-middle
    // finding). The glyph mapping is the ONE shared [connectGlyphFor] so
    // the pill, the center button and the halo can never disagree. v6:
    // look 1's own «غیرفعال» label (the new CSS) replaces look 2's
    // «قــطــع!» in the disconnected slot.
    final label = switch (state) {
      VpnState.connected => strings.statusConnected,
      VpnState.connecting => strings.statusConnecting,
      VpnState.starting => strings.statusStarting,
      VpnState.waitingForPermissions => strings.statusWaitingPermissions,
      VpnState.reconnecting => strings.statusReconnecting,
      VpnState.disconnecting => strings.statusDisconnecting,
      VpnState.failed => strings.statusFailed,
      VpnState.disconnected =>
        layered ? strings.statusIdle : strings.statusDisconnected,
    };
    final iconAsset = connectGlyphFor(state);

    if (layered) {
      return _LayeredStatusPill(
        connected: connected,
        label: label,
        iconAsset: iconAsset,
        duration: duration,
        curve: style.curve,
        s: s,
      );
    }

    return SizedBox(
      width: AethGeometry.pillWidth * s,
      height: AethGeometry.pillHeight * s,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AethRadius.pillCore * s),
        child: TweenAnimationBuilder<double>(
          // 0 = the red disconnected chip, 1 = the green connected one —
          // one tween drives the gradient's colors AND its axis (the green
          // sweep runs right→left at 266°, the red one top→bottom at 180°).
          tween: Tween(end: connected ? 1.0 : 0.0),
          duration: duration,
          curve: style.curve,
          builder: (context, t, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.lerp(
                  const Alignment(0, -1),
                  const Alignment(1, 0),
                  t,
                )!,
                end: Alignment.lerp(
                  const Alignment(0, 1),
                  const Alignment(-1, 0),
                  t,
                )!,
                colors: [
                  Color.lerp(
                    AethColors.pillRedFrom,
                    AethColors.pillGreenFrom,
                    t,
                  )!,
                  Color.lerp(
                    AethColors.pillRedTo,
                    AethColors.accentConnected,
                    t,
                  )!,
                ],
              ),
            ),
            child: Center(
              // FittedBox keeps any label (e.g. the longer «در حال اتصال»)
              // inside the 126-wide chip at ANY font.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Row(
                    key: ValueKey('pill-$label'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        iconAsset,
                        width: AethGeometry.pillIconSize * s,
                        height: AethGeometry.pillIconSize * s,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFFFFFFFF),
                          BlendMode.srcIn,
                        ),
                      ),
                      SizedBox(width: 8 * s),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w600,
                          fontSize: 16 * s,
                          height: 18 / 16,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// v6 (owner round 23) — the LOOK-1 three-layer status chip («Group
/// 119»): 140×38 r13 α.19 · 132.88×32 r11 α.45 · 125.76×26 r9 core, the
/// accent family rgba(26,217,149,α) when connected and rgba(234,35,35,α)
/// when not (the core FLAT #1AD995 on green, the 180° gradient on red).
/// ONE crossfade tween drives every layer; round 24 — the content ink is
/// WHITE on both families and both modes (the owner: «متن و آیکون دکمه
/// نمایش وضعیت اتصال باید رنگ سفید داشته باشه»), the retired palette
/// pill members and the #800000 shield stroke are gone.
class _LayeredStatusPill extends StatelessWidget {
  const _LayeredStatusPill({
    required this.connected,
    required this.label,
    required this.iconAsset,
    required this.duration,
    required this.curve,
    required this.s,
  });

  final bool connected;
  final String label;
  final String iconAsset;
  final Duration duration;
  final Curve curve;
  final double s;

  /// The CSS's own pair: rgba(26,217,149,α) on green, rgba(234,35,35,α)
  /// on red — α .19 ≈ 0x30, α .45 ≈ 0x73.
  static const Color _greenHalo = Color(0x301AD995);
  static const Color _greenMid = Color(0x731AD995);
  static const Color _redHalo = Color(0x30EA2323);
  static const Color _redMid = Color(0x73EA2323);

  // (Round 24 — the retired #800000 shield stroke is GONE: the content
  // ink is WHITE on both families, the owner's decree «متن و آیکون دکمه
  // نمایش وضعیت اتصال باید رنگ سفید داشته باشه».)

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AethGeometry.pillL1Width * s,
      height: AethGeometry.pillL1Height * s,
      child: TweenAnimationBuilder<double>(
        // 0 = the red family, 1 = the green one — one tween, every layer.
        tween: Tween(end: connected ? 1.0 : 0.0),
        duration: duration,
        curve: curve,
        builder: (context, t, _) => Stack(
          alignment: Alignment.center,
          children: [
            // The three crisp layers, painted centre-out (the halo is the
            // chip's own box; the layout size comes from the outer SizedBox).
            CustomPaint(
              size: Size(AethGeometry.pillL1Width * s, AethGeometry.pillL1Height * s),
              painter: _PillLayersPainter(t: t, s: s),
            ),
            // The content — round 24: WHITE icon + WHITE label on BOTH
            // families (the owner: «متن و آیکون دکمه نمایش وضعیت اتصال
            // باید رنگ سفید داشته باشه»).
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedSwitcher(
                duration: duration,
                child: Row(
                  key: ValueKey('pill-l1-$label'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      iconAsset,
                      width: AethGeometry.pillL1IconSize * s,
                      height: AethGeometry.pillL1IconSize * s,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFFFFFFFF),
                        BlendMode.srcIn,
                      ),
                    ),
                    SizedBox(width: 8 * s),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w600,
                        fontSize: 16 * s,
                        height: 18 / 16,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The look-1 pill's three rounded-rect layers (one painter, one crossfade
/// tween): the halo 140×38 r13 · the mid 132.88×32 r11 · the core 125.76×26
/// r9 — the core FLAT #1AD995 when connected, the 180° red gradient when
/// not (equal stops paint the flat solid, so one shader covers the tween).
class _PillLayersPainter extends CustomPainter {
  _PillLayersPainter({required this.t, required this.s});

  /// 0 = the red family, 1 = the green one.
  final double t;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    void layer(
      double w,
      double h,
      double r,
      Color green,
      Color red, {
      List<Color>? greenStops,
      List<Color>? redStops,
    }) {
      final rect = Rect.fromCenter(
        center: c,
        width: w * s,
        height: h * s,
      );
      final paint = Paint();
      if (greenStops != null && redStops != null) {
        paint.shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            Color.lerp(redStops[0], greenStops[0], t)!,
            Color.lerp(redStops[1], greenStops[1], t)!,
          ],
        );
      } else {
        paint.color = Color.lerp(red, green, t)!;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r * s)),
        paint,
      );
    }

    // Bottom-first: the halo, the mid, then the core on top.
    layer(
      AethGeometry.pillL1Width,
      AethGeometry.pillL1Height,
      AethRadius.pillL1Halo,
      _LayeredStatusPill._greenHalo,
      _LayeredStatusPill._redHalo,
    );
    layer(
      AethGeometry.pillL1MidWidth,
      AethGeometry.pillL1MidHeight,
      AethRadius.pillL1Mid,
      _LayeredStatusPill._greenMid,
      _LayeredStatusPill._redMid,
    );
    layer(
      AethGeometry.pillL1CoreWidth,
      AethGeometry.pillL1CoreHeight,
      AethRadius.pillL1Core,
      AethColors.accentConnected,
      AethColors.statusDisconnected,
      // The core: FLAT #1AD995 on green (the CSS's own solid), the 180°
      // red gradient on red — equal stops paint the flat solid.
      greenStops: [AethColors.accentConnected, AethColors.accentConnected],
      redStops: AethColors.redStops,
    );
  }

  @override
  bool shouldRepaint(_PillLayersPainter old) => old.t != t || old.s != s;
}

/// Speed Test entry — v5 owner CSS «Group 13»: three crisp layers
/// (74 r32 α.19 / 62 r27 α.45 / 44 r17 solid) + the Activity 4 glyph 28×28
/// in WHITE. While DISCONNECTED the button keeps its geometry but flips to
/// the idle family — light rgba(17,0,0,α) + `#363636`, night
/// rgba(66,66,66,α) + `#424242` (the owner's new dark CSS) — the dark,
/// disabled pose of the «حالت قطع» frame (it no longer vanishes).
///
/// v5.3 (the owner's decree «در هر دو نما دکمه تست سرعت باید به رنگ
/// قبلیش برگرده و گرادینت روش اعمال نشه»): the round-21 GREEN GRADIENT
/// sweep on the connected core is RETIRED — the core is the flat
/// `#1AD995` again (with the α layers at rgba(26,217,149,α)), exactly
/// the CSS pair, in BOTH looks.
class SpeedTestButton extends StatelessWidget {
  const SpeedTestButton({
    super.key,
    required this.visible,
    required this.connected,
    required this.style,
    required this.onTap,
  });

  final bool visible;
  final bool connected;
  final MotionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.state);

    // Animated appearance (scale + fade). OFF style ⇒ instant. The press
    // is the shared real spring (v1.0.2 — was a plain GestureDetector).
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: duration,
      curve: style.curve,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        child: IgnorePointer(
          // v5: the button is on screen in BOTH states (the dark idle
          // pose), but only a live tunnel can run a test — taps are dead
          // until connected. The press itself is the shared real spring
          // (v1.0.2 — was a plain GestureDetector).
          ignoring: !visible || !connected,
          child: PressSpring(
            style: style,
            onTap: onTap,
            child: SizedBox(
              width: AethGeometry.speedGroupSize * s,
              height: AethGeometry.speedGroupSize * s,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // v5.3 — flat inks on every layer (the gradient sweep is
                  // retired by the owner's decree): the accent family when
                  // connected — rgba(26,217,149,α) + the flat #1AD995 core
                  // — the idle family when not (light rgba(17,0,0,α) +
                  // #363636, night rgba(66,66,66,α) + #424242), ONE
                  // crossfade tween driving every ink.
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: connected ? 1.0 : 0.0),
                    duration: duration,
                    curve: style.curve,
                    builder: (context, t, _) {
                      final layerInk = Color.lerp(
                        AethColors.homeIdleLayer,
                        AethColors.accentConnected,
                        t,
                      )!;
                      return LayerStack(
                        scale: s,
                        color: AethColors.accentConnected,
                        layers: [
                          LayerSpec(
                            width: AethGeometry.speedGroupSize,
                            height: AethGeometry.speedGroupSize,
                            radius: AethRadius.speedHalo,
                            opacity: AethColors.pillHaloOpacity,
                            color: layerInk,
                          ),
                          LayerSpec(
                            width: AethGeometry.speedMidSize,
                            height: AethGeometry.speedMidSize,
                            radius: AethRadius.speedMid,
                            opacity: AethColors.pillMidOpacity,
                            color: layerInk,
                          ),
                          LayerSpec(
                            width: AethGeometry.speedCoreSize,
                            height: AethGeometry.speedCoreSize,
                            radius: AethRadius.speedCore,
                            opacity: 1,
                            // v5.3 — the FLAT core (the round-21 gradient is
                            // retired: «دکمه تست سرعت باید به رنگ قبلیش
                            // برگرده و گرادینت روش اعمال نشه»).
                            color: Color.lerp(
                              AethColors.homeIdleCore,
                              AethColors.accentConnected,
                              t,
                            )!,
                          ),
                        ],
                      );
                    },
                  ),
                  SvgPicture.asset(
                    AppAssets.iconActivity4,
                    width: AethGeometry.speedIconSize * s,
                    height: AethGeometry.speedIconSize * s,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      AethColors.speedIconRest, // WHITE — owner CSS vector
                      BlendMode.srcIn,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// v6 (owner round 23, the re-cut «Group 45») — the look-2 CONNECT button
/// is the THREE-LAYER composition: the outer squircle 160² r62 («3»,
/// rgba(47,248,177,.16) connected / rgba(234,35,35,.16) disconnected) ·
/// the mid 132² r46 («4», α .45 on the same pair) · the gradient core
/// 108.17² r41 («1», 180° green #2FF8B1→#1AD995 / red #FF5B5E→#FF383C) ·
/// the Off glyph 48×48 in WHITE. The layers are the accent family's own
/// constants (no theme dependence — the state owns them) and the whole
/// composition crossfades on the state edge. [scale] renders the
/// composition smaller (the look page's preview) without recomputing a
/// single layer.
///
/// v1.0.2 motion overhaul (the motion-line merge) — the press is a REAL
/// spring ([PressSpring]: fast squash down, personality-tuned
/// [SpringSimulation] return with a hair of overshoot) and the v4.43
/// tap-ripple burst rides the same pointer-down. [state] is optional for
/// the non-interactive previews (the onboarding look page), which keep
/// rendering the connected pose exactly as before. While DISCONNECTING
/// the tap is a deliberate no-op — one transition is already in flight,
/// the collapse tells the story. The glyph stays the CSS's own
/// Off (power) glyph in WHITE for both states.
///
/// Round 24 (the owner: «انیمیشن روی دکمه اتصال نمای 2 باید روی لایه های
/// خود دکمه اعمال بشه در صورتی که الان چند لایه پشت دکمه ایجاد شده و
/// روشون انیمیشن اعمال شده») — the WALK animation now rides the button's
/// OWN three layers: while the engine walks toward a session, the «3»/
/// «4»/«1» squircles themselves breathe (a staggered-free, in-phase
/// pulse — the outer layer the widest swing, the core the smallest), and
/// the round-23 [ConnectRipple] family that painted circles BEHIND the
/// button is RETIRED from the hero stack. Nothing is created behind the
/// button anymore — the button itself tells the walk story.
class ConnectButtonGlow extends StatefulWidget {
  const ConnectButtonGlow({
    super.key,
    required this.connected,
    this.onTap,
    this.scale = 1.0,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeInOutCubic,
    this.style = MotionStyle.standard,
    this.state,
  });

  final bool connected;
  final VoidCallback? onTap;

  /// 1.0 = the full 160px composition (the home hero button); the wizard's
  /// look page passes [AethGeometry.obPreviewGroupSize] / 160.
  final double scale;
  final Duration duration;
  final Curve curve;

  /// The motion personality (the press spring's tuning).
  final MotionStyle style;

  /// The REAL VPN state — drives the disconnecting tap lock (the glyph
  /// stays the round-19 CSS's own Off power glyph in both states). Null
  /// (the previews) keeps the binary behaviour.
  final VpnState? state;

  @override
  State<ConnectButtonGlow> createState() => _ConnectButtonGlowState();
}

/// v4.43 — owns the [TapRippleController] so the flutterfx tap-ripple
/// burst (owner-approved new dependency round) survives the rebuilds,
/// and round 24 — owns the WALK breath clock that pulses the button's
/// own layers while the engine walks.
class _ConnectButtonGlowState extends State<ConnectButtonGlow>
    with SingleTickerProviderStateMixin {
  /// The round-23 CSS's own state tints for the outer/mid layers:
  /// rgba(47,248,177,α) connected / rgba(234,35,35,α) disconnected (the
  /// α rides in [LayerSpec.opacity]).
  static const Color _greenOuter = Color(0xFF2FF8B1);
  static const Color _redOuter = Color(0xFFEA2323);

  final TapRippleController _ripple = TapRippleController();

  /// Round 24 — the walk breath: repeats while the engine walks, glides
  /// back to exact rest geometry when the walk resolves.
  late final AnimationController _walk = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _retuneWalk();
  }

  @override
  void didUpdateWidget(covariant ConnectButtonGlow old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state ||
        old.connected != widget.connected ||
        old.style != widget.style) {
      _retuneWalk();
    }
  }

  @override
  void dispose() {
    _walk.dispose();
    _ripple.detach();
    super.dispose();
  }

  /// The walk states (the same four the spark march / ripple family rode).
  static bool _isWalk(VpnState s) =>
      s == VpnState.starting ||
      s == VpnState.waitingForPermissions ||
      s == VpnState.connecting ||
      s == VpnState.reconnecting;

  void _retuneWalk() {
    final effective = widget.state ??
        (widget.connected ? VpnState.connected : VpnState.disconnected);
    final periodMs = widget.style.recipe.connectMarchMs;
    final run = _isWalk(effective) &&
        widget.style != MotionStyle.off &&
        periodMs > 0;
    if (run) {
      _walk.duration = Duration(milliseconds: periodMs);
      if (!_walk.isAnimating) _walk.repeat();
    } else if (widget.style == MotionStyle.off) {
      // The kill-switch: instant rest, no glide.
      _walk
        ..stop()
        ..value = 0;
    } else {
      // Leaving the walk (landed / failed / idle): glide the family back
      // to its exact rest geometry — value 0 IS rest (the triangle wave
      // rises from 0), so the settle never pops.
      if (_walk.value != 0) {
        _walk.animateTo(
          0,
          duration: motionDuration(widget.style, 260),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  /// The breath at the controller's own phase — a triangle wave eased
  /// both ways (0 → 1 → 0 across one period); value 0 = the exact rest
  /// geometry.
  double _breath() {
    if (!_walk.isAnimating) return 0;
    final phase = _walk.value;
    final up = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return Curves.easeInOut.transform(up.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.connected;
    final onTap = widget.onTap;
    final duration = widget.duration;
    final curve = widget.curve;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final k = s * widget.scale;
    final effective = widget.state ??
        (connected ? VpnState.connected : VpnState.disconnected);
    final accent =
        connected ? AethColors.accentConnected : AethColors.statusDisconnected;
    // The disconnecting lock: one transition already in flight — a tap is a
    // no-op and the press feedback stays silent (the collapse narrates).
    final tap = effective == VpnState.disconnecting ? null : onTap;

    // The tap target covers the WHOLE composition. The v4.43 ripple burst
    // rides the SAME pointer-down as the squash (one raw listener, one
    // gesture): rings spawn from the tap point the moment the finger
    // lands — pure decoration, the action itself never waits for them;
    // the disconnecting lock silences burst and tap together, and OFF
    // never mounts a listener at all.
    return PressSpring(
      style: widget.style,
      onTap: tap,
      onPointerDown: (origin) => _ripple.tapAt(origin),
      child: SizedBox(
        width: AethGeometry.connectGroupSize * k,
        height: AethGeometry.connectGroupSize * k,
        child: TapRipple(
          controller: _ripple,
          color: accent,
          duration:
              Duration(milliseconds: (duration.inMilliseconds * 1.5).round()),
          curve: curve,
          // Ring one is born on the core's own edge (108.17/2 design px,
          // style-scaled) and dies just past the outer squircle (x2.2).
          baseRadius: AethGeometry.connectCoreSize * k / 2,
          maxScale: 2.2,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // The three-layer composition («3»/«4»/«1», one crossfade
              // tween): the outer 160² r62 and the mid 132² r46 ride the
              // CSS's own state tints — rgba(47,248,177,α) connected /
              // rgba(234,35,35,α) disconnected, α .16/.45 — and the core
              // carries the 180° gradient pair. [LayerStack] paints the
              // family centre-out (its layout size is the core; the outer
              // SizedBox owns the group's own 160 box).
              //
              // ROUND 24 — while the engine walks, the button's OWN layers
              // breathe (in-phase, amplitude falling inward: the outer
              // ±8 %, the mid ±5 %, the core ±2 %, with a small opacity
              // lift on the halo pair). No layers are created behind the
              // button anymore — the retired [ConnectRipple] family is
              // gone from the hero stack.
              AnimatedBuilder(
                animation: _walk,
                builder: (context, _) {
                  final b = _breath();
                  return TweenAnimationBuilder<double>(
                    tween: Tween(end: connected ? 1.0 : 0.0),
                    duration: duration,
                    curve: curve,
                    builder: (context, t, _) => LayerStack(
                      scale: k,
                      color: accent,
                      layers: [
                        LayerSpec(
                          width: AethGeometry.connectGroupSize * (1 + 0.08 * b),
                          height:
                              AethGeometry.connectGroupSize * (1 + 0.08 * b),
                          radius: AethRadius.connectBase,
                          opacity: 0.16 + 0.08 * b,
                          color: Color.lerp(
                            _redOuter,
                            _greenOuter,
                            t,
                          )!,
                        ),
                        LayerSpec(
                          width: AethGeometry.connectMidSize * (1 + 0.05 * b),
                          height: AethGeometry.connectMidSize * (1 + 0.05 * b),
                          radius: AethRadius.connectMid,
                          opacity: 0.45 + 0.10 * b,
                          color: Color.lerp(
                            _redOuter,
                            _greenOuter,
                            t,
                          )!,
                        ),
                        LayerSpec(
                          width: AethGeometry.connectCoreSize * (1 + 0.02 * b),
                          height: AethGeometry.connectCoreSize * (1 + 0.02 * b),
                          radius: AethRadius.connectCore,
                          opacity: 1,
                          // The 180° gradient core («1»): green connected /
                          // red disconnected, crossfaded stop by stop.
                          gradient: [
                            Color.lerp(
                              AethColors.redStops[0],
                              AethColors.greenStops[0],
                              t,
                            )!,
                            Color.lerp(
                              AethColors.redStops[1],
                              AethColors.greenStops[1],
                              t,
                            )!,
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            // The Off glyph — 48×48, WHITE in both states (owner CSS
            // «border: 3.5px solid #FFFFFF»).
            SvgPicture.asset(
              AppAssets.iconOff,
              width: AethGeometry.connectIconSize * k,
              height: AethGeometry.connectIconSize * k,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                Color(0xFFFFFFFF),
                BlendMode.srcIn,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// (_TouchFeedback retired by the v1.0.2 motion overhaul — the shared
// [PressSpring] in motion_widgets.dart now carries the press for every
// connect surface: fast squash down, spring return, micro haptic. The
// v4.43 tap-ripple burst rides PressSpring's own pointer-down hook, so
// the retired class stays retired.)
