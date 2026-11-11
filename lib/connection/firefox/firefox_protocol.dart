/// Firefox VPN engine wire types — the Dart mirror of the Go engine's
/// contract (cmd/libfirefoxvpn at the phase-1 pin; see
/// docs/FIREFOX_VPN_ENGINE.md):
///
///  * config: ONE JSON line written to the child's stdin right after
///    spawn — the ONLY sanctioned carrier of session tokens (never argv,
///    never environment, never files, never logs);
///  * events: JSON lines on stdout; `authRefreshed` is the only event
///    carrying secret material (the refreshed same-account OAuth pair)
///    and must go straight into the Keystore-backed store;
///  * shutdown: closing the child's stdin is the shutdown request.
///
/// PHASE B (Part 2) — the `failed` event contract, extended additively
/// (EngineVersion 1.2.0-phaseb; nothing existing is renamed or removed):
///
/// ```json
/// {"event":"failed","failCode":"dnsError","httpStatus":0,
///  "retryable":true,"message":"<raw Go chain — LOG ONLY>"}
/// ```
///
///  * `failCode` — the legacy single-word codes (exchangeFailed, …) keep
///    working forever; a rebuilt engine emits the granular Phase B
///    transport classes (dnsError | networkUnavailable | timeout |
///    tlsError | sessionRejected | tokenExchange | invalidTokenResponse |
///    serverRejection | unknown — fferr.Code on the Go side);
///  * `httpStatus` — OPTIONAL int, the REAL status code on HTTP-level
///    failures (absent/0 on transport-level ones);
///  * `retryable` — OPTIONAL bool, the engine's retry policy hint;
///  * `message` — unchanged, and STILL never rendered by the UI (the
///    FirefoxErrors layer maps the class code to static text).
///
/// The Dart parser tolerates missing, null and wrong-typed extras
/// (hostile/broken JSON never throws the process managers).
///
/// Phase 1 of the Firefox VPN integration (private branch
/// `phase1/firefox-vpn`; engine license status UNRESOLVED — nothing here
/// ships publicly until the owner settles it).
library;

import 'firefox_errors.dart';

/// The engine's config object (engine.Config on the Go side).
class FirefoxEngineConfig {
  const FirefoxEngineConfig({
    required this.socksListen,
    required this.auth,
    this.guardian = 'https://vpn.mozilla.org',
    this.country = '',
    this.transport = 'h2',
    this.upstreamOverride = '',
    this.logLevel = 'normal',
    this.dns = const {'mode': 'system'},
  });

  /// Loopback listener ONLY (the engine refuses anything else).
  final String socksListen;

  /// The same-account OAuth pair (from the Keystore-backed store or a
  /// controlled test injection).
  final FirefoxSessionAuth auth;

  final String guardian;

  /// '' (auto/REC), 'REC', or an ISO-3166-1 alpha-2 code / country name.
  final String country;

  /// 'h2' (default) or 'h3'.
  final String transport;

  /// Explicit upstream "host:port" (transparent override; empty = live
  /// RemoteSettings discovery).
  final String upstreamOverride;

  final String logLevel;

  /// Process-scoped DNS policy; defaults to Android System DNS.
  final Map<String, dynamic> dns;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'socksListen': socksListen,
        'guardian': guardian,
        'country': country,
        'transport': transport,
        if (upstreamOverride.isNotEmpty) 'upstreamOverride': upstreamOverride,
        'logLevel': logLevel,
        'dns': dns,
        'auth': {
          'accessToken': auth.accessToken,
          'refreshToken': auth.refreshToken,
          if (auth.expiresAt != null)
            'expiresAt': auth.expiresAt!.toIso8601String(),
        },
      };
}

