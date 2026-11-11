// Package relay — the control-plane API relay system (AETHONE original
// implementation, 2026-11-11).
//
// WHY IT EXISTS. Mozilla's CDN edge refuses some regions (observed:
// Iran) at the GUARDIAN control plane with HTTP 451
// unavailable_in_region: the account is fine, the tunnels are fine, but
// the proxy-pass authorization cannot be fetched, so the engine cannot
// connect at all.
//
// WHAT IT DOES. Every request below rides the CONTROL plane only (FxA,
// Guardian, Remote Settings); the VPN data plane keeps talking to
// Mozilla's MASQUE tunnels directly, always. Four layers, tried in
// order, cheapest first:
//
//  1. DOUBLED PATH (no relay at all) — the 451 is issued by the CDN
//     edge for the literal Guardian path before the request reaches
//     the origin. A doubled leading slash (//api/v1/fpn/token) does
//     not match that edge rule while the origin still routes it to the
//     same handler. Free; tried first.
//  2. SHARED RELAYS (Guardian 451 only) — a public pool of community
//     relays (the arman-org update manifest) probed by health, used
//     only for Guardian /api/v1/fpn/* requests that stayed 451 after
//     the doubled path.
//  3. PERSONAL RELAY (all control-plane hosts) — the user's own relay
//     URL (a Cloudflare Worker or PHP endpoint; see docs/firefox-vpn/
//     relay.md). Used when the direct route cannot CONNECT at all
//     (nothing sent — no double delivery) or answers 451, for every
//     control-plane request, not just Guardian.
//  4. RELAY-FIRST WINDOW — after any request HAD to go through the
//     personal relay, the next ones try the relay first for 10 minutes,
//     so only the first request pays the direct-failure wait.
//
// THE WIRE PROTOCOL (compatibility: the shared pool and the public
// relay guides). The client sends to the relay URL with the target
// added as its url query parameter, next to the relay's own parameters
// (its secret):
//
//      https://RELAY/?secret=S&url=https://vpn.mozilla.org/...
//
// Method, headers and body are forwarded as they are; the relay
// answers with the target's response. A relay that refuses sets
// X-Relay-Error: <reason> on its own response; a shared-pool relay
// marks a FORWARDED response with X-Arman-Relay: 1 and answers
// ?health=1 with {"relay":"arman-vpn","version":1,"ready":true}.
//
// PROVENANCE (phase1/fxv/ORIGIN.md § relay). The design follows the
// Arman VPN client's relay system as an ARCHITECTURAL REFERENCE, by
// the owner's order of 2026-11-11 lifting the standing consultation
// prohibition. Arman is GPL-3.0 licensed, so NO Arman code is included
// here — this package is an original implementation of the documented
// protocol and behavior, written for AETHONE's engine contract (the
// same reference-only posture the FoxyVPN (MIT) consultation used).
//
// DELTA vs. the reference (honest): the reference bounds the first
// direct attempt with a 4s quick dial; AETHONE keeps the upstream's
// own 15s uTLS dial budget instead (the seam exports no dial injection
// point), so the first blocked request may wait up to that budget once
// — after it, the 10-minute relay-first window removes the wait. The
// reference also resets relay state on network-change events; AETHONE
// relies on the window's expiry plus the relay-failure→direct retry
// (a network change shows up as a relay connect failure).
package relay

import (
        "fmt"
        "net/http"
        "net/http/httptrace"
        "net/url"
        "strings"
        "sync"
        "time"

        vpnclient "firefox-vpn-client"
)

// Timing budget constants (the reference system's proven values; the
// names AETHONE's own).
const (
        // RelayFirstFor is how long, after a request had to go through the
        // personal relay, the next ones go there FIRST without trying the
        // direct route (then direct again, in case the block was lifted).
        RelayFirstFor = 10 * time.Minute

        // SharedBadFor is how long a shared relay that failed its probe or
        // its forwarded request is skipped.
        SharedBadFor = time.Minute
)

