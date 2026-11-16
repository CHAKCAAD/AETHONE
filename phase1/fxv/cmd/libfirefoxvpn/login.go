package main

// The --login role — the FxA login exchanges.
//
// TWO modes share this role (the config line's `mode` picks; the
// default stays webchannel so a 1.7.0 host is byte-compatible):
//
//   - webchannel (Phase 2, unchanged): the session token captured by
//     the sign-in WebView is exchanged for the same-account OAuth pair.
//     Rebuilt 2026-11-09 with the PHASE B classification + pair guard.
//
//   - password (1.8.0, the owner's round 8 — the arman-vpn-client
//     pattern «از پروژه arman-vpn-client الگو بگیر»): the DIRECT
//     email+password sign-in the reference app drives by DEFAULT. The
//     engine runs the whole FxA password flow itself: FxaLogin (with
//     the email-2fa verification method — the code is EMAILED, not a
//     link), the optional emailed-code step (the loginNeedsCode event
//     asks; the second stdin line answers), then the same OAuth mint
//     the webchannel mode uses. The password rides the stdin pipe
//     ONLY — never argv, never the environment, never a log line
//     (every stderr path scrubs it; deriveAuthPW happens inside the
//     pinned upstream).
//
// Shared disciplines (both modes):
//
//   - transport-level failures classify through fferr.ClassifyTransport
//     (TYPE-BASED errors.As — dnsError / networkUnavailable / timeout /
//     tlsError / tokenExchange / unknown);
//   - HTTP-level failures carry the REAL status through
//     fferr.ClassifyHTTP (401/403 → sessionRejected; 4xx →
//     serverRejection non-retryable; 5xx → retryable);
//   - the minted pair passes the Part 3 guard (both tokens present,
//     non-empty, non-blank) BEFORE loginCompleted is emitted;
//   - the unverified-session retry (FxA errno 104/138) loops inside
//     the verify budget with loginRetry events; errno 102/110/108 is
//     the definitive sessionRejected;
//   - stdin EOF is the CLEAN CANCEL (exit 0) — it aborts even an
//     in-flight call, at ANY wait point of either mode.
//
// The errno seam: the pinned upstream does not export its fxaAPIError
// type, so the FxA application errno rides the error text; extracting
// it here is the ONE string-adjacent seam and it is deliberately NOT
// part of the Phase B transport classification (which stays
// type-based). 1.8.0 extends the seam to the verify-code path (its
// plain error embeds the JSON body — `"errno":N`), documented here.

import (
        "bufio"
        "context"
        "encoding/json"
        "errors"
        "fmt"
        "io"
        "os"
        "strconv"
        "strings"
        "sync"
        "time"

        vpnclient "firefox-vpn-client"

        "aethone/fxv/internal/dnsresolver"
        "aethone/fxv/internal/engine"
        "aethone/fxv/internal/upstream"
        "aethone/fxv/internal/fferr"
        "aethone/fxv/internal/redact"
)

// FxA application errnos (the upstream's observed semantics; the fxa.js
// table is the authority — 102 unknown account, 103 incorrect password,
// 104 unverified account, 105 invalid verification code, 114 throttled,
// 120 incorrect email case, 125/126 the security block family, 142
// secondary-email sign-in, 146 invalid signin code, 149 invalid email
// for login, 153 the expired code).
const (
        fxaErrnoUnknownAccount    = 102 // the token/account was refused
        fxaErrnoIncorrectPassword = 103
        fxaErrnoUnverifiedAcct    = 104 // the ACCOUNT's email was never verified
        fxaErrnoInvalidParameter  = 107
        fxaErrnoInvalidToken      = 110
        fxaErrnoRequestWithoutTok = 108
        fxaErrnoUnverifiedSession = 104 // retry — the email is unconfirmed
        fxaErrnoUnverifiedAccount = 138 // retry — same family
        fxaErrnoInvalidCode       = 105
        fxaErrnoThrottled         = 114
        fxaErrnoEmailCase         = 120
        fxaErrnoRequestBlocked    = 125
        fxaErrnoAccountReset      = 126
        fxaErrnoSecondaryEmail    = 142
        fxaErrnoInvalidSigninCode = 146
        fxaErrnoLoginInvalidEmail = 149
        fxaErrnoCodeExpired       = 153
)

