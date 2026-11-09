// Part 3 — OAuth token response guard.
//
// Success requires BOTH access_token and refresh_token to be:
//
//	present as JSON fields, JSON type string, non-empty, non-blank
//	(blank = only Unicode whitespace). No token format is invented or
//	validated beyond string-ness — per the directive, we never guess the
//	token format.
//
// On any violation the guard returns a typed error carrying
// CodeInvalidTokenResp; the engine maps it through ClassifyTransport/
// ClassifyHTTP-adjacent handling to the SAME JSON shape as other codes,
// so Dart receives `invalidTokenResponse` like any other class.
package fferr

import (
	"encoding/json"
	"fmt"
	"strings"
)

// GuardError is the typed failure of the token guard.
type GuardError struct {
	Reason string // machine-readable, static; no token values
}

func (e *GuardError) Error() string {
	return "invalid token response: " + e.Reason
}

// Code ties GuardError into the shared contract.
func (e *GuardError) Classified() Classified {
	return Classified{
		Code:      CodeInvalidTokenResp,
		Message:   msg[CodeInvalidTokenResp],
		Retryable: false,
		Internal:  e.Error(),
	}
}

// TokenPair is the ONLY sanctioned output of a successful exchange.
type TokenPair struct {
	AccessToken  string `json:"-"`
	RefreshToken string `json:"-"`
}

// ValidateTokenResponse enforces the Part 3 rules on raw JSON bytes.
//
// Field names: `access_token` / `refresh_token` follow the FxA OAuth
// token-endpoint shape observed in the engine's exchange URL
// (https://api.accounts.firefox.com/v1/oauth/token). If the private
// repo's engine parses different/extra fields (e.g. `expires_in`,
// `scope`, `token_type`, `sessionToken`), port this guard onto the
// engine's existing struct — the rules below stay identical.
func ValidateTokenResponse(raw []byte) (TokenPair, error) {
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		return TokenPair{}, &GuardError{Reason: "body is not valid JSON"}
	}

	access, err := requireToken(doc, "access_token")
	if err != nil {
		return TokenPair{}, err
	}
	refresh, err := requireToken(doc, "refresh_token")
	if err != nil {
		return TokenPair{}, err
	}
	return TokenPair{AccessToken: access, RefreshToken: refresh}, nil
}

// requireToken checks ONE field: present → not null → JSON string →
// non-empty → non-blank. Wrong JSON type (number/object/bool) is its own
// reason; JSON null gets its own reason too.
func requireToken(doc map[string]json.RawMessage, field string) (string, error) {
	raw, ok := doc[field]
	if !ok {
		return "", &GuardError{Reason: fmt.Sprintf("field %q is missing", field)}
	}
	if strings.TrimSpace(string(raw)) == "null" {
		return "", &GuardError{Reason: fmt.Sprintf("field %q is null", field)}
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return "", &GuardError{Reason: fmt.Sprintf("field %q is not a JSON string", field)}
	}
	if s == "" {
		return "", &GuardError{Reason: fmt.Sprintf("field %q is empty", field)}
	}
	if strings.TrimSpace(s) == "" {
		return "", &GuardError{Reason: fmt.Sprintf("field %q is blank (whitespace only)", field)}
	}
	return s, nil
}
