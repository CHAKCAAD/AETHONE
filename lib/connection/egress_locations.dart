/// Egress-location truth (v4.28 — owner round 5: «لوکیشن های سایفون و تور
/// باید لوکیشن هایی باشن که واقعا ارایه میدن نه لوکیشن های فیک»).
///
/// Two families, two honest sources — no fabricated lists:
///
///  * PSIPHON — the live set is what the Psiphon network itself announces
///    at connect time. The pinned aether core forwards the tunnel-core
///    `AvailableEgressRegions` notice into the captured core log as the
///    line `[*] psiphon can leave from: AT BE BG …` (psiphon.rs note(),
///    one line per session). The adapter harvests that line after a
///    psiphon-family connect and the store replaces the seed list — the
///    network's own standing set (`psiphonEgressRegions` in
///    transport_modes.dart) remains only as the offline SEED, because
///    Psiphon publishes no static country list (verified against the
///    tunnel-core sources: the notice is the single source of truth).
///
///  * TOR — the honest set is the countries that currently have RUNNING
///    exit relays. The Tor network's own metrics API (Onionoo —
///    https://onionoo.torproject.org, the documented public protocol
///    behind Tor Metrics) answers exactly that: the verified query below
///    returned 2686 running exit relays across 51 countries on
///    2026-11-05. Fetched fire-and-forget at app start (24 h TTL,
///    disk-cached across runs, silent failure keeps the cached set);
///    `torExitCountrySnapshot` in transport_modes.dart is the offline
///    seed recorded from the same query.
///
/// Everything here is parse-only + fetch-only: no fabricated entries, no
/// invented fallbacks — a parse that finds nothing returns null and the
/// caller keeps what it already had.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// The verified Onionoo query (checked 2026-11-05, 245 KB gzip'd reply):
/// only relay documents, only the Exit flag, only currently-running
/// relays, only the `country` field. `country` is a lowercase
/// ISO-3166-1 alpha-2 code assigned by Onionoo's GeoIP database.
const String onionooExitCountriesUrl =
    'https://onionoo.torproject.org/details'
    '?type=relay&flag=exit&fields=country,flags,running&running=true';

/// How long a cached Tor exit-country set stays fresh (the Onionoo
/// documents themselves are regenerated ~hourly; a daily refresh is the
/// polite client cadence their docs ask for).
const Duration torExitCacheTtl = Duration(hours: 24);

abstract final class EgressLocations {
  // ---- preference keys (cached LIVE sets; the seeds live in code) ----
  static const psiphonEgressKey = 'aethone.locations.psiphonEgress';
  static const torExitsKey = 'aethone.locations.torExits';
  static const torExitsFetchedAtKey = 'aethone.locations.torExitsAt';

  /// The pinned core's psiphon egress line: `[*] psiphon can leave from:
  /// AT BE BG …` (psiphon.rs note(), "AvailableEgressRegions"). Multiple
  /// sessions write multiple lines — the LAST one is the newest report.
  /// Word boundaries keep a garbage token (e.g. `GER`) from bleeding a
  /// two-letter fragment into the captured set.
  static final RegExp _psiphonLine = RegExp(
    r'psiphon can leave from:\s*(\b[A-Za-z]{2}\b(?:\s+\b[A-Za-z]{2}\b)*)',
  );

  /// Extracts the live psiphon egress regions from a core-log tail.
  /// Returns null when the notice has not (yet) appeared — the caller
  /// keeps whatever it had (the seed or an older live set).
  static List<String>? parsePsiphonEgressRegions(String logText) {
    final matches = _psiphonLine.allMatches(logText).toList();
    if (matches.isEmpty) return null;
    final codes = matches.last
        .group(1)!
        .split(RegExp(r'\s+'))
        .map((c) => c.toLowerCase())
        .toList();
    return sanitizeCodes(codes);
  }

  /// Extracts the unique exit countries from an Onionoo `details` reply
  /// (`{"relays":[{"country":"de", …}, …], "bridges":[]}`). Returns null
  /// for an empty/shapeless document — never a fabricated list.
  static List<String>? parseOnionooCountries(String body) {
    Object? doc;
    try {
      doc = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (doc is! Map) return null;
    final relays = doc['relays'];
    if (relays is! List) return null;
    final codes = <String>[
      for (final r in relays)
        if (r is Map && r['country'] is String) r['country'] as String,
    ];
    return sanitizeCodes(codes);
  }

  /// Normalizes a code list: exactly-two-letter lowercase alpha, deduped,
  /// sorted. Returns null when nothing survives (an all-garbage list is
  /// not a list).
  static List<String>? sanitizeCodes(List<String> codes) {
    final valid = <String>{
      for (final c in codes)
        if (c.length == 2 && _alpha2.matches(c)) c.toLowerCase(),
    };
    if (valid.isEmpty) return null;
    return valid.toList()..sort();
  }

  static final RegExp _alpha2 = RegExp(r'^[a-z]{2}$');

  /// Fetches the live Tor exit-country set from Onionoo. Never throws —
  /// a network/API failure returns null and the caller keeps its cached
  /// set or the bundled snapshot.
  static Future<List<String>?> fetchTorExitCountries({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client
          .getUrl(Uri.parse(onionooExitCountriesUrl))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body =
          await res.transform(utf8.decoder).join().timeout(timeout);
      return parseOnionooCountries(body);
    } catch (_) {
      return null; // offline, blocked, slow — the snapshot/cache stands
    } finally {
      client?.close(force: true);
    }
  }

  // ---- disk cache (shared_preferences; JSON list, validated on read) ----

  static Future<List<String>?> _loadList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final doc = jsonDecode(raw);
      if (doc is! List) return null;
      return sanitizeCodes(
        [for (final e in doc if (e is String)) e],
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveList(String key, List<String> codes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(codes));
    } catch (_) {
      // cache-only — a failed write never surfaces
    }
  }

  /// The last live psiphon egress set the core reported (any session).
  static Future<List<String>?> loadCachedPsiphonEgress() =>
      _loadList(psiphonEgressKey);

  static Future<void> savePsiphonEgress(List<String> codes) =>
      _saveList(psiphonEgressKey, codes);

  /// The last cached Tor exit-country set (null = never fetched).
  static Future<List<String>?> loadCachedTorExits() =>
      _loadList(torExitsKey);

  static Future<void> saveTorExits(List<String> codes) async {
    await _saveList(torExitsKey, codes);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        torExitsFetchedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // cache-only
    }
  }

  /// True when the cached Tor set is older than [torExitCacheTtl] (or has
  /// never been fetched).
  static Future<bool> torCacheIsStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(torExitsFetchedAtKey);
      if (at == null) return true;
      return DateTime.now().millisecondsSinceEpoch - at >
          torExitCacheTtl.inMilliseconds;
    } catch (_) {
      return true;
    }
  }

  /// The app-start refresh: fetch the live Tor exit set when the cache is
  /// stale, hand it to [onFresh] (the store) and cache it. Fire-and-forget
  /// by design — a failure keeps the cached set / bundled snapshot.
  static Future<void> refreshTorExits(
    void Function(List<String> codes) onFresh,
  ) async {
    try {
      if (!await torCacheIsStale()) return;
      final fresh = await fetchTorExitCountries();
      if (fresh == null || fresh.isEmpty) return;
      await saveTorExits(fresh);
      onFresh(fresh);
    } catch (_) {
      // never fatal — the wheel always has the snapshot seed
    }
  }
}