// Options are the relay settings carried additively on the engine's
// Config and LoginConfig lines (all optional; zero value = the relay
// system fully off except the doubled-path Guardian bypass, which is
// free and needs no third party).
type Options struct {
        // PersonalRelay is the user's own relay URL, complete with its own
        // query (the secret). "" disables the personal layer.
        PersonalRelay string
        // PersonalEnabled is the master switch for the personal relay
        // (PersonalRelay stays stored in the app while disabled).
        PersonalEnabled bool
        // SharedEnabled arms the shared Guardian-only relay pool.
        SharedEnabled bool
        // ECHMode: "" (→ on), "off", "on" (best effort, plain TLS
        // fallback), "require" (fail closed without ECH).
        ECHMode string
        // ECHConfig: "" (the key comes from DNS), "name" (the HTTPS record
        // of another name carries the key), "name:base64key" (a fixed key).
        ECHConfig string
        // GuardianHost scopes the shared pool and the doubled-path bypass:
        // the host of the configured Guardian endpoint.
        GuardianHost string
        // Logf is the engine's level-tagged sink (callers already apply
        // their own redaction rules to what they log).
        Logf func(format string, args ...any)
}

// Normalize validates and defaults the raw option fields (static
// English errors, never values — the URL carries a secret).
func (o Options) Normalize() (Options, error) {
        if o.GuardianHost == "" {
                o.GuardianHost = "vpn.mozilla.org"
        }
        if o.ECHMode == "" {
                o.ECHMode = ECHModeOn
        }
        if err := validateECHMode(o.ECHMode); err != nil {
                return o, err
        }
        if _, _, err := parseECHConfig(o.ECHConfig); err != nil {
                return o, err
        }
        raw := strings.TrimSpace(o.PersonalRelay)
        if raw != "" {
                // The SHAPE is validated even while disabled: an address the
                // app stores should be a storable one (the engine contract
                // layer enforces the same). Disabling only clears the IN-USE
                // value; the app keeps its stored copy in its own settings.
                u, err := parseRelayURL(raw)
                if err != nil {
                        return o, err
                }
                raw = u.String()
                if !o.PersonalEnabled {
                        raw = ""
                }
        }
        o.PersonalRelay = raw
        return o, nil
}

// parseRelayURL enforces the relay URL shape (https, a host, no
// credentials, no fragment; the query is allowed — it carries the
// secret).
func parseRelayURL(raw string) (*url.URL, error) {
        u, err := url.Parse(raw)
        if err != nil || u.Scheme != "https" || u.Hostname() == "" {
                return nil, fmt.Errorf("relay URL must be https with a host")
        }
        if u.User != nil || u.Fragment != "" {
                return nil, fmt.Errorf("relay URL must not carry credentials or a fragment")
        }
        return u, nil
}

// stack is the installed control-plane RoundTripper.
type stack struct {
        direct   http.RoundTripper
        opts     Options
        personal *relayTransport
        shared   *sharedPool
        logf     func(string, ...any)

        mu         sync.Mutex
        relayUntil time.Time
}

// Install builds the transport stack from opts and installs it as the
// pinned upstream's control-plane transport (vpnclient.
// SetControlPlaneTransport — the exported seam; the upstream library
// code itself is never modified). It returns a restore function that
// reinstalls a pristine direct transport (tests; the process exits
// otherwise). Options that fail validation install nothing; options
// that normalize to inactive still install the stack, because the
// doubled-path Guardian bypass is free and third-party-less.
func Install(opts Options) (restore func()) {
        logf := opts.Logf
        if logf == nil {
                logf = func(string, ...any) {}
        }
        opts.Logf = logf
        normalized, err := opts.Normalize()
        if err != nil {
                logf("relay: options refused: %v", err)
                return func() {}
        }
        s := &stack{
                direct: vpnclient.NewControlPlaneTransport(),
                opts:   normalized,
                logf:   logf,
        }
        if normalized.PersonalRelay != "" {
                u, _ := parseRelayURL(normalized.PersonalRelay)
                s.personal = &relayTransport{relay: u, base: newRelayLeg(u, normalized)}
                logf("relay: personal relay armed host=%s ech=%s", u.Host, normalized.ECHMode)
        }
        if normalized.SharedEnabled {
                s.shared = newSharedPool(normalized)
                logf("relay: shared Guardian relay pool armed")
        }
        vpnclient.SetControlPlaneTransport(s)
        return func() { vpnclient.SetControlPlaneTransport(vpnclient.NewControlPlaneTransport()) }
}

