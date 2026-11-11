package relay

// The shared Guardian relay pool — AETHONE original implementation of
// the community-relay recovery (2026-11-11; see package comment for
// the provenance posture).
//
// The pool is deliberately LAZY: no manifest, health probe or
// forwarded request exists until a production Guardian request has
// already answered HTTP 451 (after the doubled-path bypass failed).
// Candidates and health state live in memory only, never in settings.
//
// The manifest is the arman-org community list (public JSON data,
// fetched read-only; its curation is that project's, the consumption
// protocol is the open one described in the package comment):

import (
        "context"
        "encoding/json"
        "errors"
        "io"
        "math/rand/v2"
        "net/http"
        "net/url"
        "strings"
        "sync"
        "time"
)

const (
        sharedManifestURL    = "https://raw.githubusercontent.com/arman-org/update-manifests/main/arman-vpn-client/updates.json"
        sharedManifestMirror = "https://cdn.jsdelivr.net/gh/arman-org/update-manifests@main/arman-vpn-client/updates.json"

        // sharedBudget bounds one whole recovery walk (manifest + probes +
        // the forwarded request).
        sharedBudget = 20 * time.Second
        // sharedProbeTimeout bounds each relay connection/probe.
        sharedProbeTimeout = 4 * time.Second
        // sharedManifestMax bounds the manifest body.
        sharedManifestMax = 512 * 1024
        // sharedCandidatesMax bounds the candidate count.
        sharedCandidatesMax = 100
        // sharedHealthBodyMax bounds the health JSON body.
        sharedHealthBodyMax = 4096
)

// sharedPool holds the candidate list and health state. The zero
// value is not usable; newSharedPool builds one.
type sharedPool struct {
        manifestURLs []string
        client       *http.Client
        // transport builds the relay leg for a candidate (ECH/TLS modes
        // from the same Options the personal relay uses).
        transport func(*url.URL) (http.RoundTripper, error)
        // shuffle is injectable for deterministic tests.
        shuffle func(n int, swap func(i, j int))

        mu        sync.Mutex
        urls      []string
        refreshAt time.Time
        active    string
        activeTil time.Time
        badUntil  map[string]time.Time

        // guardianHost scopes Recovery to the configured Guardian endpoint.
        guardianHost string
}

func newSharedPool(opts Options) *sharedPool {
        p := &sharedPool{
                manifestURLs: []string{sharedManifestURL, sharedManifestMirror},
                client: &http.Client{
                        Timeout:       2 * sharedProbeTimeout,
                        CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
                },
                shuffle:      rand.Shuffle,
                badUntil:     make(map[string]time.Time),
                guardianHost: opts.GuardianHost,
        }
        p.client.Transport = &http.Transport{
                Proxy:           nil,
                TLSHandshakeTimeout: sharedProbeTimeout,
                // A manifest fetch is bootstrap traffic, not a control-plane
                // request: its own plain transport, never the relay stack.
        }
        p.transport = func(u *url.URL) (http.RoundTripper, error) {
                return newRelayLeg(u, opts), nil
        }
        return p
}

// load refreshes the candidate list (cached 10 minutes; a failed
// refresh retries after a minute and never erases a fetched list). A
// valid manifest with relays.enabled=false is authoritative and clears
// the pool. The CALLER holds p.mu (Recover); load itself must not lock.
func (p *sharedPool) load(ctx context.Context) {
        if time.Now().Before(p.refreshAt) {
                return
        }
        p.refreshAt = time.Now().Add(time.Minute)
        for _, source := range p.manifestURLs {
                req, err := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
                if err != nil {
                        continue
                }
                req.Header.Set("Accept", "application/json")
                resp, err := p.client.Do(req)
                if err != nil {
                        continue
                }
                body, readErr := io.ReadAll(io.LimitReader(resp.Body, sharedManifestMax+1))
                resp.Body.Close()
                if readErr != nil || resp.StatusCode != http.StatusOK || len(body) > sharedManifestMax {
                        continue
                }
                var manifest struct {
                        Relays *struct {
                                Enabled bool     `json:"enabled"`
                                URLs    []string `json:"urls"`
                        } `json:"relays"`
                }
                if json.Unmarshal(body, &manifest) != nil {
                        continue
                }
                var candidates []string
                seen := map[string]bool{}
                if manifest.Relays != nil && manifest.Relays.Enabled {
                        for _, raw := range manifest.Relays.URLs {
                                u, err := url.Parse(strings.TrimSpace(raw))
                                if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.Fragment != "" {
                                        continue
                                }
                                q := u.Query()
                                if q.Has("url") || q.Has("health") {
                                        continue
                                }
                                raw = u.String()
                                if !seen[raw] {
                                        candidates = append(candidates, raw)
                                        seen[raw] = true
                                }
                                if len(candidates) >= sharedCandidatesMax {
                                        break
                                }
                        }
                }
                p.urls = candidates
                for raw := range p.badUntil {
                        if !seen[raw] {
                                delete(p.badUntil, raw)
                        }
                }
                p.refreshAt = time.Now().Add(10 * time.Minute)
                if !seen[p.active] {
                        p.active, p.activeTil = "", time.Time{}
                }
                return
        }
}

