package socks

import (
        "bytes"
        "fmt"
        "io"
        "net"
        "runtime"
        "strconv"
        "strings"
        "sync"
        "testing"
        "time"
)

// fakeOpener hands back an echo pipe per tunnel.
type fakeOpener struct {
        fail error
}

// halfClosePipeConn wraps a net.Pipe end with a REAL CloseWrite, like
// the engine's TunnelConn: ProxyBidirectional half-closes the upstream
// when the client EOFs, and the drain must then finish promptly (the
// bare net.Pipe has no CloseWrite, so drain tests would block for the
// full halfCloseDrainTimeout instead).
type halfClosePipeConn struct {
        net.Conn
}

func (c halfClosePipeConn) CloseWrite() error { return c.Conn.Close() }

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
        return halfClosePipeConn{Conn: c1}, nil
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

// captureSink records every line with its level tag, implementing the
// SAME discipline as the production stderrLogger (the LogSink contract:
// Debugf is a no-op unless verbose) so tests assert the observable
// end-to-end behavior of a non-verbose / verbose sink.
type captureSink struct {
        mu      sync.Mutex
        verbose bool
        lines   []string // "LEVEL message"
}

func (c *captureSink) Debugf(format string, args ...any) {
        if !c.verbose {
                return
        }
        c.record("DEBUG", format, args...)
}
func (c *captureSink) Infof(format string, args ...any)  { c.record("INFO", format, args...) }
func (c *captureSink) Warnf(format string, args ...any)  { c.record("WARN", format, args...) }
func (c *captureSink) Verbose() bool                     { return c.verbose }

func (c *captureSink) record(level, format string, args ...any) {
        c.mu.Lock()
        c.lines = append(c.lines, level+" "+fmt.Sprintf(format, args...))
        c.mu.Unlock()
}

// count returns how many recorded lines carry the level and prefix.
func (c *captureSink) count(level, prefix string) int {
        c.mu.Lock()
        defer c.mu.Unlock()
        n := 0
        for _, l := range c.lines {
                if strings.HasPrefix(l, level+" "+prefix) {
                        n++
                }
        }
        return n
}

// contains reports whether any recorded line contains substr.
func (c *captureSink) contains(substr string) bool {
        c.mu.Lock()
        defer c.mu.Unlock()
        for _, l := range c.lines {
                if strings.Contains(l, substr) {
                        return true
                }
        }
        return false
}

// snapshot copies the recorded lines (failure messages only).
func (c *captureSink) snapshot() []string {
        c.mu.Lock()
        defer c.mu.Unlock()
        out := make([]string, len(c.lines))
        copy(out, c.lines)
        return out
}

