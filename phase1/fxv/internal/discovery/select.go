// Package discovery — the AETHONE selection policy on the LIVE Mozilla
// RemoteSettings server list (fetched by the pinned upstream's
// vpnclient.FetchServerList with the uTLS Firefox ClientHello).
//
// Policy (docs/FIREFOX_VPN_SERVER_DISCOVERY.md, the phase-0 decrees):
//   - the ONLY source of truth is the live RemoteSettings collection;
//   - "CatchAll Anycast" records are EXCLUDED (the MIT reference's
//     EXCLUDED_COUNTRY_NAMES rule);
//   - quarantined servers are excluded from SELECTION (kept in the
//     --discover model, flagged, never selected);
//   - country "" or "REC" = AUTO = the recommended anycast record
//     (selectionSource "autoRec");
//   - a country filter matches code or name, case-insensitive,
//     DETERMINISTICALLY (first match in list order — the upstream's
//     anti-randomness decree; no random choice exists here);
//   - no match → ErrNoMatchForCountry carrying the available codes.
//
// This package is NEW AETHONE policy code wrapping the upstream types.
package discovery

import (
        "fmt"
        "sort"
        "strings"

        vpnclient "firefox-vpn-client"
)

// CatchAllName is the pseudo-country the phase-0 policy excludes.
const CatchAllName = "CatchAll Anycast"

// RecommendedCode is the pseudo-country code of the anycast record.
const RecommendedCode = "REC"

// Location is the engine's normalized location record — the shape the
// --discover role serializes (mirrored by FirefoxLocation on the Dart
// side; the field names are the frozen contract).
type Location struct {
        CountryCode    string `json:"countryCode"`
        CountryName    string `json:"countryName"`
        CityCode       string `json:"cityCode"`
        CityName       string `json:"cityName"`
        ServerHostname string `json:"serverHostname"`
        ServerPort     int    `json:"serverPort"`
        Quarantined    bool   `json:"quarantined"`
        Recommended    bool   `json:"recommended"`
}

// Selection is one selected upstream (the `selected` event payload).
type Selection struct {
        Country         string
        CountryName     string
        CityCode        string
        CityName        string
        Hostname        string
        Port            int
        SelectionSource string // autoRec | country | override
        Recommended     bool
}

// Model converts the live country list into the engine's location
// model (CatchAll excluded; quarantined kept but flagged; REC flagged
// recommended). The --discover role serializes this.
func Model(countries []vpnclient.Country) []Location {
        var out []Location
        for _, c := range countries {
                if isCatchAll(c) {
                        continue
                }
                rec := strings.EqualFold(c.Code, RecommendedCode)
                for _, city := range c.Cities {
                        for _, srv := range city.Servers {
                                out = append(out, Location{
                                        CountryCode:    c.Code,
                                        CountryName:    CountryDisplayName(c),
                                        CityCode:       city.Code,
                                        CityName:       city.Name,
                                        ServerHostname: srv.Hostname,
                                        ServerPort:     srv.Port,
                                        Quarantined:    srv.Quarantined,
                                        Recommended:    rec,
                                })
                        }
                }
        }
        return out
}

// isCatchAll matches the pseudo-country record the policy excludes
// (name "CatchAll Anycast", whatever its code/city).
func isCatchAll(c vpnclient.Country) bool {
        return strings.EqualFold(strings.TrimSpace(c.Name), CatchAllName)
}

// CountryDisplayName normalizes the REC record's misspelled official
// name ("Recomended Location") to "Recommended Location"; every other
// name passes through as-is.
func CountryDisplayName(c vpnclient.Country) string {
        if strings.EqualFold(c.Code, RecommendedCode) &&
                strings.Contains(strings.ToLower(c.Name), "recomend") {
                return "Recommended Location"
        }
        return c.Name
}

// NoMatchError carries the available country codes for the
// noMatchForCountry failure (the `failed` event message lists them so
// the host can surface an honest picker).
type NoMatchError struct {
        Requested      string
        AvailableCodes []string
}

func (e *NoMatchError) Error() string {
        return fmt.Sprintf("no location matches %q (available: %s)",
                e.Requested, strings.Join(e.Available(), ", "))
}

