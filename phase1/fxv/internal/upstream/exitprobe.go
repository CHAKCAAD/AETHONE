package upstream

// The engine-side exit probe (ADAPTED from the pinned upstream's
// verifyExit / parseExitProbeResponse / openTunnelContext /
// logVerifiedExit). NON-FATAL by contract: it reports
// exitVerified / exitVerifyFailed events only — the host's own
// end-to-end probe through the SOCKS port is the sole gate to
// Connected.

import (
        "context"
        "crypto/tls"
        "encoding/json"
        "fmt"
        "io"
        "net"
        "net/http"
        "net/url"
        "strings"
        "time"

        utls "github.com/refraction-networking/utls"
)

const maxExitCheckResponseSize = 64 * 1024

// ExitProbeResult is one verified exit observation.
type ExitProbeResult struct {
        IP          string
        CountryCode string
        Latency     time.Duration
        ProbeHost   string
}

// VerifyExit requests rawURL THROUGH the tunnel opener and parses the
// exit IP + country (ADAPTED). The probe request itself presents the
// uTLS Firefox ClientHello (the same identity as the control plane —
// the anti-bot edge treats Go's ClientHello as a bot signature).
func VerifyExit(opener TunnelOpener, rawURL string, timeout time.Duration) (ExitProbeResult, error) {
        if opener == nil {
                return ExitProbeResult{}, fmt.Errorf("nil tunnel opener")
        }
        probeURL, err := url.Parse(rawURL)
        if err != nil {
                return ExitProbeResult{}, fmt.Errorf("parsing exit check URL: %w", err)
        }
        if !strings.EqualFold(probeURL.Scheme, "https") || probeURL.Hostname() == "" {
                return ExitProbeResult{}, fmt.Errorf("exit check URL must use HTTPS and include a host")
        }

        transport := &http.Transport{
                Proxy:               nil,
                DisableKeepAlives:   true,
                TLSHandshakeTimeout: timeout,
                TLSClientConfig: &tls.Config{
                        MinVersion: tls.VersionTLS12,
                },
                DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
                        tun, err := OpenTunnelContext(ctx, opener, addr)
                        if err != nil {
                                return nil, err
                        }
                        host, _, splitErr := net.SplitHostPort(addr)
                        if splitErr != nil {
                                _ = tun.Close()
                                return nil, splitErr
                        }
                        uconn := utls.UClient(tun, &utls.Config{
                                ServerName: host,
                                MinVersion: utls.VersionTLS12,
                        }, utls.HelloFirefox_Auto)
                        if err := uconn.HandshakeContext(ctx); err != nil {
                                _ = tun.Close()
                                return nil, err
                        }
                        return uconn, nil
                },
        }
        defer transport.CloseIdleConnections()
        client := &http.Client{Transport: transport, Timeout: timeout}

        request, err := http.NewRequest(http.MethodGet, probeURL.String(), nil)
        if err != nil {
                return ExitProbeResult{}, fmt.Errorf("creating exit verification request: %w", err)
        }
        request.Header.Set("Accept", "text/plain, application/json")
        request.Header.Set("User-Agent", "firefox-vpn-client-exit-check/1")

        started := time.Now()
        response, err := client.Do(request)
        if err != nil {
                return ExitProbeResult{}, fmt.Errorf("requesting exit verification endpoint: %w", err)
        }
        defer response.Body.Close()
        if response.StatusCode < 200 || response.StatusCode >= 300 {
                return ExitProbeResult{}, fmt.Errorf("exit verification endpoint returned HTTP %d", response.StatusCode)
        }
        body, err := io.ReadAll(io.LimitReader(response.Body, maxExitCheckResponseSize+1))
        if err != nil {
                return ExitProbeResult{}, fmt.Errorf("reading exit verification response: %w", err)
        }
        if len(body) > maxExitCheckResponseSize {
                return ExitProbeResult{}, fmt.Errorf("exit verification response exceeds %d bytes", maxExitCheckResponseSize)
        }
        ip, countryCode, err := ParseExitProbeResponse(body)
        if err != nil {
                return ExitProbeResult{}, err
        }
        return ExitProbeResult{
                IP:          ip,
                CountryCode: countryCode,
                Latency:     time.Since(started),
                ProbeHost:   probeURL.Hostname(),
        }, nil
}

// OpenTunnelContext opens a tunnel bounded by ctx (ADAPTED).
func OpenTunnelContext(ctx context.Context, opener TunnelOpener, authority string) (net.Conn, error) {
        type tunnelResult struct {
                conn net.Conn
                err  error
        }
        resultCh := make(chan tunnelResult)
        go func() {
                conn, err := opener.OpenTunnel(authority)
                select {
                case resultCh <- tunnelResult{conn: conn, err: err}:
                case <-ctx.Done():
                        if conn != nil {
                                _ = conn.Close()
                        }
                }
        }()

        select {
        case result := <-resultCh:
                return result.conn, result.err
        case <-ctx.Done():
                return nil, ctx.Err()
        }
}

// TunnelOpener is re-declared here as the package-local opener shape
// (socks.TunnelOpener's twin).
type TunnelOpener interface {
        OpenTunnel(authority string) (net.Conn, error)
}

// ParseExitProbeResponse accepts both the key=value and JSON shapes
// (ADAPTED).
func ParseExitProbeResponse(body []byte) (string, string, error) {
        fields := make(map[string]string)
        for _, line := range strings.Split(string(body), "\n") {
                key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
                if ok {
                        fields[strings.ToLower(strings.TrimSpace(key))] = strings.TrimSpace(value)
                }
        }

        ip := firstNonEmpty(fields["ip"], fields["query"])
        countryCode := firstNonEmpty(fields["loc"], fields["country_code"], fields["countrycode"])
        if ip == "" || countryCode == "" {
                var payload map[string]any
                if err := json.Unmarshal(body, &payload); err == nil {
                        ip = firstNonEmpty(ip, jsonString(payload, "ip"), jsonString(payload, "query"))
                        countryCode = firstNonEmpty(countryCode, jsonString(payload, "country_code"), jsonString(payload, "countryCode"))
                }
        }

        ip = strings.TrimSpace(ip)
        if net.ParseIP(ip) == nil {
                return "", "", fmt.Errorf("exit verification response did not contain a valid IP address")
        }
        countryCode = strings.ToUpper(strings.TrimSpace(countryCode))
        if len(countryCode) != 2 || countryCode[0] < 'A' || countryCode[0] > 'Z' || countryCode[1] < 'A' || countryCode[1] > 'Z' {
                return "", "", fmt.Errorf("exit verification response did not contain a valid two-letter country code")
        }
        return ip, countryCode, nil
}

func jsonString(payload map[string]any, key string) string {
        value, _ := payload[key].(string)
        return value
}

func firstNonEmpty(values ...string) string {
        for _, value := range values {
                if strings.TrimSpace(value) != "" {
                        return value
                }
        }
        return ""
}
