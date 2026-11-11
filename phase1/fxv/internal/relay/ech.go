package relay

// ECH (Encrypted Client Hello) for relay connections — AETHONE
// original implementation (2026-11-11; see the package comment for the
// provenance posture).
//
// ECH hides the RELAY'S NAME from the local network: the ClientHello's
// outer SNI carries the ECH key's public name (for a Cloudflare relay,
// cloudflare-ech.com), the real name rides encrypted inside. The
// certificate is still checked against the relay's own name. This
// matters where the relay host itself (a workers.dev name, say) is
// filtered by SNI while Cloudflare's edge stays reachable.
//
// Modes (apiRelayECH):
//
//	off     — plain TLS to the relay, no ECH.
//	on      — ECH first; a relay that cannot be reached with ECH is
//	          reached without it (best effort, the default).
//	require — no ECH, no connection (fail closed).
//
// The ECH key (an ECHConfigList) comes from the HTTPS DNS record of
// the relay's name (DoH, JSON form) or from a fixed base64 value in
// apiRelayECHConfig ("name" reads another name's record; "name:key"
// pins the key itself). Keys from DNS are cached between one minute
// and one hour (Cloudflare rotates its keys every few hours); a server
// that rejects a stale key sends the current one back authenticated by
// the public name's certificate — that retry is automatic.

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// The ECH modes (apiRelayECH values).
const (
	ECHModeOff     = "off"
	ECHModeOn      = "on"
	ECHModeRequire = "require"
)

// ECH key cache bounds (Cloudflare publishes five-minute TTLs).
const (
	echKeyMinTTL = time.Minute
	echKeyMaxTTL = time.Hour
	// echKeyRetry is how long a failed lookup stands before the next
	// one, so "on"-mode requests do not each wait for DNS; a negative
	// answer (the name has no key — a relay not on Cloudflare) stands
	// the full max TTL.
	echKeyRetry  = time.Minute
	echDoHWait   = 3 * time.Second
	echDoHMaxMsg = 64 * 1024
)

// dohServers carry the HTTPS-record lookups (IP endpoints; bootstrap
// traffic with its own plain transport, never the relay stack or the
// control-plane client).
var dohServers = []string{
	"https://1.1.1.1/dns-query",
	"https://8.8.8.8/dns-query",
	"https://9.9.9.9/dns-query",
}

// dohClient is the bootstrap DoH client (bounded, proxy-free).
var dohClient = &http.Client{
	Timeout: echDoHWait,
	Transport: &http.Transport{
		Proxy:               nil,
		TLSHandshakeTimeout: echDoHWait,
	},
}

// validateECHMode checks an apiRelayECH value ("" is allowed; the
// normalizer defaults it to on).
func validateECHMode(mode string) error {
	switch mode {
	case "", ECHModeOff, ECHModeOn, ECHModeRequire:
		return nil
	}
	return fmt.Errorf("relay ECH mode %q is not off, on, or require", mode)
}

// parseECHConfig reads an apiRelayECHConfig value: "" (DNS for the
// relay's own name), "name" (DNS for another name), or "name:base64"
// (a fixed key).
func parseECHConfig(raw string) (name string, key []byte, err error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", nil, nil
	}
	name, encoded, hasColon := strings.Cut(raw, ":")
	name = strings.TrimSpace(name)
	if name == "" || strings.ContainsAny(name, "/\\ ") {
		return "", nil, fmt.Errorf("relay ECH config name is not a host name")
	}
	if !hasColon {
		return name, nil, nil
	}
	encoded = strings.TrimSpace(encoded)
	if encoded == "" {
		return "", nil, fmt.Errorf("relay ECH config key is empty")
	}
	key, err = base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(key) == 0 {
		return "", nil, fmt.Errorf("relay ECH config key is not valid base64")
	}
	return name, key, nil
}

// lookupECH fetches the ECHConfigList from the HTTPS record of name
// (the DoH JSON form: the record data is the presentation string
// "priority target ech=BASE64 ..."). Servers are tried in order until
// one answers; the TTL is clamped to the cache bounds.
func lookupECH(ctx context.Context, name string) ([]byte, time.Duration, error) {
	var lastErr error
	for _, server := range dohServers {
		if ctx.Err() != nil {
			return nil, 0, ctx.Err()
		}
		u, err := url.Parse(server)
		if err != nil {
			continue
		}
		q := u.Query()
		q.Set("name", name)
		q.Set("type", "HTTPS")
		u.RawQuery = q.Encode()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
		if err != nil {
			continue
		}
		req.Header.Set("Accept", "application/dns-json")
		resp, err := dohClient.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		body, readErr := io.ReadAll(io.LimitReader(resp.Body, echDoHMaxMsg+1))
		resp.Body.Close()
		if readErr != nil || resp.StatusCode != http.StatusOK || len(body) > echDoHMaxMsg {
			lastErr = fmt.Errorf("DoH %s answered HTTP %d", u.Host, resp.StatusCode)
			continue
		}
		var msg struct {
			Status  int    `json:"Status"`
			Answer []struct {
				Name string `json:"name"`
				Type int    `json:"type"`
				TTL  int    `json:"TTL"`
				Data string `json:"data"`
			} `json:"Answer"`
		}
		if json.Unmarshal(body, &msg) != nil {
			lastErr = errors.New("DoH answer is not JSON")
			continue
		}
		if msg.Status == 3 {
			return nil, 0, fmt.Errorf("DoH says the name does not exist")
		}
		for _, rr := range msg.Answer {
			if rr.Type != 65 { // HTTPS
				continue
			}
			for _, field := range strings.Fields(rr.Data) {
				if !strings.HasPrefix(field, "ech=") {
					continue
				}
				key, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(field, "ech="))
				if err != nil || len(key) == 0 {
					continue
				}
				ttl := time.Duration(rr.TTL) * time.Second
				if ttl < echKeyMinTTL {
					ttl = echKeyMinTTL
				}
				if ttl > echKeyMaxTTL {
					ttl = echKeyMaxTTL
				}
				return key, ttl, nil
			}
		}
		// A well-formed answer without an ech parameter: the name has
		// no key (a relay that is not on Cloudflare).
		return nil, echKeyMaxTTL, errors.New("the name has no ECH key")
	}
	if lastErr == nil {
		lastErr = errors.New("no DoH server answered")
	}
	return nil, 0, lastErr
}

