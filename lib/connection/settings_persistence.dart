/// Settings persistence (v4.19 #8 — owner device test: «اپ انتخاب های
/// تنظیمات رو یادش نمیمونه»). The ConnectionStore is the single source of
/// the user's choices; this layer mirrors those choices into
/// `shared_preferences` and restores them before the first frame:
///
///  * restore() runs BEFORE runApp — the cold start renders with the
///    user's values, never a flash of the defaults;
///  * attach() subscribes to the store and debounces saves (200 ms) —
///    notify storms during the connect walk never translate into
///    write bursts;
///  * every restored value is VALIDATED against its enum/range — a stale
///    or hand-edited prefs file can only fall back to the built-in
///    defaults, never crash the startup.
///
/// Persisted: protocol (the single v4.21 knob; the v4.20 chain key is
/// migrated on read), connection mode, scan speed, wheel country + the
/// per-family locations (v4.21), protocol mode (auto/smart), routing
/// region, kill switch, home look, motion style. Session data (ping,
/// counters, exit country) is deliberately NOT persisted — it is
/// engine-owned truth.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_assets.dart';
import '../core/app_theme.dart';
import '../core/motion.dart';
import 'connection_state.dart';
import 'app_tunnel.dart';
import 'connection_store.dart';
import 'core_settings.dart';
import 'egress_locations.dart';
import 'transport_modes.dart';

abstract final class SettingsKeys {
  static const protocol = 'aethone.settings.protocol';

  /// v4.20 legacy — the chain overlay key. Read for migration (a v4.20
  /// install stored the WARP leg in [protocol] and the family member
  /// here); written as 'none' to retire it.
  static const chain = 'aethone.settings.chain';
  static const connectionMode = 'aethone.settings.connectionMode';
  static const scanSpeed = 'aethone.settings.scanSpeed';
  static const selectedCountry = 'aethone.settings.selectedCountry';

  /// v4.21 — the per-family location picks (owner: «اپ باید انتخاب لوکیشن
  /// سایفون و تور رو یادش بمونه»): 'auto' or an ISO-3166 alpha-2 code.
  static const psiphonLocation = 'aethone.settings.psiphonLocation';
  static const torLocation = 'aethone.settings.torLocation';
  static const protocolModeSmart = 'aethone.settings.protocolModeSmart';
  static const routingRegion = 'aethone.settings.routingRegion';

  /// v4.41 — per-app tunneling (Android, tunnel mode): the mode name +
  /// the selected package list.
  static const appTunnelMode = 'aethone.settings.appTunnelMode';
  static const appTunnelApps = 'aethone.settings.appTunnelApps';
  static const killSwitch = 'aethone.settings.killSwitch';
  static const homeLook = 'aethone.settings.homeLook';
  static const motionStyle = 'aethone.settings.motionStyle';

  /// v4.22 — the fine-grained Aether core layer: ONE JSON blob (unknown
  /// keys / old shapes fall back to the built-in defaults — never crash).
  static const coreSettings = 'aethone.settings.coreSettings';

  /// v4.22 — interface-language override; missing = follow system (null).
  static const appLocale = 'aethone.settings.appLocale';

  /// v4.22 — the background-patterns switch (default ON).
  static const showPatterns = 'aethone.settings.showPatterns';

  /// v4.25 — the master animation kill-switch (default ON).
  static const animationsEnabled = 'aethone.settings.animationsEnabled';

  /// v4.34 — the app theme ('night' | 'light'; default night). v4.40: the
  /// RESOLVED mode — the persisted PREFERENCE is [themePick]; this key
  /// stays written (the shell reads it before the store binds on cold
  /// start) and doubles as the legacy seed for themePick.
  static const themeMode = 'aethone.settings.themeMode';

  /// v4.40 — the appearance pick ('night' | 'light' | 'auto'; default
  /// seeded from the legacy themeMode key, else night).
  static const themePick = 'aethone.settings.themePick';

  /// v4.40 — the desktop close behavior ('ask' | 'close' | 'tray'; default
  /// ask — the owner's round-15 ask-dialog).
  static const closeBehavior = 'aethone.settings.closeBehavior';

  /// v4.23 — the first-run wizard («صفحه شروع») completed flag; missing
  /// means the onboarding still owes the user a run.
  static const onboardingComplete = 'aethone.onboarding.complete';
}

