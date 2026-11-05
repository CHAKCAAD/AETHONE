/// Aether core settings — the fine-grained layer the settings sub-pages
/// expose (owner round: «تنظیمات جزیی … بخش فرگمنت و tls هسته aether خیلی
/// مهمه … چند تا پروفایل فرگمنت معمول توی ایران که جواب میده رو هم برای
/// انتخاب بزار»).
///
/// Every field maps to a REAL CLI flag / environment variable of the pinned
/// Aether commit (`docs/CLI_REFERENCE.md`, frozen pin) and is injected by
/// [AetherArguments.build] ONLY when it differs from the core's built-in
/// default — the arg list stays as quiet as the evidence table.
///
/// The model is a plain mutable object owned by [ConnectionStore]; every
/// mutation goes through `store.updateCore(...)` so the store notifies and
/// the persistence layer saves. Serialization is one JSON blob under a
/// single prefs key — forward-compatible (unknown keys ignored, missing
/// keys keep the built-in defaults).
///
/// FRAGMENT PRESETS — the Iran-proven profiles the owner asked for. The
/// core's own USAGE blesses the feature for this exact market:
///   `--fragment … it helps where a firewall resets a whole ClientHello
///    whose SNI ends in cloudflareclient.com, as Iran's does` (cli.rs L133).
///   * standard   — `--fragment` alone; the core's own defaults apply
///                  (size 8-16 bytes, delay 2-10 ms).
///   * balanced   — 40-100 bytes / 10-20 ms; the Hiddify-family default the
///                  Persian community runs on mid-filtered networks.
///   * aggressive — 1-3 bytes / 1-3 ms; the smallest shards, for the
///                  strictest DPI (Irancell-style whole-SNI resets).
///   * custom     — the expert fields below, free-form.
library;

import 'dart:convert';

/// TLS-ClientHello fragmentation preset (owner: the Iran profiles above).
enum FragmentPreset { off, standard, balanced, aggressive, custom }

/// Endpoint-scan obfuscation profile (`--noize`); `defaultValue` keeps the
/// core's per-protocol choice (firewall for MASQUE, balanced for WG/GOOL).
enum NoizeProfile {
  defaultValue,
  off,
  light,
  firewall,
  balanced,
  gfw,
  aggressive,
}

/// Resource profile (`--perf`); `auto` = the core's own cpu/ram detection.
enum PerfProfile { auto, low, medium, high }

/// Core log verbosity (`--log-level`; the app default stays `info`, the
/// value every previous build shipped).
enum CoreLogLevel { info, debug, trace }

/// Psiphon fronting shape (`--psiphon-mode`).
enum PsiphonFronting { auto, cdn, direct }

/// Tor bridge policy (`--tor-bridges auto` / `--no-tor-bridges` / the
/// manual lines, `--tor-bridge`-per-line — owner round 7: «وارد کردن دستی
/// پل های تور»). `custom` feeds [CoreSettings.torBridgeLines] into
/// `AETHER_TOR_BRIDGES` verbatim (tor.rs splits on `;`/newline →
/// `Bridges::Manual`).
enum TorBridgePolicy { auto, off, custom }

/// v4.31 — the WARP-leg protocol under a tor/psiphon FAMILY mode (owner
/// round 7: «انتخاب پروتکل هسته ایتر برای حالت های ترکیبی اور وارپ»;
/// the v4.21 decree deferred this exact option). The default keeps the
/// v4.19 fixed leg: WireGuard. The adapter maps it through
/// `protocolArgs`, which still forces MASQUE for the UDP-needing legs on
/// the TCP-only reverse modes (the core's own refusal, lib.rs L203-244).
///
/// v4.31c — the leg is PER FAMILY now (owner round 8: «قسمت پایه حالت های
/// ترکیبی باید توی زیرمجموعه تنطیمات تور و سایفون قرار بگیره»): the
/// tor family's combined modes and the psiphon family's each pick their
/// own base on their own settings page. The old single-field
/// `aetherLegProtocol` is migrated into BOTH on load (see [fromJson]).
enum AetherLegProtocol { wireguard, masque, gool, goolClassic, mim }

/// v4.31 — the IP version the core dials with (`-4` default / `-6` /
/// `--dual`, CLI_REFERENCE #11-13). Some Iranian mobile carriers carry
/// broken IPv6 — an explicit v4 pin is a real fix there.
enum IpVersion { v4, v6, dual }

