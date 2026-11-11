package dnsresolver

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"strings"
)

type dnsQuestion struct {
	name        string
	qtype       uint16
	questionEnd int
}

func parseDNSQuestion(message []byte) (dnsQuestion, int, error) {
	if len(message) < 12 || binary.BigEndian.Uint16(message[4:6]) == 0 {
		return dnsQuestion{}, 0, fmt.Errorf("DNS query has no question")
	}
	name, offset, err := readDNSName(message, 12)
	if err != nil || offset+4 > len(message) { return dnsQuestion{}, 0, fmt.Errorf("malformed DNS question") }
	return dnsQuestion{name: strings.TrimSuffix(strings.ToLower(name), "."), qtype: binary.BigEndian.Uint16(message[offset:offset+2]), questionEnd: offset+4}, offset+4, nil
}

func readDNSName(message []byte, start int) (string, int, error) {
	labels := make([]string, 0, 8)
	offset, next := start, -1
	for hops := 0; hops < 128; hops++ {
		if offset >= len(message) { return "", 0, fmt.Errorf("name outside message") }
		length := int(message[offset])
		if length&0xc0 == 0xc0 {
			if offset+1 >= len(message) { return "", 0, fmt.Errorf("short compression pointer") }
			ptr := ((length & 0x3f) << 8) | int(message[offset+1])
			if ptr >= len(message) { return "", 0, fmt.Errorf("bad compression pointer") }
			if next < 0 { next = offset+2 }
			offset = ptr
			continue
		}
		if length&0xc0 != 0 { return "", 0, fmt.Errorf("unsupported DNS label type") }
		offset++
		if length == 0 {
			if next < 0 { next = offset }
			return strings.Join(labels, ".") + ".", next, nil
		}
		if length > 63 || offset+length > len(message) { return "", 0, fmt.Errorf("bad DNS label length") }
		labels = append(labels, string(message[offset:offset+length]))
		offset += length
	}
	return "", 0, fmt.Errorf("DNS compression pointer loop")
}

func buildSystemResponse(ctx context.Context, query []byte, question dnsQuestion, resolver *net.Resolver) ([]byte, error) {
	var ips []net.IP
	switch question.qtype {
	case 1, 28:
		resolved, err := resolver.LookupIPAddr(ctx, question.name)
		if err != nil {
			rcode := uint16(2) // SERVFAIL: retain the distinction from NXDOMAIN.
			var dnsErr *net.DNSError
			if errors.As(err, &dnsErr) && dnsErr.IsNotFound { rcode = 3 }
			return buildDNSResponse(query, question, nil, rcode), nil
		}
		for _, item := range resolved {
			if question.qtype == 1 && item.IP.To4() != nil { ips = append(ips, item.IP.To4()) }
			if question.qtype == 28 && item.IP.To4() == nil { ips = append(ips, item.IP.To16()) }
		}
	}
	return buildDNSResponse(query, question, ips, 0), nil
}

func buildDNSResponse(query []byte, question dnsQuestion, ips []net.IP, rcode uint16) []byte {
	out := make([]byte, 12)
	copy(out[:2], query[:2])
	flags := binary.BigEndian.Uint16(query[2:4])
	flags |= 0x8000 | 0x0080
	flags = (flags & 0xfff0) | (rcode & 0x000f)
	binary.BigEndian.PutUint16(out[2:4], flags)
	binary.BigEndian.PutUint16(out[4:6], 1)
	binary.BigEndian.PutUint16(out[6:8], uint16(len(ips)))
	out = append(out, query[12:question.questionEnd]...)
	for _, ip := range ips {
		var rrType uint16
		var data []byte
		if v4 := ip.To4(); v4 != nil { rrType, data = 1, v4 } else if v6 := ip.To16(); v6 != nil { rrType, data = 28, v6 } else { continue }
		rr := []byte{0xc0, 0x0c, byte(rrType >> 8), byte(rrType), 0x00, 0x01, 0x00, 0x00, 0x00, 0x3c, byte(len(data) >> 8), byte(len(data))}
		out = append(out, rr...)
		out = append(out, data...)
	}
	return out
}
