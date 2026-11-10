// Package cptransport — the guardian-bootstrap Stage 5 control-plane
// routing layer (mission §5): a RoundTripper that keeps the pinned
// direct uTLS transport as the DEFAULT for every control-plane request
// (FxA, Remote Settings — and Guardian while no bootstrap is active)
// and sends ONLY the allowlisted Guardian requests through the local
// bootstrap proxy when one is configured.
//
// Why this shape (mission §5-1/§5-2): the pinned vpnclient exposes ONE
// process-wide control-plane seam (SetControlPlaneTransport) shared by
// FxA + Guardian + Remote Settings. Replacing it with a plain proxy
// transport would route the WHOLE control plane through Psiphon —
// forbidden. The RoutingRoundTripper is the minimal wrapper that makes
// the seam SELECTIVE:
//
//	RoutingRoundTripper
//	   +-- Default: the existing direct-uTLS transport
//	   +-- Guardian allowlist (host + method + path):
//	         +-- bootstrap unavailable (proxied == nil): Direct
//	         +-- bootstrap ready: the local proxy
//
// Allowlist precision (mission §5-3): the host is the REAL host of the
// engine's Guardian base URL (never a guessed name), and the method +
// path are matched too — never the host alone. The initial execution
// path carries exactly ONE entry, GET /api/v1/fpn/token (the pinned
// client's FetchProxyPass — the initial authorization AND the renewal
// walk; /api/v1/fpn/status and /api/v1/fpn/activate are NOT called by
// the engine and stay OUT of the allowlist until they really are).
//
// The doubled-leading-slash form of the allowed path is matched as
// well: the Arman reference's CDN-edge evasion rewrites /api/v1/fpn/
// token to //api/v1/fpn/token BEFORE the request leaves the client;
// routing must not silently break if that trick is ever enabled
// upstream of this layer (Stage 1's documented forward-compatibility
// note — the tolerance itself changes nothing today).
//
// Redirects (mission §5-5): http.Client re-enters RoundTrip for EVERY
// hop of a redirect chain, so each hop is re-checked against the
// allowlist independently — a redirect to a non-allowed host or path
// automatically falls back to the DIRECT leg and never traverses the
// bootstrap proxy.
//
// Security invariants (mission §5-5, §11): TLS stays end-to-end on the
// proxied leg (net/http performs the handshake itself over the tunnel
// with Certificate AND Hostname verification left at their defaults —
// no MITM, no InsecureSkipVerify anywhere in this package); DNS for
// the Guardian host resolves through the proxy (the socks5/http dial
// path carries the hostname to the proxy, not a locally-resolved IP —
// no local DNS leak); credentials never appear in any string this
// package renders (Redacted renders scheme+host only).
package cptransport

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/proxy"
)

// apiProxyDialTimeout mirrors the pinned proxy-demo's constant for the
// proxied control-plane leg (20s — the local loopback proxy plus the
// tunnel's own establishment budget).
const apiProxyDialTimeout = 20 * time.Second

// AllowedRequest is one allowlist entry: an HTTP method plus a request
// path (exact; the doubled-leading-slash variant is tolerated).
type AllowedRequest struct {
	Method string
	Path   string
}

// GuardianAllowlist is the allowlisted set for the Guardian base URL.
type GuardianAllowlist struct {
	// host is the Guardian base URL's hostname (lower-cased at build).
	host string
	// port is the base URL's explicit port, or "" for the scheme
	// default (an https base with no port matches the https default).
	port string
	// allowed carries the method+path entries (never empty).
	allowed []AllowedRequest
}

// NewGuardianAllowlist derives the allowlist from the engine's REAL
// Guardian base URL (https://vpn.mozilla.org by default — whatever the
// host configured) and the method+path entries the execution path
// actually calls.
func NewGuardianAllowlist(guardianBase string, allowed ...AllowedRequest) (GuardianAllowlist, error) {
	parsed, err := url.Parse(strings.TrimSpace(guardianBase))
	if err != nil || parsed.Host == "" {
		return GuardianAllowlist{}, fmt.Errorf("guardian base URL has no host: %q", guardianBase)
	}
	if len(allowed) == 0 {
		return GuardianAllowlist{}, fmt.Errorf("empty guardian allowlist")
	}
	return GuardianAllowlist{
		host:    strings.ToLower(parsed.Hostname()),
		port:    parsed.Port(),
		allowed: allowed,
	}, nil
}

// Redacted renders the allowlist for logs/diagnostics — host + entries
// only, never credentials or query strings.
func (a GuardianAllowlist) Redacted() string {
	entries := make([]string, len(a.allowed))
	for i, r := range a.allowed {
		entries[i] = r.Method + " " + r.Path
	}
	host := a.host
	if a.port != "" {
		host += ":" + a.port
	}
	return fmt.Sprintf("guardian=%s allowlist=[%s]", host, strings.Join(entries, ", "))
}

