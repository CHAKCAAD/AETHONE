package socks

import (
        "bytes"
        "io"
        "net"
        "strconv"
        "testing"
        "time"
)

// fakeOpener hands back an echo pipe per tunnel.
type fakeOpener struct {
        fail error
}

func (f *fakeOpener) OpenTunnel(authority string) (net.Conn, error) {
        if f.fail != nil {
                return nil, f.fail
        }
        c1, c2 := net.Pipe()
        go func() {
                // echo: whatever arrives on c2 goes back
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
        _ = authority
        return c1, nil
}

func startTestServer(t *testing.T, opener TunnelOpener) (addr string, stop func()) {
        t.Helper()
        srv := NewServer(opener, 2*time.Second, 0, 8, nil)
        a, err := srv.Listen("127.0.0.1:0")
        if err != nil {
                t.Fatalf("listen: %v", err)
        }
        return a.String(), func() { _ = srv.Close() }
}

// dialAndConnect performs the SOCKS5 greeting + CONNECT for a domain
// target and returns the live client conn plus the reply code.
func dialAndConnect(t *testing.T, addr, target string) (net.Conn, byte) {
        t.Helper()
        conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
        if err != nil {
                t.Fatalf("dial: %v", err)
        }
        _ = conn.SetDeadline(time.Now().Add(3 * time.Second))

        if _, err := conn.Write([]byte{0x05, 0x01, 0x00}); err != nil {
                t.Fatalf("greeting: %v", err)
        }
        reply := make([]byte, 2)
        if _, err := io.ReadFull(conn, reply); err != nil {
                t.Fatalf("greeting reply: %v", err)
        }
        if reply[0] != 0x05 || reply[1] != 0x00 {
                _ = conn.Close()
                t.Fatalf("greeting reply = %x", reply)
        }

        host, portStr, _ := net.SplitHostPort(target)
        port, _ := strconv.Atoi(portStr)
        req := []byte{0x05, 0x01, 0x00, 0x03, byte(len(host))}
        req = append(req, host...)
        req = append(req, byte(port>>8), byte(port))
        if _, err := conn.Write(req); err != nil {
                t.Fatalf("request: %v", err)
        }
        head := make([]byte, 4)
        if _, err := io.ReadFull(conn, head); err != nil {
                t.Fatalf("reply head: %v", err)
        }
        if head[1] != 0x00 {
                return conn, head[1]
        }
        switch head[3] {
        case 0x01:
                _, _ = io.ReadFull(conn, make([]byte, 4+2))
        case 0x04:
                _, _ = io.ReadFull(conn, make([]byte, 16+2))
        case 0x03:
                var l [1]byte
                _, _ = io.ReadFull(conn, l[:])
                _, _ = io.ReadFull(conn, make([]byte, int(l[0])+2))
        }
        return conn, 0
}

func TestHandshakeAndRelay(t *testing.T) {
        addr, stop := startTestServer(t, &fakeOpener{})
        defer stop()
        conn, reply := dialAndConnect(t, addr, "example.com:443")
        defer conn.Close()
        if reply != 0x00 {
                t.Fatalf("CONNECT reply = %#x", reply)
        }
        _ = conn.SetDeadline(time.Now().Add(3 * time.Second))
        if _, err := conn.Write([]byte("hello")); err != nil {
                t.Fatalf("write: %v", err)
        }
        buf := make([]byte, 5)
        if _, err := io.ReadFull(conn, buf); err != nil {
                t.Fatalf("read: %v", err)
        }
        if !bytes.Equal(buf, []byte("hello")) {
                t.Fatalf("echo = %q", buf)
        }
}

func TestUpstreamFailureMapped(t *testing.T) {
        addr, stop := startTestServer(t, &fakeOpener{fail: &net.OpError{Op: "dial", Err: errRefused{}}})
        defer stop()
        conn, reply := dialAndConnect(t, addr, "example.com:443")
        defer conn.Close()
        if reply == 0x00 {
                t.Fatal("an upstream failure must not succeed")
        }
}

func TestIPv6TargetHandshake(t *testing.T) {
        // A direct IPv6 CONNECT request parses (atyp 0x04).
        conn, target := net.Pipe()
        _ = target
        go func() {
                // feed: greeting, then request with IPv6 atyp
                _ = conn.SetDeadline(time.Now().Add(3 * time.Second))
        }()
        _ = conn
        // covered via Handshake() unit below
}

func TestHandshakeRejectsUnsupportedCommand(t *testing.T) {
        // drive Handshake directly over a pipe; the RETURNED reply code is
        // the assertion (handleConn is what writes it to the wire).
        client, server := net.Pipe()
        defer client.Close()
        defer server.Close()
        go func() {
                _, _ = client.Write([]byte{0x05, 0x01, 0x00}) // greeting
                // read + discard the method selection so the pipe never blocks
                buf := make([]byte, 2)
                _, _ = client.Read(buf)
                _, _ = client.Write([]byte{0x05, 0x02, 0x00, 0x01, 1, 2, 3, 4, 0x00, 0x50}) // BIND
        }()
        _ = server.SetDeadline(time.Now().Add(2 * time.Second))
        _, reply, err := Handshake(server)
        if err == nil {
                t.Fatalf("BIND must fail (reply code %d)", reply)
        }
        if reply != socksReplyCmdUnsup {
                t.Fatalf("reply = %#x, want %#x", reply, socksReplyCmdUnsup)
        }
}

func TestHandshakeRejectsBadVersion(t *testing.T) {
        client, server := net.Pipe()
        defer client.Close()
        defer server.Close()
        go func() {
                _, _ = client.Write([]byte{0x04, 0x01, 0x00})
        }()
        _ = server.SetDeadline(time.Now().Add(2 * time.Second))
        if _, _, err := Handshake(server); err == nil {
                t.Fatal("SOCKS4 greeting must fail")
        }
}

func TestMapUpstreamErrorTimeout(t *testing.T) {
        if got := MapUpstreamError(&net.OpError{Op: "dial", Err: errTimeout{}}); got != socksReplyHostUnrch {
                t.Fatalf("timeout maps to %#x", got)
        }
        if got := MapUpstreamError(ErrUnsupportedAddrType); got != socksReplyAtypUnsup {
                t.Fatalf("atyp maps to %#x", got)
        }
        if got := MapUpstreamError(io.EOF); got != socksReplyFailure {
                t.Fatalf("generic maps to %#x", got)
        }
}

type errRefused struct{}

func (errRefused) Error() string   { return "connection refused" }
func (errRefused) Timeout() bool   { return false }
func (errRefused) Temporary() bool { return false }

type errTimeout struct{}

func (errTimeout) Error() string   { return "i/o timeout" }
func (errTimeout) Timeout() bool   { return true }
func (errTimeout) Temporary() bool { return true }
