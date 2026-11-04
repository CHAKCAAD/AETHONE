/// «تنظیمات زبان» — the language sub-page (v4.22): the interface-language
/// override (null = follow the system), applied app-wide through
/// [ConnectionStore.appLocale] → the shell's MaterialApp.locale. The
/// option labels render in each language's OWN name (the standard
/// practice — «English» stays «English» in every locale).
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    // null = follow the system; the pills speak the sentinel form.
    final current = store.appLocale ?? 'system';
    return SubPageFrame(
      store: store,
      title: strings.settingsLanguage,
      children: () => [
        SubSectionHeading(
          icon: AppAssets.iconWebsite,
          title: strings.secAppLanguage,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingPills<String>(
                keyId: 'app-locale',
                options: [
                  ('system', strings.langSystem),
                  ('fa', 'فارسی'),
                  ('tk', strings.langTurkmen),
                  ('en', 'English'),
                  ('ru', 'Русский'),
                  ('zh', '中文（简体）'),
                ],
                selected: current,
                onSelect: (code) =>
                    store.setAppLocale(code == 'system' ? null : code),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.langDesc),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
      ],
    );
  }
}
