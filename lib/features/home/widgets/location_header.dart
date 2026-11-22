/// Location band + flag WHEEL (v5 — the «نمای 2» redesign of owner round 19).
///
/// BAND ORDER (v5, owner CSS «Group 15»/«Group 115»): the flag wheel sits
/// on TOP (y 636–688), the country row BELOW it (y 703–748) — the reverse
/// of the v4.13 order. The row itself:
///   [country name] —— [UP-chevron above the map icon, both at the EXACT
///   screen centre] —— [ping / آفلاین]
/// The «Hicon / Linear / Down 2» chevron rides 180°-rotated (pointing UP
/// at the wheel) and the Map glyph renders 180°-rotated like the CSS
/// (`transform: rotate(-180deg)`). The map icon is laid out independently
/// of both texts (two EQUAL Expanded slots + a fixed-width centre box), so
/// NO text change can ever move it off centre.
///   * connected  : name = wheel/exit country (ink) · «146 ms» green w400.
///   * disconnected: «آفلاین» in the theme ink w400.
///   * connecting : the ping slot stays empty (honest — nothing measured).
///
/// v5 — THE GREYSCALE LOCK (owner round 19: «قسمت نمایش پروتکل باید در
/// زمانی که پروتکل های غیر از سایفون و تور انتخاب میشود در حالت قطع سیاه
/// و سفید باشند و نباید قابلیت انتخاب پروتکل یا همون جابه جایی بین نقشه
/// کشور هارو داشته باشه و باید قفل باشه»): the v4.15 HIDE rule is RETIRED
/// — the band is ALWAYS laid out.
///   * Tor/Psiphon + disconnected → full colour, the real SELECTOR.
///   * every other protocol + disconnected → GREYSCALE + locked (the CSS
///     «قطع» frame: the Iran flag mask runs #252525/#FDFDFD/#3D3D3D).
///   * connected (any protocol) → full colour, locked on the exit.
/// The saturation cross-fades through ONE constant ColorFiltered tree (the
/// v4.15.1 lesson — swapping the wrapper would rebuild the PageView and
/// kill an in-flight roulette).
///
/// FLAG FALLOFF, owner CSS «Group 9» (301×52 strip, 402 frame) — unchanged:
///   centre 52×52 @ opacity 1.0 · ±1 42×42 @ 0.5 · ±2 35×35 @ 0.2.
/// v5: the clips are CIRCULAR (radius ≈ 0.47·size) and the centre slot
/// rides a 4px ring («Ellipse 74», 58×58) painted BEHIND the flags — the
/// ring marks the selection slot; scrolling flags glide over it and the
/// settled flag sits inside it.
///
/// Flag wheel — UNBOUNDED PageView (v4.13): silently re-centered after
/// every settle — there are ALWAYS flags on BOTH edges and the cycle wraps.
///
/// CONNECT ROULETTE (v4.13): on the `connected` edge the wheel spins two
/// full laps forward and lands on the engine-reported exit country; a late
/// exit-country report RE-SPINS it. A monotonic EPOCH protocol makes every
/// programmatic spin the sole owner of the wheel; the roulette never
/// writes to the store — the engine owns the connected location.
///
/// Selection lock (v4.19 #5): ONLY the protocols whose pin the core
/// actually HONORS render the wheel as a selector (psiphon-exit + reverse
/// modes); tor-exit protocols render it as a locked DISPLAY. The
/// psiphon-EXIT modes additionally FILTER the flag list to the Psiphon
/// egress regions; a filter change re-anchors the wheel on the nearest
/// allowed flag and commits it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/country_names.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
import '../../../connection/transport_modes.dart' show LocationWheelPolicy;
import '../../shared/hyper_text.dart';

class LocationHeader extends StatefulWidget {
  const LocationHeader({
    super.key,
    required this.connected,
    required this.protocolIsTorOrPsiphon,
    required this.selectable,
    required this.allowedCodes,
    required this.autoEntry,
    required this.anchorCode,
    required this.pingMs,
    required this.exitCountryCode,
    required this.onCountrySelected,
    required this.style,
  });

  final bool connected;

  /// Band-visibility family rule (v4.15 #3) — Tor/Psiphon protocols keep
  /// the band ALWAYS visible (selector or display), everything else reveals
  /// it only once connected.
  final bool protocolIsTorOrPsiphon;

