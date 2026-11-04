/// «مسیریابی‌ها» — the routing sub-page (v4.22): the routing-area pick
/// (the status card's own source, IR/TM/RU/CN/None) plus the expert
/// domain lists the pinned core consumes (--route-block/--route-direct,
/// cli.rs L323-324: "never let these reach the network at all" /
/// "send these straight out, bypassing the tunnel").
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/country_names.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class RoutingSettingsPage extends StatelessWidget {
  const RoutingSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;

    // The store keeps null = None; the pills speak the sentinel form.
    final current = store.routingRegion ?? 'none';
    return SubPageFrame(
      store: store,
      title: strings.settingsRouting,
      children: () => [
        // ---- Section: the routing area ----
        SubSectionHeading(
          icon: AppAssets.iconMap,
          title: strings.settingsRoutingArea,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingPills<String>(
                keyId: 'routing-area',
                options: [
                  ('ir', countryName('ir')!),
                  ('tm', countryName('tm')!),
                  ('ru', countryName('ru')!),
                  ('cn', countryName('cn')!),
                  ('none', strings.routingNone),
                ],
                selected: current,
                onSelect: (code) => store.setRoutingRegion(
                  code == 'none' ? null : code,
                ),
              ),
            ],
          ),
        ),

        // ---- Section: direct & blocked routes (expert) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconFilter5,
          title: strings.secRoutes,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingField(
                keyId: 'route-block',
                label: strings.routeBlockLabel,
                hint: strings.routeBlockHint,
                initial: store.coreSettings.routeBlock,
                maxLines: 2,
                onChanged: (v) =>
                    store.updateCore((c) => c.routeBlock = v.trim()),
              ),
              const SubSectionDivider(),
              SettingField(
                keyId: 'route-direct',
                label: strings.routeDirectLabel,
                hint: strings.routeDirectHint,
                initial: store.coreSettings.routeDirect,
                maxLines: 2,
                onChanged: (v) =>
                    store.updateCore((c) => c.routeDirect = v.trim()),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.routesDesc),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
        SettingInfoText(strings.appliesNextConnect),
      ],
    );
  }
}
