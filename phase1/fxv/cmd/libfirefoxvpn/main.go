// Command libfirefoxvpn — the AETHONE Firefox VPN engine (Go child
// process). NEW AETHONE code (Phase 1, rebuilt 2026-11-09 from the
// documented contract; the data-plane pieces are ADAPTED from the
// pinned upstream — see ORIGIN.md).
//
// Roles:
//
//      libfirefoxvpn                 the tunnel role (stdin config line,
//                                    JSON-lines events, SOCKS5 on 1822)
//      libfirefoxvpn --discover      print the live RemoteSettings
//                                    location model as ONE JSON line
//      libfirefoxvpn --login         the FxA WebChannel exchange (Phase 2)
//      libfirefoxvpn --dns-probe     resolve the control-plane domains
//                                    through THIS process (the multi-arch
//                                    DNS evidence role — no secrets)
//      libfirefoxvpn --guardian-probe  the Guardian-only authorization
//                                    walk (guardian-bootstrap Stage 5:
//                                    AcquireInitialPass — no discovery,
//                                    no session, no listener; honors the
//                                    apiProxy routing decision)
//
// Spawn discipline (the Dart host): bare argv, EMPTY environment —
// every secret travels on the stdin pipe only.
package main

import (
        "context"
        "errors"
        "fmt"
        "io"
        "net/url"
        "os"
        "runtime"
        "strings"
        "sync"
        "time"

        vpnclient "firefox-vpn-client"

        "aethone/fxv/internal/discovery"
        "aethone/fxv/internal/engine"
        "aethone/fxv/internal/fferr"
        "aethone/fxv/internal/redact"
        "aethone/fxv/internal/socks"
        "aethone/fxv/internal/upstream"
)

func main() {
        code := run()
        os.Exit(code)
}

func run() int {
        args := os.Args[1:]
        for _, arg := range args {
                switch arg {
                case "--discover":
                        return runDiscover()
                case "--login":
                        return runLogin()
                case "--dns-probe":
                        return runDNSProbe()
                case "--guardian-probe":
                        return runGuardianProbe()
                case "--help", "-h":
                        fmt.Fprintf(os.Stderr, "usage: libfirefoxvpn [--discover|--login|--dns-probe|--guardian-probe]\n")
                        return 0
                default:
                        fmt.Fprintf(os.Stderr, "unknown argument %q (usage: libfirefoxvpn [--discover|--login|--dns-probe|--guardian-probe])\n", arg)
                        return engine.ExitStartup
                }
        }
        return runTunnel()
}

// --------------------------------------------------------------------------
// the tunnel role
// --------------------------------------------------------------------------

