// Package socks — the loopback SOCKS5 CONNECT server, ADAPTED from the
// pinned upstream's cmd/proxy-demo/main.go (socksServer,
// handshakeSOCKS5, readSOCKSAddr, writeSOCKSReply, mapUpstreamError,
// proxyBidirectional, copyConn, closeIdleConns). Adaptations (the
// phase-1 ORIGIN record):
//
//   - the client-affinity opener variant is REMOVED (no pool, no
//     per-client slot memory — exactly one upstream session exists);
//   - logging goes through the injected level-tagged sink, never to
//     the upstream's global logEvent; the target/error redaction lives
//     HERE (logTarget / RedactedError) gated by the sink's Verbose();
//   - UDP ASSOCIATE is refused (CONNECT only — the upstream semantics
//     the AETHONE adapter relies on, tcpOnly zeptun TUN);
//   - the upstream demo's LOG LEVEL discipline is restored (Stage 6):
//     per-connection debug lines are no-ops unless the sink is verbose,
//     targets are redacted even on warn lines, and only the live=N
//     diagnostics ride Info (always visible — the Stage-2 evidence
//     channel for the maxConns cap).
package socks

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"aethone/fxv/internal/upstream"
)

const (
	socksVersion5       = 0x05
	socksCmdConnect     = 0x01
	socksAtypIPv4       = 0x01
	socksAtypDomain     = 0x03
	socksAtypIPv6       = 0x04
	socksAuthNoAuth     = 0x00
	socksAuthNoAccept   = 0xff
	socksReplySuccess   = 0x00
	socksReplyFailure   = 0x01
	socksReplyNotAllow  = 0x02
	socksReplyNetUnrch  = 0x03
	socksReplyHostUnrch = 0x04
	socksReplyCmdUnsup  = 0x07
	socksReplyAtypUnsup = 0x08
)

const (
	copyBufferSize        = 64 * 1024
	halfCloseDrainTimeout = 2 * time.Minute
)

// ErrUnsupportedAddrType is reported for SOCKS address types the server
// does not parse (mapUpstreamError maps it to reply 0x08).
var ErrUnsupportedAddrType = errors.New("unsupported SOCKS address type")

// TunnelOpener opens one CONNECT tunnel to the authority (the upstream
// session implements it).
type TunnelOpener interface {
	OpenTunnel(authority string) (net.Conn, error)
}

// LogSink receives the server's level-tagged diagnostics. The sink
// owns the upstream demo's level discipline: Debugf is a no-op unless
// Verbose() reports true (the -verbose flag parity), Infof/Warnf are
// always on, and Verbose() is what un-redacts targets and error bodies.
type LogSink interface {
	Debugf(format string, args ...any)
	Infof(format string, args ...any)
	Warnf(format string, args ...any)
	Verbose() bool
}

// Server is the SOCKS5 CONNECT server (loopback-only by contract —
// the engine's config validation refuses anything else).
type Server struct {
	upstream         TunnelOpener
	handshakeTimeout time.Duration
	idleTimeout      time.Duration
	connSlots        chan struct{}
	log              LogSink

	mu       sync.Mutex
	listener net.Listener
	conns    map[net.Conn]struct{}
	closed   bool
}

// NewServer builds the server. handshakeTimeout/idleTimeout <= 0 means
// unlimited; maxConns <= 0 means unlimited.
func NewServer(upstream TunnelOpener, handshakeTimeout, idleTimeout time.Duration, maxConns int, log LogSink) *Server {
	var slots chan struct{}
	if maxConns > 0 {
		slots = make(chan struct{}, maxConns)
	}
	if log == nil {
		log = discardSink{}
	}
	return &Server{
		upstream:         upstream,
		handshakeTimeout: handshakeTimeout,
		idleTimeout:      idleTimeout,
		connSlots:        slots,
		log:              log,
		conns:            make(map[net.Conn]struct{}),
	}
}

// Listen binds addr (the engine validated it loopback) and serves until
// Close. The returned net.Addr is the REAL bound address (socksReady).
func (s *Server) Listen(addr string) (net.Addr, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		_ = ln.Close()
		return nil, errors.New("server closed")
	}
	s.listener = ln
	s.mu.Unlock()

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			s.track(conn)
			go func() {
				defer s.untrack(conn)
				s.handleConn(conn)
			}()
		}
	}()
	return ln.Addr(), nil
}

