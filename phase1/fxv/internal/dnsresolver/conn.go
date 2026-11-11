package dnsresolver

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"sync"
	"time"
)

type dohPacketConn struct {
	ctx      context.Context
	exchange *dohExchange
	mu       sync.Mutex
	response []byte
	readAt   int
	closed   bool
	deadline time.Time
}

func newDoHPacketConn(ctx context.Context, exchange *dohExchange) *dohPacketConn {
	return &dohPacketConn{ctx: ctx, exchange: exchange}
}

// net.Resolver.Dial returns net.Conn even for its UDP path. The wrapper also
// implements PacketConn methods so the packet semantics remain explicit.
func (c *dohPacketConn) Write(p []byte) (int, error) {
	return c.WriteTo(p, nil)
}
func (c *dohPacketConn) Read(p []byte) (int, error) {
	n, _, err := c.ReadFrom(p)
	return n, err
}
func (c *dohPacketConn) WriteTo(p []byte, _ net.Addr) (int, error) {
	c.mu.Lock()
	if c.closed { c.mu.Unlock(); return 0, net.ErrClosed }
	deadline := c.deadline
	c.mu.Unlock()
	ctx, cancel := withConnDeadline(c.ctx, deadline)
	defer cancel()
	response, err := c.exchange.exchange(ctx, p)
	if err != nil { return 0, err }
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed { return 0, net.ErrClosed }
	c.response = response
	c.readAt = 0
	return len(p), nil
}
func (c *dohPacketConn) ReadFrom(p []byte) (int, net.Addr, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed { return 0, nil, net.ErrClosed }
	if c.readAt >= len(c.response) { return 0, nil, io.EOF }
	n := copy(p, c.response[c.readAt:])
	c.readAt += n
	return n, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 53}, nil
}
func (c *dohPacketConn) Close() error { c.mu.Lock(); c.closed = true; c.mu.Unlock(); return nil }
func (c *dohPacketConn) LocalAddr() net.Addr { return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)} }
func (c *dohPacketConn) RemoteAddr() net.Addr { return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 53} }
func (c *dohPacketConn) SetDeadline(t time.Time) error { c.mu.Lock(); c.deadline = t; c.mu.Unlock(); return nil }
func (c *dohPacketConn) SetReadDeadline(t time.Time) error { return c.SetDeadline(t) }
func (c *dohPacketConn) SetWriteDeadline(t time.Time) error { return c.SetDeadline(t) }

type dohStreamConn struct {
	ctx      context.Context
	exchange *dohExchange
	mu       sync.Mutex
	in       []byte
	out      []byte
	closed   bool
	deadline time.Time
}

func newDoHStreamConn(ctx context.Context, exchange *dohExchange) *dohStreamConn {
	return &dohStreamConn{ctx: ctx, exchange: exchange}
}

func (c *dohStreamConn) Write(p []byte) (int, error) {
	c.mu.Lock()
	if c.closed { c.mu.Unlock(); return 0, net.ErrClosed }
	c.in = append(c.in, p...)
	deadline := c.deadline
	consumed := len(p)
	for len(c.in) >= 2 {
		size := int(binary.BigEndian.Uint16(c.in[:2]))
		if size == 0 || size > maxDNSMessageBytes {
			c.mu.Unlock()
			return 0, fmt.Errorf("invalid DNS-over-TCP frame length")
		}
		if len(c.in) < size+2 { break }
		query := append([]byte(nil), c.in[2:size+2]...)
		c.in = c.in[size+2:]
		c.mu.Unlock()
		ctx, cancel := withConnDeadline(c.ctx, deadline)
		response, err := c.exchange.exchange(ctx, query)
		cancel()
		if err != nil { return 0, err }
		if len(response) > maxDNSMessageBytes { return 0, fmt.Errorf("DNS response too large") }
		frame := make([]byte, len(response)+2)
		binary.BigEndian.PutUint16(frame[:2], uint16(len(response)))
		copy(frame[2:], response)
		c.mu.Lock()
		if c.closed { c.mu.Unlock(); return 0, net.ErrClosed }
		c.out = append(c.out, frame...)
	}
	c.mu.Unlock()
	return consumed, nil
}

func (c *dohStreamConn) Read(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed { return 0, net.ErrClosed }
	if len(c.out) == 0 { return 0, io.EOF }
	n := copy(p, c.out)
	c.out = c.out[n:]
	return n, nil
}
func (c *dohStreamConn) Close() error { c.mu.Lock(); c.closed = true; c.mu.Unlock(); return nil }
func (c *dohStreamConn) LocalAddr() net.Addr { return &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1)} }
func (c *dohStreamConn) RemoteAddr() net.Addr { return &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 53} }
func (c *dohStreamConn) SetDeadline(t time.Time) error { c.mu.Lock(); c.deadline = t; c.mu.Unlock(); return nil }
func (c *dohStreamConn) SetReadDeadline(t time.Time) error { return c.SetDeadline(t) }
func (c *dohStreamConn) SetWriteDeadline(t time.Time) error { return c.SetDeadline(t) }

func withConnDeadline(parent context.Context, deadline time.Time) (context.Context, context.CancelFunc) {
	if !deadline.IsZero() { return context.WithDeadline(parent, deadline) }
	return context.WithTimeout(parent, defaultRequestTimeout)
}
