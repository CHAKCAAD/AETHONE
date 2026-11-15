package upstream

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"time"
)

const (
	socks5Version = 5
	socks5NoAuth  = 0
	socks5Connect = 1
	socks5UDP     = 3
	socks5IPv4    = 1
	socks5Domain  = 3
	socks5IPv6    = 4
)

// SOCKS5Dialer opens TCP streams through a loopback SOCKS5 proxy. It is used
// by Firefox's HTTP/2 tunnel when Aether is the outer carrier.
type SOCKS5Dialer struct {
	ProxyAddr string
	Dialer    net.Dialer
}

func (d *SOCKS5Dialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	if network != "tcp" && network != "tcp4" && network != "tcp6" {
		return nil, fmt.Errorf("SOCKS5 CONNECT only supports TCP, got %q", network)
	}
	host, portText, err := net.SplitHostPort(address)
	if err != nil {
		return nil, fmt.Errorf("invalid SOCKS5 target: %w", err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("invalid SOCKS5 target port")
	}

	conn, err := d.Dialer.DialContext(ctx, "tcp", d.ProxyAddr)
	if err != nil {
		return nil, err
	}
	ok := false
	defer func() {
		if !ok {
			_ = conn.Close()
		}
	}()
	if deadline, exists := ctx.Deadline(); exists {
		_ = conn.SetDeadline(deadline)
	}
	if err := socks5Negotiate(conn); err != nil {
		return nil, err
	}
	request, err := socks5Request(socks5Connect, host, uint16(port))
	if err != nil {
		return nil, err
	}
	if _, err := conn.Write(request); err != nil {
		return nil, err
	}
	if _, err := readSOCKS5Reply(conn); err != nil {
		return nil, err
	}
	_ = conn.SetDeadline(time.Time{})
	ok = true
	return conn, nil
}

// SOCKS5PacketConn is an RFC 1928 UDP association. The TCP control connection
// stays open for the lifetime of the UDP socket, as required by SOCKS5.
type SOCKS5PacketConn struct {
	udp     *net.UDPConn
	control net.Conn
	relay   *net.UDPAddr
	proxyIP net.IP
}

// NewSOCKS5PacketConn establishes UDP ASSOCIATE through a loopback SOCKS5
// endpoint. It deliberately binds its datagrams to loopback too, so the
// Aether SOCKS server sees the same client address as the control connection.
func NewSOCKS5PacketConn(ctx context.Context, proxyAddr string) (*SOCKS5PacketConn, error) {
	host, _, err := net.SplitHostPort(proxyAddr)
	if err != nil {
		return nil, fmt.Errorf("invalid SOCKS5 proxy address: %w", err)
	}
	proxyIP := net.ParseIP(host)
	if proxyIP == nil || !proxyIP.IsLoopback() {
		return nil, fmt.Errorf("SOCKS5 upstream must be a loopback IP")
	}
	dialer := &net.Dialer{}
	control, err := dialer.DialContext(ctx, "tcp", proxyAddr)
	if err != nil {
		return nil, err
	}
	fail := func(err error) (*SOCKS5PacketConn, error) {
		_ = control.Close()
		return nil, err
	}
	if deadline, exists := ctx.Deadline(); exists {
		_ = control.SetDeadline(deadline)
	}
	if err := socks5Negotiate(control); err != nil {
		return fail(err)
	}
	request, _ := socks5Request(socks5UDP, "0.0.0.0", 0)
	if _, err := control.Write(request); err != nil {
		return fail(err)
	}
	relay, err := readSOCKS5Reply(control)
	if err != nil {
		return fail(err)
	}
	_ = control.SetDeadline(time.Time{})
	if relay.IP == nil || relay.IP.IsUnspecified() {
		relay.IP = append(net.IP(nil), proxyIP...)
	}
	if !relay.IP.IsLoopback() {
		return fail(fmt.Errorf("SOCKS5 UDP relay is not loopback"))
	}
	udp, err := net.ListenUDP("udp", &net.UDPAddr{IP: proxyIP})
	if err != nil {
		return fail(err)
	}
	return &SOCKS5PacketConn{udp: udp, control: control, relay: relay, proxyIP: proxyIP}, nil
}

func socks5Negotiate(conn net.Conn) error {
	if _, err := conn.Write([]byte{socks5Version, 1, socks5NoAuth}); err != nil {
		return err
	}
	var reply [2]byte
	if _, err := io.ReadFull(conn, reply[:]); err != nil {
		return err
	}
	if reply[0] != socks5Version || reply[1] != socks5NoAuth {
		return fmt.Errorf("SOCKS5 proxy refused no-auth negotiation")
	}
	return nil
}

func socks5Request(command byte, host string, port uint16) ([]byte, error) {
	out := []byte{socks5Version, command, 0}
	var err error
	out, err = appendSOCKS5Address(out, host, port)
	return out, err
}

func appendSOCKS5Address(out []byte, host string, port uint16) ([]byte, error) {
	if ip := net.ParseIP(host); ip != nil {
		if v4 := ip.To4(); v4 != nil {
			out = append(out, socks5IPv4)
			out = append(out, v4...)
		} else {
			out = append(out, socks5IPv6)
			out = append(out, ip.To16()...)
		}
	} else {
		if host == "" || len(host) > 255 || strings.ContainsAny(host, "/?#@") {
			return nil, fmt.Errorf("invalid SOCKS5 destination host")
		}
		out = append(out, socks5Domain, byte(len(host)))
		out = append(out, host...)
	}
	var p [2]byte
	binary.BigEndian.PutUint16(p[:], port)
	return append(out, p[:]...), nil
}

func readSOCKS5Reply(r io.Reader) (*net.UDPAddr, error) {
	var header [4]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return nil, err
	}
	if header[0] != socks5Version || header[2] != 0 {
		return nil, fmt.Errorf("malformed SOCKS5 reply")
	}
	if header[1] != 0 {
		return nil, fmt.Errorf("SOCKS5 request failed (reply %d)", header[1])
	}
	host, err := readSOCKS5Host(r, header[3])
	if err != nil {
		return nil, err
	}
	var p [2]byte
	if _, err := io.ReadFull(r, p[:]); err != nil {
		return nil, err
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return nil, fmt.Errorf("SOCKS5 reply address is not an IP")
	}
	return &net.UDPAddr{IP: ip, Port: int(binary.BigEndian.Uint16(p[:]))}, nil
}

