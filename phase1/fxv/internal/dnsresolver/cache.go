package dnsresolver

import (
	"encoding/binary"
	"sync"
	"time"
)

type dnsCacheEntry struct {
	response []byte
	expires  time.Time
}

type dnsCache struct {
	mu      sync.Mutex
	entries map[string]dnsCacheEntry
	max     int
}

func newDNSCache(max int) *dnsCache {
	if max < 1 { max = 1 }
	return &dnsCache{entries: make(map[string]dnsCacheEntry), max: max}
}

func dnsCacheKey(query []byte) string {
	key := append([]byte(nil), query...)
	if len(key) >= 2 { key[0], key[1] = 0, 0 }
	return string(key)
}

func (c *dnsCache) get(query []byte) ([]byte, bool) {
	key := dnsCacheKey(query)
	c.mu.Lock()
	defer c.mu.Unlock()
	item, ok := c.entries[key]
	if !ok { return nil, false }
	if time.Now().After(item.expires) {
		delete(c.entries, key)
		return nil, false
	}
	response := append([]byte(nil), item.response...)
	if len(response) >= 2 { response[0], response[1] = query[0], query[1] }
	return response, true
}

func (c *dnsCache) put(query, response []byte) {
	ttl, ok := minimumTTL(response)
	if !ok || ttl <= 0 { return }
	if ttl > time.Hour { ttl = time.Hour }
	key := dnsCacheKey(query)
	copyResponse := append([]byte(nil), response...)
	if len(copyResponse) >= 2 { copyResponse[0], copyResponse[1] = 0, 0 }
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.max {
		var oldestKey string
		var oldest time.Time
		for k, v := range c.entries {
			if oldestKey == "" || v.expires.Before(oldest) { oldestKey, oldest = k, v.expires }
		}
		delete(c.entries, oldestKey)
	}
	c.entries[key] = dnsCacheEntry{response: copyResponse, expires: time.Now().Add(ttl)}
}

// minimumTTL uses answer-section TTLs only. EDNS OPT pseudo-records in the
// additional section carry TTL bits/flags, not cache lifetime.
func minimumTTL(message []byte) (time.Duration, bool) {
	if len(message) < 12 { return 0, false }
	answers := int(binary.BigEndian.Uint16(message[6:8]))
	if answers == 0 || answers > 512 { return 0, false }
	offset := 12
	questions := int(binary.BigEndian.Uint16(message[4:6]))
	for i := 0; i < questions; i++ {
		next, err := skipDNSName(message, offset)
		if err != nil || next+4 > len(message) { return 0, false }
		offset = next+4
	}
	var min uint32
	for i := 0; i < answers; i++ {
		next, err := skipDNSName(message, offset)
		if err != nil || next+10 > len(message) { return 0, false }
		ttl := binary.BigEndian.Uint32(message[next+4:next+8])
		rdlength := int(binary.BigEndian.Uint16(message[next+8:next+10]))
		offset = next+10+rdlength
		if offset > len(message) { return 0, false }
		if min == 0 || ttl < min { min = ttl }
	}
	return time.Duration(min) * time.Second, min > 0
}

func skipDNSName(message []byte, offset int) (int, error) {
	_, next, err := readDNSName(message, offset)
	return next, err
}