  /// v4.21 — true only for the FAMILY selectors (psiphon + tor): the wheel
  /// is scrollable BEFORE connect and LOCKED on the connected location
  /// after it (owner: «در زمان قبل اتصال باید کاربر بتونه اسکرول کنه و
  /// لوکیشن رو انتخاب کنه ولی در زمان اتصال چون نقش نمایش لوکیشن رو داره
  /// باید فقط روی لوکیشن اتصال قفل باشه»).
  final bool selectable;

  /// v4.21 — the allowed country set, or null = the whole flag manifest.
  /// When non-null it is the EXACT wheel list (auto already included where
  /// it applies).
  final List<String>? allowedCodes;

  /// v4.21 — prepend the AUTO entry («خودکار» — the core's own choice) in
  /// front of the full manifest (the tor family + the reverse modes).
  final bool autoEntry;

  /// v4.21 — the wheel's ANCHOR: the current family's remembered pick
  /// ('auto' or a country code) while disconnected. A family switch
  /// re-anchors the wheel here (per-family memory, owner: «اپ باید انتخاب
  /// لوکیشن سایفون و تور رو یادش بمونه»).
  final String anchorCode;

  final int? pingMs;
  final String? exitCountryCode;

  /// Wheel selection committed (page settle / tap). The store routes it
  /// into the current family's remembered pick.
  final void Function(String code) onCountrySelected;

  /// The motion personality — the circles-selector arrival pop rides its
  /// tempos and dies under its kill-switch (OFF).
  final MotionStyle style;

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

