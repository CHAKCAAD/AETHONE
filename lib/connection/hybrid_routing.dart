/// v1.1.0 — Hybrid per-tunnel routing (docs/hybrid-routing.md).
///
/// A hybrid protocol runs TWO independent SOCKS5 listeners inside the one
/// Aether process (verified against aether/src/lib.rs + cli.rs at the pin):
///
/// | protocol          | default route (unchanged)      | second route        |
/// |-------------------|--------------------------------|---------------------|
/// | AETHER → PSIPHON  | WARP → Psiphon  (1821)         | WARP          (1819)|
/// | PSIPHON → AETHER  | Psiphon → WARP  (1819)         | Psiphon       (1821)|
/// | AETHER → TOR      | WARP → Tor      (1820)         | WARP          (1819)|
/// | TOR → AETHER      | Tor → WARP      (1819)         | Tor           (1820)|
///
/// Every route listed is a real, independently dialable listener; nothing
/// else is offered (a tunnel that only exists INSIDE another one is shown
/// with its real chain, e.g. «WARP → Psiphon», never as a bare «Psiphon»).
///
/// This file is the DATA layer only: the rule model, its persistence form,
/// input validation for the editor, and the policy document handed to the
/// native engine. Matching happens natively (HybridPolicy.kt, called by the
/// patched zeptun for every new flow) — Flutter never decides a route.
library;

import 'dart:convert';
import 'dart:io' show InternetAddress, InternetAddressType;

import '../core/app_assets.dart';

/// The kinds of rule, in engine priority order (app beats every
/// destination rule; exact beats wildcard; domain beats IP).
enum HybridRuleKind {
  app,
  domain,
  wildcard,
  cidr;

  static HybridRuleKind? fromName(String? n) => switch (n) {
        'app' => app,
        'domain' => domain,
        'wildcard' => wildcard,
        'cidr' => cidr,
        _ => null,
      };
}

class HybridRule {
  const HybridRule({
    required this.id,
    required this.kind,
    required this.value,
    required this.tunnel,
    this.enabled = true,
    this.label,
  });

  final String id;
  final HybridRuleKind kind;

  /// Package id (app), host name (domain), `*.suffix` (wildcard) or an IP /
  /// CIDR (cidr), in the canonical form [HybridRouting.canonical] gives.
  final String value;

  /// Tunnel id of the profile ([HybridTunnel.id]).
  final String tunnel;
  final bool enabled;

  /// App label shown in the list (apps only; display convenience).
  final String? label;

  HybridRule copyWith({String? tunnel, bool? enabled, String? value, HybridRuleKind? kind}) =>
      HybridRule(
        id: id,
        kind: kind ?? this.kind,
        value: value ?? this.value,
        tunnel: tunnel ?? this.tunnel,
        enabled: enabled ?? this.enabled,
        label: label,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'value': value,
        'tunnel': tunnel,
        'enabled': enabled,
        if (label != null) 'label': label,
      };

  static HybridRule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = HybridRuleKind.fromName(raw['kind'] as String?);
    final id = raw['id'];
    final value = raw['value'];
    final tunnel = raw['tunnel'];
    if (kind == null || id is! String || value is! String || tunnel is! String) {
      return null;
    }
    return HybridRule(
      id: id,
      kind: kind,
      value: value,
      tunnel: tunnel,
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      label: raw['label'] as String?,
    );
  }
}

/// One selectable route of a hybrid profile.
class HybridTunnel {
  const HybridTunnel({
    required this.id,
    required this.label,
    required this.port,
    required this.isDefault,
  });

  /// 'warp' | 'psiphon' | 'tor' — stable across profiles.
  final String id;

  /// The honest chain the traffic takes («WARP → Psiphon»).
  final String label;
  final int port;
  final bool isDefault;
}

/// Why an entered value cannot become a rule.
enum HybridInputError { empty, invalid, duplicate }

abstract final class HybridRouting {
  /// The hybrid protocols — the only ones that show the routing section.
  static bool isHybrid(ProtocolId id) => profileOf(id) != null;

