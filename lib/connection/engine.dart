/// Engine boundary — the seam between the Flutter UI and the platform
/// service layer that will own Aether + zeptun (architecture B+, prompt §3/§7).
///
/// In UI step 1 NO platform layer exists yet, so the default adapter is
/// `EngineNotWiredAdapter`: it fails honestly with `engineNotWired` instead of
/// ever pretending to be connected. A clearly-gated preview adapter exists for
/// UI development only (never in release builds) — it animates the state
/// machine so every visual state can be built and golden-tested.
///
/// Rules carried over from the prompt:
///  * events are TYPED — the UI never parses log lines;
///  * `Connected` is only emitted after the end-to-end probe passes (§6.6);
///  * secrets never appear in events or logs.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_assets.dart';
import 'app_tunnel.dart';
import 'connection_state.dart';
import 'core_settings.dart';
import 'firefox/firefox_protocol.dart';

/// Minimal `ProxyEndpoint` model (prompt §7): filled only from the real
/// listener configuration — never guessed.
class ProxyEndpoint {
  const ProxyEndpoint({
    required this.modeId,
    required this.host,
    required this.port,
    required this.supportsUdp,
    required this.isReady,
  });

  final ProtocolId modeId;
  final String host;
  final int port;
  final bool supportsUdp;
  final bool isReady;
}

/// Typed engine events (prompt §7 `onEngineEvent`).
sealed class EngineEvent {
  const EngineEvent();
}

/// A state change that is LEGAL per the machine — the adapter must respect
/// the transition table; the store enforces it.
class EngineStateChanged extends EngineEvent {
  const EngineStateChanged(this.state, {this.errorCode, this.message});
  final VpnState state;
  final String? errorCode;
  final String? message;
}

/// Periodic health probe failed ⇒ store downgrades to `reconnecting` (§6).
class EngineHealthProbeFailed extends EngineEvent {
  const EngineHealthProbeFailed();
}

class EngineEndpointChanged extends EngineEvent {
  const EngineEndpointChanged(this.endpoint);
  final ProxyEndpoint? endpoint;
}

/// Live counters (zeptun stats / ping through the tunnel). Only real values
/// are ever delivered here.
class EngineStatsUpdated extends EngineEvent {
  const EngineStatsUpdated({
    this.pingMs,
    this.downBytes = 0,
    this.upBytes = 0,
    this.exitCountryCode,
  });
  final int? pingMs;
  final int downBytes;
  final int upBytes;
  final String? exitCountryCode;
}

/// v4.28 — the LIVE psiphon egress regions the core just reported (the
/// network's own `AvailableEgressRegions` notice, harvested from the
/// captured core log after a psiphon-family connect — see
/// EgressLocations.parsePsiphonEgressRegions). State-independent: the
/// wheel may show the fresh set whenever it arrives.
class EngineEgressRegions extends EngineEvent {
  const EngineEgressRegions(this.regions);
  final List<String> regions;
}

/// PHASE-2 (firefox-vpn) — the live/cached Firefox VPN location set from
/// the engine's `--discover` role (the adapter emits it after every
/// [EngineAdapter.refreshFirefoxLocations]; the store swaps it into the
/// wheel's firefox list). [live] is the honesty label: false = served
/// from the disk cache (offline start) — the UI surfaces which one it
/// got, never presenting a cache as live data.
class EngineFirefoxLocations extends EngineEvent {
  const EngineFirefoxLocations(this.countries, this.live, this.fetchedAt);
  final List<String> countries;
  final bool live;
  final DateTime fetchedAt;
}

/// v4.31 — the REAL exit country of a pseudo-country exit, resolved
/// post-connect (owner round 7: a Tor exit answers the trace with
/// `loc=T1` — Cloudflare's GeoIP pseudo-country for the Tor network —
/// which has no flag and no name). The adapter asks Onionoo (through the
/// live tunnel, by the exit relay's IP) and emits the real ISO-3166 code
/// here; the store applies it only while connected, so a late resolution
/// from a superseded walk can never park a stale flag. Unresolved ⇒ no
/// event (the UI keeps its honest unknown).
class EngineExitCountryResolved extends EngineEvent {
  const EngineExitCountryResolved(this.code);
  final String code;
}

/// v4.32 — SMART AUTO (app-layer, SMART_AUTO_SPEC.md): the walk is trying
/// this candidate now (attempt [attempt] of [total]). Emitted BEFORE each
/// per-candidate walk so the status card can show the explicit, observable
/// fallback chain (spec §7.2). Only ever sent while the committed tile is
/// AUTO and the user opted into SMART.
///
/// v4.34 — the tour got a MEASUREMENT phase (owner round 10: a candidate
/// that connects is quality-probed, not settled on): [measuring] is true
/// while the live candidate's ping samples are being taken — the status
/// card says «سنجش کیفیت …» instead of «در حال اتصال …».
class EngineSmartAttempt extends EngineEvent {
  const EngineSmartAttempt(this.candidate, this.attempt, this.total,
      {this.measuring = false});
  final ProtocolId candidate;
  final int attempt;
  final int total;
  final bool measuring;
}