  List<String> _allCodes = const [defaultCode];
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
    _selected = _initialAnchor();
    _loadCodes();
  }

  /// The wheel's starting selection: while disconnected the family's
  /// remembered pick; a resumed/connected session anchors on the engine's
  /// real exit if it is already known.
  String _initialAnchor() {
    if (widget.connected && widget.exitCountryCode != null) {
      return widget.exitCountryCode!;
    }
    return widget.anchorCode;
  }

  @override
  void didUpdateWidget(covariant LocationHeader old) {
    super.didUpdateWidget(old);

    // v4.21 — FAMILY SWITCH (anchor change): re-anchor the wheel on the new
    // family's remembered pick while disconnected. Also covers the allowed
    // set change (psiphon list ⇄ full manifest). Same epoch discipline as
    // the manifest load: the re-anchor supersedes any in-flight spin.
    final setChanged =
        !_sameCodeSet(old.allowedCodes, widget.allowedCodes) ||
        old.autoEntry != widget.autoEntry;
    final anchorChanged = old.anchorCode != widget.anchorCode;
    if ((setChanged || anchorChanged) && !widget.connected) {
      _applyFilter(commit: anchorChanged);
      if (!_codes.contains(_selected) || anchorChanged) {
        _selected = _codes.contains(widget.anchorCode)
            ? widget.anchorCode
            : _codes.first;
      }
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
      return;
    }

    // v4.30 — DISCONNECT EDGE (owner round 6, the sync round): after a
    // session the wheel used to stay parked on the engine's last exit —
    // for a tor exit outside the offered set that flag is not even
    // PICKABLE — while the store held the remembered pick. Re-anchor on
    // the family's pick the moment the session ends: what the wheel shows
    // while disconnected is ALWAYS what the next connect will pin.
    if (old.connected && !widget.connected) {
      _applyFilter(commit: false);
      _selected = _codes.contains(widget.anchorCode)
          ? widget.anchorCode
          : _codes.first;
      // The jump is UNCONDITIONAL: even when `_selected` is already the
      // pick, the controller can still be parked on the session's last
      // exit page (the display union's insert may have shifted page
      // indices too). A same-page jump is a visual no-op.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = _pageController;
        if (c != null && c.hasClients) {
          _epoch++; // supersede any in-flight spin
          _programmatic = true;
          c.jumpToPage(_lapBase + _indexOf(_selected));
          _programmatic = false;
        }
      });
      return;
    }

    // CONNECT EDGE → roulette: spin through the countries, land on the
    // engine-reported (or currently selected) location. Fires on EVERY path
    // into `connected` — preview adapter AND the real core. Scheduled
    // POST-FRAME: scroll commands are never issued mid-build (a rebuild
    // window can transiently hold two scroll positions).
    if (!old.connected && widget.connected) {
      // v4.30 — the engine's exit may be a country this selector never
      // OFFERED (see _ensureDisplayCode): union it in BEFORE the roulette
      // targets it, so the spin lands on its real flag.
      _ensureDisplayCode(widget.exitCountryCode);
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
      // v4.30 — an out-of-set exit joins the display set (was: the spin
      // fell into the _indexOf fallback → index 0 → the AUTO globe:
      // owner round 6 «بعد از اتصال لوکیشن رو آیکونی که برای انتخاب
      // خودکار لوکیشن در نظر گرفتیم نشون میده»).
      _ensureDisplayCode(code);
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
            .where(
              (p) =>
                  p.startsWith(prefix) &&
                  p.endsWith('.png') &&
                  // The AUTO placeholder globe shares the folder — it is NOT
                  // a country (v4.21); it enters the wheel only through the
                  // auto-entry prepend / the family lists.
                  p != '${prefix}auto.png',
            )
            .map((p) => p.substring(prefix.length, p.length - 4))
            .toList()
          ..sort();
    if (!mounted) return;
    _allCodes = codes;
    // commit:true — when the ALLOWED set excludes the current pick (the
    // psiphon filter vs the cold 'auto' default), the wheel re-anchors and
    // the store must mirror what the wheel actually shows.
    _applyFilter(commit: true);
    setState(() {});
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

  /// v4.21 — intersects the full flag manifest with [widget.allowedCodes]
  /// (manifest order kept) and re-anchors the selection when it fell out of
  /// the allowed set. The AUTO entry is prepended for the family selectors
  /// that run on the FULL manifest ([widget.autoEntry]). [commit] also
  /// writes the re-anchored pick to the store (a filter CHANGE means the
  /// protocol changed — the engine must receive the pick that is actually
  /// honorable). The commit is POST-FRAME: the manifest load often resumes
  /// mid-build, and store listeners must never be notified during a build
  /// phase.
  void _applyFilter({required bool commit}) {
    final allowed = widget.allowedCodes;
    List<String> filtered = allowed ?? _allCodes;
    if (allowed == null && widget.autoEntry) {
      filtered = [LocationWheelPolicy.autoCode, ..._allCodes];
    }
    _codes = filtered.isEmpty ? _allCodes : filtered;
    if (!_codes.contains(_selected)) {
      _selected = _codes.contains(widget.anchorCode)
          ? widget.anchorCode
          : _codes.first;
      if (commit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onCountrySelected(_selected);
        });
      }
    }
  }

  /// v4.30 — the connected DISPLAY union: the engine-reported exit may
  /// be a country the selector never OFFERED (a Tor exit relay in a
  /// country outside the snapshot when the live Onionoo refresh failed,
  /// a fresh Psiphon egress after the seed was baked). The engine truth
  /// is never fake: while CONNECTED the reported exit JOINS the display
  /// set (sorted in), so the roulette lands on its real flag instead of
  /// the old `_indexOf` fallback — index 0, the AUTO globe. Display-only:
  /// the union never enters the store, and the disconnect edge re-derives
  /// `_codes` from the offered set and re-anchors on the remembered pick.
  void _ensureDisplayCode(String? code) {
    if (code == null || code.length != 2) return;
    if (_codes.contains(code)) return;
    final next = [..._codes, code]..sort();
    setState(() => _codes = next);
  }

  static bool _sameCodeSet(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    final set = Set<String>.of(a);
    return b.every(set.contains);
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
      // 72px pitch on the INSET viewport (v5: the strip spans
      // pagePadding..refWidth-pagePadding like the mockup's clean side
      // margins — scale-free ratio).
      viewportFraction: AethGeometry.flagPitch /
          (AethGeometry.refWidth - 2 * AethGeometry.pageHPadding),
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
  /// v5 — the country row block («Group 115», 45 tall): the UP-chevron
  /// rides ABOVE the map icon (both at the EXACT screen centre), the name
  /// and ping flank them on the row that is vertically centred on the map.
  Widget _buildCountryRow(BuildContext context, AppStrings strings, double s) {
    final connected = widget.connected;
    final nameText = countryName(_selected) ?? '';

    // Ping slot: green «146 ms» when measured, «آفلاین» in the theme ink
    // when disconnected (owner CSS «حالت قطع»: #141C16, w400/15), empty
    // while the engine walks (nothing measured yet).
    final pingText = connected
        ? (widget.pingMs != null ? strings.pingMs(widget.pingMs!) : '')
        : strings.offline;

    Widget slot({required Alignment alignment, required EdgeInsets pad, required String text, required TextStyle style, TextDirection? dir}) {
      // v8a (owner round 18: «روی متن قسمت نام کشور و قسمت نمایش پینگ هم
      // Hyper Text رو اعمال کن») — the flutterfx fx_10_hyper_text decode,
      // native. The RESTING render is byte-identical to the old Text
      // (style/ellipsis/direction preserved); only CHANGES animate.
      return Expanded(
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: pad,
            child: HyperText(
              text,
              style: widget.style,
              textStyle: style,
              textDirection: dir,
            ),
          ),
        ),
      );
    }

    // v5 owner CSS: the name carries the theme ink in BOTH states
    // («ایران … color: #141C16», w500/15); the ping is the accent green
    // w400/15 only when measured.
    final nameStyle = TextStyle(
      fontFamily: 'IRANYekanX',
      fontWeight: FontWeight.w500,
      fontSize: 15 * s,
      color: AethColors.textPrimary,
    );
    final pingStyle = TextStyle(
      fontFamily: 'IRANYekanX',
      fontWeight: FontWeight.w400,
      fontSize: 15 * s,
      color: connected && widget.pingMs != null
          ? AethColors.accentConnected
          : AethColors.textPrimary,
    );

    // The chevron: «Hicon / Linear / Down 2» rotated −180° → pointing UP
    // at the wheel (its 24-box rides the block's top; the 4px visual sits
    // at y 10–14, mockup-measured).
    final chevron = Transform.rotate(
      angle: math.pi,
      child: SvgPicture.asset(
        AppAssets.iconDown2,
        width: 24 * s,
        height: 24 * s,
        colorFilter: ColorFilter.mode(
          AethColors.textPrimary,
          BlendMode.srcIn,
        ),
      ),
    );

    // The 180°-rotated Map glyph — the row's centre anchor.
    final mapIcon = Transform.rotate(
      angle: math.pi,
      child: SvgPicture.asset(
        AppAssets.iconMap,
        key: const ValueKey('location-map-icon'),
        width: 24 * s,
        height: 24 * s,
        colorFilter: ColorFilter.mode(
          AethColors.textPrimary,
          BlendMode.srcIn,
        ),
      ),
    );

    // The block («Group 115», 45 tall): chevron box on top (y 0–24,
    // 3px overlap), the name/map/ping row at y 21–45 — the texts centre
    // on the MAP box exactly like the mockup (texts y 725–747).
    // Two EQUAL Expanded slots + the fixed map box ⇒ the icon is at the
    // exact horizontal centre of the screen at all times, whatever the
    // texts read (owner defect round 4 #1).
    return SizedBox(
      height: AethGeometry.countryRowHeight * s,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            // The chevron box, centred (CSS boxes overlap the map by 3px).
            Padding(
              padding: EdgeInsets.only(bottom: 24 * s - 3 * s),
              child: Center(child: chevron),
            ),
            // The name · map · ping row, pinned to the block's bottom half.
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 24 * s,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    slot(
                      alignment: Alignment.centerRight,
                      pad: EdgeInsets.only(
                        right: AethGeometry.locationSideGap * s,
                      ),
                      text: nameText,
                      style: nameStyle,
                    ),
                    SizedBox(width: 24 * s, child: Center(child: mapIcon)),
                    slot(
                      alignment: Alignment.centerLeft,
                      pad: EdgeInsets.only(
                        left: AethGeometry.locationSideGap * s,
                      ),
                      text: pingText,
                      style: pingStyle,
                      dir: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
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

    // v4.21 + v5 — the lock rule: a family selector is scrollable ONLY
    // while disconnected; once connected the band is a pure DISPLAY locked
    // on the connected location (the roulette lands there and no user
    // scroll can move it). Non-family protocols are ALWAYS locked — v5
    /// keeps them VISIBLE but GREYSCALE while disconnected (the round-19
    /// decree) instead of hiding the band.
    final selectable = widget.selectable;
    final locked = widget.connected || !selectable;

    _ensureController();

    final wheel = _FlagsWheel(
      codes: _codes,
      controller: _pageController!,
      locked: locked,
      style: widget.style,
      onTapFlag: locked
          ? null
          : (page) {
              // v4.30 — THE TAP COMMIT (owner round 6: «هرچقدر تغیر بدی
              // لوکیشن رو تغیر نمیده»). The old path delegated the commit
              // to the settle — and that commit was DEAD CODE for taps: the
              // ScrollEndNotification is dispatched synchronously inside
              // the scroll activity's end, while `_programmatic` is still
              // true (the animateToPage continuation that clears it runs a
              // microtask LATER), so `if (!_programmatic) _select(...)`
              // never fired. The wheel DISPLAYED the tapped flag while the
              // store kept the previous pick — a psiphon tap on آمریکا
              // left the pin at the settings pick (صربستان) and a tor tap
              // never left 'auto'. Commit HERE, deterministic and
              // ordering-free; the spin below is pure visual.
              _select(_codeAt(page));
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
        //
        // v4.30.1 — AND NEVER RE-CENTER FROM A PROGRAMMATIC SETTLE. A
        // recenter jump dispatches a synchronous ScrollEndNotification
        // from inside jumpTo→goIdle while the pixels are STILL the OLD
        // ones (setPixels has not run yet) — so a notification-driven
        // `_recenterIfFar` here computed the SAME far drift again, jumped
        // again, and ping-ponged until the stack died (the round-6 tor
        // regression: the display-union insert shifts `_lapBase`
        // mid-session, which parked the raw landing page beyond the
        // lap/2 corridor for the first time). Every programmatic jump
        // (the recenter's own, the anchor/disconnect/load re-anchors)
        // holds `_programmatic = true` across its synchronous window, so
        // THIS guard cuts the recursion at its first nesting; the
        // explicit `_recenterIfFar()` after a completed `_spinToPage`
        // (outside the flag window) is the one legitimate programmatic
        // recenter and still runs.
        if (!_programmatic) {
          _select(_codeAt(page));
          _recenterIfFar();
        }
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

    // v5 — the ring behind the wheel's CENTRE slot («Ellipse 74»: 58×58,
    /// 4px #F4F4F4). Painted UNDER the flags: scrolling flags glide over
    /// it, the settled (selected) flag sits inside it.
    final ring = Container(
      width: AethGeometry.flagRingSize * s,
      height: AethGeometry.flagRingSize * s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AethColors.flagRing,
          width: AethGeometry.flagRingBorder * s,
        ),
      ),
    );

    final band = Column(
      key: const ValueKey('location-band'),
      children: [
        // v5 — the WHEEL leads the band (owner CSS «Group 15»: flags y
        // 636–688, country row 703–748); the ring centres behind it.
        Padding(
          // v5 — the mockup's clean side margins: the strip spans
          // x 33–369 on the 402 frame (the ±2 flags end inside them).
          padding: EdgeInsets.symmetric(
            horizontal: AethGeometry.pageHPadding * s,
          ),
          child: SizedBox(
            height: AethGeometry.flagRingSize * s,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ring,
                SizedBox(
                  height: AethGeometry.flagSizeSelected * s,
                  width: double.infinity,
                  child: wheel,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: AethGeometry.gapFlagsToRow * s),
        _buildCountryRow(context, strings, s),
      ],
    );

    // v5 — THE GREYSCALE LOCK replaces the v4.15 hide rule: the band is
    // ALWAYS laid out; a non-family protocol keeps it GREYSCALE + locked
    /// while disconnected (owner round 19). One constant ColorFiltered
    /// tree cross-fades the saturation (the v4.15.1 lesson — the wrapper
    /// must never change shape or the PageView's element dies mid-spin).
    final grayscale = locked && !connected;
    return FlagSaturation(
      key: const ValueKey('flag-saturation'),
      grayscale: grayscale,
      child: band,
    );
  }
}

/// v5 — the greyscale seam: ONE constant ColorFiltered tree whose
/// saturation cross-fades (1 = full colour, 0 = greyscale). The wrapper
/// NEVER changes shape — swapping it in/out would rebuild the PageView
/// subtree and kill an in-flight roulette (the v4.15.1 lesson).
class FlagSaturation extends StatelessWidget {
  const FlagSaturation({super.key, required this.grayscale, required this.child});

  /// The TARGET saturation state (the semantic bit tests can read); the
  /// 420 ms tween is presentation only.
  final bool grayscale;
  final Widget child;

  /// The luminance-preserving saturation matrix at [s] (1 = identity).
  static List<double> matrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    return <double>[
      r + (1 - r) * s, g - g * s, b - b * s, 0, 0, //
      r - r * s, g + (1 - g) * s, b - b * s, 0, 0, //
      r - r * s, g - g * s, b + (1 - b) * s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: grayscale ? 0.0 : 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, sat, child) => ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix(sat)),
        child: child,
      ),
      child: child,
    );
  }
}