// relayFirst reports whether the personal relay is currently preferred.
func (s *stack) relayFirst() bool {
        s.mu.Lock()
        defer s.mu.Unlock()
        return time.Now().Before(s.relayUntil)
}

func (s *stack) preferRelay() {
        s.mu.Lock()
        s.relayUntil = time.Now().Add(RelayFirstFor)
        s.mu.Unlock()
}

func (s *stack) preferDirect() {
        s.mu.Lock()
        s.relayUntil = time.Time{}
        s.mu.Unlock()
}

// RoundTrip is the control-plane decision walk.
func (s *stack) RoundTrip(req *http.Request) (*http.Response, error) {
        // Layer 4 (the active window): relay first, direct as its fallback.
        if s.personal != nil && s.relayFirst() {
                resp, err := s.personal.RoundTrip(cloneRequest(req))
                if err == nil {
                        return resp, nil
                }
                dresp, derr, dwhy := s.viaDirect(req)
                if dwhy == "" && derr == nil {
                        // The relay failed and Mozilla answered directly again.
                        s.preferDirect()
                        return dresp, nil
                }
                return nil, fmt.Errorf("relay unreachable: %w; direct: %v", err, derr)
        }

        resp, err, why := s.viaDirect(req)
        switch why {
        case "":
                return resp, err
        case whyRegion451:
                return s.recover451(req, resp)
        case whyConnect:
                // The direct route never opened (nothing was sent — no double
                // delivery). Only the personal relay covers plain
                // unreachability.
                if s.personal != nil {
                        if rresp, rerr := s.personal.RoundTrip(cloneRequest(req)); rerr == nil {
                                s.preferRelay()
                                s.logf("relay: direct route unreachable, served by the personal relay")
                                return rresp, nil
                        }
                }
                return resp, err
        }
        return resp, err
}

// recover451 runs the 451 recovery layers against req. resp is the
// original 451 response (body untouched): when no layer recovers, it
// is returned as-is so the upstream's GuardianHTTPError semantics (and
// the engine's failure classification) stay intact; when a layer
// recovers, its body is closed before the recovered response returns.
func (s *stack) recover451(req *http.Request, resp *http.Response) (*http.Response, error) {
        // Layer 1: the free doubled-path bypass (Guardian only).
        if doubled, ok := doubledPathRequest(req); ok {
                if dresp, derr, dwhy := s.viaDirect(doubled); dwhy == "" && derr == nil {
                        resp.Body.Close()
                        s.logf("relay: Guardian 451 bypassed with the doubled path")
                        return dresp, nil
                }
        }
        // Layer 2: the shared pool (Guardian /api/v1/fpn/* only).
        if s.shared != nil && isGuardianFPN(req, s.opts.GuardianHost) {
                if sresp, serr := s.shared.Recover(req); serr == nil {
                        resp.Body.Close()
                        s.logf("relay: Guardian 451 recovered through a shared relay")
                        return sresp, nil
                }
        }
        // Layer 3: the personal relay (every control-plane host).
        if s.personal != nil {
                if rresp, rerr := s.personal.RoundTrip(cloneRequest(req)); rerr == nil {
                        resp.Body.Close()
                        s.preferRelay()
                        s.logf("relay: 451 recovered through the personal relay")
                        return rresp, nil
                }
        }
        return resp, nil
}

// why values of the viaDirect probe.
const (
        whyRegion451 = "region451"
        whyConnect   = "connect"
)

