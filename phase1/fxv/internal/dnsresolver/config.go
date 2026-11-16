package dnsresolver

import (
        "fmt"
        "net"
        "net/url"
        "strings"
)

const (
        ModeSystem = "system"
        ModeDoH    = "doh"

        ProviderAuto      = "auto"
        ProviderCloudflare = "cloudflare"
        ProviderGoogle     = "google"
        ProviderQuad9      = "quad9"
        ProviderCustom     = "custom"

        // HelloSplitOff/SNI/FirstByte/Record are the reference's
        // network.hello_split choices, carried on the SAME config line every
        // role already ships to the engine (the dns block) so the pick rides
        // the login, the tunnel, the webview proxy and the probe alike.
        HelloSplitOff       = "off"
        HelloSplitSNI       = "sni"
        HelloSplitFirstByte = "first-byte"
        HelloSplitRecord    = "record"
)

// ValidHelloSplit reports whether mode is one of the choices (empty is
// the engine's own default — off, the reference's default).
func ValidHelloSplit(mode string) bool {
        switch mode {
        case "", HelloSplitOff, HelloSplitSNI, HelloSplitFirstByte, HelloSplitRecord:
                return true
        }
        return false
}

// AutoEndpoints is the reference project's DefaultDNSServers posture
// (arman-vpn-client, core/internal/config): the "Automatic" choice races
// every IP-literal DoH endpoint at once and the first valid answer wins,
// with the system resolver asked after SystemAfter when none answers — a
// filtering network must block ALL of them to keep the names from
// resolving.
var AutoEndpoints = []string{
        "https://1.1.1.1/dns-query",
        "https://8.8.8.8/dns-query",
        "https://9.9.9.9/dns-query",
}

// Config is scoped to the Firefox engine process. It never changes the
// Android device resolver or any other AETHONE core.
type Config struct {
        Mode                   string   `json:"mode,omitempty"`
        Provider               string   `json:"provider,omitempty"`
        Endpoint               string   `json:"endpoint,omitempty"`
        BootstrapIPs           []string `json:"bootstrapIps,omitempty"`
        SystemForLocalDomains  bool     `json:"systemForLocalDomains,omitempty"`
        SystemDomainExceptions []string `json:"systemDomainExceptions,omitempty"`
        // HelloSplit is how the TLS ClientHello of the process's direct
        // connections to Mozilla goes out (the reference's network.hello_split,
        // applied by the pinned upstream's control plane and the direct data
        // plane). Empty means off — the reference's own default; the HOST's
        // default pick is sni.
        HelloSplit string `json:"helloSplit,omitempty"`
}

func DefaultConfig() Config {
        // 1.9.0 — the reference posture (arman-vpn-client's DefaultDNSServers
        // + fallback_to_system): a host that sends no DNS block gets the AUTO
        // resolver, not the poisonable system one. System stays an explicit
        // pick.
        return Config{Mode: ModeDoH, Provider: ProviderAuto, SystemForLocalDomains: true}
}