/// The horizontal flag wheel — UNBOUNDED PageView (v4.13).
///
/// v4.35 (owner round 11, item 7: «تغیر حالت بین دارک مود و لایت مود روی
/// حالت پرچم‌های نمایش لوکیشن صفحه اصلی اثر میزاره») — ROOT CAUSE: the
/// falloff (size + opacity per flag) is read from the controller at item
/// BUILD time; the first build runs BEFORE the controller has dimensions,
/// so every item fell back to distance-0 (ALL flags full-size/full-opacity)
/// — and nothing rebuilt the items afterwards (the initial re-anchor jump
/// is a pixel NO-OP, so the controller never notified), leaving the wrong
/// falloff on screen until the NEXT store notification happened to rebuild
/// the tree — which is exactly what the owner saw: toggling the theme
/// suddenly changed the flags' state. The fix: one extra rebuild after the
/// first layout, so the items re-read the REAL page from the very first
/// seconds and the theme toggle can no longer be the thing that "fixes"
/// the wheel.
///
/// THE CIRCLES-SELECTOR ARRIVAL (the flutterfx round): when a flag lands
/// under the centre mark it POPS the flutterfx way — the
/// `circles_selector` demo's selected circle: a quick overshoot spring
/// (mass 2 / stiffness 600 / damping 8, verbatim) swings it up to the
/// selected size, past it a hair, and back; the ±1/±2 neighbours are
/// SHOVED outward with the demo's radial falloff while the selection
/// lives; the departing flag sags back onto its falloff size on the
/// demo's softer collapse spring (mass 2 / stiffness 150 / damping 20).
/// The RESTING geometry stays the committed Group-9 falloff exactly
/// (52/42/35, pitch 72) — the owner's pixel-verified frames own the
/// steady state; the circles-selector owns the ARRIVAL (owner: «زمانی که
/// پرچم کشور انتخابی وسط قرار گرفت انیمیشن روی پرچم‌ها … به این سبک
/// اعمال بشه»). OFF parks every spring.
class _FlagsWheel extends StatefulWidget {
  const _FlagsWheel({
    required this.codes,
    required this.controller,
    required this.locked,
    required this.style,
    required this.onTapFlag,
    required this.onPageSettled,
    required this.onPageChanged,
  });

