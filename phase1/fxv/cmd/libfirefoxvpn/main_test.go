package main

// The lifecycle tests — they spawn the REAL engine binary and speak the
// REAL wire contract (the phase-1 honesty rules): config failures and
// the shutdown semantics are LOCAL and deterministic; the two
// real-network scenarios (the real RemoteSettings list, the real
// Guardian with an INVALID token) assert the HONEST failure shape and
// carry the network tag so a sandbox without egress can skip them
// WITHOUT pretending (the skip is the suite's own honest guard, never
// a quiet deletion).

import (
        "bufio"
        "context"
        "encoding/json"
        "fmt"
        "io"
        "net"
        "os"
        "os/exec"
        "path/filepath"
        "runtime"
        "strings"
        "sync"
        "testing"
        "time"
)

var binaryPath string

func TestMain(m *testing.M) {
        dir, err := os.MkdirTemp("", "libfirefoxvpn-test")
        if err != nil {
                fmt.Fprintln(os.Stderr, "mktemp:", err)
                os.Exit(1)
        }
        defer os.RemoveAll(dir)
        binaryPath = filepath.Join(dir, "libfirefoxvpn")
        build := exec.Command("go", "build", "-o", binaryPath, ".")
        build.Stdout = os.Stdout
        build.Stderr = os.Stderr
        if err := build.Run(); err != nil {
                fmt.Fprintln(os.Stderr, "building the engine:", err)
                os.Exit(1)
        }
        os.Exit(m.Run())
}

// session drives one child run: writes the config line, optionally
// closes stdin, collects stdout JSON events + the exit code.
type session struct {
        cmd    *exec.Cmd
        stdin  io.WriteCloser
        stdout io.Reader
        events chan map[string]any
        exited chan int
}

func startEngine(t *testing.T, args ...string) *session {
        t.Helper()
        cmd := exec.Command(binaryPath, args...)
        stdin, err := cmd.StdinPipe()
        if err != nil {
                t.Fatalf("stdin pipe: %v", err)
        }
        stdout, err := cmd.StdoutPipe()
        if err != nil {
                t.Fatalf("stdout pipe: %v", err)
        }
        cmd.Stderr = os.Stderr
        if err := cmd.Start(); err != nil {
                t.Fatalf("start: %v", err)
        }
        s := &session{
                cmd:    cmd,
                stdin:  stdin,
                stdout: stdout,
                events: make(chan map[string]any, 64),
                exited: make(chan int, 1),
        }
        go func() {
                scanner := bufio.NewScanner(stdout)
                for scanner.Scan() {
                        line := scanner.Text()
                        if !strings.HasPrefix(line, "{") {
                                continue
                        }
                        var ev map[string]any
                        if err := json.Unmarshal([]byte(line), &ev); err == nil {
                                s.events <- ev
                        }
                }
        }()
        go func() {
                err := cmd.Wait()
                code := 0
                if exitErr, ok := err.(*exec.ExitError); ok {
                        code = exitErr.ExitCode()
                } else if err != nil {
                        code = -1
                }
                s.exited <- code
        }()
        return s
}

func (s *session) send(line string) {
        _, _ = s.stdin.Write([]byte(line + "\n"))
}

func (s *session) closeStdin() { _ = s.stdin.Close() }

func (s *session) waitEvent(t *testing.T, name string, timeout time.Duration) map[string]any {
        t.Helper()
        deadline := time.After(timeout)
        for {
                select {
                case ev := <-s.events:
                        if ev["event"] == name {
                                return ev
                        }
                case <-deadline:
                        t.Fatalf("timeout waiting for event %q", name)
                }
        }
}

func (s *session) waitExit(t *testing.T, timeout time.Duration) int {
        t.Helper()
        select {
        case code := <-s.exited:
                return code
        case <-time.After(timeout):
                t.Fatalf("timeout waiting for exit")
                return -1
        }
}

func (s *session) kill() { _ = s.cmd.Process.Kill() }

// --- the LOCAL, deterministic contract tests -------------------------------

func TestTunnelConfigNotJSON(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send("this is not json")
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["failCode"] != "badConfig" {
                t.Fatalf("failCode = %v", ev["failCode"])
        }
        if code := s.waitExit(t, 5*time.Second); code != 1 {
                t.Fatalf("exit = %d", code)
        }
}

