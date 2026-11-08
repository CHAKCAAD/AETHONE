/// Transport-mode table — the evidence-locked endpoint map (phase-1 report
/// table 11, sourced from `aether_cli_flags.json` with direct code references
/// to aether/src/cli.rs at the frozen pin). This is the data behind the future
/// `ActiveTransportSession` (prompt §12-الحاقیه): Zeptun connects to the
/// endpoint of the SELECTED mode only — no fallback, no guessing.
library;

import '../core/app_assets.dart';

/// What leaves the tunnel (defines which listener Zeptun must use).
enum ExitKind {
  warp,
  torExit,
  psiphonExit,

  /// PHASE-1 (firefox-vpn): the exit is a Firefox VPN (Fastly MASQUE)
  /// egress — reported from the REAL tunnel probe, never assumed from
  /// the selected country (docs/FIREFOX_VPN_SERVER_DISCOVERY.md §6).
  firefoxExit,
}

class TransportMode {
  const TransportMode({
    required this.id,
    required this.label,
    required this.cliValue,
    required this.socksEndpoint,
    required this.exitKind,
    required this.tcpOnly,
    required this.evidence,
  });

  final ProtocolId id;
  final String label;

  /// The env/flag value selecting this mode on the Aether command line.
  final String cliValue;

  /// The SOCKS5 endpoint Zeptun must be configured with for THIS mode.
  /// 127.0.0.1:1819 = main `--bind`; 1820 = `--tor-bind`; 1821 = `--psiphon-bind`.
  final Uri socksEndpoint;

  final ExitKind exitKind;

  /// true ⇒ UDP ASSOCIATE only carries DNS; everything else is dropped
  /// (socks.rs L1084-1093). UI must show the honest "TCP only" label.
  final bool tcpOnly;

  /// Source citation (aether/src at the frozen pin).
  final String evidence;

  bool get isReadyGateRequired => true;
}

abstract final class TransportModes {
  static const String _host = '127.0.0.1';

  /// MASQUE — Aether's real default protocol (NOT WireGuard; the reference
  /// mock merely shows WireGuard selected — report diff-table row 10).
  static final TransportMode masque = TransportMode(
    id: ProtocolId.masque,
    label: 'MASQUE',
    cliValue: 'masque',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.warp,
    tcpOnly: false,
    evidence: 'cli.rs L581 (--bind); socks.rs serve()',
  );

  static final TransportMode wireguard = TransportMode(
    id: ProtocolId.wireguard,
    label: 'WIREGUARD',
    cliValue: 'wg',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.warp,
    tcpOnly: false,
    evidence: 'AETHER_PROTOCOL=wg; same --bind listener',
  );

  static final TransportMode gool = TransportMode(
    id: ProtocolId.gool,
    label: 'GOOL',
    cliValue: 'gool',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.warp,
    tcpOnly: false,
    evidence: 'AETHER_PROTOCOL=gool; same --bind listener',
  );

  static final TransportMode goolClassic = TransportMode(
    id: ProtocolId.goolClassic,
    label: 'GOOL CLASSIC',
    cliValue: 'gool + --gool-classic',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.warp,
    tcpOnly: false,
    evidence: 'AETHER_PROTOCOL=gool, --gool-classic',
  );

  static final TransportMode mim = TransportMode(
    id: ProtocolId.mim,
    label: 'MIM',
    cliValue: 'mim',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.warp,
    tcpOnly: false,
    evidence: 'AETHER_PROTOCOL=mim; same --bind listener',
  );

