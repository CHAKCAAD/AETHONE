package socks

// GUARDIAN-BOOTSTRAP STAGE 7 — the DATA-PLANE SEPARATION proof (mission
// «تست Data Plane» / §4-1):
//
//	The user's real traffic (the SOCKS5 CONNECT the app's other engines
//	and the OS-level TUN feed into this listener) has EXACTLY ONE path:
//	the TunnelOpener seam — the live MASQUE/H2/H3 session to the
//	Mozilla/Fastly tunnel. It structurally never touches the
//	control-plane seam (vpnclient.SetControlPlaneTransport), which is
//	the ONE seam the Guardian bootstrap's RoutingRoundTripper occupies.
//
// This test drives a REAL user connection (SOCKS5 greeting + DOMAIN
// CONNECT + payload echo) through the production server while the
// control-plane seam is installed with the PRODUCTION routing shape —
// RoutingRoundTripper{direct leg, proxied leg, Guardian allowlist} —
// and proves the separation with three witnesses:
//
//	1. the tunnel opener served the user's target authority (the data
//	   really flowed through the tunnel seam);
//	2. the DIRECT control-plane leg recorded ZERO requests (no user
//	   byte triggered a control-plane request of any kind);
//	3. the bootstrap-proxy stand-in accepted ZERO connections (no user
//	   byte ever dialed the helper proxy — the mission's «مسیرهای
//	   غیرمجاز به پراکسی کمکی هدایت نمی‌شوند»).
//
// The inverse direction (the Guardian token request DOES ride the
// proxied leg, non-allowlisted control-plane URLs stay direct) is
// proven end-to-end in internal/cptransport/routing_test.go
// (TestEndToEndGuardianThroughProxyEverythingElseDirect) and in
// cmd/libfirefoxvpn/guardianprobe_test.go — together the two sides
// close the mission's full data-plane separation matrix.
import (
	"io"
	"net"
	"net/http"
	"sync/atomic"
	"testing"
	"time"

	"aethone/fxv/internal/cptransport"

	vpnclient "firefox-vpn-client"
)

// recordingDirect counts every request the DIRECT control-plane leg
// sees. The data plane must never produce one.
type recordingDirect struct {
	hits atomic.Int32
}

func (r *recordingDirect) RoundTrip(*http.Request) (*http.Response, error) {
	r.hits.Add(1)
	return nil, net.UnknownNetworkError("the direct leg was never expected to serve anything")
}

// recordingOpener echoes like the relay tests' fakeOpener and records
// every authority the DATA plane asked the tunnel to open.
type recordingOpener struct {
	authorities atomic.Pointer[[]string]
}

func (o *recordingOpener) OpenTunnel(authority string) (net.Conn, error) {
	current := o.authorities.Load()
	next := make([]string, len(*current), len(*current)+1)
	copy(next, *current)
	next = append(next, authority)
	o.authorities.Store(&next)

	c1, c2 := net.Pipe()
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := c2.Read(buf)
			if n > 0 {
				if _, werr := c2.Write(buf[:n]); werr != nil {
					return
				}
			}
			if err != nil {
				return
			}
		}
	}()
	return halfClosePipeConn{Conn: c1}, nil
}

func TestUserDataPlaneStaysOnTheTunnelWithABootstrapControlPlane(t *testing.T) {
	// --- the bootstrap-proxy stand-in: accepts and counts, nothing else.
	proxyListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("proxy listen: %v", err)
	}
	var proxyHits atomic.Int32
	proxyDone := make(chan struct{})
	go func() {
		defer close(proxyDone)
		for {
			conn, err := proxyListener.Accept()
			if err != nil {
				return // closed — the count is final
			}
			proxyHits.Add(1)
			_ = conn.Close()
		}
	}()
	defer func() {
		_ = proxyListener.Close()
		select {
		case <-proxyDone:
		case <-time.After(2 * time.Second):
		}
	}()

	// --- the PRODUCTION control-plane shape, installed on the pinned
	// client's one process-wide seam (exactly what an engine spawned
	// with apiProxy runs with): direct leg + proxied leg + the Guardian
	// allowlist. The direct leg counts; the proxied leg points at the
	// recording stand-in.
	allowlist, err := cptransport.NewGuardianAllowlist(
		"https://vpn.mozilla.org",
		cptransport.AllowedRequest{Method: http.MethodGet, Path: "/api/v1/fpn/token"},
	)
	if err != nil {
		t.Fatalf("allowlist: %v", err)
	}
	proxied, err := cptransport.NewProxyRoundTripper(
		"http://" + proxyListener.Addr().String())
	if err != nil {
		t.Fatalf("proxy round tripper: %v", err)
	}
	direct := &recordingDirect{}
	vpnclient.SetControlPlaneTransport(cptransport.NewRoutingRoundTripper(
		direct, proxied, allowlist))
	defer vpnclient.SetControlPlaneTransport(vpnclient.NewControlPlaneTransport())

	// --- the DATA plane: the production SOCKS server on the tunnel seam.
	opener := &recordingOpener{}
	empty := []string{}
	opener.authorities.Store(&empty)
	addr, stop := startTestServer(t, opener)
	defer stop()

	// A REAL user connection: greeting + DOMAIN CONNECT (the target is
	// resolved by the tunnel, exactly as the walk's engines dial) + a
	// payload the tunnel echoes back.
	conn, reply := dialAndConnect(t, addr, "user-traffic.example.org:443")
	defer conn.Close()
	if reply != 0x00 {
		t.Fatalf("CONNECT reply = %#x", reply)
	}
	_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
	payload := []byte("mozilla-tunnel-user-data")
	if _, err := conn.Write(payload); err != nil {
		t.Fatalf("user write: %v", err)
	}
	echo := make([]byte, len(payload))
	if _, err := io.ReadFull(conn, echo); err != nil {
		t.Fatalf("user read: %v", err)
	}
	if string(echo) != string(payload) {
		t.Fatalf("echo = %q, want %q", echo, payload)
	}

	// --- witness 1: the data flowed THROUGH THE TUNNEL.
	got := *opener.authorities.Load()
	if len(got) != 1 || got[0] != "user-traffic.example.org:443" {
		t.Fatalf("tunnel authorities = %v, want exactly [user-traffic.example.org:443]", got)
	}
	// --- witness 2: no control-plane request happened at all.
	if n := direct.hits.Load(); n != 0 {
		t.Fatalf("direct control-plane leg saw %d requests — the data plane must never touch it", n)
	}
	// --- witness 3: nothing ever dialed the bootstrap proxy.
	if n := proxyHits.Load(); n != 0 {
		t.Fatalf("bootstrap proxy stand-in accepted %d connections — user data must never ride it", n)
	}
}
