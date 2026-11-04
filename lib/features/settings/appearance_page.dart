/// «تنظیمات ظاهری» — the appearance sub-page (v4.22): the home look
/// (the two designs of §11.2), the motion style (standard/smooth/dynamic
/// — the same knob the protocol page's patterns read), and the v4.22
/// background-patterns switch every page honors.
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SubPageFrame(
      store: store,
      title: strings.settingsAppearance,
      children: () => [
        // ---- Section: the home screen look ----
        SubSectionHeading(
          icon: AppAssets.iconHome1,
          title: strings.secHomeLook,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingPills<HomeLook>(
            keyId: 'home-look',
            options: [
              (HomeLook.one, strings.lookOne),
              (HomeLook.two, strings.lookTwo),
            ],
            selected: store.homeLook,
            onSelect: store.setHomeLook,
          ),
        ),

        // ---- Section: animation ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconActivity4,
          title: strings.secMotion,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingPills<MotionStyle>(
            keyId: 'motion',
            options: [
              (MotionStyle.standard, strings.motionStandard),
              (MotionStyle.smooth, strings.motionSmooth),
              (MotionStyle.dynamic, strings.motionDynamic),
            ],
            selected: store.animationStyle,
            onSelect: store.setMotionStyle,
          ),
        ),

        // ---- Section: background patterns ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconPalette,
          title: strings.secPatterns,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingToggleRow(
            keyId: 'show-patterns',
            icon: AppAssets.iconPalette,
            title: strings.showPatterns,
            description: strings.showPatternsDesc,
            value: store.showPatterns,
            onChanged: store.setShowPatterns,
          ),
        ),
      ],
    );
  }
}
