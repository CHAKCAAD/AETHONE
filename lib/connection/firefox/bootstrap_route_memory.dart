/// STAGE 4 of the Guardian bootstrap mission
/// (docs/performance/FIREFOX_GUARDIAN_PSIPHON_BOOTSTRAP_PROGRESS.md) —
/// the AETHONE Bootstrap Route Memory: which bootstrap route has
/// actually WORKED, per network context, so the next connection can
/// take the Fast Path instead of re-scanning every method.
///
/// This is level TWO of the mission's two learning levels (§7.1) and
/// deliberately does NOT replace psiphon's own internal adaptive
/// engine (level one — its learned servers/tactics live in the
/// persistent `$filesDir/aether/psiphon-bootstrap` data directory and
/// are never wiped by this layer). The two are complementary: this
/// memory only picks WHICH route to try first (psiphon standalone vs
/// the existing AETHER → PSIPHON chain); psiphon itself still finds
/// its servers and protocols.
///
/// What may be stored (mission §7.1, closed list):
///  * the route kind that last fully succeeded (direct / psiphon
///    standalone / the verified chain combination);
///  * a NON-IDENTIFYING network context bucket the result was earned
///    in (see [GuardianNetworkContextProvider] — coarse categories
///    only; the production default is a single bucket);
///  * last-success time and TTL expiry;
///  * per-route success/failure counters, cooldown-until, and the
///    last failure's classification (start vs authorization);
///  * bootstrap-ready and authorization durations, recorded SEPARATELY;
///  * a schema version.
///
/// What is FORBIDDEN and has no field in the schema (structurally
/// impossible to store by accident — asserted by a test):
///  * tokens, proxy passes, sessions, refresh tokens, request bodies;
///  * raw SSID / BSSID;
///  * raw public or private IP addresses;
///  * anything identifying the network in logs.
///
/// Durability (mission §7.1): the memory survives app restarts (a
/// plain JSON file), is written ATOMICALLY (temp file + rename, so a
/// crash mid-write never corrupts the previous content), and a
/// missing/corrupt/unreadable file degrades to an EMPTY memory — it
/// can never crash the app and never blocks the Direct path
/// (mission scenario H).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Schema version of the persisted memory document.
const int kGuardianRouteMemoryVersion = 1;

/// The route kinds the memory can record (mission §7.1: «نوع مسیر
/// موفق (Direct، Psiphon Standalone، یا Combination تأییدشده)»).
enum GuardianBootstrapRouteKind {
  /// Guardian answered the DIRECT attempt — no bootstrap needed.
  direct,

  /// Stage 2 — `--psiphon-only`.
  psiphonOnly,

  /// Stage 3 — the project's EXISTING `AETHER → PSIPHON` combination.
  aetherPsiphonChain;

  String get persistedName => name;

  static GuardianBootstrapRouteKind? fromPersisted(String? value) =>
      GuardianBootstrapRouteKind.values
          .where((kind) => kind.name == value)
          .firstOrNull;
}

/// The default discovery order for routes with NO history: standalone
/// first, then the chain (the mission's §4-2 ladder — the cheaper,
/// single-engine route is tried before the heavier combination).
const List<GuardianBootstrapRouteKind> kDefaultDiscoveryOrder = [
  GuardianBootstrapRouteKind.psiphonOnly,
  GuardianBootstrapRouteKind.aetherPsiphonChain,
];

/// Default validity of a learned route (mission §7.1: «برای رکوردهای
/// مسیر TTL مشخص تعیین کن» — a policy constant, deliberately
/// conservative; 24 h covers a working day and forces re-verification
/// of stale evidence). Injectable for tests and owner tuning.
const Duration kDefaultRouteTtl = Duration(hours: 24);

/// Default cooldown after a route FAILURES before it may be tried
/// again by discovery (mission: «شکست‌های متوالی باید اولویت مسیر را
/// کاهش دهند و می‌توانند Cooldown ایجاد کنند»). A short, bounded
/// penalty — not a blacklist.
const Duration kDefaultRouteCooldown = Duration(minutes: 10);