func runTunnel() int {
        emit := engine.NewEmitter()
        log := &stderrLogger{redact: func(s string) string { return s }}

        // 1. the config line (the ONLY secret carrier on the way in).
        cfg, err := engine.ReadConfigLine(os.Stdin)
        if err != nil {
                var cfgErr *engine.ConfigError
                if errors.As(err, &cfgErr) {
                        _ = emit.Emit(engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
                                Message: cfgErr.DetailCode(), Code: engine.ExitStartup,
                        })
                } else {
                        _ = emit.Emit(engine.Event{
                                Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
                                Message: "configNotJSON", Code: engine.ExitStartup,
                        })
                }
                return engine.ExitStartup
        }
        cfg, err = cfg.Validate()
        if err != nil {
                var cfgErr *engine.ConfigError
                detail := "badConfig"
                if errors.As(err, &cfgErr) {
                        detail = cfgErr.DetailCode()
                }
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
                        Message: detail, Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }

        quiet := cfg.LogLevel == "quiet"
        log.enabled = !quiet
        log.verbose = cfg.LogLevel == "verbose" // the -verbose flag parity (stdin JSON, not env)

        _ = emit.Emit(engine.Event{
                Name: engine.EvStarted,
                Message: engine.EngineVersion,
                PID:    os.Getpid(),
        })

        // guardian-bootstrap Stage 5: the selective control-plane routing.
        // MUST precede the FIRST control-plane request (discovery below is
        // Remote Settings — it stays DIRECT either way; only the allowlisted
        // Guardian requests would ride the bootstrap leg). Empty apiProxy =
        // no change at all (the pinned default direct uTLS transport).
        if err := installGuardianRouting(cfg, log); err != nil {
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
                        Message: "apiProxyTransport", Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }

        // 2. discovery + selection (unless overridden). stdin close is
        // checked at EVERY stage boundary — the shutdown request is honored
        // wherever the walk happens to be (a clean stop, never a failure).
        ctx, cancel := context.WithCancel(context.Background())
        defer cancel()
        stdinDone := watchStdinClose(ctx, func() {
                cancel()
                _ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "stdinClosed"})
        })
        cleanStopIfRequested := func() (int, bool) {
                select {
                case <-stdinDone:
                        _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "stdinClosed"})
                        return engine.ExitClean, true
                default:
                        return 0, false
                }
        }

        var (
                proxyURL *url.URL
                sel      discovery.Selection
        )
        if cfg.UpstreamOverride != "" {
                proxyURL = &url.URL{Scheme: "https", Host: cfg.UpstreamOverride}
                sel = discovery.Selection{
                        Hostname:        hostOf(cfg.UpstreamOverride),
                        Port:            portOf(cfg.UpstreamOverride),
                        SelectionSource: "override",
                }
                log.Infof("upstream override: %s", cfg.UpstreamOverride)
        } else {
                started := time.Now()
                fetched, err := vpnclient.FetchServerList(ctx)
                if err != nil {
                        if code, stop := cleanStopIfRequested(); stop {
                                return code
                        }
                        _ = emit.Emit(failedFrom(engine.ErrDiscoveryFailed, fferr.ClassifyTransport(err).Redact(cfg.Auth.AccessToken, cfg.Auth.RefreshToken), engine.ExitStartup))
                        return engine.ExitStartup
                }
                if code, stop := cleanStopIfRequested(); stop {
                        return code
                }
                codes := discovery.CountriesWithSelectableServers(fetched)
                _ = emit.Emit(engine.Event{
                        Name:        engine.EvDiscoveryFetched,
                        Countries:   codes,
                        DiscoveryMs: time.Since(started).Milliseconds(),
                })
                picked, err := discovery.Select(fetched, cfg.Country)
                if err != nil {
                        var noMatch *discovery.NoMatchError
                        if errors.As(err, &noMatch) {
                                _ = emit.Emit(engine.Event{
                                        Name: engine.EvFailed, FailCode: engine.ErrNoMatchForCountry,
                                        Message: noMatch.Error(), Code: engine.ExitStartup,
                                })
                                return engine.ExitStartup
                        }
                        _ = emit.Emit(failedFrom(engine.ErrInternal, fferr.ClassifyTransport(err).Redact(cfg.Auth.AccessToken, cfg.Auth.RefreshToken), engine.ExitInternal))
                        return engine.ExitInternal
                }
                sel = picked
                proxyURL = &url.URL{Scheme: "https", Host: sel.HostPort()}
        }

        _ = emit.Emit(engine.Event{
                Name:            engine.EvSelected,
                Country:         sel.Country,
                CountryName:     sel.CountryName,
                CityCode:        sel.CityCode,
                CityName:        sel.CityName,
                Hostname:        sel.Hostname,
                Port:            sel.Port,
                SelectionSource: sel.SelectionSource,
                Recommended:     sel.Recommended,
        })

        // 3. the initial Guardian pass (same-account recovery inside).
        controller := upstream.NewController(upstream.ControllerConfig{
                Guardian:      cfg.Guardian,
                AccessToken:   cfg.Auth.AccessToken,
                RefreshToken:  cfg.Auth.RefreshToken,
                Transport:     cfg.Transport,
                ProxyURL:      proxyURL,
                OpenTimeout:   time.Duration(cfg.UpstreamTimeoutMs) * time.Millisecond,
                OnPassRenewed: func(pass *vpnclient.ProxyPassInfo) {
                        _ = emit.Emit(engine.Event{
                                Name:          engine.EvRenewed,
                                PassExpiresAt: pass.ExpiresAt().UTC().Format(time.RFC3339),
                                QuotaLeft:     pass.QuotaLeft,
                                QuotaReset:    pass.QuotaReset,
                        })
                },
                OnAuthRefresh: func(pair vpnclient.TokenResponse) {
                        // The SECRET-carrying event: straight to the host's vault.
                        _ = emit.Emit(engine.Event{
                                Name:          engine.EvAuthRefreshed,
                                AccessToken:   pair.AccessToken,
                                RefreshToken:  pair.RefreshToken,
                                ExpiresIn:     pair.ExpiresIn,
                                ObtainedAt:    time.Now().UTC().Format(time.RFC3339),
                        })
                },
                OnRenewalFail: func(redacted string, failCode string, retryInMs int64) {
                        _ = emit.Emit(engine.Event{
                                Name:      engine.EvRenewalFailed,
                                Message:   redact.Line(redacted),
                                FailCode:  failCode,
                                RetryInMs: retryInMs,
                        })
                },
                Logf: log.Infof,
        })
        defer controller.Close()

        pass, err := controller.AcquireInitialPass(ctx)
        if err != nil {
                if code, stop := cleanStopIfRequested(); stop {
                        return code
                }
                if errors.Is(err, vpnclient.ErrQuotaExceeded) {
                        _ = emit.Emit(engine.Event{
                                Name: engine.EvQuotaExhausted,
                                Code: engine.ExitQuota,
                        })
                        return engine.ExitQuota
                }
                class := classifyGuardian(err, cfg)
                _ = emit.Emit(failedFrom(engine.ErrPassFetchFailed, class, engine.ExitStartup))
                return engine.ExitStartup
        }
        _ = emit.Emit(engine.Event{
                Name:          engine.EvPassAcquired,
                PassExpiresAt: pass.ExpiresAt().UTC().Format(time.RFC3339),
                QuotaLeft:     pass.QuotaLeft,
                QuotaReset:    pass.QuotaReset,
        })

        // 4. the single upstream session.
        latency, err := controller.Start(ctx, pass)
        if err != nil {
                class := classifyUpstream(err, cfg)
                _ = emit.Emit(failedFrom(engine.ErrUpstreamSession, class, engine.ExitStartup))
                return engine.ExitStartup
        }
        host, _ := controller.SessionHost()
        _ = emit.Emit(engine.Event{
                Name:      engine.EvUpstreamReady,
                Transport: cfg.Transport,
                ProxyHost: host,
                LatencyMs: latency.Milliseconds(),
        })

        // 5. the SOCKS5 listener (loopback-only, validated above).
        server := socks.NewServer(controller,
                time.Duration(cfg.HandshakeTimeoutMs)*time.Millisecond,
                time.Duration(cfg.IdleTimeoutMs)*time.Millisecond,
                cfg.MaxConns, log)
        addr, err := server.Listen(cfg.SocksListen)
        if err != nil {
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: engine.ErrSocksListenFailed,
                        Message: "the SOCKS listener could not be bound", Code: engine.ExitStartup,
                })
                return engine.ExitStartup
        }
        defer server.Close()
        _ = emit.Emit(engine.Event{Name: engine.EvSocksReady, Addr: addr.String()})
        // Stage 2: mirror the upstream proxy-demo's startup log so the
        // effective SOCKS-layer limits are visible on-device (core-log.txt)
        // — maxConns now defaults to the upstream's 256 when the host
        // sends 0; idleTimeout stays 0 (the upstream demo default).
        log.Infof("socks5 ready on %s handshake_timeout=%s idle_timeout=%s max_conns=%d",
                addr.String(),
                time.Duration(cfg.HandshakeTimeoutMs)*time.Millisecond,
                time.Duration(cfg.IdleTimeoutMs)*time.Millisecond,
                cfg.MaxConns)

        // Stage 6: the periodic runtime-stats evidence line — one Info
        // line per minute of goroutine/heap/GC/allocation counters. The
        // child's environment is deliberately EMPTY (no GODEBUG/pprof
        // injection is possible), so core-log.txt is the only on-device
        // channel for the CPU/memory picture; the loop stops with the
        // engine's context.
        go runtimeStatsLoop(ctx, log, runtimeStatsInterval)

        // 6. the engine-side exit probe — NON-FATAL evidence only.
        go func() {
                result, err := upstream.VerifyExit(controller, cfg.ExitCheckURL,
                        time.Duration(cfg.ExitTimeoutMs)*time.Millisecond)
                if err != nil {
                        _ = emit.Emit(engine.Event{
                                Name:    engine.EvExitVerifyFailed,
                                Message: redact.Line(err.Error()),
                        })
                        return
                }
                var matches *bool
                if sel.Country != "" && sel.Country != discovery.RecommendedCode {
                        m := strings.EqualFold(sel.Country, result.CountryCode)
                        matches = &m
                }
                _ = emit.Emit(engine.Event{
                        Name:               engine.EvExitVerified,
                        ExitIP:             result.IP,
                        ExitCountry:        result.CountryCode,
                        ConfiguredCountry:  sel.Country,
                        ExitCountryMatches: matches,
                        LatencyMs:          result.Latency.Milliseconds(),
                })
        }()

        // 7. the park loop: stdin close = the shutdown request; quota and
        // renewal-timeout surface from the renewal walk.
        terminal := controller.Terminal()

        select {
        case <-stdinDone:
                _ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "stdinClosed"})
                return engine.ExitClean
        case kind := <-terminal:
                if kind == upstream.TerminalQuota {
                        _ = emit.Emit(engine.Event{Name: engine.EvQuotaExhausted, Code: engine.ExitQuota})
                        return engine.ExitQuota
                }
                _ = emit.Emit(engine.Event{
                        Name: engine.EvFailed, FailCode: engine.ErrRenewalTimeout,
                        Message: "the proxy pass could not be renewed in time", Code: engine.ExitRenewal,
                })
                return engine.ExitRenewal
        }
}

