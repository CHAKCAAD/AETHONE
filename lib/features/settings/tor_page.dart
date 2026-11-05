/// «تور» — the Tor sub-page (v4.22): the exit-location pick (v4.30: the
/// REAL Tor exit-country list — the live Onionoo set / the bundled
/// snapshot — exactly the list the home wheel's tor band offers, AUTO
/// first; the honest caption says the Tor core picks the exit from the
/// available relays) and the bridges panel (--no-tor-bridges + the
/// env-only tor log level). v4.31 (owner round 7: «وارد کردن دستی پل های
/// تور») adds the MANUAL bridge lines (one `--tor-bridge` per line) and
/// the tor connection budgets (the env-only AETHER_TOR_DIRECT_SECS /
/// AETHER_TOR_BRIDGE_SECS).
library;

import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final core = store.coreSettings;

    final bridgesDesc = switch (core.torBridges) {
      TorBridgePolicy.auto => strings.bridgesAutoDesc,
      TorBridgePolicy.off => strings.bridgesOffDesc,
      TorBridgePolicy.custom => strings.bridgesCustomDesc,
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
              // v4.30 — the SAME list the home wheel's tor band offers
              // (owner round 6: «قسمت انتخاب لوکیشن در صفحه اصلی و قسمت
              // انتخاب لوکیشن در تنظیمات تور و سایفون باهم همگام باشن»):
              // the REAL Tor exit countries — the live Onionoo set once a
              // refresh/cache-load has arrived, else the bundled snapshot —
              // never the full flag manifest again (the old strip offered
              // countries Tor cannot exit from).
              FlagPickStrip(
                codes: [
                  LocationWheelPolicy.autoCode,
                  ...(store.liveTorExitCountries ?? torExitCountrySnapshot),
                ],
                selected: store.torLocation,
                onSelect: store.setTorLocation,
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
                  // v4.31 — the owner's manual-bridges round: «وارد کردن
                  // دستی پل های تور».
                  (TorBridgePolicy.custom, strings.bridgesCustom),
                ],
                selected: core.torBridges,
                onSelect: (v) => store.updateCore((c) => c.torBridges = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(bridgesDesc),
              // v4.31 — the bridge lines, only while the policy is custom
              // (the same conditional-fields pattern the fragment preset's
              // custom size/delay pair uses on the core page).
              if (core.torBridges == TorBridgePolicy.custom) ...[
                const SubSectionDivider(),
                SettingField(
                  keyId: 'tor-bridge-lines',
                  label: strings.torBridgeLinesLabel,
                  hint: strings.torBridgeLinesHint,
                  initial: core.torBridgeLines,
                  maxLines: 4,
                  onChanged: (v) =>
                      store.updateCore((c) => c.torBridgeLines = v.trim()),
                ),
              ],
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

        // ---- Section: tor connection budgets (v4.31) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconWatch1,
          title: strings.secTorTimings,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingStepperRow(
                keyId: 'tor-direct-secs',
                icon: AppAssets.iconWatch1,
                label: strings.torDirectSecsLabel,
                value: core.torDirectSecs,
                min: 15,
                max: 600,
                onChanged: (v) => store.updateCore((c) => c.torDirectSecs = v),
              ),
              const SubSectionDivider(),
              SettingStepperRow(
                keyId: 'tor-bridge-secs',
                icon: AppAssets.iconWatch1,
                label: strings.torBridgeSecsLabel,
                value: core.torBridgeSecs,
                min: 60,
                max: 900,
                onChanged: (v) => store.updateCore((c) => c.torBridgeSecs = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.torTimingsDesc),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
        SettingInfoText(strings.appliesNextConnect),
      ],
    );
  }
}