/// The same-account OAuth pair. NEVER log, NEVER put in argv/env, NEVER
/// persist outside the Keystore-backed store.
class FirefoxSessionAuth {
  const FirefoxSessionAuth({
    required this.accessToken,
    this.refreshToken = '',
    this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };

  static FirefoxSessionAuth fromJson(Map<String, dynamic> raw) =>
      FirefoxSessionAuth(
        accessToken: raw['accessToken'] as String? ?? '',
        refreshToken: raw['refreshToken'] as String? ?? '',
        expiresAt: raw['expiresAt'] == null
            ? null
            : DateTime.tryParse(raw['expiresAt'] as String),
      );
}

/// One engine status event (engine.Event on the Go side). Field names
/// mirror the wire exactly.
class FirefoxEngineEvent {
  FirefoxEngineEvent.fromJson(Map<String, dynamic> raw)
      : name = raw['event'] as String? ?? '',
        message = raw['message'] as String? ?? '',
        failCode = raw['failCode'] as String? ?? '',
        reason = raw['reason'] as String? ?? '',
        exitCode = (raw['code'] as num?)?.toInt() ?? 0,
        addr = raw['addr'] as String? ?? '',
        transport = raw['transport'] as String? ?? '',
        proxyHost = raw['proxyHost'] as String? ?? '',
        country = raw['country'] as String? ?? '',
        countryName = raw['countryName'] as String? ?? '',
        cityCode = raw['cityCode'] as String? ?? '',
        cityName = raw['cityName'] as String? ?? '',
        hostname = raw['hostname'] as String? ?? '',
        port = (raw['port'] as num?)?.toInt() ?? 0,
        selectionSource = raw['selectionSource'] as String? ?? '',
        recommended = raw['recommended'] == true,
        passExpiresAt = raw['passExpiresAt'] as String? ?? '',
        quotaLeft = raw['quotaLeft'] as String? ?? '',
        quotaReset = raw['quotaReset'] as String? ?? '',
        exitIp = raw['exitIp'] as String? ?? '',
        exitCountry = raw['exitCountry'] as String? ?? '',
        configuredCountry = raw['configuredCountry'] as String? ?? '',
        exitCountryMatches = raw['exitCountryMatches'] as bool?,
        latencyMs = (raw['latencyMs'] as num?)?.toInt() ?? 0,
        line = raw['line'] as String? ?? '',
        loginMode = raw['loginMode'] as String? ?? '',
        attempt = (raw['attempt'] as num?)?.toInt() ?? 0,
        expiresIn = (raw['expiresIn'] as num?)?.toInt() ?? 0,
        obtainedAt = DateTime.tryParse(raw['obtainedAt'] as String? ?? ''),
        // PHASE B (Part 2): the optional failed-event extras — tolerant
        // reads (wrong JSON types degrade to the defaults, never throw).
        httpStatus = _tolerantInt(raw['httpStatus']),
        // null when the engine did not send it (legacy engines) or
        // sent a wrong type — the per-class default then applies.
        retryable = raw['retryable'] is bool ? raw['retryable'] as bool? : null,
        // authRefreshed / loginCompleted only — the PRIVATE pair; the host
        // routes it straight into the Keystore store and never logs it.
        // PHASE B (Part 3): tolerant string reads — a wrong-typed token
        // field degrades to '' (the pair guard then rejects it) instead
        // of throwing the whole event parse.
        accessToken = _tolerantString(raw['accessToken']),
        refreshToken = _tolerantString(raw['refreshToken']);

  final String name;
  final String message;
  final String failCode;
  final String reason;
  final int exitCode;
  final String addr;
  final String transport;
  final String proxyHost;
  final String country;
  final String countryName;
  final String cityCode;
  final String cityName;
  final String hostname;
  final int port;
  final String selectionSource;
  final bool recommended;
  final String passExpiresAt;
  final String quotaLeft;
  final String quotaReset;
  final String exitIp;
  final String exitCountry;
  final String configuredCountry;
  final bool? exitCountryMatches;
  final int latencyMs;
  final String line;
  final String loginMode;
  final int attempt;

  /// loginCompleted / authRefreshed: the pair's lifetime facts (never
  /// secret; the tokens themselves live only in the private fields).
  final int expiresIn;
  final DateTime? obtainedAt;
  final String accessToken;
  final String refreshToken;

  /// PHASE B (Part 2) — the failed-event extras (0/absent on legacy
  /// engines and on transport-level failures). `retryable` is NULL when
  /// the engine did not send the hint — the class default applies then.
  final int httpStatus;
  final bool? retryable;

  /// Wrong-typed JSON degrade helpers (Part 3's type-correctness rule:
  /// a hostile or broken engine response never throws the parse).
  static String _tolerantString(Object? v) => v is String ? v : '';
  static int _tolerantInt(Object? v) => v is num ? v.toInt() : 0;

  /// True for the events that carry secret material.
  bool get carriesSecrets =>
      (name == 'authRefreshed' || name == 'loginCompleted') &&
      (accessToken.isNotEmpty || refreshToken.isNotEmpty);