func (c Config) Validate() (Config, error) {
        c.Mode = strings.ToLower(strings.TrimSpace(c.Mode))
        c.HelloSplit = strings.ToLower(strings.TrimSpace(c.HelloSplit))
        if !ValidHelloSplit(c.HelloSplit) {
                return c, fmt.Errorf("unsupported hello split mode %q", c.HelloSplit)
        }
        if c.Mode == "" {
                def := DefaultConfig()
                def.HelloSplit = c.HelloSplit
                return def, nil
        }
        switch c.Mode {
        case ModeSystem:
                c.Provider = ""
                c.Endpoint = ""
                c.BootstrapIPs = nil
                if !c.SystemForLocalDomains && len(c.SystemDomainExceptions) == 0 {
                        // System mode has no DoH split to apply; this flag is inert.
                        c.SystemForLocalDomains = true
                }
        case ModeDoH:
                c.Provider = strings.ToLower(strings.TrimSpace(c.Provider))
                switch c.Provider {
                // 1.9.0 — the AUTO provider (the reference's
                // DefaultDNSServers): every IP-literal endpoint is queried
                // at once, the first valid answer wins, and the system
                // resolver is asked after SystemAfter when none answers.
                // Bootstrap IPs are inert here (every endpoint is an IP
                // literal) and are dropped.
                case ProviderAuto:
                        c.Endpoint = ""
                        c.BootstrapIPs = nil
                // 1.7.0 — the provider defaults are IP-LITERAL endpoints
                // (arman's ThroughServers model): a hostname endpoint
                // (cloudflare-dns.com, dns.google, …) must itself be
                // resolved before the first DoH query, and on a
                // DNS-poisoned network that bootstrap lookup is answered
                // by the poisoner — every provider then fails exactly
                // the same way ("some DNS requests failed"). The
                // IP-literal forms need NO bootstrap lookup at all and
                // carry no SNI for a middlebox to key on; each
                // provider serves a certificate valid for its IP.
                case ProviderCloudflare:
                        if c.Endpoint == "" { c.Endpoint = "https://1.1.1.1/dns-query" }
                case ProviderGoogle:
                        if c.Endpoint == "" { c.Endpoint = "https://8.8.8.8/dns-query" }
                case ProviderQuad9:
                        if c.Endpoint == "" { c.Endpoint = "https://9.9.9.9/dns-query" }
                case ProviderCustom:
                case "":
                        return c, fmt.Errorf("dns provider is required in DoH mode")
                default:
                        return c, fmt.Errorf("unsupported DNS provider %q", c.Provider)
                }
                // The AUTO posture races [AutoEndpoints] (validated IP
                // literals): the single-endpoint checks below do not apply.
                if c.Provider != ProviderAuto {
                        if c.Provider == ProviderCustom && strings.TrimSpace(c.Endpoint) == "" {
                                return c, fmt.Errorf("custom DoH endpoint is required")
                        }
                        parsed, err := url.Parse(strings.TrimSpace(c.Endpoint))
                        if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil || parsed.Fragment != "" {
                                return c, fmt.Errorf("DoH endpoint must be an absolute HTTPS URL without user-info or fragment")
                        }
                        c.Endpoint = parsed.String()
                        if len(c.BootstrapIPs) > 8 {
                                return c, fmt.Errorf("at most 8 DoH bootstrap IPs are allowed")
                        }
                        bootstrap := make([]string, 0, len(c.BootstrapIPs))
                        seenBootstrap := make(map[string]struct{}, len(c.BootstrapIPs))
                        for i, raw := range c.BootstrapIPs {
                                ip := net.ParseIP(strings.TrimSpace(raw))
                                if ip == nil || ip.IsUnspecified() || ip.IsMulticast() {
                                        return c, fmt.Errorf("invalid DoH bootstrap IP at index %d", i)
                                }
                                normalized := ip.String()
                                if _, ok := seenBootstrap[normalized]; ok { continue }
                                seenBootstrap[normalized] = struct{}{}
                                bootstrap = append(bootstrap, normalized)
                        }
                        c.BootstrapIPs = bootstrap
                }
        default:
                return c, fmt.Errorf("unsupported DNS mode %q", c.Mode)
        }

        if len(c.SystemDomainExceptions) > 64 {
                return c, fmt.Errorf("at most 64 system DNS domain exceptions are allowed")
        }
        seen := make(map[string]struct{}, len(c.SystemDomainExceptions))
        out := make([]string, 0, len(c.SystemDomainExceptions))
        for i, raw := range c.SystemDomainExceptions {
                domain, err := normalizeDomain(raw)
                if err != nil { return c, fmt.Errorf("invalid system DNS exception at index %d: %w", i, err) }
                if _, ok := seen[domain]; ok { continue }
                seen[domain] = struct{}{}
                out = append(out, domain)
        }
        c.SystemDomainExceptions = out
        return c, nil
}

func normalizeDomain(raw string) (string, error) {
        value := strings.ToLower(strings.TrimSpace(raw))
        value = strings.TrimPrefix(value, "*.")
        value = strings.TrimPrefix(value, ".")
        value = strings.TrimSuffix(value, ".")
        if value == "" || len(value) > 253 || strings.Contains(value, "/") || strings.Contains(value, ":") {
                return "", fmt.Errorf("not a valid DNS suffix")
        }
        for _, label := range strings.Split(value, ".") {
                if label == "" || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
                        return "", fmt.Errorf("not a valid DNS suffix")
                }
                for _, r := range label {
                        if !(r >= 'a' && r <= 'z') && !(r >= '0' && r <= '9') && r != '-' {
                                return "", fmt.Errorf("not a valid ASCII DNS suffix")
                        }
                }
        }
        return value, nil
}

func (c Config) UsesSystemDNS(host string) bool {
        if c.Mode != ModeDoH { return true }
        host = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
        if host == "" { return false }
        if c.SystemForLocalDomains && (host == "localhost" || strings.HasSuffix(host, ".localhost") ||
                host == "local" || strings.HasSuffix(host, ".local")) {
                return true
        }
        for _, suffix := range c.SystemDomainExceptions {
                if host == suffix || strings.HasSuffix(host, "."+suffix) { return true }
        }
        return false
}

// DoHEndpoints expands a validated DoH config into the endpoint list the
// exchange races: the AUTO provider's three IP-literal servers, or the
// one endpoint of the picked provider.
func (c Config) DoHEndpoints() []string {
        if c.Provider == ProviderAuto {
                return append([]string(nil), AutoEndpoints...)
        }
        return []string{c.Endpoint}
}