// maxCodeAttempts bounds the WRONG-code re-asks (arman's dialog keeps
// asking; the engine keeps the session but never endlessly — a wrong
// code consumes one of these, a network hiccup does not).
const maxCodeAttempts = 5

// maxCodeLen bounds the submitted code (the emailed codes are 6 digits;
// unblock codes carry letters — anything longer is host garbage).
const maxCodeLen = 16

func runLogin() int {
        emit := engine.NewEmitter()

        // 1. the config line (the ONLY secret carrier on the way in — the
        // session token OR the email+password pair, by mode).
        line, br, err := readLoginLineBounded()
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
                // §3): the token-shape, mode and password-field rejections are
                // THEIR OWN codes, never the tunnel role's badConfig umbrella.
                // The message is the static English text (the Dart UI localizes
                // by code and never renders it).
                failCode := engine.ErrBadConfig
                message := detail
                switch detail {
                case "sessionTokenInvalid":
                        failCode = engine.ErrSessionTokenInvalid
                        message = "the session token must be exactly 64 hexadecimal characters"
                case "loginModeUnsupported":
                        failCode = engine.ErrLoginModeUnsupported
                        message = "this login mode is not supported"
                case "passwordLoginEmailInvalid":
                        failCode = engine.ErrInvalidEmail
                        message = "the email address is not usable for the direct sign-in"
                case "passwordLoginPasswordInvalid":
                        failCode = engine.ErrBadConfig
                        message = "the password is empty, oversized or carries control characters"
                }
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: failCode,
                        Message: message, Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }

        if _, dnsErr := dnsresolver.Install(cfg.DNS); dnsErr != nil {
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
                        Message: "dnsConfigInvalid", Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }
        // 2.0.0 — the reference's hello split for the direct sign-in's
        // control plane.
        vpnclient.SetHelloSplit(cfg.DNS.HelloSplit)

        // 1.5.0 (the owner's round 2) — the WARP-carried exchange: with
        // an upstreamSocks carrier the token exchange dials through the
        // in-process Aether core's SOCKS listener (the pinned Firefox
        // uTLS ClientHello kept; the Fastly edge sees the WARP egress,
        // not the blocked region's). A refused carrier CONNECT now
        // falls back to the direct dial (2.0.0).
        if cfg.UpstreamSocks != "" {
                vpnclient.SetControlPlaneTransport(
                        upstream.NewSOCKS5ControlPlaneTransport(cfg.UpstreamSocks))
        }

        _ = emit.Emit(engine.Event{
                Name:     engine.EvLoginStarted,
                LoginMode: cfg.Mode,
                Message:  engine.EngineVersion,
                PID:      os.Getpid(),
        })

        if cfg.Mode == engine.LoginModePassword {
                return runLoginPassword(emit, cfg, br)
        }
        return runLoginWebChannel(emit, cfg)
}

// runLoginWebChannel is the Phase-2 walk — byte-identical behavior to
// 1.7.0 (extracted verbatim when the password mode joined the role).
func runLoginWebChannel(emit *engine.Emitter, cfg engine.LoginConfig) int {
        logf := func(format string, args ...any) {
                fmt.Fprintf(os.Stderr, "%s", "login: "+redact.Line(fmt.Sprintf(format, args...), cfg.SessionToken)+"\n")
        }

        deadline := time.After(time.Duration(cfg.VerifyTimeoutMs) * time.Millisecond)
        retryDelay := time.Duration(cfg.RetryDelayMs) * time.Millisecond
        stdinDone := watchLoginStdinClose(context.Background())

        return mintWithRetry(emit, cfg.SessionToken, stdinDone, deadline, retryDelay, logf)
}

// loginStdinPump owns the login child's stdin AFTER the config line
// (the password mode): complete lines (the code submissions) are
// forwarded on Lines; Done closes on EOF/error — the clean cancel.
type loginStdinPump struct {
        Lines chan string
        Done  chan struct{}
}

// pumpLoginStdinLines takes over the config-line reader (it may hold
// buffered bytes of an eagerly-written second line — a FRESH reader on
// os.Stdin would lose them) and forwards every subsequent line.
func pumpLoginStdinLines(br *bufio.Reader) *loginStdinPump {
        p := &loginStdinPump{
                Lines: make(chan string, 4),
                Done:  make(chan struct{}),
        }
        go func() {
                defer close(p.Done)
                for {
                        line, err := br.ReadString('\n')
                        if trimmed := strings.TrimRight(line, "\r\n"); trimmed != "" {
                                p.Lines <- trimmed
                        }
                        if err != nil {
                                return
                        }
                }
        }()
        return p
}

