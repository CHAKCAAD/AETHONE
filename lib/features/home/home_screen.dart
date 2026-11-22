/// The home screen — LOOK 1 keeps the v4.x four-band column; LOOK 2 is the
/// v5 «نمای 2» redesign (owner round 19), pixel-cut from the committed
/// mockups «نمای 2-متصل/قطع» (402×874 @3×) and the owner's own CSS:
///
///   top bar → status pill (y 198) → connect button (160dp @ 307) →
///   the CURVED WHITE SHEET (top edge y 470, U-dip to 500, shadow
///   0 −16 95 rgba(0,0,0,.09)) carrying the stats row (y 532: DOWN ·
///   speed-test · UP) → the flag wheel (y 636) → the country row
///   (y 703) → the protocol card (y 775).
///
/// The pill sits ABOVE the hero in look 2 (the v4.x order is reversed);
/// the hero is BOTTOM-anchored in the flex band so the button's white
/// base stays glued to the sheet's crown (the merged-blob look of the
/// mockups) on every device height.
///
/// State honesty: every visual (colors, ping, speed button, stats) derives
/// from the REAL [ConnectionStore] state — nothing shows "connected" before
/// the engine reports it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection/connection_state.dart';
import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_screen.dart';
import '../speedtest/speed_test_page.dart';
import 'protocol_sheet/protocol_sheet.dart';
import 'widgets/bottom_panel.dart';
import 'widgets/glow_pill.dart';
import 'widgets/hero_logo.dart';
import 'widgets/location_header.dart';
import 'widgets/pattern_sides.dart';
import 'widgets/top_bar.dart';
import 'widgets/widget_deck.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final ConnectionStore store;

  /// v4.24 — the REAL speed test page (promoted from the v4.14
  /// placeholder sheet; pixel-faithful to the three committed frames).
  void _openSpeedTest(BuildContext context) {
    Navigator.of(context).push(
      speedTestPageRoute(
        store: store,
        style: store.effectiveMotionStyle(context),
      ),
    );
  }

  /// Step 2: the REAL settings main page (pixel-faithful to the design
  /// frame). v4.17 — owner settings round #4: «به صفحه و کارت ها انیمیشن
  /// ورود و خروج اضافه کن» — the route animates and the screen staggers
  /// its blocks on the route timeline (see [SettingsScreen._enter]).
  /// v4.25 — the push rides [aethPageRoute]: the page enters with the
  /// SELECTED STYLE'S own personality (SILK fade-rise / TIDE zoom-
  /// dissolve / SPRING pop / BLINK fade / OFF instant cut).
  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      aethPageRoute<void>(
        style: store.effectiveMotionStyle(context),
        builder: (_) => SettingsScreen(store: store),
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

        final locationHeader = LocationHeader(
          connected: connected,
          // v4.21 — the band rule follows the committed mode
          // (single-knob selection after the v4.20 revert).
          protocolIsTorOrPsiphon:
              store.effectiveProtocol.isTor ||
              store.effectiveProtocol.isPsiphon,
          // v4.21 — the wheel is a real, scrollable SELECTOR for the
          // whole psiphon + tor families while DISCONNECTED, and locks on
          // the connected location once connected (owner device-test
          // round 3). v5: non-family protocols keep the band VISIBLE but
          // GREYSCALE + locked while disconnected (round 19).
          selectable: store.wheelSelectable,
          allowedCodes: store.wheelAllowedCodes,
          autoEntry: store.wheelAutoEntry,
          anchorCode: store.wheelAnchorCode,
          pingMs: store.pingMs,
          exitCountryCode: store.exitCountryCode,
          onCountrySelected: store.selectLocation,
        );

        return Scaffold(
          backgroundColor: AethColors.bgScreen,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Edge patterns (red ↔ green, animated crossfade; they also
              // DRIFT while the engine walks or the tunnel is up). The
              // appearance switch can turn them off. v5: the look-2 curved
              // sheet COVERS them below its crown exactly like the
              // mockups (the sheet is painted above in z-order).
              if (store.showPatterns)
                Positioned.fill(
                  child: PatternSides(
                    connected: connected,
                    style: style,
                    active: connected || showScan,
                  ),
                ),
              SafeArea(
                // v5 — look 2's curved sheet bleeds to the PHYSICAL bottom
                // edge (the mockups run it past the home indicator); only
                // look 1 keeps the bottom inset inside the SafeArea.
                bottom: isLookOne,
                child: Column(
                  children: [
                    // v4.12: extra top gap so the app never crowds the
                    // status-bar / notch area.
                    SizedBox(height: AethGeometry.topSafeExtraGap * s),
                    HomeTopBar(
                      onSettings: () => _openSettings(context),
                      store: store,
                    ),
                    if (isLookOne) ...[
                      SizedBox(height: AethGeometry.gapTopbarToLocation * s),
                      locationHeader,
                      // Hero band: the logo centers in the flex region.
                      Expanded(
                        child: Center(
                          child: heroStack(context, s, style, connected, showScan),
                        ),
                      ),
                      // v2.1.0 (the owner's decree: «برای صفحه اصلی چندتا
                      // ویجت خلاقانه اضافه کن») — THE HOME WIDGET DECK: the
                      // live session timer, the ping sparkline and the
                      // session data card (look 1's hero band; the v5 look-2
                      // redesign has no deck — its sheet owns the space).
                      HomeWidgetDeck(store: store, style: style),
                      SizedBox(height: AethGeometry.gapSpeedToPill * s),
                      SpeedTestButton(
                        visible: connected,
                        connected: connected,
                        style: style,
                        onTap: () => _openSpeedTest(context),
                      ),
                      SizedBox(height: AethGeometry.gapSpeedToPill * s),
                      StatusPill(state: store.state, style: style),
                      failureCaption(context, s),
                      SizedBox(height: AethGeometry.gapPillToPanel * s),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AethGeometry.pageHPadding * s,
                        ),
                        child: BottomPanel(
                          connected: connected,
                          style: style,
                          selectedProtocol: store.smartDisplayProtocol,
                          protocolLabel: protocolLabel(strings, showScan),
                          downBytes: store.downBytes,
                          upBytes: store.upBytes,
                          showConnectButton: true,
                          onProtocolCardTap: () => _openProtocolPage(context),
                          onConnect: _toggleConnection,
                          onDisconnect: _toggleConnection,
                        ),
                      ),
                      SizedBox(height: AethGeometry.gapPanelToBottom * s),
                    ] else ...[
                      // v5 «نمای 2» — the pill rides ABOVE the hero.
                      SizedBox(height: AethGeometry.gapTopbarToPill * s),
                      StatusPill(state: store.state, style: style),
                      failureCaption(context, s),
                      // The hero is BOTTOM-anchored: the connect button's
                      // white base stays glued to the sheet's crown.
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: heroStack(context, s, style, connected, showScan),
                        ),
                      ),
                      SizedBox(height: AethGeometry.gapHeroToPanel * s),
                      _LookTwoSheet(
                        store: store,
                        style: style,
                        strings: strings,
                        s: s,
                        connected: connected,
                        locationHeader: locationHeader,
                        protocolLabel: protocolLabel(strings, showScan),
                        onProtocolCardTap: () => _openProtocolPage(context),
                        onSpeedTap: () => _openSpeedTest(context),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The hero band's constant Stack: the scan halo (engine walk) and the
  /// connected aura BEHIND the look-1 logo / the look-2 connect button.
  Widget heroStack(
    BuildContext context,
    double s,
    MotionStyle style,
    bool connected,
    bool showScan,
  ) {
    final isLookOne = store.homeLook == HomeLook.one;
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedSwitcher(
          duration: motionDuration(style, MotionDurations.quick),
          child: showScan
              ? ScanRings(
                  key: const ValueKey('scan-rings'),
                  color: connected
                      ? AethColors.accentConnected
                      : AethColors.statusDisconnected,
                  size: 270 * s,
                )
              : const SizedBox.shrink(key: ValueKey('scan-off')),
        ),
        // The connected breathing aura wraps the WHOLE connect
        // composition (v4.33 rule, re-based on the v5 160px group).
        AnimatedSwitcher(
          duration: motionDuration(style, MotionDurations.state),
          child: connected
              ? AuroraBloom(
                  key: const ValueKey('connected-aura'),
                  color: AethColors.accentConnected,
                  size: (isLookOne
                          ? AethGeometry.heroSize
                          : AethGeometry.connectGroupSize) *
                      1.25 *
                      s,
                  style: style,
                )
              : const SizedBox.shrink(key: ValueKey('aura-off')),
        ),
        if (isLookOne)
          GestureDetector(
            // The logo toggles the connection exactly like the bottom FAB
            // (v4.17 round #5); tap-to-cancel during the walk (v4.19 #3).
            behavior: HitTestBehavior.opaque,
            onTap: _toggleConnection,
            child: HeroLogo(connected: connected, style: style),
          )
        else
          _CenterConnectButton(
            store: store,
            style: style,
            onTap: _toggleConnection,
          ),
      ],
    );
  }

  /// The failed state's honest caption under the status pill (v4.20),
  /// shared by both looks — it eats into the flex band in look 2.
  Widget failureCaption(BuildContext context, double s) {
    return AnimatedSize(
      duration: motionDuration(
        store.effectiveMotionStyle(context),
        MotionDurations.quick,
      ),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: store.state == VpnState.failed && store.lastErrorCode != null
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
    );
  }

  /// The panel's protocol label (v4.32/v4.35 rule): the SMART session's
  /// own display — the carrying protocol while resolved, the in-flight
  /// candidate + attempt while the walk runs.
  String protocolLabel(AppStrings strings, bool showScan) {
    return store.smartAttempt != null && showScan
        ? (store.smartAttempt!.measuring
              ? strings.smartMeasuringLabel(
                  strings.protocolName(store.smartAttempt!.candidate),
                )
              : strings.smartAttemptLabel(
                  strings.protocolName(store.smartAttempt!.candidate),
                  store.smartAttempt!.attempt,
                  store.smartAttempt!.total,
                ))
        : strings.protocolName(store.smartDisplayProtocol);
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
              style: TextStyle(
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
                style: TextStyle(
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

/// Look 2: the hero IS the connect button — v4.33 (owner round 9): the
/// owner's own CSS composition «Group 45» ([ConnectButtonGlow] — a
/// circular blurred glow over three SQUIRCLE layers with the Off glyph),
/// replacing the old all-circle GlowCircle («این دکمه رو هم در صفحه اصلی
/// و هم در این صفحه بد طراحی کردی»). Owner v4.12: plain tap toggles; the
/// swipe-only interaction from defect #11 stays reverted. v4.19 (#3): the
/// toggle logic lives in [HomeScreen._toggleConnection] (tap-to-cancel
/// during the walk).
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
    return ConnectButtonGlow(
      connected: store.isConnected,
      duration: motionDuration(style, MotionDurations.state),
      curve: style.curve,
      onTap: onTap, // tap-to-toggle (owner v4.12) + cancel (v4.19 #3)
    );
  }
}

/// v5 («نمای 2») — the curved white bottom sheet: the owner's «Rectangle
/// 87» + SVG crown (flat rim, a U-dip to +30 across the centre) with the
/// committed shadow (`0 −16 95 rgba(0,0,0,0.09)`), carrying the stats row,
/// the flag wheel + country row and the protocol card down to the screen's
/// physical bottom edge.
class _LookTwoSheet extends StatelessWidget {
  const _LookTwoSheet({
    required this.store,
    required this.style,
    required this.strings,
    required this.s,
    required this.connected,
    required this.locationHeader,
    required this.protocolLabel,
    required this.onProtocolCardTap,
    required this.onSpeedTap,
  });

  final ConnectionStore store;
  final MotionStyle style;
  final AppStrings strings;
  final double s;
  final bool connected;
  final Widget locationHeader;
  final String protocolLabel;
  final VoidCallback onProtocolCardTap;
  final VoidCallback onSpeedTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return CustomPaint(
      // The crown paints UNDER the content — the sheet's own fill must
      // never cover the stats row / flags / card riding on it.
      painter: _SheetCrownPainter(s),
      child: Padding(
        // The sheet's empty crown between its top edge and the stats row
        // (design y 470 → 532).
        padding: EdgeInsets.only(top: AethGeometry.panelTopPad * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeStatsRow(
              connected: connected,
              style: style,
              downBytes: store.downBytes,
              upBytes: store.upBytes,
              onSpeedTap: onSpeedTap,
            ),
            SizedBox(height: AethGeometry.gapStatsToFlags * s),
            locationHeader,
            SizedBox(height: AethGeometry.gapRowToCard * s),
            Padding(
              // The card spans x 33–369 on the 402-wide frame.
              padding: EdgeInsets.symmetric(
                horizontal: AethGeometry.pageHPadding * s,
              ),
              child: BottomPanel(
                connected: connected,
                style: style,
                selectedProtocol: store.smartDisplayProtocol,
                protocolLabel: protocolLabel,
                downBytes: store.downBytes,
                upBytes: store.upBytes,
                showConnectButton: false,
                onProtocolCardTap: onProtocolCardTap,
                onConnect: () {},
                onDisconnect: () {},
              ),
            ),
            // The card rides 3px + the live home-indicator inset above the
            // glass (design: 837 → 874 with the 34px inset).
            SizedBox(
              height: AethGeometry.gapCardToBottomBase * s + bottomInset,
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the sheet's crown: the blurred shadow ABOVE the top edge + the
/// bg-coloured fill whose top line follows the owner's SVG path (flat rim
/// 0–96 · U-dip to +30 across the centre · flat rim 301–402, design px).
class _SheetCrownPainter extends CustomPainter {
  _SheetCrownPainter(this.s);

  final double s;

  Path _crownPath(Size size) {
    final k = s;
    Path path = Path()..moveTo(0, 0);
    path = path
      ..lineTo(AethGeometry.panelDipX1 * k, 0)
      ..cubicTo(
        114.511 * k,
        0,
        132.325 * k,
        6.208 * k,
        AethGeometry.panelDipCx1 * k,
        17.616 * k,
      )
      ..cubicTo(
        156.933 * k,
        25.731 * k,
        169.606 * k,
        AethGeometry.panelDipDepth * k,
        AethGeometry.panelDipX2 * k,
        AethGeometry.panelDipDepth * k,
      )
      ..lineTo(AethGeometry.panelDipX3 * k, AethGeometry.panelDipDepth * k)
      ..cubicTo(
        227.894 * k,
        AethGeometry.panelDipDepth * k,
        240.567 * k,
        25.731 * k,
        AethGeometry.panelDipCx2 * k,
        17.616 * k,
      )
      ..cubicTo(
        265.175 * k,
        6.208 * k,
        282.989 * k,
        0,
        AethGeometry.panelDipX4 * k,
        0,
      )
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _crownPath(size);
    // The committed shadow — the SVG filter: feOffset dy −16, feGaussian
    // σ47.5, α0.09. Painted FIRST so the fill covers its lower half.
    canvas.save();
    canvas.translate(0, AethGeometry.panelShadowDy * s);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color.fromRGBO(0, 0, 0, AethGeometry.panelShadowAlpha)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          AethGeometry.panelShadowSigma * s,
        ),
    );
    canvas.restore();
    canvas.drawPath(path, Paint()..color = AethColors.bgScreen);
  }

  @override
  bool shouldRepaint(_SheetCrownPainter oldDelegate) =>
      oldDelegate.s != s;
}
