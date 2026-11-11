// The --guardian-probe role performs Remote Settings server-list
// discovery followed by Guardian FetchProxyPass (including same-account
// recovery). Both share one Direct budget; with apiProxy set, those exact
// two control-plane requests use the local bootstrap proxy. No upstream
// session or SOCKS listener is created. It is the real-request vehicle for the Dart host's two
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
	"net/url"
	"os"
	"time"

	vpnclient "firefox-vpn-client"

	"aethone/fxv/internal/cptransport"
	"aethone/fxv/internal/engine"
	"aethone/fxv/internal/fferr"
	"aethone/fxv/internal/upstream"
)

const remoteSettingsBaseURL = "https://firefox.settings.services.mozilla.com"

// Replaceable only to keep probe tests deterministic and offline.
var fetchRemoteSettings = func(ctx context.Context) error {
	_, err := vpnclient.FetchServerList(ctx)
	return err
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
	allow, err := cptransport.NewBootstrapAllowlist(cfg.Guardian, remoteSettingsBaseURL)
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

	// 4. Match the tunnel's control-plane order. Direct gets a fresh
	// four-second context for discovery AND another fresh four seconds
	// for Guardian authorization. Bootstrap proxy requests share one
	// bounded 55-second context to fit inside the host's 60-second cap.
	controlBudget := newControlPlaneBudget(ctx, cfg.ApiProxy)
	defer controlBudget.close()
	if cfg.UpstreamOverride == "" {
		discoveryCtx, cancelDiscovery := controlBudget.requestContext()
		err := fetchRemoteSettings(discoveryCtx)
		cancelDiscovery()
		if err != nil {
			select {
			case <-stdinDone:
				_ = emit.Emit(engine.Event{Name: engine.EvStopped, Reason: "stdinClosed"})
				return engine.ExitClean
			default:
			}
			class := fferr.ClassifyTransport(err).Redact(cfg.Auth.AccessToken, cfg.Auth.RefreshToken)
			_ = emit.Emit(failedFromStage(engine.ErrDiscoveryFailed, class, engine.ExitStartup, engine.FailureStageRemoteSettingsDiscovery))
			return engine.ExitStartup
		}
	}

	// 5. The REAL initial-pass walk — same-account FxA recovery remains
	// intact. Direct receives its own four-second Guardian budget; a
	// proxied walk remains under the one shared control-plane deadline.
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

	guardianCtx, cancelGuardian := controlBudget.requestContext()
	pass, err := controller.AcquireInitialPass(guardianCtx)
	cancelGuardian()
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
		_ = emit.Emit(failedFromStage(engine.ErrPassFetchFailed, class, engine.ExitStartup, engine.FailureStageGuardianPass))
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
