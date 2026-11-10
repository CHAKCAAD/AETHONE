// --guardian-probe role tests (guardian-bootstrap Stage 5). What is
// real here:
//   - the probe runs the PRODUCTION walk (upstream.Controller's
//     AcquireInitialPass) against a local Guardian double through the
//     pinned vpnclient's shared control-plane client;
//   - the 451 case proves the probe surfaces Stage 1's dedicated
//     guardianRegionUnavailable class (the Dart direct-attempt seam's
//     only bootstrap trigger);
//   - the apiProxy case proves the probe installs the Stage-5 routing
//     and that the Guardian request REALLY traverses a local proxy
//     with verified TLS (a test CA trusted via SSL_CERT_FILE — this
//     test binary performs no earlier verified TLS, so the process
//     root pool loads it);
//   - stdout events and exit codes are captured through a real pipe —
//     the same wire the Dart host reads.
package main

import (
	"bufio"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	vpnclient "firefox-vpn-client"

	"aethone/fxv/internal/engine"
)

// captureProbe runs the probe role with the given config line, capturing
// the stdout JSON events and the exit code through a real pipe. The
// config travels on a HELD-OPEN pipe (the production spawn's "one line
// then silence" contract — the stdin-close watcher must not see an EOF
// the way a test-run /dev/null stdin would), so no global swap beyond
// os.Stdout is needed and no data race on os.Stdin is possible.
func captureProbe(t *testing.T, configLine string) (events []map[string]any, code int) {
	t.Helper()
	oldStdout := os.Stdout
	outReader, outWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	inReader, inWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	if _, err := io.WriteString(inWriter, configLine+"\n"); err != nil {
		t.Fatalf("write config: %v", err)
	}
	os.Stdout = outWriter
	defer func() {
		os.Stdout = oldStdout
		inWriter.Close() // unblocks the watcher's reader goroutine
	}()
	code = runGuardianProbeReader(inReader)
	outWriter.Close()
	scanner := bufio.NewScanner(outReader)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "{") {
			continue
		}
		var ev map[string]any
		if json.Unmarshal([]byte(line), &ev) == nil {
			events = append(events, ev)
		}
	}
	return events, code
}

func probeConfigLine(guardian, apiProxy string) string {
	apiField := ""
	if apiProxy != "" {
		apiField = `,"apiProxy":"` + apiProxy + `"`
	}
	return `{"version":1,"socksListen":"127.0.0.1:1822","guardian":"` + guardian + `"` + apiField + `,"logLevel":"quiet","auth":{"accessToken":"probe-access-token","refreshToken":""}}`
}

func eventNamed(events []map[string]any, name string) map[string]any {
	for _, ev := range events {
		if ev["event"] == name {
			return ev
		}
	}
	return nil
}

// shapeOnlyJWT builds a 3-part JWT whose payload carries exp in the
// future (the pin's parseJWTClaims only decodes the claims — no
// signature verification, that is Guardian's job, not the client's).
func shapeOnlyJWT(t *testing.T) string {
	t.Helper()
	payload, err := json.Marshal(map[string]any{
		"exp": time.Now().Add(time.Hour).Unix(),
		"iat": time.Now().Add(-time.Minute).Unix(),
	})
	if err != nil {
		t.Fatalf("payload: %v", err)
	}
	return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
		base64.RawURLEncoding.EncodeToString(payload) +
		".shape-only-signature"
}

// installTestControlPlane points the shared control-plane client at a
// TEST-ONLY transport (the main_test.go precedent: plain net/http
// trusting the local double's self-signed certificate; restored to the
// pinned uTLS transport afterwards — the production path is untouched).
func installTestControlPlane(t *testing.T) {
	t.Helper()
	vpnclient.SetControlPlaneTransport(&http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	})
	t.Cleanup(func() {
		vpnclient.SetControlPlaneTransport(vpnclient.NewControlPlaneTransport())
	})
}

