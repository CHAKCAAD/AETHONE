/// Location header + flag WHEEL (v4.12 — owner defect reports, round 3):
///
/// Header row (v4.12, LTR-locked): the owner moved the whole location readout
/// to the LEFT-OF-CENTER of the screen as ONE compact cluster —
///   [country name] · [map icon + chevron] · [ping / offline]
/// starting at the reference x95 inset («قسمت آیکون بالا و متن پینگ و نام
/// کشور در سمت چپ وسط صفحه قرار نگرفتن»). The rest of the row stays empty.
///   * connected  : name = wheel/exit country (white) · «146 ms» green.
///   * disconnected: name = wheel selection (grey) · «آفلاین» grey.
///   * connecting : the ping slot stays empty (honest — nothing measured).
///
/// Flag wheel — INFINITE (v4.12): the 266 flags repeat 201× in a huge virtual
/// list started at its center, so the wheel can spin forever in BOTH
/// directions and there is ALWAYS a flag on the left AND the right edge
/// («پرچم ها باید به حالت اسکرول بی نهایت بچرخن ... در حال حاضر سمت راست
/// هیچ پرچمی وجود نداره»). The flag nearest the viewport centre is enlarged
/// (52 vs 42) and becomes the selection live while scrolling; on release the
/// wheel snaps to it; tapping a flag centres + selects it. Near the virtual
/// edges the wheel silently re-centers itself one code-cycle over (jump is
/// invisible: the strip repeats exactly every cycle).
///
/// Selection lock (v4.12): ONLY Tor and Psiphon actually select a country.
/// Every other protocol renders the wheel purely as a LOCATION DISPLAY —
/// scrolling/tapping disabled («انتخاب کردن کشور فقط باید در پروتکل های
/// سایفون و تور فعال باشه، این قسمت در سایر پروتکل ها فقط نقش نمایش لوکیشن
/// رو داره»). While disconnected those display-only protocols still get the
/// saturation-0 treatment (defect #14 rule, NO blur); when connected they
/// show the real exit country in full color.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/country_names.dart';
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
  /// the future core handoff (per-protocol location rules are re-checked
  /// when the engine lands).
  final void Function(String code) onCountrySelected;

  @override
  State<LocationHeader> createState() => _LocationHeaderState();
}

class _LocationHeaderState extends State<LocationHeader> {
  static const String defaultCode = 'ir';

  /// Virtual copies of the flag cycle. Odd multiple so the list has a true
  /// center start; 201 cycles ≈ 53k flags — unreachable by hand.
  static const int _copies = 201;

  List<String> _codes = const [defaultCode];
  String _selected = defaultCode;
  ScrollController? _controller;

  int get _virtualCount => _codes.length * _copies;

  /// Initial virtual index: dead center of the virtual strip, aligned to the
  /// selected code. Flags exist for thousands of items on BOTH sides.
  int get _centerStart => _codes.length * (_copies ~/ 2) + _indexOf(_selected);

  double _extentOf(BuildContext context) =>
      AethGeometry.flagPitch *
      (MediaQuery.sizeOf(context).width / AethGeometry.refWidth);

  @override
  void initState() {
    super.initState();
    _selected = widget.exitCountryCode ?? defaultCode;
    _loadCodes();
  }

  @override
  void didUpdateWidget(covariant LocationHeader old) {
    super.didUpdateWidget(old);
    // Follow the ENGINE-reported exit country when it arrives/changes —
    // spin the wheel to the nearest instance of that code.
    if (widget.exitCountryCode != null &&
        widget.exitCountryCode != old.exitCountryCode) {
      _select(widget.exitCountryCode!, notify: false);
      _centerOnCode(widget.exitCountryCode!, animate: true);
    }
  }

