package main

// Unit tests for the --login exchange seams: the errno/status
// extraction, the classifyLoginError mapping, and the parsed-pair
// guard (the Part 3 rules on the parsed TokenResponse).

import (
        "errors"
        "fmt"
        "net"
        "testing"

        "aethone/fxv/internal/engine"
        "aethone/fxv/internal/fferr"
)

func TestFxaErrnoExtraction(t *testing.T) {
        cases := []struct {
                in   string
                want int
                ok   bool
        }{
                {"FxA error (HTTP 400, errno 104): unverified session", 104, true},
                {"FxA error (HTTP 401, errno 110): invalid token", 110, true},
                {"FxA request failed (HTTP 500): boom", 0, false},
                {"totally unrelated", 0, false},
        }
        for _, tc := range cases {
                got, ok := fxaErrno(tc.in)
                if got != tc.want || ok != tc.ok {
                        t.Fatalf("fxaErrno(%q) = %d,%v want %d,%v", tc.in, got, ok, tc.want, tc.ok)
                }
        }
}

func TestFxaHTTPStatusExtraction(t *testing.T) {
        cases := []struct {
                in   string
                want int
                ok   bool
        }{
                {"FxA error (HTTP 401, errno 110): x", 401, true},
                {"FxA request failed (HTTP 503): y", 503, true},
                {"no status here", 0, false},
        }
        for _, tc := range cases {
                got, ok := fxaHTTPStatus(tc.in)
                if got != tc.want || ok != tc.ok {
                        t.Fatalf("fxaHTTPStatus(%q) = %d,%v want %d,%v", tc.in, got, ok, tc.want, tc.ok)
                }
        }
}

func TestClassifyLoginUnverifiedRetries(t *testing.T) {
        for _, errno := range []int{fxaErrnoUnverifiedSession, fxaErrnoUnverifiedAccount} {
                err := fmt.Errorf("FxA error (HTTP 400, errno %d): unverified session", errno)
                class, retry, terminal := classifyLoginError(err)
                if !retry {
                        t.Fatalf("errno %d must be retryable", errno)
                }
                if terminal != "" {
                        t.Fatalf("errno %d must not be terminal", errno)
                }
                if class.Code != fferr.CodeTokenExchange {
                        t.Fatalf("errno %d class = %s", errno, class.Code)
                }
        }
}

func TestClassifyLoginDefinitiveRejection(t *testing.T) {
        for _, errno := range []int{fxaErrnoUnknownAccount, fxaErrnoInvalidToken, fxaErrnoRequestWithoutTok} {
                err := fmt.Errorf("FxA error (HTTP 401, errno %d): nope", errno)
                _, retry, terminal := classifyLoginError(err)
                if retry {
                        t.Fatalf("errno %d must not retry", errno)
                }
                if terminal != "sessionRejected" {
                        t.Fatalf("errno %d terminal = %q", errno, terminal)
                }
        }
}

func TestClassifyLoginDNSError(t *testing.T) {
        // The exact 2026-11-08 device chain shape: url.Error → OpError →
        // DNSError → OpError(read udp [::1]:53 refused).
        dnsErr := &net.DNSError{Err: "connection refused", Name: "api.accounts.firefox.com", Server: "[::1]:53", IsTemporary: true}
        wrapped := fmt.Errorf("oauth token request: %w", fmt.Errorf("Post https://api.accounts.firefox.com/v1/oauth/token: %w",
                &net.OpError{Op: "dial", Err: dnsErr}))
        class, retry, terminal := classifyLoginError(wrapped)
        if class.Code != fferr.CodeDNS {
                t.Fatalf("class = %s, want dnsError", class.Code)
        }
        if !retry {
                t.Fatal("dnsError must be retryable here (the verify-budget loop owns it)")
        }
        if terminal != "" {
                t.Fatalf("terminal = %q", terminal)
        }
}

