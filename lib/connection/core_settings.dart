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

/// Tor bridge policy (`--tor-bridges auto` / `--no-tor-bridges`).
enum TorBridgePolicy { auto, off }

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
    this.torBridges = TorBridgePolicy.auto,
    this.torLog = TorLogLevel.info,
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

  // ---- tor family ----
  TorBridgePolicy torBridges; // off ⇒ `--no-tor-bridges`
  TorLogLevel torLog; // ≠ info ⇒ env `AETHER_TOR_LOG` (env-only in the pin)

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
        'torBridges': torBridges.name,
        'torLog': torLog.name,
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
    s.torBridges = pickEnum(TorBridgePolicy.values, m['torBridges']) ?? s.torBridges;
    s.torLog = pickEnum(TorLogLevel.values, m['torLog']) ?? s.torLog;
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