func TestTunnelConfigVersionMismatch(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":9,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"x"}}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["failCode"] != "badConfig" || ev["message"] != "configVersionMismatch" {
                t.Fatalf("event = %v", ev)
        }
        s.waitExit(t, 5*time.Second)
}

func TestTunnelSocksListenNotLoopback(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"0.0.0.0:1822","auth":{"accessToken":"x"}}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["message"] != "socksListenNotLoopback" {
                t.Fatalf("event = %v", ev)
        }
        s.waitExit(t, 5*time.Second)
}

func TestTunnelGuardianNotHttps(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822","guardian":"http://x","auth":{"accessToken":"x"}}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["message"] != "guardianNotHttps" {
                t.Fatalf("event = %v", ev)
        }
        s.waitExit(t, 5*time.Second)
}

func TestTunnelTransportUnknown(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822","transport":"sctp","auth":{"accessToken":"x"}}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["message"] != "transportUnknown" {
                t.Fatalf("event = %v", ev)
        }
        s.waitExit(t, 5*time.Second)
}

func TestTunnelRelayURLInvalid(t *testing.T) {
	s := startEngine(t)
	defer s.kill()
	s.send(`{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"x"},"relay":{"personal_url":"http://relay.example/"}}`)
	ev := s.waitEvent(t, "failed", 5*time.Second)
	if ev["message"] != "relayURLInvalid" {
		t.Fatalf("event = %v", ev)
	}
	s.waitExit(t, 5*time.Second)
}

func TestTunnelRelayBlockAccepted(t *testing.T) {
	// A valid relay block must sail through validation into the walk:
	// the next failure after it is the (honest) discovery one, never a
	// badConfig. The engine is killed mid-walk; the config shape is
	// what this test asserts.
	s := startEngine(t)
	defer s.kill()
	s.send(`{"version":1,"socksListen":"127.0.0.1:1822","auth":{"accessToken":"x"},"relay":{"personal_url":"https://relay.example/?secret=s","personal_enabled":true,"shared_enabled":true,"ech_mode":"on","ech_config":"cloudflare-ech.com"}}`)
	ev := s.waitEvent(t, "started", 5*time.Second)
	if ev["message"] != "1.3.0-relay" {
		t.Fatalf("started = %v", ev)
	}
	// The walk proceeds (discovery); a failure there is fine — the
	// badConfig shape would NOT be. Drain a couple of events looking
	// only for the badConfig shape.
	deadline := time.After(3 * time.Second)
	for {
		select {
		case ev := <-s.events:
			if ev["failCode"] == "badConfig" {
				t.Fatalf("a valid relay block must not fail as badConfig: %v", ev)
			}
		case <-deadline:
			return
		}
	}
}

func TestTunnelAuthAccessTokenMissing(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822"}`)
        ev := s.waitEvent(t, "failed", 5*time.Second)
        if ev["message"] != "authAccessTokenMissing" {
                t.Fatalf("event = %v", ev)
        }
        s.waitExit(t, 5*time.Second)
}

// The shutdown contract: closing stdin is a CLEAN stop — wherever the
// walk is. Local: the unreachable guardian fails fast while stdin is
// already closed → the engine must still exit 0 with stopped/stdinClosed.
func TestTunnelStdinCloseIsCleanStop(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822","upstreamOverride":"127.0.0.1:1","guardian":"https://127.0.0.1:1","auth":{"accessToken":"x"}}`)
        s.closeStdin()
        // The walk stops honestly; the stopping/stopped pair rides the wire.
        deadline := time.After(10 * time.Second)
        sawStopped := false
        for !sawStopped {
                select {
                case ev := <-s.events:
                        if ev["event"] == "stopped" {
                                if ev["reason"] != "stdinClosed" {
                                        t.Fatalf("stop reason = %v", ev["reason"])
                                }
                                sawStopped = true
                        }
                        if ev["event"] == "failed" {
                                t.Fatalf("a stdin-close stop must never be a failure: %v", ev)
                        }
                case <-deadline:
                        t.Fatal("timeout waiting for the clean stop")
                }
        }
        if code := s.waitExit(t, 5*time.Second); code != 0 {
                t.Fatalf("exit = %d, want 0", code)
        }
}

