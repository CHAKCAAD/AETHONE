/// Firefox VPN server discovery — the Dart-side model + internal API.
///
/// Phase 1 scope: NO UI. This file provides the data model and the fetch
/// path the (phase-2) location UI will bind to, honoring the phase-0
/// policy (docs/FIREFOX_VPN_SERVER_DISCOVERY.md):
///
///  * the ONLY source of truth is the LIVE Mozilla RemoteSettings
///    collection — fetched by the engine binary itself (`--discover`)
///    with the upstream uTLS Firefox ClientHello (a plain Dart HTTPS
///    client would present a Go/Dart ClientHello and risk the Fastly
///    edge's bot defenses; the engine is the proven path);
///  * "CatchAll Anycast" is EXCLUDED (already excluded by the engine);
///  * REC is the auto/recommended entry (mirrors `autoWheelCode`);
///  * quarantined locations are kept in the model but flagged (honest
///    availability), never selectable;
///  * a disk cache with a 6 h TTL (the MIT reference FoxyVPN's policy,
///    phase-0 §5) serves offline starts and is always LABELED as cached,
///    never presented as live data;
///  * the AETHONE 266-flag manifest is NOT a server list and is never
///    used as one.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One selectable server location (mirror of the engine's
/// discovery.LocationRecord).
class FirefoxLocation {
  const FirefoxLocation({
    required this.countryCode,
    required this.countryName,
    required this.cityCode,
    required this.cityName,
    required this.serverHostname,
    required this.serverPort,
    required this.quarantined,
    required this.recommended,
  });

  final String countryCode;
  final String countryName;
  final String cityCode;
  final String cityName;
  final String serverHostname;
  final int serverPort;
  final bool quarantined;
  final bool recommended;

  bool get selectable => !quarantined;

  Map<String, dynamic> toJson() => {
        'countryCode': countryCode,
        'countryName': countryName,
        'cityCode': cityCode,
        'cityName': cityName,
        'serverHostname': serverHostname,
        'serverPort': serverPort,
        'quarantined': quarantined,
        'recommended': recommended,
      };

  static FirefoxLocation fromJson(Map<String, dynamic> raw) =>
      FirefoxLocation(
        countryCode: raw['countryCode'] as String? ?? '',
        countryName: raw['countryName'] as String? ?? '',
        cityCode: raw['cityCode'] as String? ?? '',
        cityName: raw['cityName'] as String? ?? '',
        serverHostname: raw['serverHostname'] as String? ?? '',
        serverPort: (raw['serverPort'] as num?)?.toInt() ?? 443,
        quarantined: raw['quarantined'] == true,
        recommended: raw['recommended'] == true,
      );
}

/// One discovery result — live or cached, ALWAYS labeled.
class FirefoxLocationList {
  const FirefoxLocationList({
    required this.locations,
    required this.fetchedAt,
    required this.live,
  });

  final List<FirefoxLocation> locations;
  final DateTime fetchedAt;

  /// true = fresh from RemoteSettings; false = served from the disk cache
  /// (transparent fallback — the caller must surface which one it got).
  final bool live;

  /// The selectable entries (quarantined excluded), REC first.
  List<FirefoxLocation> get selectable {
    final rec = <FirefoxLocation>[];
    final rest = <FirefoxLocation>[];
    for (final l in locations) {
      if (!l.selectable) continue;
      (l.recommended ? rec : rest).add(l);
    }
    return [...rec, ...rest];
  }

  /// Distinct selectable country codes (REC not included as a country).
  List<String> get selectableCountryCodes {
    final seen = <String>{};
    for (final l in selectable) {
      if (l.recommended) continue;
      seen.add(l.countryCode.toUpperCase());
    }
    return seen.toList()..sort();
  }

  Map<String, dynamic> toJson() => {
        'locations': locations.map((l) => l.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
        'live': live,
      };

  static FirefoxLocationList fromJson(Map<String, dynamic> raw) =>
      FirefoxLocationList(
        locations: (raw['locations'] as List? ?? [])
            .map((e) =>
                FirefoxLocation.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false),
        fetchedAt:
            DateTime.tryParse(raw['fetchedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        live: raw['live'] == true,
      );
}

/// Fetches the live list through the engine binary's `--discover` role
/// and maintains the labeled disk cache.
class FirefoxDiscovery {
  FirefoxDiscovery({
    required this.binaryPath,
    required this.cachePath,
    this.ttl = const Duration(hours: 6),
    this.fetchTimeout = const Duration(seconds: 30),
  });

  final String binaryPath;

  /// App-private cache file (e.g. `<filesDir>/firefox/serverlist.json`).
  final String cachePath;

  final Duration ttl;
  final Duration fetchTimeout;

  FirefoxLocationList? _memory;

  /// The freshest list: memory → live fetch → disk cache (each step
  /// labeled). Never throws: a total failure returns null (the caller
  /// surfaces the honest "no list" state; connect without a country then
  /// fails inside the engine with `discoveryFailed`/`noMatchForCountry`).
  Future<FirefoxLocationList?> refresh() async {
    // 1. live fetch — the only path that can produce live data.
    final live = await _fetchLive();
    if (live != null) {
      _memory = live;
      await _writeCache(live);
      return live;
    }
    // 2. memory (may be expired but still labeled cached).
    final mem = _memory;
    if (mem != null && mem.locations.isNotEmpty) return mem;
    // 3. disk cache (labeled cached, with its age checked against the
    //    ttl only for REPORTING — an expired cache is still returned when
    //    it is all we have, transparently marked).
    final disk = await _readCache();
    if (disk != null && disk.locations.isNotEmpty) {
      _memory = disk;
      return disk;
    }
    return null;
  }

  Future<FirefoxLocationList?> _fetchLive() async {
    try {
      final result = await Process.run(
        binaryPath,
        const ['--discover'],
        environment: const {},
        includeParentEnvironment: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(fetchTimeout);
      if (result.exitCode != 0) return null;
      final decoded = _decodeLine(result.stdout as String);
      if (decoded == null) return null;
      final list = FirefoxLocationList.fromJson(decoded)
          .copyWith(live: true, fetchedAt: DateTime.now());
      if (list.locations.isEmpty) return null;
      return list;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeLine(String stdout) {
    for (final line in const LineSplitter().convert(stdout)) {
      if (!line.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // keep scanning (banner lines etc.)
      }
    }
    return null;
  }

  Future<void> _writeCache(FirefoxLocationList list) async {
    try {
      final file = File(cachePath);
      await file.parent.create(recursive: true);
      // Atomic replace (tmp + rename), the reference pattern.
      final tmp = File('$cachePath.tmp');
      await tmp.writeAsString(jsonEncode(list.toJson()), flush: true);
      await tmp.rename(cachePath);
    } catch (_) {
      // cache write is best-effort
    }
  }

  Future<FirefoxLocationList?> _readCache() async {
    try {
      final raw = await File(cachePath).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return FirefoxLocationList.fromJson(decoded).copyWith(live: false);
      }
    } catch (_) {
      // no cache / corrupt cache — transparent miss
    }
    return null;
  }

  /// Whether the cached/current list is older than the TTL.
  bool isStale(FirefoxLocationList list) =>
      DateTime.now().difference(list.fetchedAt) > ttl;
}

extension on FirefoxLocationList {
  FirefoxLocationList copyWith({bool? live, DateTime? fetchedAt}) =>
      FirefoxLocationList(
        locations: locations,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        live: live ?? this.live,
      );
}
