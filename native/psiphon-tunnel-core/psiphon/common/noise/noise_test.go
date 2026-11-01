package noise

import (
	"bytes"
	"context"
	"encoding/binary"
	"net"
	"testing"
	"time"
)

func TestLookupMatchesAether(t *testing.T) {
	for _, name := range []string{"", "off", "none", " OFF "} {
		if p := Lookup(name); p != nil {
			t.Fatalf("%q should disable noise, got %s", name, p.Name)
		}
	}
	cases := map[string]string{
		"light": "light", "firewall": "firewall", "balanced": "firewall", "unknown": "firewall",
		"gfw": "gfw", "aggressive": "gfw", "heavy": "gfw", " GFW ": "gfw",
	}
	for name, want := range cases {
		if got := Lookup(name); got == nil || got.Name != want {
			t.Fatalf("Lookup(%q) = %v, want %s", name, got, want)
		}
	}
	f := Lookup("firewall")
	if f.BeforeHandshake != 2 || f.AfterFirst != 2 || f.JunkMin != 48 || f.JunkMax != 190 ||
		f.Interval != 4*time.Millisecond || f.First != "<b 0d0a0d0a><t><r 24>" || f.Second != "<r 48>" {
		t.Fatalf("firewall drifted from Aether: %+v", *f)
	}
	Lookup("firewall").JunkMax = 1
	if Lookup("firewall").JunkMax != 190 {
		t.Fatal("Lookup must hand out copies, not the preset itself")
	}
}

func TestExpandTags(t *testing.T) {
	first := expand("<b 0d0a0d0a><t><r 24>")
	if len(first) != 4+4+24 || !bytes.HasPrefix(first, []byte{0x0d, 0x0a, 0x0d, 0x0a}) {
		t.Fatalf("I1 = %x", first)
	}
	stamp := int64(binary.BigEndian.Uint32(first[4:8]))
	if d := time.Now().Unix() - stamp; d < 0 || d > 5 {
		t.Fatalf("<t> is %d seconds off", d)
	}
	if got := expand("<b 0d 0a 0d 0a>"); !bytes.Equal(got, []byte{0x0d, 0x0a, 0x0d, 0x0a}) {
		t.Fatalf("hex with spaces = %x", got)
	}
	if got := expand("<n>"); len(got) != 8 {
		t.Fatalf("<n> gave %d bytes", len(got))
	}
	a, b := expand("<c>"), expand("<c>")
	if binary.BigEndian.Uint32(b) != binary.BigEndian.Uint32(a)+1 {
		t.Fatalf("<c> did not count: %x then %x", a, b)
	}
	for i := 0; i < 200; i++ {
		letters := expand("<rc 20-40>")
		if len(letters) < 20 || len(letters) > 40 {
			t.Fatalf("<rc 20-40> gave %d", len(letters))
		}
		for _, c := range letters {
			if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z') {
				t.Fatalf("<rc> produced %q", c)
			}
		}
		for _, c := range expand("<rd 12>") {
			if c < '0' || c > '9' {
				t.Fatalf("<rd> produced %q", c)
			}
		}
	}
	if got := expand("<r 5000>"); len(got) != maxRandom {
		t.Fatalf("<r> must cap at %d, gave %d", maxRandom, len(got))
	}
	if got := expand("<r 1024><r 1024>"); len(got) != maxPacket {
		t.Fatalf("a packet must cap at %d, gave %d", maxPacket, len(got))
	}
	if got := expand("<b zz><x 9><r -3><r abc>< >"); len(got) != 0 {
		t.Fatalf("malformed tags must add nothing, gave %x", got)
	}
	if got := expand(""); got != nil {
		t.Fatalf("empty spec gave %x", got)
	}
}

func TestJunkStaysInRange(t *testing.T) {
	for _, name := range []string{"light", "firewall", "gfw"} {
		p := Lookup(name)
		for i := 0; i < 500; i++ {
			if n := len(p.junk()); n < p.JunkMin || n > p.JunkMax {
				t.Fatalf("%s junk of %d bytes, want %d..%d", name, n, p.JunkMin, p.JunkMax)
			}
		}
	}
	p := &Profile{JunkMin: 0, JunkMax: 0}
	for i := 0; i < 100; i++ {
		if n := len(p.junk()); n < 40 || n > 90 {
			t.Fatalf("fallback junk of %d bytes", n)
		}
	}
}

func looksLikeClientHello(b []byte) bool {
	if len(b) >= 5 && b[0]>>4 == 0x0c && b[1] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 1 {
		return true
	}
	for _, at := range []int{29, 31, 34} {
		if len(b) >= at+4 && string(b[at:at+4]) == "CHLO" {
			return true
		}
	}
	return false
}

