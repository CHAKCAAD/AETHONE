package main

// The --usage role (contract 1.7.0) — the account's Guardian quota
// WITHOUT minting a proxy pass. Arman's fetchProxyUsage model
// (core/internal/guardian/guardian.go): a HEAD request to the token
// endpoint (GET fallback when HEAD is refused), the X-Quota-* response
// headers read — including X-Quota-Unlimited, which the pass-minting
// path never surfaces. The remaining-data cards get their values right
// after sign-in and on demand, not only when a tunnel connects.
//
// The request rides the WARP carrier when upstreamSocks is set (the
// control-plane transport seam — the same uTLS Firefox ClientHello
// posture the login uses), and the process-local DNS policy otherwise.

import (
        "context"
        "errors"
        "fmt"
        "io"
        "net/http"
        "os"
        "strings"
        "time"

        vpnclient "firefox-vpn-client"

        "aethone/fxv/internal/dnsresolver"
        "aethone/fxv/internal/engine"
        "aethone/fxv/internal/redact"
        "aethone/fxv/internal/upstream"
)

const (
        usageRequestTimeout = 20 * time.Second
        usageEndpointPath   = "/api/v1/fpn/token"
)

// guardianUsage is the parsed X-Quota-* header set (arman's ProxyUsage
// semantics: Unlimited wins when the flag is true; otherwise limit,
// remaining and reset must all be present and numeric — an absent trio
// with no flag is the "no quota facts" case the host renders as
// unknown, never a guess).
type guardianUsage struct {
        QuotaMax       string
        QuotaLeft      string
        QuotaReset     string
        QuotaUnlimited bool
}

func runUsage() int {
        return runUsageWith(readStdinLine, osStdout, usageHTTPClient)
}

// osStdout / readStdinLine are the production seams the tests swap.
var (
        osStdout     io.Writer = os.Stdout
        readStdinLine           = func() ([]byte, error) { return readLineBounded(os.Stdin) }
)

// usageHTTPClient builds the role's client: the SOCKS-carried control
// plane transport when a carrier is set, the pinned Firefox-uTLS direct
// transport otherwise.
func usageHTTPClient(upstreamSocks string) *http.Client {
        if upstreamSocks != "" {
                return &http.Client{
                        Transport: upstream.NewSOCKS5ControlPlaneTransport(upstreamSocks),
                        Timeout:   usageRequestTimeout,
                }
        }
        return &http.Client{
                Transport: vpnclient.NewControlPlaneTransport(),
                Timeout:   usageRequestTimeout,
        }
}

