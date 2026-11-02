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

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import 'custom_icons.dart';

class BottomPanel extends StatelessWidget {
  const BottomPanel({
    super.key,
    required this.connected,
    required this.style,
    required this.selectedProtocolIcon,
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
  final String selectedProtocolIcon;
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
          selectedProtocolIcon: selectedProtocolIcon,
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
              selectedProtocolIcon: selectedProtocolIcon,
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
}

class _CardsColumn extends StatelessWidget {
  const _CardsColumn({
    required this.connected,
    required this.style,
    required this.selectedProtocolIcon,
    required this.protocolLabel,
    required this.downBytes,
    required this.upBytes,
    required this.onProtocolCardTap,
  });

  final bool connected;
  final MotionStyle style;
  final String selectedProtocolIcon;
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
          iconAsset: selectedProtocolIcon,
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

/// Protocol selector card — [white logo] [name centered in the remaining
/// space] [white forward chevron]. The logo renders straight on the card
/// (the reference has NO backing box).
class ProtocolCard extends StatelessWidget {
  const ProtocolCard({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.onTap,
  });

  final String iconAsset;
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
                  child: AppAssets.isRasterAsset(iconAsset)
                      ? Image.asset(
                          iconAsset,
                          height: 24 * s,
                          fit: BoxFit.contain,
                        )
                      : SvgPicture.asset(
                          iconAsset,
                          height: 24 * s,
                          fit: BoxFit.contain,
                        ),
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
                colorFilter: const ColorFilter.mode(
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
              colorFilter: const ColorFilter.mode(
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
/// (disconnected) + three tiny red chevrons pinned near the bottom (covered
/// by the button in its lower position, exactly like the reference frames).
///
/// Owner v4.12: back to CLICK — a plain tap toggles (connect when
/// disconnected, disconnect when connected); the v4.11 swipe-only rule is
/// reverted. The slot slide + color crossfade + icon swap stay animated
/// (defect #5).
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: connected ? onDisconnect : onConnect,
      child: Container(
        width: AethGeometry.fabColumnWidth * s,
        height: AethGeometry.fabColumnHeight * s,
        decoration: BoxDecoration(
          color: AethColors.cardDark,
          borderRadius: BorderRadius.circular(AethRadius.fabColumn * s),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Chevrons first (under the button).
            Positioned(
              left: 0,
              right: 0,
              bottom: 25 * s,
              child: Center(
                child: TripleChevronsIcon(
                  size: 14 * s,
                  color: AethColors.fabChevrons,
                ),
              ),
            ),
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
                    transitionBuilder: (child, animation) => FadeTransition(
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
      ),
    );
  }
}