/// One route's track record inside a network context.
class GuardianRouteStats {
  GuardianRouteStats({
    this.successes = 0,
    this.failures = 0,
    this.lastSuccessAt,
    this.lastReadyMillis,
    this.lastAuthMillis,
    this.lastFailureKind,
    this.lastFailureCode,
    this.lastFailureAt,
    this.cooldownUntil,
  });

  int successes;
  int failures;

  /// The most recent FULL success (readiness + probe + authorization).
  DateTime? lastSuccessAt;

  /// Bootstrap-ready duration of the last successful attempt
  /// (start → endpoint ready), milliseconds — recorded SEPARATELY from
  /// the authorization duration (mission §7.1 measurement rule).
  int? lastReadyMillis;

  /// Authorization duration of the last successful attempt
  /// (request start → Guardian answer), milliseconds.
  int? lastAuthMillis;

  /// 'start' (the engine/probe failed) or 'authorization' (the engine
  /// was ready but Guardian said no) — the mission's separate
  /// failure classifications (§4-5).
  String? lastFailureKind;
  String? lastFailureCode;
  DateTime? lastFailureAt;

  /// Not before this instant may discovery pick this route again.
  DateTime? cooldownUntil;

  bool inCooldown(DateTime now) =>
      cooldownUntil != null && now.isBefore(cooldownUntil!);

  Map<String, Object?> toJson() => <String, Object?>{
        'successes': successes,
        'failures': failures,
        'lastSuccessAt': lastSuccessAt?.toIso8601String(),
        'lastReadyMillis': lastReadyMillis,
        'lastAuthMillis': lastAuthMillis,
        'lastFailureKind': lastFailureKind,
        'lastFailureCode': lastFailureCode,
        'lastFailureAt': lastFailureAt?.toIso8601String(),
        'cooldownUntil': cooldownUntil?.toIso8601String(),
      };

  static GuardianRouteStats fromJson(Map<Object?, Object?> json) =>
      GuardianRouteStats(
        successes: _readInt(json['successes']) ?? 0,
        failures: _readInt(json['failures']) ?? 0,
        lastSuccessAt: _readDate(json['lastSuccessAt']),
        lastReadyMillis: _readInt(json['lastReadyMillis']),
        lastAuthMillis: _readInt(json['lastAuthMillis']),
        lastFailureKind: _readString(json['lastFailureKind']),
        lastFailureCode: _readString(json['lastFailureCode']),
        lastFailureAt: _readDate(json['lastFailureAt']),
        cooldownUntil: _readDate(json['cooldownUntil']),
      );
}

/// One network context's record: the evidence that decides the next
/// connection's strategy in THIS context only (mission §7.1: per-context
/// isolation — a route that worked on one network is never blindly
/// generalized to another).
class GuardianContextRecord {
  GuardianContextRecord({
    Map<GuardianBootstrapRouteKind, GuardianRouteStats>? routes,
  }) : routes = routes ?? <GuardianBootstrapRouteKind, GuardianRouteStats>{};

  /// The route kind of the last FULL success in this context.
  GuardianBootstrapRouteKind? lastRoute;

  /// The last DIRECT attempt's classification in this context — the
  /// evidence that lets a later connection skip the doomed direct
  /// attempt (mission §4-2: only when history shows a RECENT real 451
  /// AND a valid saved bootstrap route).
  String? lastDirectOutcome; // 'ok' | 'regionUnavailable' | 'transportUnavailable' | 'other'
  DateTime? lastDirectAt;

  Map<GuardianBootstrapRouteKind, GuardianRouteStats> routes;

  GuardianRouteStats statsFor(GuardianBootstrapRouteKind kind) =>
      routes.putIfAbsent(kind, GuardianRouteStats.new);

