package main

// The --login role lifecycle tests — the REAL binary, the REAL wire.
// LOCAL: the token-shape/mode rejections and the clean cancel.
// NETWORK (tagged, honestly skipped without egress): the real FxA
// endpoint with a FAKE token → the honest terminal failure, no leak.

import (
        "encoding/json"
        "strings"
        "testing"
        "time"
)

func hex64Token() string { return strings.Repeat("ab", 32) }

func TestLoginSessionTokenInvalid(t *testing.T) {
        s := startEngine(t, "--login")
        defer s.kill()
        s.send(`{"version":1,"mode":"webchannel","sessionToken":"tooshort"}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        // The login role's OWN code (docs/FIREFOX_VPN_LOGIN.md §3), never
        // the tunnel role's badConfig umbrella.
        if ev["failCode"] != "sessionTokenInvalid" {
                t.Fatalf("event = %v", ev)
        }
        if code := s.waitExit(t, 5*time.Second); code != 1 {
                t.Fatalf("exit = %d", code)
        }
}

func TestLoginPasswordModeConfigRejections(t *testing.T) {
        // 1.8.0 — the password mode is LIVE; its field rejections keep
        // their OWN codes (never the badConfig umbrella) exactly like
        // the token-shape family.
        s := startEngine(t, "--login")
        defer s.kill()
        s.send(`{"version":1,"mode":"password","email":"no-at.example","password":"hunter2"}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["failCode"] != "invalidEmail" {
                t.Fatalf("event = %v", ev)
        }
        if code := s.waitExit(t, 5*time.Second); code != 1 {
                t.Fatalf("exit = %d", code)
        }

        s2 := startEngine(t, "--login")
        defer s2.kill()
        s2.send(`{"version":1,"mode":"password","email":"a@b.example","password":""}`)
        ev2 := s2.waitEvent(t, "failed", 5*time.Second)
        if ev2["failCode"] != "badConfig" {
                t.Fatalf("event = %v", ev2)
        }
        if code := s2.waitExit(t, 5*time.Second); code != 1 {
                t.Fatalf("exit = %d", code)
        }
}

func TestLoginPasswordModeStartedShape(t *testing.T) {
        s := startEngine(t, "--login")
        defer s.kill()
        s.send(`{"version":1,"mode":"password","email":"shape@example.com","password":"shape-test-1","verifyTimeoutMs":15000,"retryDelayMs":500}`)
        ev := s.waitEvent(t, "loginStarted", 5*time.Second)
        if ev["loginMode"] != "password" {
                t.Fatalf("loginMode = %v", ev["loginMode"])
        }
        if ver, _ := ev["message"].(string); !strings.HasPrefix(ver, "2.0.0") {
                t.Fatalf("version = %v", ev["message"])
        }
        s.closeStdin()
        // The FxA login call may be in flight (network) — the CLEAN
        // CANCEL wins either way: the pump's EOF aborts the ctx and the
        // walk answers stopped/cancelled. Without network the call
        // fails on its own; both terminate quickly.
        sawTerminal := false
        deadline := time.After(30 * time.Second)
        for !sawTerminal {
                select {
                case e := <-s.events:
                        switch e["event"] {
                        case "stopped":
                                sawTerminal = true
                        case "failed":
                                // A networkless sandbox answers this way —
                                // the shape test only pins loginStarted.
                                sawTerminal = true
                        }
                case <-deadline:
                        t.Fatal("timeout waiting for the password walk to end")
                }
        }
}

// The password mode's clean cancel: stdin EOF right after loginStarted.
// With network the cancel wins the race (stopped/cancelled, exit 0); a
// networkless sandbox lets the in-flight login call fail first (failed,
// exit 1) — both are honest terminals. NEVER acceptable: the password
// in any event, or a hang.
func TestLoginPasswordStdinCloseIsCleanCancel(t *testing.T) {
        s := startEngine(t, "--login")
        defer s.kill()
        s.send(`{"version":1,"mode":"password","email":"cancel@example.com","password":"cancel-secret-pw","verifyTimeoutMs":30000,"retryDelayMs":1000}`)
        s.waitEvent(t, "loginStarted", 5*time.Second)
        s.closeStdin()
        sawStopped, sawFailed := false, false
        deadline := time.After(45 * time.Second)
        for !sawStopped && !sawFailed {
                select {
                case ev := <-s.events:
                        raw, _ := jsonMarshal(ev)
                        if strings.Contains(raw, "cancel-secret-pw") {
                                t.Fatalf("the password leaked into an event: %s", raw)
                        }
                        switch ev["event"] {
                        case "failed":
                                sawFailed = true
                        case "stopped":
                                if ev["reason"] != "cancelled" {
                                        t.Fatalf("reason = %v", ev["reason"])
                                }
                                sawStopped = true
                        }
                case <-deadline:
                        t.Fatal("timeout waiting for the password walk to end")
                }
        }
        if sawStopped {
                if code := s.waitExit(t, 5*time.Second); code != 0 {
                        t.Fatalf("exit = %d, want 0 after a clean cancel", code)
                }
        } else {
                if code := s.waitExit(t, 5*time.Second); code != 1 {
                        t.Fatalf("exit = %d, want 1 after a login failure", code)
                }
        }
}

func TestLoginStartedEventShape(t *testing.T) {
        s := startEngine(t, "--login")
        defer s.kill()
        s.send(`{"version":1,"mode":"webchannel","sessionToken":"` + hex64Token() + `","verifyTimeoutMs":2000,"retryDelayMs":500}`)
        ev := s.waitEvent(t, "loginStarted", 5*time.Second)
        if ev["loginMode"] != "webchannel" {
                t.Fatalf("loginMode = %v", ev["loginMode"])
        }
        if ver, _ := ev["message"].(string); !strings.HasPrefix(ver, "2.0.0") {
                t.Fatalf("version = %v", ev["message"])
        }
        s.closeStdin()
        s.waitExit(t, 10 * time.Second)
}

// The clean cancel: stdin EOF is NOT a failure — the role aborts even
// an in-flight exchange and exits 0 with stopped/cancelled.
func TestLoginStdinCloseIsCleanCancel(t *testing.T) {
        s := startEngine(t, "--login")
        defer s.kill()
        s.send(`{"version":1,"mode":"webchannel","sessionToken":"` + hex64Token() + `","verifyTimeoutMs":10000,"retryDelayMs":1000}`)
        s.waitEvent(t, "loginStarted", 5*time.Second)
        s.closeStdin()
        sawStopped := false
        deadline := time.After(10 * time.Second)
        for !sawStopped {
                select {
                case ev := <-s.events:
                        if ev["event"] == "failed" {
                                t.Fatalf("a cancel must never be a failure: %v", ev)
                        }
                        if ev["event"] == "stopped" {
                                if ev["reason"] != "cancelled" {
                                        t.Fatalf("reason = %v", ev["reason"])
                                }
                                sawStopped = true
                        }
                case <-deadline:
                        t.Fatal("timeout waiting for the clean cancel")
                }
        }
        if code := s.waitExit(t, 5*time.Second); code != 0 {
                t.Fatalf("exit = %d, want 0", code)
        }
}

// The REAL FxA endpoint with a FAKE token: the honest terminal failure
// (sessionRejected for the definitive errnos; the granular Phase B
// class rides failCode) and NO token leak anywhere on the wire.
func TestLoginRealFxaFakeTokenHonestFailure(t *testing.T) {
        if !networkAvailable() {
                t.Skip("network egress unavailable — the real FxA probe cannot run here (honest skip, not a green)")
        }
        s := startEngine(t, "--login")
        defer s.kill()
        fakeToken := strings.Repeat("cd", 32)
        s.send(`{"version":1,"mode":"webchannel","sessionToken":"` + fakeToken + `","verifyTimeoutMs":30000,"retryDelayMs":1000}`)
        ev := s.waitEvent(t, "failed", 90*time.Second)
        code, _ := ev["failCode"].(string)
        switch code {
        case "sessionRejected", "tokenExchange", "serverRejection", "dnsError", "timeout", "tlsError", "networkUnavailable":
                // the honest family — anything else is a bug
        default:
                t.Fatalf("failCode = %q (unexpected class)", code)
        }
        evJSON, _ := jsonMarshal(ev)
        if strings.Contains(evJSON, fakeToken) {
                t.Fatal("the fake session token leaked into the failure event")
        }
        if exitCode := s.waitExit(t, 10*time.Second); exitCode != 1 {
                t.Fatalf("exit = %d", exitCode)
        }
}

func jsonMarshal(v any) (string, error) {
        raw, err := json.Marshal(v)
        return string(raw), err
}
