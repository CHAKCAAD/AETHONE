/// v4.35 — THE one theme-aware protocol-logo renderer (owner round 11,
/// items 4 + 5).
///
/// Item 4 («در صفحه انتخاب پروتکل در حالت لایت مود باید رنگ آیکون های سفید
/// به رنگ 141C16 تغیر کنه»): every logo whose night ink is WHITE now reads
/// [AethColors.textPrimary] — white at night (unchanged), `#141C16` in
/// light, riding the palette lerp like every other surface. The gold
/// accents stay gold in BOTH modes (the AUTO shield, گول کلاسیک, and the
/// میم dot — the frame's own identity colors).
///
/// Item 5 («آیکون هایی که دفعات قبل برای جایگزینی فرستادم … باید با سایه
/// هاشون و بدون هیچ تغیری در حالت نایت مود گزاشته بشن؛ در حالت لایت مود
/// باید رنگشون به 141C16 تغیر کنه و سایه اونها هم مشکی باشه مقدار سایه هم
/// دقیقا همون باشه»): the four combined-mode logos (سایفون اور وارپ /
/// وارپ اور سایفون / تور اور وارپ / وارپ اور تور) render as the owner's
/// own SVG artwork WITH their drop shadows — a black 81 % silhouette of the
/// vector art, offset +4 and gaussian-blurred exactly as the SVG's own
/// filter chain specifies (σ5 for the 38×41 pair, σ2 for the 24×35 pair,
/// scaled by the render size) — under the ink layer. Night: white art +
/// shadow, no other change. Light: `#141C16` art + the SAME black shadow
/// (identical values, per decree). flutter_svg skips the SVG's filter
/// primitives, so the shadow is REBUILT here from the same numbers.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';

const Color _goldInk = Color(0xFF997A35); // میم's dot / گول کلاسیک gold

class _ChainShadowSpec {
  const _ChainShadowSpec(this.viewBoxH, this.sigma, this.dy);
  final double viewBoxH;
  final double sigma;
  final double dy;
}

/// Per-protocol shadow constants for the combined-mode logos, read off the
/// owner's own SVG filter chains (feOffset dy=4; feGaussianBlur σ=5 for the
/// 38×41 artworks, σ=2 for the 24×35 ones; alpha multiplier 0.81 — the
/// owner's CSS restates it as `box-shadow: 0px 4px 10px rgba(0,0,0,0.81)`).
const Map<ProtocolId, _ChainShadowSpec> _chainShadows = {
  ProtocolId.psiphonChain: _ChainShadowSpec(41, 5, 4), // سایفون اور وارپ 38×41
  ProtocolId.torChain: _ChainShadowSpec(41, 5, 4), // تور اور وارپ 38×41
  ProtocolId.psiphonReverse: _ChainShadowSpec(35, 2, 4), // وارپ اور سایفون 24×35
  ProtocolId.torReverse: _ChainShadowSpec(35, 2, 4), // وارپ اور تور 24×35
};

