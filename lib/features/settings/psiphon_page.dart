/// «سایفون» — the Psiphon sub-page (v4.22): the exit-location pick (the
/// psiphon egress regions the pinned core actually serves, AUTO first —
/// the same source the home wheel filters by) and the CDN-fronting panel
/// (--psiphon-mode / --psiphon-cdn-sni / --psiphon-cdn-ips).
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

class PsiphonSettingsPage extends StatelessWidget {
  const PsiphonSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final core = store.coreSettings;

    final frontingDesc = switch (core.psiphonFronting) {
      PsiphonFronting.auto => strings.frontingAutoDesc,
      PsiphonFronting.cdn => strings.frontingCdnDesc,
      PsiphonFronting.direct => strings.frontingDirectDesc,
    };

    return SubPageFrame(
      store: store,
      title: strings.settingsPsiphon,
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
              FlagPickStrip(
                // v4.30 — the SAME list the home wheel offers (owner round
                // 6: the two pickers are ONE — «نه تنها از لحاظ عملکرد
                // بک‌اند بلکه از لحاظ ظاهری هم باید همگامسازی بشن»): the
                // LIVE psiphon egress set once the core itself reported
                // one, else the standing seed. A pick here and a pick on
                // the home wheel write the SAME store field.
                codes: [
                  LocationWheelPolicy.autoCode,
                  ...(store.livePsiphonRegions ?? psiphonEgressRegions),
                ],
                selected: store.psiphonLocation,
                onSelect: store.setPsiphonLocation,
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.psiphonLocationDesc),
            ],
          ),
        ),

        // ---- Section: CDN fronting ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconShuffle1,
          title: strings.secFronting,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingLabel(strings.frontingModeLabel),
              const SizedBox(height: 10),
              SettingPills<PsiphonFronting>(
                keyId: 'fronting',
                options: [
                  (PsiphonFronting.auto, strings.frontingAuto),
                  (PsiphonFronting.cdn, strings.frontingCdn),
                  (PsiphonFronting.direct, strings.frontingDirect),
                ],
                selected: core.psiphonFronting,
                onSelect: (v) =>
                    store.updateCore((c) => c.psiphonFronting = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(frontingDesc),
              const SubSectionDivider(),
              SettingField(
                keyId: 'cdn-sni',
                label: strings.cdnSniLabel,
                hint: strings.cdnSniHint,
                initial: core.cdnSni,
                onChanged: (v) =>
                    store.updateCore((c) => c.cdnSni = v.trim()),
              ),
              const SubSectionDivider(),
              SettingField(
                keyId: 'cdn-ips',
                label: strings.cdnIpsLabel,
                hint: strings.cdnIpsHint,
                initial: core.cdnIps,
                onChanged: (v) =>
                    store.updateCore((c) => c.cdnIps = v.trim()),
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
