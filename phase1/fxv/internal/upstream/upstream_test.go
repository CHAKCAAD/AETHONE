package upstream

// Unit tests for the adapted exit-probe parser (both wire shapes) and
// the tunnel write buffer's bounded behavior.

import (
        "bytes"
        "context"
        "io"
        "net"
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
