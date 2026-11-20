/// Bottom panel — v4.10 pixel-faithful rewrite (measured on the reference
/// frames حالت متصل/غیر متصل-ضاهر1, 402×874):
///
///   protocol card  x 33–298, y 706–768 (62 tall, r16, #0F1511)
///     [white protocol logo, no box] · [protocol name] · [white chevron >]
///   stat cards     y 776–841 (65 tall): DOWN left (x 33–168) / UP right
///     (x 172–300); each: 48×48 icon box inset 8 + label above value
///   FAB column     x 305–370 (65×138, r20, #0F1511): the 48×48 squircle
///     power button rides the TOP slot when connected (y 712–760) and the
///     BOTTOM slot when disconnected (y 785–833); three tiny red chevrons
///     sit near the bottom, hidden behind the button when it is down.
///
/// The whole panel is directionality-locked LTR: the reference arrangement
/// (DOWN left, UP right, FAB column on the right edge) is a fixed visual
/// layout — under the Persian RTL locale the first build mirrored it, which
/// was one of the worst device defects. Latin stat labels/values are
/// LTR-locked so «DOWN:» and «145 MB» can never bidi-flip.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_state.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../core/motion_widgets.dart';
import '../../shared/protocol_glyph.dart';

class BottomPanel extends StatelessWidget {
  const BottomPanel({
    super.key,
    required this.connected,
    required this.style,
    required this.selectedProtocol,
    required this.protocolLabel,
    required this.downBytes,
    required this.upBytes,
    required this.showConnectButton,
    required this.onProtocolCardTap,
    required this.onConnect,
    required this.onDisconnect,
    this.state,
  });

  final bool connected;
  final MotionStyle style;

  /// v1.0.2 — the REAL VPN state, threaded to [FabColumn]'s three-slot
  /// ride (top = connected, middle = walking, bottom = rest). Optional:
  /// null keeps the v4.x binary behaviour verbatim.
  final VpnState? state;

  /// v4.35 — the committed protocol as an ID (the glyph renderer owns the
  /// asset, the theme ink and the combined modes' drop shadow).
  final ProtocolId selectedProtocol;
  final String protocolLabel;
  final int downBytes;
  final int upBytes;

  /// Look 1 renders the bottom connect button; look 2 does not.
  final bool showConnectButton;
  final VoidCallback onProtocolCardTap;

  /// Tap-to-toggle connect actions (owner v4.12: «دکمه اتصال رو به حالت
  /// کلیک قبلش برگردون، نمیخوام حالت سوییپ داشته باشه» — the v4.11
  /// swipe-only interaction is reverted): the FAB tap connects when
  /// disconnected and disconnects when connected.
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    if (!showConnectButton) {
      // Look 2: no FAB column — the center button owns connect/disconnect.
      return Directionality(
        textDirection: TextDirection.ltr,
        child: _CardsColumn(
          connected: connected,
          style: style,
          selectedProtocol: selectedProtocol,
          protocolLabel: protocolLabel,
          downBytes: downBytes,
          upBytes: upBytes,
          onProtocolCardTap: onProtocolCardTap,
        ),
      );
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _CardsColumn(
              connected: connected,
              style: style,
              selectedProtocol: selectedProtocol,
              protocolLabel: protocolLabel,
              downBytes: downBytes,
              upBytes: upBytes,
              onProtocolCardTap: onProtocolCardTap,
            ),
          ),
          SizedBox(width: 7 * s),
          FabColumn(
            connected: connected,
            style: style,
            state: state,
            onConnect: onConnect,
            onDisconnect: onDisconnect,
          ),
        ],
      ),
    );
  }

  /// MB display like the reference («145 MB»); sub-MB shows 0 MB — honest
  /// cumulative counters, no fabricated values.
  static String formatBytes(int bytes) {
    final mb = bytes ~/ (1024 * 1024);
    return '$mb MB';
  }
}

