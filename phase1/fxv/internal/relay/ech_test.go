package relay

// The ECH tests: the mode/config parsers, the DoH HTTPS-record lookup
// (against a local JSON server — never the real resolvers), the fixed
// and cached key paths, and the dialer's fail-closed (require) and
// best-effort (on → plain TLS fallback) walks against a local TLS
// server. A REAL ECH handshake needs a real ECH-capable server; these
// tests cover the decision logic around it.

import (
        "context"
        "crypto/tls"
        "encoding/base64"
        "io"
        "net/http"
        "net/http/httptest"
        "net/url"
        "strings"
        "sync/atomic"
        "testing"
        "time"
)

// ---------------------------------------------------------------------------
// the parsers
// ---------------------------------------------------------------------------

func TestValidateECHMode(t *testing.T) {
        for _, ok := range []string{"", ECHModeOff, ECHModeOn, ECHModeRequire} {
                if err := validateECHMode(ok); err != nil {
                        t.Fatalf("%q must be accepted: %v", ok, err)
                }
        }
        for _, bad := range []string{"auto", "ON", "sometimes"} {
                if err := validateECHMode(bad); err == nil {
                        t.Fatalf("%q must be refused", bad)
                }
        }
}

func TestParseECHConfig(t *testing.T) {
        key := base64.StdEncoding.EncodeToString([]byte{1, 2, 3})
        cases := []struct {
                name    string
                raw     string
                wantN   string
                wantKey []byte
                wantErr bool
        }{
                {"empty", "", "", nil, false},
                {"bare name", " cloudflare-ech.com ", "cloudflare-ech.com", nil, false},
                {"name and key", "cloudflare-ech.com:" + key, "cloudflare-ech.com", []byte{1, 2, 3}, false},
                {"empty key refused", "x:", "", nil, true},
                {"bad name refused", "bad name", "", nil, true},
                {"bad base64 refused", "x:!!!", "", nil, true},
        }
        for _, c := range cases {
                t.Run(c.name, func(t *testing.T) {
                        name, key, err := parseECHConfig(c.raw)
                        if c.wantErr {
                                if err == nil {
                                        t.Fatalf("%q must be refused", c.raw)
                                }
                                return
                        }
                        if err != nil {
                                t.Fatal(err)
                        }
                        if name != c.wantN || string(key) != string(c.wantKey) {
                                t.Fatalf("parse(%q) = (%q, %v)", c.raw, name, key)
                        }
                })
        }
}

// ---------------------------------------------------------------------------
// the DoH lookup
// ---------------------------------------------------------------------------

func withDoH(t *testing.T, servers ...string) {
        t.Helper()
        old := dohServers
        dohServers = servers
        t.Cleanup(func() { dohServers = old })
}

func TestLookupECHParsesHTTPSRecord(t *testing.T) {
        key := base64.StdEncoding.EncodeToString([]byte{9, 9, 9})
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/dns-json")
                io.WriteString(w, `{"Status":0,"Answer":[
                        {"name":"relay.example.","type":1,"TTL":60,"data":"1.2.3.4"},
                        {"name":"relay.example.","type":65,"TTL":300,"data":"1 cloudflare-ech.com ech=`+key+`"}
                ]}`)
        }))
        t.Cleanup(srv.Close)
        withDoH(t, srv.URL)

        got, ttl, err := lookupECH(context.Background(), "relay.example")
        if err != nil {
                t.Fatal(err)
        }
        if string(got) != string([]byte{9, 9, 9}) {
                t.Fatalf("key = %v", got)
        }
        if ttl != 300*time.Second {
                t.Fatalf("ttl = %s, want the record's 300s", ttl)
        }
}

func TestLookupECHClampsTTL(t *testing.T) {
        key := base64.StdEncoding.EncodeToString([]byte{1})
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/dns-json")
                io.WriteString(w, `{"Status":0,"Answer":[
                        {"name":"relay.example.","type":65,"TTL":86400,"data":"1 cloudflare-ech.com ech=`+key+`"}
                ]}`)
        }))
        t.Cleanup(srv.Close)
        withDoH(t, srv.URL)

        if _, ttl, err := lookupECH(context.Background(), "relay.example"); err != nil || ttl != echKeyMaxTTL {
                t.Fatalf("a huge TTL must clamp to the max, got %s err=%v", ttl, err)
        }
}

func TestLookupECHNoKeyIsNegativeAnswer(t *testing.T) {
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/dns-json")
                io.WriteString(w, `{"Status":0,"Answer":[{"name":"relay.example.","type":65,"TTL":300,"data":"1 cloudflare-ech.com"}]}`)
        }))
        t.Cleanup(srv.Close)
        withDoH(t, srv.URL)

        _, ttl, err := lookupECH(context.Background(), "relay.example")
        if err == nil || !strings.Contains(err.Error(), "no ECH key") {
                t.Fatalf("a record without ech= is the negative answer, got %v", err)
        }
        if ttl != echKeyMaxTTL {
                t.Fatalf("the negative answer must stand the full TTL, got %s", ttl)
        }
}

func TestLookupECHNXDOMAIN(t *testing.T) {
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                io.WriteString(w, `{"Status":3}`)
        }))
        t.Cleanup(srv.Close)
        withDoH(t, srv.URL)

        if _, _, err := lookupECH(context.Background(), "gone.example"); err == nil || !strings.Contains(err.Error(), "does not exist") {
                t.Fatalf("Status 3 must surface as non-existent, got %v", err)
        }
}