func TestGuardianProbeClassifiesReal451(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/fpn/token" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusUnavailableForLegalReasons)
		_, _ = io.WriteString(w, `{"error":"unavailable_in_region"}`)
	}))
	defer srv.Close()
	installTestControlPlane(t)

	events, code := captureProbe(t, probeConfigLine(srv.URL, ""))

	if code != engine.ExitStartup {
		t.Fatalf("exit = %d (want ExitStartup)", code)
	}
	failed := eventNamed(events, "failed")
	if failed == nil {
		t.Fatalf("no failed event (events: %v)", events)
	}
	if failed["failCode"] != "guardianRegionUnavailable" {
		t.Fatalf("failCode = %v (want guardianRegionUnavailable)", failed["failCode"])
	}
	if status, _ := failed["httpStatus"].(float64); status != 451 {
		t.Fatalf("httpStatus = %v (want 451)", failed["httpStatus"])
	}
	started := eventNamed(events, "started")
	if started == nil {
		t.Fatal("no started event — the probe must announce itself like every role")
	}
}

func TestGuardianProbeSucceedsDirect(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/fpn/token" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		if r.Header.Get("Authorization") != "Bearer probe-access-token" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		w.Header().Set("X-Quota-Remaining", "499")
		w.Header().Set("X-Quota-Limit", "500")
		_ = json.NewEncoder(w).Encode(map[string]string{"token": shapeOnlyJWT(t)})
	}))
	defer srv.Close()
	installTestControlPlane(t)

	events, code := captureProbe(t, probeConfigLine(srv.URL, ""))

	if code != engine.ExitClean {
		t.Fatalf("exit = %d (want clean)", code)
	}
	acquired := eventNamed(events, "passAcquired")
	if acquired == nil {
		t.Fatalf("no passAcquired event (events: %v)", events)
	}
	if failed := eventNamed(events, "failed"); failed != nil {
		t.Fatalf("unexpected failed event: %v", failed)
	}
}

func TestGuardianProbeQuotaIsItsOwnOutcome(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = io.WriteString(w, `{"error":"quota_exceeded"}`)
	}))
	defer srv.Close()
	installTestControlPlane(t)

	events, code := captureProbe(t, probeConfigLine(srv.URL, ""))

	if code != engine.ExitQuota {
		t.Fatalf("exit = %d (want ExitQuota)", code)
	}
	if eventNamed(events, "quotaExhausted") == nil {
		t.Fatalf("no quotaExhausted event (events: %v)", events)
	}
	// Quota is NEVER a region block: no bootstrap trigger.
	if failed := eventNamed(events, "failed"); failed != nil {
		t.Fatalf("quota must not surface as failed: %v", failed)
	}
}

// ---- the apiProxy-routed probe: verified TLS through a REAL local proxy ----

// connectRecorder is a CONNECT-only proxy that records the targets.
type connectRecorder struct {
	listener net.Listener
	mu       sync.Mutex
	targets  []string
}

func startConnectRecorder(t *testing.T) *connectRecorder {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	cr := &connectRecorder{listener: listener}
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go cr.serve(conn)
		}
	}()
	t.Cleanup(func() { listener.Close() })
	return cr
}

func (cr *connectRecorder) serve(conn net.Conn) {
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	head := make([]byte, 0, 1024)
	buf := make([]byte, 1)
	for len(head) < 4096 {
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		head = append(head, buf[0])
		if len(head) >= 4 && string(head[len(head)-4:]) == "\r\n\r\n" {
			break
		}
	}
	line := string(head)
	if !strings.HasPrefix(line, "CONNECT ") {
		return
	}
	target := strings.Fields(strings.TrimPrefix(line, "CONNECT "))[0]
	cr.mu.Lock()
	cr.targets = append(cr.targets, target)
	cr.mu.Unlock()
	upstream, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		fmt.Fprintf(conn, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
		return
	}
	defer upstream.Close()
	fmt.Fprintf(conn, "HTTP/1.1 200 Connection Established\r\n\r\n")
	conn.SetReadDeadline(time.Time{})
	done := make(chan struct{}, 2)
	go func() { io.Copy(upstream, conn); done <- struct{}{} }()
	go func() { io.Copy(conn, upstream); done <- struct{}{} }()
	<-done
}