  Future<void> _loadCodes() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const prefix = 'design/flags_png/';
    final codes =
        manifest
            .listAssets()
            .where((p) => p.startsWith(prefix) && p.endsWith('.png'))
            .map((p) => p.substring(prefix.length, p.length - 4))
            .toList()
          ..sort();
    if (!mounted) return;
    setState(() => _codes = codes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.exitCountryCode != null) {
        _select(widget.exitCountryCode!, notify: false);
      }
    });
  }

  int _indexOf(String code) {
    final i = _codes.indexOf(code);
    return i < 0 ? _codes.indexOf(defaultCode).clamp(0, _codes.length - 1) : i;
  }

  String _codeAt(int virtualIndex) => _codes[virtualIndex % _codes.length];

  void _select(String code, {bool notify = true}) {
    if (_selected == code) return;
    setState(() => _selected = code);
    if (notify) widget.onCountrySelected(code);
  }

  void _ensureController(double extent) {
    _controller ??= ScrollController(
      initialScrollOffset: (_centerStart * extent).clamp(0.0, double.infinity),
    );
  }

  /// The virtual index currently nearest the viewport centre.
  int _focusVirtual() {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return _centerStart;
    final extent = _extentOf(context);
    return (controller.offset / extent).round();
  }

  /// Circular distance between two CODE indices around the flag cycle —
  /// drives the brightness falloff with virtual duplicates around.
  int _circularDistance(int a, int b) {
    final n = _codes.length;
    if (n <= 1) return 0;
    final d = (a - b).abs() % n;
    return d > n ~/ 2 ? n - d : d;
  }

  /// Centers the wheel on [virtualIndex] (tap target).
  void _centerOnVirtual(int virtualIndex, {bool animate = true}) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final extent = _extentOf(context);
    final target = (virtualIndex * extent).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    _scrollTo(target, animate: animate);
  }

  /// Centers the wheel on the instance of [code] NEAREST the current focus
  /// (engine exit-country change) — never a long jump across the strip.
  void _centerOnCode(String code, {bool animate = true}) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final n = _codes.length;
    if (n == 0) return;
    final extent = _extentOf(context);
    final focus = _focusVirtual();
    final delta = _circularDelta(_codes.indexOf(code), focus % n, n);
    final target = ((focus + delta) * extent).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    _scrollTo(target, animate: animate);
  }

  /// Shortest signed step from code index [from] to [to] around the cycle.
  int _circularDelta(int to, int from, int n) {
    var d = (to - from) % n;
    if (d > n ~/ 2) d -= n;
    if (d < -(n ~/ 2)) d += n;
    return d;
  }

  void _scrollTo(double target, {required bool animate}) {
    final controller = _controller!;
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

  void _onScrollEnd() {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final extent = _extentOf(context);
    final focus = (controller.offset / extent).round();
    _select(_codeAt(focus));
    final target = focus * extent;
    if ((controller.offset - target).abs() > 0.5) {
      controller
          .animateTo(
            target.clamp(0.0, controller.position.maxScrollExtent),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(_recenterIfNearEdge);
    } else {
      _recenterIfNearEdge();
    }
  }

  /// INFINITE WHEEL KEEP-ALIVE: when the focus drifts within 2 cycles of a
  /// virtual edge, silently jump one half-strip over. The strip repeats
  /// exactly every cycle, so the jump is pixel-identical and invisible.
  void _recenterIfNearEdge() {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    // Never fight an active drag — the next scroll-end re-checks.
    if (controller.position.isScrollingNotifier.value) return;
    final extent = _extentOf(context);
    final n = _codes.length;
    final i = (controller.offset / extent).round();
    final half = n * (_copies ~/ 2);
    if (i < n * 2 && controller.offset > 0) {
      controller.jumpTo(controller.offset + half * extent);
    } else if (i > _virtualCount - n * 2) {
      controller.jumpTo(controller.offset - half * extent);
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

    // v4.12: the lock follows the PROTOCOL TYPE only — Tor/Psiphon select a
    // country, everything else is a location display (scroll/tap disabled).
    final selectable = widget.protocolIsTorOrPsiphon;
    // Display-only protocols keep the greyscale treatment while disconnected
    // (defect #14 rule — saturation-0, NO blur); connected shows real color.
    final locked = !selectable;
    final greyscale = locked && !connected;

    final Widget headerRow = Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(left: AethGeometry.locationInsetStart * s),
        child: Row(
          children: [
            // v4.12 COMPACT CLUSTER at the left-of-center: name · icon · ping.
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
            SizedBox(width: AethGeometry.locationGroupGap * s),
            // Map icon + small chevron below (part of the cluster).
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
            SizedBox(width: AethGeometry.locationGroupGap * s),
            // Ping when connected and measured, «آفلاین» when disconnected,
            // nothing while the engine is still walking (honest).
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

    _ensureController(_extentOf(context));

    return Column(
      children: [
        headerRow,
        SizedBox(height: AethGeometry.gapLocationToFlags * s),
        _FlagsWheel(
          codes: _codes,
          controller: _controller,
          selected: _selected,
          locked: locked,
          greyscale: greyscale,
          extent: _extentOf(context),
          focusVirtual: _focusVirtual(),
          circularDistance: _circularDistance,
          onFocusChanged: (code) => _select(code),
          onTapFlag: (code, virtualIndex) {
            if (locked) return;
            _select(code);
            _centerOnVirtual(virtualIndex, animate: true);
          },
          onScrollEnd: locked ? null : _onScrollEnd,
        ),
      ],
    );
  }
}

/// The horizontal flag wheel — INFINITE (v4.12). Always occupies the SAME
/// slot (stable tree); the virtual strip is the 266-flag cycle repeated
/// [_LocationHeaderState._copies]× with symmetric centering padding.
class _FlagsWheel extends StatelessWidget {
  const _FlagsWheel({
    required this.codes,
    required this.controller,
    required this.selected,
    required this.locked,
    required this.greyscale,
    required this.extent,
    required this.focusVirtual,
    required this.circularDistance,
    required this.onFocusChanged,
    required this.onTapFlag,
    required this.onScrollEnd,
  });

  final List<String> codes;
  final ScrollController? controller;
  final String selected;
  final bool locked;
  final bool greyscale;
  final double extent;

  /// Frozen focus (virtual index) for this build — used by the falloff.
  final int focusVirtual;
  final int Function(int a, int b) circularDistance;
  final void Function(String code) onFocusChanged;
  final void Function(String code, int virtualIndex) onTapFlag;
  final VoidCallback? onScrollEnd;

  /// Virtual copies — must mirror the state value (kept in one place via the
  /// token below).
  static const int _copies = 201;

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
    final virtualCount = codes.length * _copies;
    final focusCodeIdx = focusVirtual % codes.length;

    // The wheel is LTR-LOCKED (fixed visual layout like the header row):
    // under the Persian RTL locale the horizontal axis would mirror and the
    // drag direction / neighbor ordering would flip per device language.
    final wheel = Directionality(
      textDirection: TextDirection.ltr,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            // Live stepper: the flag nearest the centre grows and becomes the
            // selection while scrolling.
            final c = controller;
            if (!locked && c != null && c.hasClients) {
              final focus = (c.offset / extent).round() % codes.length;
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
            // Centering padding so ANY item can rest exactly on the centre.
            padding: EdgeInsets.symmetric(horizontal: (viewport - extent) / 2),
            physics: locked ? const NeverScrollableScrollPhysics() : null,
            itemCount: virtualCount,
            itemBuilder: (context, i) {
              final code = codes[i % codes.length];
              final isSelected = code == selected;
              // Brightness falloff by CIRCULAR code distance — correct with
              // virtual duplicates on both sides of every flag.
              final distance = circularDistance(i % codes.length, focusCodeIdx);
              final nearSelection = isSelected || distance == 0;
              final opacity = nearSelection
                  ? 1.0
                  : switch (distance) {
                      1 => 0.85,
                      2 => 0.62,
                      _ => 0.45,
                    };
              return Center(
                child: _FlagItem(
                  key: ValueKey<int>(i),
                  asset: AppAssets.flag(code),
                  size:
                      (isSelected
                          ? AethGeometry.flagSizeSelected
                          : AethGeometry.flagSize) *
                      s,
                  opacity: opacity,
                  onTap: () => onTapFlag(code, i),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Defect #14 rule: greyscale (saturation 0) instead of blur — and
    // nothing else: no overlay, no text on top of the wheel.
    if (greyscale) {
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
    super.key,
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
