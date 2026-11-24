/// v1.0.2 — the one-tap Telegram proxy row, shared by every protocol page
/// (owner: «دکمه پروکسی تلگرام رو برای سایر پروتکل ها هم توی تنظیمات
/// مربوط به خودشون بزار»). It hands the protocol's own loopback SOCKS
/// listener to Telegram's add-proxy deep link (`tg://socks`), so Telegram
/// talks SOCKS straight to the core instead of riding the TUN.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../connection/transport_modes.dart';
import '../../../core/app_assets.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';

class TelegramProxyRow extends StatelessWidget {
  const TelegramProxyRow({super.key, required this.keyId, required this.mode});

  final String keyId;

  /// The transport mode whose listener Telegram should use.
  final TransportMode mode;

  /// Telegram's own add-proxy deep link for [mode]'s loopback listener.
  static Uri uriFor(TransportMode mode) {
    final ep = mode.socksEndpoint;
    return Uri.parse('tg://socks?server=${ep.host}&port=${ep.port}');
  }

  Future<void> _open(BuildContext context) async {
    final failed = AppStrings.of(context).lanternTelegramFailed;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var ok = false;
    try {
      ok = await launchUrl(uriFor(mode), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final ep = mode.socksEndpoint;
    return SettingNavRow(
      keyId: keyId,
      icon: AppAssets.iconSend,
      title: strings.lanternTelegramLabel,
      description: strings.telegramProxyDesc
          .replaceAll('{addr}', '${ep.host}:${ep.port}'),
      onTap: () => _open(context),
    );
  }
}
