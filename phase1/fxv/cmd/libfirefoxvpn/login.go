package main

// The --login role (Phase 2) — the FxA WebChannel login exchange,
// rebuilt 2026-11-09 with the PHASE B classification + pair guard
// integrated (docs/phaseb-engine-patch applied to the real engine
// path, per its README §3):
//
//   - transport-level failures classify through fferr.ClassifyTransport
//     (TYPE-BASED errors.As — dnsError / networkUnavailable / timeout /
//     tlsError / tokenExchange / unknown);
//   - HTTP-level failures carry the REAL status through
//     fferr.ClassifyHTTP (401/403 → sessionRejected; 4xx →
//     serverRejection non-retryable; 5xx → retryable);
//   - the minted pair passes the Part 3 guard (both tokens present,
//     non-empty, non-blank) BEFORE loginCompleted is emitted — anything
//     else is the invalidTokenResponse failure;
//   - the unverified-session retry (FxA errno 104/138 — the user has
//     not confirmed the sign-in email yet) loops inside the verify
//     budget with loginRetry events; errno 102/110/108 is the
//     definitive sessionRejected;
//   - stdin EOF is the CLEAN CANCEL (exit 0) — it aborts even an
//     in-flight exchange call.
//
// The errno seam: the pinned upstream does not export its fxaAPIError
// type, so the FxA application errno rides the error text; extracting
// it here is the ONE string-adjacent seam and it is deliberately NOT
// part of the Phase B transport classification (which stays
// type-based). See ORIGIN.md.

import (
        "bufio"
        "context"
        "errors"
        "fmt"
        "io"
        "os"
        "strconv"
        "strings"
        "sync"
        "time"

        vpnclient "firefox-vpn-client"

        "aethone/fxv/internal/engine"
        "aethone/fxv/internal/fferr"
        "aethone/fxv/internal/redact"
        "aethone/fxv/internal/relay"
)

// FxA application errnos (the upstream's observed semantics).
const (
        fxaErrnoUnknownAccount    = 102 // the token/account was refused
        fxaErrnoInvalidParameter  = 107
        fxaErrnoInvalidToken      = 110
        fxaErrnoRequestWithoutTok = 108
        fxaErrnoUnverifiedSession = 104 // retry — the email is unconfirmed
        fxaErrnoUnverifiedAccount = 138 // retry — same family
)

