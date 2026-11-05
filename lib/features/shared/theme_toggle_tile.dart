/// v4.34 — the theme-toggle tile (owner round 10: «آیکون علامت تعجب بالای
/// همه صفحه هارو برای اینکار در نظر میگیریم و تغیر حالت بین دارک مود و
/// لایت مود رو به این بخش میدیم»).
///
/// The top-bar info tile on EVERY page becomes the night ⇄ light switch:
///  * light mode active → the «Sun 1» glyph, ink `#2D264B` (the owner CSS
///    «Hicon / Linear / Sun 1 … border: 2px solid #2D264B; /* Primary */»);
///  * night mode active → the «Moon» glyph, ink `#FFFFFF` (the owner CSS
///    «Broken / Weather / Moon … border: 1.5px solid #FFFFFF»).
/// The glyph cross-fades on the switch; the tile itself rides the same
/// animated palette as every other surface (the shell's 420 ms tween).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';

class ThemeToggleTile extends StatelessWidget {
  const ThemeToggleTile({
    super.key,
    required this.store,
    required this.size,
    required this.iconSize,
    this.tileKey,
  });

  final ConnectionStore store;

  /// The owner «Rectangle 9» tile size (50 × scale).
  final double size;

  final double iconSize;

  /// Optional ValueKey (the pages keep their test keys).
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final light = store.themeMode == AethThemeMode.light;
    return Semantics(
      key: tileKey,
      label: light ? 'Switch to night mode' : 'Switch to light mode',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: store.toggleThemeMode,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: SvgPicture.asset(
                key: ValueKey<bool>(light),
                light ? AppAssets.iconSun1 : AppAssets.iconMoon,
                width: iconSize,
                height: iconSize,
                colorFilter: ColorFilter.mode(
                  light
                      ? const Color(0xFF2D264B) // owner CSS «Primary»
                      : const Color(0xFFFFFFFF), // owner CSS Moon stroke
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
