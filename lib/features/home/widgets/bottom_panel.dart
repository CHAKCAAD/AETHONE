/// Bottom panel: protocol card, DOWN/UP stat cards, and the look-1 connect
/// button (48×48, rises 72px when connected — pixel-verified 784 → 712).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
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
    required this.onConnectTap,
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
  final VoidCallback onConnectTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          // Room for the connect button column on the START side.
          padding: EdgeInsetsDirectional.only(
            start: showConnectButton ? 68 * s : 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProtocolCard(
                iconAsset: selectedProtocolIcon,
                label: protocolLabel,
                onTap: onProtocolCardTap,
              ),
              SizedBox(height: 12 * s),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      iconAsset: AppAssets.iconGraphDown,
                      iconBoxColor: AethColors.statDownBg,
                      label: 'DOWN:',
                      valueText: _formatBytes(downBytes),
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: StatCard(
                      iconAsset: AppAssets.iconGraphUp,
                      iconBoxColor: AethColors.statUpBg,
                      iconBoxBorder: AethColors.statUpBorder,
                      label: 'UP:',
                      valueText: _formatBytes(upBytes),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showConnectButton)
          AnimatedPositionedDirectional(
            start: 0,
            bottom: connected ? 92 * s : 20 * s,
            duration: motionDuration(style, MotionDurations.state),
            curve: style.curve,
            child: ConnectButton(
              connected: connected,
              style: style,
              onTap: onConnectTap,
            ),
          ),
      ],
    );
  }

  /// MB display like the reference («145 MB»); sub-MB shows 0 MB — honest
  /// cumulative counters, no fabricated values.
  static String _formatBytes(int bytes) {
    final mb = bytes ~/ (1024 * 1024);
    return '$mb MB';
  }
}

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
          height: 64 * s,
          decoration: BoxDecoration(
            color: AethColors.cardDark,
            borderRadius: BorderRadius.circular(AethRadius.card * s),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14 * s),
          child: Row(
            children: [
              Container(
                width: 40 * s,
                height: 40 * s,
                decoration: BoxDecoration(
                  color: AethColors.cardIconBg,
                  borderRadius: BorderRadius.circular(10 * s),
                ),
                padding: EdgeInsets.all(8 * s),
                child: SvgPicture.asset(iconAsset),
              ),
              SizedBox(width: 12 * s),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w600,
                  fontSize: 15 * s,
                  color: AethColors.textPrimary,
                ),
              ),
              const Spacer(),
              const ChevronDownIcon(),
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
  final Color? iconBoxBorder;
  final String label;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Container(
      height: 64 * s,
      decoration: BoxDecoration(
        color: AethColors.cardDark,
        borderRadius: BorderRadius.circular(AethRadius.card * s),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12 * s),
      child: Row(
        children: [
          Container(
            width: 36 * s,
            height: 36 * s,
            decoration: BoxDecoration(
              color: iconBoxColor,
              borderRadius: BorderRadius.circular(9 * s),
              border: iconBoxBorder != null
                  ? Border.all(color: iconBoxBorder!)
                  : null,
            ),
            padding: EdgeInsets.all(8 * s),
            child: SvgPicture.asset(
              iconAsset,
              colorFilter: const ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
          SizedBox(width: 10 * s),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
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
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w700,
                  fontSize: 15 * s,
                  color: AethColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The look-1 connect button: 48×48, red → green, power icon dark-tinted
/// (#75160F → #123E2B — owner-specified), glow behind (same family as pill).
class ConnectButton extends StatelessWidget {
  const ConnectButton({
    super.key,
    required this.connected,
    required this.style,
    required this.onTap,
  });

  final bool connected;
  final MotionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.connectButtonSize * s;
    final duration = motionDuration(style, MotionDurations.state);
    final color =
        connected ? AethColors.accentConnected : AethColors.statusDisconnected;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: duration,
        curve: style.curve,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.53),
              blurRadius: 28 * s,
              spreadRadius: 2 * s,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: duration,
            child: _PowerTinted(
              key: ValueKey(connected ? 'on' : 'off'),
              connected: connected,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerTinted extends StatelessWidget {
  const _PowerTinted({super.key, required this.connected, required this.size});

  final bool connected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        begin: connected
            ? AethColors.onPillDisconnected
            : AethColors.onPillConnected,
        end: connected
            ? AethColors.onPillConnected
            : AethColors.onPillDisconnected,
      ),
      duration: const Duration(milliseconds: 300),
      builder: (context, color, _) => PowerIcon(
        size: size,
        color: color ?? AethColors.onPillDisconnected,
      ),
    );
  }
}
