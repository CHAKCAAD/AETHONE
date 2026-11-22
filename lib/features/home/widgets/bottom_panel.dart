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
/// v5 («نمای 2», owner round 19) — LOOK 2 drops this card grid: the stats
/// moved up beside the Speed Test entry ([HomeStatsRow]) and the panel is
/// just the redesigned protocol card (336×62 r17, #F4F4F4 in light) on the
/// curved white sheet. LOOK 1 keeps the v4.10 arrangement untouched.
///
/// The whole panel is directionality-locked LTR: the reference arrangement
/// (DOWN left, UP right, FAB column on the right edge) is a fixed visual
/// layout — under the Persian RTL locale the first build mirrored it, which
/// was one of the worst device defects. Latin stat labels/values are
/// LTR-locked so «DOWN:» and «145 MB» can never bidi-flip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../shared/protocol_glyph.dart';
import 'glow_pill.dart';

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
  });

  final bool connected;
  final MotionStyle style;

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
      // v5 — LOOK 2: the stats moved up beside the Speed Test entry
      // ([HomeStatsRow] in the home column); the panel is the redesigned
      // protocol card alone, riding the curved sheet.
      return Directionality(
        textDirection: TextDirection.ltr,
        child: ProtocolCard(
          protocol: selectedProtocol,
          label: protocolLabel,
          onTap: onProtocolCardTap,
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

  /// v5 («نمای 2») — the look-2 stat row's own adaptive format, exactly
  /// like the committed mockups: «314KB» under a megabyte, «31.1MB» with
  /// one decimal above it (no space, per the frames). Zero shows «--».
  static String formatBytesAdaptive(int bytes) {
    if (bytes <= 0) return '--';
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes < mb) {
      return '${bytes ~/ kb}KB';
    }
    return '${(bytes / mb).toStringAsFixed(1)}MB';
  }
}