func runLogin() int {
        emit := engine.NewEmitter()

        // 1. the config line (the ONLY secret carrier — the session token).
        line, err := readLineBounded(os.Stdin)
        if err != nil {
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
                        Message: "configNotJSON", Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }
        cfg, err := engine.ParseLoginConfig(line)
        if err != nil {
                var cfgErr *engine.ConfigError
                detail := "configNotJSON"
                if errors.As(err, &cfgErr) {
                        detail = cfgErr.DetailCode()
                }
                // The login role's own failure codes (docs/FIREFOX_VPN_LOGIN.md
                // §3): the token-shape and mode rejections are THEIR OWN codes,
                // never the tunnel role's badConfig umbrella. The message is the
                // static English text (the Dart UI localizes by code and never
                // renders it).
                failCode := engine.ErrBadConfig
                message := detail
                switch detail {
                case "sessionTokenInvalid":
                        failCode = engine.ErrSessionTokenInvalid
                        message = "the session token must be exactly 64 hexadecimal characters"
                case "loginModeUnsupported":
                        failCode = engine.ErrLoginModeUnsupported
                        message = "this login mode is not supported (password mode is reserved and refused)"
                }
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: failCode,
                        Message: message, Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }

        _ = emit.Emit(engine.Event{
                Name:     engine.EvLoginStarted,
                LoginMode: cfg.Mode,
                Message:  engine.EngineVersion,
                PID:      os.Getpid(),
        })

        logf := func(format string, args ...any) {
                fmt.Fprintf(os.Stderr, "%s", "login: "+redact.Line(fmt.Sprintf(format, args...), cfg.SessionToken)+"\n")
        }

        // 1b. the control-plane relay stack (contract 1.3.0-relay) — the
        // login walk's control-plane host is Firefox Accounts, so this
        // is the PERSONAL layer's unreachability coverage (the
        // Guardian-scoped layers stay dormant during a login).
        // Installed before the first exchange request.
        restoreRelay := relay.Install(relay.Options{
                PersonalRelay:   cfg.Relay.PersonalURL,
                PersonalEnabled: cfg.Relay.PersonalEnabled,
                SharedEnabled:   cfg.Relay.SharedEnabled,
                ECHMode:         cfg.Relay.ECHMode,
                ECHConfig:       cfg.Relay.ECHConfig,
                Logf:            logf,
        })
        defer restoreRelay()

        // 2. the exchange walk with the verify budget + the clean cancel.
        ctx, cancel := context.WithCancel(context.Background())
        defer cancel()
        stdinDone := watchLoginStdinClose(ctx)

        budget := time.Duration(cfg.VerifyTimeoutMs) * time.Millisecond
        deadline := time.After(budget)
        retryDelay := time.Duration(cfg.RetryDelayMs) * time.Millisecond

        attempt := 0
        for {
                attempt++
                exchangeCh := make(chan *vpnclient.TokenResponse, 1)
                errCh := make(chan error, 1)
                go func() {
                        tok, err := vpnclient.FxaOAuthToken(ctx, cfg.SessionToken)
                        if tok != nil {
                                exchangeCh <- tok
                        }
                        errCh <- err
                }()

                select {
                case <-stdinDone:
                        // CLEAN CANCEL: the user backed out; abort the in-flight call.
                        cancel()
                        _ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "cancelled"})
                        _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "cancelled"})
                        return engine.ExitClean

                case <-deadline:
                        cancel()
                        _ = emit.Emit(engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrLoginTimeout,
                                Message: fferr.Classified{Message: "The sign-in was not confirmed in time"}.Message,
                                Code:    engine.ExitStartup,
                        })
                        return engine.ExitStartup

                case tok := <-exchangeCh:
                        if err := <-errCh; err == nil && tok != nil {
                                return loginSuccess(emit, tok)
                        }

                case err := <-errCh:
                        if err == nil {
                                // unreachable (tok handled above); guard anyway
                                <-exchangeCh
                                continue
                        }
                        class, retry, terminal := classifyLoginError(err)
                        if terminal != "" {
                                ev := failedFrom(engine.ErrExchangeFailed, class.Redact(cfg.SessionToken), engine.ExitStartup)
                                ev.FailCode = terminal
                                _ = emit.Emit(ev)
                                logf("exchange failed: %s", err)
                                return engine.ExitStartup
                        }
                        if !retry {
                                ev := failedFrom(engine.ErrExchangeFailed, class.Redact(cfg.SessionToken), engine.ExitStartup)
                                _ = emit.Emit(ev)
                                logf("exchange failed: %s", err)
                                return engine.ExitStartup
                        }
                        // retryable (unverified session / transport retryable):
                        // log the honest retry and loop.
                        _ = emit.Emit(engine.Event{
                                Name:      engine.EvLoginRetry,
                                Attempt:   attempt,
                                RetryInMs: retryDelay.Milliseconds(),
                        })
                        logf("exchange not confirmed yet (attempt %d): %s", attempt, err)
                        select {
                        case <-stdinDone:
                                cancel()
                                _ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "cancelled"})
                                _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "cancelled"})
                                return engine.ExitClean
                        case <-time.After(retryDelay):
                        }
                }
        }
}

// loginSuccess applies the Part 3 pair guard and emits loginCompleted
// ONLY for a well-formed pair.
func loginSuccess(emit *engine.Emitter, tok *vpnclient.TokenResponse) int {
        if guardErr := guardParsedPair(tok.AccessToken, tok.RefreshToken); guardErr != nil {
                class := guardErr.Classified()
                ev := failedFrom(engine.ErrExchangeFailed, class, engine.ExitStartup)
                _ = emit.Emit(ev)
                fmt.Fprintf(os.Stderr, "login: %s\n", class.Internal)
                return engine.ExitStartup
        }
        _ = emit.Emit(engine.Event{
                Name:          engine.EvLoginCompleted,
                AccessToken:   tok.AccessToken,
                RefreshToken:  tok.RefreshToken,
                ExpiresIn:     tok.ExpiresIn,
                ObtainedAt:    time.Now().UTC().Format(time.RFC3339),
        })
        _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "completed"})
        return engine.ExitClean
}

// guardParsedPair is the parsed-struct port of fferr.ValidateTokenResponse:
// the pinned upstream's FxaOAuthToken returns the PARSED TokenResponse
// (the audited exchange path — forking it to reach the raw body is
// forbidden), so the Part 3 rules apply to the parsed fields. The
// JSON-string typing is guaranteed by the upstream's own json.Unmarshal
// (a wrong-typed field fails the parse there and arrives here as an
// exchange error → invalidTokenResponse); empty/blank/missing are
// guarded here. No token format is invented or checked.
func guardParsedPair(access, refresh string) *fferr.GuardError {
        switch {
        case strings.TrimSpace(access) == "" && strings.TrimSpace(refresh) == "":
                return &fferr.GuardError{Reason: "both tokens are missing or blank"}
        case strings.TrimSpace(access) == "":
                return &fferr.GuardError{Reason: "access_token is missing or blank"}
        case strings.TrimSpace(refresh) == "":
                return &fferr.GuardError{Reason: "refresh_token is missing or blank"}
        }
        return nil
}

