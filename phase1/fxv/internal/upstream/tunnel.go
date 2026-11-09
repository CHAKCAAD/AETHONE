// Package upstream — one MASQUE session and its controller, ADAPTED
// from the pinned upstream's cmd/proxy-demo/main.go. This file:
// tunnelWriteBuffer + tunnelConn (the bounded ring buffer used as the
// CONNECT request body, replacing io.Pipe so upload throughput is not
// bounded by a goroutine hand-off per write).
package upstream

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"
	"time"
)

// DefaultTunnelWriteBufSize is the CONNECT request-body buffer.
const DefaultTunnelWriteBufSize = 1 << 20

var errTunnelDeadline = errors.New("tunnel connection does not support deadlines")

// TunnelWriteBuffer is a bounded, concurrency-safe ring buffer used as
// the request body of a CONNECT tunnel (ADAPTED verbatim in behavior).
type TunnelWriteBuffer struct {
	mu       sync.Mutex
	notEmpty *sync.Cond
	notFull  *sync.Cond
	buf      []byte
	n        int
	off      int
	closed   bool
	readErr  error
}

// NewTunnelWriteBuffer builds the ring buffer (size < 1 → default).
func NewTunnelWriteBuffer(size int) *TunnelWriteBuffer {
	if size < 1 {
		size = DefaultTunnelWriteBufSize
	}
	b := &TunnelWriteBuffer{buf: make([]byte, size)}
	b.notEmpty = sync.NewCond(&b.mu)
	b.notFull = sync.NewCond(&b.mu)
	return b
}

// Read drains buffered data, blocking while the buffer is empty and
// still open. A read that reaches the end of the ring returns a short
// read rather than wrapping, which io.Reader permits.
func (b *TunnelWriteBuffer) Read(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	for b.n == 0 && b.readErr == nil && !b.closed {
		b.notEmpty.Wait()
	}
	if b.n == 0 {
		if b.readErr != nil {
			return 0, b.readErr
		}
		return 0, io.EOF
	}

	end := b.off + b.n
	if end > len(b.buf) {
		end = len(b.buf)
	}
	n := copy(p, b.buf[b.off:end])
	b.off = (b.off + n) % len(b.buf)
	b.n -= n
	b.notFull.Broadcast()
	return n, nil
}

// Write blocks only while the buffer is full, so bursts smaller than
// the buffer complete without waiting for the reader.
func (b *TunnelWriteBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	total := 0
	for len(p) > 0 {
		for b.n == len(b.buf) && b.readErr == nil && !b.closed {
			b.notFull.Wait()
		}
		if b.readErr != nil {
			return total, b.readErr
		}
		if b.closed {
			return total, io.ErrClosedPipe
		}

		space := len(b.buf) - b.n
		head := (b.off + b.n) % len(b.buf)
		writable := len(b.buf) - head
		if space < writable {
			writable = space
		}
		if writable > len(p) {
			writable = len(p)
		}
		copy(b.buf[head:], p[:writable])
		b.n += writable
		p = p[writable:]
		total += writable
		b.notEmpty.Broadcast()
	}
	return total, nil
}

// Close signals end of stream. Buffered data stays readable so a
// half-closed tunnel still flushes what the client already wrote.
func (b *TunnelWriteBuffer) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.closed {
		return nil
	}
	b.closed = true
	b.notEmpty.Broadcast()
	b.notFull.Broadcast()
	return nil
}

// FailRead makes pending and future reads fail with err, unblocking
// the HTTP/2 request body reader when the tunnel is torn down.
func (b *TunnelWriteBuffer) FailRead(err error) {
	b.mu.Lock()
	if b.readErr == nil {
		b.readErr = err
	}
	b.closed = true
	b.notEmpty.Broadcast()
	b.notFull.Broadcast()
	b.mu.Unlock()
}

// TunnelConn is one established CONNECT tunnel presented as a
// net.Conn (ADAPTED verbatim in behavior).
type TunnelConn struct {
	reader  io.ReadCloser
	writer  *TunnelWriteBuffer
	reqBody *TunnelWriteBuffer
	cancel  context.CancelFunc
	name    tunnelAddr

	closeOnce sync.Once
	readOnce  sync.Once
	writeOnce sync.Once
	closeErr  error
	readErr   error
	writeErr  error
}

func (c *TunnelConn) Read(p []byte) (int, error) { return c.reader.Read(p) }

func (c *TunnelConn) Write(p []byte) (int, error) { return c.writer.Write(p) }

func (c *TunnelConn) Close() error {
	c.closeOnce.Do(func() {
		writeErr := c.CloseWrite()
		readErr := c.CloseRead()
		if c.reqBody != nil {
			c.reqBody.FailRead(io.ErrClosedPipe)
		}
		if c.cancel != nil {
			c.cancel()
		}
		if writeErr != nil {
			c.closeErr = writeErr
		} else {
			c.closeErr = readErr
		}
	})
	return c.closeErr
}

func (c *TunnelConn) CloseRead() error {
	c.readOnce.Do(func() {
		if c.reader != nil {
			c.readErr = c.reader.Close()
		}
	})
	return c.readErr
}

func (c *TunnelConn) CloseWrite() error {
	c.writeOnce.Do(func() {
		if c.writer != nil {
			c.writeErr = c.writer.Close()
		}
	})
	return c.writeErr
}

func (c *TunnelConn) LocalAddr() net.Addr                 { return c.name }
func (c *TunnelConn) RemoteAddr() net.Addr                { return c.name }
func (c *TunnelConn) SetDeadline(time.Time) error         { return errTunnelDeadline }
func (c *TunnelConn) SetReadDeadline(time.Time) error     { return errTunnelDeadline }
func (c *TunnelConn) SetWriteDeadline(time.Time) error    { return errTunnelDeadline }

type tunnelAddr string

func (a tunnelAddr) Network() string { return "tcp" }
func (a tunnelAddr) String() string  { return string(a) }