  /// Redacted rendering for logs/diagnostics — NEVER includes tokens.
  String get logLine {
    switch (name) {
      case 'authRefreshed':
        return 'engine: session tokens refreshed by the engine '
            '(stored; access<redacted> refresh<redacted>)';
      case 'loginCompleted':
        return 'login: session tokens minted by the exchange '
            '(stored; access<redacted> refresh<redacted>)';
      case 'loginRetry':
        return 'login: session not confirmed yet '
            '(attempt $attempt, retrying)';
      case 'failed':
        return 'engine failed ($failCode): $message';
      default:
        return 'engine: $name${message.isEmpty ? '' : ' — $message'}';
    }
  }
}

/// Engine event names (mirrors engine.Ev* on the Go side).
abstract final class FirefoxEngineEvents {
  static const started = 'started';
  static const discoveryFetched = 'discoveryFetched';
  static const selected = 'selected';
  static const passAcquired = 'passAcquired';
  static const upstreamReady = 'upstreamReady';
  static const socksReady = 'socksReady';
  static const exitVerified = 'exitVerified';
  static const exitVerifyFailed = 'exitVerifyFailed';
  static const authRefreshed = 'authRefreshed';
  static const renewed = 'renewed';
  static const renewalFailed = 'renewalFailed';
  static const quotaExhausted = 'quotaExhausted';
  // --login role (Phase 2)
  static const loginStarted = 'loginStarted';
  static const loginRetry = 'loginRetry';
  static const loginCompleted = 'loginCompleted';
  static const stopping = 'stopping';
  static const stopped = 'stopped';
  static const failed = 'failed';
  static const log = 'log';
}

/// Engine failure codes (mirrors engine.Err*).
abstract final class FirefoxEngineFailure {
  static const badConfig = 'badConfig';
  static const discoveryFailed = 'discoveryFailed';
  static const noMatchForCountry = 'noMatchForCountry';
  static const passFetchFailed = 'passFetchFailed';
  static const quotaExhausted = 'quotaExhausted';
  static const upstreamSessionFailed = 'upstreamSessionFailed';
  static const socksListenFailed = 'socksListenFailed';
  static const renewalTimeout = 'renewalTimeout';
  static const internalError = 'internalError';
  // --login role (Phase 2)
  static const loginModeUnsupported = 'loginModeUnsupported';
  static const sessionTokenInvalid = 'sessionTokenInvalid';
  static const sessionRejected = 'sessionRejected';
  static const loginTimeout = 'loginTimeout';
  static const exchangeFailed = 'exchangeFailed';

  /// PHASE B (Part 2) — the granular transport classes a v1.2.0-phaseb
  /// engine emits for the exchange/login failures (fferr.Code; the
  /// legacy codes above stay valid forever — see firefox_errors.dart).
  static const dnsError = FirefoxTransportError.dnsError;
  static const networkUnavailable = FirefoxTransportError.networkUnavailable;
  static const timeout = FirefoxTransportError.timeout;
  static const tlsError = FirefoxTransportError.tlsError;
  static const tokenExchange = FirefoxTransportError.tokenExchange;
  static const invalidTokenResponse = FirefoxTransportError.invalidTokenResponse;
  static const serverRejection = FirefoxTransportError.serverRejection;
  static const unknown = FirefoxTransportError.unknown;
}

/// Engine exit codes (mirrors engine.Exit*).
abstract final class FirefoxEngineExitCode {
  static const clean = 0;
  static const startup = 1;
  static const quota = 2;
  static const renewal = 3;
  static const internal = 4;
}

/// Terminal outcome of one `--login` exchange (Phase 2).
class FirefoxLoginResult {
  const FirefoxLoginResult({
    required this.state,
    this.auth,
    this.failCode = '',
    this.message = '',
  });

  factory FirefoxLoginResult.cancelled() =>
      const FirefoxLoginResult(state: FirefoxLoginState.cancelled);

  factory FirefoxLoginResult.failed(String failCode, String message) =>
      FirefoxLoginResult(
        state: FirefoxLoginState.failed,
        failCode: failCode,
        message: message,
      );

  final FirefoxLoginState state;

  /// The minted pair — present ONLY on [FirefoxLoginState.completed];
  /// the caller persists it in the Keystore vault immediately.
  final FirefoxSessionAuth? auth;

  final String failCode;
  final String message;

  bool get isCompleted => state == FirefoxLoginState.completed;
}

enum FirefoxLoginState { running, completed, cancelled, failed }
