package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"aethone/fxv/internal/dnsresolver"
)

const (
	webViewProxyConnectTimeout = 15 * time.Second
	webViewProxyHeaderTimeout  = 10 * time.Second
	webViewProxyMaxConnections = 32
)

// runWebViewProxy owns a short-lived loopback HTTP CONNECT proxy. The
// browser uses this role only while the Firefox login WebView is visible.
// Closing stdin is its shutdown signal, matching the other Go child roles.
func runWebViewProxy() int {
	stdin := bufio.NewReader(io.LimitReader(os.Stdin, maxDNSConfigLine+1))
	config, err := readOptionalDNSConfigBuffered(stdin)
	if err != nil {
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{
			"event": "webViewProxyFailed",
			"code":  "dnsConfigInvalid",
		})
		return 1
	}

	resolverName, err := dnsresolver.Install(config)
	if err != nil {
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{
			"event": "webViewProxyFailed",
			"code":  "dnsSetupFailed",
		})
		return 1
	}
	if config.Mode == dnsresolver.ModeSystem {
		resolverName = resolverDescription()
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{
			"event": "webViewProxyFailed",
			"code":  "listenFailed",
		})
		return 1
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	server := &webViewConnectProxy{
		active: make(map[net.Conn]struct{}),
	}
	ready := map[string]any{
		"event":    "webViewProxyReady",
		"addr":     listener.Addr().String(),
		"resolver": resolverName,
	}
	if err := json.NewEncoder(os.Stdout).Encode(ready); err != nil {
		_ = listener.Close()
		return 1
	}

	// Preserve the buffered reader used for the config line. It may
	// already contain bytes after the newline; the same reader must watch
	// the remaining pipe so closeStdin is never lost to read-ahead.
	go func() {
		_, _ = io.Copy(io.Discard, stdin)
		cancel()
		_ = listener.Close()
		server.closeActive()
	}()

	for {
		client, acceptErr := listener.Accept()
		if acceptErr != nil {
			if ctx.Err() != nil {
				break
			}
			fmt.Fprintln(os.Stderr, "webview-proxy: listener accept failed")
			cancel()
			break
		}

		if ctx.Err() != nil {
			_ = client.Close()
			continue
		}
		if !server.register(client) {
			_ = client.Close()
			continue
		}
		server.wg.Add(1)
		go func(conn net.Conn) {
			defer server.wg.Done()
			defer server.unregister(conn)
			handleWebViewProxyConnection(ctx, conn, dialWebViewHTTPS)
		}(client)
	}

	cancel()
	_ = listener.Close()
	server.closeActive()
	server.wg.Wait()
	return 0
}

type webViewConnectProxy struct {
	mu     sync.Mutex
	active map[net.Conn]struct{}
	wg     sync.WaitGroup
}

func (s *webViewConnectProxy) register(conn net.Conn) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.active) >= webViewProxyMaxConnections {
		return false
	}
	s.active[conn] = struct{}{}
	return true
}

func (s *webViewConnectProxy) unregister(conn net.Conn) {
	s.mu.Lock()
	delete(s.active, conn)
	s.mu.Unlock()
	_ = conn.Close()
}

func (s *webViewConnectProxy) closeActive() {
	s.mu.Lock()
	connections := make([]net.Conn, 0, len(s.active))
	for conn := range s.active {
		connections = append(connections, conn)
	}
	s.mu.Unlock()
	for _, conn := range connections {
		_ = conn.Close()
	}
}

type webViewConnectDialer func(context.Context, string, string) (net.Conn, error)