  Map<String, Object?> toJson() => <String, Object?>{
        'lastRoute': lastRoute?.persistedName,
        'lastDirectOutcome': lastDirectOutcome,
        'lastDirectAt': lastDirectAt?.toIso8601String(),
        'routes': <String, Object?>{
          for (final entry in routes.entries)
            entry.key.persistedName: entry.value.toJson(),
        },
      };

  static GuardianContextRecord? fromJson(Map<Object?, Object?> json) {
    final record = GuardianContextRecord(
      routes: <GuardianBootstrapRouteKind, GuardianRouteStats>{},
    );
    final lastRoute = GuardianBootstrapRouteKind.fromPersisted(
      _readString(json['lastRoute']),
    );
    if (lastRoute != null) record.lastRoute = lastRoute;
    record.lastDirectOutcome = _readString(json['lastDirectOutcome']);
    record.lastDirectAt = _readDate(json['lastDirectAt']);
    final routes = json['routes'];
    if (routes is Map) {
      for (final entry in routes.entries) {
        final kind = GuardianBootstrapRouteKind.fromPersisted(
          entry.key.toString(),
        );
        final value = entry.value;
        if (kind != null && value is Map) {
          record.routes[kind] = GuardianRouteStats.fromJson(value);
        }
      }
    }
    return record;
  }
}

/// The persisted, atomic, corruption-tolerant route memory.
class GuardianBootstrapRouteMemory {
  GuardianBootstrapRouteMemory._(this._path, this._contexts, this._ttl,
      this._cooldown, this._onLog);

  /// Loads the memory from [path]. ANY problem — missing file, garbage
  /// JSON, wrong version, unexpected shape — yields an EMPTY memory
  /// (mission scenario H: corruption never crashes and never blocks
  /// the Direct path).
  static Future<GuardianBootstrapRouteMemory> load(
    String path, {
    Duration ttl = kDefaultRouteTtl,
    Duration cooldown = kDefaultRouteCooldown,
    void Function(String line)? onLog,
  }) async {
    final contexts = <String, GuardianContextRecord>{};
    try {
      final file = File(path);
      if (await file.exists()) {
        final parsed = jsonDecode(await file.readAsString());
        if (parsed is Map && parsed['version'] == kGuardianRouteMemoryVersion) {
          final stored = parsed['contexts'];
          if (stored is Map) {
            for (final entry in stored.entries) {
              final value = entry.value;
              if (value is Map) {
                final record = GuardianContextRecord.fromJson(value);
                if (record != null) contexts[entry.key.toString()] = record;
              }
            }
          }
        } else if (parsed is Map) {
          onLog?.call('route memory version mismatch — starting fresh');
        }
      }
    } catch (error) {
      // Corrupt/unreadable content: degrade to empty (overwritten with
      // valid JSON by the next successful persist).
      onLog?.call('route memory unreadable, starting fresh: $error');
    }
    return GuardianBootstrapRouteMemory._(
      path,
      contexts,
      ttl,
      cooldown,
      onLog,
    );
  }

  final String _path;
  final Map<String, GuardianContextRecord> _contexts;
  final Duration _ttl;
  final Duration _cooldown;
  final void Function(String line)? _onLog;

  /// Persists ATOMICALLY: temp file + rename, so a crash mid-write
  /// leaves the previous content intact. Persistence failures are
  /// swallowed (logged via [onLog]) — the memory must never block a
  /// connection (mission §7.1).
  Future<void> persist() async {
    try {
      final document = <String, Object?>{
        'version': kGuardianRouteMemoryVersion,
        'contexts': <String, Object?>{
          for (final entry in _contexts.entries) entry.key: entry.value.toJson(),
        },
      };
      final tmp = File('$_path.tmp');
      await tmp.writeAsString(jsonEncode(document), flush: true);
      await tmp.rename(_path);
    } catch (error) {
      _onLog?.call('route memory persist failed (ignored): $error');
    }
  }

