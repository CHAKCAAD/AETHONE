/// Location header + flag WHEEL (v4.13 — owner defect reports, round 4):
///
/// Header row (v4.13, LTR-locked) — owner re-clarification, EXACT reference
/// geometry («آیکون پرچم در وسط صفحه باید باشه، متن پینگ ... در سمت راستش
/// باید باشه و متن نمایش اسم کشور باید در سمت چپش باشه»):
///   [country name] —— [map icon + chevron at the EXACT screen centre] —— [ping / آفلاین]
/// The map icon is laid out independently of both texts (two EQUAL Expanded
/// slots + a fixed-width centre box), so NO text change can ever move it off
/// centre («وقتی متن قسمت پینگ کاراکتر هاش تغیر میکنه ... آیکون از وسط بودن
/// خارج نشه»). Long names/pings ellipsis INSIDE their own half.
///   * connected  : name = wheel/exit country (white) · «146 ms» green.
///   * disconnected: name = wheel selection (grey) · «آفلاین» grey.
///   * connecting : the ping slot stays empty (honest — nothing measured).
///
/// Flag wheel — REBUILT on PageView (v4.13): the v4.12 virtual-strip ListView
/// started near its own left edge after the async flag-manifest load (the
/// controller was created against the 1-code placeholder list), so scrolling
/// left ran into EMPTY space («نباید پرچم ها از یک طرف خالی باشه»). The
/// wheel is now an UNBOUNDED PageView started ~1,000,000 pages in, silently
/// re-centered after every settle — there are ALWAYS flags on BOTH edges and
/// the cycle wraps («اگه روی پرچم ایران هستی ... در نهایت مجددا به پرچم ایران
/// برسی»). The nearest-centre flag is the LARGEST with the HIGHEST opacity
/// (52 > 42 > 36 > 30, 1.0 > .85 > .62 > .45 — measured on the reference
/// frames) and it updates CONTINUOUSLY while scrolling.
///
/// CONNECT ROULETTE (v4.13, owner: «وقتی اتصال صورت گرفت اسکرول پرچم ها باید
/// بین کشور ها مقداری اسکرول کند و بعد لوکیشن اصلی رو نشون بده»): the moment
/// the machine enters `connected` the wheel spins forward through the
/// countries (two full laps) and lands on the engine-reported exit country.
/// Works on the real-core path too: the trigger is the STATE edge, and a
/// late exit-country report RE-SPINS the roulette (a fresh two-lap spin from
/// the current position — the owner's «مقداری اسکرول کند» feel is preserved
/// even when the exit code arrives mid-spin). A monotonic EPOCH protocol
/// makes every programmatic spin the sole owner of the wheel: a superseded
/// animation's completion is a no-op — it never clears the programmatic
/// flag, never re-centers and never writes to the store. The roulette
/// never writes to the store at all — the engine owns the connected
/// location.
///
/// State-change animation (v4.13): the disconnected greyscale is TWEENED
/// (saturation 0 ↔ 1) instead of switching instantly.
///
/// Selection lock: ONLY Tor and Psiphon select a country; every other
/// protocol renders the wheel as a locked LOCATION DISPLAY (defect #13).
library;

import 'dart:async';

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

  /// Wheel selection committed (page settle / tap). The store keeps it for
  /// the future core handoff (per-protocol location rules are re-checked
  /// when the engine lands).
  final void Function(String code) onCountrySelected;

  @override
  State<LocationHeader> createState() => _LocationHeaderState();
}

class _LocationHeaderState extends State<LocationHeader> {
  static const String defaultCode = 'ir';

  /// The wheel starts this many FULL CYCLES into the unbounded strip. The
  /// base is a MULTIPLE of the cycle length, so `page % cycle` IS the code
  /// index — the v4.13 first cut used 1,000,000 (106 pages past a cycle
  /// boundary), which silently shifted the whole mapping by 106 codes.
  static const int _startLap = 100000;

  List<String> _codes = const [defaultCode];
  String _selected = defaultCode;
  PageController? _pageController;

  /// The unbounded strip's rest position for the current cycle.
  int get _lapBase => _cycle * _startLap;

  /// True while a PROGRAMMATIC animation drives the wheel (roulette /
  /// engine-follow / manifest jump): page changes update the header visually
  /// but are never committed to the store — the engine owns that channel.
  bool _programmatic = false;

  /// Roulette bookkeeping (see library doc).
  bool _rouletteRunning = false;
  bool _rouletteQueued = false;
  String? _rouletteTarget;

  /// Monotonic owner stamp for programmatic spins. Every [_spinToPage] call
  /// captures `++_epoch`; a completion that does not match the CURRENT epoch
  /// was superseded by a newer spin and must be a full no-op.
  int _epoch = 0;

  int get _cycle => _codes.length;

