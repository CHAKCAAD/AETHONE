/// Location header + flag WHEEL (v4.11 — owner defect reports #8/#9/#14):
///
/// Header row (fixed visual layout, LTR-locked): country name LEFT ·
/// map icon CENTER (Spacers keep it centered) · ping/offline RIGHT.
///   * connected  : name = wheel/exit country (white) · «146 ms» green.
///   * disconnected: name = wheel selection (grey) · «آفلاین» grey in the
///     SAME slot the ping occupies when connected (defect #9 — the offline
///     text no longer sits on the location selector nor pushes the map icon
///     sideways).
///   * connecting : the ping slot stays empty (honest — nothing measured).
///
/// Flag wheel («پله‌ای» — defect #8): a horizontal ListView with 72px pitch;
/// the flag nearest the viewport centre is continuously enlarged (52 vs 42)
/// AND becomes the selection while you scroll; on release the wheel snaps to
/// the nearest flag; tapping a flag centres + selects it. The country name
/// above updates live with the wheel selection (defect #8 second half).
///
/// Disconnected state (defect #14): NO blur anywhere — protocols WITHOUT a
/// location selector get a locked wheel + a black-and-white (saturation-0)
/// color effect; Tor/Psiphon (which DO select a location) stay fully normal.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'custom_icons.dart';

class LocationHeader extends StatefulWidget {
  const LocationHeader({
    super.key,
    required this.connected,
    required this.protocolIsTorOrPsiphon,
    required this.pingMs,
    required this.exitCountryCode,
    required this.onCountrySelected,
  });

  final bool connected;
  final bool protocolIsTorOrPsiphon;
  final int? pingMs;
  final String? exitCountryCode;

  /// Wheel selection committed (snap settle or tap). The store keeps it for
  /// the future core handoff (defect #13 note: per-protocol location rules
  /// are re-checked when the engine lands).
  final void Function(String code) onCountrySelected;

  @override
  State<LocationHeader> createState() => _LocationHeaderState();
}

class _LocationHeaderState extends State<LocationHeader> {
  static const String defaultCode = 'ir';

  List<String> _codes = const [defaultCode];
  String _selected = defaultCode;
  ScrollController? _controller;

  @override
  void initState() {
    super.initState();
    _selected = widget.exitCountryCode ?? defaultCode;
    _loadCodes();
  }

