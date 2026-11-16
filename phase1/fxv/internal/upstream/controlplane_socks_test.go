package upstream

import (
        "context"
        "crypto/x509"
        "io"
        "net"
        "net/http"
        "net/http/httptest"
        "net/url"
        "testing"
        "time"
)

// TestSOCKSTransportFallsBackToDirect (2.0.0 — the owner's
// firefoxtransport:networkUnavailable in BOTH carrier modes): a control
// plane dial whose carrier CONNECT is refused must still complete through
// the direct dial — the same pinned hello, its own budget.
func TestSOCKSTransportFallsBackToDirect(t *testing.T) {
        // The real target: a TLS server on loopback playing the control-plane
        // endpoint.
        target := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                _, _ = w.Write([]byte(`{"ok":true}`))
        }))
        defer target.Close()
        targetURL, _ := url.Parse(target.URL)
        pool := x509.NewCertPool()
        pool.AddCert(target.Certificate())
        SetControlPlaneRoots(pool)
        t.Cleanup(func() { SetControlPlaneRoots(nil) })

        // A carrier that refuses every CONNECT: a TCP listener that closes at
        // once.
        refused, err := net.Listen("tcp", "127.0.0.1:0")
        if err != nil {
                t.Fatal(err)
        }
        defer refused.Close()
        go func() {
                for {
                        c, err := refused.Accept()
                        if err != nil {
                                return
                        }
                        _ = c.Close()
                }
        }()

        transport := NewSOCKS5ControlPlaneTransport(refused.Addr().String())
        if transport.DialTLS == nil {
                t.Fatal("the transport exposes no DialTLS")
        }
        ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
        defer cancel()

        // The dial runs in a goroutine because DialTLS is a plain function
        // field; the context bounds the wait.
        type dialResult struct {
                conn net.Conn
                err  error
        }
        ch := make(chan dialResult, 1)
        go func() {
                conn, err := transport.DialTLS("tcp", targetURL.Host, nil)
                ch <- dialResult{conn, err}
        }()
        var conn net.Conn
        select {
        case r := <-ch:
                if r.err != nil {
                        t.Fatalf("the direct fallback did not fire: %v", r.err)
                }
                conn = r.conn
        case <-ctx.Done():
                t.Fatal("the dial hung — the fallback did not fire")
        }
        defer conn.Close()

        req, _ := http.NewRequest(http.MethodGet, target.URL+"/", nil)
        _ = req.Write(conn)
        _ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
        buf := make([]byte, 4096)
        n, err := conn.Read(buf)
        if err != nil && err != io.EOF {
                t.Fatalf("reading the response: %v", err)
        }
        if n == 0 {
                t.Fatal("no response through the fallback connection")
        }
}

// TestSOCKSTransportCarrierFirst: with a WORKING carrier the dial goes
// through it (a plain CONNECT relay) — the round-4 decree keeps its
// order.
func TestSOCKSTransportCarrierFirst(t *testing.T) {
        target := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                _, _ = w.Write([]byte(`{"ok":true}`))
        }))
        defer target.Close()
        targetURL, _ := url.Parse(target.URL)
        pool := x509.NewCertPool()
        pool.AddCert(target.Certificate())
        SetControlPlaneRoots(pool)
        t.Cleanup(func() { SetControlPlaneRoots(nil) })

        // A minimal SOCKS5 carrier: no-auth, CONNECT to whatever is asked.
        dialedCh := make(chan string, 4)
        relay, err := net.Listen("tcp", "127.0.0.1:0")
        if err != nil {
                t.Fatal(err)
        }
        defer relay.Close()
        go func() {
                for {
                        c, err := relay.Accept()
                        if err != nil {
                                return
                        }
                        go serveMiniSOCKS5(t, c, dialedCh)
                }
        }()

        transport := NewSOCKS5ControlPlaneTransport(relay.Addr().String())
        type dialResult struct {
                conn net.Conn
                err  error
        }
        ch := make(chan dialResult, 1)
        go func() {
                conn, err := transport.DialTLS("tcp", targetURL.Host, nil)
                ch <- dialResult{conn, err}
        }()
        select {
        case r := <-ch:
                if r.err != nil {
                        t.Fatalf("the carrier dial failed: %v", r.err)
                }
                _ = r.conn.Close()
        case <-time.After(30 * time.Second):
                t.Fatal("the carrier dial hung")
        }
        if dialed := <-dialedCh; dialed != targetURL.Host {
                t.Fatalf("the carrier must carry the target by hostname, got %q", dialed)
        }
}

// serveMiniSOCKS5 answers a no-auth CONNECT by relaying to the asked
// host.
func serveMiniSOCKS5(t *testing.T, c net.Conn, dialed chan<- string) {
        t.Helper()
        defer c.Close()
        _ = c.SetDeadline(time.Now().Add(30 * time.Second))
        // greeting: version, nmethods, the methods themselves (one: no-auth)
        buf := make([]byte, 3)
        if _, err := io.ReadFull(c, buf[:3]); err != nil {
                return
        }
        if _, err := c.Write([]byte{5, 0}); err != nil {
                return
        }
        // request
        if _, err := io.ReadFull(c, buf[:3]); err != nil {
                return
        }
        if buf[1] != 1 {
                return
        }
        atyp := make([]byte, 1)
        if _, err := io.ReadFull(c, atyp); err != nil {
                return
        }
        var host string
        switch atyp[0] {
        case 3:
                l := make([]byte, 1)
                if _, err := io.ReadFull(c, l); err != nil {
                        return
                }
                name := make([]byte, l[0])
                if _, err := io.ReadFull(c, name); err != nil {
                        return
                }
                host = string(name)
        case 1:
                ip := make([]byte, 4)
                if _, err := io.ReadFull(c, ip); err != nil {
                        return
                }
                host = net.IP(ip).String()
        default:
                return
        }
        port := make([]byte, 2)
        if _, err := io.ReadFull(c, port); err != nil {
                return
        }
        dialed <- net.JoinHostPort(host, itoa(int(port[0])<<8|int(port[1])))
        upstreamConn, err := net.DialTimeout("tcp", net.JoinHostPort(host, itoa(int(port[0])<<8|int(port[1]))), 10*time.Second)
        if err != nil {
                _, _ = c.Write([]byte{5, 1, 0, 1, 0, 0, 0, 0, 0, 0})
                return
        }
        defer upstreamConn.Close()
        if _, err := c.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
                return
        }
        done := make(chan struct{}, 2)
        go func() { _, _ = io.Copy(upstreamConn, c); done <- struct{}{} }()
        go func() { _, _ = io.Copy(c, upstreamConn); done <- struct{}{} }()
        <-done
}

func itoa(n int) string {
        if n == 0 {
                return "0"
        }
        var out []byte
        for n > 0 {
                out = append([]byte{byte('0' + n%10)}, out...)
                n /= 10
        }
        return string(out)
}
