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
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_state.dart';
import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_screen.dart';
import 'protocol_sheet/protocol_sheet.dart';
import 'widgets/bottom_panel.dart';
import 'widgets/glow_pill.dart';
import 'widgets/hero_logo.dart';
import 'widgets/location_header.dart';
import 'widgets/pattern_sides.dart';
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

  /// Step 2: the REAL settings main page (pixel-faithful to the design
  /// frame) — the placeholder sheet is gone.
  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(store: store),
      ),
    );
  }

  /// v4.16 — the REAL protocol-selection sheet (pixel-faithful to the frame
  /// «صفحه شناور انتخاب پروتکل صفحه اصلی.jpg"); the placeholder sheet is
  /// gone. Selecting a protocol auto-returns here (owner: «بعد از انتخاب
  /// پروتکل به صورت خودکار کاربر باید به صفحه اول بازگردد»).
  void _openProtocolSheet(BuildContext context) {
    Navigator.of(context).push(
      protocolSheetRoute(store: store, style: store.effectiveMotionStyle(context)),
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
        // The scanning walk: starting → connecting (→ reconnecting).
        final showScan =
            !connected &&
            (store.state == VpnState.starting ||
                store.state == VpnState.connecting ||
                store.state == VpnState.reconnecting);

        return Scaffold(
          backgroundColor: AethColors.bgScreen,
          body: Stack(
            children: [
              // Edge patterns (red ↔ green, animated crossfade; v4.15 #5:
              // they also DRIFT while the engine walks or the tunnel is up —
              // «بعد از اتصال و حین اتصال پترن های پس زمینه هم انیمیشن
              // داشته باشند»).
              Positioned.fill(
                child: PatternSides(
                  connected: connected,
                  style: style,
                  active: connected || showScan,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // v4.12: extra top gap so the app never crowds the
                    // status-bar / notch area (owner: «کمی از بالا کل اپ رو
                    // فاصله بده تا اپ وارد فرورفتگی نمایش درصد شارژ و ...
                    // گوشی نشه»).
                    SizedBox(height: AethGeometry.topSafeExtraGap * s),
                    HomeTopBar(
                      onSettings: () => _openSettings(context),
                    ),
                    SizedBox(height: AethGeometry.gapTopbarToLocation * s),
                    LocationHeader(
                      connected: connected,
                      protocolIsTorOrPsiphon:
                          store.selectedProtocol.isTor ||
                          store.selectedProtocol.isPsiphon,
                      pingMs: store.pingMs,
                      exitCountryCode: store.exitCountryCode,
                      // Wheel selection commit — the store keeps it for the
                      // future core handoff (defects #8/#13).
                      onCountrySelected: store.selectCountry,
                    ),
                    // Hero band: logo (look 1) or center connect button (2).
                    // The flex region is the reference's hero band — the
                    // logo centers exactly like the frame. While the engine
                    // walks (starting/connecting/reconnecting) the scanning
                    // halo plays BEHIND the central icon (defect #10).
                    Expanded(
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: showScan
                                  ? ScanRings(
                                      key: const ValueKey('scan-rings'),
                                      color: connected
                                          ? AethColors.accentConnected
                                          : AethColors.statusDisconnected,
                                      size: 270 * s,
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('scan-off'),
                                    ),
                            ),
                            // v4.15 connected halo — AURORA BLOOM (owner
                            // home round #2: the v4.13 rotating sweep is
                            // REPLACED by a soft breathing glow + slow
                            // water-ripples BEHIND the central icon in BOTH
                            // looks, so the connected screen keeps a quiet
                            // life. The hero adds its own breathing scale
                            // pulse.
                            AnimatedSwitcher(
                              duration: motionDuration(
                                style,
                                MotionDurations.state,
                              ),
                              child: connected
                                  ? AuroraBloom(
                                      key: const ValueKey('connected-aura'),
                                      color: AethColors.accentConnected,
                                      size:
                                          (isLookOne
                                              ? AethGeometry.heroSize
                                              : AethGeometry.centerButtonSize) *
                                          1.25 *
                                          s,
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('aura-off'),
                                    ),
                            ),
                            if (isLookOne)
                              HeroLogo(connected: connected, style: style)
                            else
                              _CenterConnectButton(store: store, style: style),
                          ],
                        ),
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
                        onProtocolCardTap: () => _openProtocolSheet(context),
                        // Tap connect (owner v4.12: «دکمه اتصال رو به حالت
                        // کلیک قبلش برگردون، نمیخوام حالت سوییپ داشته باشه»)
                        // — the FAB toggles: tap connects, tap again
                        // disconnects. The center look-2 button behaves the
                        // same.
                        onConnect: store.connect,
                        onDisconnect: store.disconnect,
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

/// Look 2: the hero IS the connect button (112px core, 4-layer glow) with
/// the set's real Off.svg icon. Owner v4.12: back to CLICK — a tap toggles
/// (connect when disconnected, disconnect when connected); the swipe-only
/// interaction from defect #11 is reverted.
class _CenterConnectButton extends StatelessWidget {
  const _CenterConnectButton({required this.store, required this.style});

  final ConnectionStore store;
  final MotionStyle style;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final connected = store.isConnected;
    final duration = motionDuration(style, MotionDurations.state);

    void toggle() => connected ? store.disconnect() : store.connect();

    return GlowCircle(
      active: connected,
      duration: duration,
      curve: style.curve,
      onTap: toggle, // tap-to-toggle (owner v4.12)
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
        builder: (context, color, _) => SvgPicture.asset(
          AppAssets.iconOff,
          width: 48 * s,
          height: 48 * s,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(
            color ?? AethColors.onPillDisconnected,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