  final List<String> codes;
  final PageController controller;
  final bool locked;
  final MotionStyle style;
  final void Function(int page)? onTapFlag;
  final void Function(int page) onPageSettled;
  final void Function(int page) onPageChanged;

  @override
  State<_FlagsWheel> createState() => _FlagsWheelState();
}

class _FlagsWheelState extends State<_FlagsWheel>
    with TickerProviderStateMixin {
  /// Set after the one-shot post-layout rebuild (see the class doc).
  bool _primed = false;

  /// v4.15 #3 — owner CSS «Group 9» falloff, restated from the 402 frame:
  /// centre 52 @ 1.0 · ±1 42 @ 0.5 · ±2 35 @ 0.2 (flat beyond ±2 —
  /// everything past ±2 is off the 301-wide strip anyway).
  static const List<double> _sizes = [52, 42, 35];
  static const List<double> _opacities = [1.0, 0.5, 0.2];

  // ------------------------------------------------------------------
  // The circles-selector port (flutterfx `circles_selector`, verbatim
  // springs; the grid became the 1-D wheel).
  // ------------------------------------------------------------------

  /// The demo's `quickOvershootSpring` — the arrival pop.
  static const SpringDescription _popSpring = SpringDescription(
    mass: 2,
    stiffness: 600,
    damping: 8,
  );

  /// The demo's `spring` — the release/collapse.
  static const SpringDescription _collapseSpring = SpringDescription(
    mass: 2,
    stiffness: 150,
    damping: 20,
  );

  /// Live arrival pops, keyed by CODE index (page % n) — the demo's
  /// `Map<int, AnimationController>` pattern. Bounded: a new centre
  /// retires every other entry, so at most a handful ever live.
  final Map<int, AnimationController> _pops = {};

  /// The last centre page seen (the rounded controller page) — the pop
  /// fires when it CHANGES (arrive / pass / land).
  int? _centerPage;

  /// How far past the resting size the overshoot may peak (× selected
  /// size). The demo's selected circle rests 2×; the wheel's frames own
  /// the resting 52, so the pop is the ARRIVAL and the overshoot the
  /// flourish: peak ≈ 52 × 1.08.
  static const double _overshootAmp = 0.25;

  /// The ±1 neighbours' outward shove at full pop (design px) — the
  /// demo's neighbour displacement, scaled to the 72-px pitch strip.
  static const double _pushMax = 6.0;

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
  void initState() {
    super.initState();
    widget.controller.addListener(_onWheelScrolled);
  }

  @override
  void didUpdateWidget(covariant _FlagsWheel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onWheelScrolled);
      widget.controller.addListener(_onWheelScrolled);
      _centerPage = null; // re-arm against the new controller
    }
    // A family/manifest switch re-keys every pop (page % n changed its
    // meaning) — retire them all and let the next centre re-arm. CONTENT
    // comparison: the store's wheel lists are rebuilt as fresh instances
    // on every notify (same entries), and retiring on an identical set
    // would kill the live pop on every selection commit.
    if (!_sameCodes(old.codes, widget.codes)) {
      _retireAllPops();
      _centerPage = null;
    }
    // The kill-switch: OFF parks every spring.
    if (old.style != MotionStyle.off && widget.style == MotionStyle.off) {
      _retireAllPops();
    }
  }

  /// Element-wise equality (the lists are short; the store hands the
  /// wheel a freshly-built instance on every notify).
  static bool _sameCodes(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onWheelScrolled);
    for (final c in _pops.values) {
      c.dispose();
    }
    _pops.clear();
    super.dispose();
  }

  void _retireAllPops() {
    final live = Map.of(_pops);
    _pops.clear();
    for (final e in live.entries) {
      _retireController(e.key, e.value);
    }
    if (live.isNotEmpty) setState(() {});
  }

  /// The demo's deselect: collapse toward zero on the soft spring, then
  /// dispose. [key] is only used to guard the removal (a re-fired pop
  /// replaces the map entry and adopts the controller).
  void _retireController(int key, AnimationController c) {
    if (c.isAnimating) {
      // Keep rendering while it sags home.
      _pops[key] = c;
      c
          .animateWith(
              SpringSimulation(_collapseSpring, c.value, 0, -1))
          .then((_) {
        if (!mounted) {
          c.dispose();
          return;
        }
        if (_pops[key] == c) {
          setState(() => _pops.remove(key));
          c.dispose();
        }
      });
    } else {
      c.dispose();
    }
  }

  /// The centre mark moved onto a new page — the circles-selector's
  /// "tap": the new centre pops, everyone else retires.
  void _onWheelScrolled() {
    final controller = widget.controller;
    if (!controller.hasClients ||
        controller.positions.length != 1 ||
        !controller.positions.first.haveDimensions) {
      return;
    }
    final p = controller.page;
    if (p == null) return;
    final center = p.round();
    if (center == _centerPage) return;
    _centerPage = center;
    if (widget.style == MotionStyle.off) return;
    final n = widget.codes.length;
    if (n == 0) return;
    final key = center % n;

    for (final k in _pops.keys.toList()) {
      if (k == key) continue;
      final c = _pops.remove(k)!;
      _retireController(k, c);
    }

    final existing = _pops[key];
    if (existing != null) {
      // Re-centered mid-release (a bounce back / a re-tap): re-pop from
      // wherever it is now.
      existing.animateWith(
          SpringSimulation(_popSpring, existing.value, 1, 1));
      return;
    }
    final c = AnimationController.unbounded(vsync: this);
    _pops[key] = c;
    c.animateWith(SpringSimulation(_popSpring, 0, 1, 1));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_primed) {
      // One extra build after this frame: by then the controller has
      // dimensions and every item's falloff re-reads the REAL page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _primed = true);
          _onWheelScrolled(); // arm the centre mark (the welcome pop)
        }
      });
    }
    final controller = widget.controller;
    final codes = widget.codes;

    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final n = codes.length;

    // v4.15 #3: the greyscale ColorFiltered wrapper is RETIRED — the locked
    // band is HIDDEN while disconnected instead (see the reveal seam in the
    // parent), and a connected display shows full colour.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification) {
            final p = controller.position.haveDimensions
                ? controller.page
                : null;
            if (p != null) widget.onPageSettled(p.round());
          }
          return false;
        },
        child: SizedBox(
          // The circles-selector overshoot peaks ≈ 8 % past the selected
          // size — the strip gets that much headroom so the pop never
          // clips against the PageView's own viewport edge. The resting
          // geometry is untouched: the flags still centre on the same
          // line and the committed frames keep their sizes.
          height: AethGeometry.flagSizeSelected * 1.15 * s,
          child: PageView.builder(
            controller: controller,
            physics: widget.locked ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: widget.onPageChanged,
            itemCount: null, // unbounded both directions
            itemBuilder: (context, page) {
              final code = codes[page % n];
              // The flutterfx reading: a neighbour's displacement is driven
              // by the SELECTED circle's controller, never its own — every
              // visible item therefore listens to the centre mark's pop as
              // well as its own (the departing sag).
              final ownPop = _pops[page % n];
              final centerKey =
                  _centerPage == null ? null : _centerPage! % n;
              final centerPop =
                  centerKey == null ? null : _pops[centerKey];
              final listen = <Listenable>[
                controller,
                ?ownPop,
                if (centerPop != null && centerPop != ownPop) centerPop,
              ];
              return AnimatedBuilder(
                animation: listen.length == 1
                    ? controller
                    : Listenable.merge(listen),
                builder: (context, _) {
                  // Safe read: never touch controller.page during a
                  // multi-position rebuild window.
                  final safe = controller.hasClients &&
                      controller.positions.length == 1 &&
                      controller.positions.first.haveDimensions;
                  final pos = safe ? (controller.page ?? page.toDouble()) : page.toDouble();
                  final (size, opacity) = _lookFor((pos - page).abs());
                  var sz = size;
                  var dx = 0.0;
                  if (ownPop != null || centerPop != null) {
                    // The circles-selector arrival mapped onto the wheel.
                    // The GROW rides the flag's OWN pop (only the flag
                    // under the centre mark — or the one sagging off it —
                    // owns one); the SHOVE rides the CENTRE's pop (the
                    // demo's selected circle displacing its neighbours).
                    final own = ownPop?.value ?? 0.0;
                    final v = (centerPop?.value ?? own).clamp(0.0, 1.35);
                    final d = pos - page; // signed offset from the centre
                    final u = d.abs();
                    // Grow: only the flag under the centre mark blends up
                    // to the selected size (gone by one slot out).
                    final growGate =
                        (1.0 - (u - 0.35) / 0.5).clamp(0.0, 1.0);
                    final blend = own.clamp(0.0, 1.0) * growGate;
                    final target = size +
                        (AethGeometry.flagSizeSelected - size) * blend;
                    // The flourish: the spring's past-1 swing (and its
                    // below-0 sag on release) rides the same gate, clamped
                    // so the overshoot stays inside the strip's headroom.
                    final wobble = own > 1
                        ? (own - 1).clamp(0.0, 0.35)
                        : own < 0
                            ? own.clamp(-0.35, 0.0)
                            : 0.0;
                    sz = target * (1 + _overshootAmp * wobble * growGate);
                    // Shove: the demo's radial neighbour displacement —
                    // an ODD ramp of the signed offset (zero at the
                    // centre, full at ±1, gone by ±3).
                    final mag = u <= 1
                        ? u
                        : (1.0 - (u - 1) / 2).clamp(0.0, 1.0);
                    final ramp = d < 0 ? -mag : mag;
                    dx = -_pushMax * v * ramp;
                  }
                  return Center(
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: Offset(dx * s, 0),
                        child: _FlagItem(
                          key: ValueKey<int>(page),
                          asset: AppAssets.flag(code),
                          size: sz * s,
                          onTap: widget.onTapFlag == null
                              ? null
                              : () => widget.onTapFlag!(page),
                        ),
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
    // v5 — circular clips (owner CSS image radii ≈ 0.47·size at 3×).
    final flag = ClipRRect(
      borderRadius: BorderRadius.circular(size * AethGeometry.flagRadiusFactor),
      child: Image.asset(asset, fit: BoxFit.cover, width: size, height: size),
    );
    if (onTap == null) return flag;
    return GestureDetector(onTap: onTap, child: flag);
  }
}