/// v5 («نمای 2») — the look-2 stats row: the DOWN/UP counters flank the
/// Speed Test entry on the curved sheet (mockup-measured: the Graph
/// glyphs 26×26 at x 34 / x 282, y 562–588, the texts 20px right of each
/// glyph; the speed group sits dead-centre). The glyphs are the icon
/// set's own «Graph Down»/«Graph Up» OUTLINES (no filled box — the v4.10
/// stat-card boxes are a look-1-only treatment), green #00D589 / red
/// #E63946 in BOTH connection states.
class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({
    super.key,
    required this.connected,
    required this.style,
    required this.downBytes,
    required this.upBytes,
    required this.onSpeedTap,
  });

  final bool connected;
  final MotionStyle style;
  final int downBytes;
  final int upBytes;

  /// Passed straight to the Speed Test entry's [SpeedTestButton.onTap].
  final VoidCallback onSpeedTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: AethGeometry.speedGroupSize * s,
        // The speed group rides the EXACT screen centre (mockup:
        // 164–238 on the 402 frame) because both stat groups take EQUAL
        // slots — DOWN hugs the left edge of its slot, UP the right edge
        // of its own.
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _StatGroup(
                    iconAsset: AppAssets.iconGraphDown,
                    label: 'DOWN:',
                    valueText: BottomPanel.formatBytesAdaptive(downBytes),
                  ),
                ),
              ),
              // v5: the entry stays on screen in BOTH states — green while
              // connected, the CSS idle family (#363636 over rgba(17,0,0,α))
              // while disconnected; taps stay dead without a tunnel.
              SpeedTestButton(
                visible: true,
                connected: connected,
                style: style,
                onTap: onSpeedTap,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _StatGroup(
                    iconAsset: AppAssets.iconGraphUp,
                    label: 'UP:',
                    valueText: BottomPanel.formatBytesAdaptive(upBytes),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One look-2 stat group: the outline Graph glyph + the two-line
/// «DOWN:»/value text block (LTR-locked, never bidi-flipped).
class _StatGroup extends StatelessWidget {
  const _StatGroup({
    required this.iconAsset,
    required this.label,
    required this.valueText,
  });

  final String iconAsset;
  final String label;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset(
          iconAsset,
          width: AethGeometry.statGlyphSize * s,
          height: AethGeometry.statGlyphSize * s,
          fit: BoxFit.contain,
          // The set's own stroke colors (#00D589 / the red family) — the
          // owner's rule: the icon files' own colors, no tinting.
        ),
        SizedBox(width: AethGeometry.statGlyphTextGap * s),
        Directionality(
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
                    fontSize: 11 * s,
                    letterSpacing: 0.5,
                    color: AethColors.textSecondary,
                  ),
                ),
                Text(
                  valueText,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
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
      ],
    );
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
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Protocol selector card — [logo] [name centered in the remaining space]
/// [forward chevron]. The logo renders straight on the card (the
/// reference has NO backing box).
///
/// v5 («نمای 2», owner CSS «Group 117»/«Rectangle 13»): 336×62,
/// `border-radius: 17px`, `background: #F4F4F4` (light — the themed card
/// family), the label 16px/400 in the theme ink and the WireGuard-class
/// glyph ~34px wide at the left end. Look 1 keeps the same redesigned
/// card (it rides the dark family at night exactly as before).
///
/// v4.35 (owner round 11, items 4/5) — the logo renders through the shared
/// [ProtocolGlyph]: theme ink (white at night / #141C16 in light) and the
/// combined modes' rebuilt drop shadow.
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
        borderRadius: BorderRadius.circular(AethRadius.protocolCard * s),
        child: Container(
          height: AethGeometry.protocolCardHeight * s,
          decoration: BoxDecoration(
            color: AethColors.cardDark,
            borderRadius: BorderRadius.circular(AethRadius.protocolCard * s),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14 * s),
          child: Row(
            children: [
              SizedBox(
                width: AethGeometry.protocolLogoSize * s,
                height: AethGeometry.protocolLogoSize * s,
                child: Center(
                  // v5 — the shared theme-aware glyph; 34 renders the CSS's
                  // ~37px-wide W at the card's left end.
                  child: ProtocolGlyph(id: protocol, size: 34 * s),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w400,
                      fontSize: 16 * s,
                      color: AethColors.textPrimary,
                    ),
                  ),
                ),
              ),
              // Owner defect #12: the forward chevron is the set's own
              // «Right 2.svg» artwork, tinted like the reference card.
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
  });

  final String iconAsset;
  final Color iconBoxColor;
  final String label;
  final String valueText;
  final Color? iconBoxBorder;

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
                    Text(
                      valueText,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
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
/// slides between the top slot (connected) and the bottom slot
/// (disconnected).
///
/// v4.15 (owner home round #4: «سه فلش رو به بالا در بخش دکمه اتصال کلا حذف
/// شود») — the three up-chevrons are gone in EVERY state (the v4.13
/// restoration of the disconnected reference pose is reverted by decree).
///
/// Owner v4.12 (kept): plain tap toggles; the slot slide + color crossfade
/// + icon swap stay animated (defect #5).
class FabColumn extends StatelessWidget {
  const FabColumn({
    super.key,
    required this.connected,
    required this.style,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connected;
  final MotionStyle style;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.state);
    final size = AethGeometry.connectButtonSize * s;
    final color = connected
        ? AethColors.accentConnected
        : AethColors.statusDisconnected;
    final toggle = connected ? onDisconnect : onConnect;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggle,
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
                // Icon = the set's own «Off.svg» (owner defect #2).
                AnimatedPositioned(
                  left: (AethGeometry.fabColumnWidth * s - size) / 2,
                  top: connected ? 5 * s : null,
                  bottom: connected ? null : 12 * s,
                  duration: duration,
                  curve: style.curve,
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
                onTap: toggle,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
