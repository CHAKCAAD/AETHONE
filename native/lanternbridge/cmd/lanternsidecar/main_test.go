package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIsLoopbackAddress(t *testing.T) {
	tests := []struct {
		address string
		want    bool
	}{
		{"127.0.0.1:1831", true},
		{"127.0.0.1:1832", true},
		{"[::1]:1831", true},
		{"0.0.0.0:1831", false},
		{"192.168.1.2:1831", false},
		{"localhost:1831", false},
		{"127.0.0.1", false},
		{"", false},
	}
	for _, test := range tests {
		t.Run(test.address, func(t *testing.T) {
			if got := isLoopbackAddress(test.address); got != test.want {
				t.Fatalf("isLoopbackAddress(%q) = %v, want %v", test.address, got, test.want)
			}
		})
	}
}

func TestReadSocksAuth(t *testing.T) {
	dir := t.TempDir()
	good := filepath.Join(dir, "good")
	if err := os.WriteFile(good, []byte(strings.Repeat("ab", 32)+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	user, pass, err := readSocksAuth(good)
	if err != nil || user != "aethone" || pass != strings.Repeat("ab", 32) {
		t.Fatalf("good secret: %q %q %v", user, pass, err)
	}
	for name, body := range map[string]string{"short": "abcd", "nonhex": strings.Repeat("zz", 32), "empty": ""} {
		p := filepath.Join(dir, name)
		_ = os.WriteFile(p, []byte(body), 0600)
		if _, _, err := readSocksAuth(p); err == nil {
			t.Fatalf("%s secret accepted", name)
		}
	}
	if _, _, err := readSocksAuth(filepath.Join(dir, "missing")); err == nil {
		t.Fatal("missing secret file accepted")
	}
}

