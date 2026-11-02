/// Transport-mode table — the evidence-locked endpoint map (phase-1 report
/// table 11, sourced from `aether_cli_flags.json` with direct code references
/// to aether/src/cli.rs at the frozen pin). This is the data behind the future
/// `ActiveTransportSession` (prompt §12-الحاقیه): Zeptun connects to the
/// endpoint of the SELECTED mode only — no fallback, no guessing.
library;

import '../core/app_assets.dart';

/// What leaves the tunnel (defines which listener Zeptun must use).
enum ExitKind { warp, torExit, psiphonExit }

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
  ];

  static TransportMode byId(ProtocolId id) =>
      all.firstWhere((m) => m.id == id);
}
