// Package carrier — the WARP carrier seam: the SOCKS5 CLIENT that
// routes the Firefox engine's traffic through the in-process Aether
// core's SOCKS listener, the "Firefox over Warp" mode (2026-11-15).
//
// This mirrors the chain families of the AETHONE adapter (torChain /
// psiphonChain: an inner exit riding the WARP carrier) with the engine
// as the inner leg:
//
//	apps → zeptun TUN → engine SOCKS5 (1822)
//	                       ├─ control plane: FxA / Guardian /
//	RemoteSettings — uTLS Firefox ClientHello over the carrier
//	                       └─ data plane: the h2 MASQUE session,
//	dialed through the carrier
//	                 → aether SOCKS5 (1819) → WARP tunnel → internet
//
// Provenance: NEW AETHONE code. The SOCKS5 dialing follows the pinned
// upstream's own -api-proxy client (cmd/proxy-demo/main.go
// configureAPIProxy — golang.org/x/net/proxy with the ContextDialer
// assertion) and the uTLS Firefox ClientHello handshake mirrors the
// upstream's dialFirefoxTLS (http_client.go). The upstream's
// -api-proxy path drops to Go's crypto/tls ClientHello + HTTP/1.1
// over the proxied socket (OPERATOR.md: the Go ClientHello sits on the
// Fastly blacklist); the carrier keeps the Firefox preset — the
// anti-bot posture survives the chaining.
package carrier

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/url"
	"time"

	utls "github.com/refraction-networking/utls"
	"golang.org/x/net/http2"
	"golang.org/x/net/proxy"
)

// DialTimeout bounds one carrier dial (the SOCKS5 handshake to the
// local aether listener plus the connect it forwards). The local hop
// is instant; the budget buys the WARP leg's round trips.
const DialTimeout = 20 * time.Second

// TLSTimeout bounds the uTLS handshake riding a carrier connection
// (mirrors the upstream's controlPlaneDialTimeout with headroom for
// the tunnel's extra hop).
const TLSTimeout = 20 * time.Second

// Dialer dials TCP connections through a SOCKS5 carrier (the aether
// core's loopback listener). The zero value is not usable; New builds
// one from a socks5:// URL.
type Dialer struct {
	socksDial proxy.ContextDialer
	// URL is the parsed carrier address (never a secret; diagnostics
	// render Host only).
	URL *url.URL
}

// New parses raw ("socks5://host:port" or "socks5h://…") and builds
// the carrier dialer. The full shape (explicit port, no path/query/
// fragment) is enforced here as the defensive second gate behind the
// engine's config validation.
func New(raw string) (*Dialer, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return nil, fmt.Errorf("carrier url: %w", err)
	}
	if (u.Scheme != "socks5" && u.Scheme != "socks5h") || u.Host == "" ||
		u.Port() == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return nil, fmt.Errorf("carrier url: want socks5://host:port, got %q", raw)
	}
	var auth *proxy.Auth
	if u.User != nil {
		password, _ := u.User.Password()
		auth = &proxy.Auth{User: u.User.Username(), Password: password}
	}
	d, err := proxy.SOCKS5("tcp", u.Host, auth, &net.Dialer{Timeout: DialTimeout})
	if err != nil {
		return nil, fmt.Errorf("carrier dialer: %w", err)
	}
	cd, ok := d.(proxy.ContextDialer)
	if !ok {
		return nil, fmt.Errorf("carrier dialer does not support contexts")
	}
	return &Dialer{socksDial: cd, URL: u}, nil
}

// Host renders the carrier's host:port for log lines (the URL's other
// parts never carried anything interesting).
func (d *Dialer) Host() string {
	if d.URL == nil {
		return ""
	}
	return d.URL.Host
}

// DialContext opens one TCP connection through the carrier. The
// address keeps its hostname (socks5h semantics): the aether listener
// resolves it through the WARP tunnel, so the engine's own resolver
// never leaks the control-plane names to the local network.
func (d *Dialer) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	return d.socksDial.DialContext(ctx, network, addr)
}

// DialFirefoxTLS dials addr through the carrier and completes the TLS
// handshake with a FIREFOX ClientHello (uTLS HelloFirefox_Auto), the
// upstream's dialFirefoxTLS with the raw socket swapped for the
// carrier. The preset offers ALPN h2 + http/1.1; the http2.Transport
// on top speaks the negotiated h2 natively.
func (d *Dialer) DialFirefoxTLS(ctx context.Context, network, addr string) (net.Conn, error) {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, fmt.Errorf("carrier address %q: %w", addr, err)
	}
	rawConn, err := d.DialContext(ctx, network, addr)
	if err != nil {
		return nil, err
	}

	conn := utls.UClient(rawConn, &utls.Config{
		ServerName: host,
		MinVersion: utls.VersionTLS12,
	}, utls.HelloFirefox_Auto)
	handshakeCtx, cancel := context.WithTimeout(ctx, TLSTimeout)
	defer cancel()
	if err := conn.HandshakeContext(handshakeCtx); err != nil {
		rawConn.Close()
		return nil, err
	}
	return conn, nil
}

// NewControlPlaneTransport builds the http2.Transport whose TLS rides
// the uTLS Firefox ClientHello DIALED THROUGH the carrier — the
// chaining upgrade over the upstream's -api-proxy path (which pins
// HTTP/1.1 + Go's ClientHello and would walk straight back into the
// Fastly ClientHello blacklist). Install it with the upstream's
// SetControlPlaneTransport BEFORE the first control-plane request.
func NewControlPlaneTransport(d *Dialer) *http2.Transport {
	return &http2.Transport{
		// The tls.Config argument is unused: the uTLS preset owns the
		// ClientHello shape (mirrors the upstream's own transport).
		DialTLS: func(network, addr string, _ *tls.Config) (net.Conn, error) {
			return d.DialFirefoxTLS(context.Background(), network, addr)
		},
	}
}
