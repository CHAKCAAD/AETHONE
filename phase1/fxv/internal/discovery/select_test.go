package discovery

import (
	"strings"
	"testing"

	vpnclient "firefox-vpn-client"
)

func country(code, name string, cities ...vpnclient.City) vpnclient.Country {
	return vpnclient.Country{Code: code, Name: name, Cities: cities}
}

func city(code, name string, servers ...vpnclient.Server) vpnclient.City {
	return vpnclient.City{Code: code, Name: name, Servers: servers}
}

func server(host string, quarantined bool) vpnclient.Server {
	return vpnclient.Server{Hostname: host, Port: 2499, Quarantined: quarantined}
}

func liveList() []vpnclient.Country {
	return []vpnclient.Country{
		country("REC", "Recomended Location", city("REC", "Recomended Location", server("p.m1.fastly-masque.net", false))),
		country("US", "CatchAll Anycast", city("Q30", "CatchAll Anycast", server("p.m1.fastly-masque.net", false))),
		country("FR", "France", city("LFPB", "Paris", server("lfpb115.m1.fastly-masque.net", false))),
		country("IT", "Italy", city("MXP", "Milan", server("mxp69.m1.fastly-masque.net", true))),
		country("DE", "Germany", city("MUC", "Munich", server("muc139.m1.fastly-masque.net", false))),
	}
}

func TestSelectAutoIsRecommendedAnycast(t *testing.T) {
	sel, err := Select(liveList(), "")
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if sel.SelectionSource != "autoRec" || !sel.Recommended {
		t.Fatalf("auto must pick the REC record: %+v", sel)
	}
	if sel.Hostname != "p.m1.fastly-masque.net" {
		t.Fatalf("hostname = %q", sel.Hostname)
	}
}

func TestSelectRecKeywordIsAuto(t *testing.T) {
	sel, err := Select(liveList(), "REC")
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if sel.SelectionSource != "autoRec" {
		t.Fatalf("REC keyword must be AUTO: %+v", sel)
	}
}

func TestSelectCountryCode(t *testing.T) {
	sel, err := Select(liveList(), "de")
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if sel.Country != "DE" || sel.Hostname != "muc139.m1.fastly-masque.net" {
		t.Fatalf("country pick: %+v", sel)
	}
	if sel.SelectionSource != "country" || sel.Recommended {
		t.Fatalf("source: %+v", sel)
	}
}

func TestSelectCountryNameCaseInsensitive(t *testing.T) {
	sel, err := Select(liveList(), "france")
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if sel.Country != "FR" {
		t.Fatalf("name pick: %+v", sel)
	}
}

func TestSelectSkipsQuarantined(t *testing.T) {
	// Italy's only server is quarantined → no match.
	_, err := Select(liveList(), "IT")
	if err == nil {
		t.Fatal("a quarantined-only country must not match")
	}
}

func TestSelectNoMatchCarriesAvailable(t *testing.T) {
	_, err := Select(liveList(), "XX")
	noMatch, ok := err.(*NoMatchError)
	if !ok {
		t.Fatalf("expected NoMatchError, got %v", err)
	}
	avail := strings.Join(noMatch.Available(), ",")
	if !strings.Contains(avail, "DE") || !strings.Contains(avail, "FR") {
		t.Fatalf("available list incomplete: %s", avail)
	}
	if strings.Contains(avail, "IT") {
		t.Fatalf("quarantined-only country must not be offered: %s", avail)
	}
	if strings.Contains(avail, "REC") {
		t.Fatalf("REC is not a country: %s", avail)
	}
}

func TestModelExcludesCatchAll(t *testing.T) {
	model := Model(liveList())
	for _, loc := range model {
		if strings.Contains(loc.CountryName, "CatchAll") {
			t.Fatalf("CatchAll leaked into the model: %+v", loc)
		}
	}
}

func TestModelKeepsQuarantinedFlagged(t *testing.T) {
	model := Model(liveList())
	found := false
	for _, loc := range model {
		if loc.CountryCode == "IT" {
			found = true
			if !loc.Quarantined {
				t.Fatalf("Italy must be flagged quarantined: %+v", loc)
			}
		}
	}
	if !found {
		t.Fatal("Italy missing from the model (quarantined locations stay, flagged)")
	}
}

func TestModelRecNameNormalized(t *testing.T) {
	model := Model(liveList())
	for _, loc := range model {
		if loc.CountryCode == "REC" {
			if loc.CountryName != "Recommended Location" {
				t.Fatalf("REC name = %q", loc.CountryName)
			}
			if !loc.Recommended {
				t.Fatal("REC must be recommended")
			}
			return
		}
	}
	t.Fatal("REC missing from the model")
}

func TestDeterministicSelection(t *testing.T) {
	// Same input → same output, always (the anti-randomness decree).
	first, err := Select(liveList(), "FR")
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	for i := 0; i < 50; i++ {
		again, err := Select(liveList(), "FR")
		if err != nil {
			t.Fatalf("select %d: %v", i, err)
		}
		if again != first {
			t.Fatalf("selection is not deterministic: %+v vs %+v", again, first)
		}
	}
}

func TestHostPort(t *testing.T) {
	sel := Selection{Hostname: "h.example", Port: 2499}
	if sel.HostPort() != "h.example:2499" {
		t.Fatalf("hostport = %q", sel.HostPort())
	}
}
