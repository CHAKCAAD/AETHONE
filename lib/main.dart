import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'connection/connection_state.dart';
import 'connection/connection_store.dart';
import 'connection/desktop_window.dart';
import 'connection/egress_locations.dart';
import 'connection/platform_engine_adapter.dart';
import 'connection/settings_persistence.dart';
import 'connection/smart_scorecard.dart';

/// v2.1.0 — the cold-start half of the tile/widget quick-connect: asks
/// the activity once whether the launch intent carried the flag (the
/// method clears it natively as it answers — a stale ask never re-fires).
/// No method / no activity (the test hosts) stays silent.
Future<void> _takeQuickConnectAsk(ConnectionStore store) async {
  final asked = await DesktopWindowChannel.invokeRawBool('takeQuickConnect');
  if (asked == true) {
    if (store.state == VpnState.disconnected ||
        store.state == VpnState.failed) {
      unawaited(store.connect());
    }
  }
}

Future<void> main() async {
  // The ConnectionStore is constructed with the (first) app widget and its
  // platform adapter registers the aethone/engine MethodChannel handler right
  // away — the binding must exist before that (M2).
  WidgetsFlutterBinding.ensureInitialized();

  // v4.19 (#8 — owner device test: «اپ انتخاب های تنظیمات رو یادش نمیمونه»):
  // the user's settings are restored BEFORE the first frame, so the cold
  // start renders the remembered protocol/mode/country/etc. — never a flash
  // of the defaults — and every later change is saved (debounced).
  final store = ConnectionStore();
  final persistence = SettingsPersistence();
  await persistence.restore(store);
  persistence.attach(store);

  // v4.32 — the SMART scorecard (engine truth, its own prefs key — the
  // EgressLocations pattern): merge the persisted standings INTO the live
  // instance the adapter already holds, so the first SMART connect orders
  // its candidates by everything the device has ever measured. Fire-safe:
  // a missing/malformed cache keeps the fresh scorecard.
  final cachedScorecard = await loadCachedScorecard();
  if (cachedScorecard != null) {
    store.smartScorecard.loadFrom(cachedScorecard.toJson());
  }

  // v4.28 — REAL egress locations (owner round 5: «لوکیشن های واقعی، نه
  // فیک»): refresh the Tor exit-country set from the network's own
  // metrics API (Onionoo) when the cache is stale. Fire-and-forget — an
  // offline start keeps the cached set / the bundled snapshot, and the
  // psiphon set arrives from the core itself at the next psiphon connect.
  unawaited(
    EgressLocations.refreshTorExits(store.applyTorExitCountries),
  );

  // v4.40 — the desktop window/tray bridge (owner round 15): the close
  // button's ask-dialog, the remembered pick, and the tray menu's toggle
  // entry. No-op on Android.
  DesktopWindowBridge(store).bind();

  // v4.41 (owner round 17, item 12) — the Android connection notifications'
  // «قطع اتصال» action: the SAME full user disconnect the in-app button
  // runs (core + TUN + hold service + state machine), fired from the
  // service's action button through the engine channel. The store's
  // single-flight guard owns every other state.
  PlatformEngineAdapter.onNotificationDisconnect = () {
    final state = store.state;
    if (state == VpnState.connected ||
        state == VpnState.connecting ||
        state == VpnState.starting ||
        state == VpnState.reconnecting) {
      unawaited(store.disconnect());
    }
  };

  // v2.1.0 (the owner's decree, 2026-11-17: «برای بخش کنترل سنتر گوشی هم
  // ویجت اضافه کن») — the quick-settings tile / home widget quick-connect:
  // the tile's connect tap launches the app with the QUICK_CONNECT flag;
  // the activity hands it over as a `quickConnect` method call (live
  // activity) or a one-shot `takeQuickConnect` poll (cold start). The
  // store's own connect() runs the walk — no second engine channel.
  PlatformEngineAdapter.onQuickConnect = () {
    if (store.state == VpnState.disconnected || store.state == VpnState.failed) {
      unawaited(store.connect());
    }
  };
  unawaited(_takeQuickConnectAsk(store));

  runApp(AethoneApp(store: store));
}
