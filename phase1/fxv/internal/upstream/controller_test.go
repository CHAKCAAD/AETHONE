package upstream

// The 1.7.0 h3→h2 fallback tests (the owner's round 5): a FAILED h3
// session build retries ONCE as h2 through the same dial path, the
// live transport label mirrors the fallback, an h2 pick never touches
// h3, and a double failure reports the h3 chain (the user's pick).
// The builders are swapped through the controller's same-package seam —
// no live Fastly edge, no TLS.

import (
        "errors"
        "fmt"
        "net/url"
        "strings"
        "testing"
        "time"

        vpnclient "firefox-vpn-client"
)

var errUDPAssociateRefused = errors.New("SOCKS5 request failed (reply 2): the carrier refused the UDP ASSOCIATE")

func newFallbackTestController(t *testing.T, transport string) *Controller {
        t.Helper()
        cfg := ControllerConfig{
                Transport:   transport,
                ProxyURL:    &url.URL{Scheme: "https", Host: "edge.example.com:443"},
                OpenTimeout: time.Second,
                Logf:        func(string, ...any) {},
        }
        return NewController(cfg)
}

func TestH3FailureFallsBackToH2(t *testing.T) {
        c := newFallbackTestController(t, "h3")
        h3Attempts, h2Attempts := 0, 0
        c.h3Builder = func(*vpnclient.ProxyPassInfo) (*H3ProxySession, error) {
                h3Attempts++
                return nil, errUDPAssociateRefused
        }
        c.h2Builder = func(*vpnclient.ProxyPassInfo) (*H2ProxySession, error) {
                h2Attempts++
                return &H2ProxySession{proxyHost: "edge.example.com:443"}, nil
        }
        session, transport, err := c.buildSession(&vpnclient.ProxyPassInfo{RawToken: "tok"})
        if err != nil {
                t.Fatalf("the h2 fallback must rescue the refused UDP ASSOCIATE: %v", err)
        }
        if transport != "h2" {
                t.Fatalf("the live transport must be labeled h2 after the fallback, got %q", transport)
        }
        if session == nil {
                t.Fatal("the fallback session must be the h2 session")
        }
        if h3Attempts != 1 || h2Attempts != 1 {
                t.Fatalf("exactly one h3 attempt and one h2 fallback expected, got h3=%d h2=%d", h3Attempts, h2Attempts)
        }
}

func TestH3FallbackIsLoggedHonestly(t *testing.T) {
        var logs []string
        c := newFallbackTestController(t, "h3")
        c.cfg.Logf = func(format string, args ...any) {
                logs = append(logs, fmt.Sprintf(format, args...))
        }
        c.h3Builder = func(*vpnclient.ProxyPassInfo) (*H3ProxySession, error) {
                return nil, errUDPAssociateRefused
        }
        c.h2Builder = func(*vpnclient.ProxyPassInfo) (*H2ProxySession, error) {
                return &H2ProxySession{}, nil
        }
        if _, _, err := c.buildSession(&vpnclient.ProxyPassInfo{RawToken: "tok"}); err != nil {
                t.Fatal(err)
        }
        found := false
        for _, line := range logs {
                if strings.Contains(line, "falling back to h2") && strings.Contains(line, "h3 session failed") {
                        found = true
                }
        }
        if !found {
                t.Fatalf("the fallback must be logged honestly, saw %v", logs)
        }
}

func TestH3SuccessNeverTouchesH2(t *testing.T) {
        c := newFallbackTestController(t, "h3")
        h2Touched := false
        c.h3Builder = func(*vpnclient.ProxyPassInfo) (*H3ProxySession, error) {
                return &H3ProxySession{proxyHost: "edge.example.com:443"}, nil
        }
        c.h2Builder = func(*vpnclient.ProxyPassInfo) (*H2ProxySession, error) {
                h2Touched = true
                return &H2ProxySession{}, nil
        }
        _, transport, err := c.buildSession(&vpnclient.ProxyPassInfo{RawToken: "tok"})
        if err != nil || transport != "h3" {
                t.Fatalf("a healthy h3 must stay h3: transport=%q err=%v", transport, err)
        }
        if h2Touched {
                t.Fatal("a healthy h3 must never dial h2")
        }
}

func TestDoubleFailureReportsTheH3Chain(t *testing.T) {
        c := newFallbackTestController(t, "h3")
        errH2 := errors.New("h2: connection refused")
        c.h3Builder = func(*vpnclient.ProxyPassInfo) (*H3ProxySession, error) {
                return nil, errUDPAssociateRefused
        }
        c.h2Builder = func(*vpnclient.ProxyPassInfo) (*H2ProxySession, error) {
                return nil, errH2
        }
        _, _, err := c.buildSession(&vpnclient.ProxyPassInfo{RawToken: "tok"})
        if err == nil {
                t.Fatal("a double failure must fail")
        }
        if !errors.Is(err, errUDPAssociateRefused) {
                t.Fatalf("the reported chain must be the h3 one (the user's pick), got: %v", err)
        }
}

func TestH2PickNeverDialsH3(t *testing.T) {
        c := newFallbackTestController(t, "h2")
        h3Touched := false
        c.h3Builder = func(*vpnclient.ProxyPassInfo) (*H3ProxySession, error) {
                h3Touched = true
                return nil, errors.New("must not be called")
        }
        c.h2Builder = func(*vpnclient.ProxyPassInfo) (*H2ProxySession, error) {
                return &H2ProxySession{}, nil
        }
        _, transport, err := c.buildSession(&vpnclient.ProxyPassInfo{RawToken: "tok"})
        if err != nil || transport != "h2" {
                t.Fatalf("h2 pick: transport=%q err=%v", transport, err)
        }
        if h3Touched {
                t.Fatal("an h2 pick must never dial h3")
        }
}
