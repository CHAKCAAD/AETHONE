/// PHASE B (firefox-vpn, Part 2 + Part 3) — the engine→UI error contract.
///
/// The failure chain this module owns:
///
///     Go engine (type-based classification — see
///     docs/phaseb-engine-patch/) → JSON `failed` event (failCode +
///     optional httpStatus/retryable + raw message) → FirefoxVpnEngine /
///     FirefoxLoginClient (process managers) → PlatformEngineAdapter /
///     ConnectionStore (service/state) → the UI surfaces.
///
/// Rules (the Phase B decree):
///  * the UI text is chosen by the CLASS CODE ONLY — the engine's raw
///    Go chain (`message`) NEVER reaches a user-visible surface; it goes
///    to the diagnostics log through [redactLine] only;
///  * the granular classes distinguish DNS / network unavailable /
///    timeout / TLS / session rejected / token exchange / invalid token
///    response / server rejection / Guardian region-unavailable (the
///    Guardian-only 451 class — guardian-bootstrap Stage 1) / unknown;
///  * HTTP-level failures carry the REAL status code ([FirefoxFailure.httpStatus]);
///  * [FirefoxFailure.retryable] is the UI policy (a "try again" hint);
///  * LEGACY engines (EngineVersion 1.1.0-phase2, the 2026-11-08 field
///    build) emit the umbrella `exchangeFailed` with no httpStatus —
///    accepted forever and mapped to the token-exchange class;
///  * unknown / empty / wrong-typed codes fall back to the generic
///    class and NEVER throw (the parser tolerates hostile JSON);
///  * the OAuth pair guard (Part 3): "completed" requires BOTH tokens
///    present as JSON strings, non-empty and non-blank — no token format
///    is invented or checked beyond that.
library;

/// The Phase B failure classes (the wire `failCode` values a v1.2.0-phaseb
/// engine emits; mirrors `fferr.Code` on the Go side).
abstract final class FirefoxTransportError {
  static const dnsError = 'dnsError';
  static const networkUnavailable = 'networkUnavailable';
  static const timeout = 'timeout';
  static const tlsError = 'tlsError';
  static const sessionRejected = 'sessionRejected';
  static const tokenExchange = 'tokenExchange';
  static const invalidTokenResponse = 'invalidTokenResponse';
  static const serverRejection = 'serverRejection';

  /// guardian-bootstrap Stage 1 — the GUARDIAN-only 451 class: the
  /// VPN authorization service refused the request for the
  /// requester's region. Only the Guardian control-plane walk emits
  /// it (the engine-side ClassifyGuardian); FxA / Remote Settings /
  /// any other endpoint keep the generic classes for every status,
  /// 451 included.
  static const guardianRegionUnavailable = 'guardianRegionUnavailable';
  static const unknown = 'unknown';
}

/// The legacy umbrella code the 2026-11-08 field build emits for every
/// exchange-transport failure (observed in the owner's logcat, line 43649:
/// `engine failed (exchangeFailed): oauth token request: Post "https://…":
/// dial tcp: lookup … on [::1]:53: … connection refused`). Kept compatible
/// forever — installed engines must keep working across the upgrade.
const String _legacyExchangeFailed = 'exchangeFailed';

/// The normalized, UI-safe failure produced by [FirefoxErrors.classify].
class FirefoxFailure {
  const FirefoxFailure({
    required this.code,
    this.httpStatus = 0,
    this.retryable = false,
    this.legacy = false,
  });

  /// One of [FirefoxTransportError] — NEVER a free-form engine string.
  final String code;

  /// The REAL HTTP status when the failure was HTTP-level (401/403/400/
  /// 503…); 0 for transport-level failures. Passthrough from the engine.
  final int httpStatus;

  /// UI policy: worth offering "try again".
  final bool retryable;

  /// True when the code came from a pre-Phase-B engine (the umbrella
  /// `exchangeFailed`) — the class is the safe generalization of it.
  final bool legacy;

  @override
  String toString() =>
      'FirefoxFailure($code, httpStatus=$httpStatus, retryable=$retryable'
      '${legacy ? ', legacy' : ''})';
}

