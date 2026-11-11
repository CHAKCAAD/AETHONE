/// ConnectionStore — the UI-facing orchestrator (ChangeNotifier).
///
/// Implements prompt §8 rules:
///  * ONE transition in flight; multi-tap on the connect button is harmless;
///  * engine events drive the machine; illegal transitions are surfaced as
///    failures instead of silently swallowed;
///  * health-probe failure ⇒ `reconnecting`;
///  * appearance settings (home look, animation style) live here too until
///    the settings model step (M3) adds persistence.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_assets.dart';
import '../core/app_theme.dart';
import '../core/motion.dart';
import 'connection_state.dart';
import 'core_settings.dart';
import 'egress_locations.dart';
import 'engine.dart';
import 'firefox/firefox_protocol.dart';
import 'app_tunnel.dart';
import 'platform_engine_adapter.dart';
import 'smart_scorecard.dart';
import 'transport_modes.dart';

/// The two selectable home-screen looks (owner: identical logic, different
/// layout — report §11.2).
enum HomeLook { one, two }

/// PHASE-2 (firefox-vpn) — the Firefox account's signed-in state, from
/// the Keystore vault's presence (honest: unknown until the first check,
/// then signedIn / signedOut; nothing simulated).
enum FirefoxAccountStatus { unknown, signedIn, signedOut }

class ConnectionStore extends ChangeNotifier implements EngineConfigSource {
  /// v4.32 — [scorecard] defaults ONCE (the redirecting constructor) so the
  /// store and its platform adapter always share the SAME live instance —
  /// the async disk restore later merges into it in place.
  ConnectionStore({EngineAdapter? engine, SmartScorecard? scorecard})
    : this._with(engine, scorecard ?? SmartScorecard());

  ConnectionStore._with(EngineAdapter? engine, SmartScorecard scorecard)
    : smartScorecard = scorecard,
      _engine = engine ?? _defaultEngine(scorecard) {
    // The platform adapter reads the user's live configuration through this
    // read-only view (M2 seam — see [EngineConfigSource]).
    _engine.bind(this);
    _subscription = _engine.events.listen(_onEvent);
    unawaited(loadFirefoxDnsSettings());
  }

  /// v4.32 — the SMART scorecard the adapter orders its candidates by
  /// (ENGINE TRUTH, not a user preference: restored from its own prefs
  /// key before the first frame via [SmartScorecard.loadFrom] — the
  /// in-place merge keeps this instance the live one the adapter holds).
  final SmartScorecard smartScorecard;

  /// Engine selection order (M2):
  ///  1. PREVIEW_MODE (debug CI builds only) → the honest simulator;
  ///  2. Android → the REAL platform adapter (embedded Aether via FFI +
  ///     zeptun via the VpnService JNI bridge);
  ///  3. v4.36 (desktop round): a REAL Linux or Windows APP engages the SAME
  ///     adapter — its runner implements the identical `aethone/engine`
  ///     channel surface in C++ and marks the process with the
  ///     AETHONE_DESKTOP_ENGINE=1 environment flag (set before the engine
  ///     starts). The flag keeps the TEST hosts (which run on Linux too but
  ///     never set it) on the old honest engineNotWired path, so the v4.26
  ///     resume-window suite keeps its exact semantics. The Android branch
  ///     is byte-identical to before;
  ///  4. everything else (other desktops, tests, web) → fails honestly with
  ///     `engineNotWired` instead of ever pretending to be connected.
  static bool get _desktopAppEngaged =>
      (Platform.isLinux || Platform.isWindows) &&
      Platform.environment['AETHONE_DESKTOP_ENGINE'] == '1';

  static EngineAdapter _defaultEngine(SmartScorecard scorecard) {
    if (PreviewEngineAdapter.allowed) return PreviewEngineAdapter();
    if (!kIsWeb && (Platform.isAndroid || _desktopAppEngaged)) {
      return PlatformEngineAdapter(scorecard: scorecard);
    }
    return EngineNotWiredAdapter();
  }

  final EngineAdapter _engine;
  late final StreamSubscription<EngineEvent> _subscription;

  final VpnStateMachine _machine = VpnStateMachine();

  /// Single-flight guard (prompt §8: only one transition in flight).
  bool _operationInFlight = false;

  /// v4.19 (#3) — re-entrancy guard of the CANCELLING disconnect: a tap on
  /// the connect button while the engine walk is in flight must reach the
  /// engine even though [_operationInFlight] is held by that walk.
  bool _cancelling = false;

  /// v4.19 (#3) — a cancel was executed and no new connect has started
  /// since: progress emissions from the aborted walk (already in flight
  /// when the cancel landed) are dropped, even after the machine reached
  /// `disconnected` — a cancelled session must never end in a fake
  /// `failed(illegalTransition)`. Cleared by the next user connect.
  bool _cancelledWalk = false;

  /// The states a tap-to-cancel may interrupt (the engine walk in flight).
  static const Set<VpnState> _cancelableStates = {
    VpnState.starting,
    VpnState.waitingForPermissions,
    VpnState.connecting,
  };

  // ---- state surface consumed by the UI ----
  VpnState get state => _machine.current;