  /// AETHER→TOR — exit IP is a Tor node ⇒ Zeptun uses --tor-bind (1820).
  static final TransportMode torChain = TransportMode(
    id: ProtocolId.torChain,
    label: 'AETHER → TOR',
    cliValue: 'AETHER_TOR=chain',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1820),
    exitKind: ExitKind.torExit,
    tcpOnly: true,
    evidence: 'cli.rs L584 (aether→warp→tor; second proxy on --tor-bind), L595',
  );

  static final TransportMode torReverse = TransportMode(
    id: ProtocolId.torReverse,
    label: 'TOR → AETHER',
    cliValue: 'AETHER_TOR=reverse',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.warp,
    tcpOnly: true,
    evidence: 'cli.rs L585; lib.rs L203-218 (h2 forced)',
  );

  static final TransportMode torOnly = TransportMode(
    id: ProtocolId.torOnly,
    label: 'TOR ONLY',
    cliValue: 'AETHER_TOR=only',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.torExit,
    tcpOnly: true,
    evidence: 'cli.rs L586 (no tunnel; --bind serves plain Tor)',
  );

  /// AETHER→PSIPHON — exit IP is Psiphon ⇒ Zeptun uses --psiphon-bind (1821).
  static final TransportMode psiphonChain = TransportMode(
    id: ProtocolId.psiphonChain,
    label: 'AETHER → PSIPHON',
    cliValue: 'AETHER_PSIPHON=chain',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1821),
    exitKind: ExitKind.psiphonExit,
    tcpOnly: true,
    evidence: 'cli.rs L598, L602 (--psiphon-bind=1821)',
  );

  static final TransportMode psiphonReverse = TransportMode(
    id: ProtocolId.psiphonReverse,
    label: 'PSIPHON → AETHER',
    cliValue: 'AETHER_PSIPHON=reverse',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.warp,
    tcpOnly: true,
    evidence: 'cli.rs L599; lib.rs L229-243 (TCP-only ⇒ h2 forced)',
  );

  static final TransportMode psiphonOnly = TransportMode(
    id: ProtocolId.psiphonOnly,
    label: 'PSIPHON ONLY',
    cliValue: 'AETHER_PSIPHON=only',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1819),
    exitKind: ExitKind.psiphonExit,
    tcpOnly: true,
    evidence: 'cli.rs L600 (no tunnel; --bind serves plain psiphon)',
  );

  /// PHASE-1 (firefox-vpn, private branch) — FIREFOX VPN ONLY: the
  /// dedicated Go engine (libfirefoxvpn.so) serving SOCKS5 CONNECT on
  /// 127.0.0.1:1822. Port 1822 was vetted against the evidence-locked
  /// map (1819 aether --bind, 1820 --tor-bind, 1821 --psiphon-bind) and
  /// the adapter asserts it free at runtime before every connect.
  /// `cliValue` documents that NO aether CLI exists for this mode — the
  /// aether core never starts; the child process is driven over its
  /// stdin/stdout contract (docs/FIREFOX_VPN_ENGINE.md).
  static final TransportMode firefoxOnly = TransportMode(
    id: ProtocolId.firefoxOnly,
    label: 'FIREFOX VPN',
    cliValue: '(no aether core — dedicated engine child process)',
    socksEndpoint: Uri(scheme: 'socks5', host: _host, port: 1822),
    exitKind: ExitKind.firefoxExit,
    tcpOnly: true,
    evidence: 'fxv cmd/libfirefoxvpn (engine contract; phase-1 pin)',
  );

  static final List<TransportMode> all = [
    masque,
    wireguard,
    gool,
    goolClassic,
    mim,
    torChain,
    torReverse,
    torOnly,
    psiphonChain,
    psiphonReverse,
    psiphonOnly,
    firefoxOnly,
  ];

  static TransportMode byId(ProtocolId id) => all.firstWhere((m) => m.id == id);
}

/// v4.19 (#5) — the SEED set of countries the Psiphon network has been
/// offering as its egress («در حالت تور و سایفون باید فقط پرچم کشورهایی رو
/// نشون بده که سایفون و تور ساپورت میکنن»).
///
/// Evidence status, honestly recorded:
///  * the core passes the pick through as `EgressRegion` in the
///    psiphon-tunnel-core config (psiphon.rs L650-652) and validates the
///    SYNTAX only (2 ASCII letters, psiphon.rs region());
///  * the LIVE set of offered regions is dynamic — the network announces it
///    at connect time via the `AvailableEgressRegions` notice
///    (psiphon.rs L716-718, notice.go L475-484); no static list exists in
///    the pinned sources;
///  * this table therefore mirrors the Psiphon network's standing egress
///    regions as the OFFLINE SEED ONLY. v4.28 adds the live capture: every
///    psiphon-family connect harvests the core's own
///    `[*] psiphon can leave from: …` line from the captured core log
///    (EgressLocations.parsePsiphonEgressRegions) and the store swaps this
///    seed for the network's real, current offer.
///  * Picking a region the network no longer offers fails the psiphon
///    connect HONESTLY (no server matches) — the core never fakes an exit.
const List<String> psiphonEgressRegions = <String>[
  'at', 'au', 'be', 'bg', 'ca', 'ch', 'cz', 'de', 'dk', 'ee', //
  'es', 'fi', 'fr', 'gb', 'hk', 'hr', 'hu', 'ie', 'il', 'in', //
  'it', 'jp', 'lt', 'lv', 'mk', 'my', 'nl', 'no', 'nz', 'pl', //
  'pt', 'ro', 'rs', 'se', 'sg', 'si', 'sk', 'ua', 'us', 'za',
];