  @override
  void initState() {
    super.initState();
    _selected = widget.exitCountryCode ?? defaultCode;
    _loadCodes();
  }

  @override
  void didUpdateWidget(covariant LocationHeader old) {
    super.didUpdateWidget(old);

    // CONNECT EDGE → roulette: spin through the countries, land on the
    // engine-reported (or currently selected) location. Fires on EVERY path
    // into `connected` — preview adapter AND the real core. Scheduled
    // POST-FRAME: scroll commands are never issued mid-build (a rebuild
    // window can transiently hold two scroll positions).
    if (!old.connected && widget.connected) {
      _rouletteTarget = widget.exitCountryCode ?? _selected;
      _rouletteQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runRoulette();
      });
      return;
    }

    // Engine-reported exit country arrives/changes while connected:
    //  * if the roulette is queued/running, RE-SPIN it toward the real exit
    //    country (from the current wheel position — the two-lap feel stays;
    //    the superseded spin's completion is an epoch no-op);
    //  * otherwise follow it with the nearest-instance spin (never a long
    //    jump across the wheel).
    if (widget.connected &&
        widget.exitCountryCode != null &&
        widget.exitCountryCode != old.exitCountryCode) {
      final code = widget.exitCountryCode!;
      if (_rouletteRunning && _rouletteTarget == code) return;
      _select(code, notify: false);
      _rouletteTarget = code;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_rouletteRunning || _rouletteQueued) {
            _runRoulette();
          } else {
            _spinToCode(code);
          }
        }
      });
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
    // The controller (if already created against the placeholder list) must
    // hop to the same code in the REAL cycle — same visual, correct index.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _pageController;
      if (c != null && c.hasClients) {
        _epoch++; // invalidate any in-flight programmatic spin
        _programmatic = true;
        c.jumpToPage(_lapBase + _indexOf(_selected));
        _programmatic = false;
      }
    });
  }

  int _indexOf(String code) {
    final i = _codes.indexOf(code);
    return i < 0 ? _codes.indexOf(defaultCode).clamp(0, _codes.length - 1) : i;
  }

  String _codeAt(int page) => _codes[page % _cycle];

  void _select(String code, {bool notify = true}) {
    if (_selected == code) return;
    setState(() => _selected = code);
    if (notify) widget.onCountrySelected(code);
  }

  void _ensureController() {
    _pageController ??= PageController(
      // 72 pitch on the 402 reference frame — scale-free ratio.
      viewportFraction: AethGeometry.flagPitch / AethGeometry.refWidth,
      initialPage: _lapBase + _indexOf(_selected),
    );
  }

  /// Shortest signed step from code index [from] to [to] around the cycle.
  int _circularDelta(int to, int from, int n) {
    var d = (to - from) % n;
    if (d > n ~/ 2) d -= n;
    if (d < -(n ~/ 2)) d += n;
    return d;
  }

  /// The wheel's single scroll position when it is the ONLY client and
  /// layout is done — null during any rebuild/reattach window (a transient
  /// second position must never crash a paint). Every scroll command and
  /// every page read goes through this guard.
  PageController? _safeController() {
    final c = _pageController;
    if (c == null || !c.hasClients || c.positions.length != 1) return null;
    if (!c.positions.first.haveDimensions) return null;
    return c;
  }

  /// The single programmatic-scroll seam. A newer call SUPERSEDES an older
  /// in-flight one (epoch protocol): the superseded animation's completion
  /// is a full no-op — it never clears the programmatic flag, never
  /// re-centers, and never lets a mid-spin settle write to the store.
  /// Returns true only when THIS spin ran to completion as the current
  /// owner.
  Future<bool> _spinToPage(
    int page, {
    required Duration duration,
    required bool roulette,
  }) async {
    final c = _safeController();
    if (c == null || _cycle < 2) return false;
    final myEpoch = ++_epoch;
    _programmatic = true;
    _rouletteRunning = roulette;
    await c.animateToPage(
      page,
      duration: duration,
      curve: Curves.easeInOutCubic,
    );
    if (!mounted || myEpoch != _epoch) return false; // superseded
    _programmatic = false;
    _rouletteRunning = false;
    _recenterIfFar();
    return true;
  }

  /// Engine exit-country follow: spin to the NEAREST instance of [code].
  Future<void> _spinToCode(String code) async {
    final c = _safeController();
    if (c == null || _cycle < 2) return;
    final from = c.page!.round();
    final delta = _circularDelta(_indexOf(code), from % _cycle, _cycle);
    if (delta == 0) {
      _syncSelectedToPage();
      return;
    }
    await _spinToPage(
      from + delta,
      duration: const Duration(milliseconds: 480),
      roulette: false,
    );
  }

  /// CONNECT ROULETTE: two full laps forward through the countries, landing
  /// on the CURRENT [_rouletteTarget] (read at start — a late exit-country
  /// report updates it BEFORE this spin begins). Purely visual — no store
  /// writes (header updates ride the programmatic page changes; the engine
  /// owns the connected location).
  Future<void> _runRoulette() async {
    _rouletteQueued = false;
    final code = _rouletteTarget ?? _selected;
    final c = _safeController();
    if (c == null || _cycle < 2) return;
    final from = c.page!.round();
    final n = _cycle;
    var forward = (_indexOf(code) - from % n) % n;
    if (forward < n ~/ 3) forward += n; // always a visible spin
    final landed = await _spinToPage(
      from + 2 * n + forward,
      duration: const Duration(milliseconds: 2600),
      roulette: true,
    );
    if (landed && mounted) _syncSelectedToPage();
  }

  /// Header truth sync at rest: the header shows the country under the
  /// wheel's current rest position (never a stale captured code).
  void _syncSelectedToPage() {
    final c = _safeController();
    if (c == null) return;
    final p = c.page?.round();
    if (p == null) return;
    final code = _codeAt(p);
    if (_selected != code) setState(() => _selected = code);
  }

  /// Silent re-center: the strip repeats every cycle, so a jump of whole
  /// cycles is pixel-identical. Keeps the page index forever near [_baseOffset].
  void _recenterIfFar() {
    final c = _safeController();
    if (c == null || _cycle < 2) return;
    final p = c.page;
    if (p == null) return;
    final round = p.round();
    if ((p - round).abs() > 0.01) return; // only at rest
    final drift = round - _lapBase;
    final lap = (_cycle * 1000);
    if (drift > lap ~/ 2) {
      _programmatic = true;
      c.jumpToPage(round - lap);
      _programmatic = false;
    } else if (-drift > lap ~/ 2) {
      _programmatic = true;
      c.jumpToPage(round + lap);
      _programmatic = false;
    }
  }

  // ------------------------------------------------------------------
  // Header row — the centre icon is INDEPENDENT of both texts.
  // ------------------------------------------------------------------
  Widget _buildHeaderRow(BuildContext context, AppStrings strings, double s) {
    final connected = widget.connected;
    final nameText = countryName(_selected) ?? '';

    // Ping slot: green «146 ms» when measured, «آفلاین» grey when
    // disconnected, empty while the engine walks (nothing measured yet).
    final pingText = connected
        ? (widget.pingMs != null ? strings.pingMs(widget.pingMs!) : '')
        : strings.offline;

    Widget slot({required Alignment alignment, required EdgeInsets pad, required String text, required TextStyle style, TextDirection? dir}) {
      return Expanded(
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: pad,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textDirection: dir,
              style: style,
            ),
          ),
        ),
      );
    }

    final nameStyle = TextStyle(
      fontFamily: 'IRANYekanX',
      fontWeight: FontWeight.w500,
      fontSize: 15 * s,
      color: connected ? AethColors.textPrimary : AethColors.textSecondary,
    );
    final pingStyle = TextStyle(
      fontFamily: 'IRANYekanX',
      fontWeight: FontWeight.w500,
      fontSize: 14 * s,
      color: connected && widget.pingMs != null
          ? AethColors.accentConnected
          : AethColors.textSecondary,
    );

    // Two EQUAL Expanded slots + the fixed icon box ⇒ the icon is at the
    // exact horizontal centre of the screen at all times, whatever the
    // texts read (owner defect round 4 #1).
    return SizedBox(
      height: 22 * s,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            slot(
              alignment: Alignment.centerRight,
              pad: EdgeInsets.only(right: AethGeometry.locationSideGap * s),
              text: nameText,
              style: nameStyle,
            ),
            SizedBox(
              width: 22 * s,
              child: Center(
                child: SvgPicture.asset(
                  AppAssets.iconMap,
                  key: const ValueKey('location-map-icon'),
                  width: 22 * s,
                  height: 22 * s,
                  colorFilter: ColorFilter.mode(
                    connected
                        ? AethColors.textPrimary
                        : AethColors.textSecondary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            slot(
              alignment: Alignment.centerLeft,
              pad: EdgeInsets.only(left: AethGeometry.locationSideGap * s),
              text: pingText,
              style: pingStyle,
              dir: TextDirection.ltr,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final connected = widget.connected;

    // v4.12 rule kept: the lock follows the PROTOCOL TYPE only.
    final selectable = widget.protocolIsTorOrPsiphon;
    final locked = !selectable;
    final greyscale = locked && !connected;

    _ensureController();

    final wheel = _FlagsWheel(
      codes: _codes,
      controller: _pageController!,
      locked: locked,
      greyscale: greyscale,
      onTapFlag: locked
          ? null
          : (page) {
              // Epoch seam: a tap supersedes any in-flight roulette — the
              // roulette's completion becomes a no-op and the tapped page's
              // settle commits the selection to the store.
              unawaited(
                _spinToPage(
                  page,
                  duration: const Duration(milliseconds: 320),
                  roulette: false,
                ),
              );
            },
      onPageSettled: (page) {
        // User-driven settle: commit the selection; programmatic settles
        // (roulette / engine follow) never touch the store.
        if (!_programmatic) _select(_codeAt(page));
        _recenterIfFar();
      },
      onPageChanged: (page) {
        final code = _codeAt(page);
        if (_programmatic) {
          if (_selected != code) setState(() => _selected = code);
        } else {
          _select(code);
        }
      },
    );

    return Column(
      children: [
        _buildHeaderRow(context, strings, s),
        SizedBox(height: 3 * s),
        // Chevron under the map icon — centred on the screen like the icon.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ChevronDownIcon(size: 8 * s, color: AethColors.textSecondary),
          ),
        ),
        SizedBox(height: AethGeometry.gapLocationToFlags * s),
        wheel,
      ],
    );
  }
}

/// The horizontal flag wheel — UNBOUNDED PageView (v4.13).
class _FlagsWheel extends StatelessWidget {
  const _FlagsWheel({
    required this.codes,
    required this.controller,
    required this.locked,
    required this.greyscale,
    required this.onTapFlag,
    required this.onPageSettled,
    required this.onPageChanged,
  });

  final List<String> codes;
  final PageController controller;
  final bool locked;
  final bool greyscale;
  final void Function(int page)? onTapFlag;
  final void Function(int page) onPageSettled;
  final void Function(int page) onPageChanged;

  /// Design falloff: 52/42/36/30 px and 1.0/.85/.62/.45 opacity (reference
  /// frames: the centre flag is the largest and the most opaque).
  static const List<double> _sizes = [52, 42, 36, 30];
  static const List<double> _opacities = [1.0, 0.85, 0.62, 0.45];

  /// Saturation-lerped color matrix (1 = full colour, 0 = grey; rec709 luma).
  static List<double> _saturationMatrix(double sat) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final ir = (1 - sat) * r, ig = (1 - sat) * g, ib = (1 - sat) * b;
    return [
      ir + sat, ig, ib, 0, 0, //
      ir, ig + sat, ib, 0, 0, //
      ir, ig, ib + sat, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  (double, double) _lookFor(double distance) {
    final d = distance.abs();
    if (d >= _sizes.length - 1) return (_sizes.last, _opacities.last);
    final i = d.floor();
    final t = d - i;
    return (
      _sizes[i] + (_sizes[i + 1] - _sizes[i]) * t,
      _opacities[i] + (_opacities[i + 1] - _opacities[i]) * t,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final n = codes.length;

    final wheel = Directionality(
      textDirection: TextDirection.ltr,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification) {
            final p = controller.position.haveDimensions
                ? controller.page
                : null;
            if (p != null) onPageSettled(p.round());
          }
          return false;
        },
        child: SizedBox(
          height: AethGeometry.flagSizeSelected * s,
          child: PageView.builder(
            controller: controller,
            physics: locked ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: onPageChanged,
            itemCount: null, // unbounded both directions
            itemBuilder: (context, page) {
              final code = codes[page % n];
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  // Safe read: never touch controller.page during a
                  // multi-position rebuild window.
                  final safe = controller.hasClients &&
                      controller.positions.length == 1 &&
                      controller.positions.first.haveDimensions;
                  final pos = safe ? (controller.page ?? page.toDouble()) : page.toDouble();
                  final (size, opacity) = _lookFor((pos - page).abs());
                  return Center(
                    child: Opacity(
                      opacity: opacity,
                      child: _FlagItem(
                        key: ValueKey<int>(page),
                        asset: AppAssets.flag(code),
                        size: size * s,
                        onTap: onTapFlag == null
                            ? null
                            : () => onTapFlag!(page),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    // Defect #14 rule kept: saturation-0 (NOT blur) for locked protocols
    // while disconnected — but now TWEENED on state change (owner round 4
    // #6: «تغیر وضعیت پرچم کشور ها ... باید با انیمیشن انجام شود»).
    return TweenAnimationBuilder<double>(
      tween: Tween(end: greyscale ? 0.0 : 1.0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      builder: (context, sat, child) {
        if (sat > 0.995) return child!;
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturationMatrix(sat)),
          child: child,
        );
      },
      child: wheel,
    );
  }
}

class _FlagItem extends StatelessWidget {
  const _FlagItem({
    super.key,
    required this.asset,
    required this.size,
    required this.onTap,
  });

  final String asset;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final flag = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(asset, fit: BoxFit.cover, width: size, height: size),
    );
    if (onTap == null) return flag;
    return GestureDetector(onTap: onTap, child: flag);
  }
}