abstract final class FirefoxErrors {
  /// Maps an engine `failCode` (plus the optional Phase B extras) to the
  /// normalized failure. Never throws; unknown/empty codes → the unknown
  /// class so the UI can render the generic safe text.
  static FirefoxFailure classify(
    String failCode, {
    int httpStatus = 0,
    bool? retryable,
  }) {
    switch (failCode) {
      case FirefoxTransportError.dnsError:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? true,
        );
      case FirefoxTransportError.networkUnavailable:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? false,
        );
      case FirefoxTransportError.timeout:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? true,
        );
      case FirefoxTransportError.tlsError:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? false,
        );
      case FirefoxTransportError.sessionRejected:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? false,
        );
      case FirefoxTransportError.tokenExchange:
      case _legacyExchangeFailed: // the 2026-11-08 field contract
        return FirefoxFailure(
          code: FirefoxTransportError.tokenExchange,
          httpStatus: httpStatus,
          retryable: retryable ?? true,
          legacy: failCode == _legacyExchangeFailed,
        );
      case FirefoxTransportError.invalidTokenResponse:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? false,
        );
      case FirefoxTransportError.serverRejection:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? (httpStatus >= 500),
        );
      case FirefoxTransportError.guardianRegionUnavailable:
        return FirefoxFailure(
          code: failCode,
          httpStatus: httpStatus,
          retryable: retryable ?? false,
        );
      default:
        // Unknown / empty / future codes: the generic class. The code
        // itself is not surfaced to the UI.
        return FirefoxFailure(
          code: FirefoxTransportError.unknown,
          httpStatus: httpStatus,
          retryable: retryable ?? false,
        );
    }
  }

  /// The static English diagnostic for the adapter's failure seam (the
  /// details sheet text). Safe by construction: no host, no port, no raw
  /// chain, no token. The PERSIAN user-facing text lives in the l10n
  /// table (AppStrings.firefoxErrorText) keyed by the same class.
  static String diagnostic(FirefoxFailure f) {
    switch (f.code) {
      case FirefoxTransportError.dnsError:
        return f.legacy
            ? 'the sign-in exchange failed (legacy engine code) — most '
                'often the device cannot resolve the account server name'
            : 'the device could not resolve the account server name (DNS)';
      case FirefoxTransportError.networkUnavailable:
        return 'the account server could not be reached';
      case FirefoxTransportError.timeout:
        return 'the account server took too long to respond';
      case FirefoxTransportError.tlsError:
        return 'a secure connection to the account server could not be '
            'established';
      case FirefoxTransportError.sessionRejected:
        return 'the session was rejected by the account server'
            '${f.httpStatus > 0 ? ' (HTTP ${f.httpStatus})' : ''}';
      case FirefoxTransportError.tokenExchange:
        return 'the sign-in exchange failed';
      case FirefoxTransportError.invalidTokenResponse:
        return 'the account server returned an invalid token response';
      case FirefoxTransportError.serverRejection:
        return 'the account server rejected the request'
            '${f.httpStatus > 0 ? ' (HTTP ${f.httpStatus})' : ''}';
      case FirefoxTransportError.guardianRegionUnavailable:
        return 'the Firefox VPN authorization service is not available '
            'in this region'
            '${f.httpStatus > 0 ? ' (Guardian HTTP ${f.httpStatus})' : ''}';
      default:
        return 'the sign-in exchange failed for an unknown reason';
    }
  }

  /// Part 3 — the OAuth pair guard, Dart side (defense in depth behind
  /// the engine's own Go guard; docs/phaseb-engine-patch/).
  ///
  /// "Valid" means: both [access] and [refresh] are non-null, of type
  /// String, non-empty, and not whitespace-only. Returns null when the
  /// pair is valid; otherwise the static, value-free reason (mirrors the
  /// Go guard's wording — safe to log).
  static String? invalidPairReason(Object? access, Object? refresh) {
    String? one(Object? v, String field) {
      if (v == null) return 'field "$field" is missing';
      if (v is! String) return 'field "$field" is not a string';
      if (v.isEmpty) return 'field "$field" is empty';
      if (v.trim().isEmpty) return 'field "$field" is blank (whitespace only)';
      return null;
    }

    return one(access, 'accessToken') ?? one(refresh, 'refreshToken');
  }

  /// Strips token-shaped values from a diagnostics line before it reaches
  /// the log sink (the Phase B secrecy rule; the engine side redacts its
  /// own chain — this is the Dart-side belt and braces for anything the
  /// app itself formats).
  ///
  /// Masks: 32+ hex runs (session tokens), 40+ base64ish runs (OAuth
  /// access/refresh tokens), and explicit `token=`/`session=` fragments.
  static final RegExp _hexRun = RegExp(r'[0-9a-fA-F]{32,}');
  static final RegExp _b64Run = RegExp(r'[A-Za-z0-9+/_-]{40,}');

  static String redactLine(String line) {
    var out = line;
    out = out.replaceAllMapped(_hexRun, (_) => '<redacted>');
    out = out.replaceAllMapped(_b64Run, (_) => '<redacted>');
    return out;
  }
}
