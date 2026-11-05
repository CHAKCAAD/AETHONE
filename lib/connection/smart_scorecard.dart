/// SMART AUTO scorecard (v4.32) — the engine-owned memory that orders the
/// plain-Aether candidate set for the SMART walk
/// (SMART_AUTO_SPEC.md §4: the minimum factor set).
///
/// This is ENGINE TRUTH, not a user preference: it persists under its own
/// `shared_preferences` keys exactly like the EgressLocations caches (saved
/// at record time, restored at adapter construction, never part of
/// SettingsPersistence.attach snapshots).
///
/// Per candidate (the five plain Aether profiles — SMART_AUTO_SPEC §2:
/// masque, wireguard, gool, gool-classic, mim; Tor/Psiphon are family
/// MODES, excluded from the auto-selectable set by §6.7):
///  * attempts / successes / consecutiveFailures
///    (§4.2 establishment success/failure; §4.5 failure STREAKS downgrade
///    a candidate's standing, not only successes upgrade it);
///  * an EWMA of the walk's end-to-end probe ping — the SOCKS5 CONNECT +
///    trace latency measured through the LIVE listener (§4.3: native
///    speed measurement through SOCKS5, no HTTP-proxy substitution);
///  * lastSuccessAt — a success older than the trust window stops
///    ordering the candidate first (networks change).
///
/// Ordering ([rank]):
///  1. candidates with a success inside the trust window, by
///     consecutiveFailures ASC, then EWMA ping ASC, then most-recent
///     success first;
///  2. never-attempted candidates, in the exploration order (the protocol
///     sheet's own default ladder);
///  3. everything else (only failures so far / only stale successes), by
///     consecutiveFailures ASC, then attempts ASC.
///
/// Parse-only + record-only: a malformed blob restores an EMPTY
/// scorecard (persistence must never block a connect), and the model
/// never fabricates measurements it was not handed.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_assets.dart';

/// The auto-selectable candidate set in exploration order (the protocol
/// sheet's own ladder: the core default MASQUE first, the v4.19 cold
/// default WireGuard second, then the nested profiles). Tor/Psiphon family
/// members are deliberately absent (SMART_AUTO_SPEC §6.1/§6.7 — they are
/// modes the user selects, never protocol candidates).
const List<ProtocolId> smartCandidates = [
  ProtocolId.masque,
  ProtocolId.wireguard,
  ProtocolId.gool,
  ProtocolId.mim,
  ProtocolId.goolClassic,
];

/// How long a recorded success keeps a candidate in the trusted tier.
const Duration smartTrustWindow = Duration(hours: 24);

/// The EWMA smoothing factor for the probe ping (a fresh sample carries
/// ~20 % of the next estimate — reactive without amnesia).
const double _pingAlpha = 0.2;

/// One candidate's standing.
class SmartProtocolScore {
  SmartProtocolScore({
    this.attempts = 0,
    this.successes = 0,
    this.consecutiveFailures = 0,
    this.ewmaPingMs,
    this.lastSuccessAt,
  });

  int attempts;
  int successes;
  int consecutiveFailures;

  /// EWMA of the walk probe's ping; null = never measured on this device.
  int? ewmaPingMs;

  /// Milliseconds-since-epoch of the last successful connect.
  int? lastSuccessAt;

  Map<String, dynamic> toJson() => {
        'attempts': attempts,
        'successes': successes,
        'consecutiveFailures': consecutiveFailures,
        if (ewmaPingMs != null) 'ewmaPingMs': ewmaPingMs,
        if (lastSuccessAt != null) 'lastSuccessAt': lastSuccessAt,
      };

  static SmartProtocolScore fromJson(dynamic raw) {
    if (raw is! Map) return SmartProtocolScore();
    final m = raw.cast<String, dynamic>();
    int? readInt(String key) =>
        m[key] is int && (m[key] as int) >= 0 ? m[key] as int : null;
    return SmartProtocolScore(
      attempts: readInt('attempts') ?? 0,
      successes: readInt('successes') ?? 0,
      consecutiveFailures: readInt('consecutiveFailures') ?? 0,
      ewmaPingMs: readInt('ewmaPingMs'),
      lastSuccessAt: readInt('lastSuccessAt'),
    );
  }
}

class SmartScorecard {
  SmartScorecard();

  final Map<ProtocolId, SmartProtocolScore> _scores = {};