  bool get isConnected => state == VpnState.connected;

  String? lastErrorCode;
  String? lastErrorMessage;

  int? pingMs; // null ⇒ not measured; NEVER fabricated
  int downBytes = 0;
  int upBytes = 0;
  String? exitCountryCode; // null ⇒ unknown; no flag shown

  /// v4.32 — the protocol the SMART walk actually CONNECTED with (null =
  /// not a live SMART session). The bottom panel shows it in place of the
  /// generic AUTO while connected; cleared on every disconnect/failed
  /// transition alongside the other session data.
  ProtocolId? smartResolvedProtocol;

  /// v4.32 — the in-flight SMART candidate (attempt i of n), surfaced by
  /// the connecting status card as the explicit fallback chain (spec
  /// §7.2). Null when the walk is not in a SMART attempt. v4.34 adds
  /// [measuring] — true while the tour measures a CONNECTED candidate's
  /// quality (the card says «سنجش کیفیت …» instead of the attempt count).
  ({ProtocolId candidate, int attempt, int total, bool measuring})?
  smartAttempt;

  /// v4.32 — the protocol the bottom panel shows: the SMART-resolved
  /// protocol while a SMART session is live, else the committed tile.
  ProtocolId get smartDisplayProtocol =>
      smartResolvedProtocol ?? effectiveProtocol;

  // ---- user preferences (settings main page, step 2) ----
  // These are USER-CHOSEN values rendered by the settings status cards
  // («هر سه کارت وضعیت به دادهٔ واقعی نگاشت شدند» — phase-1 report D2).
  // M2 feeds them to the cores; the engine never writes them.

  /// Protocol selection mode — AUTO (default) or SMART
  /// (SMART_AUTO_SPEC.md: the app-layer selector landed in v4.32 — the
  /// adapter runs the scorecard-ordered candidate chain while the
  /// committed tile is AUTO; a manual tile is never rewritten, §7.6).
  @override
  bool protocolModeSmart = false;

  /// Routing-rules country: 'ir' (default, design shows «Iran»), 'tm',
  /// 'ru', 'cn' or null = None (phase-1 report: IR/TM/RU/CN + None).
  @override
  String? routingRegion = 'ir';

  /// Kill switch preference — ON by default (design shows «ON»).
  bool killSwitch = true;

  /// v4.41 (owner round 17, item 4) — per-app tunneling (Android, tunnel
  /// mode): all = every app rides the TUN (the standing behavior), allow
  /// = ONLY the selected apps, disallow = everything EXCEPT the selected
  /// apps. Applied by AethoneVpnService's Builder through
  /// VpnService.Builder.addAllowedApplication / addDisallowedApplication.
  @override
  AppTunnelMode appTunnelMode = AppTunnelMode.all;

  /// The selected packages ([AppTunnelMode.allow] / [AppTunnelMode.disallow]).
  @override
  Set<String> appTunnelApps = <String>{};

  /// Settings setters (notify; the settings page + status cards rebuild).
  void setProtocolModeSmart(bool smart) {
    if (protocolModeSmart == smart) return;
    protocolModeSmart = smart;
    notifyListeners();
  }

  void setRoutingRegion(String? code) {
    if (routingRegion == code) return;
    routingRegion = code;
    notifyListeners();
  }

  void setKillSwitch(bool on) {
    if (killSwitch == on) return;
    killSwitch = on;
    notifyListeners();
  }

  /// v4.41 — per-app tunneling setters (the routing page's section).
  void setAppTunnelMode(AppTunnelMode mode) {
    if (appTunnelMode == mode) return;
    appTunnelMode = mode;
    notifyListeners();
  }

  void toggleAppTunnelApp(String packageName, {required bool selected}) {
    final next = {...appTunnelApps};
    if (selected == next.contains(packageName)) return;
    selected ? next.add(packageName) : next.remove(packageName);
    appTunnelApps = next;
    notifyListeners();
  }

  /// The location the USER picked on the flag wheel (v4.11, defect #8).
  /// The engine-reported [exitCountryCode] stays the only "connected to X"
  /// truth; this is the selector state the core consumes (M2).
  @override
  String? selectedCountryCode;

  /// v4.21 — per-family location picks (owner device-test round 3: «اپ
  /// باید انتخاب لوکیشن سایفون و تور رو یادش بمونه» + «برای سایفون و تور
  /// به انتخاب خودکار هم باید بزاریم … از قبل خودشون دارن»):
  /// 'auto' = the core's own choice (the built-in capability the owner
  /// named — no flag passed), else an ISO-3166 alpha-2 lowercase pick.
  /// Remembered per family and persisted.
  @override
  String psiphonLocation = LocationWheelPolicy.autoCode;

  @override
  String torLocation = LocationWheelPolicy.autoCode;

  /// v4.28 — the LIVE psiphon egress set: the network's own
  /// `AvailableEgressRegions` report harvested from the core log after a
  /// psiphon-family connect (owner round 5: «لوکیشن های واقعی، نه فیک»).
  /// null until the first report arrives — the wheel falls back to the
  /// standing seed. NOT a user choice: engine truth, never persisted as a
  /// preference (it is cached by [EgressLocations] instead).
  List<String>? livePsiphonRegions;

