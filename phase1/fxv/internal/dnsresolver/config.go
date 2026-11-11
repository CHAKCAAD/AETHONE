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

	ProviderCloudflare = "cloudflare"
	ProviderGoogle     = "google"
	ProviderQuad9      = "quad9"
	ProviderCustom     = "custom"
)

// Config is scoped to the Firefox engine process. It never changes the
// Android device resolver or any other AETHONE core.
type Config struct {
	Mode                   string   `json:"mode,omitempty"`
	Provider               string   `json:"provider,omitempty"`
	Endpoint               string   `json:"endpoint,omitempty"`
	BootstrapIPs           []string `json:"bootstrapIps,omitempty"`
	SystemForLocalDomains  bool     `json:"systemForLocalDomains,omitempty"`
	SystemDomainExceptions []string `json:"systemDomainExceptions,omitempty"`
}

func DefaultConfig() Config {
	return Config{Mode: ModeSystem, SystemForLocalDomains: true}
}

func (c Config) Validate() (Config, error) {
	c.Mode = strings.ToLower(strings.TrimSpace(c.Mode))
	if c.Mode == "" {
		return DefaultConfig(), nil
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
		case ProviderCloudflare:
			if c.Endpoint == "" { c.Endpoint = "https://cloudflare-dns.com/dns-query" }
		case ProviderGoogle:
			if c.Endpoint == "" { c.Endpoint = "https://dns.google/dns-query" }
		case ProviderQuad9:
			if c.Endpoint == "" { c.Endpoint = "https://dns.quad9.net/dns-query" }
		case ProviderCustom:
		case "":
			return c, fmt.Errorf("dns provider is required in DoH mode")
		default:
			return c, fmt.Errorf("unsupported DNS provider %q", c.Provider)
		}
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