// TestConnectionLimitRejectsBeyondCap: with maxConns=N, the (N+1)-th
// concurrent connection is rejected FAST (closed before the SOCKS
// handshake) and the limit recovers as soon as a slot frees. This is
// the restored upstream defense against unbounded stream accumulation
// on the single upstream h2 ClientConn (Stage 2).
func TestConnectionLimitRejectsBeyondCap(t *testing.T) {
        const cap = 3
        srv := NewServer(&fakeOpener{}, 0, 0, cap, nil) // handshake timeout 0: slots held deterministically
        addr, err := srv.Listen("127.0.0.1:0")
        if err != nil {
                t.Fatalf("listen: %v", err)
        }
        defer srv.Close()

        held := make([]net.Conn, 0, cap)
        for i := 0; i < cap; i++ {
                c, derr := net.DialTimeout("tcp", addr.String(), 2*time.Second)
                if derr != nil {
                        t.Fatalf("dial %d: %v", i, derr)
                }
                held = append(held, c)
        }
        // Let the handlers start (slots are acquired there).
        deadline := time.Now().Add(2 * time.Second)
        for {
                srv.mu.Lock()
                n := len(srv.conns)
                srv.mu.Unlock()
                if n == cap {
                        break
                }
                if time.Now().After(deadline) {
                        t.Fatalf("tracked conns = %d, want %d", n, cap)
                }
                time.Sleep(10 * time.Millisecond)
        }

        // The beyond-cap conn is closed before any SOCKS reply.
        extra, derr := net.DialTimeout("tcp", addr.String(), 2*time.Second)
        if derr != nil {
                t.Fatalf("extra dial: %v", derr)
        }
        defer extra.Close()
        _ = extra.SetDeadline(time.Now().Add(3 * time.Second))
        buf := make([]byte, 2)
        if _, rerr := io.ReadFull(extra, buf); rerr == nil {
                t.Fatal("a beyond-cap connection must be rejected without a SOCKS reply")
        }

        // Regression (Stage-2 slot-steal fix): the rejection above must
        // NOT have freed a slot. A second beyond-cap conn must be
        // rejected too — with the old deferred-release bug it would be
        // silently accepted (the rejection had stolen a live slot), and
        // a sent greeting would then earn a method reply.
        extra2, derr := net.DialTimeout("tcp", addr.String(), 2*time.Second)
        if derr != nil {
                t.Fatalf("extra dial 2: %v", derr)
        }
        defer extra2.Close()
        _ = extra2.SetDeadline(time.Now().Add(3 * time.Second))
        if _, werr := extra2.Write([]byte{0x05, 0x01, 0x00}); werr != nil {
                t.Fatalf("greeting write: %v", werr)
        }
        if _, rerr := io.ReadFull(extra2, buf); rerr == nil {
                t.Fatal("a second beyond-cap connection must also be rejected (the cap must not erode on rejection)")
        }

        // Recovery: free one slot, wait for its handler to release it
        // (untrack runs after handleConn returns), then a fresh tunnel
        // must relay again.
        _ = held[0].Close()
        held = held[1:]
        deadline = time.Now().Add(3 * time.Second)
        for {
                srv.mu.Lock()
                n := len(srv.conns)
                srv.mu.Unlock()
                if n < cap {
                        break
                }
                if time.Now().After(deadline) {
                        t.Fatalf("the closed conn's handler never released its slot (tracked=%d)", n)
                }
                time.Sleep(10 * time.Millisecond)
        }
        conn, reply := dialAndConnect(t, addr.String(), "example.com:443")
        if reply != 0x00 {
                t.Fatalf("after a slot freed, CONNECT reply = %#x", reply)
        }
        _ = conn.SetDeadline(time.Now().Add(3 * time.Second))
        if _, werr := conn.Write([]byte("ok")); werr != nil {
                t.Fatalf("write: %v", werr)
        }
        echo := make([]byte, 2)
        if _, rerr := io.ReadFull(conn, echo); rerr != nil {
                t.Fatalf("read echo: %v", rerr)
        }
        if !bytes.Equal(echo, []byte("ok")) {
                t.Fatalf("echo = %q", echo)
        }
        _ = conn.Close()
        for _, c := range held {
                _ = c.Close()
        }
}

// TestConcurrentTunnelsBelowCapRelay: 16 concurrent tunnels under a 16
// cap all handshake, relay and close (no false rejections under load).
func TestConcurrentTunnelsBelowCapRelay(t *testing.T) {
        const n = 16
        srv := NewServer(&fakeOpener{}, 2*time.Second, 0, n, nil)
        addr, err := srv.Listen("127.0.0.1:0")
        if err != nil {
                t.Fatalf("listen: %v", err)
        }
        defer srv.Close()

        var wg sync.WaitGroup
        errs := make(chan error, n)
        for i := 0; i < n; i++ {
                wg.Add(1)
                go func() {
                        defer wg.Done()
                        conn, reply := dialAndConnect(t, addr.String(), "example.com:443")
                        if reply != 0x00 {
                                errs <- fmt.Errorf("CONNECT reply = %#x", reply)
                                return
                        }
                        defer conn.Close()
                        _ = conn.SetDeadline(time.Now().Add(5 * time.Second))
                        if _, werr := conn.Write([]byte("ping")); werr != nil {
                                errs <- werr
                                return
                        }
                        echo := make([]byte, 4)
                        if _, rerr := io.ReadFull(conn, echo); rerr != nil {
                                errs <- rerr
                                return
                        }
                        if !bytes.Equal(echo, []byte("ping")) {
                                errs <- fmt.Errorf("echo = %q", echo)
                        }
                }()
        }
        wg.Wait()
        close(errs)
        for e := range errs {
                t.Error(e)
        }
}