/// v4.32 — SMART AUTO resolved: a candidate's walk REACHED Connected —
/// the live session runs [protocol] (the UI shows it in place of the
/// generic AUTO). Emitted once per successful smart connect, right after
/// the Connected state.
class EngineSmartResolved extends EngineEvent {
  const EngineSmartResolved(this.protocol);
  final ProtocolId protocol;
}

/// Structured log line (level + message; secrets already stripped upstream).
class EngineLogLine extends EngineEvent {
  const EngineLogLine(this.level, this.message);
  final String level;
  final String message;
}

/// Read-only view of the user's tunnel configuration the platform adapter
/// consumes (M2). Implemented by the store — these are USER choices; the
/// engine never writes them.
abstract class EngineConfigSource {
  /// The protocol the user committed on the protocol sheet — ONE knob: a
  /// plain tile (AUTO..MIM) or a family member (torChain…psiphonOnly).
  /// v4.21: the v4.20 chain/leg SPLIT was reverted per the owner's decree
  /// («حالت جدید که برای انتخاب پروتکل AETHER در حالت اور وارپ ایجاد کردی
  /// از لحاظ تجربه کاربری جالب نیست لطفا به حالت قبل برشگردون بعدا یک
  /// گزینه برای انتخاب پروتکل هسته AETHER در پروتکل های اور وارپ اضافه
  /// میکنیم») — the WARP leg under a family mode is fixed WireGuard (the
  /// v4.19 decree) until that dedicated option lands.
  ProtocolId get selectedProtocol;

  /// تونل (whole-device VpnService + zeptun) or پروکسی (local SOCKS only).
  ConnectionMode get connectionMode;

  /// Flag-wheel country pick (ISO-3166 alpha-2, lowercase) or null = auto.
  String? get selectedCountryCode;

  /// v4.21 — the per-family location picks (owner: «اپ باید انتخاب لوکیشن
  /// سایفون و تور رو یادش بمونه» + «برای سایفون و تور به انتخاب خودکار هم
  /// باید بزاریم»): 'auto' = the core's own choice, else an ISO-3166
  /// alpha-2 lowercase code. The adapter maps them per mode
  /// (--psiphon-region / --exit-loc / no pin for tor-exit modes).
  String get psiphonLocation;
  String get torLocation;

  /// PHASE-2 (firefox-vpn) — the firefox family's own pick: 'auto' (the
  /// engine's AUTO = Mozilla's REC anycast) or an ISO-3166 alpha-2
  /// lowercase code from the LIVE RemoteSettings list (never the static
  /// flag manifest). Persisted like the family picks above.
  String get firefoxLocation;

  /// PHASE-2 — the firefox data-plane transport: 'h2' (default, TCP +
  /// TLS 1.3) or 'h3' (QUIC). Fed verbatim to the engine config.
  String get firefoxTransport;

  /// Process-local resolver policy for Firefox control-plane traffic only.
  Map<String, dynamic> get firefoxDnsConfig => const {'mode': 'system'};

  /// «سرعت اسکن» 1..5 (protocol sheet; feeds the core scan profile).
  int get scanSpeed;

  /// v4.41 (owner round 17, item 3): the routing-area pick — 'ir'/'tm'/
  /// 'ru'/'cn' or null (= none). The adapter materializes the country's
  /// routing profile (lib/connection/country_routes.dart) and plants
  /// `AETHER_ROUTES_FILE` before every core start: the selected country's
  /// own domains + IP space go DIRECT, everything else tunnels. Before
  /// v4.41 this pick was persisted but never consumed — the profiles
  /// routed nothing.
  String? get routingRegion;

  /// v4.41 (owner round 17, item 4): the per-app tunneling pick (Android,
  /// tunnel mode) — [AppTunnelMode.all] keeps the whole-device TUN, the
  /// other two modes apply [appTunnelApps] through the VpnService
  /// Builder's allow/disallow lists.
  AppTunnelMode get appTunnelMode;
  Set<String> get appTunnelApps;

  /// v4.32 — the AUTO/SMART protocol-mode pill (connection page +
  /// onboarding). SMART is the APP-LAYER selector (SMART_AUTO_SPEC.md §3:
  /// the pinned core has no auto-ranking); AUTO keeps the core's own
  /// default resolution (masque). Only meaningful together with the AUTO
  /// tile — a manual protocol pick is never rewritten (spec §7.6).
  bool get protocolModeSmart;

  /// v4.22 — the fine-grained Aether core layer (fragment / TLS /
  /// transport / engine / family expert knobs). The adapter folds it into
  /// the arg list + process env of every `aether_core_start`.
  CoreSettings get coreSettings;
}

/// The seam the UI talks to. The production implementation (M2) drives the
/// platform service (MethodChannel/FFI) that owns both engines.
///
/// Division of responsibility (UI step 1): the STORE owns user-intent
/// transitions (`starting`, `disconnecting`); adapters only report PROGRESS
/// (`waitingForPermissions`, `connecting`, `connected`, `disconnected`,
/// `failed`). This keeps the machine single-flight and retry-legal.
abstract class EngineAdapter {
  Stream<EngineEvent> get events;
  Future<void> connect();
  Future<void> disconnect();