class _CardsColumn extends StatelessWidget {
  const _CardsColumn({
    required this.connected,
    required this.style,
    required this.selectedProtocol,
    required this.protocolLabel,
    required this.downBytes,
    required this.upBytes,
    required this.onProtocolCardTap,
  });

  final bool connected;
  final MotionStyle style;

  /// v4.35 — the committed protocol as an ID (the glyph renderer owns the
  /// asset, the theme ink and the combined modes' drop shadow).
  final ProtocolId selectedProtocol;
  final String protocolLabel;
  final int downBytes;
  final int upBytes;
  final VoidCallback onProtocolCardTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProtocolCard(
          protocol: selectedProtocol,
          label: protocolLabel,
          onTap: onProtocolCardTap,
        ),
        SizedBox(height: 8 * s),
        Row(
          children: [
            Expanded(
              child: StatCard(
                iconAsset: AppAssets.iconGraphDown,
                iconBoxColor: AethColors.statDownBg,
                label: 'DOWN:',
                valueText: BottomPanel.formatBytes(downBytes),
                style: style,
              ),
            ),
            SizedBox(width: 8 * s),
            Expanded(
              child: StatCard(
                iconAsset: AppAssets.iconGraphUp,
                iconBoxColor: AethColors.statUpBg,
                iconBoxBorder: AethColors.statUpBorder,
                label: 'UP:',
                valueText: BottomPanel.formatBytes(upBytes),
                style: style,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Protocol selector card — [logo] [name centered in the remaining space]
/// [white forward chevron]. The logo renders straight on the card (the
/// reference has NO backing box).
///
/// v4.35 (owner round 11, items 4/5) — the logo renders through the shared
/// [ProtocolGlyph]: theme ink (white at night / #141C16 in light) and the
/// combined modes' rebuilt drop shadow. (v4.17 history: the Tor/Psiphon
/// raster logos carry BLACK ink and were tinted white; the chain SVGs
/// rendered filter-less white art — both now own their theme treatment in
/// one place.)
class ProtocolCard extends StatelessWidget {
  const ProtocolCard({
    super.key,
    required this.protocol,
    required this.label,
    required this.onTap,
  });

  final ProtocolId protocol;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AethRadius.card * s),
        child: Container(
          height: AethGeometry.protocolCardHeight * s,
          decoration: BoxDecoration(
            color: AethColors.cardDark,
            borderRadius: BorderRadius.circular(AethRadius.card * s),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14 * s),
          child: Row(
            children: [
              SizedBox(
                width: AethGeometry.protocolLogoSize * s,
                height: AethGeometry.protocolLogoSize * s,
                child: Center(
                  // v4.35 — the shared theme-aware glyph (ink + shadow).
                  child: ProtocolGlyph(id: protocol, size: 24 * s),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w600,
                      fontSize: 15 * s,
                      color: AethColors.textPrimary,
                    ),
                  ),
                ),
              ),
              // Owner defect #12: the forward chevron is the set's own
              // «Right 2.svg» artwork, white-tinted like the reference card.
              SvgPicture.asset(
                AppAssets.iconRight2,
                width: 26 * s,
                height: 26 * s,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  AethColors.textPrimary,
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

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.iconAsset,
    required this.iconBoxColor,
    required this.label,
    required this.valueText,
    this.iconBoxBorder,
    this.style = MotionStyle.standard,
  });

  final String iconAsset;
  final Color iconBoxColor;
  final String label;

  /// v1.0.2 — the value crossfades through the shared [AnimatedValueText]
  /// (a raw swap popped before; the audit's «عددها میپرند» finding). The
  /// child key IS the text, so a stats tick with the same bytes animates
  /// nothing, and exactly ONE [Text] renders per frame for `find.text`.
  final String valueText;
  final Color? iconBoxBorder;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Container(
      height: AethGeometry.statCardHeight * s,
      decoration: BoxDecoration(
        color: AethColors.cardDark,
        borderRadius: BorderRadius.circular(AethRadius.card * s),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8 * s),
      child: Row(
        children: [
          Container(
            width: AethGeometry.statIconBoxSize * s,
            height: AethGeometry.statIconBoxSize * s,
            decoration: BoxDecoration(
              color: iconBoxColor,
              borderRadius: BorderRadius.circular(10 * s),
              border: iconBoxBorder != null
                  ? Border.all(color: iconBoxBorder!)
                  : null,
            ),
            padding: EdgeInsets.all(10 * s),
            child: SvgPicture.asset(
              iconAsset,
              colorFilter: ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
          SizedBox(width: 10 * s),
          // LTR-locked: «DOWN:» over «145 MB», never bidi-flipped.
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
                        fontSize: 10 * s,
                        letterSpacing: 0.5,
                        color: AethColors.textSecondary,
                      ),
                    ),
                    // v1.0.2 — the value swap crossfades (asymmetric fade +
                    // micro-rise), never pops. LTR-locked like the label.
                    AnimatedValueText(
                      valueText,
                      style: style,
                      textDirection: TextDirection.ltr,
                      textStyle: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w700,
                        fontSize: 14 * s,
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

/// The look-1 right column: dark squircle container + the power button that
/// rides the slot the REAL state owns (v1.0.2 motion overhaul — was a binary
/// top/bottom flip on `connected`):
///
///   connected    → TOP slot (the power sits at the summit, green)
///   walking      → MIDDLE slot with the state's own micro-rhythm:
///                  starting  = the slot jump itself (the small leap)
///                  waiting   = a calm, slow breath (the held tap)
///                  connecting= a fine vertical tremor (the march's echo)
///                  reconnect = a double pulse per period (the seek echo)
///   disconnecting→ glides DOWN to the bottom slot (the soft descent)
///   disconnected / failed → BOTTOM slot (the resting pose)
///
/// v4.15 (owner home round #4: «سه فلش رو به بالا در بخش دکمه اتصال کلا حذف
/// شود») — the three up-chevrons are gone in EVERY state. Owner v4.12 (kept):
/// plain tap toggles; the slot slide + color crossfade + icon swap stay
/// animated. v1.0.2: the press is the shared real [PressSpring] and while
/// DISCONNECTING the tap is a deliberate no-op (one transition is already
/// in flight — the collapse narrates; the home toggle agrees).
///
/// [state] is optional (the onboarding preview mounts the column without
/// one) — null keeps the v4.x binary top/bottom behaviour verbatim.
class FabColumn extends StatelessWidget {
  const FabColumn({
    super.key,
    required this.connected,
    required this.style,
    required this.onConnect,
    required this.onDisconnect,
    this.state,
  });

  final bool connected;
  final MotionStyle style;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  /// The REAL VPN state — drives the three-slot ride + the busy rhythm.
  final VpnState? state;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.state);
    final size = AethGeometry.connectButtonSize * s;
    final color = connected
        ? AethColors.accentConnected
        : AethColors.statusDisconnected;
    final effective =
        state ?? (connected ? VpnState.connected : VpnState.disconnected);
    final locked = effective == VpnState.disconnecting;
    final toggle = connected ? onDisconnect : onConnect;

    // The three slots (v4.10 geometry: top 5, bottom 12; the middle slot
    // centers the button in the 138-tall column).
    final double slotTop = switch (effective) {
      VpnState.connected => 5,
      VpnState.disconnected ||
      VpnState.failed ||
      VpnState.disconnecting => AethGeometry.fabColumnHeight -
          AethGeometry.connectButtonSize -
          12,
      _ => (AethGeometry.fabColumnHeight - AethGeometry.connectButtonSize) / 2,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked ? null : toggle,
      child: SizedBox(
        width: AethGeometry.fabColumnWidth * s,
        height: AethGeometry.fabColumnHeight * s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The visible column (v4.10 geometry, unchanged).
            Container(
              width: AethGeometry.fabColumnWidth * s,
              height: AethGeometry.fabColumnHeight * s,
              decoration: BoxDecoration(
                color: AethColors.cardDark,
                borderRadius: BorderRadius.circular(AethRadius.fabColumn * s),
              ),
            ),
            // Column content.
            Stack(
              clipBehavior: Clip.none,
              children: [
                // v4.15 #4: the three up-chevrons are REMOVED entirely
                // (owner: «سه فلش رو به بالا در بخش دکمه اتصال کلا حذف
                // شود») — nothing else lives in the column besides the
                // power button.
                // Power button — NO glow (the reference frames show none).
                // Icon = the set's own «Off.svg» (owner defect #2). The
                // slot ride is state-driven (v1.0.2); the busy states add
                // their own micro-rhythm through [_FabRhythm].
                AnimatedPositioned(
                  left: (AethGeometry.fabColumnWidth * s - size) / 2,
                  top: slotTop * s,
                  duration: duration,
                  curve: style.curve,
                  child: _FabRhythm(
                    state: effective,
                    style: style,
                    child: PressSpring(
                      style: style,
                      onTap: locked ? null : toggle,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: style.curve,
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(AethRadius.fab * s),
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: duration,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.7,
                                  end: 1.0,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: SvgPicture.asset(
                              AppAssets.iconOff,
                              key: ValueKey(connected ? 'fab-on' : 'fab-off'),
                              width: 24 * s,
                              height: 24 * s,
                              fit: BoxFit.contain,
                              colorFilter: ColorFilter.mode(
                                connected
                                    ? AethColors.onPillConnected
                                    : AethColors.onPillDisconnected,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Invisible EXTENDED hit area around the whole section (8 px
            // sides / 6 px top-bottom): taps on the column's background and
            // its immediate surroundings toggle too — owner round-4 #4. The
            // out-of-bounds sibling keeps the layout box pixel-exact.
            Positioned(
              left: -8 * s,
              right: -8 * s,
              top: -6 * s,
              bottom: -6 * s,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: locked ? null : toggle,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The busy states' micro-rhythm for the FAB power button (v1.0.2) — the
/// SAME tempos the [ConnectHalo] behind the hero plays, echoed small on
/// the panel: waiting breathes on [MotionRecipe.connectHoldMs], connecting
/// tremors finely on [connectMarchMs], reconnecting double-pulses on
/// [connectSeekMs]. One controller, retuned per state; stops dead outside
/// the busy states and under MotionStyle.off (nothing idles invisibly).
class _FabRhythm extends StatefulWidget {
  const _FabRhythm({
    required this.state,
    required this.style,
    required this.child,
  });

  final VpnState state;
  final MotionStyle style;
  final Widget child;

  @override
  State<_FabRhythm> createState() => _FabRhythmState();
}

class _FabRhythmState extends State<_FabRhythm> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _retune();
  }

  @override
  void didUpdateWidget(covariant _FabRhythm old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state || old.style != widget.style) _retune();
  }

  void _retune() {
    final r = widget.style.recipe;
    final ms = switch (widget.state) {
      VpnState.connecting => r.connectMarchMs,
      VpnState.reconnecting => r.connectSeekMs,
      VpnState.waitingForPermissions => r.connectHoldMs,
      _ => 0, // starting's leap is the slot ride itself; the rest are still
    };
    if (ms > 0 && widget.style != MotionStyle.off) {
      _c.duration = Duration(milliseconds: ms);
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == MotionStyle.off || !_c.isAnimating) {
      return widget.child;
    }
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        var dy = 0.0;
        var scale = 1.0;
        switch (widget.state) {
          // CONNECTING — a fine vertical tremor, two beats per march loop.
          case VpnState.connecting:
            dy = math.sin(t * 2 * math.pi * 2) * 1.2 * s;
          // WAITING — the held tap: a slow, calm breath (≤1.5%).
          case VpnState.waitingForPermissions:
            final b = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
            scale = 1 + 0.015 * b;
          // RECONNECTING — the seek's double pulse, echoed small.
          case VpnState.reconnecting:
            double bump(double m) => math.exp(-math.pow((t - m) / 0.09, 2));
            final p = math.max(bump(0.18), 0.65 * bump(0.42));
            scale = 1 + 0.03 * p;
          default:
            break;
        }
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}
