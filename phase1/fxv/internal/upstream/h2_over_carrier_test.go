package upstream_test

// The h2-over-carrier integration test (1.4.0-warp): proves the MASQUE
// data plane really rides a SOCKS5 carrier. The full loop, all local:
//
//	H2ProxySession ──(SOCKS5 CONNECT)──▶ fxv socks server (the
//	"aether" carrier) ──▶ fake MASQUE h2 server (TLS + h2 CONNECT,
//	x/net/http2 ServeConn) ──▶ echo TCP listener (the "internet")
//
// The session's TLS verifies against the system pool, so TestMain
// installs the test CA via SSL_CERT_FILE (honored by crypto/x509 on
// Linux; set before any pool load — TestMain runs first).

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"net/http"

	"golang.org/x/net/http2"

	"aethone/fxv/internal/carrier"
	"aethone/fxv/internal/socks"
	"aethone/fxv/internal/upstream"
)

// testCertPEM/testKeyPEM: ONE pair per process, generated in TestMain
// so the SSL_CERT_FILE root and every server instance present the SAME
// certificate.
var testCertPEM, testKeyPEM []byte

func TestMain(m *testing.M) {
	testCertPEM, testKeyPEM = selfSignedPair()
	certPEM, keyPEM := testCertPEM, testKeyPEM
	dir, err := os.MkdirTemp("", "fxv-h2-carrier-test")
	if err != nil {
		fmt.Fprintln(os.Stderr, "mktemp:", err)
		os.Exit(1)
	}
	defer os.RemoveAll(dir)
	caPath := dir + "/ca.pem"
	if err := os.WriteFile(caPath, certPEM, 0o600); err != nil {
		fmt.Fprintln(os.Stderr, "write ca:", err)
		os.Exit(1)
	}
	// crypto/x509's system pool honors SSL_CERT_FILE on Unix; set
	// before the first handshake in this process.
	os.Setenv("SSL_CERT_FILE", caPath)
	_ = keyPEM
	os.Exit(m.Run())
}

// selfSignedPair builds one ECDSA P-256 cert (SAN 127.0.0.1 +
// localhost) and returns its DER-less PEM pair.
func selfSignedPair() (certPEM, keyPEM []byte) {
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: "127.0.0.1"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		// BasicConstraintsValid is REQUIRED alongside IsCA — without it
		// CreateCertificate drops the basicConstraints extension and the
		// self-signed pair fails TLS verification with a confusing
		// "parent cannot sign this kind" ConstraintViolation.
		BasicConstraintsValid: true,
		IsCA:                  true,
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		DNSNames:              []string{"localhost"},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		panic(err)
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		panic(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}),
		pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
}

// carrierSink drops the fxv socks server's diagnostics.
type carrierSink struct{}

func (carrierSink) Debugf(string, ...any) {}
func (carrierSink) Infof(string, ...any)  {}
func (carrierSink) Warnf(string, ...any)  {}
func (carrierSink) Verbose() bool         { return false }

// forwardOpener dials the fake MASQUE server for every CONNECT (the
// "aether carrier" stand-in: one fixed upstream).
type forwardOpener struct{ target string }

func (o forwardOpener) OpenTunnel(string) (net.Conn, error) {
	return net.Dial("tcp", o.target)
}

// echoOpener's tunnels are plain pipes to the dialed authority (the
// carrier talking to the real internet side).
type echoOpener struct{}

func (echoOpener) OpenTunnel(authority string) (net.Conn, error) {
	return net.Dial("tcp", authority)
}

// startEcho runs a line-echo TCP listener.
func startEcho(t *testing.T) net.Addr {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("echo listen: %v", err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				_, _ = io.Copy(c, c)
			}(c)
		}
	}()
	return ln.Addr()
}

// startFakeMasque runs the TLS+h2 CONNECT proxy. Its handler answers
// CONNECT by dialing the request's authority and piping the stream.
func startFakeMasque(t *testing.T) *url.URL {
	t.Helper()
	cert, err := tls.X509KeyPair(testCertPEM, testKeyPEM)
	if err != nil {
		t.Fatalf("keypair: %v", err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("masque listen: %v", err)
	}
	t.Cleanup(func() { _ = ln.Close() })

	handler := http2.Server{}
	go func() {
		for {
			raw, err := ln.Accept()
			if err != nil {
				return
			}
			go func(raw net.Conn) {
				defer raw.Close()
				tlsConn := tls.Server(raw, &tls.Config{
					Certificates: []tls.Certificate{cert},
					MinVersion:   tls.VersionTLS12,
					NextProtos:   []string{"h2"},
				})
				if err := tlsConn.Handshake(); err != nil {
					return
				}
				if tlsConn.ConnectionState().NegotiatedProtocol != "h2" {
					return
				}
				handler.ServeConn(tlsConn, &http2.ServeConnOpts{
					Handler: connectProxyHandler(),
				})
			}(raw)
		}
	}()
	return &url.URL{Scheme: "https", Host: ln.Addr().String()}
}

// connectProxyHandler pipes each CONNECT stream to its authority. The
// response direction flushes after every write: the h2 responseWriter
// buffers DATA frames and a CONNECT tunnel's bytes cannot wait for the
// buffer to fill — without the flush the tunnel deadlocks on its first
// response chunk.
func connectProxyHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		target, err := net.Dial("tcp", r.Host)
		if err != nil {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		defer target.Close()
		w.WriteHeader(http.StatusOK)
		flushOnce(w)
		done := make(chan struct{}, 2)
		go func() {
			_, _ = io.Copy(target, r.Body)
			done <- struct{}{}
		}()
		go func() {
			_ = copyWithFlush(w, target)
			done <- struct{}{}
		}()
		<-done
	})
}

