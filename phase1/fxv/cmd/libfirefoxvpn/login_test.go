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

func TestLoginPasswordModeRefused(t *testing.T) {
        s := startEngine(t, "--login")
        defer s.kill()
        s.send(`{"version":1,"mode":"password","sessionToken":"` + hex64Token() + `"}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["failCode"] != "loginModeUnsupported" {
                t.Fatalf("event = %v", ev)
        }
        if code := s.waitExit(t, 5*time.Second); code != 1 {
                t.Fatalf("exit = %d", code)
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
        if ver, _ := ev["message"].(string); !strings.HasPrefix(ver, "1.2.0-phaseb") {
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