/// The store→storage bridge. [restore] + [attach] are the only operations;
/// the store's own API and defaults stay untouched (tests construct plain
/// stores and stay deterministic).
class SettingsPersistence {
  SettingsPersistence({Future<SharedPreferences>? prefs})
    : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;
  Timer? _saveDebounce;
  bool _restored = false;
  ConnectionStore? _store;

  /// Applies the persisted values onto [store]. Missing keys keep the
  /// store's built-in defaults; invalid values fall back too (validated).
  Future<void> restore(ConnectionStore store) async {
    try {
      final prefs = await _prefsFuture;

      // v4.21 — single-knob protocol restore with the v4.20 migration:
      // a v4.20 install stored the WARP LEG in `protocol` and the family
      // member in `chain`; the effective mode was the chain, so the chain
      // WINS the migration. A v4.19 install stored the mode directly.
      ProtocolId? restored;
      final protocolName = prefs.getString(SettingsKeys.protocol);
      if (protocolName != null) {
        for (final id in ProtocolId.values) {
          if (id.name == protocolName) {
            restored = id;
            break;
          }
        }
      }
      final chainName = prefs.getString(SettingsKeys.chain);
      if (chainName != null && chainName != 'none') {
        for (final id in ProtocolId.values) {
          if (id.name == chainName && (id.isTor || id.isPsiphon)) {
            restored = id; // the v4.20 overlay supersedes the stored leg
            break;
          }
        }
      }
      if (restored != null) store.selectedProtocol = restored;
      final modeName = prefs.getString(SettingsKeys.connectionMode);
      if (modeName == ConnectionMode.tunnel.name) {
        store.connectionMode = ConnectionMode.tunnel;
      } else if (modeName == ConnectionMode.proxy.name) {
        store.connectionMode = ConnectionMode.proxy;
      }
      final speed = prefs.getInt(SettingsKeys.scanSpeed);
      if (speed != null && speed >= 1 && speed <= 5) {
        store.scanSpeed = speed;
      }
      final country = prefs.getString(SettingsKeys.selectedCountry);
      if (country == null) {
        store.selectedCountryCode = null;
      } else if (country.length == 2 && country == country.toLowerCase()) {
        store.selectedCountryCode = country;
      }
      // v4.21 — the per-family location picks.
      final psiphon = prefs.getString(SettingsKeys.psiphonLocation);
      if (_isLocationPick(psiphon)) {
        store.psiphonLocation = psiphon!;
      }
      final tor = prefs.getString(SettingsKeys.torLocation);
      if (_isLocationPick(tor)) {
        store.torLocation = tor!;
      }
      if (prefs.containsKey(SettingsKeys.protocolModeSmart)) {
        store.protocolModeSmart = prefs.getBool(SettingsKeys.protocolModeSmart)!;
      }
      final region = prefs.getString(SettingsKeys.routingRegion);
      if (region == null) {
        store.routingRegion = null;
      } else if (region.length == 2 && region == region.toLowerCase()) {
        store.routingRegion = region;
      }
      // v4.41 — per-app tunneling: unknown mode names fall back to `all`
      // (never crash an old/corrupt blob); the package list is stored
      // verbatim (uninstalled packages are skipped by the service).
      store.appTunnelMode = AppTunnelMode.fromName(
        prefs.getString(SettingsKeys.appTunnelMode),
      );
      store.appTunnelApps = prefs
              .getStringList(SettingsKeys.appTunnelApps)
              ?.where((p) => p.trim().isNotEmpty)
              .toSet() ??
          <String>{};
      if (prefs.containsKey(SettingsKeys.killSwitch)) {
        store.killSwitch = prefs.getBool(SettingsKeys.killSwitch)!;
      }
      final look = prefs.getString(SettingsKeys.homeLook);
      if (look == HomeLook.one.name) {
        store.homeLook = HomeLook.one;
      } else if (look == HomeLook.two.name) {
        store.homeLook = HomeLook.two;
      }
      final motion = prefs.getString(SettingsKeys.motionStyle);
      if (motion == MotionStyle.standard.name) {
        store.animationStyle = MotionStyle.standard;
      } else if (motion == MotionStyle.smooth.name) {
        store.animationStyle = MotionStyle.smooth;
      } else if (motion == MotionStyle.dynamic.name) {
        store.animationStyle = MotionStyle.dynamic;
      } else if (motion == MotionStyle.minimal.name) {
        // v4.25 — the fourth style joins the picker.
        store.animationStyle = MotionStyle.minimal;
      }
      // v4.22 — the Aether core fine-grained layer (one JSON blob).
      final coreRaw = prefs.getString(SettingsKeys.coreSettings);
      if (coreRaw != null) {
        try {
          final decoded = jsonDecode(coreRaw);
          if (decoded != null) {
            final parsed = CoreSettings.fromJson(decoded);
            if (parsed != CoreSettings()) {
              store.coreSettings = parsed;
            }
          }
        } catch (_) {
          // A malformed blob keeps the defaults — persistence must never
          // block the app.
        }
      }
      // v4.22 — interface language + the patterns switch.
      final localeCode = prefs.getString(SettingsKeys.appLocale);
      if (localeCode == null) {
        store.appLocale = null;
      } else if (ConnectionStore.supportedLocaleCodes.contains(localeCode)) {
        store.appLocale = localeCode;
      }
      if (prefs.containsKey(SettingsKeys.showPatterns)) {
        store.showPatterns = prefs.getBool(SettingsKeys.showPatterns)!;
      }
      // v4.25 — the master animation kill-switch.
      if (prefs.containsKey(SettingsKeys.animationsEnabled)) {
        store.animationsEnabled = prefs.getBool(SettingsKeys.animationsEnabled)!;
      }
      // v4.34 — the app theme (light mode, owner round 10).
      final themeName = prefs.getString(SettingsKeys.themeMode);
      if (themeName == AethThemeMode.night.name) {
        store.themeMode = AethThemeMode.night;
      } else if (themeName == AethThemeMode.light.name) {
        store.themeMode = AethThemeMode.light;
      }
      // v4.40 — the appearance pick (owner round 15's AUTO mode): the
      // resolved [store.themeMode] above is only the cold-start render
      // seed; the pick owns the preference. A missing pick inherits the
      // legacy themeMode value (an existing install keeps its face); AUTO
      // re-resolves by the clock at restore.
      final pickName = prefs.getString(SettingsKeys.themePick);
      if (pickName == AethThemePick.auto.name) {
        store.themePick = AethThemePick.auto;
        store.themeMode = resolveAutoTheme(DateTime.now());
      } else if (pickName == AethThemePick.light.name) {
        store.themePick = AethThemePick.light;
        store.themeMode = AethThemeMode.light;
      } else if (pickName == AethThemePick.night.name) {
        store.themePick = AethThemePick.night;
        store.themeMode = AethThemeMode.night;
      } else {
        store.themePick = store.themeMode == AethThemeMode.light
            ? AethThemePick.light
            : AethThemePick.night;
      }
      // v4.40 — the desktop close behavior (owner round 15).
      final closeName = prefs.getString(SettingsKeys.closeBehavior);
      if (closeName == CloseBehavior.close.name) {
        store.closeBehavior = CloseBehavior.close;
      } else if (closeName == CloseBehavior.tray.name) {
        store.closeBehavior = CloseBehavior.tray;
      } else {
        store.closeBehavior = CloseBehavior.ask;
      }
      // v4.23 — the onboarding flag.
      store.onboardingComplete =
          prefs.getBool(SettingsKeys.onboardingComplete) ?? false;
      // v4.28 — seed the LIVE egress sets from their cache (engine truth,
      // NOT user preferences — the keys are owned by EgressLocations and
      // the saves happen at harvest/refresh time, never in attach()).
      // A missing cache keeps the built-in seeds (the standing psiphon
      // set / the bundled Tor snapshot).
      final psiphonLive = await EgressLocations.loadCachedPsiphonEgress();
      if (psiphonLive != null) {
        store.applyPsiphonEgressRegions(psiphonLive);
      }
      final torLive = await EgressLocations.loadCachedTorExits();
      if (torLive != null) {
        store.applyTorExitCountries(torLive);
      }
      // v4.23 — the wizard's RECOMMENDED defaults for a fresh install
      // (the step-4 frame ships تونل selected, اتوماتیک selected and the
      // widest scan pill — and step 1 ships فارسی pre-picked): applied
      // ONLY while the wizard has never been completed AND the user has
      // no explicit persisted pick of their own, so every existing
      // install keeps its choices untouched.
      if (!prefs.containsKey(SettingsKeys.onboardingComplete)) {
        if (!prefs.containsKey(SettingsKeys.appLocale)) {
          store.appLocale = 'fa';
        }
        if (!prefs.containsKey(SettingsKeys.connectionMode)) {
          store.connectionMode = ConnectionMode.tunnel;
        }
        if (!prefs.containsKey(SettingsKeys.protocolModeSmart)) {
          store.protocolModeSmart = true;
        }
        if (!prefs.containsKey(SettingsKeys.scanSpeed)) {
          store.scanSpeed = 5;
        }
      }
      _restored = true;
    } catch (e) {
      // Persistence must never block the app: with a broken storage the
      // store simply runs on its defaults.
      debugPrint('SettingsPersistence.restore failed: $e');
    }
  }

