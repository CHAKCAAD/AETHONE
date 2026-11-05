/// «تنظیمات عمومی» — the general sub-page (v4.22). v4.35 (owner round 11,
/// the beta-release round: «توی قسمت تنظیمات عمومی هم فعلا آدرس مخزن و
/// کانال رو بردار و نسخه برنامه رو بنویس آزمایشی»): the About card now
/// carries ONLY the version row, and its value reads the beta stage
/// («آزمایشی») instead of the number — the repo/channel rows are dropped
/// for the beta window (the real number stays in pubspec/app_meta, where
/// the tests keep it honest).
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SubPageFrame(
      store: store,
      title: strings.settingsGeneral,
      children: () => [
        // ---- Section: about the app ----
        SubSectionHeading(
          icon: AppAssets.iconInformationCircle,
          title: strings.secAbout,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingNavRow(
                keyId: 'app-version',
                icon: AppAssets.iconSetting,
                title: strings.appVersionLabel,
                // v4.35 — the beta window shows the stage, not the number.
                trailingValue: strings.betaStage,
                chevron: false,
                onTap: () {}, // a value row — not a navigation target
              ),
            ],
          ),
        ),

        // ---- Section: notifications & events ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconActivity4,
          title: strings.secNotifications,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingInfoText(strings.notificationsComing),
        ),
      ],
    );
  }
}
