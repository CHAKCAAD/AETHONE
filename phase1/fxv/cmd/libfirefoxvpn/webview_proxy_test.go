package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"testing"
	"time"
)

func TestParseWebViewConnectTarget(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		wantHost string
		wantPort string
		wantErr bool
	}{
		{name: "domain", raw: "accounts.firefox.com:443", wantHost: "accounts.firefox.com", wantPort: "443"},
		{name: "uppercase and trailing dot", raw: "ACCOUNTS.FIREFOX.COM.:443", wantHost: "accounts.firefox.com", wantPort: "443"},
		{name: "IPv6", raw: "[2001:db8::1]:443", wantHost: "2001:db8::1", wantPort: "443"},
		{name: "missing port", raw: "accounts.firefox.com", wantErr: true},
		{name: "invalid port", raw: "accounts.firefox.com:99999", wantErr: true},
		{name: "path injection", raw: "accounts.firefox.com:443/path", wantErr: true},
		{name: "userinfo", raw: "user@accounts.firefox.com:443", wantErr: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			host, port, err := parseWebViewConnectTarget(tc.raw)
			if (err != nil) != tc.wantErr {
				t.Fatalf("error = %v, wantErr %v", err, tc.wantErr)
			}
			if err == nil && (host != tc.wantHost || port != tc.wantPort) {
				t.Fatalf("target = %q:%q, want %q:%q", host, port, tc.wantHost, tc.wantPort)
			}
		})
	}
}

func TestWebViewCONNECTRelaysBytesWithoutTerminatingTLS(t *testing.T) {
	clientProxy, browser := net.Pipe()
	upstreamProxy, upstreamServer := net.Pipe()
	defer browser.Close()
	defer upstreamServer.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	dialCalled := make(chan string, 1)
	go handleWebViewProxyConnection(ctx, clientProxy, func(_ context.Context, host, port string) (net.Conn, error) {
		dialCalled <- net.JoinHostPort(host, port)
		return upstreamProxy, nil
	})

	if _, err := io.WriteString(browser, "CONNECT accounts.firefox.com:443 HTTP/1.1\r\nHost: accounts.firefox.com:443\r\n\r\n"); err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(browser)
	request := &http.Request{Method: http.MethodConnect}
	response, err := http.ReadResponse(reader, request)
	if err != nil {
		t.Fatalf("read CONNECT response: %v", err)
	}
	if response.StatusCode != http.StatusOK {
		t.Fatalf("CONNECT status = %d", response.StatusCode)
	}
	select {
	case target := <-dialCalled:
		if target != "accounts.firefox.com:443" {
			t.Fatalf("dial target = %q", target)
		}
	case <-time.After(time.Second):
		t.Fatal("CONNECT dialer was not called")
	}

	// The proxy sees only the CONNECT authority and then opaque bytes.
	// TLS records pass through unchanged in both directions.
	const outbound = "client-tls-record"
	if _, err := io.WriteString(browser, outbound); err != nil {
		t.Fatal(err)
	}
	_ = upstreamServer.SetReadDeadline(time.Now().Add(time.Second))
	received := make([]byte, len(outbound))
	if _, err := io.ReadFull(upstreamServer, received); err != nil {
		t.Fatalf("upstream read: %v", err)
	}
	if string(received) != outbound {
		t.Fatalf("upstream got %q", received)
	}

	const inbound = "server-tls-record"
	if _, err := io.WriteString(upstreamServer, inbound); err != nil {
		t.Fatal(err)
	}
	_ = browser.SetReadDeadline(time.Now().Add(time.Second))
	returned := make([]byte, len(inbound))
	if _, err := io.ReadFull(reader, returned); err != nil {
		t.Fatalf("browser read: %v", err)
	}
	if string(returned) != inbound {
		t.Fatalf("browser got %q", returned)
	}

	cancel()
	_ = browser.Close()
}

func TestWebViewProxyRejectsNonHttpsPorts(t *testing.T) {
	clientProxy, browser := net.Pipe()
	defer browser.Close()
	dialCalled := false
	go handleWebViewProxyConnection(context.Background(), clientProxy, func(context.Context, string, string) (net.Conn, error) {
		dialCalled = true
		return nil, fmt.Errorf("must not dial")
	})

	if _, err := io.WriteString(browser, "CONNECT accounts.firefox.com:8443 HTTP/1.1\r\nHost: accounts.firefox.com:8443\r\n\r\n"); err != nil {
		t.Fatal(err)
	}
	response, err := http.ReadResponse(bufio.NewReader(browser), &http.Request{Method: http.MethodConnect})
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", response.StatusCode)
	}
	if dialCalled {
		t.Fatal("non-443 CONNECT reached the dialer")
	}
}

func TestWebViewProxyRoleStartsAndStopsOnStdinEOF(t *testing.T) {
	s := startEngine(t, "--webview-proxy")
	defer s.kill()
	s.send(`{"dns":{"mode":"system"}}`)
	ev := s.waitEvent(t, "webViewProxyReady", 5*time.Second)
	addr, _ := ev["addr"].(string)
	host, port, err := net.SplitHostPort(addr)
	if err != nil || host != "127.0.0.1" || port == "" {
		t.Fatalf("proxy address = %q, err = %v", addr, err)
	}
	conn, err := net.DialTimeout("tcp", addr, time.Second)
	if err != nil {
		t.Fatalf("loopback listener is not reachable: %v", err)
	}
	_ = conn.Close()
	s.closeStdin()
	if code := s.waitExit(t, 5*time.Second); code != 0 {
		t.Fatalf("proxy process exit = %d, want 0", code)
	}
}

func TestWebViewProxyRejectsPrivateDestinations(t *testing.T) {
	if !isUnsafeWebViewProxyIP(net.ParseIP("10.0.0.1")) {
		t.Fatal("RFC1918 address should be blocked")
	}
	if !isUnsafeWebViewProxyIP(net.ParseIP("127.0.0.1")) {
		t.Fatal("loopback address should be blocked")
	}
	if isUnsafeWebViewProxyIP(net.ParseIP("1.1.1.1")) {
		t.Fatal("public address should remain eligible")
	}
}


func TestWebViewProxyRoleInstallsSelectedDoHResolver(t *testing.T) {
	s := startEngine(t, "--webview-proxy")
	defer s.kill()
	s.send(`{"dns":{"mode":"doh","provider":"google"}}`)
	ev := s.waitEvent(t, "webViewProxyReady", 5*time.Second)
	if got := ev["resolver"]; got != "DoH (google)" {
		t.Fatalf("resolver = %v, want DoH (google)", got)
	}
	s.closeStdin()
	if code := s.waitExit(t, 5*time.Second); code != 0 {
		t.Fatalf("proxy process exit = %d, want 0", code)
	}
}
