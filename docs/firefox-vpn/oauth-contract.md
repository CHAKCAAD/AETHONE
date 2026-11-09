# OAuth Contract — the token pair guard

Implementation: `phase1/fxv/internal/fferr/token.go` (Go) +
`lib/connection/firefox/firefox_login.dart` (Dart guards).

## 1. What a valid pair is

A successful OAuth exchange MUST carry BOTH fields:

```text
access_token   — present, a JSON string, non-empty, not whitespace-only
refresh_token  — present, a JSON string, non-empty, not whitespace-only
```

* Field names `access_token` / `refresh_token` follow the FxA OAuth
  response shape.
* JSON `null` is handled explicitly (a `null` value is invalid, not a
  crash).
* **No token format, length or pattern is invented or assumed** —
  presence and non-blankness are the whole contract.

## 2. On violation

The guard classifies the response as:

```text
invalidTokenResponse
```

— an ordinary `failed` classification like any other; the engine
emits the event, never crashes, and the pair is treated as absent.

## 3. Dart-side guards (`loginCompleted` / `authRefreshed`)

The Dart login manager independently validates the pair before
accepting either event:

* An incomplete pair is NEVER treated as success.
* A healthy pair is NEVER rejected without cause.
* A corrupt/malformed engine response never crashes the app.
* **The vault is never overwritten by an invalid pair** — a valid
  stored pair survives a failed refresh/login round.
* Legacy codes (below) remain supported.

## 4. Legacy compatibility

The pre-phase-B code:

```text
exchangeFailed
```

is still recognized on the Dart side, alongside the new taxonomy.
Unknown codes map safely to a generic failure — never to
`sessionRejected` or `dnsError`.

## 5. Security rules (unchanged)

* Tokens NEVER in argv, NEVER in the child environment
  (`includeParentEnvironment: false`), NEVER in logs, NEVER in UI
  error messages.
* The pair reaches the engine only through the private stdin pipe.
* At rest: Android Keystore AES/GCM ciphertext only
  (`docs/FIREFOX_VPN_SECURITY.md`).
* Redaction sentinels cover tokens in both Go and Dart test suites.

## 6. Test status

* Go/Dart/Flutter OAuth-pair tests: recorded green 2026-11-09 (prior
  session: missing field, null, wrong type, empty string,
  whitespace-only, vault protection, legacy code).
* Corrective session: **NOT RUN — OWNER REQUEST**.