// Available returns the sorted distinct selectable country codes
// (REC excluded — it is not a country).
func (e *NoMatchError) Available() []string {
        return DistinctCountryCodes(e.AvailableCodes)
}

// DistinctCountryCodes lists the sorted distinct real country codes in
// the model (CatchAll excluded upstream of the model, REC excluded
// here, quarantined-only countries excluded).
func DistinctCountryCodes(codes []string) []string {
        seen := map[string]bool{}
        var out []string
        for _, code := range codes {
                upper := strings.ToUpper(strings.TrimSpace(code))
                if upper == "" || upper == RecommendedCode || seen[upper] {
                        continue
                }
                seen[upper] = true
                out = append(out, upper)
        }
        sort.Strings(out)
        return out
}

// CountriesWithSelectableServers returns the distinct country codes
// that have at least one NON-quarantined server.
func CountriesWithSelectableServers(countries []vpnclient.Country) []string {
        var codes []string
        for _, c := range countries {
                if isCatchAll(c) || strings.EqualFold(c.Code, RecommendedCode) {
                        continue
                }
                for _, city := range c.Cities {
                        usable := false
                        for _, srv := range city.Servers {
                                if !srv.Quarantined {
                                        usable = true
                                        break
                                }
                        }
                        if usable {
                                codes = append(codes, c.Code)
                                break
                        }
                }
        }
        return DistinctCountryCodes(codes)
}

// Select applies the policy. country "" or "REC" selects the
// recommended anycast record (autoRec). Otherwise the deterministic
// first match on code or name (case-insensitive) among countries with
// at least one non-quarantined server.
func Select(countries []vpnclient.Country, country string) (Selection, error) {
        filter := strings.TrimSpace(country)
        if filter == "" || strings.EqualFold(filter, RecommendedCode) {
                return selectRecommended(countries)
        }
        for _, c := range countries {
                if isCatchAll(c) {
                        continue
                }
                if !countryMatches(c, filter) {
                        continue
                }
                for _, city := range c.Cities {
                        for _, srv := range city.Servers {
                                if srv.Quarantined {
                                        continue
                                }
                                return Selection{
                                        Country:         strings.ToUpper(c.Code),
                                        CountryName:     CountryDisplayName(c),
                                        CityCode:        city.Code,
                                        CityName:        city.Name,
                                        Hostname:        srv.Hostname,
                                        Port:            srv.Port,
                                        SelectionSource: "country",
                                        Recommended:     false,
                                }, nil
                        }
                }
        }
        return Selection{}, &NoMatchError{
                Requested:     filter,
                AvailableCodes: CountriesWithSelectableServers(countries),
        }
}

// selectRecommended finds the REC record and its first server. A
// quarantined REC server is still used (the anycast record is a single
// hostname; the flag is reported, never fatal for AUTO — the upstream
// p.m1.fastly-masque.net is the anycast front door).
func selectRecommended(countries []vpnclient.Country) (Selection, error) {
        for _, c := range countries {
                if isCatchAll(c) {
                        continue
                }
                if !strings.EqualFold(c.Code, RecommendedCode) {
                        continue
                }
                for _, city := range c.Cities {
                        for _, srv := range city.Servers {
                                return Selection{
                                        Country:         RecommendedCode,
                                        CountryName:     CountryDisplayName(c),
                                        CityCode:        city.Code,
                                        CityName:        city.Name,
                                        Hostname:        srv.Hostname,
                                        Port:            srv.Port,
                                        SelectionSource: "autoRec",
                                        Recommended:     true,
                                }, nil
                        }
                }
        }
        return Selection{}, &NoMatchError{
                Requested:     "REC (auto)",
                AvailableCodes: CountriesWithSelectableServers(countries),
        }
}

// countryMatches: ISO-3166-1 alpha-2 code or English name,
// case-insensitive, trimmed.
func countryMatches(c vpnclient.Country, filter string) bool {
        if strings.EqualFold(strings.TrimSpace(c.Code), filter) {
                return true
        }
        return strings.EqualFold(strings.TrimSpace(c.Name), filter)
}

// HostPort renders the selection as the upstream dial target.
func (s Selection) HostPort() string {
        return fmt.Sprintf("%s:%d", s.Hostname, s.Port)
}