func (s *Server) track(conn net.Conn) {
	s.mu.Lock()
	s.conns[conn] = struct{}{}
	n := len(s.conns)
	s.mu.Unlock()
	// Stage-2 diagnostic on the Info level (Stage 6): the live count
	// is the on-device evidence channel for the maxConns cap, so it
	// must stay visible at the engine's normal level while the
	// per-connection debug lines go quiet (upstream parity).
	s.log.Infof("socks: conn tracked live=%d", n)
}

func (s *Server) untrack(conn net.Conn) {
	s.mu.Lock()
	delete(s.conns, conn)
	n := len(s.conns)
	s.mu.Unlock()
	s.log.Infof("socks: conn untracked live=%d", n)
}

// Close stops accepting and closes every live client connection.
func (s *Server) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true
	var err error
	if s.listener != nil {
		err = s.listener.Close()
	}
	for conn := range s.conns {
		_ = conn.Close()
	}
	return err
}

func (s *Server) acquireConnSlot() bool {
	if s.connSlots == nil {
		return true
	}
	select {
	case s.connSlots <- struct{}{}:
		return true
	default:
		return false
	}
}

func (s *Server) releaseConnSlot() {
	if s.connSlots == nil {
		return
	}
	<-s.connSlots
}

func (s *Server) handleConn(conn net.Conn) {
	// Stage-2 fix (upstream parity): the deferred release must be
	// registered ONLY after a successful acquire. Registering it
	// before the acquire — as the adaptation had — makes every
	// REJECTED connection run releaseConnSlot anyway: a receive
	// from the full buffered channel that STEALS a live
	// connection's slot, so each rejection erodes the cap by one
	// (cap=N degrades toward unlimited under rejection storms).
	// The upstream registers the release after the acquire; so do we.
	defer conn.Close()
	clientAddr := logAddr(conn.RemoteAddr())
	if !s.acquireConnSlot() {
		s.log.Warnf("socks: client rejected: connection limit reached client=%s", clientAddr)
		return
	}
	defer s.releaseConnSlot()
	s.log.Debugf("socks: client connected client=%s", clientAddr)

	if s.handshakeTimeout > 0 {
		_ = conn.SetDeadline(time.Now().Add(s.handshakeTimeout))
	}
	target, replyCode, err := Handshake(conn)
	if err != nil {
		s.log.Debugf("socks: handshake failed client=%s reply=%d err=%v", clientAddr, replyCode, err)
		if replyCode != 0 {
			if writeErr := WriteReply(conn, replyCode, nil); writeErr != nil {
				s.log.Debugf("socks: handshake failure reply failed client=%s err=%v", clientAddr, writeErr)
			}
		}
		return
	}
	if s.handshakeTimeout > 0 {
		_ = conn.SetDeadline(time.Time{})
	}
	s.log.Debugf("socks: CONNECT requested client=%s target=%s", clientAddr, s.logTarget(target))

	upstreamConn, err := s.upstream.OpenTunnel(target)
	if err != nil {
		reply := MapUpstreamError(err)
		s.log.Warnf("socks: upstream tunnel open failed client=%s target=%s reply=%d err=%s",
			clientAddr, s.logTarget(target), reply, upstream.RedactedError(err, s.log.Verbose()))
		if writeErr := WriteReply(conn, reply, nil); writeErr != nil {
			s.log.Debugf("socks: upstream failure reply failed client=%s err=%v", clientAddr, writeErr)
		}
		return
	}
	defer upstreamConn.Close()

	if err := WriteReply(conn, socksReplySuccess, conn.LocalAddr()); err != nil {
		s.log.Debugf("socks: success reply failed client=%s target=%s err=%v", clientAddr, s.logTarget(target), err)
		return
	}
	s.log.Debugf("socks: upstream tunnel open succeeded client=%s target=%s", clientAddr, s.logTarget(target))
	ProxyBidirectional(conn, upstreamConn, s.idleTimeout)
	s.log.Debugf("socks: client disconnected client=%s target=%s", clientAddr, s.logTarget(target))
}

