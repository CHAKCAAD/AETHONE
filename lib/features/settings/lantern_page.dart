/// «لنترن» — the Lantern sub-page (feature/motion-phase3-lantern), the
/// third protocol page beside Psiphon and Tor, built from the same
/// sub-page kit:
///
///  * the exit location — ONLY the countries Lantern's own server list
///    offered on the last Lantern connect (the sidecar's `/servers`
///    control call; Lantern publishes no static list), AUTO first. The
///    pick is shared with the home wheel's Lantern band, and a change on
///    a live Lantern session switches servers at once (`/select`);
///  * the connect budget — the sidecar's `--connect-timeout` (30–300 s,
///    default 180).
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/transport_modes.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class LanternSettingsPage extends StatelessWidget {
  const LanternSettingsPage({super.key, required this.store});

  final ConnectionStore store;

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