  GuardianContextRecord _recordFor(String contextId) =>
      _contexts.putIfAbsent(contextId, GuardianContextRecord.new);

  GuardianRouteStats? statsFor(
    String contextId,
    GuardianBootstrapRouteKind kind,
  ) =>
      _contexts[contextId]?.routes[kind];

  // ---- evidence recording --------------------------------------------------

  /// A direct attempt fully succeeded: record Direct as the winning
  /// route of this context (mission §7.1 «اگر مستقیم موفق بود … نتیجه
  /// Direct به‌عنوان مسیر موفق ثبت شود») — including its route stats,
  /// so a later `validFastPathRoute` honestly reports Direct (which the
  /// manager treats as "direct first", the default ladder anyway).
  void recordDirectSuccess(String contextId, {DateTime? now}) {
    final record = _recordFor(contextId);
    final at = now ?? DateTime.now();
    record.lastRoute = GuardianBootstrapRouteKind.direct;
    record.lastDirectOutcome = 'ok';
    record.lastDirectAt = at;
    final stats = record.statsFor(GuardianBootstrapRouteKind.direct);
    stats.successes += 1;
    stats.lastSuccessAt = at;
    stats.cooldownUntil = null;
  }

  /// A direct attempt answered 451 — the region-block evidence that
  /// (together with a valid saved route) enables skipping the doomed
  /// direct attempt on the next connection.
  void recordDirectRegionUnavailable(String contextId, {DateTime? now}) {
    final record = _recordFor(contextId);
    record.lastDirectOutcome = 'regionUnavailable';
    record.lastDirectAt = now ?? DateTime.now();
  }

  /// A direct attempt failed WITHOUT a 451 (401/403/timeout/5xx/…) —
  /// recorded honestly; this must NEVER look like a region block and
  /// never triggers bootstrap by itself (mission §4-2).
  void recordDirectOtherFailure(String contextId, {DateTime? now}) {
    final record = _recordFor(contextId);
    record.lastDirectOutcome = 'other';
    record.lastDirectAt = now ?? DateTime.now();
  }

  /// Direct control-plane transport was unavailable (DNS/network/timeout,
  /// with no HTTP response). A recently verified bootstrap route may be
  /// prioritized on the next walk instead of repeating the same blackhole.
  void recordDirectTransportUnavailable(String contextId, {DateTime? now}) {
    final record = _recordFor(contextId);
    record.lastDirectOutcome = 'transportUnavailable';
    record.lastDirectAt = now ?? DateTime.now();
  }

  /// A bootstrap route FULLY succeeded (readiness + probe +
  /// authorization) — the only way a route becomes Fast-Path eligible.
  void recordRouteSuccess(
    String contextId,
    GuardianBootstrapRouteKind kind, {
    required int readyMillis,
    required int authMillis,
    DateTime? now,
  }) {
    final record = _recordFor(contextId);
    final at = now ?? DateTime.now();
    record.lastRoute = kind;
    final stats = record.statsFor(kind);
    stats.successes += 1;
    stats.lastSuccessAt = at;
    stats.lastReadyMillis = readyMillis;
    stats.lastAuthMillis = authMillis;
    stats.cooldownUntil = null; // a success clears any stale penalty
  }

  /// A bootstrap route failed — classified by [kind]: 'start' (engine
  /// or probe) vs 'authorization' (engine ready, Guardian refused).
  /// Applies the bounded cooldown (priority reduction, not a
  /// blacklist).
  void recordRouteFailure(
    String contextId,
    GuardianBootstrapRouteKind kind, {
    required String failureKind,
    String? code,
    DateTime? now,
  }) {
    final record = _recordFor(contextId);
    final at = now ?? DateTime.now();
    final stats = record.statsFor(kind);
    stats.failures += 1;
    stats.lastFailureKind = failureKind;
    stats.lastFailureCode = code;
    stats.lastFailureAt = at;
    stats.cooldownUntil = at.add(_cooldown);
    if (record.lastRoute == kind) {
      record.lastRoute = null; // no longer a Fast-Path candidate
    }
  }