func readSOCKS5Host(r io.Reader, atyp byte) (string, error) {
	switch atyp {
	case socks5IPv4:
		var b [4]byte
		_, err := io.ReadFull(r, b[:])
		return net.IP(b[:]).String(), err
	case socks5IPv6:
		var b [16]byte
		_, err := io.ReadFull(r, b[:])
		return net.IP(b[:]).String(), err
	case socks5Domain:
		var n [1]byte
		if _, err := io.ReadFull(r, n[:]); err != nil {
			return "", err
		}
		b := make([]byte, int(n[0]))
		if _, err := io.ReadFull(r, b); err != nil {
			return "", err
		}
		return string(b), nil
	default:
		return "", fmt.Errorf("unsupported SOCKS5 address type %d", atyp)
	}
}

func (c *SOCKS5PacketConn) ReadFrom(p []byte) (int, net.Addr, error) {
	buf := make([]byte, 65535)
	for {
		n, from, err := c.udp.ReadFromUDP(buf)
		if err != nil {
			return 0, nil, err
		}
		if !from.IP.Equal(c.relay.IP) || from.Port != c.relay.Port {
			continue
		}
		if n < 4 || buf[0] != 0 || buf[1] != 0 || buf[2] != 0 {
			continue
		}
		host, pos, err := decodeSOCKS5UDPHost(buf[:n], 3)
		if err != nil || pos+2 > n {
			continue
		}
		port := int(binary.BigEndian.Uint16(buf[pos : pos+2]))
		pos += 2
		if port == 0 {
			continue
		}
		var source net.Addr
		if ip := net.ParseIP(host); ip != nil {
			source = &net.UDPAddr{IP: ip, Port: port}
		} else {
			source = &socks5DomainUDPAddr{host: host, port: port}
		}
		copied := copy(p, buf[pos:n])
		return copied, source, nil
	}
}