// Handshake performs the SOCKS5 greeting + CONNECT request read
// (ADAPTED from handshakeSOCKS5). Returns the target authority
// ("host:port").
func Handshake(conn net.Conn) (string, byte, error) {
	header := make([]byte, 2)
	if _, err := io.ReadFull(conn, header); err != nil {
		return "", 0, err
	}
	if header[0] != socksVersion5 {
		return "", 0, fmt.Errorf("unexpected SOCKS version %d", header[0])
	}

	methods := make([]byte, int(header[1]))
	if _, err := io.ReadFull(conn, methods); err != nil {
		return "", 0, err
	}

	method := byte(socksAuthNoAccept)
	for _, candidate := range methods {
		if candidate == socksAuthNoAuth {
			method = socksAuthNoAuth
			break
		}
	}
	if _, err := conn.Write([]byte{socksVersion5, method}); err != nil {
		return "", 0, err
	}
	if method == socksAuthNoAccept {
		return "", 0, errors.New("no supported SOCKS auth methods")
	}

	reqHeader := make([]byte, 4)
	if _, err := io.ReadFull(conn, reqHeader); err != nil {
		return "", 0, err
	}
	if reqHeader[0] != socksVersion5 {
		return "", socksReplyFailure, fmt.Errorf("unexpected request version %d", reqHeader[0])
	}
	if reqHeader[1] != socksCmdConnect {
		return "", socksReplyCmdUnsup, fmt.Errorf("unsupported SOCKS command %d", reqHeader[1])
	}

	host, err := ReadAddr(conn, reqHeader[3])
	if err != nil {
		if errors.Is(err, ErrUnsupportedAddrType) {
			return "", socksReplyAtypUnsup, err
		}
		return "", socksReplyFailure, err
	}

	portBytes := make([]byte, 2)
	if _, err := io.ReadFull(conn, portBytes); err != nil {
		return "", socksReplyFailure, err
	}
	port := binary.BigEndian.Uint16(portBytes)
	return net.JoinHostPort(host, fmt.Sprintf("%d", port)), socksReplySuccess, nil
}

// ReadAddr parses one SOCKS address field (ADAPTED from readSOCKSAddr).
func ReadAddr(r io.Reader, atyp byte) (string, error) {
	switch atyp {
	case socksAtypIPv4:
		buf := make([]byte, net.IPv4len)
		if _, err := io.ReadFull(r, buf); err != nil {
			return "", err
		}
		return net.IP(buf).String(), nil
	case socksAtypIPv6:
		buf := make([]byte, net.IPv6len)
		if _, err := io.ReadFull(r, buf); err != nil {
			return "", err
		}
		return net.IP(buf).String(), nil
	case socksAtypDomain:
		var size [1]byte
		if _, err := io.ReadFull(r, size[:]); err != nil {
			return "", err
		}
		buf := make([]byte, int(size[0]))
		if _, err := io.ReadFull(r, buf); err != nil {
			return "", err
		}
		return string(buf), nil
	default:
		return "", ErrUnsupportedAddrType
	}
}

// WriteReply writes one SOCKS5 reply (ADAPTED from writeSOCKSReply).
func WriteReply(w io.Writer, rep byte, addr net.Addr) error {
	host := "0.0.0.0"
	port := 0
	if addr != nil {
		if tcpAddr, ok := addr.(*net.TCPAddr); ok {
			host = tcpAddr.IP.String()
			port = tcpAddr.Port
		}
	}

	ip := net.ParseIP(host)
	atyp := byte(socksAtypIPv4)
	addrBytes := []byte{0, 0, 0, 0}
	if ip != nil && ip.To4() != nil {
		addrBytes = ip.To4()
	} else if ip != nil && ip.To16() != nil {
		atyp = socksAtypIPv6
		addrBytes = ip.To16()
	}

	reply := make([]byte, 0, 6+len(addrBytes))
	reply = append(reply, socksVersion5, rep, 0x00, atyp)
	reply = append(reply, addrBytes...)
	reply = append(reply, byte(port>>8), byte(port))
	_, err := w.Write(reply)
	return err
}

