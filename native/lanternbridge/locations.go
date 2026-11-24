// AETHONE v1.0.2 — Lantern's location catalog and country-first connects.
//
// Radiance only lists the servers Lantern's config server ASSIGNED to this
// device in the current config, and that assignment rotates between config
// fetches (the owner's field report: a first session offered DE + NL, a
// later one also JP). Two consequences the app used to show:
//
//  1. the wheel only knew the countries of the very last assignment, and
//  2. a non-auto pick connected through AUTO first (the fastest server,
//     e.g. NL) and only switched to the picked country once the post-connect
//     /select landed — the header showed NL, then JP.
//
// This file fixes both inside the sidecar:
//
//   - every location Lantern ever announced (the config's own "servers"
//     catalog, every assigned outbound's location) is remembered in
//     <dataDir>/aethone_locations.json, so the full set is known from the
//     first connect on and survives restarts;
//   - a country pick is sent to Lantern as Radiance's PreferredLocation
//     (the field Lantern's config server reads when assigning servers), the
//     config is re-fetched when no assigned server sits in that country,
//     and the tunnel CONNECTS straight to the best server there — never
//     through AUTO first.

package lanternbridge

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	rcommon "github.com/getlantern/radiance/common"
	"github.com/getlantern/radiance/common/settings"
	"github.com/getlantern/radiance/config"
	"github.com/getlantern/radiance/events"
	"github.com/getlantern/radiance/servers"
	"github.com/getlantern/radiance/vpn"
)

// lanternLocation is one country Lantern announced, as the app sees it.
type lanternLocation struct {
	Country     string `json:"country"`
	City        string `json:"city,omitempty"`
	CountryCode string `json:"country_code"`
	// Assigned is true when the CURRENT config holds a server there (it can
	// be selected without a config re-fetch).
	Assigned bool `json:"assigned"`
}

var catalog struct {
	mu   sync.Mutex
	path string
	// byCC is keyed by the upper-case ISO alpha-2 code.
	byCC map[string]lanternLocation
	sub  *events.Subscription[config.NewConfigEvent]
}

// initCatalog loads the remembered locations and starts listening for new
// configs. Called from Init before the backend starts, so the first config
// (cached or fetched) is never missed.
func initCatalog(dataDir string) {
	catalog.mu.Lock()
	catalog.path = filepath.Join(dataDir, "aethone_locations.json")
	catalog.byCC = map[string]lanternLocation{}
	if raw, err := os.ReadFile(catalog.path); err == nil {
		var saved []lanternLocation
		if json.Unmarshal(raw, &saved) == nil {
			for _, l := range saved {
				if cc := normCC(l.CountryCode); cc != "" {
					l.CountryCode = cc
					l.Assigned = false
					catalog.byCC[cc] = l
				}
			}
		}
	}
	if catalog.sub == nil {
		catalog.sub = events.Subscribe(func(evt config.NewConfigEvent) {
			if evt.New == nil {
				return
			}
			var found []rcommon.PreferredLocation
			found = append(found, evt.New.Servers...)
			for _, l := range evt.New.OutboundLocations {
				if l != nil {
					found = append(found, *l)
				}
			}
			rememberLocations(found)
		})
	}
	catalog.mu.Unlock()
}

func normCC(cc string) string {
	cc = strings.ToUpper(strings.TrimSpace(cc))
	if len(cc) != 2 {
		return ""
	}
	return cc
}

func rememberLocations(found []rcommon.PreferredLocation) {
	catalog.mu.Lock()
	defer catalog.mu.Unlock()
	if catalog.byCC == nil {
		return
	}
	changed := false
	for _, l := range found {
		cc := normCC(l.CountryCode)
		if cc == "" {
			continue
		}
		if _, ok := catalog.byCC[cc]; ok {
			continue
		}
		catalog.byCC[cc] = lanternLocation{Country: l.Country, City: l.City, CountryCode: cc}
		changed = true
	}
	if changed {
		saveCatalogLocked()
	}
}

func saveCatalogLocked() {
	if catalog.path == "" {
		return
	}
	list := make([]lanternLocation, 0, len(catalog.byCC))
	for _, l := range catalog.byCC {
		l.Assigned = false
		list = append(list, l)
	}
	sort.Slice(list, func(i, j int) bool { return list[i].CountryCode < list[j].CountryCode })
	if raw, err := json.Marshal(list); err == nil {
		_ = os.WriteFile(catalog.path, raw, 0600)
	}
}

