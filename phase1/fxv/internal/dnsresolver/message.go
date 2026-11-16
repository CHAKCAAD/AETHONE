package dnsresolver

import (
        "context"
        "encoding/binary"
        "errors"
        "fmt"
        "net"
        "net/netip"
        "strings"
)

// iranBlockPageV6 holds the IPv6 addresses of Iran's filtering page
// (arman-vpn-client, internal/resolver — its IPv4 ones, 10.10.34.34-36,
// are private and caught by IsPrivate).
var iranBlockPageV6 = netip.MustParsePrefix("2001:4188:2:600:10:10:34:0/112")

// IsBlockPage reports whether a public name resolving to addr cannot be
// its real address: a filtering network's answer (the reference's rule,
// ported verbatim). Private, loopback, unspecified and link-local
// addresses are never a public server's real address, and neither is the
// filtering page's IPv6 block.
func IsBlockPage(addr netip.Addr) bool {
        addr = addr.Unmap()
        return addr.IsPrivate() || addr.IsLoopback() || addr.IsUnspecified() ||
                addr.IsLinkLocalUnicast() || iranBlockPageV6.Contains(addr)
}

// IsBlockPageIP is [IsBlockPage] for a net.IP answer record.
func IsBlockPageIP(ip net.IP) bool {
        parsed, ok := netip.AddrFromSlice(ip)
        if !ok {
                return false
        }
        return IsBlockPage(parsed)
}

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
        // The direct system path (the local-domain split and the pure
        // system mode): the rcode-encoded reply, block-page addresses
        // stripped (a poisoned name fails to resolve rather than walking
        // the connection into the filter).
        switch question.qtype {
        case 1, 28:
        default:
                return buildDNSResponse(query, question, nil, 0), nil
        }
        resolved, err := resolver.LookupIPAddr(ctx, question.name)
        if err != nil {
                rcode := uint16(2) // SERVFAIL: retain the distinction from NXDOMAIN.
                var dnsErr *net.DNSError
                if errors.As(err, &dnsErr) && dnsErr.IsNotFound { rcode = 3 }
                return buildDNSResponse(query, question, nil, rcode), nil
        }
        var valid []net.IP
        for _, item := range resolved {
                if question.qtype == 1 && item.IP.To4() != nil && !IsBlockPageIP(item.IP.To4()) {
                        valid = append(valid, item.IP.To4())
                }
                if question.qtype == 28 && item.IP.To4() == nil && !IsBlockPageIP(item.IP.To16()) {
                        valid = append(valid, item.IP.To16())
                }
        }
        return buildDNSResponse(query, question, valid, 0), nil
}

// systemLookupResponse answers from the system resolver for the RACING
// exchange (1.9.0, the reference's systemLookup contract): a failed
// lookup (NXDOMAIN, SERVFAIL) is an ERROR — the racing state machine
// ignores it while the DoH endpoints are still in flight, exactly like
// arman-vpn-client's lookupWithSystem. A successful answer carries the
// block-page filter: the filtering network's addresses are stripped,
// and an answer that was ONLY block pages is reported as poisoned (it
// is held as the last resort, never the winner while the endpoints
// can still answer).
func systemLookupResponse(ctx context.Context, query []byte, question dnsQuestion, resolver *net.Resolver) ([]byte, bool, error) {
        switch question.qtype {
        case 1, 28:
        default:
                // Other record types keep the rcode-encoded reply (the
                // packet-conn seam needs a message, and the racing path
                // only asks A/AAAA through Go's own resolver).
                return buildDNSResponse(query, question, nil, 0), false, nil
        }
        resolved, err := resolver.LookupIPAddr(ctx, question.name)
        if err != nil {
                return nil, false, err
        }
        var ips []net.IP
        var hadAddresses bool
        for _, item := range resolved {
                if question.qtype == 1 && item.IP.To4() != nil {
                        ips = append(ips, item.IP.To4())
                        hadAddresses = true
                }
                if question.qtype == 28 && item.IP.To4() == nil {
                        ips = append(ips, item.IP.To16())
                        hadAddresses = true
                }
        }
        valid := make([]net.IP, 0, len(ips))
        for _, ip := range ips {
                if !IsBlockPageIP(ip) {
                        valid = append(valid, ip)
                }
        }
        poisoned := hadAddresses && len(valid) == 0
        return buildDNSResponse(query, question, valid, 0), poisoned, nil
}

// parseAnswerAddresses walks a DNS response's answer section and returns
// every A/AAAA record's address (CNAME chains included) and whether the
// section carried any address record at all. The walk starts after the
// question section ([questionEnd]).
func parseAnswerAddresses(response []byte, questionEnd int) ([]net.IP, bool, error) {
        if len(response) < 12 {
                return nil, false, fmt.Errorf("short DNS response")
        }
        answers := int(binary.BigEndian.Uint16(response[6:8]))
        offset := questionEnd
        var ips []net.IP
        hadAddresses := false
        for i := 0; i < answers; i++ {
                _, next, err := readDNSName(response, offset)
                if err != nil { return nil, false, err }
                offset = next
                if offset+10 > len(response) { return nil, false, fmt.Errorf("truncated DNS answer header") }
                rrType := binary.BigEndian.Uint16(response[offset : offset+2])
                rdLength := int(binary.BigEndian.Uint16(response[offset+8 : offset+10]))
                offset += 10
                if offset+rdLength > len(response) { return nil, false, fmt.Errorf("truncated DNS answer data") }
                switch rrType {
                case 1:
                        if rdLength == 4 {
                                ips = append(ips, net.IP(append([]byte(nil), response[offset:offset+rdLength]...)))
                                hadAddresses = true
                        }
                case 28:
                        if rdLength == 16 {
                                ips = append(ips, net.IP(append([]byte(nil), response[offset:offset+rdLength]...)))
                                hadAddresses = true
                        }
                }
                offset += rdLength
        }
        return ips, hadAddresses, nil
}

// filterBlockPageAnswers rewrites a response whose answer section carries
// block-page addresses (the filtering network's answer) keeping only the
// real ones. It reports whether the response remains usable: a fully
// poisoned answer (every address was a block page) is NOT usable — the
// racing exchange keeps waiting for another server's answer.
func filterBlockPageAnswers(query []byte, question dnsQuestion, response []byte) ([]byte, bool, error) {
        if question.qtype != 1 && question.qtype != 28 {
                return response, true, nil // not an address question: nothing to filter
        }
        if rcode := binary.BigEndian.Uint16(response[2:4]) & 0x000f; rcode != 0 {
                return response, true, nil // an authoritative negative answer
        }
        ips, hadAddresses, err := parseAnswerAddresses(response, question.questionEnd)
        if err != nil {
                return nil, false, err
        }
        if !hadAddresses {
                return response, true, nil // NODATA / non-address records: pass through
        }
        valid := make([]net.IP, 0, len(ips))
        for _, ip := range ips {
                if !IsBlockPageIP(ip) { valid = append(valid, ip) }
        }
        if len(valid) == 0 {
                return nil, false, nil // fully poisoned
        }
        if len(valid) == len(ips) {
                return response, true, nil // nothing to strip: keep the original (CNAMEs intact)
        }
        return buildDNSResponse(query, question, valid, 0), true, nil
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
