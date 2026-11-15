package main

import (
        "bufio"
        "encoding/json"
        "fmt"
        "io"
        "net"
        "net/url"
        "strconv"
        "strings"

        "aethone/fxv/internal/dnsresolver"
)

const maxDNSConfigLine = 64 * 1024

// webviewProxyConfig is the --webview-proxy role's stdin line: the DNS
// policy plus (1.5.0, the owner's round 2) the OPTIONAL WARP carrier —
// a loopback socks5:// URL (the in-process Aether core's listener). When
// set, the CONNECT targets dial through the carrier with their
// HOSTNAMES (socks5h semantics — the carrier resolves the name through
// the WARP tunnel, so neither a poisoned local DNS nor an SNI/IP block
// on the local network can stop the sign-in page).
type webviewProxyConfig struct {
        DNS           dnsresolver.Config
        UpstreamSocks string
}

// readOptionalDNSConfig reads {"dns":{...}}. EOF/empty stdin means the
// historical Android system resolver, preserving older process callers.
func readOptionalDNSConfig(r io.Reader) (dnsresolver.Config, error) {
        reader := bufio.NewReader(io.LimitReader(r, maxDNSConfigLine+1))
        cfg, err := readWebviewProxyConfigBuffered(reader)
        return cfg.DNS, err
}

// readOptionalDNSConfigBuffered keeps the caller's buffered reader alive.
// Long-running roles such as --webview-proxy must continue observing EOF
// after the one configuration line, without losing bytes read ahead here.
func readOptionalDNSConfigBuffered(reader *bufio.Reader) (dnsresolver.Config, error) {
        cfg, err := readWebviewProxyConfigBuffered(reader)
        return cfg.DNS, err
}

// readWebviewProxyConfigBuffered parses the full --webview-proxy config
// line (dns + upstreamSocks) from the caller's buffered reader.
func readWebviewProxyConfigBuffered(reader *bufio.Reader) (webviewProxyConfig, error) {
        line, err := reader.ReadString('\n')
        if err != nil && err != io.EOF {
                return webviewProxyConfig{}, err
        }
        if len(line) > maxDNSConfigLine {
                return webviewProxyConfig{}, fmt.Errorf("DNS config line too large")
        }
        line = strings.TrimSpace(line)
        var cfg webviewProxyConfig
        if line == "" {
                cfg.DNS = dnsresolver.DefaultConfig()
                return cfg, nil
        }
        var envelope struct {
                DNS           dnsresolver.Config `json:"dns"`
                UpstreamSocks string             `json:"upstreamSocks"`
        }
        if err := json.Unmarshal([]byte(line), &envelope); err != nil {
                return webviewProxyConfig{}, fmt.Errorf("invalid JSON")
        }
        cfg.DNS, err = envelope.DNS.Validate()
        if err != nil {
                return webviewProxyConfig{}, err
        }
        cfg.UpstreamSocks = envelope.UpstreamSocks
        if err := validateWebviewCarrier(cfg.UpstreamSocks); err != nil {
                return webviewProxyConfig{}, err
        }
        return cfg, nil
}

// validateWebviewCarrier gates the carrier URL: empty (the direct dial)
// or a loopback socks5:// host:port with no userinfo/path/query/fragment
// — the same shape the tunnel config's upstreamSocks seam enforces.
func validateWebviewCarrier(raw string) error {
        if strings.TrimSpace(raw) == "" {
                return nil
        }
        u, err := url.Parse(strings.TrimSpace(raw))
        if err != nil || u.Scheme != "socks5" || u.User != nil ||
                u.Hostname() == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
                return fmt.Errorf("upstreamSocksInvalid")
        }
        ip := net.ParseIP(u.Hostname())
        port, portErr := strconv.Atoi(u.Port())
        if ip == nil || !ip.IsLoopback() || portErr != nil || port < 1 || port > 65535 {
                return fmt.Errorf("upstreamSocksInvalid")
        }
        return nil
}