// MapUpstreamError maps an upstream open failure to a SOCKS reply code
// (ADAPTED from mapUpstreamError).
func MapUpstreamError(err error) byte {
	if err == nil {
		return socksReplyFailure
	}
	if errors.Is(err, ErrUnsupportedAddrType) {
		return socksReplyAtypUnsup
	}
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return socksReplyHostUnrch
	}
	return socksReplyFailure
}

// ProxyBidirectional relays both directions with optional idle close
// (ADAPTED from proxyBidirectional + closeIdleConns + copyConn).
func ProxyBidirectional(clientConn, upstreamConn net.Conn, idleTimeout time.Duration) {
	var activity func()
	done := make(chan struct{})

	if idleTimeout > 0 {
		activityCh := make(chan struct{}, 1)
		activity = func() {
			select {
			case activityCh <- struct{}{}:
			default:
			}
		}
		go closeIdleConns(clientConn, upstreamConn, idleTimeout, activityCh, done)
	} else {
		activity = func() {}
	}

	results := make(chan error, 2)
	go func() {
		err := copyConn(upstreamConn, clientConn, activity)
		if err == nil {
			closeWrite(upstreamConn)
		}
		results <- err
	}()

	go func() {
		err := copyConn(clientConn, upstreamConn, activity)
		if err == nil {
			closeWrite(clientConn)
		}
		results <- err
	}()

	firstErr := <-results
	if firstErr != nil {
		_ = clientConn.Close()
		_ = upstreamConn.Close()
	}
	var secondErr error
	if firstErr == nil {
		drainTimer := time.NewTimer(halfCloseDrainTimeout)
		select {
		case secondErr = <-results:
			if !drainTimer.Stop() {
				<-drainTimer.C
			}
		case <-drainTimer.C:
			_ = clientConn.Close()
			_ = upstreamConn.Close()
			secondErr = <-results
		}
	} else {
		secondErr = <-results
	}
	if secondErr != nil {
		_ = clientConn.Close()
		_ = upstreamConn.Close()
	}
	close(done)
}

func closeIdleConns(clientConn, upstreamConn net.Conn, idleTimeout time.Duration, activity <-chan struct{}, done <-chan struct{}) {
	timer := time.NewTimer(idleTimeout)
	defer timer.Stop()
	for {
		select {
		case <-activity:
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			timer.Reset(idleTimeout)
		case <-timer.C:
			_ = clientConn.Close()
			_ = upstreamConn.Close()
			return
		case <-done:
			return
		}
	}
}

var copyBufferPool = sync.Pool{
	New: func() any { return make([]byte, copyBufferSize) },
}

func copyConn(dst, src net.Conn, activity func()) error {
	buf := copyBufferPool.Get().([]byte)
	defer copyBufferPool.Put(buf)

	for {
		nr, readErr := src.Read(buf)
		if nr > 0 {
			activity()
			nw, writeErr := dst.Write(buf[:nr])
			if nw > 0 {
				activity()
			}
			if writeErr != nil {
				return writeErr
			}
			if nw != nr {
				return io.ErrShortWrite
			}
		}
		if readErr != nil {
			if errors.Is(readErr, io.EOF) {
				return nil
			}
			return readErr
		}
	}
}

func closeWrite(conn net.Conn) {
	if closeWriter, ok := conn.(interface{ CloseWrite() error }); ok {
		_ = closeWriter.CloseWrite()
	}
}

// logTarget renders a SOCKS target for logging (upstream logTarget
// parity): the full authority only under verbose; otherwise the demo's
// redaction marker — on EVERY line it appears in, warn included, so
// browsing domains never reach core-log.txt at the normal level.
func (s *Server) logTarget(target string) string {
	if s.log.Verbose() {
		return target
	}
	return "<redacted; use -verbose>"
}

func logAddr(addr net.Addr) string {
	if addr == nil {
		return "<nil>"
	}
	return addr.String()
}

// discardSink drops every log line (tests / quiet mode).
type discardSink struct{}

func (discardSink) Debugf(string, ...any) {}
func (discardSink) Infof(string, ...any)  {}
func (discardSink) Warnf(string, ...any)  {}
func (discardSink) Verbose() bool          { return false }
