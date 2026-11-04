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
import 'package:flutter/services.dart';
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
  /// frame). v4.17 — owner settings round #4: «به صفحه و کارت ها انیمیشن
  /// ورود و خروج اضافه کن» — the route is a fade+slide PageRouteBuilder and
  /// the screen staggers its blocks on the route timeline (see
  /// [SettingsScreen._enter]); pop retraces the cascade.
  void _openSettings(BuildContext context) {
    final style = store.effectiveMotionStyle(context);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: motionDuration(style, 380),
        reverseTransitionDuration: motionDuration(style, 320),
        pageBuilder: (_, _, _) => SettingsScreen(store: store),
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
      ),
    );
  }

  /// v4.19 — the REAL protocol-selection PAGE (promoted from the v4.16
  /// floating sheet per the owner: «در یک صفحه جدا مثل صفحه اصلی تنظیمات
  /// قرار بدیم»). Selecting a protocol auto-returns here (owner: «بعد از
  /// انتخاب پروتکل به صورت خودکار کاربر باید به صفحه اول بازگردد»).
  void _openProtocolPage(BuildContext context) {
    Navigator.of(context).push(
      protocolPageRoute(store: store, style: store.effectiveMotionStyle(context)),
    );
  }

  /// v4.19 (#3) — tap-to-cancel, owner device test: «حین اتصال کاربر باید
  /// بتونه اتصال رو کنسل کنه». Every connect surface (hero logo, look-2
  /// center button, bottom FAB) routes through THIS toggle: while the
  /// engine walk is in flight a tap CANCELS the pending connection (the
  /// store's canceling disconnect — legal edges starting/…/connecting →
  /// disconnecting), instead of being silently ignored by the old
  /// single-flight guard.
  void _toggleConnection() {
    switch (store.state) {
      case VpnState.starting:
      case VpnState.waitingForPermissions:
      case VpnState.connecting:
      case VpnState.connected:
        store.disconnect();
      case VpnState.failed:
      case VpnState.reconnecting:
      case VpnState.disconnected:
        store.connect();
      case VpnState.disconnecting:
        break; // one transition already in flight — ignore
    }
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
                      // v4.21 — the band rule follows the committed mode
                      // (single-knob selection after the v4.20 revert).
                      protocolIsTorOrPsiphon:
                          store.effectiveProtocol.isTor ||
                          store.effectiveProtocol.isPsiphon,
                      // v4.21 — the wheel is a real, scrollable SELECTOR
                      // for the whole psiphon + tor families while
                      // DISCONNECTED, and locks on the connected location
                      // once connected (owner device-test round 3).
                      selectable: store.wheelSelectable,
                      allowedCodes: store.wheelAllowedCodes,
                      autoEntry: store.wheelAutoEntry,
                      anchorCode: store.wheelAnchorCode,
                      pingMs: store.pingMs,
                      exitCountryCode: store.exitCountryCode,
                      // Wheel selection commit — the store routes the pick
                      // into the current family's remembered location.
                      onCountrySelected: store.selectLocation,
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
                              GestureDetector(
                                // v4.17 — owner home round #5: «آیکون وسط
                                // صفحه هم به عنوان دکمه اتصال عمل کنه البته
                                // دکمه اتصال هم همچنان عملکردش رو داشته
                                // باشه» — the logo toggles the connection
                                // exactly like the bottom FAB. v4.19 (#3):
                                // the toggle now CANCELS the in-flight walk
                                // instead of being ignored while connecting.
                                behavior: HitTestBehavior.opaque,
                                onTap: _toggleConnection,
                                child: HeroLogo(
                                  connected: connected,
                                  style: style,
                                ),
                              )
                            else
                              _CenterConnectButton(
                                store: store,
                                style: style,
                                onTap: _toggleConnection,
                              ),
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
                    // v4.20 — the failed state names its stage: the engine's
                    // own error code rides under the pill (tap = full details
                    // + copy). A device failure can now be REPORTED without
                    // adb (owner: the tunnel failure was an anonymous miss).
                    AnimatedSize(
                      duration: motionDuration(
                        style,
                        MotionDurations.quick,
                      ),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: store.state == VpnState.failed &&
                              store.lastErrorCode != null
                          ? Padding(
                              padding: EdgeInsets.only(top: 8 * s),
                              child: _FailureCaption(
                                code: store.lastErrorCode!,
                                message: store.lastErrorMessage,
                                onTap: () => _openFailureDetails(
                                  context,
                                  store.lastErrorCode!,
                                  store.lastErrorMessage,
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
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
                          store.effectiveProtocol,
                        ),
                        protocolLabel: strings.protocolName(
                          store.effectiveProtocol,
                        ),
                        downBytes: store.downBytes,
                        upBytes: store.upBytes,
                        showConnectButton: isLookOne,
                        onProtocolCardTap: () => _openProtocolPage(context),
                        // Tap connect (owner v4.12: «دکمه اتصال رو به حالت
                        // کلیک قبلش برگردون، نمیخوام حالت سوییپ داشته باشه»)
                        // — the FAB toggles: tap connects, tap again
                        // disconnects. The center look-2 button behaves the
                        // same. v4.19 (#3): both handlers route through the
                        // tap-to-cancel toggle — during the engine walk a
                        // tap cancels the pending connection.
                        onConnect: _toggleConnection,
                        onDisconnect: _toggleConnection,
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

  /// v4.20 — the failure details sheet: the engine's own error code + full
  /// message, with a copy button so the owner can hand the exact stage over
  /// (the tunnel failure was previously an anonymous miss: «اپ هنوز هم در
  /// حالت تونل مشکل داره و وصل نمیشه»).
  void _openFailureDetails(
    BuildContext context,
    String code,
    String? message,
  ) {
    final strings = AppStrings.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AethColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
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
              strings.failureDetailsTitle,
              style: const TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AethColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              code,
              style: const TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AethColors.statusDisconnected,
              ),
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  height: 1.6,
                  color: AethColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: '$code\n${message ?? ''}'),
                );
                Navigator.of(sheetContext).pop();
              },
              icon: const Icon(
                Icons.copy_rounded,
                size: 18,
                color: AethColors.accentConnected,
              ),
              label: Text(
                strings.failureDetailsCopy,
                style: const TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: AethColors.accentConnected,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// v4.20 — the failed state's honest caption under the status pill: the
/// engine's own error code («کد خطا: tunnelStartFailed»), tappable for the
/// full details sheet. Rendered ONLY in the failed state; AnimatedSize in
/// [HomeScreen] keeps the layout shift soft.
class _FailureCaption extends StatelessWidget {
  const _FailureCaption({
    required this.code,
    this.message,
    this.onTap,
  });

  final String code;
  final String? message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        '${strings.failureCodeLabel}: $code',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'IRANYekanX',
          fontWeight: FontWeight.w500,
          fontSize: 11 * s,
          height: 1.4,
          color: AethColors.statusDisconnected.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Look 2: the hero IS the connect button (112px core, 4-layer glow) with
/// the set's real Off.svg icon. Owner v4.12: back to CLICK — a tap toggles
/// (connect when disconnected, disconnect when connected); the swipe-only
/// interaction from defect #11 is reverted. v4.19 (#3): the toggle logic
/// lives in [HomeScreen._toggleConnection] (tap-to-cancel during the walk).
class _CenterConnectButton extends StatelessWidget {
  const _CenterConnectButton({
    required this.store,
    required this.style,
    required this.onTap,
  });

  final ConnectionStore store;
  final MotionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final connected = store.isConnected;
    final duration = motionDuration(style, MotionDurations.state);

    return GlowCircle(
      active: connected,
      duration: duration,
      curve: style.curve,
      onTap: onTap, // tap-to-toggle (owner v4.12) + cancel (v4.19 #3)
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