func TestClassifyLoginTLSError(t *testing.T) {
        // A real self-signed rejection shape (x509 UnknownAuthority wrapped).
        tlsErr := errors.New("tls: failed to verify certificate: x509: certificate signed by unknown authority")
        class, _, _ := classifyLoginError(tlsErr)
        // Not a typed TLS error (plain errors.New) — falls to unknown/errno
        // seams; the TYPED path is covered by the fferr suite. Here we only
        // assert it never misclassifies as DNS or sessionRejected.
        if class.Code == fferr.CodeDNS || class.Code == fferr.CodeSessionRejected {
                t.Fatalf("misclassified: %s", class.Code)
        }
}

func TestClassifyLoginHTTPStatuses(t *testing.T) {
        // No errno, plain status shapes through the seam.
        class, retry, terminal := classifyLoginError(fmt.Errorf("FxA request failed (HTTP 500): oops"))
        if class.Code != fferr.CodeServerRejection || !retry || terminal != "" {
                t.Fatalf("500: %+v retry=%v terminal=%q", class, retry, terminal)
        }
        if class.HTTPStatus != 500 {
                t.Fatalf("httpStatus = %d", class.HTTPStatus)
        }

        class, retry, terminal = classifyLoginError(fmt.Errorf("FxA request failed (HTTP 404): nope"))
        if class.Code != fferr.CodeServerRejection || retry || terminal != "" {
                t.Fatalf("404: %+v retry=%v terminal=%q", class, retry, terminal)
        }
}

func TestGuardParsedPair(t *testing.T) {
        cases := []struct {
                name          string
                access, refr  string
                ok            bool
                reasonMatch   string
        }{
                {"valid pair", "access-token-value", "refresh-token-value", true, ""},
                {"missing access", "", "refresh-token-value", false, "access_token"},
                {"blank access", "   ", "refresh-token-value", false, "access_token"},
                {"missing refresh", "access-token-value", "", false, "refresh_token"},
                {"blank refresh", "access-token-value", "\t\n", false, "refresh_token"},
                {"both missing", "", "", false, "both"},
        }
        for _, tc := range cases {
                t.Run(tc.name, func(t *testing.T) {
                        guard := guardParsedPair(tc.access, tc.refr)
                        if tc.ok && guard != nil {
                                t.Fatalf("valid pair rejected: %v", guard)
                        }
                        if !tc.ok {
                                if guard == nil {
                                        t.Fatal("invalid pair accepted")
                                }
                                if tc.reasonMatch != "" && !containsReason(guard.Reason, tc.reasonMatch) {
                                        t.Fatalf("reason %q lacks %q", guard.Reason, tc.reasonMatch)
                                }
                                if guard.Classified().Code != fferr.CodeInvalidTokenResp {
                                        t.Fatalf("guard class = %s", guard.Classified().Code)
                                }
                        }
                })
        }
}

func containsReason(haystack, needle string) bool {
        return len(haystack) >= len(needle) && (haystack == needle ||
                indexOf(haystack, needle) >= 0)
}

func indexOf(h, n string) int {
        for i := 0; i+len(n) <= len(h); i++ {
                if h[i:i+len(n)] == n {
                        return i
                }
        }
        return -1
}

func TestFailedFromCarriesClassifiedFields(t *testing.T) {
        retryable := true
        class := fferr.Classified{Code: fferr.CodeDNS, Message: "DNS name resolution failed", Retryable: true}
        ev := failedFrom("exchangeFailed", class, 1)
        if ev.FailCode != "dnsError" {
                t.Fatalf("failCode = %s", ev.FailCode)
        }
        if ev.Retryable == nil || *ev.Retryable != retryable {
                t.Fatalf("retryable = %v", ev.Retryable)
        }
        if ev.Message != "DNS name resolution failed" {
                t.Fatalf("message = %s", ev.Message)
        }
}

func TestFailedFromKeepsUmbrellaWhenNoClass(t *testing.T) {
        ev := failedFrom("upstreamSessionFailed", classifyUpstream(errors.New("negotiation failed"), engine.Config{}), 1)
        if ev.FailCode != "upstreamSessionFailed" {
                t.Fatalf("failCode = %s", ev.FailCode)
        }
}
