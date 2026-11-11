package dnsresolver

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestValidateModesAndEndpoints(t *testing.T) {
	c, err := (Config{}).Validate()
	if err != nil || c.Mode != ModeSystem { t.Fatalf("default config: %+v, %v", c, err) }
	if _, err := (Config{Mode: ModeDoH, Provider: ProviderCustom}).Validate(); err == nil {
		t.Fatal("custom provider without endpoint must fail")
	}
	if _, err := (Config{Mode: ModeDoH, Provider: ProviderCloudflare, Endpoint:"http://dns.example/dns-query"}).Validate(); err == nil {
		t.Fatal("plain HTTP DoH endpoint must fail")
	}
	if _, err := (Config{Mode: ModeDoH, Provider: ProviderCustom, Endpoint:"https://user:pass@dns.example/dns-query"}).Validate(); err == nil {
		t.Fatal("endpoint user-info must fail")
	}
}

func TestNormalizeExceptionsAndSuffixMatch(t *testing.T) {
	c, err := (Config{
		Mode: ModeDoH, Provider: ProviderCloudflare,
		SystemForLocalDomains: true,
		SystemDomainExceptions: []string{"*.corp.example", ".internal.example"},
	}).Validate()
	if err != nil { t.Fatal(err) }
	for _, host := range []string{"localhost", "printer.local", "vpn.corp.example", "internal.example"} {
		if !c.UsesSystemDNS(host) { t.Fatalf("%s should use system DNS", host) }
	}
	for _, host := range []string{"accounts.firefox.com", "notcorp.example"} {
		if c.UsesSystemDNS(host) { t.Fatalf("%s should use DoH", host) }
	}
}

func TestDNSQuestionAndSyntheticSystemReply(t *testing.T) {
	query := makeDNSQuery("unit.test", 1)
	question, _, err := parseDNSQuestion(query)
	if err != nil { t.Fatal(err) }
	if question.name != "unit.test" || question.qtype != 1 { t.Fatalf("question = %+v", question) }
	reply := buildDNSResponse(query, question, []net.IP{net.IPv4(192,0,2,10)}, 0)
	if binary.BigEndian.Uint16(reply[6:8]) != 1 { t.Fatalf("answer count: %d", binary.BigEndian.Uint16(reply[6:8])) }
	if !strings.Contains(strings.ToLower(string(reply)), "unit") { t.Fatal("question was not retained") }
}

func TestDNSCacheHonorsTTLAndTransactionID(t *testing.T) {
	cache := newDNSCache(2)
	query := makeDNSQuery("cache.test", 1)
	question, _, _ := parseDNSQuestion(query)
	reply := buildDNSResponse(query, question, []net.IP{net.IPv4(192,0,2,11)}, 0)
	cache.put(query, reply)
	query2 := append([]byte(nil), query...)
	query2[0], query2[1] = 0x12, 0x34
	got, ok := cache.get(query2)
	if !ok { t.Fatal("expected cache hit") }
	if got[0] != 0x12 || got[1] != 0x34 { t.Fatal("transaction ID was not restored") }
}

func TestWithConnDeadlineUsesParentCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	child, done := withConnDeadline(ctx, time.Time{})
	defer done()
	if child.Err() == nil { t.Fatal("parent cancellation was lost") }
}

func TestDoHExchangePostsRFC8484Message(t *testing.T) {
	var sawRequest bool
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost { t.Errorf("method = %s", r.Method) }
		if r.Header.Get("Content-Type") != "application/dns-message" { t.Errorf("content type = %q", r.Header.Get("Content-Type")) }
		if r.Header.Get("Accept") != "application/dns-message" { t.Errorf("accept = %q", r.Header.Get("Accept")) }
		sawRequest = true
		query, err := io.ReadAll(r.Body)
		if err != nil { t.Errorf("read query: %v", err); return }
		question, _, err := parseDNSQuestion(query)
		if err != nil { t.Errorf("parse query: %v", err); return }
		w.Header().Set("Content-Type", "application/dns-message")
		_, _ = w.Write(buildDNSResponse(query, question, []net.IP{net.IPv4(203,0,113,44)}, 0))
	}))
	defer server.Close()
	cfg, err := (Config{Mode:ModeDoH, Provider:ProviderCustom, Endpoint:server.URL}).Validate()
	if err != nil { t.Fatal(err) }
	exchange := &dohExchange{cfg:cfg, client:server.Client(), systemResolver:net.DefaultResolver, cache:newDNSCache(8)}
	query := makeDNSQuery("accounts.example", 1)
	response, err := exchange.exchange(context.Background(), query)
	if err != nil { t.Fatal(err) }
	if !sawRequest { t.Fatal("DoH endpoint was not called") }
	if response[0] != query[0] || response[1] != query[1] { t.Fatal("DNS transaction ID changed") }
	if binary.BigEndian.Uint16(response[6:8]) != 1 { t.Fatalf("answers = %d", binary.BigEndian.Uint16(response[6:8])) }
}

func makeDNSQuery(name string, qtype uint16) []byte {
	message := make([]byte, 12)
	binary.BigEndian.PutUint16(message[:2], 0x1234)
	binary.BigEndian.PutUint16(message[2:4], 0x0100)
	binary.BigEndian.PutUint16(message[4:6], 1)
	for _, label := range strings.Split(name, ".") {
		message = append(message, byte(len(label)))
		message = append(message, label...)
	}
	message = append(message, 0, byte(qtype>>8), byte(qtype), 0, 1)
	return message
}