  /// Gives the adapter a read-only view of the user's configuration.
  /// Called once by the store right after construction; default no-op
  /// (preview / not-wired adapters never read user config).
  void bind(EngineConfigSource config) {}

  // ---- PHASE-2 (firefox-vpn) — the firefox engine surface. Defaults
  // keep the preview/not-wired adapters honest (no engine = no
  // locations, no session, a failed login) without special-casing them
  // everywhere.

  /// Asks the adapter to refresh the Firefox location list through the
  /// engine's `--discover` role; the result arrives as an
  /// [EngineFirefoxLocations] event. Default: no-op.
  Future<void> refreshFirefoxLocations() async {}

  /// Runs the WebChannel login exchange (the engine's `--login` role).
  /// Default: the honest not-wired failure.
  Future<FirefoxLoginResult> firefoxWebChannelLogin(
    String sessionToken, {
    void Function(String line)? onLog,
  }) async =>
      FirefoxLoginResult.failed(
        'engineNotWired',
        'the Firefox VPN engine is not available on this platform',
      );

  /// Whether a session pair lives in the Keystore vault. Default: absent.
  Future<bool> firefoxHasSession() async => false;

  /// The sign-out vault wipe. Default: no-op.
  Future<void> firefoxClearSession() async {}

  /// Cancels an in-flight login exchange. Default: no-op.
  Future<void> firefoxLoginCancel() async {}

  /// Runs the engine's DNS-only diagnostic role. Null means this platform
  /// has no Firefox engine process available.
  Future<List<Map<String, dynamic>>?> firefoxDnsProbe(
    Map<String, dynamic> dnsConfig,
  ) async => null;
}

/// Default adapter until the native service lands (M2): fails honestly.
class EngineNotWiredAdapter extends EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  @override
  void bind(EngineConfigSource config) {} // nothing to configure — never wired

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    _controller.add(
      const EngineStateChanged(
        VpnState.failed,
        errorCode: 'engineNotWired',
        message: 'Native engine layer is not wired yet (milestone M2).',
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _controller.add(const EngineStateChanged(VpnState.disconnected));
  }

  void dispose() => _controller.close();
}

/// PREVIEW-ONLY adapter (UI development / golden tests). Gated behind
/// `--dart-define=PREVIEW_MODE=true` AND never active in release builds.
/// It simulates the legal state walk so every visual state can be exercised;
/// it must NEVER ship enabled — see `PreviewEngineAdapter.allowed`.
class PreviewEngineAdapter extends EngineAdapter {
  PreviewEngineAdapter({
    // v4.11 (owner defect #10): the connecting walk must last long enough
    // for the scanning halo behind the central icon to be SEEN and for the
    // swipe gesture to feel like a real handshake (~2.6 s). Preview-only.
    this.stepDelay = const Duration(milliseconds: 2600),
    this.samplePingMs = 146,
    this.sampleExitCountry = 'ir',
  });

  final Duration stepDelay;
  final int samplePingMs;
  final String sampleExitCountry;

  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  static const bool requested = bool.fromEnvironment('PREVIEW_MODE');

  /// Preview simulation is allowed only in non-release builds with the
  /// explicit opt-in flag.
  static bool get allowed => requested && !kReleaseMode;

  /// v4.19 (#3): the simulated walk is CANCELLABLE mid-flight — the owner's
  /// device-test decree «حین اتصال کاربر باید بتونه اتصال رو کنسل کنه» has
  /// to be exercisable in the preview builds too. A cancelled walk emits
  /// NOTHING itself; the disconnect that cancelled it owns the terminal
  /// event (otherwise a late `connected` would be an illegal jump).
  bool _cancelled = false;
  bool _walking = false;

  @override
  void bind(EngineConfigSource config) {} // simulation ignores user config

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    if (_walking) return;
    _walking = true;
    _cancelled = false;
    _emit(const EngineStateChanged(VpnState.connecting));
    // Small slices so a cancel is honored within ~50 ms instead of after
    // the whole stepDelay.
    var waited = Duration.zero;
    while (!_cancelled && waited < stepDelay) {
      const slice = Duration(milliseconds: 50);
      await Future<void>.delayed(slice);
      waited += slice;
    }
    _walking = false;
    if (_cancelled) return;
    // End-to-end probe "passed" in preview — this is a SIMULATION, clearly
    // documented; production Connected only comes from the real probe.
    _emit(const EngineStateChanged(VpnState.connected));
    _emit(
      EngineStatsUpdated(
        pingMs: samplePingMs,
        exitCountryCode: sampleExitCountry,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    if (_walking) {
      // Cancellation (#3): the in-flight walk aborts silently (it flips
      // _walking itself when it exits); this call owns the terminal state.
      _cancelled = true;
      // Give the walk slice loop a beat to observe the flag and exit.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    } else {
      await Future<void>.delayed(stepDelay);
    }
    _emit(const EngineStateChanged(VpnState.disconnected));
  }

  void _emit(EngineEvent e) => _controller.add(e);

  void dispose() => _controller.close();
}
