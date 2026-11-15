package upstream

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"testing"
	"time"
)

func TestSOCKS5DialerUsesDomainCONNECT(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	serverErr := make(chan error, 1)
	go func() {
		control, err := listener.Accept()
		if err != nil {
			serverErr <- err
			return
		}
		defer control.Close()
		var greeting [3]byte
		if _, err := io.ReadFull(control, greeting[:]); err != nil {
			serverErr <- err
			return
		}
		if greeting != [3]byte{5, 1, 0} {
			serverErr <- io.ErrUnexpectedEOF
			return
		}
		_, _ = control.Write([]byte{5, 0})
		var head [4]byte
		if _, err := io.ReadFull(control, head[:]); err != nil {
			serverErr <- err
			return
		}
		if head != [4]byte{5, socks5Connect, 0, socks5Domain} {
			serverErr <- io.ErrUnexpectedEOF
			return
		}
		var n [1]byte
		if _, err := io.ReadFull(control, n[:]); err != nil {
			serverErr <- err
			return
		}
		host := make([]byte, int(n[0]))
		if _, err := io.ReadFull(control, host); err != nil {
			serverErr <- err
			return
		}
		var port [2]byte
		if _, err := io.ReadFull(control, port[:]); err != nil {
			serverErr <- err
			return
		}
		if string(host) != "edge.example" || binary.BigEndian.Uint16(port[:]) != 443 {
			serverErr <- io.ErrUnexpectedEOF
			return
		}
		_, _ = control.Write([]byte{5, 0, 0, socks5IPv4, 127, 0, 0, 1, 0, 0})
		payload := make([]byte, 4)
		if _, err := io.ReadFull(control, payload); err != nil {
			serverErr <- err
			return
		}
		_, err = control.Write(payload)
		serverErr <- err
	}()

	dialer := &SOCKS5Dialer{ProxyAddr: listener.Addr().String()}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	conn, err := dialer.DialContext(ctx, "tcp", "edge.example:443")
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	reply := make([]byte, 4)
	if _, err := io.ReadFull(conn, reply); err != nil {
		t.Fatal(err)
	}
	if string(reply) != "ping" {
		t.Fatalf("reply = %q", reply)
	}
	if err := <-serverErr; err != nil {
		t.Fatal(err)
	}
}

func TestSOCKS5PacketConnCarriesDomainUDPWithoutLocalDNS(t *testing.T) {
	controlListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer controlListener.Close()
	relay, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()

	serverErr := make(chan error, 1)
	go func() {
		control, err := controlListener.Accept()
		if err != nil {
			serverErr <- err
			return
		}
		defer control.Close()
		var greeting [3]byte
		if _, err := io.ReadFull(control, greeting[:]); err != nil {
			serverErr <- err
			return
		}
		_, _ = control.Write([]byte{5, 0})
		var request [10]byte
		if _, err := io.ReadFull(control, request[:]); err != nil {
			serverErr <- err
			return
		}
		if request[0] != 5 || request[1] != socks5UDP || request[3] != socks5IPv4 {
			serverErr <- io.ErrUnexpectedEOF
			return
		}
		bound := relay.LocalAddr().(*net.UDPAddr)
		_, _ = control.Write([]byte{5, 0, 0, socks5IPv4, 127, 0, 0, 1, byte(bound.Port >> 8), byte(bound.Port)})
		buf := make([]byte, 2048)
		n, client, err := relay.ReadFromUDP(buf)
		if err != nil {
			serverErr <- err
			return
		}
		host, pos, err := decodeSOCKS5UDPHost(buf[:n], 3)
		if err != nil || host != "edge.example" || pos+2 > n {
			serverErr <- io.ErrUnexpectedEOF
			return
		}
		if binary.BigEndian.Uint16(buf[pos:pos+2]) != 443 || string(buf[pos+2:n]) != "hello-quic" {
			serverErr <- io.ErrUnexpectedEOF
			return
		}
		reply := []byte{0, 0, 0, socks5Domain, byte(len("edge.example"))}
		reply = append(reply, "edge.example"...)
		reply = append(reply, 1, 187)
		reply = append(reply, "world-quic"...)
		_, err = relay.WriteToUDP(reply, client)
		serverErr <- err
		// Wait until the client tears down its TCP control connection.
		_, _ = io.Copy(io.Discard, control)
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	packetConn, err := NewSOCKS5PacketConn(ctx, controlListener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer packetConn.Close()

	destination := &socks5DomainUDPAddr{host: "edge.example", port: 443}
	if n, err := packetConn.WriteTo([]byte("hello-quic"), destination); err != nil || n != len("hello-quic") {
		t.Fatalf("WriteTo = %d, %v", n, err)
	}
	_ = packetConn.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 64)
	n, source, err := packetConn.ReadFrom(buf)
	if err != nil {
		t.Fatal(err)
	}
	if n != len("world-quic") || string(buf[:n]) != "world-quic" {
		t.Fatalf("reply = %q", buf[:n])
	}
	if source.String() != "edge.example:443" {
		t.Fatalf("source = %s", source)
	}
	if err := <-serverErr; err != nil {
		t.Fatal(err)
	}
}
