package carrier

// The carrier tests: URL shape, the SOCKS5 dial through the fxv socks
// server itself (the same wire the aether listener speaks), and the
// uTLS Firefox ClientHello handshake riding a carrier connection
// against a local TLS 1.3 + h2 server. All loopback; no network.

import (
	"bufio"
	"context"
	"encoding/binary"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"aethone/fxv/internal/socks"
)

// TestNewURLShape walks the URL gate: the two socks schemes are
// accepted, everything else a host might paste is refused.
func TestNewURLShape(t *testing.T) {
	ok := []string{
		"socks5://127.0.0.1:1819",
		"socks5h://127.0.0.1:1819",
		"socks5://localhost:1819",
		"socks5://user:pass@127.0.0.1:1819",
	}
	for _, raw := range ok {
		if _, err := New(raw); err != nil {
			t.Errorf("New(%q) = %v, want ok", raw, err)
		}
	}
	bad := []string{
		"",                            // empty
		"127.0.0.1:1819",              // no scheme
		"http://127.0.0.1:1819",       // wrong scheme
		"https://127.0.0.1:1819",      // wrong scheme
		"socks5://127.0.0.1",          // no port
		"socks5://",                   // no host
		"socks5://127.0.0.1:1819/p",   // path
		"socks5://127.0.0.1:1819?x=1", // query
	}
	for _, raw := range bad {
		if _, err := New(raw); err == nil {
			t.Errorf("New(%q) = ok, want error", raw)
		}
	}
}

// echoOpener is a fxv socks.TunnelOpener whose tunnels are plain TCP
// pipes to the target (the "internet" side of the test).
type echoOpener struct{}

func (echoOpener) OpenTunnel(authority string) (net.Conn, error) {
	return net.Dial("tcp", authority)
}

// testSink drops the server's diagnostics.
type testSink struct{}

func (testSink) Debugf(string, ...any) {}
func (testSink) Infof(string, ...any)  {}
func (testSink) Warnf(string, ...any)  {}
func (testSink) Verbose() bool         { return false }

// startSocksServer runs the fxv SOCKS5 CONNECT server on a random
// loopback port and returns its dial address.
func startSocksServer(t *testing.T) string {
	t.Helper()
	srv := socks.NewServer(echoOpener{}, 5*time.Second, 0, 0, testSink{})
	addr, err := srv.Listen("127.0.0.1:0")
	if err != nil {
		t.Fatalf("socks listen: %v", err)
	}
	t.Cleanup(func() { _ = srv.Close() })
	return addr.String()
}

// TestDialContextRoundTrip proves the SOCKS5 client path: bytes dialed
// through the carrier arrive at a plain TCP listener (the aether
// listener's CONNECT wire, spoken by the fxv server).
func TestDialContextRoundTrip(t *testing.T) {
	target, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("target listen: %v", err)
	}
	defer target.Close()
	go func() {
		for {
			c, err := target.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				_, _ = io.Copy(c, c)
			}(c)
		}
	}()

	proxyAddr := startSocksServer(t)
	d, err := New("socks5://" + proxyAddr)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	conn, err := d.DialContext(context.Background(), "tcp", target.Addr().String())
	if err != nil {
		t.Fatalf("DialContext: %v", err)
	}
	defer conn.Close()

	const payload = "firefox-over-warp roundtrip"
	if _, err := conn.Write([]byte(payload + "\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if strings.TrimSpace(line) != payload {
		t.Fatalf("roundtrip = %q, want %q", line, payload)
	}
}

