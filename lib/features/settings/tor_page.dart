/// «تور» — the Tor sub-page (v4.22): the exit-location pick (the FULL flag
/// manifest like the home wheel's tor band, AUTO first; the honest caption
/// says the Tor core picks the exit from the available relays) and the
/// bridges panel (--no-tor-bridges + the env-only tor log level).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/core_settings.dart';
import '../../../connection/transport_modes.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class TorSettingsPage extends StatelessWidget {
  const TorSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  /// The full flag manifest (the home wheel's tor band runs on the same
  /// list): every committed flags_png artwork, 'auto' excluded — the
  /// strip prepends it itself.
  static Future<List<String>> _loadManifest() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'design/flags_png/';
    return manifest
        .listAssets()
        .where(
          (p) =>
              p.startsWith(prefix) &&
              p.endsWith('.png') &&
              p != '${prefix}auto.png',
        )
        .map((p) => p.substring(prefix.length, p.length - 4))
        .toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final core = store.coreSettings;

    final bridgesDesc = switch (core.torBridges) {
      TorBridgePolicy.auto => strings.bridgesAutoDesc,
      TorBridgePolicy.off => strings.bridgesOffDesc,
    };

    return SubPageFrame(
      store: store,
      title: strings.settingsTor,
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
              FutureBuilder<List<String>>(
                future: _loadManifest(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const SizedBox(
                      height: 72,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return FlagPickStrip(
                    codes: [
                      LocationWheelPolicy.autoCode,
                      ...snap.data!,
                    ],
                    selected: store.torLocation,
                    onSelect: store.setTorLocation,
                  );
                },
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.torLocationDesc),
            ],
          ),
        ),

        // ---- Section: Tor bridges ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconDiscovery1,
          title: strings.secTorBridges,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingLabel(strings.bridgesLabel),
              const SizedBox(height: 10),
              SettingPills<TorBridgePolicy>(
                keyId: 'bridges',
                options: [
                  (TorBridgePolicy.auto, strings.bridgesAuto),
                  (TorBridgePolicy.off, strings.bridgesOff),
                ],
                selected: core.torBridges,
                onSelect: (v) => store.updateCore((c) => c.torBridges = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(bridgesDesc),
              const SubSectionDivider(),
              SettingLabel(strings.torLogLevelLabel),
              const SizedBox(height: 10),
              SettingPills<TorLogLevel>(
                keyId: 'tor-log',
                options: [
                  (TorLogLevel.info, strings.logInfo),
                  (TorLogLevel.debug, strings.logDebug),
                  (TorLogLevel.trace, strings.logTrace),
                ],
                selected: core.torLog,
                onSelect: (v) => store.updateCore((c) => c.torLog = v),
              ),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
        SettingInfoText(strings.appliesNextConnect),
      ],
    );
  }
}
