package noise

import (
	"context"
	"encoding/binary"
	"encoding/hex"
	"net"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/Psiphon-Labs/psiphon-tunnel-core/psiphon/common/prng"
)

const (
	maxRandom  = 1024
	maxPacket  = 1200
	firstPause = 2 * time.Millisecond
	letters    = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	digits     = "0123456789"
)

type Profile struct {
	Name            string
	BeforeHandshake int
	AfterFirst      int
	JunkMin         int
	JunkMax         int
	First           string
	Second          string
	Interval        time.Duration
}

var presets = map[string]Profile{
	"light": {
		Name:            "light",
		BeforeHandshake: 1,
		JunkMin:         32,
		JunkMax:         96,
		First:           "<b 0d0a0d0a><t><r 16>",
		Interval:        3 * time.Millisecond,
	},
	"firewall": {
		Name:            "firewall",
		BeforeHandshake: 2,
		AfterFirst:      2,
		JunkMin:         48,
		JunkMax:         190,
		First:           "<b 0d0a0d0a><t><r 24>",
		Second:          "<r 48>",
		Interval:        4 * time.Millisecond,
	},
	"gfw": {
		Name:            "gfw",
		BeforeHandshake: 2,
		AfterFirst:      1,
		JunkMin:         64,
		JunkMax:         256,
		First:           "<b 0d0a0d0a><t><r 24>",
		Second:          "<r 32>",
		Interval:        5 * time.Millisecond,
	},
}

func Lookup(name string) *Profile {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "", "off", "none":
		return nil
	case "light":
		return preset("light")
	case "gfw", "aggressive", "heavy":
		return preset("gfw")
	default:
		return preset("firewall")
	}
}

func preset(name string) *Profile {
	p := presets[name]
	return &p
}

type contextKey struct{}

func WithProfile(ctx context.Context, p *Profile) context.Context {
	if p == nil {
		return ctx
	}
	return context.WithValue(ctx, contextKey{}, p)
}

func FromContext(ctx context.Context) *Profile {
	if ctx == nil {
		return nil
	}
	p, _ := ctx.Value(contextKey{}).(*Profile)
	return p
}

func (p *Profile) Send(ctx context.Context, conn net.PacketConn, to *net.UDPAddr) int {
	if p == nil || conn == nil || to == nil {
		return 0
	}
	if ctx == nil {
		ctx = context.Background()
	}
	sent := 0
	write := func(b []byte) {
		if len(b) == 0 {
			return
		}
		if _, err := conn.WriteTo(guard(b), to); err == nil {
			sent++
		}
	}
	for i := 0; i < p.BeforeHandshake; i++ {
		write(p.junk())
		if !pause(ctx, p.Interval) {
			return sent
		}
	}
	if first := expand(p.First); len(first) > 0 {
		write(first)
		if !pause(ctx, firstPause) {
			return sent
		}
	}
	for i := 0; i < p.AfterFirst; i++ {
		write(p.junk())
		if !pause(ctx, p.Interval) {
			return sent
		}
	}
	write(expand(p.Second))
	return sent
}

func (p *Profile) junk() []byte {
	lo, hi := p.JunkMin, p.JunkMax
	if hi <= lo || lo <= 0 {
		lo, hi = 40, 90
	}
	return prng.Bytes(prng.Range(lo, hi))
}

func pause(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return true
	case <-ctx.Done():
		return false
	}
}

var counter atomic.Uint32

func expand(spec string) []byte {
	var out []byte
	for {
		open := strings.IndexByte(spec, '<')
		if open < 0 {
			break
		}
		end := strings.IndexByte(spec[open:], '>')
		if end < 0 {
			break
		}
		fields := strings.Fields(spec[open+1 : open+end])
		spec = spec[open+end+1:]
		if len(fields) == 0 {
			continue
		}
		arg := strings.Join(fields[1:], "")
		switch fields[0] {
		case "b":
			if b, err := hex.DecodeString(arg); err == nil {
				out = append(out, b...)
			}
		case "t":
			out = binary.BigEndian.AppendUint32(out, uint32(time.Now().Unix()))
		case "c":
			out = binary.BigEndian.AppendUint32(out, counter.Add(1))
		case "n":
			out = append(out, prng.Bytes(8)...)
		case "r":
			out = append(out, prng.Bytes(length(arg))...)
		case "rc":
			out = appendFrom(out, letters, length(arg))
		case "rd":
			out = appendFrom(out, digits, length(arg))
		}
	}
	if len(out) > maxPacket {
		out = out[:maxPacket]
	}
	return out
}

func appendFrom(out []byte, alphabet string, n int) []byte {
	for i := 0; i < n; i++ {
		out = append(out, alphabet[prng.Intn(len(alphabet))])
	}
	return out
}

func length(arg string) int {
	lo, hi, ranged := strings.Cut(arg, "-")
	n, err := strconv.Atoi(lo)
	if err != nil || n < 0 {
		return 0
	}
	if ranged {
		if top, err := strconv.Atoi(hi); err == nil && top > n {
			n = prng.Range(n, top)
		}
	}
	if n > maxRandom {
		n = maxRandom
	}
	return n
}

func guard(b []byte) []byte {
	if len(b) >= 5 && b[0]>>4 == 0x0c && b[1] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 1 {
		b[0] ^= 0x40
	}
	for _, at := range [...]int{29, 31, 34} {
		if len(b) >= at+4 && string(b[at:at+4]) == "CHLO" {
			b[at] ^= 0x20
		}
	}
	return b
}