// runLoginPassword — the arman-pattern direct sign-in: FxaLogin → the
// optional emailed code (loginNeedsCode + the second stdin line) → the
// OAuth mint. stdin EOF at ANY wait is the clean cancel.
func runLoginPassword(emit *engine.Emitter, cfg engine.LoginConfig, br *bufio.Reader) int {
        // The password's life in this process: the config line's copy
        // (scrubbed from every stderr path below) and the pinned upstream's
        // own argument — deriveAuthPW consumes it there. This copy is
        // dropped the moment the login call returns.
        password := cfg.Password
        cfg.Password = ""
        logf := func(format string, args ...any) {
                fmt.Fprintf(os.Stderr, "%s", "login: "+redact.Line(fmt.Sprintf(format, args...), password, cfg.SessionToken)+"\n")
        }

        ctx, cancel := context.WithCancel(context.Background())
        defer cancel()
        pump := pumpLoginStdinLines(br)
        // The pump's EOF cancels the walk's ctx too — an IN-FLIGHT FxA
        // call (login or verify) aborts instead of stranding the exit
        // until its own budget runs out.
        go func() {
                <-pump.Done
                cancel()
        }()

        budget := time.Duration(cfg.VerifyTimeoutMs) * time.Millisecond
        deadline := time.After(budget)

        // 1. the password login itself (email-2fa: the confirmation code
        // is EMAILED to the account, not a link — a headless client can
        // finish it). Runs async so the CLEAN CANCEL (stdin EOF) fires
        // instantly, exactly like the webchannel exchange walk.
        type loginOutcome struct {
                resp *vpnclient.LoginResponse
                err  error
        }
        loginCh := make(chan loginOutcome, 1)
        go func() {
                resp, err := vpnclient.FxaLogin(ctx, cfg.Email, password)
                loginCh <- loginOutcome{resp, err}
        }()
        var loginResp *vpnclient.LoginResponse
        select {
        case <-pump.Done:
                // CLEAN CANCEL: the user backed out (the ctx watcher
                // already aborted the in-flight call).
                cancel()
                _ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "cancelled"})
                _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "cancelled"})
                return engine.ExitClean
        case <-deadline:
                cancel()
                _ = emit.Emit(engine.Event{
                        Name:     engine.EvFailed,
                        FailCode: engine.ErrLoginTimeout,
                        Message:  fferr.Classified{Message: "The sign-in was not confirmed in time"}.Message,
                        Code:     engine.ExitStartup,
                })
                return engine.ExitStartup
        case outcome := <-loginCh:
                if outcome.err != nil {
                        cancel()
                        ev, code := passwordLoginFailure(outcome.err)
                        ev.Code = engine.ExitStartup
                        _ = emit.Emit(ev)
                        logf("password login failed (%s): %s", code, outcome.err)
                        return engine.ExitStartup
                }
                loginResp = outcome.resp
        }
        password = ""
        logf("password accepted for %s (verified=%v, method=%s)",
                cfg.Email, loginResp.Verified, loginResp.VerificationMethod)

        // 2. the emailed-code step (only when the session landed
        // unverified — a recently-confirmed account skips it). One ask per
        // loop pass; only WRONG/bad submissions consume the attempts cap —
        // a network hiccup re-asks for free (the overall deadline bounds
        // the loop either way).
        sessionToken := loginResp.SessionToken
        submissions := 0
        lastErr := ""
        for !loginResp.Verified {
                if submissions >= maxCodeAttempts {
                        cancel()
                        _ = emit.Emit(engine.Event{
                                Name:    engine.EvFailed,
                                FailCode: engine.ErrCodeAttemptsExhausted,
                                Message: "The code was wrong too many times",
                                Code:    engine.ExitStartup,
                        })
                        return engine.ExitStartup
                }
                _ = emit.Emit(engine.Event{
                        Name:              engine.EvLoginNeedsCode,
                        Email:             cfg.Email,
                        VerificationMethod: loginResp.VerificationMethod,
                        Attempt:           submissions + 1,
                        LastError:         lastErr,
                })
                lastErr = ""

                var codeLine string
                select {
                case <-pump.Done:
                        // EOF — a pending line wins; without one it is the
                        // CLEAN CANCEL (the user backed out).
                        select {
                        case l := <-pump.Lines:
                                codeLine = l
                        default:
                                cancel()
                                _ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "cancelled"})
                                _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "cancelled"})
                                return engine.ExitClean
                        }
                case l := <-pump.Lines:
                        codeLine = l
                case <-deadline:
                        cancel()
                        _ = emit.Emit(engine.Event{
                                Name:     engine.EvFailed,
                                FailCode: engine.ErrLoginTimeout,
                                Message:  fferr.Classified{Message: "The sign-in was not confirmed in time"}.Message,
                                Code:     engine.ExitStartup,
                        })
                        return engine.ExitStartup
                }

                code, ok := parseCodeLine(codeLine)
                if !ok {
                        // Host garbage: consumes the submission (the cap bounds it).
                        logf("code line rejected (bad shape)")
                        submissions++
                        lastErr = "badCodeInput"
                        continue
                }

                if err := vpnclient.FxaVerifySession(ctx, sessionToken, code); err != nil {
                        kind, retryable := classifyVerifyCodeError(err)
                        switch kind {
                        case "wrongCode":
                                logf("verify code rejected (submission %d): %s", submissions+1, err)
                                submissions++
                                lastErr = "wrongCode"
                                continue
                        case "network":
                                if !retryable {
                                        cancel()
                                        ev, c := verifyFailureTerminal(err)
                                        ev.Code = engine.ExitStartup
                                        _ = emit.Emit(ev)
                                        logf("verify failed (%s): %s", c, err)
                                        return engine.ExitStartup
                                }
                                logf("verify code transport failure (re-asking): %s", err)
                                lastErr = "network"
                                continue
                        default:
                                cancel()
                                ev, c := verifyFailureTerminal(err)
                                ev.Code = engine.ExitStartup
                                _ = emit.Emit(ev)
                                logf("verify failed (%s): %s", c, err)
                                return engine.ExitStartup
                        }
                }
                loginResp.Verified = true
                logf("session verified by the emailed code")
        }

        // 3. the mint — the SAME retry walk the webchannel mode runs.
        return mintWithRetry(emit, sessionToken, pump.Done, deadline,
                time.Duration(cfg.RetryDelayMs)*time.Millisecond, logf)
}

