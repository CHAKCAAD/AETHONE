/// Home top bar: settings icon tile (START side — visual right in RTL), the
/// AETHONE wordmark centered with the real brand mark (آیکون اپ/2.svg)
/// BEHIND it, info icon tile (END side — visual left in RTL).
///
/// v4.11 (owner defect reports #7 + #14):
///   * #7 — both top icons sit on the owner Figma «Rectangle 9» tile:
///     50×50, #0F1510, radius 16, shadow 0 4 4 rgba(0,0,0,0.25).
///   * #14 — the mark behind the wordmark is the REAL 2.svg artwork rendered
///     with its own gradients (the previous flat bright-green painter is
///     gone; the owner rejected the flat green color).
///
/// Behavior: settings icon → Settings; info icon → Telegram channel
/// t.me/AETHONE.
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
    final tile = AethGeometry.topTileSize * s;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AethGeometry.pageHPadding * s),
      child: SizedBox(
        height: tile,
        child: Row(
          children: [
            _IconTile(
              asset: AppAssets.iconSetting,
              size: tile,
              iconSize: AethGeometry.topTileIcon * s,
              semanticLabel: 'Settings',
              onTap: onSettings,
            ),
            const Spacer(),
            const _Wordmark(),
            const Spacer(),
            _IconTile(
              asset: AppAssets.iconInformationCircle,
              size: tile,
              iconSize: AethGeometry.topTileIcon * s,
              semanticLabel: 'Telegram channel',
              onTap: _openTelegram,
            ),
          ],
        ),
      ),
    );
  }
}

/// The owner «Rectangle 9» tile: dark rounded square + soft drop shadow +
/// the white linear icon centered.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.asset,
    required this.size,
    required this.iconSize,
    required this.semanticLabel,
    this.onTap,
  });

  final String asset;
  final double size;
  final double iconSize;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AethColors.topTile,
            borderRadius: BorderRadius.circular(AethGeometry.topTileRadius * s),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000), // rgba(0,0,0,0.25) 0 4 4
                offset: Offset(0, 4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              asset,
              width: iconSize,
              height: iconSize,
              colorFilter: const ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The AETHONE wordmark: white bold text with the REAL brand mark (2.svg,
/// its own gradient facets) centered BEHIND the letters — measured on the
/// reference frames: mark ≈38px centered on the wordmark center.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final fontSize = AethGeometry.wordmarkFontSize * s;
    return Stack(
      alignment: Alignment.center,
      children: [
        SvgPicture.asset(
          AppAssets.brandMark,
          width: AethGeometry.brandMarkSize * s,
          height: AethGeometry.brandMarkSize * s,
          fit: BoxFit.contain,
          // The artwork renders with its OWN gradient colors (v4.11, owner
          // defect #14: the flat green tint was wrong).
        ),
        Text(
          'AETHONE',
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            letterSpacing: AethGeometry.wordmarkLetterSpacing * s,
            color: AethColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
