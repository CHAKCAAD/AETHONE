package main

// The --usage role tests (contract 1.7.0): the quota-header parse with
// arman's ProxyUsage semantics (unlimited flag / the numeric trio), the
// HEAD→GET fallback, the 429-carries-usage rule, and the role's event
// shape through the injected seams (no TLS, no network beyond the test
// server).

import (
        "bufio"
        "bytes"
        "encoding/json"
        "io"
        "net/http"
        "net/http/httptest"
        "strings"
        "testing"
)

// readUsageTestLine builds the stdin seam from a fixed config string
// (production reads os.Stdin through readLineBounded).
func readUsageTestLine(raw string) func() ([]byte, error) {
        return func() ([]byte, error) {
                br := bufio.NewReader(strings.NewReader(raw))
                line, err := br.ReadString('\n')
                if err != nil && err != io.EOF {
                        return nil, err
                }
                line = strings.TrimRight(line, "\r\n")
                if line == "" {
                        return nil, io.EOF
                }
                return []byte(line), nil
        }
}

func TestUsageFromHeadersUnlimitedWins(t *testing.T) {
        h := http.Header{}
        h.Set("X-Quota-Unlimited", "true")
        h.Set("X-Quota-Limit", "")
        h.Set("X-Quota-Remaining", "")
        usage := usageFromHeaders(h)
        if usage == nil || !usage.QuotaUnlimited {
                t.Fatalf("the unlimited flag must win alone: %+v", usage)
        }
}

func TestUsageFromHeadersTrio(t *testing.T) {
        h := http.Header{}
        h.Set("X-Quota-Limit", "5368709120")
        h.Set("X-Quota-Remaining", "1073741824")
        h.Set("X-Quota-Reset", "1767225600")
        usage := usageFromHeaders(h)
        if usage == nil {
                t.Fatal("the numeric trio must parse")
        }
        if usage.QuotaMax != "5368709120" || usage.QuotaLeft != "1073741824" || usage.QuotaReset != "1767225600" {
                t.Fatalf("wrong trio: %+v", usage)
        }
        if usage.QuotaUnlimited {
                t.Fatal("a metered trio must not be unlimited")
        }
}

func TestUsageFromHeadersRejectsPartial(t *testing.T) {
        for name, set := range map[string]func(http.Header){
                "missing reset":     func(h http.Header) { h.Set("X-Quota-Limit", "1"); h.Set("X-Quota-Remaining", "1") },
                "missing remaining": func(h http.Header) { h.Set("X-Quota-Limit", "1"); h.Set("X-Quota-Reset", "1") },
                "non numeric limit": func(h http.Header) { h.Set("X-Quota-Limit", "unlimited"); h.Set("X-Quota-Remaining", "1"); h.Set("X-Quota-Reset", "1") },
                "empty":             func(http.Header) {},
        } {
                h := http.Header{}
                set(h)
                if usage := usageFromHeaders(h); usage != nil {
                        t.Fatalf("%s: partial garbage must be no usage, got %+v", name, usage)
                }
        }
}

func TestUsageRoleHappyPathThroughTestServer(t *testing.T) {
        var sawMethod []string
        server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                sawMethod = append(sawMethod, r.Method)
                if r.URL.Path != usageEndpointPath {
                        t.Errorf("unexpected path %s", r.URL.Path)
                }
                if got := r.Header.Get("Authorization"); got != "Bearer test-access-token" {
                        t.Errorf("missing bearer")
                }
                w.Header().Set("X-Quota-Limit", "5368709120")
                w.Header().Set("X-Quota-Remaining", "4294967296")
                w.Header().Set("X-Quota-Reset", "2026-12-01T00:00:00Z")
                w.WriteHeader(http.StatusOK)
        }))
        defer server.Close()

        cfgLine := `{"version":1,"auth":{"accessToken":"test-access-token"},"guardian":"` + server.URL + `"}`
        var out bytes.Buffer
        code := runUsageWith(readUsageTestLine(cfgLine), &out, func(string) *http.Client {
                return server.Client()
        })
        if code != 0 {
                t.Fatalf("usage role exit %d, want 0; out=%s", code, out.String())
        }
        var ev map[string]any
        if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &ev); err != nil {
                t.Fatalf("usage event not JSON: %v (%s)", err, out.String())
        }
        if ev["event"] != "usage" {
                t.Fatalf("wrong event %v", ev["event"])
        }
        if ev["quotaMax"] != "5368709120" || ev["quotaLeft"] != "4294967296" {
                t.Fatalf("wrong quota fields: %v", ev)
        }
        if ev["quotaReset"] != "2026-12-01T00:00:00Z" {
                t.Fatalf("wrong reset: %v", ev["quotaReset"])
        }
        if _, has := ev["quotaUnlimited"]; has {
                t.Fatal("a metered usage must not carry quotaUnlimited")
        }
        if len(sawMethod) == 0 || sawMethod[0] != http.MethodHead {
                t.Fatalf("HEAD first expected, saw %v", sawMethod)
        }
}

