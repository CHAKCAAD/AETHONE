/// «تنظیمات ظاهری» — the appearance sub-page: the home look (the two
/// designs of §11.2), the motion style, and the v4.22 background-patterns
/// switch every page honors.
///
/// v4.25 — the owner's «انیمیشن‌های اختصاصی» round: the style picker now
/// offers ALL FOUR personalities (استاندارد SILK · نرم TIDE · پویا SPRING ·
/// حداقلی BLINK — each with its own choreography, see [MotionRecipe]) and
/// the section gains the master kill-switch row «خاموش کردن همهٔ
/// انیمیشن‌ها»: flipping it clamps the whole app to [MotionStyle.off]
/// instantly (the pick itself stays remembered — flipping back restores
/// it).
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // v4.25 — the four styles; each one is a distinct personality
              // (rise/zoom/curve/stagger/sway all differ — motion.dart).
              SettingPills<MotionStyle>(
                keyId: 'motion',
                options: [
                  (MotionStyle.standard, strings.motionStandard),
                  (MotionStyle.smooth, strings.motionSmooth),
                  (MotionStyle.dynamic, strings.motionDynamic),
                  (MotionStyle.minimal, strings.motionMinimal),
                ],
                selected: store.animationStyle,
                onSelect: store.setMotionStyle,
              ),
              const SubSectionGap.betweenRows(),
              // v4.25 — the master kill-switch (owner: «یه دکمه هم برای
              // خاموش کردن همه انیمیشن ها بزار»): ON = every animation in
              // the app stops instantly, whatever the style pick above.
              SettingToggleRow(
                keyId: 'animations-off',
                icon: AppAssets.iconCloseCircle,
                title: strings.animationsOffTitle,
                description: strings.animationsOffDesc,
                value: !store.animationsEnabled,
                onChanged: (off) => store.setAnimationsEnabled(!off),
              ),
            ],
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