/// v4.28 — the SEED set of countries where the Tor network currently has
/// RUNNING exit relays, recorded 2026-11-05 from the network's own metrics
/// API (Onionoo — the verified query in egress_locations.dart returned
/// 2686 running exit relays across exactly these 51 countries). At app
/// start `EgressLocations.refreshTorExits` replaces it with the live set
/// (24 h TTL, disk-cached; offline keeps this snapshot or the last cache).
///
/// The pinned core still has NO Tor exit-country pin (`AETHER_TOR_COUNTRY`
/// is the BridgeDB/moat request country for OBTAINING BRIDGES, not an exit
/// pin — CLI_REFERENCE env-table note, bridges.rs L410-448), so a tor-exit
/// pick stays a remembered display anchor; after connect the wheel locks
/// on the engine-reported real exit (owner device-test round 3: «در حالت
/// تور انتخاب لوکیشن باید فعال باشه»). The list below is what the wheel
/// OFFERS — the countries Tor can really leave from, not every flag.
const List<String> torExitCountrySnapshot = <String>[
  'ae', 'at', 'au', 'az', 'be', 'bg', 'ca', 'ch', 'cl', 'cr', //
  'cy', 'cz', 'de', 'dk', 'ee', 'es', 'fi', 'fr', 'gb', 'hk', //
  'hr', 'hu', 'id', 'il', 'is', 'it', 'jp', 'kr', 'kz', 'lt', //
  'lu', 'md', 'mx', 'my', 'nl', 'no', 'nz', 'pe', 'pl', 'pt', //
  'ro', 'rs', 'sc', 'se', 'sg', 'tr', 'tw', 'ua', 'us', 'vn', //
  'za',
];

/// v4.21 — the AUTO wheel entry (owner: «راستی برای سایفون و تور به انتخاب
/// خودکار هم باید بزاریم … این انتخاب خودکار قابلیت خود هسته هاست و لازم
/// نیست چیزی اضافه کنیم از قبل خودشون دارن»): 'auto' means NO pin flag is
/// passed and the core picks its own egress — the built-in capability the
/// owner named. The wheel renders it as the placeholder globe flag
/// (design/flags_png/auto.png — a stand-in until the owner's own artwork
/// lands) with the label «خودکار».
const String autoWheelCode = 'auto';

/// The per-protocol location-wheel policy (v4.19 #5, revised v4.21).
abstract final class LocationWheelPolicy {
  /// The sentinel wheel entry for the core's own auto selection.
  static const String autoCode = autoWheelCode;

  /// True while the wheel is a real, scrollable SELECTOR for this
  /// protocol — the whole psiphon + tor families (owner device-test
  /// round 3: «در حالت تور انتخاب لوکیشن باید فعال باشه، چرا پرچم ها
  /// نشون داده نمیشن؟»). Everything else keeps the plain display band
  /// (hidden until connected — the v4.15 #3 rule).
  static bool selectable(ProtocolId id) => id.isTor || id.isPsiphon;

  /// The allowed wheel entries for a family selector, AUTO FIRST; null =
  /// the whole flag manifest (plain modes / the post-connect display).
  /// v4.28: both REAL sets are live-replaceable —
  ///  * psiphon-exit modes → the psiphon set ([psiphonRegions]: the
  ///    core's own `AvailableEgressRegions` report once one has arrived,
  ///    else the standing seed [psiphonEgressRegions]);
  ///  * tor-exit modes → the Tor exit-country set ([torExits]: the live
  ///    Onionoo set / last cache, else the [torExitCountrySnapshot]) —
  ///    NOT the full flag manifest anymore (owner round 5: «لوکیشن های
  ///    واقعی، نه فیک»);
  ///  * the reverse modes exit through WARP and keep the full manifest
  ///    (+ auto, prepended by the wheel).
  static List<String>? allowedCodes(
    ProtocolId id, {
    List<String>? psiphonRegions,
    List<String>? torExits,
  }) => switch (id) {
        ProtocolId.psiphonOnly || ProtocolId.psiphonChain =>
          [autoCode, ...(psiphonRegions ?? psiphonEgressRegions)],
        ProtocolId.torChain ||
        ProtocolId.torOnly =>
          [autoCode, ...(torExits ?? torExitCountrySnapshot)],
        ProtocolId.psiphonReverse || ProtocolId.torReverse => null,
        _ => null,
      };

  /// True when this protocol's selector runs on the FULL manifest with the
  /// AUTO entry prepended by the wheel (v4.28: only the WARP-exit REVERSE
  /// modes — the psiphon-exit modes get their filtered list from
  /// [allowedCodes] and so do the tor-exit modes now, both already carrying
  /// the auto entry themselves).
  static bool autoEntry(ProtocolId id) =>
      id == ProtocolId.torReverse || id == ProtocolId.psiphonReverse;
}
