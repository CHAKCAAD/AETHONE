package upstream

// Unit tests for the adapted exit-probe parser (both wire shapes) and
// the tunnel write buffer's bounded behavior.

import (
        "bytes"
        "context"
        "errors"
        "fmt"
        "io"
        "net"
        "strings"
        "testing"
        "time"
)

// blockingOpener never resolves on its own.
type blockingOpener struct{}

func (blockingOpener) OpenTunnel(string) (net.Conn, error) { blockForever(); return nil, nil }

func blockForever() {
        select {}
}

func ioDeadlineCtx(t *testing.T) (ctx context.Context) {
        ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
        t.Cleanup(cancel)
        return ctx
}

func TestParseExitProbeResponseKV(t *testing.T) {
        ip, cc, err := ParseExitProbeResponse([]byte("fl=abc\nip=203.0.113.7\nloc=DE\ntls=1.3\n"))
        if err != nil || ip != "203.0.113.7" || cc != "DE" {
                t.Fatalf("kv: %v %s %s", err, ip, cc)
        }
}

func TestParseExitProbeResponseJSON(t *testing.T) {
        ip, cc, err := ParseExitProbeResponse([]byte(`{"ip":"198.51.100.9","country_code":"FR"}`))
        if err != nil || ip != "198.51.100.9" || cc != "FR" {
                t.Fatalf("json: %v %s %s", err, ip, cc)
        }
}

func TestParseExitProbeResponseRejectsGarbage(t *testing.T) {
        if _, _, err := ParseExitProbeResponse([]byte("nothing useful")); err == nil {
                t.Fatal("garbage must be rejected")
        }
        if _, _, err := ParseExitProbeResponse([]byte("ip=not-an-ip\nloc=DE")); err == nil {
                t.Fatal("an invalid IP must be rejected")
        }
        if _, _, err := ParseExitProbeResponse([]byte("ip=1.2.3.4\nloc=D")); err == nil {
                t.Fatal("a one-letter country must be rejected")
        }
}

func TestTunnelWriteBufferRoundTrip(t *testing.T) {
        b := NewTunnelWriteBuffer(16)
        payload := []byte("hello tunnel world")
        go func() {
                _, _ = b.Write(payload)
                _ = b.Close()
        }()
        var out bytes.Buffer
        buf := make([]byte, 7)
        for {
                n, err := b.Read(buf)
                if n > 0 {
                        out.Write(buf[:n])
                }
                if err == io.EOF {
                        break
                }
                if err != nil {
                        t.Fatalf("read: %v", err)
                }
        }
        if !bytes.Equal(out.Bytes(), payload) {
                t.Fatalf("round trip = %q", out.String())
        }
}

func TestTunnelWriteBufferFailRead(t *testing.T) {
        b := NewTunnelWriteBuffer(4)
        b.FailRead(io.ErrClosedPipe)
        if _, err := b.Read(make([]byte, 4)); err != io.ErrClosedPipe {
                t.Fatalf("read err = %v", err)
        }
}

func TestOpenTunnelContextCancel(t *testing.T) {
        // A blocked opener canceled by the context surfaces ctx.Err.
        opener := blockingOpener{}
        done := make(chan error, 1)
        go func() {
                _, err := OpenTunnelContext(ioDeadlineCtx(t), opener, "example.com:443")
                done <- err
        }()
        select {
        case err := <-done:
                t.Fatalf("resolved too early: %v", err)
        case <-time.After(50 * time.Millisecond):
        }
        // context canceled by the deadline helper
        err := <-done
        if err == nil {
                t.Fatal("the canceled open must fail")
        }
}

