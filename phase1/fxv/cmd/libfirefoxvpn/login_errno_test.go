package main

// The 1.8.0 password-mode classifier tests — the errno seam's TWO
// documented shapes (the fxaAPIError text "errno N" and the verify
// path's JSON body `"errno":N`), the arman SignInError mapping, the
// code-line parse, and the redaction of the password in every stderr
// path. Pure functions, no network.

import (
        "errors"
        "fmt"
        "net"
        "strings"
        "testing"

        "aethone/fxv/internal/redact"
)

func TestFxaErrnoBothShapes(t *testing.T) {
        cases := []struct {
                text string
                want int
                ok   bool
        }{
                {"FxA error (HTTP 400, errno 103): {\"errno\":103}", 103, true},
                {"FxA error (HTTP 401, errno 102): bad", 102, true},
                {"verification failed (HTTP 400): {\"errno\":105,\"error\":\"...\"}", 105, true},
                {"verification failed (HTTP 429): {\"errno\":114}", 114, true},
                {"FxA request failed (HTTP 500): no errno", 0, false},
                {"errno without digits", 0, false},
                {"", 0, false},
        }
        for _, tc := range cases {
                got, ok := fxaErrno(tc.text)
                if ok != tc.ok || got != tc.want {
                        t.Fatalf("fxaErrno(%q) = %d,%v want %d,%v", tc.text, got, ok, tc.want, tc.ok)
                }
        }
}

func TestPasswordLoginFailureErrnoMapping(t *testing.T) {
        cases := []struct {
                name     string
                err      error
                failCode string
        }{
                {"unknown account", fmt.Errorf("FxA error (HTTP 400, errno 102): nope"), "noAccount"},
                {"wrong password", fmt.Errorf("FxA error (HTTP 400, errno 103): nope"), "wrongPassword"},
                {"unverified account", fmt.Errorf("FxA error (HTTP 400, errno 104): nope"), "unverifiedAccount"},
                {"throttled", fmt.Errorf("FxA error (HTTP 429, errno 114): slow down"), "tooManyAttempts"},
                {"email case", fmt.Errorf("FxA error (HTTP 400, errno 120): case"), "emailCaseInvalid"},
                {"security block", fmt.Errorf("FxA error (HTTP 400, errno 125): blocked"), "requestBlocked"},
                {"account reset", fmt.Errorf("FxA error (HTTP 400, errno 126): locked"), "requestBlocked"},
                {"secondary email", fmt.Errorf("FxA error (HTTP 400, errno 142): primary needed"), "secondaryEmail"},
                {"invalid email", fmt.Errorf("FxA error (HTTP 400, errno 149): nope"), "invalidEmail"},
                {"unverified session family", fmt.Errorf("FxA error (HTTP 400, errno 138): nope"), "unverifiedAccount"},
                {"invalid token", fmt.Errorf("FxA error (HTTP 401, errno 110): nope"), "sessionRejected"},
        }
        for _, tc := range cases {
                t.Run(tc.name, func(t *testing.T) {
                        ev, _ := passwordLoginFailure(tc.err)
                        if ev.FailCode != tc.failCode {
                                t.Fatalf("failCode = %q, want %q", ev.FailCode, tc.failCode)
                        }
                        if ev.Name != "failed" {
                                t.Fatalf("event = %q", ev.Name)
                        }
                })
        }
}

func TestPasswordLoginFailureTransport(t *testing.T) {
        // A REAL transport failure keeps the Phase B class (the seam never
        // sees it) — a dial refusal classifies networkUnavailable.
        err := &net.OpError{Op: "dial", Net: "tcp", Err: errors.New("connection refused")}
        ev, _ := passwordLoginFailure(err)
        if ev.FailCode != "networkUnavailable" {
                t.Fatalf("failCode = %q", ev.FailCode)
        }
}

func TestClassifyVerifyCodeError(t *testing.T) {
        cases := []struct {
                name      string
                err       error
                kind      string
                retryable bool
        }{
                {"wrong code", fmt.Errorf("verification failed (HTTP 400): {\"errno\":105}"), "wrongCode", false},
                {"invalid signin code", fmt.Errorf("verification failed (HTTP 400): {\"errno\":146}"), "wrongCode", false},
                {"expired code", fmt.Errorf("verification failed (HTTP 400): {\"errno\":153}"), "expired", false},
                {"throttled code", fmt.Errorf("verification failed (HTTP 429): {\"errno\":114}"), "throttled", false},
                {"server error", fmt.Errorf("verification failed (HTTP 503): busy"), "network", true},
                {"client garbage status", fmt.Errorf("verification failed (HTTP 400): {\"errno\":999}"), "network", false},
        }
        for _, tc := range cases {
                t.Run(tc.name, func(t *testing.T) {
                        kind, retryable := classifyVerifyCodeError(tc.err)
                        if kind != tc.kind || retryable != tc.retryable {
                                t.Fatalf("kind = %q,%v want %q,%v", kind, retryable, tc.kind, tc.retryable)
                        }
                })
        }
}

func TestVerifyFailureTerminal(t *testing.T) {
        ev, code := verifyFailureTerminal(fmt.Errorf("verification failed (HTTP 400): {\"errno\":153}"))
        if ev.FailCode != "codeExpired" || code != "codeExpired" {
                t.Fatalf("event = %+v, code = %q", ev, code)
        }
        ev, code = verifyFailureTerminal(fmt.Errorf("verification failed (HTTP 429): {\"errno\":114}"))
        if ev.FailCode != "tooManyAttempts" || code != "tooManyAttempts" {
                t.Fatalf("event = %+v, code = %q", ev, code)
        }
}

func TestParseCodeLine(t *testing.T) {
        cases := []struct {
                line string
                code string
                ok   bool
        }{
                {`{"code":"123456"}`, "123456", true},
                {`{"code":"abc-def"}`, "abc-def", true},
                {`{"code":"  123456  "}`, "123456", true},
                {`{"code":""}`, "", false},
                {`{"other":1}`, "", false},
                {`not json`, "", false},
                {`{"code":"` + strings.Repeat("x", 17) + `"}`, "", false},
        }
        for _, tc := range cases {
                code, ok := parseCodeLine(tc.line)
                if ok != tc.ok || code != tc.code {
                        t.Fatalf("parseCodeLine(%q) = %q,%v want %q,%v", tc.line, code, ok, tc.code, tc.ok)
                }
        }
}

func TestPasswordRedaction(t *testing.T) {
        // Every stderr path scrubs the password — the logf discipline.
        password := "super-secret-pw"
        scrubbed := redact.Line("login: password accepted with super-secret-pw inside", password)
        if strings.Contains(scrubbed, password) {
                t.Fatalf("password survived redaction: %q", scrubbed)
        }
        if !strings.Contains(scrubbed, redact.Placeholder) {
                t.Fatalf("placeholder missing: %q", scrubbed)
        }
}

func TestPasswordLoginFailureNoSecretEcho(t *testing.T) {
        // An error chain that somehow embeds the password can never cross
        // into the event's user-facing message (the classified message is
        // static; the raw chain rides stderr only, redacted by the caller).
        err := errors.New("FxA error (HTTP 400, errno 103): super-secret-pw echoed")
        ev, _ := passwordLoginFailure(err)
        raw := fmt.Sprintf("%+v", ev)
        if strings.Contains(raw, "super-secret-pw") {
                t.Fatalf("password crossed into the event: %s", raw)
        }
}