// echDialer opens the TLS connections to one relay with ECH.
type echDialer struct {
	host    string // the relay's name, sent inside the encrypted hello
	require bool
	keyName string // whose HTTPS record carries the key
	fixed   []byte // a key from the settings instead of DNS

	dial func(ctx context.Context, network, address string) (net.Conn, error)

	mu        sync.Mutex
	key       []byte
	expires   time.Time
	lookupErr error
}

func newECHDialer(host string, opts Options, dial func(context.Context, string, string) (net.Conn, error)) (*echDialer, error) {
	name, key, err := parseECHConfig(opts.ECHConfig)
	if err != nil {
		return nil, err
	}
	if name == "" {
		name = host
	}
	return &echDialer{
		host:    host,
		require: opts.ECHMode == ECHModeRequire,
		keyName: name,
		fixed:   key,
		dial:    dial,
	}, nil
}

// currentKey returns the cached, fixed or freshly looked-up key.
func (e *echDialer) currentKey(ctx context.Context) ([]byte, error) {
	if e.fixed != nil {
		return e.fixed, nil
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.key != nil && time.Now().Before(e.expires) {
		return e.key, nil
	}
	if e.lookupErr != nil && time.Now().Before(e.expires) {
		return nil, e.lookupErr
	}
	key, ttl, err := lookupECH(ctx, e.keyName)
	if err != nil {
		// A negative "no key" answer stands the full TTL; a transport
		// failure is retried sooner.
		if ttl == 0 {
			ttl = echKeyRetry
		}
		e.lookupErr, e.expires = err, time.Now().Add(ttl)
		return nil, err
	}
	e.key, e.lookupErr, e.expires = key, nil, time.Now().Add(ttl)
	return key, nil
}

// setKey stores a fresh key (the retry list a rejecting server sent).
func (e *echDialer) setKey(key []byte) {
	if e.fixed != nil {
		return
	}
	e.mu.Lock()
	e.key, e.lookupErr, e.expires = key, nil, time.Now().Add(echKeyMaxTTL)
	e.mu.Unlock()
}

// DialTLSContext is the relay leg's TLS dial.
func (e *echDialer) DialTLSContext(ctx context.Context, network, address string) (net.Conn, error) {
	key, err := e.currentKey(ctx)
	if err != nil {
		return e.withoutECH(ctx, network, address, err)
	}
	conn, err := e.handshake(ctx, network, address, key)
	var rejected *tls.ECHRejectionError
	if errors.As(err, &rejected) && len(rejected.RetryConfigList) > 0 {
		// A stale key: the rejecting server sent the current one,
		// authenticated by the public name's certificate.
		e.setKey(rejected.RetryConfigList)
		conn, err = e.handshake(ctx, network, address, rejected.RetryConfigList)
	}
	if err == nil {
		return conn, nil
	}
	if errors.As(err, &rejected) {
		err = errors.New("the relay does not take ECH")
	}
	if ctx.Err() != nil {
		return nil, err
	}
	return e.withoutECH(ctx, network, address, fmt.Errorf("ECH handshake: %w", err))
}

// handshake dials and completes TLS with the ECH key (TLS 1.3).
func (e *echDialer) handshake(ctx context.Context, network, address string, key []byte) (*tls.Conn, error) {
	raw, err := e.dial(ctx, network, address)
	if err != nil {
		return nil, err
	}
	cfg := &tls.Config{
		ServerName:                     e.host,
		MinVersion:                     tls.VersionTLS13,
		EncryptedClientHelloConfigList: key,
	}
	conn := tls.Client(raw, cfg)
	if err := conn.HandshakeContext(ctx); err != nil {
		_ = raw.Close()
		return nil, err
	}
	return conn, nil
}

// withoutECH connects plainly in "on" mode and refuses in "require".
func (e *echDialer) withoutECH(ctx context.Context, network, address string, why error) (net.Conn, error) {
	if e.require {
		return nil, fmt.Errorf("no ECH (mode is require): %w", why)
	}
	raw, err := e.dial(ctx, network, address)
	if err != nil {
		return nil, err
	}
	conn := tls.Client(raw, &tls.Config{ServerName: e.host, MinVersion: tls.VersionTLS12})
	if err := conn.HandshakeContext(ctx); err != nil {
		_ = raw.Close()
		return nil, err
	}
	return conn, nil
}