func TestUsageRoleUnlimitedAccount(t *testing.T) {
        server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("X-Quota-Unlimited", "true")
                w.WriteHeader(http.StatusOK)
        }))
        defer server.Close()

        cfgLine := `{"version":1,"auth":{"accessToken":"tok"},"guardian":"` + server.URL + `"}`
        var out bytes.Buffer
        code := runUsageWith(readUsageTestLine(cfgLine), &out, func(string) *http.Client {
                return server.Client()
        })
        if code != 0 {
                t.Fatalf("usage role exit %d, want 0; out=%s", code, out.String())
        }
        var ev map[string]any
        if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &ev); err != nil {
                t.Fatalf("usage event not JSON: %v", err)
        }
        if ev["quotaUnlimited"] != true {
                t.Fatalf("unlimited account must carry quotaUnlimited=true: %v", ev)
        }
}

func TestUsageRoleHeadRefusedFallsBackToGet(t *testing.T) {
        var methods []string
        server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                methods = append(methods, r.Method)
                if r.Method == http.MethodHead {
                        w.WriteHeader(http.StatusMethodNotAllowed)
                        return
                }
                w.Header().Set("X-Quota-Limit", "10")
                w.Header().Set("X-Quota-Remaining", "5")
                w.Header().Set("X-Quota-Reset", "99")
                w.WriteHeader(http.StatusOK)
        }))
        defer server.Close()

        cfgLine := `{"version":1,"auth":{"accessToken":"tok"},"guardian":"` + server.URL + `"}`
        var out bytes.Buffer
        code := runUsageWith(readUsageTestLine(cfgLine), &out, func(string) *http.Client {
                return server.Client()
        })
        if code != 0 {
                t.Fatalf("GET fallback must succeed, exit %d; out=%s", code, out.String())
        }
        if len(methods) != 2 || methods[0] != "HEAD" || methods[1] != "GET" {
                t.Fatalf("expected HEAD then GET, saw %v", methods)
        }
}

func TestUsageRoleSpentQuotaCarriesUsage(t *testing.T) {
        server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("X-Quota-Limit", "1000")
                w.Header().Set("X-Quota-Remaining", "0")
                w.Header().Set("X-Quota-Reset", "1767225600")
                w.WriteHeader(http.StatusTooManyRequests)
        }))
        defer server.Close()

        cfgLine := `{"version":1,"auth":{"accessToken":"tok"},"guardian":"` + server.URL + `"}`
        var out bytes.Buffer
        code := runUsageWith(readUsageTestLine(cfgLine), &out, func(string) *http.Client {
                return server.Client()
        })
        if code != 0 {
                t.Fatalf("a 429 with usage headers is a SUCCESS (arman's rule), exit %d; out=%s", code, out.String())
        }
        var ev map[string]any
        if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &ev); err != nil {
                t.Fatalf("usage event not JSON: %v", err)
        }
        if ev["quotaLeft"] != "0" {
                t.Fatalf("spent quota must report remaining=0: %v", ev)
        }
}

func TestUsageRoleRejectedTokenClassified(t *testing.T) {
        server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.WriteHeader(http.StatusUnauthorized)
        }))
        defer server.Close()

        cfgLine := `{"version":1,"auth":{"accessToken":"tok"},"guardian":"` + server.URL + `"}`
        var out bytes.Buffer
        code := runUsageWith(readUsageTestLine(cfgLine), &out, func(string) *http.Client {
                return server.Client()
        })
        if code == 0 {
                t.Fatal("a rejected token must fail the role")
        }
        var ev map[string]any
        if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &ev); err != nil {
                t.Fatalf("usageFailed event not JSON: %v", err)
        }
        if ev["event"] != "usageFailed" || ev["failCode"] != "sessionRejected" {
                t.Fatalf("wrong classification: %v", ev)
        }
        if ev["httpStatus"] != float64(401) {
                t.Fatalf("httpStatus must carry through: %v", ev)
        }
}

func TestUsageRoleBadConfigFailsClosed(t *testing.T) {
        var out bytes.Buffer
        code := runUsageWith(readUsageTestLine(`{"version":1}`), &out, func(string) *http.Client {
                t.Fatal("no request may be made without an access token")
                return &http.Client{}
        })
        if code == 0 {
                t.Fatal("missing access token must fail closed")
        }
        if !strings.Contains(out.String(), "usageFailed") {
                t.Fatalf("expected usageFailed, got %s", out.String())
        }
        if strings.Contains(out.String(), "accessToken") {
                t.Fatal("no token material may appear in events")
        }
}
