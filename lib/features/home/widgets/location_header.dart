/// Location header + flag carousel.
///
/// Connected (normal protocols): country name (visual LEFT) · map icon with a
/// small chevron (center) · ping in green (visual RIGHT) — pixel-verified in
/// the phase-1 report. Ping renders ONLY when really connected and measured.
///
/// Disconnected (normal protocols): the whole flags area is blurred and the
/// header reads «آفلاین» (owner rule + reference images).
///
/// Tor/Psiphon modes: the top area becomes the sub-mode selector (deferred to
/// the protocol-sheet step; documented in docs/UI_IMPLEMENTATION.md).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'custom_icons.dart';

/// Country flags shown in the carousel. Real exit locations arrive from the
/// engine (M2); until then the carousel renders this static set — the same
/// set the reference mock shows (mock flags are decorative, report 3.3-12).
const List<String> kCarouselFlagCodes = [
  'fr', 'es', 'gr', 'ge', 'ir', 'mx', 'de', 'us',
];

class LocationHeader extends StatelessWidget {
  const LocationHeader({
    super.key,
    required this.connected,
    required this.protocolIsTorOrPsiphon,
    required this.pingMs,
    required this.exitCountryCode,
    required this.onFlagSelected,
  });

  final bool connected;
  final bool protocolIsTorOrPsiphon;
  final int? pingMs;
  final String? exitCountryCode;
  final void Function(String code) onFlagSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;

    final Widget headerRow;
    if (connected) {
      headerRow = Row(
        children: [
          // START side (visual right in RTL): ping — green, measured only.
          Text(
            pingMs != null ? strings.pingMs(pingMs!) : '',
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w500,
              fontSize: 14 * s,
              color: AethColors.accentConnected,
            ),
          ),
          const Spacer(),
          // Center: map icon + small chevron below.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                AppAssets.iconMap,
                width: 22 * s,
                height: 22 * s,
                colorFilter: const ColorFilter.mode(
                  AethColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
              SizedBox(height: 2 * s),
              ChevronDownIcon(size: 8 * s, color: AethColors.textSecondary),
            ],
          ),
          const Spacer(),
          // END side (visual left in RTL): exit country name.
          Text(
            _countryName(exitCountryCode),
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w500,
              fontSize: 16 * s,
              color: AethColors.textPrimary,
            ),
          ),
        ],
      );
    } else {
      headerRow = Column(
        children: [
          Text(
            strings.offline,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w500,
              fontSize: 15 * s,
              color: AethColors.textSecondary,
            ),
          ),
          SizedBox(height: 2 * s),
          SvgPicture.asset(
            AppAssets.iconMap,
            width: 22 * s,
            height: 22 * s,
            colorFilter: const ColorFilter.mode(
              AethColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        headerRow,
        SizedBox(height: 10 * s),
        _FlagsArea(
          connected: connected,
          protocolIsTorOrPsiphon: protocolIsTorOrPsiphon,
          exitCountryCode: exitCountryCode,
          onFlagSelected: onFlagSelected,
        ),
      ],
    );
  }

  String _countryName(String? code) {
    // Minimal mapping for the carousel countries; full ISO table arrives with
    // the routing/onboarding step (the ZIP guide has all 266 codes).
    const names = <String, String>{
      'ir': 'ایران', 'fr': 'فرانسه', 'es': 'اسپانیا', 'gr': 'یونان',
      'ge': 'گرجستان', 'mx': 'مکزیک', 'de': 'آلمان', 'us': 'آمریکا',
      'tm': 'ترکمنستان', 'ru': 'روسیه', 'cn': 'چین',
    };
    if (code == null) return '';
    return names[code] ?? code.toUpperCase();
  }
}

class _FlagsArea extends StatelessWidget {
  const _FlagsArea({
    required this.connected,
    required this.protocolIsTorOrPsiphon,
    required this.exitCountryCode,
    required this.onFlagSelected,
  });

  final bool connected;
  final bool protocolIsTorOrPsiphon;
  final String? exitCountryCode;
  final void Function(String code) onFlagSelected;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final strings = AppStrings.of(context);
    final blurThis = !connected && !protocolIsTorOrPsiphon;

    final carousel = _FlagCarousel(
      flagSize: 42 * s,
      exitCountryCode: exitCountryCode,
      onFlagSelected: onFlagSelected,
    );

    if (!blurThis) {
      return carousel;
    }

    // Disconnected + normal protocol ⇒ the whole area is blurred (owner rule,
    // confirmed by the reference images) and shows the offline label.
    return Stack(
      alignment: Alignment.center,
      children: [
        carousel,
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6 * s, sigmaY: 6 * s),
              child: Container(
                color: AethColors.bgScreen.withValues(alpha: 0.30),
                alignment: Alignment.center,
                child: Text(
                  strings.offline,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w600,
                    fontSize: 16 * s,
                    color: AethColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlagCarousel extends StatelessWidget {
  const _FlagCarousel({
    required this.flagSize,
    required this.exitCountryCode,
    required this.onFlagSelected,
  });

  final double flagSize;
  final String? exitCountryCode;
  final void Function(String code) onFlagSelected;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    const codes = kCarouselFlagCodes;
    return SizedBox(
      height: flagSize * 1.35,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 24 * s),
        itemExtent: flagSize * 1.25,
        children: [
          for (final code in codes)
            Padding(
              padding: EdgeInsets.symmetric(vertical: flagSize * 0.14),
              child: _FlagItem(
                asset: AppAssets.flag(code),
                size: flagSize,
                selected: exitCountryCode == code,
                onTap: () => onFlagSelected(code),
              ),
            ),
        ],
      ),
    );
  }
}

class _FlagItem extends StatelessWidget {
  const _FlagItem({
    required this.asset,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String asset;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.2 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.24),
            border: selected
                ? Border.all(color: AethColors.textPrimary, width: 2)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.24),
            child: SvgPicture.asset(asset, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