// runUsageWith is the role body, seam-injected for the tests (the
// clientFactory replaces the TLS posture with the test server's).
func runUsageWith(
        stdin func() ([]byte, error),
        stdout io.Writer,
        clientFactory func(upstreamSocks string) *http.Client,
) int {
        emit := engine.NewEmitterToWriter(stdout)
        line, err := stdin()
        if err != nil {
                _ = emit.Emit(engine.Event{
                        Name: engine.EvUsageFailed, FailCode: engine.ErrBadConfig,
                        Message: "configNotJSON", Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }
        cfg, err := engine.ParseUsageConfig(line)
        if err != nil {
                var cfgErr *engine.ConfigError
                detail := "configNotJSON"
                if errors.As(err, &cfgErr) {
                        detail = cfgErr.DetailCode()
                }
                _ = emit.Emit(engine.Event{
                        Name: engine.EvUsageFailed, FailCode: engine.ErrBadConfig,
                        Message: detail, Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }

        if _, dnsErr := dnsresolver.Install(cfg.DNS); dnsErr != nil {
                _ = emit.Emit(engine.Event{
                        Name: engine.EvUsageFailed, FailCode: engine.ErrBadConfig,
                        Message: "dnsConfigInvalid", Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }

        // The carrier seam — same as the login role: the request dials
        // through the in-process Aether core's SOCKS listener when set
        // (loopback-only, fail-closed; never a direct retry).
        client := clientFactory(cfg.UpstreamSocks)

        ctx, cancel := context.WithTimeout(context.Background(), usageRequestTimeout)
        defer cancel()

        usage, status, err := fetchGuardianUsage(ctx, client, cfg.Guardian, cfg.Auth.AccessToken)
        if err != nil {
                _ = emit.Emit(engine.Event{
                        Name:       engine.EvUsageFailed,
                        FailCode:   usageFailCode(status, err),
                        Message:    redact.Line(err.Error()),
                        HTTPStatus: status,
                        Code:       engine.ExitStartup,
                })
                return engine.ExitStartup
        }
        _ = emit.Emit(engine.Event{
                Name:           engine.EvUsage,
                QuotaMax:       usage.QuotaMax,
                QuotaLeft:      usage.QuotaLeft,
                QuotaReset:     usage.QuotaReset,
                QuotaUnlimited: usage.QuotaUnlimited,
        })
        return engine.ExitClean
}

// fetchGuardianUsage asks the token endpoint for its quota headers
// WITHOUT minting a pass: HEAD first (no body, no token materialized);
// when HEAD is refused (some edges answer 405/400 to HEAD) the GET
// fallback reads the same headers. A 429 is a USAGE CARRYING answer
// (arman's rule: a spent quota still reports valid usage headers).
func fetchGuardianUsage(
        ctx context.Context,
        client *http.Client,
        endpoint string,
        accessToken string,
) (*guardianUsage, int, error) {
        if endpoint == "" {
                endpoint = vpnclient.GuardianEndpointDefault
        }
        base := strings.TrimRight(endpoint, "/") + usageEndpointPath

        do := func(method string) (*http.Response, error) {
                req, err := http.NewRequestWithContext(ctx, method, base, nil)
                if err != nil {
                        return nil, err
                }
                req.Header.Set("Authorization", "Bearer "+accessToken)
                req.Header.Set("Content-Type", "application/json")
                req.Header.Set("User-Agent", "MozillaVPN/2.35.0 (sys:linux; iap:true)")
                req.Header.Set("Accept", "application/json")
                return client.Do(req)
        }

        resp, err := do(http.MethodHead)
        if err == nil && (resp.StatusCode == http.StatusMethodNotAllowed ||
                resp.StatusCode == http.StatusBadRequest) {
                _ = resp.Body.Close()
                resp, err = do(http.MethodGet)
        }
        if err != nil {
                return nil, 0, fmt.Errorf("guardian usage request failed: %w", err)
        }
        defer resp.Body.Close()
        _, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))

        if resp.StatusCode == http.StatusOK {
                usage := usageFromHeaders(resp.Header)
                if usage != nil {
                        return usage, resp.StatusCode, nil
                }
                return nil, resp.StatusCode, fmt.Errorf("guardian usage: no quota headers on the token endpoint")
        }
        if resp.StatusCode == http.StatusTooManyRequests {
                // A spent quota still reports its usage headers.
                if usage := usageFromHeaders(resp.Header); usage != nil {
                        return usage, resp.StatusCode, nil
                }
        }
        if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
                return nil, resp.StatusCode, fmt.Errorf("guardian usage: token rejected (HTTP %d)", resp.StatusCode)
        }
        return nil, resp.StatusCode, fmt.Errorf("guardian usage: HTTP %d", resp.StatusCode)
}

// usageFromHeaders parses the X-Quota-* set with arman's ProxyUsage
// semantics: X-Quota-Unlimited: true wins alone; otherwise limit,
// remaining and reset must all be present and numeric (reset may be
// RFC3339 or Unix seconds — the host parses it).
func usageFromHeaders(h http.Header) *guardianUsage {
        if strings.EqualFold(strings.TrimSpace(h.Get("X-Quota-Unlimited")), "true") {
                return &guardianUsage{QuotaUnlimited: true}
        }
        limit := strings.TrimSpace(h.Get("X-Quota-Limit"))
        remaining := strings.TrimSpace(h.Get("X-Quota-Remaining"))
        reset := strings.TrimSpace(h.Get("X-Quota-Reset"))
        if limit == "" || remaining == "" || reset == "" {
                return nil
        }
        if !isASCIIInteger(limit) || !isASCIIInteger(remaining) {
                return nil
        }
        return &guardianUsage{
                QuotaMax:   limit,
                QuotaLeft:  remaining,
                QuotaReset: reset,
        }
}

func isASCIIInteger(v string) bool {
        if v == "" {
                return false
        }
        for _, r := range v {
                if r < '0' || r > '9' {
                        return false
                }
        }
        return true
}

// usageFailCode maps the fetch outcome to the host's classified codes
// (the same families the login uses; unknown stays the umbrella).
func usageFailCode(status int, err error) string {
        if status == http.StatusUnauthorized || status == http.StatusForbidden {
                return engine.ErrSessionRejected
        }
        if status == http.StatusTooManyRequests {
                return engine.ErrQuotaExhausted
        }
        if status >= 400 && status < 600 {
                return "serverRejection"
        }
        if err != nil && strings.Contains(err.Error(), "guardian usage request failed") {
                return "networkUnavailable"
        }
        return engine.ErrBadConfig
}
