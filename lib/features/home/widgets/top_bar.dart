/// Home top bar: settings icon (START side — visual right in RTL), the
/// AETHONE wordmark centered, info icon (END side — visual left in RTL).
///
/// Behavior (owner text): settings icon → Settings; info icon → Telegram
/// channel t.me/AETHONE. The reference image shows an "i" (Information
/// Circle) icon — pending decision D1 we keep the reference icon and wire it
/// to the Telegram link (option A: honors both the image and the text).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key, required this.onSettings});

  final VoidCallback onSettings;

  static const String telegramChannelUrl = 'https://t.me/AETHONE';

  Future<void> _openTelegram() async {
    final uri = Uri.parse(telegramChannelUrl);
    // External browser/app — never an in-app webview.
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Opening failed (no handler). Honest no-op; diagnostics page (later
      // step) will surface such errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AethGeometry.pageHPadding * s),
      child: SizedBox(
        height: 44 * s,
        child: Row(
          children: [
            _TopBarIcon(
              asset: AppAssets.iconSetting,
              semanticLabel: 'Settings',
              onTap: onSettings,
            ),
            const Spacer(),
            // Wordmark — reference: Bold ~20–22px white.
            Text(
              'AETHONE',
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: 21 * s,
                letterSpacing: 2.5 * s,
                color: AethColors.textPrimary,
              ),
            ),
            const Spacer(),
            _TopBarIcon(
              asset: AppAssets.iconInformationCircle,
              semanticLabel: 'Telegram channel',
              onTap: _openTelegram,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({
    required this.asset,
    required this.semanticLabel,
    this.onTap,
  });

  final String asset;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: IconButton(
        onPressed: onTap,
        icon: SvgPicture.asset(
          asset,
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(
            AethColors.textPrimary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
