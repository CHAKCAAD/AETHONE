package upstream

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"time"

	utls "github.com/refraction-networking/utls"
	"golang.org/x/net/http2"
)

const controlPlaneSOCKSTimeout = 15 * time.Second

// NewSOCKS5ControlPlaneTransport preserves the pinned Firefox uTLS
// ClientHello while dialing the Mozilla control plane through Aether's
// loopback SOCKS5 listener. This is installed before RemoteSettings,
// Guardian, or token-refresh requests are made by the tunnel role.
func NewSOCKS5ControlPlaneTransport(proxyAddr string) http.RoundTripper {
	dialer := &SOCKS5Dialer{ProxyAddr: proxyAddr}
	return &http2.Transport{
		DialTLS: func(network, address string, _ *tls.Config) (net.Conn, error) {
			host, _, err := net.SplitHostPort(address)
			if err != nil {
				return nil, fmt.Errorf("control plane address %q: %w", address, err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), controlPlaneSOCKSTimeout)
			defer cancel()

			raw, err := dialer.DialContext(ctx, network, address)
			if err != nil {
				return nil, err
			}
			conn := utls.UClient(raw, &utls.Config{
				ServerName: host,
				MinVersion: tls.VersionTLS12,
			}, utls.HelloFirefox_Auto)
			if err := conn.HandshakeContext(ctx); err != nil {
				_ = raw.Close()
				return nil, err
			}
			return conn, nil
		},
	}
}
