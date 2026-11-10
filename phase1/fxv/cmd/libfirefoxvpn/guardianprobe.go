// The --guardian-probe role (guardian-bootstrap Stage 5): a LIGHTWEIGHT
// engine run that performs EXACTLY the initial Guardian authorization
// walk of the tunnel role — FxA same-account recovery + FetchProxyPass
// (GET /api/v1/fpn/token) — and reports the classified outcome, with
// no Remote-Settings discovery, no upstream session, and no SOCKS
// listener. It is the real-request vehicle for the Dart host's two
// Stage-4 seams:
//
//	GuardianDirectAttempt          --guardian-probe, NO apiProxy — the
//	                                 request rides the direct uTLS
//	                                 transport; a real 451 surfaces as
//	                                 the guardianRegionUnavailable
//	                                 class (Stage 1's rules).
//	GuardianAuthorizationVerifier  --guardian-probe, apiProxy set —
//	                                 the SAME request rides the
//	                                 RoutingRoundTripper's allowlisted
//	                                 leg through the local bootstrap
//	                                 proxy; success is a real
//	                                 authorization, not a health ping
//	                                 (mission §4-4).
//
// The walk is the production code path itself (upstream.Controller's
// AcquireInitialPass — the same controller the tunnel role uses), so
// the probe can never drift from what a real connect does. The exit
// and event contracts mirror the tunnel role: `started`, then either
// `passAcquired` + a clean exit, or `quotaExhausted`/`failed` with the
// Stage-1 classification and the startup exit codes. `authRefreshed`
// (the same-account recovery) is emitted exactly like the tunnel role
// — the Dart host stores the pair, never logs it.
//
// The pass a probe acquires is NOT handed to anyone: the caller that
// needs a live tunnel spawns the tunnel role (with the same apiProxy
// decision the probe just proved), which acquires its own pass. One
// extra FetchProxyPass per probe is the price of the honest decision —
// the same endpoint the renewal loop already calls regularly.
package main

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"

	vpnclient "firefox-vpn-client"

	"aethone/fxv/internal/cptransport"
	"aethone/fxv/internal/engine"
	"aethone/fxv/internal/upstream"
)

// guardianTokenPath is the ONE endpoint the engine's execution path
// really calls on the Guardian host (Stage 1's source-verified table):
// the pinned client's FetchProxyPass — the initial authorization AND
// the renewal walk. /api/v1/fpn/status and /api/v1/fpn/activate are
// NOT called by this engine and stay out of the allowlist (mission
// §5-3: only endpoints confirmed in the real execution path).
var guardianAllowlistEntries = []cptransport.AllowedRequest{
	{Method: http.MethodGet, Path: "/api/v1/fpn/token"},
}

// installGuardianRouting installs the Stage-5 selective control-plane
// routing when cfg.ApiProxy is set (mission §5-2). An empty ApiProxy
// leaves the pinned default direct uTLS transport untouched — the
// pre-Stage-5 behavior, byte-identical. It MUST run before the first
// control-plane request (the pin's shared client is process-wide).
func installGuardianRouting(cfg engine.Config, log *stderrLogger) error {
	if cfg.ApiProxy == "" {
		return nil
	}
	proxied, err := cptransport.NewProxyRoundTripper(cfg.ApiProxy)
	if err != nil {
		// Static text only: the construction error may quote the URL;
		// the loopback/validation guarantees make the details useless
		// anyway (validation already parsed the same value).
		return errors.New("the api proxy transport could not be built")
	}
	allow, err := cptransport.NewGuardianAllowlist(cfg.Guardian, guardianAllowlistEntries...)
	if err != nil {
		return errors.New("the guardian allowlist could not be built")
	}
	vpnclient.SetControlPlaneTransport(cptransport.NewRoutingRoundTripper(
		vpnclient.NewControlPlaneTransport(), proxied, allow))
	// Redacted evidence line: scheme + host only. Config validation
	// already forbids credentials in the URL; belt and braces — never
	// render the raw value.
	parsed, perr := url.Parse(cfg.ApiProxy)
	if perr != nil {
		return errors.New("the api proxy URL could not be re-parsed")
	}
	log.Infof("guardian control-plane routing installed: api-proxy scheme=%s host=%s; %s",
		parsed.Scheme, parsed.Host, allow.Redacted())
	return nil
}

