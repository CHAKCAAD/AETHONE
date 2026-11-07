/// v4.40 — THE one protocol-logo renderer (owner round 16, the icon-set
/// round).
///
/// The owner's decree («رنگ و شکل آیکون ها باید دقیقا همین فایل هایی باشه
/// که برات ارسال شده»): every logo renders as its OWN file, colors and
/// shapes untouched — no srcIn tint, no rebuilt drop shadows, no derived
/// gold dots. The four protocols the owner sent in TWO faces
/// (ماسک/میم/وایرگارد/گول) pick their «لایت»/«دارک» variant by the RESOLVED
/// theme ([AethThemeSync.light] — the same slot the palette reads, so the
/// icon cross-fades with the 420 ms theme tween and rides the auto mode);
/// tor/psiphon/gool-classic and the combined modes carry ONE face for both
/// themes (the owner's own «هر دو حالت» naming).
///
/// The selected green tile keeps the app's standing all-ink-white rule
/// (v4.35, the AUTO precedent — [white]): a solid-green artwork (وارپ اور
/// تور / وارپ اور سایفون are #1AD995 — the tile's own fill) would vanish
/// on its selected tile otherwise.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_assets.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';

class ProtocolGlyph extends StatelessWidget {
  const ProtocolGlyph({
    super.key,
    required this.id,
    required this.size,
    this.white = false,
  });

  final ProtocolId id;

  /// Square render box in logical px (the caller scales by the screen).
  final double size;

  /// The all-ink treatment the green selected tile uses (kept from v4.35:
  /// the selected tile's own fill is the accent green — a green artwork
  /// (وارپ اور X) would be invisible on it).
  final bool white;

  @override
  Widget build(BuildContext context) {
    final asset = AppAssets.protocolIcon(id, light: AethThemeSync.light);

    // AUTO — no dedicated artwork in the owner's round-16 set (report
    // §6.9): the gold Shield Tick (ink-white on the selected green tile).
    if (id == ProtocolId.auto) {
      return SvgPicture.asset(
        AppAssets.iconShieldTick,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(
          white ? AethColors.textPrimary : AethColors.goldAccent,
          BlendMode.srcIn,
        ),
      );
    }

    // Every real protocol: the owner's own file, EXACTLY as delivered.
    // `white` (the selected green tile) keeps the standing all-ink rule.
    if (white) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(
          Color(0xFFFFFFFF),
          BlendMode.srcIn,
        ),
      );
    }
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
