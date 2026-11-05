/// «سایفون» — the Psiphon sub-page (v4.22): the exit-location pick (the
/// psiphon egress regions the pinned core actually serves, AUTO first —
/// the same source the home wheel filters by) and the CDN-fronting panel
/// (--psiphon-mode / --psiphon-cdn-sni / --psiphon-cdn-ips). v4.31 (owner
/// round 7: «تننیمات بیشتر») adds the fronting SETS, the ready budget
/// (the env-only AETHER_PSIPHON_READY_SECS) and the pasted server
/// entries. v4.31c (owner round 8: «قسمت پایه حالت های ترکیبی باید توی
/// زیرمجموعه تنطیمات تور و سایفون قرار بگیره») moves the COMBINED-MODE
/// BASE here: the Aether protocol under the psiphon family's
/// chain/reverse modes, this family's own pick.
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
                // 6: the two pickers are ONE): the LIVE psiphon egress set
                // once the core itself reported one, else the standing
                // seed. A pick here and a pick on the home wheel write the
                // SAME store field.
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

        // ---- Section: the combined-mode base (v4.31c — moved from the
        // connection page by the round-8 decree; the psiphon family's own
        // leg pick, writing CoreSettings.psiphonLegProtocol) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secFamilyLeg,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingLabel(strings.aetherLegLabel),
              const SizedBox(height: 10),
              SettingPills<AetherLegProtocol>(
                keyId: 'psiphon-leg',
                options: [
                  // The same order + labels as the protocol page's own
                  // tiles (strings.aetherLegName reuses their names).
                  (AetherLegProtocol.wireguard, strings.aetherLegName(
                      AetherLegProtocol.wireguard)),
                  (AetherLegProtocol.masque, strings.aetherLegName(
                      AetherLegProtocol.masque)),
                  (AetherLegProtocol.gool, strings.aetherLegName(
                      AetherLegProtocol.gool)),
                  (AetherLegProtocol.goolClassic, strings.aetherLegName(
                      AetherLegProtocol.goolClassic)),
                  (AetherLegProtocol.mim, strings.aetherLegName(
                      AetherLegProtocol.mim)),
                ],
                selected: core.psiphonLegProtocol,
                onSelect: (v) =>
                    store.updateCore((c) => c.psiphonLegProtocol = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.psiphonLegDesc),
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
              // v4.31 — which of psiphon's built-in fronting edge lists
              // the CDN fronting uses (--psiphon-cdn-sets, #91).
              const SubSectionDivider(),
              SettingField(
                keyId: 'cdn-sets',
                label: strings.cdnSetsLabel,
                hint: strings.cdnSetsHint,
                initial: core.cdnSets,
                onChanged: (v) =>
                    store.updateCore((c) => c.cdnSets = v.trim()),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.cdnSetsDesc),
            ],
          ),
        ),

        // ---- Section: ready budget (v4.31) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconWatch1,
          title: strings.secPsiphonTimings,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingStepperRow(
                keyId: 'psiphon-ready-secs',
                icon: AppAssets.iconWatch1,
                label: strings.psiphonReadyLabel,
                value: core.psiphonReadySecs,
                min: 60,
                max: 600,
                onChanged: (v) =>
                    store.updateCore((c) => c.psiphonReadySecs = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.psiphonReadyDesc),
            ],
          ),
        ),

        // ---- Section: server entries (v4.31) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSetting,
          title: strings.serverEntriesLabel,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingField(
                keyId: 'psiphon-server-entries',
                label: strings.serverEntriesLabel,
                hint: strings.serverEntriesHint,
                initial: core.psiphonServerEntries,
                maxLines: 4,
                onChanged: (v) =>
                    store.updateCore((c) => c.psiphonServerEntries = v.trim()),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.serverEntriesDesc),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
        SettingInfoText(strings.appliesNextConnect),
      ],
    );
  }
}