// mintWithRetry runs the FxaOAuthToken exchange with the verify budget,
// the unverified-session retry and the clean cancel — shared by both
// login modes (extracted verbatim from the 1.7.0 webchannel walk).
func mintWithRetry(
        emit *engine.Emitter,
        sessionToken string,
        cancelCh <-chan struct{},
        deadline <-chan time.Time,
        retryDelay time.Duration,
        logf func(string, ...any),
) int {
        ctx, cancel := context.WithCancel(context.Background())
        defer cancel()

        attempt := 0
        for {
                attempt++
                exchangeCh := make(chan *vpnclient.TokenResponse, 1)
                errCh := make(chan error, 1)
                go func() {
                        tok, err := vpnclient.FxaOAuthToken(ctx, sessionToken)
                        if tok != nil {
                                exchangeCh <- tok
                        }
                        errCh <- err
                }()

                select {
                case <-cancelCh:
                        // CLEAN CANCEL: the user backed out; abort the in-flight call.
                        cancel()
                        _ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "cancelled"})
                        _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "cancelled"})
                        return engine.ExitClean

                case <-deadline:
                        cancel()
                        _ = emit.Emit(engine.Event{
                                Name:     engine.EvFailed,
                                FailCode: engine.ErrLoginTimeout,
                                Message:  fferr.Classified{Message: "The sign-in was not confirmed in time"}.Message,
                                Code:     engine.ExitStartup,
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
                                ev := failedFrom(engine.ErrExchangeFailed, class.Redact(sessionToken), engine.ExitStartup)
                                ev.FailCode = terminal
                                _ = emit.Emit(ev)
                                logf("exchange failed: %s", err)
                                return engine.ExitStartup
                        }
                        if !retry {
                                ev := failedFrom(engine.ErrExchangeFailed, class.Redact(sessionToken), engine.ExitStartup)
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
                        case <-cancelCh:
                                cancel()
                                _ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "cancelled"})
                                _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "cancelled"})
                                return engine.ExitClean
                        case <-time.After(retryDelay):
                        }
                }
        }
}