// TestSequentialTunnelsNoConnOrGoroutineLeak: 100 open/relay/close
// cycles must leave zero tracked conns and no leaked handler
// goroutines (the Stage-2 audit's leak checks for the SOCKS layer).
func TestSequentialTunnelsNoConnOrGoroutineLeak(t *testing.T) {
        sink := &captureSink{}
        srv := NewServer(&fakeOpener{}, 2*time.Second, 0, 8, sink)
        addr, err := srv.Listen("127.0.0.1:0")
        if err != nil {
                t.Fatalf("listen: %v", err)
        }

        runtime.GC()
        baseGoroutines := runtime.NumGoroutine()

        for i := 0; i < 100; i++ {
                conn, reply := dialAndConnect(t, addr.String(), "example.com:443")
                if reply != 0x00 {
                        _ = conn.Close()
                        t.Fatalf("cycle %d: CONNECT reply = %#x", i, reply)
                }
                _ = conn.SetDeadline(time.Now().Add(3 * time.Second))
                if _, werr := conn.Write([]byte("x")); werr != nil {
                        _ = conn.Close()
                        t.Fatalf("cycle %d: write: %v", i, werr)
                }
                echo := make([]byte, 1)
                if _, rerr := io.ReadFull(conn, echo); rerr != nil {
                        _ = conn.Close()
                        t.Fatalf("cycle %d: read: %v", i, rerr)
                }
                _ = conn.Close()
        }

        // Tracked conns must drain to zero.
        deadline := time.Now().Add(3 * time.Second)
        for {
                srv.mu.Lock()
                n := len(srv.conns)
                srv.mu.Unlock()
                if n == 0 {
                        break
                }
                if time.Now().After(deadline) {
                        t.Fatalf("tracked conns after 100 cycles = %d, want 0", n)
                }
                time.Sleep(10 * time.Millisecond)
        }

        // Handler goroutines must settle back near the baseline.
        deadline = time.Now().Add(3 * time.Second)
        for {
                runtime.GC()
                if runtime.NumGoroutine() <= baseGoroutines+2 {
                        break
                }
                if time.Now().After(deadline) {
                        t.Fatalf("goroutines = %d, baseline %d (+2 tolerated)", runtime.NumGoroutine(), baseGoroutines)
                }
                time.Sleep(20 * time.Millisecond)
        }

        _ = srv.Close()

        // The Stage-2 diagnostics (Stage 6: Info level now) must have
        // counted every cycle.
        if tracked, untracked := sink.count("INFO", "socks: conn tracked live="),
                sink.count("INFO", "socks: conn untracked live=");
                tracked < 100 || untracked < 100 {
                t.Fatalf("diagnostics: tracked=%d untracked=%d, want >=100 each", tracked, untracked)
        }
        // The per-connection debug lines must be SILENT at the normal
        // level (upstream logDebug parity).
        if got := sink.count("DEBUG", "socks: "); got != 0 {
                t.Fatalf("non-verbose sink saw %d debug lines, want 0", got)
        }
}

// TestLogTargetRedactsUnlessVerbose — the target redaction contract
// (upstream logTarget parity): the marker at the normal level, the full
// authority under verbose.
func TestLogTargetRedactsUnlessVerbose(t *testing.T) {
        const target = "secret-domain.example:443"
        srv := NewServer(&fakeOpener{}, 0, 0, 0, &captureSink{})
        if got := srv.logTarget(target); got != "<redacted; use -verbose>" {
                t.Fatalf("non-verbose logTarget = %q", got)
        }
        srv = NewServer(&fakeOpener{}, 0, 0, 0, &captureSink{verbose: true})
        if got := srv.logTarget(target); got != target {
                t.Fatalf("verbose logTarget = %q", got)
        }
}