  /// v4.28 — the LIVE Tor exit-country set (Onionoo — running exit relays
  /// per country). null until the first fetch/cache-load; the wheel falls
  /// back to the bundled snapshot.
  List<String>? liveTorExitCountries;

  /// v4.28 — consumes the adapter's [EngineEgressRegions] event (or the
  /// app-start Onionoo refresh): swaps in a sanitized live set and saves
  /// the cache. A no-change swap does not wake the listeners.
  void applyPsiphonEgressRegions(List<String> regions) {
    final clean = EgressLocations.sanitizeCodes(regions);
    if (clean == null) return; // garbage is not a live set — keep the seed
    if (listEquals(clean, livePsiphonRegions)) return;
    livePsiphonRegions = clean;
    notifyListeners();
  }

  /// v4.28 — the Tor exit-country counterpart of the above.
  void applyTorExitCountries(List<String> codes) {
    final clean = EgressLocations.sanitizeCodes(codes);
    if (clean == null) return;
    if (listEquals(clean, liveTorExitCountries)) return;
    liveTorExitCountries = clean;
    notifyListeners();
  }

  // ---- PHASE-2 (firefox-vpn) — the firefox family's own surface ----

  /// The firefox location pick ('auto' = Mozilla's REC anycast, else a
  /// lowercase ISO code from the LIVE RemoteSettings list) — remembered
  /// and persisted like the family picks above.
  @override
  String firefoxLocation = LocationWheelPolicy.autoCode;

  /// The firefox data-plane transport ('h2' default / 'h3' optional).
  @override
  String firefoxTransport = 'h2';

  /// Firefox DNS preferences. They are deliberately process-scoped: they
  /// never modify Android Private DNS or the other AETHONE engines.
  String firefoxDnsMode = 'system';
  String firefoxDnsProvider = 'cloudflare';
  String firefoxDnsEndpoint = '';
  List<String> firefoxDnsBootstrapIps = const [];

  @override
  Map<String, dynamic> get firefoxDnsConfig => {
        'mode': firefoxDnsMode,
        if (firefoxDnsMode == 'doh') ...{
          'provider': firefoxDnsProvider,
          if (firefoxDnsProvider == 'custom' && firefoxDnsEndpoint.trim().isNotEmpty)
            'endpoint': firefoxDnsEndpoint.trim(),
          if (firefoxDnsBootstrapIps.isNotEmpty)
            'bootstrapIps': firefoxDnsBootstrapIps,
          'systemForLocalDomains': true,
        },
      };