  /// Read-only lookup (never creates an entry — ranking must not mutate
  /// the scorecard it reads).
  SmartProtocolScore scoreOf(ProtocolId id) =>
      _scores[id] ?? SmartProtocolScore();

  /// The candidates ordered best-first (see the library doc). Pure —
  /// records do not mutate the order mid-walk.
  List<ProtocolId> rank({DateTime? now}) {
    final at = now ?? DateTime.now();
    final windowStart = at.millisecondsSinceEpoch -
        smartTrustWindow.inMilliseconds;

    int tier(ProtocolId id) {
      final s = scoreOf(id);
      if (s.attempts == 0) return 1; // never tried — explore
      if (s.lastSuccessAt != null && s.lastSuccessAt! >= windowStart) {
        return 0; // trusted: a success inside the window
      }
      return 2; // only failures / stale successes
    }

    final ranked = [...smartCandidates]..sort((a, b) {
        final ta = tier(a);
        final tb = tier(b);
        if (ta != tb) return ta.compareTo(tb);
        final sa = scoreOf(a);
        final sb = scoreOf(b);
        if (ta == 1) {
          // Never-tried: keep the exploration order stable.
          return smartCandidates.indexOf(a) - smartCandidates.indexOf(b);
        }
        if (sa.consecutiveFailures != sb.consecutiveFailures) {
          return sa.consecutiveFailures.compareTo(sb.consecutiveFailures);
        }
        if (ta == 0) {
          final pa = sa.ewmaPingMs;
          final pb = sb.ewmaPingMs;
          if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
          if (pa != null && pb == null) return -1; // measured beats unknown
          if (pa == null && pb != null) return 1;
          // Same ping story: the most recent success first.
          final la = sa.lastSuccessAt ?? 0;
          final lb = sb.lastSuccessAt ?? 0;
          return lb.compareTo(la);
        }
        return sa.attempts.compareTo(sb.attempts); // least-tried first
      });
    return ranked;
  }

  /// Records one candidate attempt (§4.2/§4.5). [pingMs] is the walk's
  /// end-to-end probe latency on success (null on failure or when the
  /// probe carried no ping).
  void record(ProtocolId id, bool ok, int? pingMs, {DateTime? now}) {
    final s = _scores[id] ??= SmartProtocolScore();
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    s.attempts += 1;
    if (ok) {
      s.successes += 1;
      s.consecutiveFailures = 0;
      s.lastSuccessAt = at;
      if (pingMs != null && pingMs > 0) {
        s.ewmaPingMs = s.ewmaPingMs == null
            ? pingMs
            : (_pingAlpha * pingMs + (1 - _pingAlpha) * s.ewmaPingMs!)
                .round();
      }
    } else {
      s.consecutiveFailures += 1;
    }
  }

  /// Enum-ordered (stable across runs — [loadFrom] reads the same order,
  /// so encode/decode/encode is byte-identical).
  Map<String, dynamic> toJson() => {
        for (final id in ProtocolId.values)
          if (_scores.containsKey(id)) id.name: _scores[id]!.toJson(),
      };

  /// In-place merge from a persisted blob (keeps this instance live for
  /// an adapter already holding it). Malformed pieces are skipped.
  void loadFrom(dynamic raw) {
    if (raw is! Map) return;
    final m = raw.cast<String, dynamic>();
    for (final id in ProtocolId.values) {
      final piece = m[id.name];
      if (piece == null) continue;
      final parsed = SmartProtocolScore.fromJson(piece);
      if (parsed.attempts > 0 || parsed.successes > 0) {
        _scores[id] = parsed;
      }
    }
  }

  static SmartScorecard fromJson(dynamic raw) =>
      SmartScorecard()..loadFrom(raw);

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is SmartScorecard && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

// ---- disk cache (engine truth; the EgressLocations pattern) ----

const String _scorecardKey = 'aethone.smart.scorecard';

/// Restores the persisted scorecard (null = none / malformed — the caller
/// keeps a fresh one).
Future<SmartScorecard?> loadCachedScorecard() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scorecardKey);
    if (raw == null || raw.isEmpty) return null;
    final card = SmartScorecard.fromJson(jsonDecode(raw));
    return card == SmartScorecard() ? null : card;
  } catch (_) {
    return null;
  }
}

/// Saves the scorecard at record time. Fire-and-forget by design — a
/// failed write costs ordering freshness, never a connect.
Future<void> saveScorecard(SmartScorecard card) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scorecardKey, card.encode());
  } catch (_) {
    // cache-only
  }
}
