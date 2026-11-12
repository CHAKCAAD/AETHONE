package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"aethone/fxv/internal/dnsresolver"
)

const maxDNSConfigLine = 64 * 1024

// readOptionalDNSConfig reads {"dns":{...}}. EOF/empty stdin means the
// historical Android system resolver, preserving older process callers.
func readOptionalDNSConfig(r io.Reader) (dnsresolver.Config, error) {
	reader := bufio.NewReader(io.LimitReader(r, maxDNSConfigLine+1))
	return readOptionalDNSConfigBuffered(reader)
}

// readOptionalDNSConfigBuffered keeps the caller's buffered reader alive.
// Long-running roles such as --webview-proxy must continue observing EOF
// after the one configuration line, without losing bytes read ahead here.
func readOptionalDNSConfigBuffered(reader *bufio.Reader) (dnsresolver.Config, error) {
	line, err := reader.ReadString('\n')
	if err != nil && err != io.EOF {
		return dnsresolver.Config{}, err
	}
	if len(line) > maxDNSConfigLine {
		return dnsresolver.Config{}, fmt.Errorf("DNS config line too large")
	}
	line = strings.TrimSpace(line)
	if line == "" {
		return dnsresolver.DefaultConfig(), nil
	}
	var envelope struct {
		DNS dnsresolver.Config `json:"dns"`
	}
	if err := json.Unmarshal([]byte(line), &envelope); err != nil {
		return dnsresolver.Config{}, fmt.Errorf("invalid JSON")
	}
	return envelope.DNS.Validate()
}
