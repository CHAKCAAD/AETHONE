/// «تنظیمات عمومی» — the general sub-page (v4.22): the honest About block
/// (the real version const, the real Telegram channel, the real repo) and
/// the notifications block, which today carries one honest coming-line
/// instead of any fake toggle (the OS integration step owns it).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/app_meta.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  Future<void> _openRepository() async {
    final uri = Uri.parse(repositoryUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

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
                trailingValue: appVersion,
                chevron: false,
                onTap: () {}, // a value row — not a navigation target
              ),
              const SubSectionDivider(),
              SettingNavRow(
                keyId: 'telegram',
                icon: AppAssets.iconSend,
                title: strings.telegramRow,
                onTap: openTelegramChannel,
              ),
              const SubSectionDivider(),
              SettingNavRow(
                keyId: 'repository',
                icon: AppAssets.logoGithub,
                title: strings.githubRow,
                onTap: _openRepository,
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