  @override
  void didUpdateWidget(covariant LocationHeader old) {
    super.didUpdateWidget(old);
    // Follow the ENGINE-reported exit country when it arrives/changes.
    if (widget.exitCountryCode != null &&
        widget.exitCountryCode != old.exitCountryCode) {
      _select(widget.exitCountryCode!, notify: false);
      _centerOn(_indexOf(_selected), animate: true);
    }
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOn(_indexOf(_selected));
    });
  }

  int _indexOf(String code) {
    final i = _codes.indexOf(code);
    return i < 0 ? _codes.indexOf(defaultCode).clamp(0, _codes.length - 1) : i;
  }

  void _select(String code, {bool notify = true}) {
    if (_selected == code) return;
    setState(() => _selected = code);
    if (notify) widget.onCountrySelected(code);
  }

  void _ensureController(double extent, double viewport) {
    _controller ??= ScrollController(
      initialScrollOffset:
          (_indexOf(_selected) * extent).clamp(0.0, double.infinity),
    );
  }

  void _centerOn(int index, {bool animate = false}) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final extent = AethGeometry.flagPitch * s;
    final target = (index * extent)
        .clamp(0.0, controller.position.maxScrollExtent);
    if (animate) {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(target);
    }
  }

  int get _focusIndex {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return _indexOf(_selected);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final extent = AethGeometry.flagPitch * s;
    return (controller.offset / extent).round().clamp(0, _codes.length - 1);
  }

  void _onScrollEnd() {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final extent = AethGeometry.flagPitch * s;
    final focus = _focusIndex;
    _select(_codes[focus]);
    final target = (focus * extent)
        .clamp(0.0, controller.position.maxScrollExtent);
    if ((controller.offset - target).abs() > 0.5) {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final connected = widget.connected;

    // Defect #14: locked + greyscale ONLY for protocols without a location
    // selector while disconnected. Tor/Psiphon (and any connected state)
    // stay normal. NO blur anywhere.
    final locked = !connected && !widget.protocolIsTorOrPsiphon;

    final Widget headerRow = Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(
          left: AethGeometry.locationInsetStart * s,
          right: AethGeometry.locationInsetEnd * s,
        ),
        child: Row(
          children: [
            // LEFT — the wheel-selected country (white when connected,
            // grey when offline). Updates live with the wheel (defect #8).
            Flexible(
              child: Text(
                countryName(_selected) ?? '',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w500,
                  fontSize: 15 * s,
                  color: connected
                      ? AethColors.textPrimary
                      : AethColors.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            // CENTER — map icon + small chevron below.
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
            // RIGHT — exactly ONE status text slot: the ping when connected
            // and measured, «آفلاین» when disconnected (defect #9), nothing
            // while the engine is still walking (honest).
            Flexible(
              child: Text(
                connected
                    ? (widget.pingMs != null
                        ? strings.pingMs(widget.pingMs!)
                        : '')
                    : strings.offline,
                textDirection: TextDirection.ltr,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w500,
                  fontSize: 14 * s,
                  color: connected
                      ? AethColors.accentConnected
                      : AethColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    _ensureController(
      AethGeometry.flagPitch * s,
      MediaQuery.sizeOf(context).width,
    );

    return Column(
      children: [
        headerRow,
        SizedBox(height: AethGeometry.gapLocationToFlags * s),
        _FlagsWheel(
          codes: _codes,
          controller: _controller,
          selected: _selected,
          locked: locked,
          extent: AethGeometry.flagPitch * s,
          onFocusChanged: (code) => _select(code),
          onTapFlag: (code) {
            if (locked) return;
            _select(code);
            _centerOn(_indexOf(code), animate: true);
          },
          onScrollEnd: locked ? null : _onScrollEnd,
        ),
      ],
    );
  }
}

/// The horizontal flag wheel. Always occupies the SAME slot (stable tree) —
/// the v4.10 lesson: swapping the carousel for an overlay reset the scroll.
class _FlagsWheel extends StatelessWidget {
  const _FlagsWheel({
    required this.codes,
    required this.controller,
    required this.selected,
    required this.locked,
    required this.extent,
    required this.onFocusChanged,
    required this.onTapFlag,
    required this.onScrollEnd,
  });

  final List<String> codes;
  final ScrollController? controller;
  final String selected;
  final bool locked;
  final double extent;
  final void Function(String code) onFocusChanged;
  final void Function(String code) onTapFlag;
  final VoidCallback? onScrollEnd;

  static const List<double> _grayscaleMatrix = [
    // 5x4 saturation-0 matrix (rec709 luma weights).
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final viewport = MediaQuery.sizeOf(context).width;
    final wheel = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // Live stepper: the flag nearest the centre grows and becomes the
          // selection while scrolling (defect #8).
          final controller = this.controller;
          if (controller != null && controller.hasClients) {
            final focus =
                (controller.offset / extent).round().clamp(0, codes.length - 1);
            if (codes[focus] != selected) onFocusChanged(codes[focus]);
          }
        } else if (notification is ScrollEndNotification) {
          onScrollEnd?.call();
        }
        return false;
      },
      child: SizedBox(
        height: AethGeometry.flagSizeSelected * s,
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemExtent: extent,
          // Centreing padding so ANY item can rest exactly on the centre.
          padding: EdgeInsets.symmetric(horizontal: (viewport - extent) / 2),
          physics: locked ? const NeverScrollableScrollPhysics() : null,
          itemCount: codes.length,
          itemBuilder: (context, i) {
            final code = codes[i];
            final isSelected = code == selected;
            // Brightness falloff away from the selected flag.
            final distance = (i - codes.indexOf(selected)).abs();
            final opacity = isSelected
                ? 1.0
                : switch (distance) {
                    1 => 0.85,
                    2 => 0.62,
                    _ => 0.45,
                  };
            return Center(
              child: _FlagItem(
                asset: AppAssets.flag(code),
                size: (isSelected
                        ? AethGeometry.flagSizeSelected
                        : AethGeometry.flagSize) *
                    s,
                opacity: opacity,
                onTap: () => onTapFlag(code),
              ),
            );
          },
        ),
      ),
    );

    // Defect #14: greyscale (saturation 0) instead of blur — and nothing
    // else: no overlay, no text on top of the wheel.
    if (locked) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
        child: wheel,
      );
    }
    return wheel;
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
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

/// Country display names for the wheel (full ISO table arrives with the
/// routing/onboarding step — the ZIP guide has all 266 codes).
String? countryName(String? code) {
  const names = <String, String>{
    'ir': 'ایران', 'fr': 'فرانسه', 'es': 'اسپانیا', 'gr': 'یونان',
    'ge': 'گرجستان', 'mx': 'مکزیک', 'de': 'آلمان', 'us': 'آمریکا',
    'tm': 'ترکمنستان', 'ru': 'روسیه', 'cn': 'چین', 'gb': 'انگلستان',
    'nl': 'هلند', 'tr': 'ترکیه', 'it': 'ایتالیا', 'no': 'نروژ',
    'eg': 'مصر', 'kr': 'کره جنوبی', 'kp': 'کره شمالی', 'kw': 'کویت',
    'km': 'کومور', 'kn': 'سنت کیتس', 'at': 'اتریش', 'au': 'استرالیا',
  };
  if (code == null) return null;
  return names[code] ?? code.toUpperCase();
}