// catalogSnapshot merges the remembered catalog with the live assignment.
func catalogSnapshot(assigned []*servers.Server) []lanternLocation {
	live := map[string]bool{}
	var fresh []rcommon.PreferredLocation
	for _, srv := range assigned {
		if srv == nil {
			continue
		}
		if cc := normCC(srv.Location.CountryCode); cc != "" {
			live[cc] = true
			fresh = append(fresh, srv.Location)
		}
	}
	rememberLocations(fresh)
	catalog.mu.Lock()
	defer catalog.mu.Unlock()
	out := make([]lanternLocation, 0, len(catalog.byCC))
	for cc, l := range catalog.byCC {
		l.Assigned = live[cc]
		out = append(out, l)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CountryCode < out[j].CountryCode })
	return out
}

// bestServerIn returns the best ASSIGNED server tag in the country: the
// lowest measured latency, else the first one listed. Empty when none.
func bestServerIn(all []*servers.Server, cc string) string {
	best, bestScore := "", uint32(1<<31)
	for _, srv := range all {
		if srv == nil || normCC(srv.Location.CountryCode) != cc || srv.Tag == "" {
			continue
		}
		score := uint32(1 << 30)
		if h := srv.SelectionHistory; h != nil && h.LastSuccessDelayMs > 0 {
			score = h.LastSuccessDelayMs
		}
		if best == "" || score < bestScore {
			best, bestScore = srv.Tag, score
		}
	}
	return best
}

// setPreferredCountry records the pick as Radiance's PreferredLocation (the
// config request field Lantern's server assigns by). Empty clears it (AUTO).
func setPreferredCountry(cc string) {
	cc = normCC(cc)
	if cc == "" {
		_ = settings.Clear(settings.PreferredLocationKey)
		return
	}
	loc := rcommon.PreferredLocation{CountryCode: cc}
	catalog.mu.Lock()
	if known, ok := catalog.byCC[cc]; ok {
		loc.Country = known.Country
		loc.City = known.City
	}
	catalog.mu.Unlock()
	if loc.Country == "" {
		loc.Country = cc
	}
	if err := settings.Set(settings.PreferredLocationKey, &loc); err != nil {
		slog.Warn("AETHONE: could not store the Lantern preferred location", "error", err)
	}
}

// awaitServerIn waits until the config carries a server in the country,
// asking Lantern for a fresh config (with the preferred location set) when
// the current one has none. Returns the best tag or "" on timeout.
func awaitServerIn(cc string, budget time.Duration) string {
	b := currentBackend()
	if b == nil {
		return ""
	}
	deadline := time.Now().Add(budget)
	refetched := false
	for {
		all := b.AllServers()
		if tag := bestServerIn(all, cc); tag != "" {
			return tag
		}
		// Ask once the first config is in (an empty list means Radiance is
		// still on its very first fetch, which already carries the
		// preferred location).
		if !refetched && len(all) > 0 {
			refetched = true
			go func() {
				if err := b.UpdateConfig(); err != nil {
					slog.Warn("AETHONE: Lantern config re-fetch failed", "error", err)
				}
			}()
		}
		if time.Now().After(deadline) {
			return ""
		}
		time.Sleep(300 * time.Millisecond)
	}
}

// SelectCountry switches a live (or the next) Lantern session to the best
// server in the country ("" or "AUTO" = automatic). It sets the preferred
// location first, so a country outside the current assignment is requested
// from Lantern's config server, then selects the server once it arrives.
func SelectCountry(country string) error {
	cc := normCC(country)
	if cc == "" || strings.EqualFold(country, "auto") {
		setPreferredCountry("")
		return SelectServer("")
	}
	setPreferredCountry(cc)
	tag := awaitServerIn(cc, 30*time.Second)
	if tag == "" {
		return fmt.Errorf("Lantern assigned no server in %s", cc)
	}
	return SelectServer(tag)
}

// initialTag resolves the tag a country-first connect should start on.
// AUTO (or a country Lantern never assigns within the wait) returns
// vpn.AutoSelectTag.
func initialTag(country string, budget time.Duration) string {
	cc := normCC(country)
	if cc == "" {
		setPreferredCountry("")
		return vpn.AutoSelectTag
	}
	setPreferredCountry(cc)
	if tag := awaitServerIn(cc, budget); tag != "" {
		return tag
	}
	slog.Warn("AETHONE: no Lantern server in the picked country yet, connecting on auto", "country", cc)
	return vpn.AutoSelectTag
}