func flushOnce(w http.ResponseWriter) {
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
}

// copyWithFlush streams src into w, flushing after every write (the
// CONNECT tunnel contract: each chunk the target produces must go out
// as its own DATA frame, not accumulate in the response buffer).
func copyWithFlush(w http.ResponseWriter, src io.Reader) error {
	flusher, _ := w.(http.Flusher)
	buf := make([]byte, 32*1024)
	for {
		n, err := src.Read(buf)
		if n > 0 {
			if _, werr := w.Write(buf[:n]); werr != nil {
				return werr
			}
			if flusher != nil {
				flusher.Flush()
			}
		}
		if err != nil {
			return err
		}
	}
}

// startCarrier runs the fxv SOCKS5 server (the aether stand-in).
func startCarrier(t *testing.T) string {
	t.Helper()
	srv := socks.NewServer(echoOpener{}, 5*time.Second, 0, 0, carrierSink{})
	addr, err := srv.Listen("127.0.0.1:0")
	if err != nil {
		t.Fatalf("carrier listen: %v", err)
	}
	t.Cleanup(func() { _ = srv.Close() })
	return addr.String()
}

// TestH2SessionOverCarrier is the data-plane evidence: one full h2
// MASQUE session — TLS + CONNECT tunnel — whose every byte transits
// the SOCKS5 carrier (the session's DialFunc), carrying a payload
// roundtrip to the echo listener behind the fake proxy.
func TestH2SessionOverCarrier(t *testing.T) {
	echoAddr := startEcho(t)
	masqueURL := startFakeMasque(t)
	carrierAddr := startCarrier(t)

	d, err := carrier.New("socks5://" + carrierAddr)
	if err != nil {
		t.Fatalf("carrier.New: %v", err)
	}
	session, err := upstream.NewH2ProxySessionOverCarrier(
		masqueURL, "test-token", 10*time.Second, d.DialContext)
	if err != nil {
		t.Fatalf("NewH2ProxySessionOverCarrier: %v", err)
	}
	defer session.Close()

	if !session.IsAlive() {
		t.Fatal("the session over the carrier is not alive")
	}
	conn, err := session.OpenTunnel(echoAddr.String())
	if err != nil {
		t.Fatalf("OpenTunnel: %v", err)
	}
	defer conn.Close()

	const payload = "masque-data-plane-over-warp"
	go func() {
		_, _ = conn.Write([]byte(payload + "\n"))
	}()
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		t.Fatalf("tunnel read: %v", err)
	}
	if strings.TrimSpace(line) != payload {
		t.Fatalf("roundtrip = %q, want %q", line, payload)
	}
	if _, _, err := net.SplitHostPort(session.ProxyHost()); err != nil {
		t.Fatalf("ProxyHost = %q", session.ProxyHost())
	}
}

// TestH2SessionCarrierDirectEquivalence pins the DIRECT constructor's
// unchanged behavior (nil dial → the plain net.Dialer path).
func TestH2SessionCarrierDirectEquivalence(t *testing.T) {
	echoAddr := startEcho(t)
	masqueURL := startFakeMasque(t)

	// No carrier: the session dials the fake proxy directly. The
	// fake proxy's CONNECT still reaches the echo listener.
	session, err := upstream.NewH2ProxySession(masqueURL, "test-token", 10*time.Second)
	if err != nil {
		t.Fatalf("NewH2ProxySession: %v", err)
	}
	defer session.Close()
	conn, err := session.OpenTunnel(echoAddr.String())
	if err != nil {
		t.Fatalf("OpenTunnel: %v", err)
	}
	defer conn.Close()
	const payload = "direct-path-unchanged"
	go func() { _, _ = conn.Write([]byte(payload + "\n")) }()
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		t.Fatalf("tunnel read: %v", err)
	}
	if strings.TrimSpace(line) != payload {
		t.Fatalf("roundtrip = %q, want %q", line, payload)
	}
}

// TestH2SessionOverCarrierNilDial guards the constructor's contract.
func TestH2SessionOverCarrierNilDial(t *testing.T) {
	if _, err := upstream.NewH2ProxySessionOverCarrier(&url.URL{Scheme: "https", Host: "127.0.0.1:1"}, "t", time.Second, nil); err == nil {
		t.Fatal("nil dial must be refused")
	}
	_ = context.Background()
}