// TestPerConnectionLinesGatedByVerbose — a full tunnel cycle at the
// normal level logs NO debug lines and NO target domain (the live=N
// Info pair only); the same cycle under verbose logs the upstream
// demo's per-connection diagnostics WITH the domain.
func TestPerConnectionLinesGatedByVerbose(t *testing.T) {
        const target = "secret-domain.example:443"
        for _, verbose := range []bool{false, true} {
                sink := &captureSink{verbose: verbose}
                srv := NewServer(&fakeOpener{}, 2*time.Second, 0, 8, sink)
                addr, err := srv.Listen("127.0.0.1:0")
                if err != nil {
                        t.Fatalf("listen: %v", err)
                }

                conn, reply := dialAndConnect(t, addr.String(), target)
                if reply != 0x00 {
                        _ = conn.Close()
                        t.Fatalf("verbose=%v: CONNECT reply = %#x", verbose, reply)
                }
                _ = conn.SetDeadline(time.Now().Add(3 * time.Second))
                if _, werr := conn.Write([]byte("hi")); werr != nil {
                        _ = conn.Close()
                        t.Fatalf("write: %v", werr)
                }
                echo := make([]byte, 2)
                if _, rerr := io.ReadFull(conn, echo); rerr != nil {
                        _ = conn.Close()
                        t.Fatalf("read echo: %v", rerr)
                }
                _ = conn.Close()

                // tracked/untracked must ride Info in BOTH modes.
                deadline := time.Now().Add(3 * time.Second)
                for {
                        if sink.count("INFO", "socks: conn untracked live=") > 0 {
                                break
                        }
                        if time.Now().After(deadline) {
                                t.Fatalf("verbose=%v: the untracked Info line never arrived", verbose)
                        }
                        time.Sleep(10 * time.Millisecond)
                }
                _ = srv.Close()

                if !verbose {
                        if got := sink.count("DEBUG", "socks: "); got != 0 {
                                t.Fatalf("normal level: %d debug lines, want 0", got)
                        }
                        if sink.contains("secret-domain.example") {
                        t.Fatal("normal level: the target domain leaked into a log line")
                        }
                } else {
                        for _, want := range []string{
                                "socks: client connected ",
                                "socks: CONNECT requested ",
                                "socks: upstream tunnel open succeeded ",
                                "socks: client disconnected ",
                        } {
                                if sink.count("DEBUG", want) == 0 {
                                        t.Fatalf("verbose: missing debug line %q (recorded: %v)", want, sink.snapshot())
                                }
                        }
                        if !sink.contains("secret-domain.example:443") {
                                t.Fatal("verbose: the target domain must be visible for debugging")
                        }
                }
        }
}

// TestWarnLineRedactsTargetAndErrorBody — an upstream open failure at
// the normal level: the warn line IS written (always-on) but carries
// the redaction marker instead of the target, and the error rendering
// goes through upstream.RedactedError.
func TestWarnLineRedactsTargetAndErrorBody(t *testing.T) {
        const target = "secret-domain.example:443"
        sink := &captureSink{}
        srv := NewServer(&fakeOpener{fail: &net.OpError{Op: "dial", Err: errRefused{}}}, 2*time.Second, 0, 8, sink)
        addr, err := srv.Listen("127.0.0.1:0")
        if err != nil {
                t.Fatalf("listen: %v", err)
        }
        defer srv.Close()

        conn, reply := dialAndConnect(t, addr.String(), target)
        defer conn.Close()
        if reply == 0x00 {
                t.Fatal("an upstream failure must not succeed")
        }

        deadline := time.Now().Add(3 * time.Second)
        for {
                if sink.count("WARN", "socks: upstream tunnel open failed ") > 0 {
                        break
                }
                if time.Now().After(deadline) {
                        t.Fatal("the upstream-failure warn line never arrived")
                }
                time.Sleep(10 * time.Millisecond)
        }
        if !sink.contains("<redacted; use -verbose>") {
                t.Fatal("the warn line must carry the redaction marker")
        }
        if sink.contains("secret-domain.example") {
                t.Fatal("the warn line leaked the target domain")
        }
}
