/// Aether process-environment hygiene — the v4.21 fix for the owner's
/// device-test report «فقط بار اول وصل میشن … دیگه هیچ پروتکلی متصل
/// نمیشه» (engineClosed, state: null).
///
/// ROOT CAUSE (evidence: aether/src/cli.rs at the frozen pin):
///  * the Aether core parses its CLI by translating EVERY flag into an
///    `AETHER_*` environment variable via `std::env::set_var` — flags only
///    SET, they never CLEAR;
///  * the core runs IN-PROCESS (dart:ffi, architecture B+), so the process
///    environment SURVIVES between `aether_core_start` jobs;
///  * a second connect therefore inherited the previous session's mode:
///    e.g. `AETHER_PSIPHON=chain` (psiphon-over-warp), or — worse — the
///    core's OWN reverse-mode leftovers `AETHER_UPSTREAM` +
///    `AETHER_MASQUE_HTTP2=1` (lib.rs sets them itself for --tor-reverse /
///    --psiphon-reverse), which point the new session at the DEAD carrier
///    port of the old one. The core then fails during startup (often at
///    `upstream::check_setting()`, lib.rs L107) — job done with an error
///    result, surfacing as the anonymous `engineClosed (state: null)`.
///
/// THE FIX: before EVERY `aether_core_start`, the adapter clears every
/// `AETHER_*` variable the pinned core can read (the full inventory below
/// was extracted mechanically from `grep -rhoE 'AETHER_[A-Z0-9_]+'` over
/// aether/src at the pin — 137 names). The fresh arg list then re-sets
/// exactly the variables the selected mode needs. `unsetenv` is called
/// through bionic libc (`DynamicLibrary.process()`), because Dart's
/// `Platform.environment` is read-only and cannot touch the native
/// `getenv` the Rust core reads.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The complete `AETHER_*` inventory of the pinned core (cli.rs set/append
/// targets + core-internal set_var + every env::var read). Keep in sync
/// with the pin: the companion test (`aether_env_test.dart`) re-derives
/// nothing — the list is frozen evidence, matched against CLI_REFERENCE.
const List<String> aetherEnvVars = <String>[
  'AETHER_ACCESS_CLIENT_ID',
  'AETHER_ACCESS_CLIENT_SECRET',
  'AETHER_ACCESS_EMAIL',
  'AETHER_ACCESS_TOKEN',
  'AETHER_API_ADDRESS',
  'AETHER_API_HOST',
  'AETHER_API_SNI',
  'AETHER_CONFIG',
  'AETHER_DISABLE_EXTENSION_PERMUTATION',
  'AETHER_DISABLE_GREASE',
  'AETHER_DISABLE_OCSP_STAPLING',
  'AETHER_DISABLE_SCT',
  'AETHER_DISABLE_SESSION_TICKET',
  'AETHER_DNS',
  'AETHER_DOH_FRONT_TEST_DNS',
  'AETHER_DOH_FRONT_TEST_DOMAIN',
  'AETHER_DOH_SERVER_TEST_DNS',
  'AETHER_DOH_SERVER_TEST_DOMAIN',
  'AETHER_DOH_TEST_DNS',
  'AETHER_DOH_TEST_DOMAIN',
  'AETHER_ECH',
  'AETHER_ECH_DNS',
  'AETHER_ECH_DOMAIN',
  'AETHER_ENABLE_ECH_GREASE',
  'AETHER_ENABLE_GREASE_SIGALGS',
  'AETHER_EXIT_LOC',
  'AETHER_EXIT_LOC_SECS',
  'AETHER_GATEWAY',
  'AETHER_GOOL_INNER',
  'AETHER_GOOL_MODE',
  'AETHER_HALF_CLOSE_SECS',
  'AETHER_HTTP_PROXY',
  'AETHER_IP',
  'AETHER_IRONCLAD_PORT',
  'AETHER_LOG_LEVEL',
  'AETHER_MARK',
  'AETHER_MASQUE_CONFIG',
  'AETHER_MASQUE_H2_FRAGMENT',
  'AETHER_MASQUE_H2_FRAGMENT_DELAY',
  'AETHER_MASQUE_H2_FRAGMENT_SIZE',
  'AETHER_MASQUE_H2_FRAGMENT_SNI',
  'AETHER_MASQUE_H2_KEEPALIVE_SECS',
  'AETHER_MASQUE_H2_KEEPALIVE_TIMEOUT_SECS',
  'AETHER_MASQUE_H2_PEER',
  'AETHER_MASQUE_HTTP2',
  'AETHER_MASQUE_MTU',
  'AETHER_MASQUE_NO_DATA_CHECK',
  'AETHER_MASQUE_RECONNECT_SECS',
  'AETHER_MASQUE_SNI',
  'AETHER_MASQUE_STARTUP_SECS',
  'AETHER_MASQUE_VALIDATE_SECS',
  'AETHER_MAX_CLIENTS',
  'AETHER_MIM_INNER_PEER',
  'AETHER_MIM_OUTER_PEER',
  'AETHER_MIM_PEERS',
  'AETHER_NETSTACK_TCP_RX',
  'AETHER_NETSTACK_TCP_TX',
  'AETHER_NOIZE',
  'AETHER_PEER',
  'AETHER_PERF_PROFILE',
  'AETHER_PROBE_ATTEMPTS',
  'AETHER_PROBE_PORTS',
  'AETHER_PROBE_TIMEOUT_MS',
  'AETHER_PROTOCOL',
  'AETHER_PSIPHON',
  'AETHER_PSIPHON_BIN',
  'AETHER_PSIPHON_BIND',
  'AETHER_PSIPHON_CDN_IPS',
  'AETHER_PSIPHON_CDN_SETS',
  'AETHER_PSIPHON_CDN_SNI',
  'AETHER_PSIPHON_CONFIG',
  'AETHER_PSIPHON_DIR',
  'AETHER_PSIPHON_HTTP',
  'AETHER_PSIPHON_INTERFACE',
  'AETHER_PSIPHON_MODE',
  'AETHER_PSIPHON_PROPAGATION_CHANNEL_ID',
  'AETHER_PSIPHON_READY_SECS',
  'AETHER_PSIPHON_REGION',
  'AETHER_PSIPHON_SERVER_ENTRIES',
  'AETHER_PSIPHON_SERVER_LIST',
  'AETHER_PSIPHON_SPONSOR_ID',
  'AETHER_QUICK_RECONNECT',
  'AETHER_QUIC_V2',
  'AETHER_REGISTER',
  'AETHER_REPROVISION',
  'AETHER_ROUTES_FILE',
  'AETHER_ROUTE_BLOCK',
  'AETHER_ROUTE_DIRECT',
  'AETHER_ROUTE_SNIFF',
  'AETHER_ROUTE_SNIFF_MS',
  'AETHER_SCAN',
  'AETHER_SOCKS',
  'AETHER_STATS',
  'AETHER_STATS_SECS',
  'AETHER_TCP_CONNECT_SECS',
  'AETHER_TCP_KEEPALIVE_SECS',
  'AETHER_TEAM',
  'AETHER_TEAM_ENDPOINT',
  'AETHER_TLS13_CIPHERS',
  'AETHER_TLS_ALPS',
  'AETHER_TLS_CERT_COMPRESSION',
  'AETHER_TLS_CIPHERS',
  'AETHER_TLS_GROUPS',
  'AETHER_TLS_KEY_SHARES',
  'AETHER_TLS_SERVER_PADDING',
  'AETHER_TLS_SIGALGS',
  'AETHER_TLS_TRUST_ANCHORS',
  'AETHER_TLS_VERIFY',
  'AETHER_TOR',
  'AETHER_TOR_BIND',
  'AETHER_TOR_BRIDGE_FILE',
  'AETHER_TOR_BRIDGE_SECS',
  'AETHER_TOR_BRIDGES',
  'AETHER_TOR_CHECK',
  'AETHER_TOR_COUNTRY',
  'AETHER_TOR_DIR',
  'AETHER_TOR_DIRECT_SECS',
  'AETHER_TOR_HTTP',
  'AETHER_TOR_LOG',
  'AETHER_TOR_PT',
  'AETHER_TOR_PT_DIR',
  'AETHER_TOR_RELAY_PORTS',
  'AETHER_TOR_RELAYS',
  'AETHER_TOR_STALL_SECS',
  'AETHER_UPSTREAM',
  'AETHER_WG_CONFIG',
  'AETHER_WG_ENDPOINT_COOLDOWN_SECS',
  'AETHER_WG_KEEPALIVE',
  'AETHER_WG_NO_DATA_CHECK',
  'AETHER_WG_NO_PROFILE_RETRY',
  'AETHER_WG_PEER',
  'AETHER_WG_RECONNECT_SECS',
  'AETHER_WG_STALE_SECS',
  'AETHER_WG_VALIDATE_SECS',
  'AETHER_WIW_INNER_PEER',
  'AETHER_WIW_OUTER_PEER',
  'AETHER_WIW_PEERS',
];

