package dnsresolver

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	defaultRequestTimeout = 8 * time.Second
	maxDNSMessageBytes    = 65535
)

// Install applies a process-local resolver. Call it before starting any
// Firefox network operation. System mode deliberately leaves the original
// Bionic/host resolver untouched.
func Install(raw Config) (string, error) {
	cfg, err := raw.Validate()
	if err != nil {
		return "", err
	}
	if cfg.Mode == ModeSystem {
		return "android/system resolver (Bionic getaddrinfo)", nil
	}

	systemResolver := net.DefaultResolver
	client, err := newDoHHTTPClient(cfg, systemResolver)
	if err != nil {
		return "", err
	}
	exchange := &dohExchange{
		cfg:            cfg,
		client:         client,
		systemResolver: systemResolver,
		cache:          newDNSCache(256),
	}
	net.DefaultResolver = &net.Resolver{
		PreferGo:     true,
		StrictErrors: false,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			if strings.HasPrefix(network, "udp") {
				return newDoHPacketConn(ctx, exchange), nil
			}
			return newDoHStreamConn(ctx, exchange), nil
		},
	}
	return fmt.Sprintf("DoH (%s)", cfg.Provider), nil
}

func newDoHHTTPClient(cfg Config, systemResolver *net.Resolver) (*http.Client, error) {
	endpoint, err := url.Parse(cfg.Endpoint)
	if err != nil {
		return nil, err
	}
	bootstrap := make([]net.IP, 0, len(cfg.BootstrapIPs))
	for _, raw := range cfg.BootstrapIPs {
		bootstrap = append(bootstrap, net.ParseIP(raw))
	}
	dialer := &net.Dialer{Timeout: defaultRequestTimeout, KeepAlive: 30 * time.Second}
	transport := &http.Transport{
		Proxy: nil, // environment/system proxies must not silently change DNS routing
		TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12},
		ForceAttemptHTTP2: true,
		MaxIdleConns: 4,
		MaxIdleConnsPerHost: 2,
		IdleConnTimeout: 30 * time.Second,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, port, splitErr := net.SplitHostPort(address)
			if splitErr != nil {
				return nil, splitErr
			}
			if !strings.EqualFold(host, endpoint.Hostname()) {
				return dialer.DialContext(ctx, network, address)
			}
			ips := bootstrap
			if len(ips) == 0 {
				resolved, resolveErr := systemResolver.LookupIPAddr(ctx, host)
				if resolveErr != nil {
					return nil, fmt.Errorf("resolve DoH endpoint using Android system DNS: %w", resolveErr)
				}
				ips = make([]net.IP, 0, len(resolved))
				for _, item := range resolved {
					ips = append(ips, item.IP)
				}
			}
			if len(ips) == 0 {
				return nil, fmt.Errorf("DoH endpoint has no bootstrap addresses")
			}
			var lastErr error
			for _, ip := range ips {
				conn, dialErr := dialer.DialContext(ctx, "tcp", net.JoinHostPort(ip.String(), port))
				if dialErr == nil {
					// net/http still validates TLS against the hostname in
					// the request URL; only the TCP destination is pinned.
					return conn, nil
				}
				lastErr = dialErr
			}
			if lastErr == nil {
				lastErr = fmt.Errorf("no usable DoH bootstrap address")
			}
			return nil, lastErr
		},
	}
	return &http.Client{
		Transport: transport,
		Timeout: defaultRequestTimeout,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}, nil
}

type dohExchange struct {
	cfg            Config
	client         *http.Client
	systemResolver *net.Resolver
	cache          *dnsCache
}

func (d *dohExchange) exchange(ctx context.Context, query []byte) ([]byte, error) {
	if len(query) < 12 || len(query) > maxDNSMessageBytes {
		return nil, fmt.Errorf("invalid DNS query message length")
	}
	if cached, ok := d.cache.get(query); ok {
		return cached, nil
	}
	question, _, err := parseDNSQuestion(query)
	if err != nil {
		return nil, err
	}
	if d.cfg.UsesSystemDNS(question.name) {
		return buildSystemResponse(ctx, query, question, d.systemResolver)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, d.cfg.Endpoint, bytes.NewReader(query))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/dns-message")
	req.Header.Set("Accept", "application/dns-message")
	req.Header.Set("User-Agent", "AETHONE-Firefox-DNS/1")
	resp, err := d.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("DoH server returned HTTP %d", resp.StatusCode)
	}
	response, err := io.ReadAll(io.LimitReader(resp.Body, maxDNSMessageBytes+1))
	if err != nil {
		return nil, err
	}
	if len(response) < 12 || len(response) > maxDNSMessageBytes {
		return nil, fmt.Errorf("DoH server returned a malformed or oversized DNS message")
	}
	response[0], response[1] = query[0], query[1]
	d.cache.put(query, response)
	return response, nil
}