  /// The routes of a hybrid protocol, default first; null for every
  /// single-tunnel protocol (plain WARP modes, -only modes, Lantern, AUTO).
  static List<HybridTunnel>? profileOf(ProtocolId id) => switch (id) {
        ProtocolId.psiphonChain => const [
            HybridTunnel(id: 'psiphon', label: 'WARP → Psiphon', port: 1821, isDefault: true),
            HybridTunnel(id: 'warp', label: 'WARP', port: 1819, isDefault: false),
          ],
        ProtocolId.psiphonReverse => const [
            HybridTunnel(id: 'warp', label: 'Psiphon → WARP', port: 1819, isDefault: true),
            HybridTunnel(id: 'psiphon', label: 'Psiphon', port: 1821, isDefault: false),
          ],
        ProtocolId.torChain => const [
            HybridTunnel(id: 'tor', label: 'WARP → Tor', port: 1820, isDefault: true),
            HybridTunnel(id: 'warp', label: 'WARP', port: 1819, isDefault: false),
          ],
        ProtocolId.torReverse => const [
            HybridTunnel(id: 'warp', label: 'Tor → WARP', port: 1819, isDefault: true),
            HybridTunnel(id: 'tor', label: 'Tor', port: 1820, isDefault: false),
          ],
        _ => null,
      };

  static String? tunnelLabel(ProtocolId profile, String tunnel) {
    for (final t in profileOf(profile) ?? const <HybridTunnel>[]) {
      if (t.id == tunnel) return t.label;
    }
    return null;
  }

  static final _package = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');
  // Unicode letters are allowed in a label: the native side converts IDN to
  // punycode (java.net.IDN) — the form the fake-IP DNS sees.
  static final _label = RegExp(r'^[\p{L}\p{N}]([\p{L}\p{N}-]{0,61}[\p{L}\p{N}])?$', unicode: true);

  static String? _name(String input) {
    var s = input.trim().toLowerCase();
    while (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty || s.length > 253) return null;
    final labels = s.split('.');
    if (labels.length < 2) return null;
    if (labels.any((l) => !_label.hasMatch(l))) return null;
    return s;
  }

  /// The canonical stored value, or null when [input] is not valid for the
  /// kind. Matches HybridPolicy.canonical on the native side (which also
  /// applies IDNA). `example.com` (exact) matches ONLY example.com;
  /// `*.example.com` matches its subdomains only, never the apex.
  static String? canonical(HybridRuleKind kind, String input) {
    final v = input.trim();
    switch (kind) {
      case HybridRuleKind.app:
        return _package.hasMatch(v) ? v : null;
      case HybridRuleKind.domain:
        if (v.startsWith('*.')) return null;
        return _name(v);
      case HybridRuleKind.wildcard:
        if (!v.startsWith('*.')) return null;
        final n = _name(v.substring(2));
        return n == null ? null : '*.$n';
      case HybridRuleKind.cidr:
        return _cidr(v);
    }
  }

  /// A domain field accepts both `example.com` and `*.example.com`.
  static HybridRuleKind domainKindOf(String input) =>
      input.trim().startsWith('*.') ? HybridRuleKind.wildcard : HybridRuleKind.domain;

  static String? _cidr(String v) {
    final slash = v.indexOf('/');
    final host = slash < 0 ? v : v.substring(0, slash);
    final addr = InternetAddress.tryParse(host);
    if (addr == null) return null;
    final bits = addr.type == InternetAddressType.IPv4 ? 32 : 128;
    final prefix = slash < 0 ? bits : int.tryParse(v.substring(slash + 1));
    if (prefix == null || prefix < 0 || prefix > bits) return null;
    final raw = addr.rawAddress;
    for (var b = prefix; b < bits; b++) {
      if ((raw[b ~/ 8] >> (7 - b % 8)) & 1 == 1) return null; // host bits set
    }
    return '${addr.address}/$prefix';
  }

  /// Validates a new or edited value against the profile's existing rules
  /// ([editingId] = the rule being edited, excluded from the duplicate
  /// check). Returns the error, or null when it may be saved.
  static HybridInputError? validate(
    List<HybridRule> existing,
    HybridRuleKind kind,
    String input, {
    String? editingId,
  }) {
    if (input.trim().isEmpty) return HybridInputError.empty;
    final c = canonical(kind, input);
    if (c == null) return HybridInputError.invalid;
    final dup = existing.any((r) => r.id != editingId && r.kind == kind && r.value == c);
    return dup ? HybridInputError.duplicate : null;
  }