func TestLookupECHFallsToNextServer(t *testing.T) {
        dead := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
        deadURL := dead.URL
        dead.Close()

        key := base64.StdEncoding.EncodeToString([]byte{7})
        live := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/dns-json")
                io.WriteString(w, `{"Status":0,"Answer":[{"name":"relay.example.","type":65,"TTL":300,"data":"1 p.example ech=`+key+`"}]}`)
        }))
        t.Cleanup(live.Close)
        withDoH(t, deadURL, live.URL)

        got, _, err := lookupECH(context.Background(), "relay.example")
        if err != nil {
                t.Fatal(err)
        }
        if len(got) != 1 || got[0] != 7 {
                t.Fatalf("the next DoH server must answer, got %v", got)
        }
}

// ---------------------------------------------------------------------------
// the dialer's key sources
// ---------------------------------------------------------------------------

func TestECHDialerFixedKeyNeverDialsDNS(t *testing.T) {
        hits := int32(0)
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                atomic.AddInt32(&hits, 1)
        }))
        t.Cleanup(srv.Close)
        withDoH(t, srv.URL)

        key := []byte{4, 4, 4}
        d, err := newECHDialer("relay.example", Options{
                ECHMode:   ECHModeOn,
                ECHConfig: "pin.example:" + base64.StdEncoding.EncodeToString(key),
        }, dialRelay)
        if err != nil {
                t.Fatal(err)
        }
        for i := 0; i < 3; i++ {
                got, err := d.currentKey(context.Background())
                if err != nil || string(got) != string(key) {
                        t.Fatalf("currentKey = %v, %v", got, err)
                }
        }
        if atomic.LoadInt32(&hits) != 0 {
                t.Fatal("a fixed key must never trigger a DoH lookup")
        }
}

func TestECHDialerCachesDNSKey(t *testing.T) {
        key := base64.StdEncoding.EncodeToString([]byte{5})
        hits := int32(0)
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                atomic.AddInt32(&hits, 1)
                w.Header().Set("Content-Type", "application/dns-json")
                io.WriteString(w, `{"Status":0,"Answer":[{"name":"relay.example.","type":65,"TTL":3600,"data":"1 p.example ech=`+key+`"}]}`)
        }))
        t.Cleanup(srv.Close)
        withDoH(t, srv.URL)

        d, err := newECHDialer("relay.example", Options{ECHMode: ECHModeOn, ECHConfig: "relay.example"}, dialRelay)
        if err != nil {
                t.Fatal(err)
        }
        if got, err := d.currentKey(context.Background()); err != nil || len(got) != 1 || got[0] != 5 {
                t.Fatalf("first lookup = %v, %v", got, err)
        }
        if got, err := d.currentKey(context.Background()); err != nil || len(got) != 1 || got[0] != 5 {
                t.Fatalf("cached lookup = %v, %v", got, err)
        }
        if atomic.LoadInt32(&hits) != 1 {
                t.Fatalf("the key must be cached, DoH hits = %d", hits)
        }
}

// ---------------------------------------------------------------------------
// the dial walks (local TLS server)
// ---------------------------------------------------------------------------

// echoTLSServer is a plain local TLS server (no ECH on it).
func echoTLSServer(t *testing.T) *httptest.Server {
        t.Helper()
        s := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                io.WriteString(w, "hello")
        }))
        t.Cleanup(s.Close)
        return s
}

func TestECHDialerOnFallsBackToPlainTLS(t *testing.T) {
        srv := echoTLSServer(t)
        u, _ := url.Parse(srv.URL)

        // A garbage fixed key: the ECH handshake cannot succeed against a
        // plain server; "on" must fall back to the plain TLS connection.
        d, err := newECHDialer(u.Hostname(), Options{
                ECHMode:   ECHModeOn,
                ECHConfig: "pin.example:" + base64.StdEncoding.EncodeToString([]byte{0xDE, 0xAD, 0xBE, 0xEF}),
        }, dialRelay)
        if err != nil {
                t.Fatal(err)
        }
        ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        conn, err := d.DialTLSContext(ctx, "tcp", u.Host)
        if err != nil {
                t.Fatalf("on mode must reach the relay over plain TLS: %v", err)
        }
        defer conn.Close()
        tlsConn, ok := conn.(*tls.Conn)
        if !ok {
                t.Fatalf("the fallback connection must be TLS, got %T", conn)
        }
        if v := tlsConn.ConnectionState().Version; v < tls.VersionTLS12 {
                t.Fatalf("the fallback must speak at least TLS 1.2, got 0x%04x", v)
        }
}

func TestECHDialerRequireFailsClosed(t *testing.T) {
        srv := echoTLSServer(t)
        u, _ := url.Parse(srv.URL)

        d, err := newECHDialer(u.Hostname(), Options{
                ECHMode:   ECHModeRequire,
                ECHConfig: "pin.example:" + base64.StdEncoding.EncodeToString([]byte{0xDE, 0xAD}),
        }, dialRelay)
        if err != nil {
                t.Fatal(err)
        }
        ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        _, err = d.DialTLSContext(ctx, "tcp", u.Host)
        if err == nil || !strings.Contains(err.Error(), "require") {
                t.Fatalf("require mode must refuse the plain fallback, got %v", err)
        }
}