// viaDirect sends through the direct (uTLS Firefox ClientHello)
// transport. why is non-empty only when another layer may take over:
// the connection never opened (provably nothing was sent — the
// httptrace GotConn hook never fired), or the answer was 451.
//
// The GotConn proof is strictly safer than a timeout race: a transport
// error AFTER the connection was assigned (a mid-write break) is
// returned as a plain error and never auto-retried through a relay, so
// no request can ever be delivered twice by this stack.
func (s *stack) viaDirect(req *http.Request) (*http.Response, error, string) {
        var connected bool
        out := cloneRequest(req)
        out = out.WithContext(httptrace.WithClientTrace(out.Context(), &httptrace.ClientTrace{
                GotConn: func(httptrace.GotConnInfo) { connected = true },
        }))
        resp, err := s.direct.RoundTrip(out)
        switch {
        case err != nil && !connected && req.Context().Err() == nil && replayable(req):
                return nil, err, whyConnect
        case err == nil && resp != nil && resp.StatusCode == http.StatusUnavailableForLegalReasons:
                return resp, nil, whyRegion451
        }
        if resp != nil {
                resp.Request = req
        }
        return resp, err, ""
}

// replayable reports whether req can be safely sent twice: a bodyless
// request, or one whose body can be re-obtained via GetBody.
func replayable(req *http.Request) bool {
        return req.Body == nil || req.GetBody != nil
}

// cloneRequest clones req with a replayed body when one exists; a
// body without GetBody (never produced by the control-plane callers —
// http.NewRequestWithContext sets it for the reader types) is shared,
// not dropped, so a non-replayable request is still sent exactly once.
func cloneRequest(req *http.Request) *http.Request {
        out := req.Clone(req.Context())
        if req.Body != nil && req.GetBody != nil {
                if body, err := req.GetBody(); err == nil {
                        out.Body = body
                }
        }
        return out
}

// doubledPathRequest clones req with one more leading slash on its
// path — the CDN edge's literal-path region rule does not match the
// doubled form while the origin still routes it to the same handler.
// It returns false when the path is already doubled or the body is
// not replayable.
func doubledPathRequest(req *http.Request) (*http.Request, bool) {
        if req.URL == nil || !strings.HasPrefix(req.URL.Path, "/") || strings.HasPrefix(req.URL.Path, "//") {
                return nil, false
        }
        if req.Body != nil && req.GetBody == nil {
                return nil, false
        }
        out := cloneRequest(req)
        u := *req.URL
        u.Path = "/" + u.Path
        u.RawPath = ""
        out.URL = &u
        return out, true
}

// isGuardianFPN reports whether req targets the Guardian FPN API (the
// only surface the shared relay pool may carry).
func isGuardianFPN(req *http.Request, guardianHost string) bool {
        return strings.EqualFold(req.URL.Hostname(), guardianHost) &&
                strings.HasPrefix(req.URL.Path, "/api/v1/fpn/")
}

// relayTransport sends each request to the relay with the target URL
// in the relay's url query parameter (next to the relay's own
// parameters, such as its secret), forwarding the method, headers and
// body as they are. A relay that refuses answers with X-Relay-Error;
// that is an error naming the relay, never a fake success.
type relayTransport struct {
        relay *url.URL
        base  http.RoundTripper
}

func (t *relayTransport) RoundTrip(req *http.Request) (*http.Response, error) {
        target := *t.relay
        query := target.Query()
        query.Set("url", req.URL.String())
        target.RawQuery = query.Encode()
        out := cloneRequest(req)
        out.URL = &target
        out.Host = ""
        resp, err := t.base.RoundTrip(out)
        if err != nil {
                return nil, fmt.Errorf("relay %s: %w", t.relay.Host, err)
        }
        if reason := resp.Header.Get("X-Relay-Error"); reason != "" {
                resp.Body.Close()
                return nil, fmt.Errorf("relay %s refused %s: %s", t.relay.Host, req.URL.Host, reason)
        }
        resp.Request = req
        return resp, nil
}
