/// Location header + flag carousel.
///
/// v4.10 pixel-faithful layout (measured on the reference frames):
///  * Connected (normal protocols): a COMPACT row — exit-country name at
///    x≈95 (visual LEFT), map icon + small chevron at the CENTER (x≈201),
///    ping in green ending at x≈324 (visual RIGHT). The row is NOT flush
///    with the screen edges. Ping renders ONLY when really connected and
///    measured, and is forced LTR so «146 ms» can never flip to «ms 146»
///    under the Persian RTL locale (the bidi bug seen on the first device
///    build). The flag artworks ship as pre-rendered PNGs (v4.10) because
///    265 of the 266 committed SVGs embed the artwork as a raster image
///    inside an SVG `pattern`, which flutter_svg cannot render.
///  * Disconnected (normal protocols): the same compact row reads «آفلاین»
///    and the whole flags area is blurred (owner rule + reference images).
///  * Tor/Psiphon modes: the top area becomes the sub-mode selector
///    (deferred to the protocol-sheet step; documented in
///    docs/UI_IMPLEMENTATION.md).
///
/// Flags: horizontally swipeable carousel (owner: «پرچم کشورها به صورت
/// اسلایدی با انیمشن جابه جا میشوند») — the selected country sits at the
/// CENTER, slightly larger (52 vs 42), with a brightness falloff towards the
/// edges, exactly like the reference row (pitch 72). All 266 committed flag
/// artworks ship as PNGs extracted from the owner's own SVGs (v4.10 — the
/// SVGs embed the artwork as a raster `image` element which flutter_svg
/// cannot show).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'custom_icons.dart';

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

    final Widget headerRow = Directionality(
      // Fixed visual layout (reference): name LEFT · icon CENTER · ping RIGHT.
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(
          left: AethGeometry.locationInsetStart * s,
          right: AethGeometry.locationInsetEnd * s,
        ),
        child: Row(
          children: [
            Text(
              connected ? _countryName(exitCountryCode) : strings.offline,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w500,
                fontSize: 15 * s,
                color:
                    connected ? AethColors.textPrimary : AethColors.textSecondary,
              ),
            ),
            const Spacer(),
            // Center: map icon + small chevron below (reference y 116–148).
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  AppAssets.iconMap,
                  width: 22 * s,
                  height: 22 * s,
                  colorFilter: ColorFilter.mode(
                    connected
                        ? AethColors.textPrimary
                        : AethColors.textSecondary,
                    BlendMode.srcIn,
                  ),
                ),
                SizedBox(height: 2 * s),
                ChevronDownIcon(size: 8 * s, color: AethColors.textSecondary),
              ],
            ),
            const Spacer(),
            // Ping — LTR-locked so the digits always lead («146 ms»).
            Text(
              pingMs != null ? strings.pingMs(pingMs!) : '',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w500,
                fontSize: 14 * s,
                color: AethColors.accentConnected,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      children: [
        headerRow,
        SizedBox(height: AethGeometry.gapLocationToFlags * s),
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

class _FlagsArea extends StatefulWidget {
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
  State<_FlagsArea> createState() => _FlagsAreaState();
}

class _FlagsAreaState extends State<_FlagsArea> {
  List<String> _codes = const [];
  String? _picked;
  ScrollController? _controller;

  @override
  void initState() {
    super.initState();
    _picked = widget.exitCountryCode;
    _loadCodes();
  }

  @override
  void didUpdateWidget(covariant _FlagsArea old) {
    super.didUpdateWidget(old);
    if (widget.exitCountryCode != old.exitCountryCode &&
        widget.exitCountryCode != null) {
      _picked = widget.exitCountryCode;
      _centerOn(_indexOf(_picked), animate: true);
    }
  }

  /// All committed country codes, resolved from the asset manifest (the
  /// flags ship as a directory asset, so the bundle lists every file).
  Future<void> _loadCodes() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'design/flags_png/';
    final codes = manifest
        .listAssets()
        .where((p) => p.startsWith(prefix) && p.endsWith('.png'))
        .map((p) => p.substring(prefix.length, p.length - 4))
        .toList()
      ..sort();
    if (!mounted) return;
    setState(() => _codes = codes);
    // Codes arrived after the first frame — center the picked country now
    // that the items exist (post-frame so the ListView has attached).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOn(_indexOf(_picked));
    });
  }

  int _indexOf(String? code) {
    if (code == null) return 0;
    final i = _codes.indexOf(code);
    return i < 0 ? 0 : i;
  }

  void _ensureController(double extent, double viewport) {
        _controller ??= ScrollController(
      initialScrollOffset:
          (_indexOf(_picked) * extent - (viewport - extent) / 2)
              .clamp(0.0, double.infinity),
    );
  }

  void _centerOn(int index, {bool animate = false}) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final extent = AethGeometry.flagPitch * s;
    final viewport = controller.position.viewportDimension;
    final target = (index * extent - (viewport - extent) / 2)
        .clamp(0.0, controller.position.maxScrollExtent);
    if (animate) {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final strings = AppStrings.of(context);
    final blurThis = !widget.connected && !widget.protocolIsTorOrPsiphon;
    final extent = AethGeometry.flagPitch * s;
    final width = MediaQuery.sizeOf(context).width;
    _ensureController(extent, width);

    final carousel = _FlagCarousel(
      codes: _codes,
      controller: _controller,
      selected: _picked,
      onFlagSelected: (code) {
        setState(() => _picked = code);
        widget.onFlagSelected(code);
        _centerOn(_indexOf(code), animate: true);
      },
    );

    // Stable tree: the carousel ALWAYS occupies the same slot so the
    // ListView (and its scroll position) survives the blur overlay coming
    // and going — replacing it reset the scroll to 0 (v4.10 device bug).
    return Stack(
      alignment: Alignment.center,
      children: [
        carousel,
        if (blurThis)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter:
                    ui.ImageFilter.blur(sigmaX: 6 * s, sigmaY: 6 * s),
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
    required this.codes,
    required this.controller,
    required this.selected,
    required this.onFlagSelected,
  });

  final List<String> codes;
  final ScrollController? controller;
  final String? selected;
  final void Function(String code) onFlagSelected;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final extent = AethGeometry.flagPitch * s;
    final selectedIdx = selected == null ? -1 : codes.indexOf(selected!);

    return SizedBox(
      height: AethGeometry.flagSizeSelected * s,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        itemExtent: extent,
        padding: EdgeInsets.zero,
        itemCount: codes.length,
        itemBuilder: (context, i) {
          final code = codes[i];
          final distance = selectedIdx < 0 ? 0 : (i - selectedIdx).abs();
          // Brightness falloff away from the selected flag (reference row:
          // the selected Iran tile is bright, neighbours fade out).
          final opacity = switch (distance) {
            0 => 1.0,
            1 => 0.85,
            2 => 0.62,
            _ => 0.45,
          };
          return Center(
            child: _FlagItem(
              asset: AppAssets.flag(code),
              size: (distance == 0
                      ? AethGeometry.flagSizeSelected
                      : AethGeometry.flagSize) *
                  s,
              opacity: opacity,
              onTap: () => onFlagSelected(code),
            ),
          );
        },
      ),
    );
  }
}

class _FlagItem extends StatelessWidget {
  const _FlagItem({
    required this.asset,
    required this.size,
    required this.opacity,
    required this.onTap,
  });

  final String asset;
  final double size;
  final double opacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.24),
            child: Image.asset(asset, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