// runtimeStatsInterval is the on-device evidence cadence (Stage 6):
// one line per minute — cheap (ReadMemStats stops the world for
// microseconds) and deliberately NOT a knob (no config field; the
// contract stays the stdin JSON config only).
const runtimeStatsInterval = 60 * time.Second

// runtimeStatsLoop emits one Info stats line per interval until the
// context is cancelled (the engine's park-loop exit).
func runtimeStatsLoop(ctx context.Context, log *stderrLogger, interval time.Duration) {
        var prev runtime.MemStats
        runtime.ReadMemStats(&prev)
        prevAt := time.Now()
        ticker := time.NewTicker(interval)
        defer ticker.Stop()
        for {
                select {
                case <-ctx.Done():
                        return
                case <-ticker.C:
                        var cur runtime.MemStats
                        runtime.ReadMemStats(&cur)
                        now := time.Now()
                        log.Infof("runtime stats %s", formatRuntimeStats(&prev, &cur, now.Sub(prevAt)))
                        prev = cur
                        prevAt = now
                }
        }
}

// formatRuntimeStats renders one stats line: goroutine count, live
// heap, OS view, GC count, cumulative allocation and the allocation
// RATE over the elapsed window. The counters are cumulative — the
// reader diffs consecutive lines for trends (e.g. GC frequency,
// goroutine accumulation — the ping-degradation evidence Stage 6
// needs from the owner's device).
func formatRuntimeStats(prev, cur *runtime.MemStats, dt time.Duration) string {
        allocKBps := 0.0
        if dt > 0 {
                allocKBps = float64(cur.TotalAlloc-prev.TotalAlloc) / 1024 / dt.Seconds()
        }
        return fmt.Sprintf("goroutines=%d heap_mb=%.1f sys_mb=%.1f num_gc=%d total_alloc_mb=%.1f alloc_kbps=%.0f",
                runtime.NumGoroutine(),
                float64(cur.HeapAlloc)/(1024*1024),
                float64(cur.Sys)/(1024*1024),
                cur.NumGC,
                float64(cur.TotalAlloc)/(1024*1024),
                allocKBps,
        )
}