  /// The rules that a new/edited rule overlaps with on another tunnel
  /// (shown to the user as a conflict notice; the more specific rule wins
  /// per the documented priority — nothing is silently merged).
  static List<HybridRule> overlaps(List<HybridRule> rules, HybridRule rule) {
    final out = <HybridRule>[];
    for (final r in rules) {
      if (r.id == rule.id || !r.enabled || r.tunnel == rule.tunnel) continue;
      if (_overlap(r, rule)) out.add(r);
    }
    return out;
  }

  static bool _overlap(HybridRule a, HybridRule b) {
    bool covers(String wildcard, String name) {
      final suffix = wildcard.substring(2);
      return name.endsWith('.$suffix') && name.length > suffix.length + 1;
    }

    final ka = a.kind, kb = b.kind;
    if (ka == HybridRuleKind.wildcard && kb == HybridRuleKind.domain) return covers(a.value, b.value);
    if (kb == HybridRuleKind.wildcard && ka == HybridRuleKind.domain) return covers(b.value, a.value);
    if (ka == HybridRuleKind.wildcard && kb == HybridRuleKind.wildcard) {
      return covers(a.value, b.value.substring(2)) || covers(b.value, a.value.substring(2));
    }
    if (ka == HybridRuleKind.cidr && kb == HybridRuleKind.cidr) {
      return _cidrOverlap(a.value, b.value);
    }
    return false;
  }

  static bool _cidrOverlap(String a, String b) {
    (List<int>, int)? parse(String v) {
      final i = v.indexOf('/');
      final addr = InternetAddress.tryParse(v.substring(0, i));
      if (addr == null) return null;
      return (addr.rawAddress, int.parse(v.substring(i + 1)));
    }

    final pa = parse(a), pb = parse(b);
    if (pa == null || pb == null || pa.$1.length != pb.$1.length) return false;
    final p = pa.$2 < pb.$2 ? pa.$2 : pb.$2;
    for (var bit = 0; bit < p; bit++) {
      final x = (pa.$1[bit ~/ 8] >> (7 - bit % 8)) & 1;
      final y = (pb.$1[bit ~/ 8] >> (7 - bit % 8)) & 1;
      if (x != y) return false;
    }
    return true;
  }

  /// Rules whose tunnel the profile does not have (e.g. carried over from
  /// an older build) — shown as errors; the engine REFUSES their traffic
  /// rather than re-routing it.
  static List<HybridRule> invalidRules(ProtocolId profile, List<HybridRule> rules) {
    final ids = {for (final t in profileOf(profile) ?? const <HybridTunnel>[]) t.id};
    return [for (final r in rules) if (!ids.contains(r.tunnel)) r];
  }

  /// The policy document for the native engine (AethoneVpnService extra
  /// `hybridRouting` / channel `hybridRoutingUpdate`), or null for a
  /// single-tunnel protocol. Sent for EVERY hybrid tunnel — with no rules
  /// every flow takes the default route exactly as before, and rules can
  /// then be added live without restarting the TUN.
  static String? policyJson(ProtocolId profile, List<HybridRule> rules, {int portOffset = 0}) {
    final tunnels = profileOf(profile);
    if (tunnels == null) return null;
    return jsonEncode({
      'profile': profile.name,
      'tunnels': [
        for (final t in tunnels)
          {'id': t.id, 'endpoint': '127.0.0.1:${t.port + portOffset}'},
      ],
      'rules': [for (final r in rules) r.toJson()],
    });
  }

  /// Persistence form: profile name → rule list.
  static String encodeAll(Map<String, List<HybridRule>> all) => jsonEncode({
        for (final e in all.entries) e.key: [for (final r in e.value) r.toJson()],
      });

  static Map<String, List<HybridRule>> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final o = jsonDecode(raw);
      if (o is! Map) return {};
      final out = <String, List<HybridRule>>{};
      for (final e in o.entries) {
        final key = e.key;
        final list = e.value;
        if (key is! String || list is! List) continue;
        final rules = [for (final r in list) HybridRule.fromJson(r)].whereType<HybridRule>().toList();
        out[key] = rules;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static int _seq = 0;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_seq++).toRadixString(36)}';
}
