package dnsresolver

import (
        "strings"
        "testing"
)

// 2.0.0 — the HelloSplit seam (the reference's network.hello_split
// choices, riding the dns config line).
func TestHelloSplitValidation(t *testing.T) {
        for _, mode := range []string{"", "off", "sni", "first-byte", "record", "SNI", " Record "} {
                cfg, err := Config{Mode: ModeDoH, Provider: ProviderAuto, HelloSplit: mode}.Validate()
                if err != nil {
                        t.Fatalf("mode %q must validate: %v", mode, err)
                }
                want := normalizeHelloSplitForTest(mode)
                if cfg.HelloSplit != want {
                        t.Fatalf("mode %q normalized to %q, want %q", mode, cfg.HelloSplit, want)
                }
        }
        for _, mode := range []string{"nonsense", "segments", "split"} {
                bad := Config{Mode: ModeDoH, Provider: ProviderAuto, HelloSplit: mode}
                if _, err := bad.Validate(); err == nil {
                        t.Fatalf("mode %q must be rejected", mode)
                }
        }
        if !ValidHelloSplit("") || !ValidHelloSplit(HelloSplitRecord) || ValidHelloSplit("nope") {
                t.Fatal("ValidHelloSplit disagrees with the choices")
        }
}

// The empty-mode default keeps the caller's hello split pick (the early
// return must not drop it).
func TestHelloSplitSurvivesDefaultConfig(t *testing.T) {
        cfg, err := Config{HelloSplit: HelloSplitSNI}.Validate()
        if err != nil {
                t.Fatal(err)
        }
        if cfg.HelloSplit != HelloSplitSNI {
                t.Fatalf("the default path dropped the pick: %q", cfg.HelloSplit)
        }
        if cfg.Mode != ModeDoH || cfg.Provider != ProviderAuto {
                t.Fatalf("the default posture changed: %+v", cfg)
        }
}

func normalizeHelloSplitForTest(raw string) string {
        return strings.ToLower(strings.TrimSpace(raw))
}
