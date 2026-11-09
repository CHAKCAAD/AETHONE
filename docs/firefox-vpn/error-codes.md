# Error Codes — the classified failure chain

Implementation: `phase1/fxv/internal/fferr/classify.go` (Go) +
`lib/connection/firefox/firefox_errors.dart` (Dart mapping). The
Phase-B patch package (`docs/phaseb-engine-patch/`) is now integrated
in the REAL engine source — the docs folder remains as the historical
record only.

## 1. The taxonomy

```text
dnsError             networkUnavailable   timeout
tlsError             sessionRejected      tokenExchange
invalidTokenResponse serverRejection     unknown
```

Legacy (still recognized): `exchangeFailed`.

Optional fields on the emitted event:

```json
{ "retryable": true, "httpStatus": 503 }
```

## 2. Classification by error TYPE — never string matching

`fferr.Classify` uses `errors.As` against the real Go error types:

| Type / condition | Classification |
|---|---|
| `*net.DNSError` (however deeply wrapped) | `dnsError` |
| `*tls.CertificateVerificationError`, `*x509.UnknownAuthorityError`, `*x509.HostnameError` | `tlsError` |
| `*net.OpError` (network-level failures) | `networkUnavailable` |
| `net.Error` with `Timeout()`, `context.DeadlineExceeded` | `timeout` |
| remaining transport errors | `networkUnavailable` / `unknown` |

DNS is matched FIRST because the 2026-11-08 field chain was
`url.Error → OpError(dial) → DNSError → OpError(read udp … refused)` —
`errors.As` must hit the `DNSError` regardless of wrap depth. A DNS
error is never mis-reported as `sessionRejected`, and no error is ever
classified by grepping its text.

## 3. HTTP mapping

| Status | Classification | Notes |
|---|---|---|
| 401 / 403 | `sessionRejected` | the server rejected the credentials/session |
| other 4xx | `serverRejection` (or `tokenExchange` on the token endpoint) | `retryable: false` |
| 5xx | `serverRejection` with `retryable: true` | transient server-side failure |

`httpStatus` rides the event whenever a real status exists.
`retryable` is derived from the error's actual semantics, never
blanket-set.

## 4. Where each code is produced

* `invalidTokenResponse` — the OAuth pair guard
  ([oauth-contract.md](oauth-contract.md)).
* `tokenExchange` — the `--login` OAuth exchange chain.
* `sessionTokenInvalid` / `loginModeUnsupported` — the login role's
  own rejections (token shape / mode), keeping the tunnel's
  `badConfig` umbrella clean.
* `badConfig` details ride the message: `configVersionMismatch`,
  `socksListenNotLoopback`, `guardianNotHttps`, `transportUnknown`,
  `authAccessTokenMissing`, `configNotJSON`, `upstreamOverrideInvalid`.

## 5. Log security

None of the following ever appear in stdout/stderr/logcat events:

```text
session tokens · access tokens · refresh tokens ·
HAWK credentials · any sensitive OAuth material
```

Messages are static English; dynamic detail is limited to codes,
hosts and statuses. Both sides' test suites carry sentinel-redaction
checks.

## 6. Test status

Classification, HTTP mapping, legacy and redaction tests: recorded
green 2026-11-09 (prior session, Go 85/85). Corrective session:
**NOT RUN — OWNER REQUEST**.