/// One protocol logo at [size] (a square render box, logical px — the
/// caller applies the screen scale). Ink rules (v4.35):
///   * auto            → gold shield ([AethColors.goldAccent]); `white`
///                       (the selected green tile) forces the ink white as
///                       before.
///   * goolClassic     → gold const `#997A35` (its only ink — both modes).
///   * mim             → ink body + the gold dot overlay (const geometry
///                       read off the SVG: c(22.7222, 4.5) r4.5 in 39×32).
///   * psiphon/tor ONLY→ the raster logos, srcIn-tinted [textPrimary]
///                       (night white / light #141C16 — was hardcoded
///                       Colors.white, invisible on the light card).
///   * masque/wireguard/gool → the white single-ink SVGs, srcIn
///                       [textPrimary] (native was white-only).
///   * chain/reverse   → the owner's artwork + the rebuilt drop shadow.
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

  /// Forces the all-ink treatment the green selected tile uses (kept for
  /// AUTO's white-on-green; a no-op for the textPrimary inks).
  final bool white;

  @override
  Widget build(BuildContext context) {
    final ink = AethColors.textPrimary;
    final asset = AppAssets.protocolIcon(id);

    // AUTO — no dedicated artwork (report §6.9): the gold Shield Tick
    // (ink-white on the selected green tile).
    if (id == ProtocolId.auto) {
      return SvgPicture.asset(
        AppAssets.iconShieldTick,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(
          white ? ink : AethColors.goldAccent,
          BlendMode.srcIn,
        ),
      );
    }

    // The combined modes — the owner's artwork with its drop shadow
    // rebuilt (item 5). White art at night, #141C16 in light, the same
    // black shadow in both.
    final chainShadow = _chainShadows[id];
    if (chainShadow != null) {
      return _ShadowedChainGlyph(
        asset: asset,
        size: size,
        ink: ink,
        spec: chainShadow,
      );
    }

    // The raster family logos (psiphon/tor ONLY) — srcIn the theme ink.
    if (AppAssets.isRasterAsset(asset)) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: ink,
        colorBlendMode: BlendMode.srcIn,
      );
    }

    // گول کلاسیک — the gold-only artwork; the gold stays gold in both
    // modes (identity accent, not a white ink).
    if (id == ProtocolId.goolClassic) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: const ColorFilter.mode(_goldInk, BlendMode.srcIn),
      );
    }

    // میم — ink body + the gold dot on top (const SVG geometry), so the
    // body follows the theme while the dot keeps its identity color.
    if (id == ProtocolId.mim) {
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          SvgPicture.asset(
            asset,
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
          ),
          _MimGoldDot(size: size),
        ],
      );
    }

    // masque / wireguard / gool — single white ink at night; srcIn the
    // theme ink so light mode reads #141C16 (item 4).
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
    );
  }
}

/// The owner's combined-mode artwork + the rebuilt drop shadow: a black
/// 81 % silhouette of the vector art, translated by the SVG's own dy and
/// gaussian-blurred at the SVG's own σ (scaled to the render size), painted
/// under the ink layer.
class _ShadowedChainGlyph extends StatelessWidget {
  const _ShadowedChainGlyph({
    required this.asset,
    required this.size,
    required this.ink,
    required this.spec,
  });

  final String asset;
  final double size;
  final Color ink;
  final _ChainShadowSpec spec;

  @override
  Widget build(BuildContext context) {
    // Render-scale against the SVG's own viewBox height (the shadow numbers
    // live in viewBox units).
    final k = size / spec.viewBoxH;
    final dy = spec.dy * k;
    final sigma = spec.sigma * k;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // The shadow — the artwork's own silhouette at 81 % black.
        Transform.translate(
          offset: Offset(0, dy),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.decal,
            ),
            child: SvgPicture.asset(
              asset,
              width: size,
              height: size,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                Color(0xCF000000), // rgba(0,0,0,0.81) — the owner's CSS
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        // The art — white at night, #141C16 in light (the palette lerp).
        SvgPicture.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
        ),
      ],
    );
  }
}

/// میم's gold dot — a circle at c(22.7222, 4.5) r4.5 inside the 39×32
/// viewBox, repositioned at the render scale so the body can be srcIn'd
/// with the theme ink while the dot keeps `#997A35`.
///
/// Geometry: the 39×32 viewBox renders into the square box with contain
/// (scale = size/39 — width-limited), so the art spans the full box width
/// and is letterboxed vertically by (size − 32·size/39)/2.
class _MimGoldDot extends StatelessWidget {
  const _MimGoldDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = size / 39;
    final letterboxTop = (size - 32 * scale) / 2;
    final cx = 22.7222 * scale;
    final cy = letterboxTop + 4.5 * scale;
    final r = 4.5 * scale;
    return Positioned(
      left: cx - r,
      top: cy - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: const BoxDecoration(
            color: _goldInk,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