/// v4.31 — Encrypted Client Hello on the MASQUE handshakes and the WARP
/// API calls (`--ech auto|base64`, cli.rs L154-167): the SNI travels
/// encrypted, the direct anti-SNI-blocking answer. `auto` looks the key
/// up over DoH (`--ech-dns` resolver, default udp://1.1.1.1), `manual`
/// takes a base64 key verbatim; without a usable key the handshake
/// neither leaks the name nor proceeds — honest.
enum EchMode { off, auto, manual }

/// Tor log verbosity — environment-only in the pinned core
/// (`AETHER_TOR_LOG`, no CLI flag) → injected as a process env var by the
/// adapter, not an arg.
enum TorLogLevel { info, debug, trace }

/// Routing-mode choice for the routing page («منطقهٔ مسیریابی») — the
/// store's legacy `routingRegion` field stays the source of truth; this
/// enum is only the UI vocabulary.
enum RoutingArea { iran, turkmenistan, russia, china, none }

/// The Aether core fine-grained settings. Defaults == the core's defaults
/// (a fresh object passes NOTHING the core would not do on its own).
class CoreSettings {
  CoreSettings({
    this.fragmentPreset = FragmentPreset.off,
    this.fragmentSize = '40-100',
    this.fragmentDelay = '10-20',
    this.tlsCustom = false,
    this.disableGrease = false,
    this.greaseSigalgs = false,
    this.echGrease = false,
    this.sessionTicket = true,
    this.ocsp = true,
    this.sct = true,
    this.extPermutation = true,
    this.tlsVerify = false,
    this.tlsGroups = '',
    this.keyShares = '',
    this.ciphers12 = '',
    this.ciphers13 = '',
    this.masqueSni = '',
    this.h2Transport = false,
    this.quicV2 = true,
    this.dns = '1.1.1.1,1.0.0.1',
    this.noize = NoizeProfile.defaultValue,
    this.perf = PerfProfile.auto,
    this.logLevel = CoreLogLevel.info,
    this.keepalive = 5,
    this.psiphonFronting = PsiphonFronting.auto,
    this.cdnSni = '',
    this.cdnIps = '',
    this.cdnSets = '',
    this.psiphonReadySecs = 180,
    this.psiphonServerEntries = '',
    this.torBridges = TorBridgePolicy.auto,
    this.torBridgeLines = '',
    this.torDirectSecs = 75,
    this.torBridgeSecs = 360,
    this.torLog = TorLogLevel.info,
    this.torLegProtocol = AetherLegProtocol.wireguard,
    this.psiphonLegProtocol = AetherLegProtocol.wireguard,
    this.ipVersion = IpVersion.v4,
    this.upstreamProxy = '',
    this.echMode = EchMode.off,
    this.echKey = '',
    this.echDns = '',
    this.echDomain = '',
    this.routeBlock = '',
    this.routeDirect = '',
    this.expertRevealed = false,
  });

  // ---- TLS ClientHello fragmentation (the owner's headline section) ----
  FragmentPreset fragmentPreset;

  /// Custom-mode shard size, `n` or `a-b` bytes (cli.rs `--fragment-size`).
  String fragmentSize;

  /// Custom-mode inter-shard delay, `n` or `a-b` ms (`--fragment-delay`).
  String fragmentDelay;

  // ---- TLS fingerprint (custom profile only; the standard profile is
  // the untouched Chrome-mimicking default) ----
  bool tlsCustom;
  bool disableGrease; // true ⇒ `--disable-grease`
  bool greaseSigalgs; // true ⇒ `--enable-grease-sigalgs`
  bool echGrease; // true ⇒ `--enable-ech-grease`
  bool sessionTicket; // false ⇒ `--disable-session-ticket`
  bool ocsp; // false ⇒ `--disable-ocsp-stapling`
  bool sct; // false ⇒ `--disable-sct`
  bool extPermutation; // false ⇒ `--disable-extension-permutation`
  bool tlsVerify; // true ⇒ `--tls-verify` (core default: off w/o --team)
  String tlsGroups; // non-empty ⇒ `--tls-groups`
  String keyShares; // non-empty ⇒ `--tls-key-shares`
  String ciphers12; // non-empty ⇒ `--tls-ciphers` (TLS 1.2 suites)
  String ciphers13; // non-empty ⇒ `--tls13-ciphers` (TLS 1.3 suites)
  String masqueSni; // non-empty ⇒ `--masque-sni`