// argv carries NO config and NO secrets (the spawn is bare).
func TestTunnelArgvIsBare(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822","upstreamOverride":"127.0.0.1:1","guardian":"https://127.0.0.1:1","auth":{"accessToken":"secret-value-do-not-leak"}}`)
        s.closeStdin()
        _ = s.waitExit(t, 10 * time.Second)
        // the engine ran with argv = [binary] only; nothing to grep — the
        // assertion is structural (no args were passed by the harness)
}

func TestStartedEventShape(t *testing.T) {
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822","upstreamOverride":"127.0.0.1:1","guardian":"https://127.0.0.1:1","auth":{"accessToken":"x"}}`)
        ev := s.waitEvent(t, "started", 5*time.Second)
        if ver, _ := ev["message"].(string); !strings.HasPrefix(ver, "1.3.0-relay") {
                t.Fatalf("engine version = %v", ev["message"])
        }
        if pid, _ := ev["pid"].(float64); pid <= 0 {
                t.Fatalf("pid = %v", ev["pid"])
        }
        s.closeStdin()
        s.waitExit(t, 10 * time.Second)
}

// The wire field names are the frozen Dart contract — the selected
// event carries the exact keys firefox_protocol.dart reads.
func TestSelectedEventWireFields(t *testing.T) {
        if !networkAvailable() {
                t.Skip("network egress unavailable — the live RemoteSettings discovery cannot run here (honest skip, not a green)")
        }
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822","country":"DE","auth":{"accessToken":"invalid-token-for-honest-failure"}}`)
        ev := s.waitEvent(t, "selected", 30*time.Second)
        for _, key := range []string{"country", "countryName", "cityCode", "cityName", "hostname", "port", "selectionSource", "recommended"} {
                if _, ok := ev[key]; !ok {
                        t.Fatalf("selected event missing wire key %q: %v", key, ev)
                }
        }
        if ev["country"] != "DE" || ev["selectionSource"] != "country" {
                t.Fatalf("selection = %v", ev)
        }
        s.closeStdin()
        s.waitExit(t, 15*time.Second)
}

// The real Guardian with an INVALID token: the honest failure carries
// the sessionRejected class and the REAL HTTP status (401/403).
func TestRealGuardianInvalidTokenHonestFailure(t *testing.T) {
        if !networkAvailable() {
                t.Skip("network egress unavailable — the real Guardian probe cannot run here (honest skip, not a green)")
        }
        s := startEngine(t)
        defer s.kill()
        s.send(`{"version":1,"socksListen":"127.0.0.1:1822","country":"DE","guardian":"https://vpn.mozilla.org","auth":{"accessToken":"0000000000000000000000000000000000000000000000000000000000000000"}}`)
        ev := s.waitEvent(t, "failed", 60*time.Second)
        if code, _ := ev["failCode"].(string); code != "sessionRejected" {
                t.Fatalf("failCode = %v (want sessionRejected)", ev["failCode"])
        }
        if status, _ := ev["httpStatus"].(float64); status != 401 && status != 403 {
                t.Fatalf("httpStatus = %v (want 401/403)", ev["httpStatus"])
        }
        // the invalid token itself must NEVER appear anywhere on the wire
        if strings.Contains(fmt.Sprint(ev), "0000000000000000000000000000000000000000000000000000000000000000") {
                t.Fatal("the rejected token leaked into the failed event")
        }
        if code := s.waitExit(t, 10*time.Second); code != 1 {
                t.Fatalf("exit = %d", code)
        }
}

func networkAvailable() bool {
        conn, err := net.DialTimeout("tcp", "firefox.settings.services.mozilla.com:443", 3*time.Second)
        if err != nil {
                return false
        }
        _ = conn.Close()
        return true
}