func (cr *connectRecorder) saw(target string) bool {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	for _, t := range cr.targets {
		if t == target {
			return true
		}
	}
	return false
}

func TestGuardianProbeRoutesThroughTheLocalProxyWithVerifiedTLS(t *testing.T) {
	// The full Stage-5 wiring proof at the engine level: the probe's
	// FetchProxyPass traverses the local proxy (CONNECT recorded) and
	// the TLS handshake against the Guardian double is VERIFIED through
	// the tunnel (the test CA is trusted via SSL_CERT_FILE — no
	// InsecureSkipVerify anywhere on this path; an untrusted
	// certificate would fail the whole probe).
	_, leafCert, leafKey := makeProbeTestCA(t)
	guardian := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/fpn/token" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("X-Quota-Remaining", "498")
		_ = json.NewEncoder(w).Encode(map[string]string{"token": shapeOnlyJWT(t)})
	}))
	guardian.TLS = &tls.Config{
		Certificates: []tls.Certificate{{
			Certificate: [][]byte{leafCert.Raw},
			PrivateKey:  leafKey,
		}},
		MinVersion: tls.VersionTLS12,
	}
	guardian.StartTLS()
	defer guardian.Close()

	recorder := startConnectRecorder(t)

	events, code := captureProbe(t, probeConfigLine(
		guardian.URL, "http://"+recorder.listener.Addr().String()))

	if code != engine.ExitClean {
		t.Fatalf("exit = %d (want clean; events: %v)", code, events)
	}
	if eventNamed(events, "passAcquired") == nil {
		t.Fatalf("no passAcquired event (events: %v)", events)
	}
	guardianAddr := strings.TrimPrefix(guardian.URL, "https://")
	if !recorder.saw(guardianAddr) {
		t.Fatalf("the probe's Guardian request never traversed the local proxy (targets: %v)", recorder.targets)
	}
	// The transport is process-global: restore the pinned default.
	t.Cleanup(func() {
		vpnclient.SetControlPlaneTransport(vpnclient.NewControlPlaneTransport())
	})
}

// makeProbeTestCA generates a self-signed CA + leaf for 127.0.0.1 and
// trusts the CA through SSL_CERT_FILE (Linux loads it at the FIRST
// verified-TLS use; no earlier test in this package verifies TLS).
func makeProbeTestCA(t *testing.T) (caKey *rsa.PrivateKey, leafCert *x509.Certificate, leafKey *rsa.PrivateKey) {
	t.Helper()
	caKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("ca key: %v", err)
	}
	caTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "guardian-probe-test-ca"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatalf("ca cert: %v", err)
	}
	caCert, err := x509.ParseCertificate(caDER)
	if err != nil {
		t.Fatalf("parse ca: %v", err)
	}
	if err := os.WriteFile(filepath.Join(t.TempDir(), "unused-ca.pem"),
		[]byte("placeholder"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	// The pem file Go's root pool loads:
	caPEM := "-----BEGIN CERTIFICATE-----\n" +
		base64.StdEncoding.EncodeToString(caDER) + "\n-----END CERTIFICATE-----\n"
	caPath := filepath.Join(t.TempDir(), "ca.pem")
	if err := os.WriteFile(caPath, []byte(caPEM), 0o600); err != nil {
		t.Fatalf("write ca: %v", err)
	}
	t.Setenv("SSL_CERT_FILE", caPath)

	leafKey, err = rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("leaf key: %v", err)
	}
	leafTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: "127.0.0.1"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
		DNSNames:     []string{"localhost"},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caCert, &leafKey.PublicKey, caKey)
	if err != nil {
		t.Fatalf("leaf cert: %v", err)
	}
	leafCert, err = x509.ParseCertificate(leafDER)
	if err != nil {
		t.Fatalf("parse leaf: %v", err)
	}
	return caKey, leafCert, leafKey
}