func TestGuardNeverEmitsAClientHello(t *testing.T) {
	ietf := append([]byte{0xc3, 0, 0, 0, 1}, make([]byte, 60)...)
	if looksLikeClientHello(guard(ietf)) {
		t.Fatalf("IETF Initial lookalike survived: %x", ietf[:5])
	}
	for _, at := range []int{29, 31, 34} {
		g := make([]byte, 64)
		copy(g[at:], "CHLO")
		if looksLikeClientHello(guard(g)) {
			t.Fatalf("gQUIC CHLO at %d survived", at)
		}
	}
	plain := expand("<b 0d0a0d0a><t><r 24>")
	before := append([]byte(nil), plain...)
	if !bytes.Equal(guard(plain), before) {
		t.Fatal("guard changed a packet that was never a ClientHello")
	}
}

func receive(t *testing.T, server net.PacketConn, want int) [][]byte {
	var got [][]byte
	buf := make([]byte, 2048)
	for len(got) < want {
		_ = server.SetReadDeadline(time.Now().Add(2 * time.Second))
		n, _, err := server.ReadFrom(buf)
		if err != nil {
			t.Fatalf("received %d of %d packets: %v", len(got), want, err)
		}
		got = append(got, append([]byte(nil), buf[:n]...))
	}
	_ = server.SetReadDeadline(time.Now().Add(50 * time.Millisecond))
	if _, _, err := server.ReadFrom(buf); err == nil {
		t.Fatalf("more than %d packets arrived", want)
	}
	return got
}

func pair(t *testing.T) (net.PacketConn, net.PacketConn, *net.UDPAddr) {
	server, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	client, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { server.Close(); client.Close() })
	return server, client, server.LocalAddr().(*net.UDPAddr)
}

func TestSendOrderMatchesAether(t *testing.T) {
	for _, name := range []string{"light", "firewall", "gfw"} {
		t.Run(name, func(t *testing.T) {
			p := Lookup(name)
			server, client, to := pair(t)
			want := p.BeforeHandshake + 1 + p.AfterFirst
			if p.Second != "" {
				want++
			}
			if sent := p.Send(context.Background(), client, to); sent != want {
				t.Fatalf("Send reported %d packets, want %d", sent, want)
			}
			got := receive(t, server, want)
			for i := 0; i < p.BeforeHandshake; i++ {
				if n := len(got[i]); n < p.JunkMin || n > p.JunkMax {
					t.Fatalf("packet %d is %d bytes, not junk", i, n)
				}
			}
			first := got[p.BeforeHandshake]
			if !bytes.HasPrefix(first, []byte{0x0d, 0x0a, 0x0d, 0x0a}) {
				t.Fatalf("packet %d should be I1, got %x", p.BeforeHandshake, first[:8])
			}
			for i, pkt := range got {
				if len(pkt) > maxPacket || looksLikeClientHello(pkt) {
					t.Fatalf("packet %d is unsafe to send: %d bytes", i, len(pkt))
				}
			}
		})
	}
}

func TestSendIsANoOpWhenOff(t *testing.T) {
	_, client, to := pair(t)
	var off *Profile
	if n := off.Send(context.Background(), client, to); n != 0 {
		t.Fatalf("a nil profile sent %d packets", n)
	}
	if n := Lookup("firewall").Send(context.Background(), client, nil); n != 0 {
		t.Fatalf("no destination, yet %d packets", n)
	}
}

func TestSendStopsWhenTheDialIsCancelled(t *testing.T) {
	_, client, to := pair(t)
	p := &Profile{BeforeHandshake: 5, JunkMin: 50, JunkMax: 60, First: "<r 10>", Interval: time.Hour}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan int)
	go func() { done <- p.Send(ctx, client, to) }()
	time.Sleep(20 * time.Millisecond)
	cancel()
	select {
	case n := <-done:
		if n != 1 {
			t.Fatalf("sent %d packets before the cancel took effect", n)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Send ignored the cancelled context")
	}
}

func TestContextCarriesTheProfile(t *testing.T) {
	ctx := context.Background()
	if WithProfile(ctx, nil) != ctx {
		t.Fatal("attaching no profile must leave the context alone")
	}
	if FromContext(ctx) != nil {
		t.Fatal("an empty context has no profile")
	}
	p := Lookup("gfw")
	inner, cancel := context.WithTimeout(WithProfile(ctx, p), time.Minute)
	defer cancel()
	if FromContext(inner) != p {
		t.Fatal("the profile must survive derived contexts")
	}
}