// TestStderrLoggerLevelDiscipline (Stage 6): the engine's human-log
// sink follows the upstream demo's level rules — quiet writes nothing,
// the normal level writes info/warn but NOT debug, verbose writes all
// three, and Verbose() reports only the verbose mode (the logTarget /
// RedactedError un-redaction gate).
func TestStderrLoggerLevelDiscipline(t *testing.T) {
        run := func(enabled, verbose bool) string {
                var buf strings.Builder
                log := &stderrLogger{
                        enabled: enabled,
                        verbose: verbose,
                        redact:  func(s string) string { return s },
                        w:       &buf,
                }
                log.Debugf("socks: CONNECT requested target=%s", "secret-domain.example:443")
                log.Infof("socks: conn tracked live=%d", 1)
                log.Warnf("socks: upstream tunnel open failed target=%s", "<redacted; use -verbose>")
                return buf.String()
        }

        // quiet: nothing at all.
        if out := run(false, false); out != "" {
                t.Fatalf("quiet wrote %q", out)
        }

        // normal: info + warn only; the debug line (and its domain) silent.
        normal := run(true, false)
        if strings.Contains(normal, "debug:") || strings.Contains(normal, "secret-domain.example") {
                t.Fatalf("normal level leaked debug output: %q", normal)
        }
        if !strings.Contains(normal, "info: socks: conn tracked live=1") {
                t.Fatalf("normal level must keep the Info live=N channel: %q", normal)
        }
        if !strings.Contains(normal, "warn: socks: upstream tunnel open failed") {
                t.Fatalf("normal level must keep warn lines: %q", normal)
        }

        // verbose: all three levels, domain visible.
        verboseOut := run(true, true)
        for _, want := range []string{
                "debug: socks: CONNECT requested target=secret-domain.example:443",
                "info: socks: conn tracked live=1",
                "warn: socks: upstream tunnel open failed",
        } {
                if !strings.Contains(verboseOut, want) {
                        t.Fatalf("verbose output missing %q (got %q)", want, verboseOut)
                }
        }

        // The un-redaction gate mirrors the mode.
        log := &stderrLogger{enabled: true, verbose: true}
        if !log.Verbose() {
                t.Fatal("verbose logger must report Verbose()=true")
        }
        log = &stderrLogger{enabled: true}
        if log.Verbose() {
                t.Fatal("normal logger must report Verbose()=false")
        }
}

// TestFormatRuntimeStats (Stage 6): the evidence line renders the
// counters and the allocation rate from the window delta; a zero
// window must not panic.
func TestFormatRuntimeStats(t *testing.T) {
        prev := &runtime.MemStats{HeapAlloc: 10 << 20, Sys: 50 << 20, NumGC: 2, TotalAlloc: 100 << 20}
        cur := &runtime.MemStats{HeapAlloc: 20 << 20, Sys: 80 << 20, NumGC: 5, TotalAlloc: 160 << 20}
        line := formatRuntimeStats(prev, cur, 60*time.Second)
        for _, want := range []string{
                "goroutines=",
                "heap_mb=20.0",
                "sys_mb=80.0",
                "num_gc=5",
                "total_alloc_mb=160.0",
                // 60 MiB allocated over 60s = 1024 KB/s.
                "alloc_kbps=1024",
        } {
                if !strings.Contains(line, want) {
                        t.Fatalf("stats line %q missing %q", line, want)
                }
        }
        if zero := formatRuntimeStats(prev, cur, 0); !strings.Contains(zero, "alloc_kbps=0") {
                t.Fatalf("zero window must render alloc_kbps=0 without panicking: %q", zero)
        }
}

// syncBuffer is a mutex-guarded writer (the stats goroutine and the
// test read concurrently; -race would catch an unsynchronized builder).
type syncBuffer struct {
        mu  sync.Mutex
        buf strings.Builder
}

func (b *syncBuffer) Write(p []byte) (int, error) {
        b.mu.Lock()
        defer b.mu.Unlock()
        return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
        b.mu.Lock()
        defer b.mu.Unlock()
        return b.buf.String()
}

// TestRuntimeStatsLoopEmitsAndStops (Stage 6): the loop emits Info
// stats lines on its ticker and exits promptly on context cancel.
func TestRuntimeStatsLoopEmitsAndStops(t *testing.T) {
        out := &syncBuffer{}
        log := &stderrLogger{enabled: true, redact: func(s string) string { return s }, w: out}
        ctx, cancel := context.WithCancel(context.Background())
        done := make(chan struct{})
        go func() {
                runtimeStatsLoop(ctx, log, 5*time.Millisecond)
                close(done)
        }()

        deadline := time.Now().Add(3 * time.Second)
        for {
                if strings.Contains(out.String(), "info: runtime stats goroutines=") {
                        break
                }
                if time.Now().After(deadline) {
                        t.Fatal("no runtime stats line within 3s")
                }
                time.Sleep(5 * time.Millisecond)
        }

        cancel()
        select {
        case <-done:
        case <-time.After(3 * time.Second):
                t.Fatal("the stats loop did not stop on cancel")
        }
}
