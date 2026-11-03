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
/// Persisted: protocol, connection mode, scan speed, wheel country,
/// protocol mode (auto/smart), routing region, kill switch, home look,
/// motion style. Session data (ping, counters, exit country) is
/// deliberately NOT persisted — it is engine-owned truth.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_assets.dart';
import '../core/motion.dart';
import 'connection_state.dart';
import 'connection_store.dart';

abstract final class SettingsKeys {
  static const protocol = 'aethone.settings.protocol';
  static const connectionMode = 'aethone.settings.connectionMode';
  static const scanSpeed = 'aethone.settings.scanSpeed';
  static const selectedCountry = 'aethone.settings.selectedCountry';
  static const protocolModeSmart = 'aethone.settings.protocolModeSmart';
  static const routingRegion = 'aethone.settings.routingRegion';
  static const killSwitch = 'aethone.settings.killSwitch';
  static const homeLook = 'aethone.settings.homeLook';
  static const motionStyle = 'aethone.settings.motionStyle';
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
      final protocolName = prefs.getString(SettingsKeys.protocol);
      if (protocolName != null) {
        for (final id in ProtocolId.values) {
          if (id.name == protocolName) {
            store.selectedProtocol = id;
            break;
          }
        }
      }
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
      if (prefs.containsKey(SettingsKeys.protocolModeSmart)) {
        store.protocolModeSmart = prefs.getBool(SettingsKeys.protocolModeSmart)!;
      }
      final region = prefs.getString(SettingsKeys.routingRegion);
      if (region == null) {
        store.routingRegion = null;
      } else if (region.length == 2 && region == region.toLowerCase()) {
        store.routingRegion = region;
      }
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
      }
      _restored = true;
    } catch (e) {
      // Persistence must never block the app: with a broken storage the
      // store simply runs on its defaults.
      debugPrint('SettingsPersistence.restore failed: $e');
    }
  }

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
      await prefs.setBool(SettingsKeys.killSwitch, store.killSwitch);
      await prefs.setString(SettingsKeys.homeLook, store.homeLook.name);
      await prefs.setString(SettingsKeys.motionStyle, store.animationStyle.name);
    } catch (e) {
      debugPrint('SettingsPersistence.save failed: $e');
    }
  }
}