  // ---- decisions -----------------------------------------------------------

  /// The valid saved Fast-Path route for [contextId], or null. Valid =
  /// a recorded full success that is still inside the TTL and whose
  /// route is not in cooldown (mission: old data alone grants nothing;
  /// memory decides PRIORITY only, never readiness).
  GuardianBootstrapRouteKind? validFastPathRoute(
    String contextId, {
    DateTime? now,
  }) {
    final record = _contexts[contextId];
    if (record == null) return null;
    final kind = record.lastRoute;
    if (kind == null) return null;
    final stats = record.routes[kind];
    final successAt = stats?.lastSuccessAt;
    if (successAt == null) return null;
    final at = now ?? DateTime.now();
    if (at.isAfter(successAt.add(_ttl))) return null; // expired → discovery
    if (stats!.inCooldown(at)) return null;
    return kind;
  }

  /// Whether the next connection may SKIP Direct: a valid saved
  /// bootstrap route plus recent evidence that Direct was blocked by
  /// Guardian 451 or a transport-level blackhole. Other failures never
  /// qualify; TTL and context rules still apply.
  bool shouldSkipDirect(
    String contextId, {
    DateTime? now,
  }) {
    final saved = validFastPathRoute(contextId, now: now);
    if (saved == null || saved == GuardianBootstrapRouteKind.direct) {
      return false;
    }
    final record = _contexts[contextId]!;
    if (record.lastDirectOutcome != 'regionUnavailable' &&
        record.lastDirectOutcome != 'transportUnavailable') return false;
    final at = now ?? DateTime.now();
    final directAt = record.lastDirectAt;
    if (directAt == null) return false;
    return at.isBefore(directAt.add(_ttl));
  }

  /// The discovery order for [contextId] (mission §4-3 adaptive
  /// selection, kept deliberately simple and testable — no opaque
  /// scoring model):
  ///  1. routes NOT in cooldown come first;
  ///  2. among them, routes with a successful history sort by MOST
  ///     RECENT success first (a new success outranks an old one —
  ///     recency weighting without magic coefficients);
  ///  3. routes without history keep the mission's default ladder
  ///     (standalone before the chain);
  ///  4. cooldown-penalized routes go last (still reachable when
  ///     nothing else remains — a bounded penalty, not a blacklist).
  List<GuardianBootstrapRouteKind> discoveryOrder(
    String contextId, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final record = _contexts[contextId];
    final statsOf = <GuardianBootstrapRouteKind, GuardianRouteStats>{};
    if (record != null) statsOf.addAll(record.routes);

    int successRecency(GuardianBootstrapRouteKind kind) {
      final successAt = statsOf[kind]?.lastSuccessAt;
      return successAt == null ? 0 : successAt.microsecondsSinceEpoch;
    }

    final fresh = <GuardianBootstrapRouteKind>[];
    final cooled = <GuardianBootstrapRouteKind>[];
    for (final kind in kDefaultDiscoveryOrder) {
      final inCooldown = statsOf[kind]?.inCooldown(at) ?? false;
      (inCooldown ? cooled : fresh).add(kind);
    }
    bool hasHistory(GuardianBootstrapRouteKind kind) =>
        statsOf[kind]?.lastSuccessAt != null;
    fresh.sort((a, b) {
      final aHistory = hasHistory(a) ? 0 : 1;
      final bHistory = hasHistory(b) ? 0 : 1;
      if (aHistory != bHistory) return aHistory.compareTo(bHistory);
      return successRecency(b).compareTo(successRecency(a));
    });
    return [...fresh, ...cooled];
  }
}

// ---- tolerant JSON readers -------------------------------------------------

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _readString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime? _readDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