// runGuardianProbe is the --guardian-probe role's entry point.
func runGuardianProbe() int {
	return runGuardianProbeReader(os.Stdin)
}

// runGuardianProbeReader is the testable core (the config line comes
// from r; the events go to stdout exactly like every other role).
func runGuardianProbeReader(r io.Reader) int {
	emit := engine.NewEmitter()
	log := &stderrLogger{redact: func(s string) string { return s }}

	// 1. The SAME config line contract as the tunnel role.
	cfg, err := engine.ReadConfigLine(r)
	if err != nil {
		var cfgErr *engine.ConfigError
		detail := "configNotJSON"
		if errors.As(err, &cfgErr) {
			detail = cfgErr.DetailCode()
		}
		_ = emit.Emit(engine.Event{
			Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
			Message: detail, Code: engine.ExitStartup,
		})
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
	log.verbose = cfg.LogLevel == "verbose"

	_ = emit.Emit(engine.Event{
		Name:    engine.EvStarted,
		Message: engine.EngineVersion + " guardian-probe",
		PID:     os.Getpid(),
	})

	// 2. The routing install — before ANY control-plane request. The
	// probe's whole purpose: the same walk, through the same transport
	// decision the tunnel role would use.
	if err := installGuardianRouting(cfg, log); err != nil {
		_ = emit.Emit(engine.Event{
			Name: engine.EvFailed, FailCode: engine.ErrBadConfig,
			Message: "apiProxyTransport", Code: engine.ExitStartup,
		})
		return engine.ExitStartup
	}

	// 3. The walk: stdin close cancels it, exactly like the tunnel
	// role honors its shutdown request. The watcher reads the SAME
	// reader the config line came from (production: os.Stdin — one
	// line then silence; tests: an injected pipe).
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stdinDone := watchStdinCloseReader(ctx, r, func() {
		cancel()
		_ = emit.Emit(engine.Event{Name: engine.EvStopping, Reason: "stdinClosed"})
	})
	// A settle edge: the probe's return happens strictly AFTER the
	// watcher finished its final action (the stopping emit — the only
	// event any background goroutine can produce). Production is
	// unaffected (the process exits right after anyway); tests that
	// swap os.Stdout around the call get a clean happens-before
	// instead of a data race on the global.
	watcherSettled := make(chan struct{})
	go func() {
		<-stdinDone
		close(watcherSettled)
	}()
	defer func() {
		cancel()
		<-watcherSettled
	}()

	// 4. The REAL initial-pass walk — the same controller the tunnel
	// role uses (AcquireInitialPass: FetchProxyPass, with the
	// same-account FxA recovery when the access token is rejected as
	// stale). No Start() — no session, no renewal loop, no listener.
	controller := upstream.NewController(upstream.ControllerConfig{
		Guardian:     cfg.Guardian,
		AccessToken:  cfg.Auth.AccessToken,
		RefreshToken: cfg.Auth.RefreshToken,
		Transport:    cfg.Transport,
		OpenTimeout:  time.Duration(cfg.UpstreamTimeoutMs) * time.Millisecond,
		OnAuthRefresh: func(pair vpnclient.TokenResponse) {
			// The SECRET-carrying event, identical to the tunnel role:
			// straight to the host's vault, never logged.
			_ = emit.Emit(engine.Event{
				Name:         engine.EvAuthRefreshed,
				AccessToken:  pair.AccessToken,
				RefreshToken: pair.RefreshToken,
				ExpiresIn:    pair.ExpiresIn,
				ObtainedAt:   time.Now().UTC().Format(time.RFC3339),
			})
		},
		OnRenewalFail: func(string, string, int64) {}, // never fires without Start()
		Logf:          log.Infof,
	})
	defer controller.Close()

	pass, err := controller.AcquireInitialPass(ctx)
	if err != nil {
		select {
		case <-stdinDone:
			_ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "stdinClosed"})
			return engine.ExitClean
		default:
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
	return engine.ExitClean
}