  // ---- transport ----
  bool h2Transport; // true ⇒ `--h2` (HTTP/2 over TCP); false = H3/QUIC
  bool quicV2; // false ⇒ `--no-quic-v2`
  String dns; // ≠ default ⇒ `--dns`

  // ---- engine-wide ----
  NoizeProfile noize; // ≠ default ⇒ `--noize`
  PerfProfile perf; // ≠ auto ⇒ `--perf`
  CoreLogLevel logLevel; // ≠ info ⇒ `--log-level`
  int keepalive; // ≠ 5 ⇒ `--keepalive` (WireGuard leg)

  // ---- psiphon family ----
  PsiphonFronting psiphonFronting; // ≠ auto ⇒ `--psiphon-mode`
  String cdnSni; // non-empty ⇒ `--psiphon-cdn-sni`
  String cdnIps; // non-empty ⇒ `--psiphon-cdn-ips`

  /// v4.31 — `--psiphon-cdn-sets` (#91): which of the built-in fronting
  /// edge lists to use (e.g. `psiphon-akamai,vercel`); empty = all of
  /// them (the core's own default).
  String cdnSets;

  /// v4.31 — `AETHER_PSIPHON_READY_SECS` (env-only, default 180): how long
  /// the core waits for psiphon to tunnel. The adapter also widens its
  /// own walk budget past this so a slower psiphon is not failed by the
  /// app before the core itself gives up.
  int psiphonReadySecs;

  /// v4.31 — `--psiphon-server-entries` (#94): pasted psiphon server
  /// entries (the JSON blob the official clients export); empty = the
  /// built-in discovery.
  String psiphonServerEntries;

  // ---- tor family ----
  TorBridgePolicy torBridges; // off ⇒ `--no-tor-bridges`

  /// v4.31 — the MANUAL bridge lines (one per line, `obfs4 …` /
  /// `webtunnel …`); joined with `;` into `AETHER_TOR_BRIDGES` when
  /// [torBridges] == custom — exactly what repeated `--tor-bridge` args
  /// produce (cli.rs append(), tor.rs splits on `;`/newline).
  String torBridgeLines;

  /// v4.31 — `AETHER_TOR_DIRECT_SECS` (env-only, default 75): how long tor
  /// tries the plain direct path before bridges.
  int torDirectSecs;

  /// v4.31 — `AETHER_TOR_BRIDGE_SECS` (env-only, default 360): the longest
  /// any ONE bridge may take.
  int torBridgeSecs;

  TorLogLevel torLog; // ≠ info ⇒ env `AETHER_TOR_LOG` (env-only in the pin)

  // ---- v4.31: the family-mode WARP legs + the dial layer ----

  /// v4.31c — the Aether protocol under the TOR family's combined modes
  /// (chain + reverse; the owner's deferred «انتخاب پروتکل هسته ایتر»
  /// option, per family since round 8). Default = the v4.19 fixed
  /// WireGuard leg.
  AetherLegProtocol torLegProtocol;

  /// v4.31c — the Aether protocol under the PSIPHON family's combined
  /// modes. Default = the v4.19 fixed WireGuard leg.
  AetherLegProtocol psiphonLegProtocol;

  /// The IP version of the dial (`-4`/`-6`/`--dual`); default = the
  /// core's own v4.
  IpVersion ipVersion;

  /// `--upstream` (#3, e.g. `socks5://host:port`): dial THROUGH another
  /// proxy. Only folded for PLAIN Aether modes — the reverse family modes
  /// own this variable internally for their carrier (lib.rs L203-244) and
  /// a user value there would fight the chain itself. Empty = off.
  String upstreamProxy;

  // ---- v4.31: ECH (encrypted SNI) ----
  EchMode echMode;

  /// base64 ECH key (`--ech <base64>`; only in [EchMode.manual]).
  String echKey;

  /// The DoH resolver `--ech auto` asks for the key (`--ech-dns`, e.g.
  /// `https://1.1.1.1/dns-query` or `udp://1.1.1.1`); empty = the core
  /// default (udp://1.1.1.1).
  String echDns;

  /// The domain whose key `--ech auto` takes (`--ech-domain`, default
  /// cloudflare-ech.com); empty = the core default.
  String echDomain;