// classifyLoginError maps one exchange failure to (class, retryable,
// terminal failCode). terminal != "" means a definitive failure code
// (sessionRejected) that overrides the umbrella; retry requests the
// verify-budget loop (unverified session / retryable transport).
func classifyLoginError(err error) (class fferr.Classified, retry bool, terminal string) {
        if err == nil {
                return fferr.Classified{}, false, ""
        }

        // Transport-level first — TYPE-BASED (errors.As inside fferr).
        transport := fferr.ClassifyTransport(err)
        switch transport.Code {
        case fferr.CodeDNS, fferr.CodeTimeout:
                return transport, true, ""
        case fferr.CodeNetworkUnreach, fferr.CodeTLS, fferr.CodeTokenExchange:
                return transport, transport.Retryable, ""
        case fferr.CodeUnknown:
                // fall through to the FxA application seam below
        default:
                return transport, false, ""
        }

        // FxA application level: the errno seam (the pinned upstream does
        // not export fxaAPIError; the errno rides the error text — the one
        // documented string-adjacent seam, NOT the transport classifier).
        errno, hasErrno := fxaErrno(err.Error())
        if hasErrno {
                switch errno {
                case fxaErrnoUnverifiedSession, fxaErrnoUnverifiedAccount:
                        return fferr.Classified{
                                Code:     fferr.CodeTokenExchange,
                                Message:  "The sign-in exchange failed",
                                Internal: err.Error(),
                        }, true, ""
                case fxaErrnoUnknownAccount, fxaErrnoInvalidToken, fxaErrnoRequestWithoutTok:
                        return fferr.Classified{
                                Code:     fferr.CodeSessionRejected,
                                Message:  "The session was rejected by the account server",
                                Internal: err.Error(),
                        }, false, engine.ErrSessionRejected
                }
        }

        // HTTP-level classification with the REAL status.
        if status, ok := fxaHTTPStatus(err.Error()); ok {
                httpClass := fferr.ClassifyHTTP(status, nil)
                httpClass.Internal = err.Error()
                if status == httpStatusUnauthorized || status == httpStatusBadRequest {
                        // 400/401 unconfirmed/unverified — the documented retry pair.
                        httpClass.Code = fferr.CodeTokenExchange
                        httpClass.Message = "The sign-in exchange failed"
                        return httpClass, true, ""
                }
                return httpClass, httpClass.Retryable, ""
        }

        // The honest unknown.
        unknown := fferr.ClassifyTransport(err)
        unknown.Code = fferr.CodeUnknown
        unknown.Message = "Something went wrong"
        return unknown, false, ""
}

const (
        httpStatusBadRequest  = 400
        httpStatusUnauthorized = 401
)

// fxaErrno extracts "errno %d" from the upstream's fxaAPIError text
// ("FxA error (HTTP %d, errno %d): %s").
func fxaErrno(s string) (int, bool) {
        idx := strings.Index(s, "errno ")
        if idx < 0 {
                return 0, false
        }
        rest := s[idx+len("errno "):]
        end := 0
        for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' {
                end++
        }
        if end == 0 {
                return 0, false
        }
        n, err := strconv.Atoi(rest[:end])
        if err != nil {
                return 0, false
        }
        return n, true
}

// fxaHTTPStatus extracts "HTTP %d" from the upstream's fxaAPIError
// text ("FxA error (HTTP %d, errno %d)" / "FxA request failed (HTTP %d)").
func fxaHTTPStatus(s string) (int, bool) {
        idx := strings.Index(s, "HTTP ")
        if idx < 0 {
                return 0, false
        }
        rest := s[idx+len("HTTP "):]
        end := 0
        for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' {
                end++
        }
        if end == 0 {
                return 0, false
        }
        n, err := strconv.Atoi(rest[:end])
        if err != nil {
                return 0, false
        }
        return n, true
}

// readLineBounded reads ONE line (bounded by the 1 MiB config-line
// limit; the buffer carrying the session token is dropped by the
// caller after the parse).
func readLineBounded(f *os.File) ([]byte, error) {
        br := bufio.NewReader(io.LimitReader(f, maxLoginLine))
        line, err := br.ReadString('\n')
        if err != nil && err != io.EOF {
                return nil, err
        }
        line = strings.TrimRight(line, "\r\n")
        if line == "" {
                return nil, io.EOF
        }
        return []byte(line), nil
}

// maxLoginLine bounds the login config line (same 1 MiB contract).
const maxLoginLine = 1 << 20

// watchLoginStdinClose resolves on stdin EOF (the clean cancel).
func watchLoginStdinClose(ctx context.Context) <-chan struct{} {
        done := make(chan struct{})
        var once sync.Once
        trigger := func() { once.Do(func() { close(done) }) }
        go func() {
                buf := make([]byte, 1)
                for {
                        n, err := os.Stdin.Read(buf)
                        if n > 0 && err == nil {
                                continue
                        }
                        trigger()
                        return
                }
        }()
        go func() {
                <-ctx.Done()
                trigger()
        }()
        return done
}