  /// A valid family pick: the AUTO sentinel or an ISO-3166 alpha-2
  /// lowercase code.
  static bool _isLocationPick(String? value) =>
      value != null &&
      (value == LocationWheelPolicy.autoCode ||
          (value.length == 2 && value == value.toLowerCase()));

  /// Persists every change of [store] (debounced). Call once, after
  /// [restore]; a store that was never restored still saves normally.
  void attach(ConnectionStore store) {
    _store = store;
    store.addListener(_scheduleSave);
  }

  /// Detaches the listener (tests / hot restart hygiene).
  void detach(ConnectionStore store) {
    _saveDebounce?.cancel();
    store.removeListener(_scheduleSave);
    _store = null;
  }

  void _scheduleSave() {
    if (!_restored) return; // never echo the pre-restore frame back
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 200), () {
      final store = _store;
      if (store != null) save(store);
    });
  }

  /// Immediate, synchronous-with-store snapshot writer (used by the
  /// debounced timer and directly by tests).
  Future<void> save(ConnectionStore store) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(SettingsKeys.protocol, store.selectedProtocol.name);
      // v4.21 — retire the v4.20 chain key (single-knob model).
      await prefs.setString(SettingsKeys.chain, 'none');
      await prefs.setString(
        SettingsKeys.connectionMode,
        store.connectionMode.name,
      );
      await prefs.setInt(SettingsKeys.scanSpeed, store.scanSpeed);
      final country = store.selectedCountryCode;
      if (country == null) {
        await prefs.remove(SettingsKeys.selectedCountry);
      } else {
        await prefs.setString(SettingsKeys.selectedCountry, country);
      }
      await prefs.setString(
        SettingsKeys.psiphonLocation,
        store.psiphonLocation,
      );
      await prefs.setString(SettingsKeys.torLocation, store.torLocation);
      await prefs.setBool(
        SettingsKeys.protocolModeSmart,
        store.protocolModeSmart,
      );
      final region = store.routingRegion;
      if (region == null) {
        await prefs.remove(SettingsKeys.routingRegion);
      } else {
        await prefs.setString(SettingsKeys.routingRegion, region);
      }
      // v4.41 — per-app tunneling.
      await prefs.setString(
        SettingsKeys.appTunnelMode,
        store.appTunnelMode.name,
      );
      await prefs.setStringList(
        SettingsKeys.appTunnelApps,
        store.appTunnelApps.toList(growable: false),
      );
      await prefs.setBool(SettingsKeys.killSwitch, store.killSwitch);
      await prefs.setString(SettingsKeys.homeLook, store.homeLook.name);
      await prefs.setString(SettingsKeys.motionStyle, store.animationStyle.name);
      // v4.22 — the core layer, the language override, the patterns switch.
      await prefs.setString(
        SettingsKeys.coreSettings,
        store.coreSettings.encode(),
      );
      final locale = store.appLocale;
      if (locale == null) {
        await prefs.remove(SettingsKeys.appLocale);
      } else {
        await prefs.setString(SettingsKeys.appLocale, locale);
      }
      await prefs.setBool(SettingsKeys.showPatterns, store.showPatterns);
      // v4.25 — the animation kill-switch rides every snapshot.
      await prefs.setBool(
        SettingsKeys.animationsEnabled,
        store.animationsEnabled,
      );
      // v4.34 — the app theme rides every snapshot (v4.40: the RESOLVED
      // mode + the pick that owns it).
      await prefs.setString(
        SettingsKeys.themeMode,
        store.themeMode.name,
      );
      await prefs.setString(
        SettingsKeys.themePick,
        store.themePick.name,
      );
      // v4.40 — the desktop close behavior rides every snapshot.
      await prefs.setString(
        SettingsKeys.closeBehavior,
        store.closeBehavior.name,
      );
      // v4.23 — the wizard flag rides every snapshot so a completed run
      // survives restarts (and mid-flow kills resume rather than restart
      // — the flow re-runs, but each step's persisted picks reload).
      await prefs.setBool(
        SettingsKeys.onboardingComplete,
        store.onboardingComplete,
      );
    } catch (e) {
      debugPrint('SettingsPersistence.save failed: $e');
    }
  }
}
