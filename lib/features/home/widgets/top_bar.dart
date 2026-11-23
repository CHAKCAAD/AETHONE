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
            // v5.3 — NOT const (deliberate): a canonicalized const child is
            // skipped by updateChild on every rebuild, so its build ran
            // exactly ONCE and the theme ink never re-read — the owner's
            // wordmark report («در هردوحالت رنگ سفید داره»). The palette
            // tick must be able to rebuild this subtree.
            // ignore: prefer_const_constructors
            _Wordmark(),
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
            // v4.35 (owner round 11, item 1): NO shadow in light mode —
            // the color rides the palette (night rgba(0,0,0,0.25) 0 4 4 /
            // light transparent) and fades with the 420 ms mode tween.
            boxShadow: [
              BoxShadow(
                color: AethColors.tileShadow,
                offset: const Offset(0, 4),
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

/// The AETHONE wordmark — v5 («نمای 2»): plain bold text, NO brand mark
/// behind it (the committed mockups show the bare wordmark; the v4.11
/// mark-behind-the-letters is retired with the redesign).
///
/// v5.3 (the owner's dark-mode round) — TWO fixes:
///  * «نوشته AETHONE بالای صفحه اصلی حالت دارک و لایت رو رعایت نمیکنه و
///    در هردوحالت رنگ سفید داره»: the mark was mounted as a `const`
///    instance — a canonicalized const child is SKIPPED by Flutter's
///    updateChild on every rebuild, so its build ran exactly ONCE and the
///    theme ink never re-read. It is a plain (non-const) widget now, so
///    every palette tick of the 420 ms mode tween re-reads [wordmarkInk]
///    (white at night, black in light).
///  * the owner's new CSS pins the home lockup at 18px / weight 800.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Text(
      'AETHONE',
      style: TextStyle(
        fontFamily: 'IRANYekanX',
        fontWeight: FontWeight.w800,
        fontSize: AethGeometry.homeWordmarkFontSize * s,
        letterSpacing: AethGeometry.wordmarkLetterSpacing * s,
        // v4.41 (round 17, item 10) + v1.0.0 (round 18): white at night,
        // black in light — the resolved slots, never the lerped palette.
        color: AethColors.wordmarkInk,
      ),
    );
  }
}