// TestSessionEstablishedLog pins the stage-3/stage-5 diagnostics
// contract: the on-device log line (controller.Start → host Logf →
// core-log.txt) must carry the ACTUALLY-live transport, the proxy, the
// connected endpoint (remote, when the session reports one), and the
// establish latency for BOTH h2 and h3 — the fields the owner greps
// the log for when recording the mission's "real Transport" and
// "Endpoint" baseline fields or comparing h2 vs h3 on-device.
func TestSessionEstablishedLog(t *testing.T) {
        line := sessionEstablishedLog("h3", "lfpb115.m1.fastly-masque.net:2499", "192.0.2.10:443", 1234*time.Millisecond)
        for _, want := range []string{
                "transport=h3",
                "proxy=lfpb115.m1.fastly-masque.net:2499",
                "remote=192.0.2.10:443",
                "establish_latency=1.234s",
        } {
                if !strings.Contains(line, want) {
                        t.Fatalf("line = %q, missing %q", line, want)
                }
        }
        h2 := sessionEstablishedLog("h2", "p.example.net:443", "23.192.228.80:443", 0)
        if !strings.Contains(h2, "transport=h2") {
                t.Fatalf("h2 line = %q", h2)
        }
        if !strings.Contains(h2, "remote=23.192.228.80:443") {
                t.Fatalf("h2 line must carry the connected endpoint too: %q", h2)
        }
        if !strings.Contains(h2, "establish_latency=0s") {
                t.Fatalf("zero latency must render as 0s: %q", h2)
        }
        // An IPv6 endpoint renders with the bracketed host form.
        v6 := sessionEstablishedLog("h2", "p.example.net:443", "[2001:db8::1]:443", time.Second)
        if !strings.Contains(v6, "remote=[2001:db8::1]:443") {
                t.Fatalf("v6 endpoint must render bracketed: %q", v6)
        }
        // A session that cannot report a remote omits the field — it is
        // never rendered empty.
        bare := sessionEstablishedLog("h2", "p.example.net:443", "", time.Second)
        if strings.Contains(bare, "remote=") {
                t.Fatalf("empty remote must omit the field: %q", bare)
        }
}

// TestRedactedError (Stage 6): the SOCKS warn line's error rendering —
// the proxy CONNECT answer body is redacted unless verbose (upstream
// logErr parity), other errors pass through, nil renders as <nil>.
func TestRedactedError(t *testing.T) {
        if got := RedactedError(nil, false); got != "<nil>" {
                t.Fatalf("nil = %q", got)
        }

        plain := &net.OpError{Op: "dial", Err: errors.New("connection refused")}
        if got, want := RedactedError(plain, false), plain.Error(); got != want {
                t.Fatalf("plain error non-verbose = %q, want %q", got, want)
        }

        full := &proxyConnectHTTPError{statusCode: 403, status: "403 Forbidden", body: "<html>secret error page</html>"}
        if got := RedactedError(full, true); !strings.Contains(got, "secret error page") {
                t.Fatalf("verbose must keep the body: %q", got)
        }
        redacted := RedactedError(full, false)
        if strings.Contains(redacted, "secret error page") {
                t.Fatalf("non-verbose leaked the body: %q", redacted)
        }
        if !strings.Contains(redacted, "<redacted; use -verbose>") {
                t.Fatalf("non-verbose must carry the marker: %q", redacted)
        }
        if !strings.Contains(redacted, "403 Forbidden") {
                t.Fatalf("the status line stays (not sensitive): %q", redacted)
        }

        // A body-less CONNECT failure renders identically at both levels.
        bare := &proxyConnectHTTPError{statusCode: 502, status: "502 Bad Gateway"}
        if got, want := RedactedError(bare, false), bare.Error(); got != want {
                t.Fatalf("body-less non-verbose = %q, want %q", got, want)
        }

        // Wrapped CONNECT errors are unwrapped to the typed cause.
        wrapped := fmt.Errorf("open tunnel: %w", full)
        if got := RedactedError(wrapped, false); strings.Contains(got, "secret error page") {
                t.Fatalf("wrapped body leaked: %q", got)
        } else if !strings.Contains(got, "<redacted; use -verbose>") {
                t.Fatalf("wrapped non-verbose must carry the marker: %q", got)
        }
}