typedef _UnsetEnvC = Int32 Function(Pointer<Utf8>);
typedef _UnsetEnvDart = int Function(Pointer<Utf8>);
typedef _SetEnvC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetEnvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);

/// Clears every [aetherEnvVars] entry from the PROCESS environment (the
/// one the in-process Rust core reads via getenv). Returns the number of
/// variables actually removed. Safe to call anywhere: no-ops when a
/// variable is unset already, and never throws — a failure to clean one
/// variable is not worth killing a connect walk for (the fresh arg list
/// overrides the important mode selects anyway).
int clearAetherEnvironment() {
  int removed = 0;
  try {
    final libc = DynamicLibrary.process();
    final unset =
        libc.lookupFunction<_UnsetEnvC, _UnsetEnvDart>('unsetenv');
    for (final name in aetherEnvVars) {
      final cName = name.toNativeUtf8();
      try {
        if (unset(cName) == 0) removed++;
      } finally {
        calloc.free(cName);
      }
    }
  } catch (_) {
    // Not on a platform that exports unsetenv (tests, desktop) — nothing
    // to clean; the core would not run in-process there anyway.
    return 0;
  }
  return removed;
}

/// Sets one `AETHER_*` variable in the process environment (used by tests
/// to plant a polluted environment before [clearAetherEnvironment]).
bool setAetherEnvVar(String name, String value) {
  try {
    final libc = DynamicLibrary.process();
    final setenv =
        libc.lookupFunction<_SetEnvC, _SetEnvDart>('setenv');
    final cName = name.toNativeUtf8();
    final cValue = value.toNativeUtf8();
    try {
      return setenv(cName, cValue, 1) == 0;
    } finally {
      calloc.free(cName);
      calloc.free(cValue);
    }
  } catch (_) {
    return false;
  }
}

/// Reads one variable through the native getenv (the view the Rust core
/// sees) — null when unset. Test/diagnostic aid.
String? aetherEnvVar(String name) {
  try {
    final libc = DynamicLibrary.process();
    final getenv = libc
        .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>)>('getenv');
    final cName = name.toNativeUtf8();
    try {
      final raw = getenv(cName);
      return raw == nullptr ? null : raw.toDartString();
    } finally {
      calloc.free(cName);
    }
  } catch (_) {
    return null;
  }
}