  // ---- routing (expert) ----
  String routeBlock; // non-empty ⇒ `--route-block` (comma/newline list)
  String routeDirect; // non-empty ⇒ `--route-direct`

  /// v4.22 — UI-only: the core page's expert toggle (reveals the TLS +
  /// engine panels). Persisted with the rest so the page reopens the way
  /// the user left it; NEVER read by the engine layer.
  bool expertRevealed;

  /// The effective shard size/delay for the CURRENT preset (custom fields
  /// only matter in custom mode) — what the UI preview and the adapter
  /// both read, so they can never disagree.
  ({String size, String delay}) get effectiveFragment {
    switch (fragmentPreset) {
      case FragmentPreset.off:
        return (size: '', delay: '');
      case FragmentPreset.standard:
        return (size: '', delay: ''); // bare --fragment: core defaults
      case FragmentPreset.balanced:
        return (size: '40-100', delay: '10-20');
      case FragmentPreset.aggressive:
        return (size: '1-3', delay: '1-3');
      case FragmentPreset.custom:
        return (size: fragmentSize.trim(), delay: fragmentDelay.trim());
    }
  }

  // ---- serialization (one JSON blob; unknown/missing keys fall back) ----

  Map<String, dynamic> toJson() => {
        'v': 1,
        'fragmentPreset': fragmentPreset.name,
        'fragmentSize': fragmentSize,
        'fragmentDelay': fragmentDelay,
        'tlsCustom': tlsCustom,
        'disableGrease': disableGrease,
        'greaseSigalgs': greaseSigalgs,
        'echGrease': echGrease,
        'sessionTicket': sessionTicket,
        'ocsp': ocsp,
        'sct': sct,
        'extPermutation': extPermutation,
        'tlsVerify': tlsVerify,
        'tlsGroups': tlsGroups,
        'keyShares': keyShares,
        'ciphers12': ciphers12,
        'ciphers13': ciphers13,
        'masqueSni': masqueSni,
        'h2Transport': h2Transport,
        'quicV2': quicV2,
        'dns': dns,
        'noize': noize.name,
        'perf': perf.name,
        'logLevel': logLevel.name,
        'keepalive': keepalive,
        'psiphonFronting': psiphonFronting.name,
        'cdnSni': cdnSni,
        'cdnIps': cdnIps,
        'cdnSets': cdnSets,
        'psiphonReadySecs': psiphonReadySecs,
        'psiphonServerEntries': psiphonServerEntries,
        'torBridges': torBridges.name,
        'torBridgeLines': torBridgeLines,
        'torDirectSecs': torDirectSecs,
        'torBridgeSecs': torBridgeSecs,
        'torLog': torLog.name,
        'torLegProtocol': torLegProtocol.name,
        'psiphonLegProtocol': psiphonLegProtocol.name,
        'ipVersion': ipVersion.name,
        'upstreamProxy': upstreamProxy,
        'echMode': echMode.name,
        'echKey': echKey,
        'echDns': echDns,
        'echDomain': echDomain,
        'routeBlock': routeBlock,
        'routeDirect': routeDirect,
        'expertRevealed': expertRevealed,
      };

