package redact

import (
	"strings"
	"testing"
)

const sentinelAccess = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
const sentinelRefresh = "9999ffff8888eeee7777dddd6666cccc5555bbbb4444aaaa333322221111"

func TestSecretsScrubbed(t *testing.T) {
	in := "oauth failed with " + sentinelAccess + " and " + sentinelRefresh
	out := Line(in, sentinelAccess, sentinelRefresh)
	if strings.Contains(out, sentinelAccess) || strings.Contains(out, sentinelRefresh) {
		t.Fatalf("leak: %s", out)
	}
	if !strings.Contains(out, Placeholder) {
		t.Fatalf("no placeholder: %s", out)
	}
}

func TestUnlistedTokenRunsMasked(t *testing.T) {
	// A rotated/partial token echo that was NOT in the scrub set is
	// still long-hex-shaped and must be masked.
	unlisted := "0123456789abcdef0123456789abcdef01234567"
	out := Line("rotated value: " + unlisted)
	if strings.Contains(out, unlisted) {
		t.Fatalf("unlisted run leaked: %s", out)
	}
}

func TestNormalTextUntouched(t *testing.T) {
	in := "lookup api.accounts.firefox.com on [::1]:53: connection refused"
	out := Line(in, sentinelAccess, sentinelRefresh)
	if out != in {
		t.Fatalf("ordinary diagnostic must pass through: %q", out)
	}
}

func TestEmptySecretsIgnored(t *testing.T) {
	in := "plain"
	if out := Line(in, "", ""); out != in {
		t.Fatalf("empty scrub set changed the line: %q", out)
	}
}

func TestMarkerStays(t *testing.T) {
	out := Line("value " + sentinelAccess, sentinelAccess)
	if !strings.Contains(out, "[REDACTED]") {
		t.Fatalf("marker missing: %s", out)
	}
}