func decodeSOCKS5UDPHost(packet []byte, pos int) (string, int, error) {
	if pos >= len(packet) {
		return "", 0, io.ErrUnexpectedEOF
	}
	atyp := packet[pos]
	pos++
	switch atyp {
	case socks5IPv4:
		if pos+4 > len(packet) {
			return "", 0, io.ErrUnexpectedEOF
		}
		return net.IP(packet[pos : pos+4]).String(), pos + 4, nil
	case socks5IPv6:
		if pos+16 > len(packet) {
			return "", 0, io.ErrUnexpectedEOF
		}
		return net.IP(packet[pos : pos+16]).String(), pos + 16, nil
	case socks5Domain:
		if pos >= len(packet) {
			return "", 0, io.ErrUnexpectedEOF
		}
		n := int(packet[pos])
		pos++
		if n == 0 || pos+n > len(packet) {
			return "", 0, io.ErrUnexpectedEOF
		}
		return string(packet[pos : pos+n]), pos + n, nil
	default:
		return "", 0, fmt.Errorf("unsupported SOCKS5 UDP address type %d", atyp)
	}
}

func (c *SOCKS5PacketConn) WriteTo(p []byte, addr net.Addr) (int, error) {
	host, port, err := socks5HostPort(addr)
	if err != nil {
		return 0, err
	}
	packet, err := appendSOCKS5Address([]byte{0, 0, 0}, host, uint16(port))
	if err != nil {
		return 0, err
	}
	packet = append(packet, p...)
	_, err = c.udp.WriteToUDP(packet, c.relay)
	if err != nil {
		return 0, err
	}
	return len(p), nil
}

func socks5HostPort(addr net.Addr) (string, int, error) {
	switch value := addr.(type) {
	case *net.UDPAddr:
		if value.Port < 1 || value.Port > 65535 {
			return "", 0, fmt.Errorf("invalid UDP destination port")
		}
		if value.IP == nil {
			return "", 0, fmt.Errorf("UDP destination has no IP")
		}
		return value.IP.String(), value.Port, nil
	case *socks5DomainUDPAddr:
		if value.port < 1 || value.port > 65535 {
			return "", 0, fmt.Errorf("invalid UDP destination port")
		}
		return value.host, value.port, nil
	default:
		host, portText, err := net.SplitHostPort(addr.String())
		if err != nil {
			return "", 0, err
		}
		port, err := strconv.Atoi(portText)
		return host, port, err
	}
}

// socks5DomainUDPAddr preserves a hostname so DNS resolution happens inside
// the Aether carrier instead of leaking a direct lookup from the Firefox child.
type socks5DomainUDPAddr struct {
	host string
	port int
}

func (a *socks5DomainUDPAddr) Network() string { return "udp" }
func (a *socks5DomainUDPAddr) String() string  { return net.JoinHostPort(a.host, strconv.Itoa(a.port)) }

func (c *SOCKS5PacketConn) Close() error {
	udpErr := c.udp.Close()
	controlErr := c.control.Close()
	if udpErr != nil {
		return udpErr
	}
	return controlErr
}

func (c *SOCKS5PacketConn) LocalAddr() net.Addr                { return c.udp.LocalAddr() }
func (c *SOCKS5PacketConn) SetDeadline(t time.Time) error      { return c.udp.SetDeadline(t) }
func (c *SOCKS5PacketConn) SetReadDeadline(t time.Time) error  { return c.udp.SetReadDeadline(t) }
func (c *SOCKS5PacketConn) SetWriteDeadline(t time.Time) error { return c.udp.SetWriteDeadline(t) }