func handleWebViewProxyConnection(
	parent context.Context,
	client net.Conn,
	dial webViewConnectDialer,
) {
	_ = client.SetReadDeadline(time.Now().Add(webViewProxyHeaderTimeout))
	reader := bufio.NewReader(client)
	request, err := http.ReadRequest(reader)
	if err != nil {
		writeWebViewProxyResponse(client, http.StatusBadRequest, "Bad Request")
		return
	}
	if request.Body != nil {
		_ = request.Body.Close()
	}
	if request.Method != http.MethodConnect {
		writeWebViewProxyResponse(client, http.StatusMethodNotAllowed, "CONNECT Required")
		return
	}

	target := request.Host
	if target == "" {
		target = request.RequestURI
	}
	host, port, err := parseWebViewConnectTarget(target)
	if err != nil {
		writeWebViewProxyResponse(client, http.StatusBadRequest, "Invalid CONNECT Target")
		return
	}
	// The sign-in surface is HTTPS. Keeping the listener limited to 443
	// prevents it from becoming a general-purpose local port forwarder.
	if port != "443" {
		writeWebViewProxyResponse(client, http.StatusForbidden, "HTTPS Only")
		return
	}

	ctx, cancel := context.WithTimeout(parent, webViewProxyConnectTimeout)
	defer cancel()
	upstream, err := dial(ctx, host, port)
	if err != nil {
		writeWebViewProxyResponse(client, http.StatusBadGateway, "Upstream Unavailable")
		return
	}
	defer upstream.Close()

	_ = client.SetDeadline(time.Time{})
	if _, err := io.WriteString(
		client,
		"HTTP/1.1 200 Connection Established\r\nProxy-Agent: AETHONE-Firefox-DNS/1\r\n\r\n",
	); err != nil {
		return
	}

	relayWebViewTunnel(parent, client, reader, upstream)
}

func parseWebViewConnectTarget(raw string) (string, string, error) {
	raw = strings.TrimSpace(raw)
	host, port, err := net.SplitHostPort(raw)
	if err != nil || host == "" {
		return "", "", fmt.Errorf("invalid CONNECT authority")
	}
	if strings.ContainsAny(host, "/?#@%") {
		return "", "", fmt.Errorf("invalid CONNECT hostname")
	}
	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber < 1 || portNumber > 65535 {
		return "", "", fmt.Errorf("invalid CONNECT port")
	}
	return strings.TrimSuffix(strings.ToLower(host), "."), strconv.Itoa(portNumber), nil
}

// dialWebViewHTTPS resolves the CONNECT hostname through net.DefaultResolver.
// dnsresolver.Install has already installed the selected process-local policy.
// Resolved private, loopback and link-local destinations are rejected so this
// temporary loopback listener cannot be used to reach device-local services.
func dialWebViewHTTPS(ctx context.Context, host, port string) (net.Conn, error) {
	ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, err
	}
	dialer := &net.Dialer{
		Timeout:   webViewProxyConnectTimeout,
		KeepAlive: 30 * time.Second,
	}
	var lastErr error
	for _, item := range ips {
		if isUnsafeWebViewProxyIP(item.IP) {
			continue
		}
		conn, dialErr := dialer.DialContext(
			ctx,
			"tcp",
			net.JoinHostPort(item.IP.String(), port),
		)
		if dialErr == nil {
			return conn, nil
		}
		lastErr = dialErr
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("hostname resolved only to blocked addresses")
}

func isUnsafeWebViewProxyIP(ip net.IP) bool {
	return ip == nil ||
		ip.IsUnspecified() ||
		ip.IsLoopback() ||
		ip.IsPrivate() ||
		ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() ||
		ip.IsMulticast()
}

func writeWebViewProxyResponse(conn net.Conn, status int, reason string) {
	_, _ = fmt.Fprintf(
		conn,
		"HTTP/1.1 %d %s\r\nConnection: close\r\nContent-Length: 0\r\n\r\n",
		status,
		reason,
	)
}

func relayWebViewTunnel(
	ctx context.Context,
	client net.Conn,
	clientReader io.Reader,
	upstream net.Conn,
) {
	var copies sync.WaitGroup
	copies.Add(2)

	go func() {
		defer copies.Done()
		_, _ = io.Copy(upstream, clientReader)
		if half, ok := upstream.(interface{ CloseWrite() error }); ok {
			_ = half.CloseWrite()
		}
	}()
	go func() {
		defer copies.Done()
		_, _ = io.Copy(client, upstream)
		if half, ok := client.(interface{ CloseWrite() error }); ok {
			_ = half.CloseWrite()
		}
	}()

	done := make(chan struct{})
	go func() {
		copies.Wait()
		close(done)
	}()
	select {
	case <-ctx.Done():
		_ = client.Close()
		_ = upstream.Close()
		<-done
	case <-done:
		_ = client.Close()
		_ = upstream.Close()
	}
}
