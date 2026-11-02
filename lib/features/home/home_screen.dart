/// The home screen — faithful reimplementation of the four reference frames
/// (looks 1/2 × connected/disconnected) plus the intermediate machine states.
/// Layout bands follow the pixel-verified geometry (report table 5):
///   top bar → location/flags band → hero band (logo 164dp @ 292.7/874) →
///   status pill (@594/874) → bottom panel (@~716–860).
///
/// State honesty: every visual (colors, ping, speed button, stats) derives
/// from the REAL [ConnectionStore] state — nothing shows "connected" before
/// the engine reports it (prompt §8 / report §10 rule).
library;

import 'package:flutter/material.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import 'widgets/bottom_panel.dart';
import 'widgets/custom_icons.dart';
import 'widgets/glow_pill.dart';
import 'widgets/hero_logo.dart';
import 'widgets/location_header.dart';
import 'widgets/pattern_sides.dart';
import 'widgets/status_pill.dart';
import 'widgets/top_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final ConnectionStore store;

  void _openPlaceholderSheet(BuildContext context, String message) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AethColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AethColors.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w500,
                fontSize: 15,
                color: AethColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final size = MediaQuery.sizeOf(context);
        final s = size.width / AethGeometry.refWidth;
        final style = store.effectiveMotionStyle(context);
        final connected = store.isConnected;
        final isLookOne = store.homeLook == HomeLook.one;

        return Scaffold(
          backgroundColor: AethColors.bgScreen,
          body: Stack(
            children: [
              // Edge patterns (red ↔ green, animated crossfade).
              Positioned.fill(
                child: PatternSides(connected: connected, style: style),
              ),
              SafeArea(
                child: Column(
                  children: [
                    HomeTopBar(
                      onSettings: () => _openPlaceholderSheet(
                        context,
                        strings.settingsComingNext,
                      ),
                    ),
                    SizedBox(height: AethGeometry.gapTopbarToLocation * s),
                    LocationHeader(
                      connected: connected,
                      protocolIsTorOrPsiphon:
                          store.selectedProtocol.isTor ||
                          store.selectedProtocol.isPsiphon,
                      pingMs: store.pingMs,
                      exitCountryCode: store.exitCountryCode,
                      onFlagSelected: (_) {}, // exit location = engine-owned
                    ),
                    // Hero band: logo (look 1) or center connect button (2).
                    // The flex region is the reference's hero band
                    // (y 212–534) — the logo centers exactly like the frame.
                    Expanded(
                      child: Center(
                        child: isLookOne
                            ? HeroLogo(connected: connected, style: style)
                            : _CenterConnectButton(store: store, style: style),
                      ),
                    ),
                    // Speed Test entry — connected only, animated. Its slot
                    // stays reserved when hidden so the hero never moves
                    // (both reference frames pin the logo at y≈293).
                    SpeedTestButton(
                      visible: connected,
                      style: style,
                      onTap: () => _openPlaceholderSheet(
                        context,
                        strings.speedTestComingNext,
                      ),
                    ),
                    SizedBox(height: AethGeometry.gapSpeedToPill * s),
                    StatusPill(state: store.state, style: style),
                    SizedBox(height: AethGeometry.gapPillToPanel * s),
                    Padding(
                      // Reference: the panel spans x 33–370 on the 402-wide
                      // frame (pageHPadding both sides) — NOT edge to edge.
                      padding: EdgeInsets.symmetric(
                        horizontal: AethGeometry.pageHPadding * s,
                      ),
                      child: BottomPanel(
                        connected: connected,
                        style: style,
                        selectedProtocolIcon: AppAssets.protocolIcon(
                          store.selectedProtocol,
                        ),
                        protocolLabel: strings.protocolName(
                          store.selectedProtocol,
                        ),
                        downBytes: store.downBytes,
                        upBytes: store.upBytes,
                        showConnectButton: isLookOne,
                        onProtocolCardTap: () => _openPlaceholderSheet(
                          context,
                          strings.protocolSheetComingNext,
                        ),
                        onConnectTap: () =>
                            connected ? store.disconnect() : store.connect(),
                      ),
                    ),
                    SizedBox(height: AethGeometry.gapPanelToBottom * s),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Look 2: the hero IS the connect button (112px core, 4-layer glow, power
/// icon) — owner: "دکمه وسط صفحه این کار را انجام میدهد".
class _CenterConnectButton extends StatelessWidget {
  const _CenterConnectButton({required this.store, required this.style});

  final ConnectionStore store;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final connected = store.isConnected;
    final duration = motionDuration(style, MotionDurations.state);

    return GlowCircle(
      active: connected,
      duration: duration,
      curve: style.curve,
      onTap: () => connected ? store.disconnect() : store.connect(),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: connected
              ? AethColors.onPillDisconnected
              : AethColors.onPillConnected,
          end: connected
              ? AethColors.onPillConnected
              : AethColors.onPillDisconnected,
        ),
        duration: duration,
        curve: style.curve,
        builder: (context, color, _) => PowerIcon(
          size: 48 * s,
          color: color ?? AethColors.onPillDisconnected,
        ),
      ),
    );
  }
}