// watchStdinClose resolves when the host closes the child's stdin (the
// shutdown request). A goroutine blocks on a zero-byte read.
func watchStdinClose(ctx context.Context, onClosed func()) <-chan struct{} {
        return watchStdinCloseReader(ctx, os.Stdin, onClosed)
}

// watchStdinCloseReader is the reader-injected core (the probe role
// passes its config reader so tests never race the os.Stdin global;
// the production callers hand it os.Stdin via watchStdinClose).
func watchStdinCloseReader(ctx context.Context, r io.Reader, onClosed func()) <-chan struct{} {
        done := make(chan struct{})
        var once sync.Once
        trigger := func() {
                once.Do(func() {
                        onClosed()
                        close(done)
                })
        }
        go func() {
                buf := make([]byte, 1)
                for {
                        n, err := r.Read(buf)
                        if n > 0 && err == nil {
                                // The contract is ONE line then silence; extra bytes are
                                // drained (never interpreted as a second config).
                                continue
                        }
                        trigger()
                        return
                }
        }()
        go func() {
                <-ctx.Done()
                trigger()
        }()
        return done
}

// failedFrom builds the failed event carrying the Phase B classified
// fields (additive: httpStatus/retryable only when meaningful).
func failedFrom(failCode string, class fferr.Classified, exit int) engine.Event {
        ev := engine.Event{
                Name:    engine.EvFailed,
                FailCode: failCode,
                Message: class.Message,
                Code:    exit,
        }
        if class.Code != "" {
                // The granular Phase B class REPLACES the umbrella code when the
                // classifier produced one (legacy Dart maps both).
                ev.FailCode = string(class.Code)
        }
        if class.HTTPStatus != 0 {
                ev.HTTPStatus = class.HTTPStatus
        }
        if class.Retryable {
                retryable := true
                ev.Retryable = &retryable
        } else if class.Code != "" {
                retryable := false
                ev.Retryable = &retryable
        }
        return ev
}

