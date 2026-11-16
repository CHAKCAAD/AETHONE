package upstream

import (
        "context"
        "crypto/tls"
        "crypto/x509"
        "fmt"
        "net"
        "sync/atomic"
        "time"

        utls "github.com/refraction-networking/utls"
        "golang.org/x/net/http2"

        vpnclient "firefox-vpn-client"
)

const controlPlaneSOCKSTimeout = 15 * time.Second

// controlPlaneRoots, when set, is the root pool the carrier transport's
// TLS verifies against (nil: the system's — production never sets it;
// the reference's firefoxtls.Handshake carries the same seam).
var controlPlaneRoots atomic.Pointer[x509.CertPool]

// SetControlPlaneRoots installs the verification roots for the carrier
// transport's TLS connections.
func SetControlPlaneRoots(pool *x509.CertPool) {
        if pool == nil {
                controlPlaneRoots.Store(nil)
                return
        }
        controlPlaneRoots.Store(pool)
}

// NewSOCKS5ControlPlaneTransport preserves the pinned Firefox uTLS
// ClientHello while dialing the Mozilla control plane through Aether's
// loopback SOCKS5 listener. This is installed before RemoteSettings,
// Guardian, or token-refresh requests are made by the tunnel role.
//
// 2.0.0 — the carrier no longer fails closed: when the SOCKS CONNECT
// itself fails (the carrier refused the target, or its egress is refused
// by the edge — the failure the owner measured as
// firefoxtransport:networkUnavailable in BOTH carrier modes), the dial
// falls back to DIRECT: the process resolver's racing policy answers the
// name and the connection carries the same pinned Firefox hello (with
// the reference's hello split). The round-4 decree keeps its order — the
// carrier is still tried FIRST — but a refused carrier can no longer
// take the whole walk down with it.
func NewSOCKS5ControlPlaneTransport(proxyAddr string) *http2.Transport {
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
                                // The carrier could not open the target. Nothing was
                                // sent through it, so nothing is sent twice: the direct
                                // dial takes over with its OWN budget (the carrier's
                                // attempt must not eat it).
                                directCtx, directCancel := context.WithTimeout(context.Background(), controlPlaneSOCKSTimeout)
                                defer directCancel()
                                raw, err = directControlPlaneDial(directCtx, network, address)
                                if err != nil {
                                        return nil, err
                                }
                                conn := utls.UClient(raw, &utls.Config{
                                        ServerName: host,
                                        MinVersion: tls.VersionTLS12,
                                        RootCAs:    controlPlaneRoots.Load(),
                                }, utls.HelloFirefox_Auto)
                                if err := conn.HandshakeContext(directCtx); err != nil {
                                        _ = raw.Close()
                                        return nil, err
                                }
                                return conn, nil
                        }
                        conn := utls.UClient(raw, &utls.Config{
                                ServerName: host,
                                MinVersion: tls.VersionTLS12,
                                RootCAs:    controlPlaneRoots.Load(),
                        }, utls.HelloFirefox_Auto)
                        if err := conn.HandshakeContext(ctx); err != nil {
                                _ = raw.Close()
                                return nil, err
                        }
                        return conn, nil
                },
        }
}

// directControlPlaneDial dials the control-plane target straight from the
// device: the process resolver's racing policy answers the name and the
// connection is wrapped with the reference's hello split before TLS.
func directControlPlaneDial(ctx context.Context, network, address string) (net.Conn, error) {
        dialer := &net.Dialer{Timeout: controlPlaneSOCKSTimeout}
        raw, err := dialer.DialContext(ctx, network, address)
        if err != nil {
                return nil, fmt.Errorf("carrier and direct dials both failed: %w", err)
        }
        return vpnclient.WrapHelloSplit(raw), nil
}
