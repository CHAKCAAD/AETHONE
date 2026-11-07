/// v4.41 — the country routing profiles (owner round 17, item 3):
/// «قابلیت مسیریابی رو چک کن که واقعا کار کنن مخصوصا پروفایل ایران. یک بار
/// بازبینی کن و اگه قوانین مسیریابی کشورها به درستی وجود نداشت ایجادشون کن»
///
/// THE AUDIT FINDING this file fixes: the IR/TM/RU/CN routing-area pills
/// (settings + onboarding) only ever persisted `routingRegion` — the value
/// NEVER reached the engine, so no profile routed anything. The engine hook
/// is the pinned aether core's `AETHER_ROUTES_FILE` (routing.rs from_env):
/// the file's `[direct]` section is APPENDED to the `--route-direct` list
/// the user's own expert fields flow through, and its `[block]` section to
/// `--route-block` — so this file only needs to carry the COUNTRY rules.
///
/// Each profile (`design/routing/direct-<cc>.txt`) sends the country's own
/// traffic DIRECT (ccTLD + IDN TLD suffix rules covering every subdomain,
/// a curated domestic-domain list, and the country's aggregated IPv4 space
/// from the RIR delegation data) while everything else keeps tunneling;
/// `private` keeps LAN/loopback/CGNAT local. SNI sniffing is on by default
/// in the pinned core (AETHER_ROUTE_SNIFF), so the domain rules apply to
/// real traffic through the TUN, not just explicit SOCKS names.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// The per-country profile assets (the routing-area pills' codes). The
/// files' [direct] rules ship verbatim — data sources and dates are
/// recorded in each file's header.
const Map<String, String> countryRouteAssets = <String, String>{
  'ir': 'design/routing/direct-ir.txt',
  'tm': 'design/routing/direct-tm.txt',
  'ru': 'design/routing/direct-ru.txt',
  'cn': 'design/routing/direct-cn.txt',
};

/// True when [code] is a region with a routing profile (null/none = the
/// user opted out — no file, no env var, exactly the pre-v4.41 behavior).
bool hasCountryRouteProfile(String? code) =>
    code != null && countryRouteAssets.containsKey(code);

/// Materializes the selected country's routes file inside the app's
/// writable engine directory and returns its ABSOLUTE path — the value the
/// adapter plants into `AETHER_ROUTES_FILE` right before `aether_core_start`
/// (the core appends the file's sections to the env/CLI rule lists; see
/// routing.rs `RuleSet::from_env` + `push_list`).
///
/// The file is (re)written on EVERY connect: a profile update shipped with
/// an app release takes effect without stale-file bookkeeping, and the
/// previous session's file can never leak into the next one.
Future<String> materializeCountryRoutes({
  required String filesDir,
  required String region,
}) async {
  final asset = countryRouteAssets[region];
  if (asset == null) {
    throw ArgumentError('no routing profile for region "$region"');
  }
  final text = await rootBundle.loadString(asset);
  final dir = Directory('$filesDir/aether');
  await dir.create(recursive: true);
  final file = File('${dir.path}/routes.txt');
  await file.writeAsString(text, flush: true);
  return file.path;
}