// healthy probes a candidate: GET ?health=1 must answer the fixed
// shared-pool health JSON. The probe talks only to the relay itself —
// no request to Mozilla.
func (p *sharedPool) healthy(ctx context.Context, relay *url.URL, base http.RoundTripper) bool {
        u := *relay
        query := u.Query()
        query.Set("health", "1")
        u.RawQuery = query.Encode()
        req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
        if err != nil {
                return false
        }
        req.Header.Set("Accept", "application/json")
        req.Header.Set("Cache-Control", "no-cache")
        client := &http.Client{
                Transport:     base,
                Timeout:       2 * sharedProbeTimeout,
                CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
        }
        resp, err := client.Do(req)
        if err != nil {
                return false
        }
        defer resp.Body.Close()
        var report struct {
                Relay   string `json:"relay"`
                Version int    `json:"version"`
                Ready   bool   `json:"ready"`
        }
        // The community health identity: the arman-org pool's relays answer
        // "arman-vpn"; relays deployed from AETHONE's own guide
        // (docs/firefox-vpn/relay/worker.js) answer "aethone". Both are the
        // same wire protocol — either identity proves a deliberate relay
        // health endpoint, not a random JSON that happens to say ready.
        return resp.StatusCode == http.StatusOK &&
                json.NewDecoder(io.LimitReader(resp.Body, sharedHealthBodyMax)).Decode(&report) == nil &&
                (report.Relay == "arman-vpn" || report.Relay == "aethone") &&
                report.Version == 1 && report.Ready
}

// Recover re-sends a 451'd Guardian request through the first healthy
// shared relay. It returns an error when no relay recovered the
// request; the caller then keeps the original 451 response.
func (p *sharedPool) Recover(req *http.Request) (*http.Response, error) {
        if !isGuardianFPN(req, p.guardianHost) {
                return nil, errors.New("shared relays carry Guardian requests only")
        }
        if req.Body != nil && req.GetBody == nil {
                return nil, errors.New("request body is not replayable")
        }
        ctx, cancel := context.WithTimeout(req.Context(), sharedBudget)
        handedOff := false
        defer func() {
                if !handedOff {
                        cancel()
                }
        }()
        // One walk at a time: concurrent 451s (pass fetch + renewal)
        // reuse the winner instead of each scanning the full pool.
        p.mu.Lock()
        defer p.mu.Unlock()
        if ctx.Err() != nil {
                return nil, ctx.Err()
        }
        p.load(ctx)

        order := append([]string(nil), p.urls...)
        p.shuffle(len(order), func(i, j int) { order[i], order[j] = order[j], order[i] })
        if p.active != "" && time.Now().Before(p.activeTil) {
                order = append([]string{p.active}, order...)
        }
        seen := map[string]bool{}
        for _, raw := range order {
                if ctx.Err() != nil {
                        break
                }
                if seen[raw] || time.Now().Before(p.badUntil[raw]) {
                        continue
                }
                seen[raw] = true
                u, err := url.Parse(raw)
                if err != nil {
                        continue
                }
                base, err := p.transport(u)
                if err != nil {
                        continue
                }
                if closer, ok := base.(interface{ CloseIdleConnections() }); ok {
                        defer closer.CloseIdleConnections()
                }
                if !p.healthy(ctx, u, base) {
                        p.badUntil[raw] = time.Now().Add(SharedBadFor)
                        continue
                }
                out := cloneRequest(req)
                out = out.WithContext(ctx)
                resp, err := (&relayTransport{relay: u, base: base}).RoundTrip(out)
                if err == nil && usableSharedResponse(req, resp) {
                        // RoundTrip's body still reads under ctx; keep the budget
                        // alive until the caller closes the body.
                        resp.Body = &cancelOnCloseBody{ReadCloser: resp.Body, cancel: cancel}
                        handedOff = true
                        p.active, p.activeTil = raw, time.Now().Add(RelayFirstFor)
                        resp.Request = req
                        return resp, nil
                }
                if resp != nil {
                        resp.Body.Close()
                }
                p.badUntil[raw] = time.Now().Add(SharedBadFor)
                // A non-idempotent request that left the relay without a
                // usable answer may have been delivered: stop, never re-send.
                if req.Method != http.MethodGet && req.Method != http.MethodHead {
                        break
                }
        }
        return nil, errors.New("no healthy shared relay is available")
}

// usableSharedResponse validates a relayed Guardian answer: the
// FORWARDED marker must be present, and the status must be one
// Guardian itself could have produced with a JSON body.
func usableSharedResponse(req *http.Request, resp *http.Response) bool {
        if resp == nil || resp.Header.Get("X-Arman-Relay") != "1" {
                return false
        }
        switch resp.StatusCode {
        case http.StatusOK, http.StatusUnauthorized, http.StatusForbidden, http.StatusTooManyRequests:
                return strings.Contains(strings.ToLower(resp.Header.Get("Content-Type")), "application/json")
        }
        return false
}

// cancelOnCloseBody keeps a child context's deadline alive until the
// response body is closed by the final consumer.
type cancelOnCloseBody struct {
        io.ReadCloser
        cancel context.CancelFunc
}

func (b *cancelOnCloseBody) Close() error {
        err := b.ReadCloser.Close()
        b.cancel()
        return err
}