  /// Parses a persisted blob; a malformed/old blob returns the built-in
  /// defaults (persistence must never crash the startup).
  static CoreSettings fromJson(dynamic raw) {
    if (raw is! Map) return CoreSettings();
    final m = raw.cast<String, dynamic>();
    if (m['v'] != 1) return CoreSettings();
    final s = CoreSettings();
    T? pickEnum<T extends Enum>(Iterable<T> values, Object? v) {
      if (v is! String) return null;
      for (final t in values) {
        if (t.name == v) return t;
      }
      return null;
    }

    s.fragmentPreset =
        pickEnum(FragmentPreset.values, m['fragmentPreset']) ?? s.fragmentPreset;
    if (m['fragmentSize'] is String) s.fragmentSize = m['fragmentSize'];
    if (m['fragmentDelay'] is String) s.fragmentDelay = m['fragmentDelay'];
    if (m['tlsCustom'] is bool) s.tlsCustom = m['tlsCustom'];
    if (m['disableGrease'] is bool) s.disableGrease = m['disableGrease'];
    if (m['greaseSigalgs'] is bool) s.greaseSigalgs = m['greaseSigalgs'];
    if (m['echGrease'] is bool) s.echGrease = m['echGrease'];
    if (m['sessionTicket'] is bool) s.sessionTicket = m['sessionTicket'];
    if (m['ocsp'] is bool) s.ocsp = m['ocsp'];
    if (m['sct'] is bool) s.sct = m['sct'];
    if (m['extPermutation'] is bool) s.extPermutation = m['extPermutation'];
    if (m['tlsVerify'] is bool) s.tlsVerify = m['tlsVerify'];
    if (m['tlsGroups'] is String) s.tlsGroups = m['tlsGroups'];
    if (m['keyShares'] is String) s.keyShares = m['keyShares'];
    if (m['ciphers12'] is String) s.ciphers12 = m['ciphers12'];
    if (m['ciphers13'] is String) s.ciphers13 = m['ciphers13'];
    if (m['masqueSni'] is String) s.masqueSni = m['masqueSni'];
    if (m['h2Transport'] is bool) s.h2Transport = m['h2Transport'];
    if (m['quicV2'] is bool) s.quicV2 = m['quicV2'];
    if (m['dns'] is String) s.dns = m['dns'];
    s.noize = pickEnum(NoizeProfile.values, m['noize']) ?? s.noize;
    s.perf = pickEnum(PerfProfile.values, m['perf']) ?? s.perf;
    s.logLevel = pickEnum(CoreLogLevel.values, m['logLevel']) ?? s.logLevel;
    if (m['keepalive'] is int && (m['keepalive'] as int) > 0) {
      s.keepalive = m['keepalive'];
    }
    s.psiphonFronting =
        pickEnum(PsiphonFronting.values, m['psiphonFronting']) ?? s.psiphonFronting;
    if (m['cdnSni'] is String) s.cdnSni = m['cdnSni'];
    if (m['cdnIps'] is String) s.cdnIps = m['cdnIps'];
    if (m['cdnSets'] is String) s.cdnSets = m['cdnSets'];
    if (m['psiphonReadySecs'] is int && (m['psiphonReadySecs'] as int) > 0) {
      s.psiphonReadySecs = m['psiphonReadySecs'];
    }
    if (m['psiphonServerEntries'] is String) {
      s.psiphonServerEntries = m['psiphonServerEntries'];
    }
    s.torBridges = pickEnum(TorBridgePolicy.values, m['torBridges']) ?? s.torBridges;
    if (m['torBridgeLines'] is String) s.torBridgeLines = m['torBridgeLines'];
    if (m['torDirectSecs'] is int && (m['torDirectSecs'] as int) > 0) {
      s.torDirectSecs = m['torDirectSecs'];
    }
    if (m['torBridgeSecs'] is int && (m['torBridgeSecs'] as int) > 0) {
      s.torBridgeSecs = m['torBridgeSecs'];
    }
    s.torLog = pickEnum(TorLogLevel.values, m['torLog']) ?? s.torLog;
    // v4.31c — the per-family legs, with the v4.31 single-field migration:
    // an old blob's aetherLegProtocol seeds BOTH families (the value the
    // user picked once applies to each family's own page from now on).
    final legacyLeg =
        pickEnum(AetherLegProtocol.values, m['aetherLegProtocol']);
    s.torLegProtocol =
        pickEnum(AetherLegProtocol.values, m['torLegProtocol']) ??
        legacyLeg ??
        s.torLegProtocol;
    s.psiphonLegProtocol =
        pickEnum(AetherLegProtocol.values, m['psiphonLegProtocol']) ??
        legacyLeg ??
        s.psiphonLegProtocol;
    s.ipVersion = pickEnum(IpVersion.values, m['ipVersion']) ?? s.ipVersion;
    if (m['upstreamProxy'] is String) s.upstreamProxy = m['upstreamProxy'];
    s.echMode = pickEnum(EchMode.values, m['echMode']) ?? s.echMode;
    if (m['echKey'] is String) s.echKey = m['echKey'];
    if (m['echDns'] is String) s.echDns = m['echDns'];
    if (m['echDomain'] is String) s.echDomain = m['echDomain'];
    if (m['routeBlock'] is String) s.routeBlock = m['routeBlock'];
    if (m['routeDirect'] is String) s.routeDirect = m['routeDirect'];
    if (m['expertRevealed'] is bool) s.expertRevealed = m['expertRevealed'];
    return s;
  }

  /// The exact prefs payload (a JSON string under one key).
  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) {
    if (other is! CoreSettings) return false;
    return other.encode() == encode();
  }

  @override
  int get hashCode => encode().hashCode;
}