// classifyGuardian maps Guardian failures. The typed sentinels first
// (the upstream's own ErrTokenInvalid fires ONLY on 401/403 →
// sessionRejected; ErrQuotaExceeded is handled before this point), then
// the typed GuardianHTTPError through fferr.ClassifyGuardian with the
// REAL status and body — the Guardian-only 451 becomes the dedicated
// guardianRegionUnavailable class (guardian-bootstrap Stage 1; the
// error type itself is the endpoint proof: the pin constructs
// GuardianHTTPError only in the /api/v1/fpn/* walks) — then
// type-based transport classification. The status for the
// token-invalid sentinel rides the error text (the same documented
// seam as the FxA errno — the upstream pin exports no typed status
// there) and is extracted, never guessed.
func classifyGuardian(err error, cfg engine.Config) fferr.Classified {
        if errors.Is(err, vpnclient.ErrTokenInvalid) {
                class := fferr.Classified{
                        Code:      fferr.CodeSessionRejected,
                        Message:   "The session was rejected by the account server",
                        Internal:  err.Error(),
                }
                if status, ok := fxaHTTPStatus(err.Error()); ok {
                        class.HTTPStatus = status
                }
                return class.Redact(cfg.Auth.AccessToken, cfg.Auth.RefreshToken)
        }
        var httpErr *vpnclient.GuardianHTTPError
        if errors.As(err, &httpErr) {
                return fferr.ClassifyGuardian(httpErr.StatusCode, httpErr.Body).Redact(cfg.Auth.AccessToken, cfg.Auth.RefreshToken)
        }
        class := fferr.ClassifyTransport(err)
        if class.Code == fferr.CodeUnknown {
                // The umbrella exchange class for control-plane walks.
                class.Code = fferr.CodeTokenExchange
                class.Message = "The sign-in exchange failed"
        }
        return class.Redact(cfg.Auth.AccessToken, cfg.Auth.RefreshToken)
}

// classifyUpstream maps session-build failures (h2/h3 negotiation
// included) — upstreamSessionFailed keeps its umbrella code (the
// transport-level classes belong to the exchange walks).
func classifyUpstream(err error, cfg engine.Config) fferr.Classified {
        class := fferr.Classified{Code: "", Message: "the upstream session could not be established"}
        if errors.Is(err, upstream.ErrHTTP2Unavailable) || errors.Is(err, upstream.ErrHTTP3Unavailable) {
                class.Message = "the proxy did not negotiate the requested transport"
        }
        return class
}

// hostOf / portOf split a host:port override.
func hostOf(hostPort string) string {
        if i := strings.LastIndex(hostPort, ":"); i > 0 {
                return hostPort[:i]
        }
        return hostPort
}

func portOf(hostPort string) int {
        if i := strings.LastIndex(hostPort, ":"); i > 0 {
                var p int
                if _, err := fmt.Sscanf(hostPort[i+1:], "%d", &p); err == nil {
                        return p
                }
        }
        return 443
}

// stderrLogger writes the engine's human logs (redacted upstream) —
// the level discipline of the upstream demo's logDebug/logInfo/logWarn
// (Stage 6): quiet silences everything, debug needs verbose, info/warn
// are always on when not quiet.
type stderrLogger struct {
        enabled bool
        verbose bool
        redact  func(string) string
        w       io.Writer // nil = os.Stderr (tests inject a buffer)
}

func (l *stderrLogger) sink() io.Writer {
        if l.w != nil {
                return l.w
        }
        return os.Stderr
}

func (l *stderrLogger) Debugf(format string, args ...any) {
        if l.enabled && l.verbose {
                fmt.Fprintf(l.sink(), "%s", "debug: "+l.redact(fmt.Sprintf(format, args...))+"\n")
        }
}

func (l *stderrLogger) Warnf(format string, args ...any) {
        if l.enabled {
                fmt.Fprintf(l.sink(), "%s", "warn: "+l.redact(fmt.Sprintf(format, args...))+"\n")
        }
}

func (l *stderrLogger) Infof(format string, args ...any) {
        if l.enabled {
                fmt.Fprintf(l.sink(), "%s", "info: "+l.redact(fmt.Sprintf(format, args...))+"\n")
        }
}

func (l *stderrLogger) Verbose() bool { return l.verbose }