// matches reports whether req targets the allowlisted Guardian host
// with an allowlisted method+path.
func (a GuardianAllowlist) matches(req *http.Request) bool {
	if req == nil || req.URL == nil {
		return false
	}
	if !strings.EqualFold(req.URL.Hostname(), a.host) {
		return false
	}
	reqPort := req.URL.Port()
	if reqPort == "" {
		// Scheme default: https targets carry no explicit port and
		// match an https base's default; http targets an http base's.
		switch strings.ToLower(req.URL.Scheme) {
		case "https":
			reqPort = "443"
		case "http":
			reqPort = "80"
		}
	}
	wantPort := a.port
	if wantPort == "" {
		wantPort = "443" // the engine's Guardian base is https-only (config validation)
	}
	if reqPort != wantPort {
		return false
	}
	path := req.URL.Path
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	// The doubled-leading-slash tolerance (see the package comment).
	if strings.HasPrefix(path, "//") {
		path = path[1:]
	}
	for _, r := range a.allowed {
		if req.Method == r.Method && path == r.Path {
			return true
		}
	}
	return false
}

// RoutingRoundTripper is the selective control-plane transport
// (mission §5-2). It is safe for concurrent use: both legs are.
type RoutingRoundTripper struct {
	direct    http.RoundTripper
	proxied   http.RoundTripper // nil = bootstrap unavailable -> Direct
	allowlist GuardianAllowlist
}

// NewRoutingRoundTripper builds the routing transport. direct is the
// EXISTING direct-uTLS transport (vpnclient.NewControlPlaneTransport()
// — never replaced, mission §5-2); proxied may be nil, in which case
// EVERYTHING goes direct (the "bootstrap unavailable" state).
func NewRoutingRoundTripper(direct, proxied http.RoundTripper, allowlist GuardianAllowlist) *RoutingRoundTripper {
	return &RoutingRoundTripper{direct: direct, proxied: proxied, allowlist: allowlist}
}

// RoundTrip routes per the allowlist: allowlisted Guardian requests
// ride the proxied leg when one is configured; everything else — FxA,
// Remote Settings, non-allowlisted paths on the Guardian host, and
// every redirect hop that leaves the allowlist — rides the direct leg.
func (t *RoutingRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	if t.proxied != nil && t.allowlist.matches(req) {
		return t.proxied.RoundTrip(req)
	}
	return t.direct.RoundTrip(req)
}

// NewProxyRoundTripper builds the bootstrap leg from a local proxy URL
// (http/https/socks5/socks5h), following the pinned proxy-demo's
// configureAPIProxy pattern exactly: net/http performs TLS itself over
// the proxied socket with the DEFAULT verification chain (no MITM, no
// weakened checks) and the HTTP/1.1 pin (the pinned demo's choice for
// the proxied path — see NewControlPlaneTransport's doc in the pin).
//
// The socks5 and socks5h schemes behave identically here (as in the
// pin's demo): x/net/proxy's SOCKS5 dialer forwards the DESTINATION
// HOSTNAME to the proxy, so the Guardian host resolves through the
// bootstrap proxy, never through the local resolver (mission §5-5 — no
// unintended DNS disclosure).
func NewProxyRoundTripper(rawURL string) (http.RoundTripper, error) {
	raw := strings.TrimSpace(rawURL)
	if raw == "" {
		return nil, fmt.Errorf("empty api proxy URL")
	}
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	parsed, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if parsed.Host == "" {
		return nil, fmt.Errorf("missing proxy host")
	}

	dialer := &net.Dialer{Timeout: apiProxyDialTimeout}
	transport := &http.Transport{
		ForceAttemptHTTP2: false,
		TLSClientConfig:   nil, // DEFAULT verification: Certificate + Hostname checks stay ON
		TLSNextProto:      map[string]func(authority string, c *tls.Conn) http.RoundTripper{},
	}

	switch parsed.Scheme {
	case "http", "https":
		transport.Proxy = http.ProxyURL(parsed)
		transport.DialContext = dialer.DialContext
	case "socks5", "socks5h":
		var auth *proxy.Auth
		if parsed.User != nil {
			password, _ := parsed.User.Password()
			auth = &proxy.Auth{User: parsed.User.Username(), Password: password}
		}
		socksDialer, err := proxy.SOCKS5("tcp", parsed.Host, auth, dialer)
		if err != nil {
			return nil, fmt.Errorf("creating socks5 dialer: %w", err)
		}
		contextDialer, ok := socksDialer.(proxy.ContextDialer)
		if !ok {
			return nil, fmt.Errorf("socks5 dialer does not support contexts")
		}
		transport.DialContext = contextDialer.DialContext
	default:
		return nil, fmt.Errorf("unsupported proxy scheme %q (supported: http, https, socks5, socks5h)", parsed.Scheme)
	}
	return transport, nil
}
