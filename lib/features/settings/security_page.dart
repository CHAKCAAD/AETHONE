/// «تنظیمات امنیت» — the security sub-page (v4.22): the Kill Switch
/// preference (the status card's own source) with its honest caption, and
/// the diagnostics block (the core-log viewer's second entry point — the
/// first sits on the settings main page).
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
import 'settings_screen.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class SecuritySettingsPage extends StatelessWidget {
  const SecuritySettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SubPageFrame(
      store: store,
      title: strings.settingsSecurity,
      children: () => [
        // ---- Section: Kill Switch ----
        SubSectionHeading(
          icon: AppAssets.iconSecuritySafe,
          title: strings.secKillSwitch,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingToggleRow(
            keyId: 'kill-switch',
            icon: AppAssets.iconOff,
            title: strings.secKillSwitch,
            description: strings.killSwitchDesc,
            value: store.killSwitch,
            onChanged: store.setKillSwitch,
          ),
        ),

        // ---- Section: diagnostics ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconActivity4,
          title: strings.secDiagnostics,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingNavRow(
            keyId: 'core-log',
            icon: AppAssets.iconInformationCircle,
            title: strings.coreLogTitle,
            // v4.25 — the style-personal route + the honest pattern state.
            onTap: () => Navigator.of(context).push(
              aethPageRoute<void>(
                style: store.effectiveMotionStyle(context),
                builder: (_) => CoreLogPage(
                  showPatterns: store.showPatterns,
                  connected: store.isConnected,
                  style: store.effectiveMotionStyle(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