// passwordLoginFailure maps one FxaLogin failure to its failed event
// (the granular arman SignInError codes; the transport classes ride the
// existing classifier) plus the short code for the stderr line.
func passwordLoginFailure(err error) (engine.Event, string) {
        // Transport-level first (type-based — a REAL net/tls/url failure;
        // the FxA application errors classify Unknown and fall to the seam).
        transport := fferr.ClassifyTransport(err)
        switch transport.Code {
        case fferr.CodeDNS, fferr.CodeTimeout, fferr.CodeNetworkUnreach,
                fferr.CodeTLS, fferr.CodeTokenExchange:
                return failedFrom(engine.ErrExchangeFailed, transport, engine.ExitStartup), string(transport.Code)
        }

        // FxA application level: the errno seam.
        errno, hasErrno := fxaErrno(err.Error())
        if hasErrno {
                switch errno {
                case fxaErrnoUnknownAccount:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrNoAccount,
                                Message: "No Firefox Account has this email",
                        }, engine.ErrNoAccount
                case fxaErrnoIncorrectPassword:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrWrongPassword,
                                Message: "The password is incorrect",
                        }, engine.ErrWrongPassword
                case fxaErrnoUnverifiedAcct, fxaErrnoUnverifiedAccount:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrUnverifiedAccount,
                                Message: "The account's email has not been verified yet",
                        }, engine.ErrUnverifiedAccount
                case fxaErrnoThrottled:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrTooManyAttempts,
                                Message: "Too many attempts; try again later",
                        }, engine.ErrTooManyAttempts
                case fxaErrnoEmailCase:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrEmailCaseInvalid,
                                Message: "The email's letter case does not match the account",
                        }, engine.ErrEmailCaseInvalid
                case fxaErrnoRequestBlocked, fxaErrnoAccountReset:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrRequestBlocked,
                                Message: "The sign-in was blocked for security reasons",
                        }, engine.ErrRequestBlocked
                case fxaErrnoSecondaryEmail:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrSecondaryEmail,
                                Message: "The primary account email is required for sign-in",
                        }, engine.ErrSecondaryEmail
                case fxaErrnoLoginInvalidEmail:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrInvalidEmail,
                                Message: "This email cannot be used to sign in",
                        }, engine.ErrInvalidEmail
                case fxaErrnoInvalidToken, fxaErrnoRequestWithoutTok, fxaErrnoInvalidParameter:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrSessionRejected,
                                Message: "The session was rejected by the account server",
                        }, engine.ErrSessionRejected
                }
        }

        // HTTP-level with the REAL status.
        if status, ok := fxaHTTPStatus(err.Error()); ok {
                httpClass := fferr.ClassifyHTTP(status, nil)
                httpClass.Internal = err.Error()
                if status == httpStatusTooManyRequests {
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrTooManyAttempts,
                                Message: "Too many attempts; try again later",
                                HTTPStatus: status,
                        }, engine.ErrTooManyAttempts
                }
                return failedFrom(engine.ErrExchangeFailed, httpClass, engine.ExitStartup), string(httpClass.Code)
        }

        // The honest unknown.
        unknown := fferr.ClassifyTransport(err)
        unknown.Code = fferr.CodeUnknown
        unknown.Message = "Something went wrong"
        return failedFrom(engine.ErrExchangeFailed, unknown, engine.ExitStartup), engine.ErrExchangeFailed
}

// classifyVerifyCodeError maps one FxaVerifySession failure to
// ("wrongCode" | "expired" | "throttled" | "network" + retryable) —
// the re-ask driver of the code loop.
func classifyVerifyCodeError(err error) (kind string, retryable bool) {
        transport := fferr.ClassifyTransport(err)
        switch transport.Code {
        case fferr.CodeDNS, fferr.CodeTimeout:
                return "network", true
        case fferr.CodeNetworkUnreach, fferr.CodeTLS:
                return "network", transport.Retryable
        }
        // Everything else (TokenExchange, Unknown, …) is an FxA application
        // answer in disguise — the errno seam decides.

        errno, hasErrno := fxaErrno(err.Error())
        if hasErrno {
                switch errno {
                case fxaErrnoInvalidCode, fxaErrnoInvalidSigninCode:
                        return "wrongCode", false
                case fxaErrnoCodeExpired:
                        return "expired", false
                case fxaErrnoThrottled:
                        return "throttled", false
                }
        }
        if status, ok := fxaHTTPStatus(err.Error()); ok {
                if status == httpStatusTooManyRequests {
                        return "throttled", false
                }
                if status >= 500 {
                        return "network", true
                }
        }
        return "network", false
}

