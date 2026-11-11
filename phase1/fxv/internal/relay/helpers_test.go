package relay

// Shared test helpers: TLS roots for the local httptest servers (the
// production transports verify against the system roots; the local test
// CA is not there).

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

// TestMain points Go's root-certificate file at the httptest CA: the
// ECH dialer's plain-TLS fallback verifies against the SYSTEM roots
// (that is its security property — no injection point), and the local
// test servers must therefore verify through them. Set before the
// first handshake; the x509 root pool loads lazily exactly once.
func TestMain(m *testing.M) {
	s := httptest.NewUnstartedServer(nil)
	s.StartTLS()
	cert := s.Certificate()
	s.Close()

	f, err := os.CreateTemp("", "relay-test-roots-*.pem")
	if err != nil {
		fmt.Fprintln(os.Stderr, "test roots:", err)
		os.Exit(1)
	}
	if _, err := f.Write(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})); err != nil {
		fmt.Fprintln(os.Stderr, "test roots:", err)
		os.Exit(1)
	}
	f.Close()
	os.Setenv("SSL_CERT_FILE", f.Name())
	os.Exit(m.Run())
}

// tlsRootsOf builds the cert pool trusting the local server.
func tlsRootsOf(server *httptest.Server) *x509.CertPool {
	pool := x509.NewCertPool()
	pool.AddCert(server.Certificate())
	return pool
}

// tlsRootsTransport is an HTTP/1.1 transport trusting the local server.
func tlsRootsTransport(server *httptest.Server) *http.Transport {
	return &http.Transport{TLSClientConfig: &tls.Config{RootCAs: tlsRootsOf(server)}}
}
