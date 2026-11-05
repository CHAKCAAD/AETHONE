/// Home top bar: settings icon tile (START side — visual right in RTL), the
/// AETHONE wordmark centered with the real brand mark (آیکون اپ/2.svg)
/// BEHIND it, theme-toggle tile (END side — visual left in RTL).
///
/// v4.11 (owner defect reports #7 + #14):
///   * #7 — both top icons sit on the owner Figma «Rectangle 9» tile:
///     50×50, #0F1510, radius 16, shadow 0 4 4 rgba(0,0,0,0.25).
///   * #14 — the mark behind the wordmark is the REAL 2.svg artwork rendered
///     with its own gradients (the previous flat bright-green painter is
///     gone; the owner rejected the flat green color).
///
/// v4.34 — the info tile is now the NIGHT ⇄ LIGHT switch (owner round 10:
/// «آیکون علامت تعجب بالای همه صفحه هارو … تغیر حالت بین دارک مود و لایت
/// مود رو به این بخش میدیم»); the Telegram channel link lives on in the
/// settings pages' rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../connection/connection_store.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../shared/theme_toggle_tile.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key, required this.onSettings, required this.store});

  final VoidCallback onSettings;

  /// v4.34 — the theme toggle reads/writes the store's [ConnectionStore.
  /// themeMode].
  final ConnectionStore store;

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
            ThemeToggleTile(
              store: store,
              size: tile,
              iconSize: AethGeometry.topTileIcon * s,
              tileKey: const ValueKey('home-theme-toggle'),
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
              colorFilter: ColorFilter.mode(
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