// verifyFailureTerminal builds the failed event for a TERMINAL verify
// failure (expired / throttled / the unclassifiable).
func verifyFailureTerminal(err error) (engine.Event, string) {
        errno, hasErrno := fxaErrno(err.Error())
        if hasErrno {
                switch errno {
                case fxaErrnoCodeExpired:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrCodeExpired,
                                Message: "The verification code has expired; sign in again",
                        }, engine.ErrCodeExpired
                case fxaErrnoThrottled:
                        return engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrTooManyAttempts,
                                Message: "Too many attempts; try again later",
                        }, engine.ErrTooManyAttempts
                }
        }
        if status, ok := fxaHTTPStatus(err.Error()); ok && status == httpStatusTooManyRequests {
                return engine.Event{
                        Name: engine.EvFailed, FailCode: engine.ErrTooManyAttempts,
                        Message: "Too many attempts; try again later",
                        HTTPStatus: status,
                }, engine.ErrTooManyAttempts
        }
        class := fferr.ClassifyTransport(err)
        if class.Code == fferr.CodeUnknown {
                class.Message = "The code could not be verified"
        }
        return failedFrom(engine.ErrExchangeFailed, class, engine.ExitStartup), string(class.Code)
}

// parseCodeLine accepts {"code":"…"} (tolerant: unknown fields are
// ignored — the additive contract) with a printable 1..16 char code.
func parseCodeLine(line string) (string, bool) {
        var payload struct {
                Code string `json:"code"`
        }
        if err := json.Unmarshal([]byte(line), &payload); err != nil {
                return "", false
        }
        code := strings.TrimSpace(payload.Code)
        if code == "" || len(code) > maxCodeLen {
                return "", false
        }
        for _, r := range code {
                if r < 0x20 || r == 0x7f {
                        return "", false
                }
        }
        return code, true
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
        httpStatusBadRequest       = 400
        httpStatusUnauthorized     = 401
        httpStatusTooManyRequests  = 429
)

// fxaErrno extracts the FxA application errno from the upstream's error
// text. TWO documented shapes ride the seam: the fxaAPIError text
// ("FxA error (HTTP %d, errno %d): %s" — "errno N") and the
// verify-code path's plain error (its JSON body — `"errno":N`).
func fxaErrno(s string) (int, bool) {
        for _, marker := range []string{"errno ", `"errno":`} {
                idx := strings.Index(s, marker)
                if idx < 0 {
                        continue
                }
                rest := s[idx+len(marker):]
                end := 0
                for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' {
                        end++
                }
                if end == 0 {
                        continue
                }
                n, err := strconv.Atoi(rest[:end])
                if err != nil {
                        continue
                }
                return n, true
        }
        return 0, false
}

// fxaHTTPStatus extracts "HTTP %d" from the upstream's fxaAPIError
// text ("FxA error (HTTP %d, errno %d)" / "FxA request failed (HTTP %d)")
// and the verify path's "verification failed (HTTP %d)".
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

// readLineBounded reads ONE line from f (bounded by the 1 MiB
// config-line limit) — the usage role's seam (the login role uses
// [readLoginLineBounded], which hands the reader back for the password
// mode's second line).
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

// readLoginLineBounded reads the login role's FIRST line (bounded by
// the 1 MiB config-line limit; the buffer carrying the credentials is
// dropped by the caller after the parse) and hands the reader back —
// the password mode's line pump inherits whatever it buffered past
// line 1 (a FRESH reader on os.Stdin would lose an eagerly-written
// second line).
func readLoginLineBounded() ([]byte, *bufio.Reader, error) {
        br := bufio.NewReader(io.LimitReader(os.Stdin, maxLoginLine))
        line, err := br.ReadString('\n')
        if err != nil && err != io.EOF {
                return nil, br, err
        }
        line = strings.TrimRight(line, "\r\n")
        if line == "" {
                return nil, br, io.EOF
        }
        return []byte(line), br, nil
}

// maxLoginLine bounds the login config line (same 1 MiB contract).
const maxLoginLine = 1 << 20

// watchLoginStdinClose resolves on stdin EOF (the webchannel mode's
// clean cancel — the password mode uses the line pump's Done instead).
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
