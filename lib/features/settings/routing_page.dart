/// «مسیریابی‌ها» — the routing sub-page (v4.22): the routing-area pick
/// (the status card's own source, IR/TM/RU/CN/None) plus the expert
/// domain lists the pinned core consumes (--route-block/--route-direct,
/// cli.rs L323-324: "never let these reach the network at all" /
/// "send these straight out, bypassing the tunnel").
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/app_tunnel.dart';
import '../../../connection/connection_store.dart';
import '../../../connection/platform_engine_adapter.dart';
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
              const SubSectionDivider(),
              // v4.41 (round 17, item 3) — the profile now really routes:
              // the picked country's own domains + IP space go DIRECT, the
              // rest tunnels. Stated plainly so the pick is an informed one.
              SettingInfoText(strings.routingAreaDesc),
            ],
          ),
        ),

        // ---- Section: per-app tunneling (Android, tunnel mode) ----
        // v4.41 (owner round 17, item 4): «قابلیت مثتثنی کردن برنامه ها
        // از تونل در اندروید … دو حالت داشته باشه 1. فقط برنامه های
        // انتخاب شده تونل بشن 2. برنامه های انتخاب شده تونل نشن این
        // قسمت با زبان طراحی اپ هماهنگ باشه». Android only — the TUN's
        // per-app scoping is a VpnService.Builder capability; desktop
        // builds (and tests) hide the section entirely.
        if (Platform.isAndroid) ...[
          SizedBox(height: 24 * s),
          SubSectionHeading(
            icon: AppAssets.iconCategory,
            title: strings.tunnelApps,
          ),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingPills<String>(
                  keyId: 'tunnel-apps-mode',
                  options: [
                    ('all', strings.tunnelAppsModeAll),
                    ('allow', strings.tunnelAppsModeAllow),
                    ('disallow', strings.tunnelAppsModeDisallow),
                  ],
                  selected: store.appTunnelMode.name,
                  onSelect: (name) =>
                      store.setAppTunnelMode(AppTunnelMode.fromName(name)),
                ),
                if (store.appTunnelMode != AppTunnelMode.all) ...[
                  const SubSectionDivider(),
                  _AppPickerList(store: store),
                ],
                const SubSectionDivider(),
                SettingInfoText(strings.tunnelAppsDesc),
              ],
            ),
          ),
        ],

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

// ---------------------------------------------------------------------------
// v4.41 (round 17, item 4) — the per-app tunneling picker: the launchable
// apps as checkable rows in the settings cards' own language (rounded
// rows, selected = the accent-green tile + the Tick glyph, exactly like
// the pill selection semantics).
// ---------------------------------------------------------------------------

class _AppPickerList extends StatefulWidget {
  const _AppPickerList({required this.store});

  final ConnectionStore store;

  @override
  State<_AppPickerList> createState() => _AppPickerListState();
}

class _AppPickerListState extends State<_AppPickerList> {
  List<InstalledApp>? _apps;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final apps = await PlatformEngineAdapter.installedApps();
      if (mounted) setState(() => _apps = apps);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final apps = _apps;
    if (apps == null) {
      return SettingInfoText(
        _failed ? strings.tunnelAppsLoadFailed : strings.tunnelAppsLoading,
      );
    }
    if (apps.isEmpty) {
      return SettingInfoText(strings.tunnelAppsLoadFailed);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final app in apps)
          Padding(
            padding: EdgeInsets.only(bottom: 8 * s),
            child: _AppRow(
              key: ValueKey('tunnel-app-${app.packageName}'),
              app: app,
              selected: widget.store.appTunnelApps.contains(app.packageName),
              onToggle: (value) => widget.store.toggleAppTunnelApp(
                app.packageName,
                selected: value,
              ),
            ),
          ),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.selected,
    required this.onToggle,
  });

  final InstalledApp app;
  final bool selected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onToggle(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: 12 * s,
          vertical: 9 * s,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AethColors.accentConnected
              : AethColors.sheetDescCard,
          borderRadius: BorderRadius.circular(14 * s),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13 * s,
                      color: AethColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w400,
                      fontSize: 10 * s,
                      color: AethColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10 * s),
            SizedBox(
              width: 22 * s,
              height: 22 * s,
              // The Tick glyph's own ink is dark navy — on the selected
              // accent-green tile it must re-ink like every heading icon.
              child: selected
                  ? SvgPicture.asset(
                      AppAssets.iconTick,
                      fit: BoxFit.contain,
                      colorFilter: ColorFilter.mode(
                        AethColors.textPrimary,
                        BlendMode.srcIn,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
