// Package redact scrubs secret values from every string that leaves the
// engine (stderr logs, event messages, classified internals). It is NEW
// AETHONE code (Phase 1, rebuilt 2026-11-09).
//
// The scrub set is the caller's secret values (access/refresh/session
// tokens). Redaction is belt-and-braces: the engine never intentionally
// writes a secret anywhere but the stdin pipe (in) and the
// authRefreshed / loginCompleted events (out) — this package exists so
// an accidental echo in an error chain still cannot leak it.
package redact

import "strings"

// Placeholder replaces every scrubbed secret.
const Placeholder = "[REDACTED]"

// Line rewrites s with every non-empty secret in secrets replaced by
// the placeholder. Long hex-ish token runs that were NOT in the scrub
// set (a rotated value, a partial echo) are masked too: any run of
// ≥24 characters drawn from [0-9a-fA-F._-] is treated as secret-shaped.
func Line(s string, secrets ...string) string {
	for _, secret := range secrets {
		if secret == "" {
			continue
		}
		s = strings.ReplaceAll(s, secret, Placeholder)
	}
	s = maskTokenRuns(s)
	return s
}

// maskTokenRuns masks long token-shaped runs (hex / base64url-ish)
// that escaped the explicit scrub set.
func maskTokenRuns(s string) string {
	var b strings.Builder
	i := 0
	for i < len(s) {
		j := tokenRunEnd(s, i)
		if j-i >= 24 {
			b.WriteString(Placeholder)
		} else {
			b.WriteString(s[i:j])
		}
		i = j
	}
	return b.String()
}

func tokenRunEnd(s string, i int) int {
	j := i
	for j < len(s) && isTokenByte(s[j]) {
		j++
	}
	if j == i {
		j++ // not a token byte; emit it as-is
	}
	return j
}

func isTokenByte(c byte) bool {
	switch {
	case c >= '0' && c <= '9':
		return true
	case c >= 'a' && c <= 'f':
		return true
	case c >= 'A' && c <= 'F':
		return true
	case c == '_' || c == '-' || c == '.':
		return true
	}
	return false
}