// TestDialFirefoxTLSFirefoxHello proves the anti-bot posture survives
// the chaining, using the pinned upstream's own test pattern
// (http_client_test.go TestControlPlaneTransportDialsFirefoxHello): a
// raw listener behind the carrier captures the first TLS record — the
// handshake never completes, so no certificate is ever verified; what
// matters is that a (large, Firefox-shaped) ClientHello arrived THROUGH
// the SOCKS carrier.
func TestDialFirefoxTLSFirefoxHello(t *testing.T) {
	target, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	helloCh := make(chan []byte, 1)
	go func() {
		conn, err := target.Accept()
		if err != nil {
			close(helloCh)
			return
		}
		buf := make([]byte, 2048)
		_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
		n, _ := conn.Read(buf)
		_ = conn.Close()
		helloCh <- buf[:n]
	}()

	proxyAddr := startSocksServer(t)
	d, err := New("socks5h://" + proxyAddr)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	// The handshake fails against the raw listener (it closes after the
	// capture); only the ClientHello matters.
	_, _ = d.DialFirefoxTLS(context.Background(), "tcp", target.Addr().String())

	hello, ok := <-helloCh
	if !ok || len(hello) < 48 {
		t.Fatalf("no ClientHello captured (%d bytes)", len(hello))
	}
	if hello[0] != 0x16 {
		t.Fatalf("not a TLS handshake record: first byte %#x", hello[0])
	}
	assertFirefoxHello(t, hello)
}

// assertFirefoxHello is the pinned upstream's own fingerprint check
// (http_client_test.go TestControlPlaneTransportDialsFirefoxHello):
// Firefox leads with the TLS 1.3 suite 0x1301, still offers the legacy
// RSA/AEAD suites 0x0035/0x009c, and carries >= 15 suites — Go's
// default hello leads with ECDHE, omits the legacy pair, and has 13.
func assertFirefoxHello(t *testing.T, hello []byte) {
	t.Helper()
	// record(5) + handshake header(4) + version(2) + random(32) = 43
	pos := 43
	sidLen := int(hello[pos])
	pos += 1 + sidLen
	csLen := int(binary.BigEndian.Uint16(hello[pos : pos+2]))
	cipherCount := csLen / 2
	firstCipher := binary.BigEndian.Uint16(hello[pos+2 : pos+4])
	has0035, has009c := false, false
	for i := 0; i < cipherCount; i++ {
		switch binary.BigEndian.Uint16(hello[pos+2+2*i : pos+4+2*i]) {
		case 0x0035:
			has0035 = true
		case 0x009c:
			has009c = true
		}
	}
	if firstCipher != 0x1301 || !has0035 || !has009c || cipherCount < 15 {
		t.Fatalf("ClientHello is not the uTLS Firefox preset: first=%#04x count=%d legacy0035=%v legacy009c=%v",
			firstCipher, cipherCount, has0035, has009c)
	}
}

// TestControlPlaneTransportDialsThroughCarrier wires the full
// http2.Transport seam: its DialTLS reaches a raw listener THROUGH the
// SOCKS server and presents the same Firefox-shaped ClientHello.
func TestControlPlaneTransportDialsThroughCarrier(t *testing.T) {
	target, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	helloCh := make(chan []byte, 1)
	go func() {
		conn, err := target.Accept()
		if err != nil {
			close(helloCh)
			return
		}
		buf := make([]byte, 2048)
		_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
		n, _ := conn.Read(buf)
		_ = conn.Close()
		helloCh <- buf[:n]
	}()

	proxyAddr := startSocksServer(t)
	d, err := New("socks5://" + proxyAddr)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	tr := NewControlPlaneTransport(d)
	if tr.DialTLS == nil {
		t.Fatal("DialTLS must be set (uTLS Firefox ClientHello)")
	}
	// The handshake fails against the raw listener by design; the
	// captured record is the assertion.
	_, _ = tr.DialTLS("tcp", target.Addr().String(), nil)

	hello, ok := <-helloCh
	if !ok || len(hello) < 48 {
		t.Fatalf("no ClientHello captured (%d bytes)", len(hello))
	}
	if hello[0] != 0x16 {
		t.Fatalf("not a TLS handshake record: first byte %#x", hello[0])
	}
	assertFirefoxHello(t, hello)
}

// assertFirefoxHello is the pinned upstream's own fingerprint check
// (http_client_test.go TestControlPlaneTransportDialsFirefoxHello):
// Firefox leads with the TLS 1.3 suite 0x1301, still offers the legacy
// RSA/AEAD suites 0x0035/0x009c, and carries >= 15 suites — Go's
// default hello leads with ECDHE, omits the legacy pair, and has 13.
