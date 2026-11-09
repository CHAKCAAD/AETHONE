// Package fferr — Phase B Part 2/3 classification guard, INTEGRATED into
// the AETHONE Firefox engine tree (phase1/fxv, 2026-11-09 rebuild).
// Verbatim from docs/phaseb-engine-patch/fferr (the drop-in patch this
// engine rebuild applied); the engine's exchange/login paths call
// ClassifyTransport / ClassifyHTTP / ValidateTokenResponse at their
// transport/HTTP/parse decision points.
//
// Rules honored here (from the Phase B directive):
//   - discrimination by ERROR TYPE (errors.As), never string matching;
//   - HTTP errors carry the REAL status code;
//   - user-facing messages are static and can never contain
//     Token / Session / RefreshToken values;
//   - the raw chain is kept for the engine log only (`Internal`).
package fferr

import (
        "context"
        "crypto/tls"
        "crypto/x509"
        "errors"
        "fmt"
        "net"
        "net/url"
        "strings"
        "syscall"
)

// Code is the stable engine→Dart error code (JSON contract).
type Code string

const (
        CodeDNS              Code = "dnsError"
        CodeNetworkUnreach   Code = "networkUnavailable"
        CodeTimeout          Code = "timeout"
        CodeTLS              Code = "tlsError"
        CodeSessionRejected  Code = "sessionRejected"
        CodeTokenExchange    Code = "tokenExchange"
        CodeInvalidTokenResp Code = "invalidTokenResponse"
        CodeServerRejection  Code = "serverRejection"
        CodeUnknown          Code = "unknown"
)

// Classified is what the engine serializes to Dart on failure.
// Message is SAFE for the UI (static text); Internal goes to stderr only.
type Classified struct {
        Code       Code   `json:"code"`
        Message    string `json:"message"` // static; Dart localizes by Code
        HTTPStatus int    `json:"httpStatus,omitempty"`
        Retryable  bool   `json:"retryable"`
        Internal   string `json:"-"` // engine stderr only; never crosses to UI
}

// safe user-facing strings. Persian UI text lives on the Dart side; the
// engine emits the code, Dart maps unknown codes to a generic message.
var msg = map[Code]string{
        CodeDNS:              "DNS name resolution failed",
        CodeNetworkUnreach:   "Could not reach the server",
        CodeTimeout:          "The server took too long to respond",
        CodeTLS:              "Secure connection could not be established",
        CodeSessionRejected:  "The session was rejected by the account server",
        CodeTokenExchange:    "The sign-in exchange failed",
        CodeInvalidTokenResp: "The account server returned an invalid token response",
        CodeServerRejection:  "The account server rejected the request",
        CodeUnknown:          "Something went wrong",
}

// ClassifyTransport inspects a TRANSPORT-level failure (no HTTP response
// arrived). err may be the raw *url.Error chain exactly as returned by
// http.Client.Do / Post.
func ClassifyTransport(err error) Classified {
        c := Classified{Code: CodeUnknown, Message: msg[CodeUnknown], Retryable: false}
        if err == nil {
                return c
        }
        c.Internal = err.Error()

        var dnsErr *net.DNSError
        var tlsCve *tls.CertificateVerificationError
        var uaErr *x509.UnknownAuthorityError
        var hostErr *x509.HostnameError
        var opErr *net.OpError
        var netErr net.Error

        switch {
        // DNS first: the 2026-11-08 device chain is url.Error→OpError(dial)→
        // DNSError→OpError(read udp … connection refused). errors.As must hit
        // the DNSError regardless of how deeply it is wrapped.
        case errors.As(err, &dnsErr):
                c.Code = CodeDNS
                c.Message = msg[CodeDNS]
                c.Retryable = dnsErr.IsTemporary || dnsErr.IsTimeout
                if dnsErr.IsNotFound {
                        c.Message = "DNS name could not be resolved"
                }
        case errors.As(err, &tlsCve), errors.As(err, &uaErr), errors.As(err, &hostErr):
                c.Code = CodeTLS
                c.Message = msg[CodeTLS]
                c.Retryable = false
        case errors.As(err, &netErr) && netErr.Timeout():
                c.Code = CodeTimeout
                c.Message = msg[CodeTimeout]
                c.Retryable = true
        case errors.Is(err, context.DeadlineExceeded):
                c.Code = CodeTimeout
                c.Message = msg[CodeTimeout]
                c.Retryable = true
        case errors.As(err, &opErr):
                // Dial refused / unreachable (TCP to the API host, not the DNS leg).
                c.Code = CodeNetworkUnreach
                c.Message = msg[CodeNetworkUnreach]
                c.Retryable = false
        default:
                var uerr *url.Error
                if errors.As(err, &uerr) {
                        c.Code = CodeTokenExchange
                        c.Message = msg[CodeTokenExchange]
                }
        }
        return c
}

func isConnRefused(op *net.OpError) bool {
        return errors.Is(op.Err, syscall.ECONNREFUSED)
}

// ClassifyHTTP inspects an HTTP-level outcome (a response DID arrive).
// status is the real status code from the exchange response.
func ClassifyHTTP(status int, body []byte) Classified {
        c := Classified{
                HTTPStatus: status,
                Internal:   fmt.Sprintf("http status %d", status),
        }
        switch {
        case status == 401 || status == 403:
                c.Code = CodeSessionRejected
                c.Message = msg[CodeSessionRejected]
                c.Retryable = false
        case status >= 400 && status < 500:
                c.Code = CodeServerRejection
                c.Message = msg[CodeServerRejection]
                c.Retryable = false
        case status >= 500:
                c.Code = CodeServerRejection
                c.Message = msg[CodeServerRejection]
                c.Retryable = true
        default:
                c.Code = CodeUnknown
                c.Message = msg[CodeUnknown]
        }
        _ = body // body is never echoed into user-facing text
        return c
}

// Redact guarantees the Phase B secrecy rule at the engine boundary:
// no Token/Session/Refresh value may cross into the classified payload.
// It returns a copy with Internal rewritten to a safe form for stderr
// debugging, with any of the given secret values stripped.
func (c Classified) Redact(secrets ...string) Classified {
        out := c
        out.Internal = c.Internal
        for _, s := range secrets {
                if s == "" {
                        continue
                }
                out.Internal = strings.ReplaceAll(out.Internal, s, "[REDACTED]")
        }
        return out
}
