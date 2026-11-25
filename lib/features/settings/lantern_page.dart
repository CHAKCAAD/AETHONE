/// «لنترن» — the Lantern sub-page (feature/motion-phase3-lantern), the
/// third protocol page beside Psiphon and Tor, built from the same
/// sub-page kit:
///
///  * the exit location — ONLY the countries Lantern's own server list
///    offered on the last Lantern connect (the sidecar's `/servers`
///    control call; Lantern publishes no static list), AUTO first. The
///    pick is shared with the home wheel's Lantern band, and a change on
///    a live Lantern session switches servers at once (`/select`);
///  * the tunnel — UDP pass-through and the compatible (sequential)
///    SOCKS handshake zeptun speaks to the sidecar;
///  * Telegram — one tap hands Lantern's local SOCKS (127.0.0.1:1822) to
///    Telegram's own proxy list (`tg://socks`);
///  * the connect budget — the sidecar's `--connect-timeout` (30–300 s,
///    default 180).
///
/// No DNS picker on purpose: the tunnel's fake-IP DNS hands every NAME to
/// Lantern, which resolves it on its own server — a local resolver choice
/// would change nothing on the wire.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/transport_modes.dart';
import '../../../core/app_assets.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class LanternSettingsPage extends StatelessWidget {
  const LanternSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  /// Telegram's own add-proxy deep link, pointed at Lantern's loopback
  /// SOCKS listener.
  static Uri get telegramProxyUri {
    final ep = TransportModes.lantern.socksEndpoint;
    return Uri.parse('tg://socks?server=${ep.host}&port=${ep.port}');
  }

  Future<void> _openTelegram(BuildContext context) async {
    final failed = AppStrings.of(context).lanternTelegramFailed;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var ok = false;
    try {
      ok = await launchUrl(
        telegramProxyUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final core = store.coreSettings;
    // Read INSIDE the builder: the frame rebuilds on store changes, and
    // the sidecar's /servers report lands after the page is open.
    List<String> countries() =>
        store.liveLanternCountries ?? const <String>[];

    return SubPageFrame(
      store: store,
      title: strings.settingsLantern,
      icon: AppAssets.protocolLanternLogo(light: AethThemeSync.light),
      iconTinted: false,
      children: () => [
        // ---- Section: exit location ----
        SubSectionHeading(
          icon: AppAssets.iconLocation,
          title: strings.secExitLocation,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The SAME list the home wheel's Lantern band offers.
              FlagPickStrip(
                codes: [LocationWheelPolicy.autoCode, ...countries()],
                selected: store.lanternLocation,
                onSelect: store.setLanternLocation,
              ),
              const SubSectionDivider(),
              SettingInfoText(
                countries().isEmpty
                    ? strings.lanternLocationEmpty
                    : strings.lanternLocationDesc,
              ),
            ],
          ),
        ),

        // ---- Section: the tunnel ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secLanternTunnel,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingToggleRow(
                keyId: 'lantern-udp',
                icon: AppAssets.iconShuffle1,
                title: strings.lanternUdpLabel,
                description: strings.lanternUdpDesc,
                value: core.lanternUdp,
                onChanged: (v) => store.updateCore((c) => c.lanternUdp = v),
              ),
              const SubSectionDivider(),
              SettingToggleRow(
                keyId: 'lantern-strict',
                icon: AppAssets.iconShieldTick,
                title: strings.lanternStrictLabel,
                description: strings.lanternStrictDesc,
                value: core.lanternStrictSocks,
                onChanged: (v) =>
                    store.updateCore((c) => c.lanternStrictSocks = v),
              ),
              const SubSectionDivider(),
              SettingNavRow(
                keyId: 'lantern-telegram',
                icon: AppAssets.iconSend,
                title: strings.lanternTelegramLabel,
                description: strings.lanternTelegramDesc,
                onTap: () => _openTelegram(context),
              ),
            ],
          ),
        ),

        // ---- Section: the connect budget ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconWatch1,
          title: strings.secLanternTimings,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingStepperRow(
                keyId: 'lantern-connect-secs',
                icon: AppAssets.iconWatch1,
                label: strings.lanternConnectSecsLabel,
                value: core.lanternConnectSecs,
                min: 30,
                max: 300,
                onChanged: (v) =>
                    store.updateCore((c) => c.lanternConnectSecs = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.lanternTimingsDesc),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
        SettingInfoText(
          Platform.isAndroid
              ? strings.appliesNextConnect
              : strings.lanternAndroidOnly,
        ),
      ],
    );
  }
}