  Future<void> loadFirefoxDnsSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('firefox.dns.mode') ?? 'system';
      final provider = prefs.getString('firefox.dns.provider') ?? 'cloudflare';
      firefoxDnsMode = mode == 'doh' ? 'doh' : 'system';
      firefoxDnsProvider = const {'cloudflare', 'google', 'quad9', 'custom'}
              .contains(provider)
          ? provider
          : 'cloudflare';
      firefoxDnsEndpoint = prefs.getString('firefox.dns.endpoint') ?? '';
      firefoxDnsBootstrapIps =
          prefs.getStringList('firefox.dns.bootstrap_ips') ?? const [];
      notifyListeners();
    } catch (_) {
      // Preferences unavailable (e.g. a pure unit-test host): System DNS
      // remains the safe, backward-compatible default.
    }
  }

  Future<void> _persistFirefoxDnsSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('firefox.dns.mode', firefoxDnsMode);
      await prefs.setString('firefox.dns.provider', firefoxDnsProvider);
      await prefs.setString('firefox.dns.endpoint', firefoxDnsEndpoint);
      await prefs.setStringList(
          'firefox.dns.bootstrap_ips', firefoxDnsBootstrapIps);
    } catch (_) {
      // A persistence failure must not silently change the active resolver.
    }
  }

  void setFirefoxDnsMode(String mode) {
    final pick = mode == 'doh' ? 'doh' : 'system';
    if (firefoxDnsMode == pick) return;
    firefoxDnsMode = pick;
    unawaited(_persistFirefoxDnsSettings());
    notifyListeners();
  }

  void setFirefoxDnsProvider(String provider) {
    const allowed = {'cloudflare', 'google', 'quad9', 'custom'};
    final pick = allowed.contains(provider) ? provider : 'cloudflare';
    if (firefoxDnsProvider == pick) return;
    firefoxDnsProvider = pick;
    unawaited(_persistFirefoxDnsSettings());
    notifyListeners();
  }

  void setFirefoxDnsCustom(String endpoint, String bootstrapIps) {
    final nextIps = bootstrapIps
        .split(RegExp(r'[\s,;]+'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .take(8)
        .toList(growable: false);
    if (firefoxDnsEndpoint == endpoint.trim() &&
        listEquals(firefoxDnsBootstrapIps, nextIps)) return;
    firefoxDnsEndpoint = endpoint.trim();
    firefoxDnsBootstrapIps = nextIps;
    unawaited(_persistFirefoxDnsSettings());
    notifyListeners();
  }

  /// The LIVE firefox country set (the engine's --discover role; null
  /// until the first refresh — the wheel falls back to the standing
  /// seed, firefoxCountrySnapshot). Engine truth, never a preference.
  List<String>? liveFirefoxCountries;

  /// The honesty label of the last location refresh: true = live fetch,
  /// false = disk cache (offline start). The settings page surfaces it —
  /// a cache is never presented as live data.
  bool firefoxLocationsLive = false;
  DateTime? firefoxLocationsFetchedAt;

  /// The signed-in state of the Firefox account (vault presence —
  /// honest: no session = signedOut, nothing simulated).
  FirefoxAccountStatus firefoxAccount = FirefoxAccountStatus.unknown;

  /// Consumes the adapter's [EngineFirefoxLocations] event: swaps in the
  /// sanitized live set + its honesty labels. A no-change swap does not
  /// wake the listeners.
  void applyFirefoxLocations(List<String> codes, bool live, DateTime fetchedAt) {
    final clean = EgressLocations.sanitizeCodes(codes);
    if (clean == null) return; // garbage is not a live set — keep the seed
    final changed = !listEquals(clean, liveFirefoxCountries) ||
        firefoxLocationsLive != live;
    liveFirefoxCountries = clean;
    firefoxLocationsLive = live;
    firefoxLocationsFetchedAt = fetchedAt;
    if (changed) notifyListeners();
  }

  /// PHASE-2 — asks the adapter for the live Firefox location list (the
  /// engine's --discover role; the result arrives as an event — see
  /// [applyFirefoxLocations]). Fire-and-forget: the picker renders the
  /// standing seed until the refresh lands.
  void refreshFirefoxLocations() {
    unawaited(_engine.refreshFirefoxLocations());
  }

  /// PHASE-2 — refreshes the signed-in state from the vault. Called at
  /// app start and after every login/logout.
  Future<void> refreshFirefoxAccount() async {
    final has = await _engine.firefoxHasSession();
    final next = has ? FirefoxAccountStatus.signedIn : FirefoxAccountStatus.signedOut;
    if (firefoxAccount == next) return;
    firefoxAccount = next;
    notifyListeners();
  }

  /// PHASE-2 — the sign-out: if a firefox session is LIVE it is
  /// disconnected first (the store owns user intent), then the vault is
  /// wiped (the logout-grade clear) and the state refreshed.
  Future<void> firefoxSignOut() async {
    if (state == VpnState.connected &&
        effectiveProtocol.isFirefox) {
      await disconnect();
    }
    await _engine.firefoxClearSession();
    await refreshFirefoxAccount();
  }

  /// PHASE-2 — runs the WebChannel login exchange (the login screen's
  /// captured token → the engine's --login role → the Keystore vault).
  Future<FirefoxLoginResult> firefoxCompleteLogin(String sessionToken) {
    return _engine.firefoxWebChannelLogin(sessionToken);
  }

  /// PHASE-2 — cancels an in-flight login exchange (the login screen's
  /// dispose path): stdin close → grace → kill; no orphan survives.
  Future<void> firefoxLoginCancel() => _engine.firefoxLoginCancel();

  /// Tests the selected Firefox resolver against the control-plane domains.
  /// This is DNS evidence only, not an OAuth or VPN-connectivity test.
  Future<List<Map<String, dynamic>>?> firefoxDnsProbe() =>
      _engine.firefoxDnsProbe(firefoxDnsConfig);

  /// v4.22 — direct setters for the SETTINGS pages (the Psiphon/Tor pages
  /// write their own family field regardless of the currently selected
  /// protocol; [selectLocation] stays the home-wheel path).
  void setPsiphonLocation(String code) {
    final pick = LocationWheelPolicy.autoCode == code ||
            (code.length == 2 && code == code.toLowerCase())
        ? code
        : LocationWheelPolicy.autoCode;
    if (psiphonLocation == pick) return;
    psiphonLocation = pick;
    notifyListeners();
  }

  void setTorLocation(String code) {
    final pick = LocationWheelPolicy.autoCode == code ||
            (code.length == 2 && code == code.toLowerCase())
        ? code
        : LocationWheelPolicy.autoCode;
    if (torLocation == pick) return;
    torLocation = pick;
    notifyListeners();
  }

  /// PHASE-2 — the firefox settings page's direct setter (same contract
  /// as the family setters: 'auto' or a lowercase ISO-2 pick; anything
  /// else falls back to auto — the LIVE list is the source of truth, an
  /// unknown code would fail inside the engine honestly anyway).
  void setFirefoxLocation(String code) {
    final pick = LocationWheelPolicy.autoCode == code ||
            (code.length == 2 && code == code.toLowerCase())
        ? code
        : LocationWheelPolicy.autoCode;
    if (firefoxLocation == pick) return;
    firefoxLocation = pick;
    notifyListeners();
  }

  /// PHASE-2 — the transport pick ('h2' | 'h3'; anything else → 'h2').
  void setFirefoxTransport(String transport) {
    final pick = transport == 'h3' ? 'h3' : 'h2';
    if (firefoxTransport == pick) return;
    firefoxTransport = pick;
    notifyListeners();
  }

  /// v4.21 — ONE commit path for every wheel settle/tap: routes the pick
  /// into the current family's field (psiphon / tor), or the plain wheel
  /// pick for non-family protocols. Never fires while a transition is in
  /// flight (the selector is locked then anyway).
  void selectLocation(String code) {
    if (_operationInFlight) return;
    final effective = effectiveProtocol;
    if (effective.isPsiphon) {
      if (psiphonLocation == code) return;
      psiphonLocation = code;
      notifyListeners();
    } else if (effective.isTor) {
      if (torLocation == code) return;
      torLocation = code;
      notifyListeners();
    } else if (effective.isFirefox) {
      if (firefoxLocation == code) return;
      firefoxLocation = code;
      notifyListeners();
    } else {
      selectCountry(code);
    }
  }

  /// The pick the wheel should ANCHOR on for the current protocol (the
  /// family pick, or the plain selection for non-family protocols — the
  /// plain family's band is a post-connect display, so its cold anchor is
  /// the classic ایران default, never the AUTO sentinel).
  String get wheelAnchorCode {
    final effective = effectiveProtocol;
    if (effective.isPsiphon) return psiphonLocation;
    if (effective.isTor) return torLocation;
    if (effective.isFirefox) return firefoxLocation;
    return selectedCountryCode ?? 'ir';
  }

  /// v4.21 — the wheel policy follows the EFFECTIVE mode: the psiphon and
  /// tor families are real selectors (owner: «در حالت تور انتخاب لوکیشن
  /// باید فعال باشه»), everything else keeps the plain display band
  /// (v4.15 #3 hide rule).
  bool get wheelSelectable =>
      LocationWheelPolicy.selectable(effectiveProtocol);

  /// The allowed wheel entries for the current protocol — family modes
  /// carry the AUTO entry first; null = the whole flag manifest (plain
  /// modes, post-connect display).
  ///
  /// v4.28 — the family sets are the LIVE truth when one exists: the
  /// psiphon set the core itself reported ([livePsiphonRegions]) and the
  /// Tor exit countries from Onionoo ([liveTorExitCountries]); the
  /// policy falls back to the standing seeds (psiphonEgressRegions /
  /// torExitCountrySnapshot) when no live set has arrived yet.
  List<String>? get wheelAllowedCodes =>
      LocationWheelPolicy.allowedCodes(
        effectiveProtocol,
        psiphonRegions: livePsiphonRegions,
        torExits: liveTorExitCountries,
        firefoxCountries: liveFirefoxCountries,
      );

  /// v4.21 — true when the wheel runs on the FULL manifest with the AUTO
  /// entry prepended (the tor family + the reverse modes).
  bool get wheelAutoEntry =>
      LocationWheelPolicy.autoEntry(effectiveProtocol);

  /// Wheel selection commit for the PLAIN family (flag snap / tap).
  /// Ignored while an operation is in flight so the selector can never
  /// fight a running transition. Family modes commit through
  /// [selectLocation] instead.
  void selectCountry(String code) {
    if (_operationInFlight) return;
    if (selectedCountryCode == code) return;
    selectedCountryCode = code;
    notifyListeners();
  }

  /// v4.19 — the app's DEFAULT protocol is WireGuard (owner device-test
  /// decree #4: «حالا که هنوز بخش تنظیمات رو طراحی نکردیم حالت دیفالت تور
  /// اور وارپ رو بزار روی پروتکل وایرگارد»). The sheet's AUTO tile still
  /// selects the core's own default (MASQUE) explicitly — only the cold
  /// default changed.
  ///
  /// v4.21 — SINGLE KNOB again (owner: the v4.20 chain/leg split was not
  /// good UX — «لطفا به حالت قبل برشگردون»): the field holds the committed
  /// mode directly — a plain tile OR a family member. The WARP leg under a
  /// family mode is the fixed WireGuard default (v4.19 decree) until the
  /// promised "AETHER core protocol" option lands.
  @override
  ProtocolId selectedProtocol = ProtocolId.wireguard;

  /// The mode the engine runs and the UI shows — with the single-knob
  /// revert this is simply the committed selection.
  ProtocolId get effectiveProtocol => selectedProtocol;

  /// v4.16 — protocol selection with notify (the sheet binds here; tapping
  /// a tile commits the protocol and auto-pops back to the home).
  void selectProtocol(ProtocolId id) {
    if (selectedProtocol == id) return;
    selectedProtocol = id;
    notifyListeners();
  }

  /// v4.16 — «حالت اتصال» (تونل/پروکسی). Default proxy per the sheet frame;
  /// the engine consumes it (M2 — see [ConnectionMode]).
  @override
  ConnectionMode connectionMode = ConnectionMode.proxy;

  void setConnectionMode(ConnectionMode mode) {
    if (connectionMode == mode) return;
    connectionMode = mode;
    notifyListeners();
  }

  /// v4.16 — «سرعت اسکن» 1..5 (the sheet frame ships the widest pill = 5
  /// selected). The engine consumes it (M2 — scan profile).
  @override
  int scanSpeed = 5;

  void setScanSpeed(int level) {
    final clamped = level.clamp(1, 5);
    if (scanSpeed == clamped) return;
    scanSpeed = clamped;
    notifyListeners();
  }

  HomeLook homeLook = HomeLook.one;
  MotionStyle animationStyle = MotionStyle.standard;

  /// v4.25 — the master animation kill-switch (appearance page: «خاموش
  /// کردن همهٔ انیمیشن‌ها»). When false, EVERY animated surface renders
  /// without non-essential motion: [effectiveMotionStyle] clamps to
  /// [MotionStyle.off] regardless of the picked style (the pick itself
  /// stays remembered — flipping the switch back restores it).
  bool animationsEnabled = true;

  void setAnimationsEnabled(bool on) {
    if (animationsEnabled == on) return;
    animationsEnabled = on;
    notifyListeners();
  }

  // ---- v4.22 settings sub-pages ----

  /// The fine-grained Aether core layer (fragment / TLS / transport /
  /// engine / family expert knobs) — owned here, mutated through
  /// [updateCore], consumed by the platform adapter, persisted as one
  /// JSON blob by the persistence layer.
  @override
  CoreSettings coreSettings = CoreSettings();

  /// The single commit path for every sub-page mutation (notify + the
  /// debounced save); changes apply from the NEXT connect.
  void updateCore(void Function(CoreSettings) mutate) {
    mutate(coreSettings);
    notifyListeners();
  }

  /// Interface-language override: null = follow the system (default),
  /// else 'fa' | 'en' | 'ru' | 'zh' | 'tk' — validated, anything else keeps
  /// the previous value. v4.23: 'tk' joins (the onboarding wizard ships a
  /// Turkmenistan tile); the SHELL maps it onto the English Material
  /// locale — AppStrings carries the tk→en fallback (documented gap until
  /// native Turkmen review + flutter_localizations coverage).
  String? appLocale;

  static const Set<String> supportedLocaleCodes = {'fa', 'en', 'ru', 'zh', 'tk'};

  void setAppLocale(String? code) {
    final pick = (code == null || supportedLocaleCodes.contains(code))
        ? code
        : appLocale;
    if (appLocale == pick) return;
    appLocale = pick;
    notifyListeners();
  }

  /// v4.22 — the background patterns on/off switch (appearance page).
  /// Default ON (the owner's own design); OFF renders the bare bg colour.
  bool showPatterns = true;

  void setShowPatterns(bool on) {
    if (showPatterns == on) return;
    showPatterns = on;
    notifyListeners();
  }

  // ---- v4.34 LIGHT MODE (owner round 10) · v4.40 the AUTO pick (round 15) ----

  /// The app theme — night by default (every earlier build shipped dark;
  /// the wizard frames are dark). The top-bar sun/moon tile flips it and
  /// the shell cross-fades the whole palette (see AethoneApp).
  ///
  /// v4.40 — this is the RESOLVED mode; the PERSISTED preference is
  /// [themePick] (night / light / auto). While the pick is AUTO the store
  /// keeps re-resolving this field by the local clock (06:00–18:00 light —
  /// see [resolveAutoTheme]); a fixed pick writes its own mode here.
  AethThemeMode themeMode = AethThemeMode.night;

  /// The persisted appearance pick (owner round 15: «حالت خودکار … از ساعت
  /// 6 صبح تا 6 عصر لایت، از 6 عصر تا 6 صبح نایت»). AUTO delegates the
  /// mode to the clock; the other two pin it.
  AethThemePick themePick = AethThemePick.night;

  void setThemeMode(AethThemeMode mode) {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
  }

  /// Commits the appearance pick: a FIXED pick resolves [themeMode] right
  /// away; AUTO re-resolves by the clock now AND at every boundary (the
  /// shell owns the re-check timer). Notifies exactly ONCE per change —
  /// [setThemeMode] is not used internally for exactly that reason.
  void setThemePick(AethThemePick pick) {
    if (themePick == pick) return;
    themePick = pick;
    final AethThemeMode target = switch (pick) {
      AethThemePick.night => AethThemeMode.night,
      AethThemePick.light => AethThemeMode.light,
      AethThemePick.auto => resolveAutoTheme(DateTime.now()),
    };
    themeMode = target; // set directly — ONE notification, below
    notifyListeners();
  }

  /// v4.40 — the AUTO schedule tick (the shell calls it every minute while
  /// the pick is AUTO): moves [themeMode] when the 06:00/18:00 boundary
  /// crosses. Returns true when the mode changed (the shell re-tweens).
  bool applyAutoThemeSchedule(DateTime localNow) {
    if (themePick != AethThemePick.auto) return false;
    final target = resolveAutoTheme(localNow);
    if (themeMode == target) return false;
    themeMode = target;
    notifyListeners();
    return true;
  }

  /// The top-bar tile: flips to the OPPOSITE of the currently-resolved
  /// mode (the tile shows the sun/moon of what IS, so the tap lands on
  /// what the user sees); an AUTO pick exits to that fixed opposite.
  void toggleThemeMode() => setThemePick(themeMode == AethThemeMode.night
      ? AethThemePick.light
      : AethThemePick.night);

  // ---- v4.40 — the desktop close behavior (owner round 15) ----

  /// What the window's close button does (desktop only): ASK every time
  /// (the owner's ask-dialog — the default), or a REMEMBERED direct action
  /// («انتخابش دفعه بعد هم اعمال بشه مستقیم»). The dialog's checkbox
  /// writes the remembered pick here.
  CloseBehavior closeBehavior = CloseBehavior.ask;

  void setCloseBehavior(CloseBehavior behavior) {
    if (closeBehavior == behavior) return;
    closeBehavior = behavior;
    notifyListeners();
  }

  /// v4.40 — «بازنشانی تنظیمات» (general settings): every USER preference
  /// returns to its factory value; the debounced save persists them all on
  /// the next tick. The wizard flag STAYS completed (a reset must never
  /// force a user back through onboarding), and the engine truth caches
  /// (SMART scorecard, live egress sets) are ENGINE data, not settings —
  /// they survive untouched.
  void resetToDefaults() {
    appLocale = null;
    homeLook = HomeLook.one;
    animationStyle = MotionStyle.standard;
    animationsEnabled = true;
    showPatterns = true;
    themePick = AethThemePick.night;
    themeMode = AethThemeMode.night;
    closeBehavior = CloseBehavior.ask;
    scanSpeed = 5;
    selectedProtocol = ProtocolId.auto;
    protocolModeSmart = false;
    connectionMode = ConnectionMode.proxy;
    selectedCountryCode = null;
    coreSettings = CoreSettings();
    notifyListeners();
  }

  // ---- v4.23 onboarding («صفحه شروع») ----

  /// True once the first-run wizard has been completed — the shell shows
  /// [OnboardingFlow] until then, and the flag persists so the wizard
  /// runs exactly once per install.
  bool onboardingComplete = false;

  /// Commits the wizard: flips [onboardingComplete] (the debounced save
  /// writes it) and notifies so the shell can hand over to the home.
  void completeOnboarding() {
    if (onboardingComplete) return;
    onboardingComplete = true;
    notifyListeners();
  }

  /// Effective style after the master kill-switch and the OS
  /// reduce-motion clamp (in that order — a disabled app never animates,
  /// whatever the accessibility setting says).
  MotionStyle effectiveMotionStyle(BuildContext context) {
    if (!animationsEnabled) return MotionStyle.off;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduce ? clampForReduceMotion(animationStyle) : animationStyle;
  }

  // ---- actions ----

  /// Connect. Multi-tap safe: while an operation is in flight, subsequent
  /// taps are ignored (they do NOT queue a second transition).
  /// Retry from `failed`/`reconnecting` enters `connecting` directly
  /// (prompt §8: «از Failed یا Reconnecting هنگام تلاش مجدد به Connecting برو»).
  Future<void> connect() async {
    if (_operationInFlight) return;
    if (state == VpnState.connected ||
        state == VpnState.connecting ||
        state == VpnState.starting ||
        state == VpnState.waitingForPermissions ||
        state == VpnState.disconnecting) {
      return;
    }
    // A fresh user intent supersedes any cancelled-walk residue.
    _cancelledWalk = false;
    _operationInFlight = true;
    notifyListeners();
    try {
      switch (state) {
        case VpnState.failed:
        case VpnState.reconnecting:
          _apply(VpnState.connecting);
        default:
          _apply(VpnState.starting);
      }
      await _engine.connect();
    } catch (e) {
      _fail(errorCode: 'engineException', message: e.toString());
    } finally {
      _operationInFlight = false;
      notifyListeners();
    }
  }

  /// Disconnect — or, while the engine walk (starting/…/connecting) is in
  /// flight, CANCEL the pending connection (owner device test #3: «حین
  /// اتصال کاربر باید بتونه اتصال رو کنسل کنه»). The state machine allows
  /// every walk state → disconnecting, and the platform adapter aborts its
  /// walk at the next checkpoint; the cancel owns the terminal state.
  Future<void> disconnect() async {
    if (_cancelling) return;
    final current = state;
    if (current == VpnState.disconnected || current == VpnState.disconnecting) {
      return;
    }
    final isCancel = _cancelableStates.contains(current);
    // A cancel interrupts the in-flight walk ON PURPOSE; a plain disconnect
    // (from connected/failed/reconnecting) still honors the single-flight
    // guard so it can never race a connect that is not running.
    if (!isCancel && _operationInFlight) return;
    _cancelling = isCancel;
    if (isCancel) _cancelledWalk = true;
    _operationInFlight = true;
    notifyListeners();
    try {
      _apply(VpnState.disconnecting);
      await _engine.disconnect();
    } catch (e) {
      _fail(errorCode: 'engineException', message: e.toString());
    } finally {
      _operationInFlight = false;
      _cancelling = false;
      notifyListeners();
    }
  }

  /// Retry from Failed/Reconnecting → Connecting (prompt §8).
  Future<void> retry() async {
    if (state == VpnState.failed || state == VpnState.reconnecting) {
      await connect();
    }
  }

  void setHomeLook(HomeLook look) {
    if (homeLook == look) return;
    homeLook = look;
    notifyListeners();
  }

  void setMotionStyle(MotionStyle style) {
    if (animationStyle == style) return;
    animationStyle = style;
    notifyListeners();
  }

  // ---- engine event mapping ----

  void _onEvent(EngineEvent event) {
    switch (event) {
      case EngineStateChanged(
        state: final eventState,
        errorCode: final errorCode,
        message: final message,
      ):
        // v4.19 (#3) — a cancelled walk's stale emission must never fight
        // the cancel: between the adapter's _disconnecting checkpoint and
        // its emission there is an unavoidable event-loop window, and the
        // emission may even land AFTER the machine already reached
        // `disconnected`. While disconnecting — or after a cancel until a
        // fresh connect starts — progress emissions from the aborted walk
        // are dropped; the cancel owns the terminal state (otherwise the
        // late `connected` would land as an illegalTransition failure).
        final cancelResidue = _cancelledWalk &&
            (_machine.current == VpnState.disconnecting ||
                _machine.current == VpnState.disconnected);
        if ((cancelResidue || _machine.current == VpnState.disconnecting) &&
            (eventState == VpnState.connected ||
                eventState == VpnState.connecting ||
                eventState == VpnState.starting ||
                eventState == VpnState.waitingForPermissions)) {
          break;
        }
        if (eventState == VpnState.failed) {
          _fail(errorCode: errorCode, message: message);
        } else {
          _apply(eventState);
        }
      case EngineHealthProbeFailed():
        if (state == VpnState.connected) {
          _apply(VpnState.reconnecting);
        }
      case EngineEndpointChanged():
        // TODO(M2): track active endpoint for the ActiveTransportSession.
        break;
      case EngineStatsUpdated(
        :final pingMs,
        :final downBytes,
        :final upBytes,
        :final exitCountryCode,
      ):
        this.pingMs = pingMs;
        this.downBytes = downBytes;
        this.upBytes = upBytes;
        // v4.31 — null means "no DISPLAYABLE exit this report": the
        // adapter strips GeoIP pseudo-countries (loc=T1, the Tor network —
        // no flag, no name) to null. Keep the last real exit (e.g. the
        // post-connect Onionoo resolution) instead of erasing it; every
        // new session clears the field on the connecting transition
        // anyway.
        if (exitCountryCode != null) this.exitCountryCode = exitCountryCode;
      case EngineEgressRegions(:final regions):
        applyPsiphonEgressRegions(regions);
      case EngineFirefoxLocations(:final countries, :final live, :final fetchedAt):
        applyFirefoxLocations(countries, live, fetchedAt);
      case EngineExitCountryResolved(:final code):
        // v4.31 — the REAL country behind a Tor exit (the trace only says
        // T1): apply it while — and only while — a session is actually
        // connected; a late resolution from a superseded walk must never
        // park a stale flag on the disconnected home screen.
        if (_machine.current == VpnState.connected) {
          exitCountryCode = code;
        }
      case EngineSmartAttempt(
          :final candidate,
          :final attempt,
          :final total,
          :final measuring,
        ):
        // v4.32 — the explicit, observable SMART chain (spec §7.2): the
        // connecting card shows which candidate is being tried; v4.34 —
        // or that its quality is being measured.
        smartAttempt = (
          candidate: candidate,
          attempt: attempt,
          total: total,
          measuring: measuring,
        );
      case EngineSmartResolved(:final protocol):
        // v4.32 — a candidate's walk reached Connected: the session runs
        // THIS protocol (the status card shows it instead of the generic
        // AUTO). Applies only while connected — a late event from a
        // superseded walk never parks a stale resolution.
        if (_machine.current == VpnState.connected) {
          smartResolvedProtocol = protocol;
          smartAttempt = null;
        }
      case EngineLogLine():
        break; // structured logging lands with the diagnostics page
    }
    notifyListeners();
  }

  void _apply(VpnState next) {
    // Dedupe: adapters may re-report the state the store already entered.
    if (next == _machine.current) return;
    if (!VpnStateMachine.isValidTransition(_machine.current, next)) {
      // An illegal jump is a bug in the adapter: fail loudly, never fake.
      _fail(
        errorCode: 'illegalTransition',
        message: '${_machine.current} → $next refused by the state machine',
      );
      return;
    }
    if (next == VpnState.disconnected || next == VpnState.connecting) {
      // Leaving/never-reaching connected ⇒ no stale ping/exit data.
      pingMs = null;
      exitCountryCode = null;
      downBytes = 0;
      upBytes = 0;
      // v4.32 — the SMART session residue clears with everything else.
      smartResolvedProtocol = null;
      if (next == VpnState.disconnected) smartAttempt = null;
    }
    _machine.transition(next);
    if (next == VpnState.connected) {
      // Owner v4.12: a SMALL haptic pulse the moment the connection really
      // lands (state-machine-verified, never on a fake/optimistic path).
      HapticFeedback.mediumImpact();
    }
  }

  void _fail({String? errorCode, String? message}) {
    lastErrorCode = errorCode;
    lastErrorMessage = message;
    // any → failed is always legal (prompt §8).
    _machine.transition(VpnState.failed);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
