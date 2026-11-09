# PHASE B — the engine-side error classification + token guard (Go patch)

Status: **the logic is COMPLETE and test-verified here** (`go test ./...`
in `fferr/` — 7/7 PASS, including a REAL end-to-end replay of the
owner's 2026-11-08 `exchangeFailed` DNS chain). **NOT yet applied to the
engine source**: the `fxv` engine tree (upstream core pin
`55ad91a2ccea1c93e69c82a08a7681e279884db5` + `cmd/libfirefoxvpn`) lives
OUTSIDE this repo and was not present in the Phase B workspace, so this
package is the drop-in patch + its tests, ready for the engine rebuild
session. The DART half of the contract is already applied and green in
this repo (see below).

## 1. What this fixes (the Phase B Part 2 + Part 3 decree)

The 2026-11-08 field build (logcat line 43649, package
`com.chakcaad.aethone.da`) reported the login exchange failure as the
umbrella code with the RAW Go chain as the message:

```
engine failed (exchangeFailed): oauth token request: Post
"https://api.accounts.firefox.com/v1/oauth/token": dial tcp: lookup
api.accounts.firefox.com on [::1]:53: read udp [::1]:37265->[::1]:53:
read: connection refused
```

Part 2 replaces the umbrella with granular, TYPE-BASED classes (DNS /
network unavailable / timeout / TLS / session rejected / token exchange /
invalid token response / server rejection / unknown — always via
`errors.As`/`errors.Is`, NEVER string matching), carries the REAL HTTP
status code on HTTP-level failures, and keeps the raw chain for the
engine log only. Part 3 gates "success" on a well-formed OAuth pair
(both tokens present, JSON strings, non-empty, non-blank — no invented
token format).

## 2. The wire contract (additive; EngineVersion 1.2.0-phaseb)

`failed` events gain two OPTIONAL fields; nothing existing is renamed
or removed (installed 1.1.0-phase2 engines keep working — the Dart side
maps `exchangeFailed` to the token-exchange class forever):

```json
{"event":"failed","failCode":"dnsError","httpStatus":0,
 "retryable":true,"message":"<raw Go chain — engine log only>"}
```

* `failCode` — one of `dnsError|networkUnavailable|timeout|tlsError|
  sessionRejected|tokenExchange|invalidTokenResponse|serverRejection|
  unknown` (the legacy single-word codes remain valid).
* `httpStatus` — the real status code when a response arrived (401/403 →
  `sessionRejected`; 4xx → `serverRejection` non-retryable; 5xx →
  `serverRejection` retryable).
* `retryable` — the engine's retry hint.
* `message` — the static English text (Dart localizes by code; the raw
  chain goes to stderr via `Classified.Internal`).

The Dart consumer of this contract is already in this repo:
`lib/connection/firefox/firefox_errors.dart` (+ the extended
`firefox_protocol.dart` parser, the classified adapter seam, the login
screen's per-class texts) — covered by `test/firefox_errors_test.dart`.

## 3. Placement in the engine (the rebuild session's checklist)

1. Copy the `fferr/` package into the engine tree as
   `internal/fferr` (module path adjusted; `classify.go` + `token.go`
   verbatim, tests included).
2. In `cmd/libfirefoxvpn/login.go` (the `--login` role's exchange walk):
   * wrap the `http.Client.Do/Post` error with
     `fferr.ClassifyTransport(err)` and emit the classified `failed`
     event (`failCode`/`httpStatus`/`retryable` + the static message);
     the raw chain goes to the engine's stderr log via
     `.Redact(sessionToken, …)` — never into the event;
   * on an HTTP response, use `fferr.ClassifyHTTP(resp.StatusCode, body)`;
   * replace the raw token-response parse with
     `fferr.ValidateTokenResponse(body)` — a `*fferr.GuardError` emits
     the `invalidTokenResponse` event (never a success).
3. The connect-role exchange paths (`internal/engine/…`) take the same
   two wrappers at their transport/HTTP decision points.
4. Keep the 1.1.0 event field names exactly (additive change only).
5. **Build config — the A1 decree (2026-11-08, real-device verified):
   the ARM64 Android binary is built with CGO** (`CGO_ENABLED=1`,
   `GOOS=android`, `GOARCH=arm64`,
   `CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android34-clang`)
   — this is what routes DNS through the Android system resolver instead
   of Go's pure resolver talking to the dead `[::1]:53`. Rebuilding with
   `CGO_ENABLED=0` for arm64 would regress the real login (the exact
   failure this patch classifies). armeabi-v7a / x86_64 already build
   with the NDK clang toolchain; the host build stays pure Go.
6. Re-run: `go vet ./...` + `go test ./...` in the engine tree, then the
   3-ABI rebuild (`phase1/scripts/build_engine.sh`), ELF inspection, and
   the jniLibs re-deploy (hash-verified ≡ build) — the Phase 2 recipe.

## 4. Evidence (this repo copy, 2026-11-09)

```
$ cd docs/phaseb-engine-patch/fferr && go vet ./... && go test ./... -count=1 -v
vet: OK
TestNov8ChainReplay   PASS — the exact 2026-11-08 chain replayed over a
                        REAL [::1]:53 refusal → dnsError, retryable=true
TestTimeoutReal       PASS — real 300 ms client timeout → timeout
TestTLSReal           PASS — real self-signed rejection → tlsError
TestNetworkRefusedReal PASS — real TCP refusal (127.0.0.1:1) → networkUnavailable
TestHTTPStatuses      PASS — 401/403 → sessionRejected; 400 → serverRejection
                        (non-retryable); 500/503 → serverRejection (retryable);
                        real status codes carried
TestTokenGuard        PASS — 8 rejection cases + the valid acceptance
TestNoLeak            PASS — sentinel tokens never appear in any
                        classified/guard payload; Redact leaves markers
TestUnknownAndFallback PASS — unknown → unknown; OpError → networkUnavailable
```

The Dart-side mirror of every rule above is applied and green in this
branch (`flutter analyze` clean; the full suite passes — see
`FIREFOX_VPN_PHASEB_REPORT.md` §E).
