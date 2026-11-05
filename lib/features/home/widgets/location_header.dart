/// Location header + flag WHEEL (v4.13 — owner defect reports, round 4;
/// restyled v4.15 — owner home round #3):
///
/// Header row (v4.13, LTR-locked) — owner re-clarification, EXACT reference
/// geometry («آیکون پرچم در وسط صفحه باید باشه، متن پینگ ... در سمت راستش
/// باید باشه و متن نمایش اسم کشور باید در سمت چپش باشه»):
///   [country name] —— [map icon + chevron at the EXACT screen centre] —— [ping / آفلاین]
/// The map icon is laid out independently of both texts (two EQUAL Expanded
/// slots + a fixed-width centre box), so NO text change can ever move it off
/// centre. Long names/pings ellipsis INSIDE their own half.
///   * connected  : name = wheel/exit country (white) · «146 ms» green.
///   * disconnected: name = wheel selection (grey) · «آفلاین» grey.
///   * connecting : the ping slot stays empty (honest — nothing measured).
///
/// v4.15 #3 — VISIBILITY RULE (owner: «بخش پرچم ها در حالت غیر متصل پروتکل
/// های به غیر از زیرمجموعه سایفون و تور کاملا پنهان باشه و فقط در حالت
/// اتصال نقش نمایش لوکیشن رو داشته باشه. دقت کن که این بخش در پروتکل های
/// زیرمجموعه سایفون و تور نقش انتخاب لوکیشن را دارد»):
///   * Tor/Psiphon protocols → the band is ALWAYS visible (location SELECTOR).
///   * every other protocol → the band is completely HIDDEN while
///     disconnected and REVEALS (animated) once connected, acting as the
///     location DISPLAY. Every movement of the band (hide/reveal) animates
///     through a single 420 ms ease tween (clip + fade), so the hero band
///     glides instead of jumping.
///
/// v4.15 #3 — FLAG FALLOFF, owner CSS «Group 9» (301×52 strip, 402 frame):
///   centre 52×52 @ opacity 1.0 · ±1 42×42 @ 0.5 · ±2 35×35 @ 0.2 —
///   the centre flag is the LARGEST and the most opaque (the flag that
///   becomes the selected/displayed location always reads at 100%). The
///   falloff interpolates CONTINUOUSLY while scrolling (size and opacity
///   ride the controller, no snap points).
///
/// Flag wheel — UNBOUNDED PageView (v4.13): silently re-centered after every
/// settle — there are ALWAYS flags on BOTH edges and the cycle wraps. The
/// old v4.13 greyscale lock is RETIRED by the v4.15 hide rule (a hidden band
/// cannot be greyscale — it is simply not there).
///
/// CONNECT ROULETTE (v4.13, owner: «وقتی اتصال صورت گرفت اسکرول پرچم ها باید
/// بین کشور ها مقداری اسکرول کند و بعد لوکیشن اصلی رو نشون بده»): the moment
/// the machine enters `connected` the wheel spins forward through the
/// countries (two full laps) and lands on the engine-reported exit country.
/// Works on the real-core path too: the trigger is the STATE edge, and a
/// late exit-country report RE-SPINS the roulette (a fresh two-lap spin from
/// the current position). A monotonic EPOCH protocol makes every
/// programmatic spin the sole owner of the wheel: a superseded animation's
/// completion is a no-op. The roulette never writes to the store at all —
/// the engine owns the connected location.
///
/// Selection lock (v4.19 #5 refinement): ONLY the protocols whose pin the
/// core actually HONORS render the wheel as a selector (psiphon-exit +
/// reverse modes); tor-exit protocols render it as a locked DISPLAY (the
/// core has no Tor exit-country control — the roulette still lands on the
/// real exit). The psiphon-EXIT modes additionally FILTER the flag list to
/// the Psiphon egress regions (owner: «در حالت تور و سایفون باید فقط پرچم
/// کشورهایی رو نشون بده که سایفون و تور ساپورت میکنن»); a filter change
/// re-anchors the wheel on the nearest allowed flag and commits it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/app_assets.dart';
import '../../../core/country_names.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import '../../../connection/transport_modes.dart' show LocationWheelPolicy;
import 'custom_icons.dart';

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

    // v4.21 — the lock rule (owner device-test round 3): a family selector
    // is scrollable ONLY while disconnected; once connected the band is a
    // pure DISPLAY locked on the connected location (the roulette lands
    // there and no user scroll can move it). Non-family protocols keep the
    // v4.15 #3 rule (hidden until connected, then the same locked display).
    final selectable = widget.selectable;
    final locked = widget.connected || !selectable;

    // v4.15 #3 — the hide rule: a non-Tor/Psiphon protocol keeps the whole
    // band completely hidden while disconnected; it only exists (revealing
    // animated) as the location display once connected.
    final hidden = locked && !connected;

    _ensureController();

    final wheel = _FlagsWheel(
      codes: _codes,
      controller: _pageController!,
      locked: locked,
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

    final band = Column(
      children: [
        _buildHeaderRow(context, strings, s),
        SizedBox(height: 3 * s),
        // Chevron under the map icon — centred on the screen like the icon.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ChevronDownIcon(
              size: 8 * s,
              color: AethColors.textSecondary,
            ),
          ),
        ),
        SizedBox(height: AethGeometry.gapLocationToFlags * s),
        wheel,
      ],
    );

    // v4.15 #3 — the reveal seam. One tween drives clip + fade: the band
    // grows from zero height (Align heightFactor) and fades in together,
    // so the layout above/below GLIDES. The wheel stays laid out at full
    // size behind the clip while hidden — the PageController never loses
    // its clients, so the connect-edge roulette is always safe.
    //
    // v4.15.1 — BUGFIX: the wrapper tree must NEVER change shape. The first
    // cut short-circuited `t >= 0.999` to the bare child, which swapped the
    // element at this slot (ClipRect ≠ Column) the moment the reveal
    // finished — mid-roulette, 420 ms into the spin. The PageView subtree
    // was inflated FRESH, the old scroll position detached (completing the
    // animateToPage future as a fake success) and the new client re-attached
    // at initialPage — the wheel snapped back to ایران and the roulette
    // died. A CONSTANT ClipRect > Align > Opacity tree with only the `t`
    // values tweened is visually identical at t = 1 (Align heightFactor 1
    // and Opacity 1 are no-ops) and keeps the PageView's element — and its
    // scroll position — alive through the whole reveal + roulette.
    return TweenAnimationBuilder<double>(
      key: const ValueKey('location-band'),
      tween: Tween(end: hidden ? 0.0 : 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, t, child) {
        return ClipRect(
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            heightFactor: t,
            child: Opacity(opacity: t, child: child),
          ),
        );
      },
      child: band,
    );
  }
}

/// The horizontal flag wheel — UNBOUNDED PageView (v4.13).
class _FlagsWheel extends StatelessWidget {
  const _FlagsWheel({
    required this.codes,
    required this.controller,
    required this.locked,
    required this.onTapFlag,
    required this.onPageSettled,
    required this.onPageChanged,
  });

  final List<String> codes;
  final PageController controller;
  final bool locked;
  final void Function(int page)? onTapFlag;
  final void Function(int page) onPageSettled;
  final void Function(int page) onPageChanged;

  /// v4.15 #3 — owner CSS «Group 9» falloff, restated from the 402 frame:
  /// centre 52 @ 1.0 · ±1 42 @ 0.5 · ±2 35 @ 0.2 (flat beyond ±2 —
  /// everything past ±2 is off the 301-wide strip anyway).
  static const List<double> _sizes = [52, 42, 35];
  static const List<double> _opacities = [1.0, 0.5, 0.2];

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
