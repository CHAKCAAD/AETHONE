package engine

import "testing"

func TestLoginConfigVersionMismatch(t *testing.T) {
	if _, err := ParseLoginConfig([]byte(`{"version":2,"mode":"webchannel","sessionToken":"` + hex64() + `"}`)); err == nil {
		t.Fatal("version 2 must be rejected")
	}
}

func TestLoginConfigPasswordModeRefused(t *testing.T) {
	_, err := ParseLoginConfig([]byte(`{"version":1,"mode":"password","sessionToken":"` + hex64() + `"}`))
	if err == nil {
		t.Fatal("the reserved password mode must be refused")
	}
	var cfgErr *ConfigError
	if as := asErr(err, &cfgErr); as && cfgErr.Detail != "loginModeUnsupported" {
		t.Fatalf("detail = %q", cfgErr.Detail)
	}
}

func TestLoginConfigUnknownModeRefused(t *testing.T) {
	if _, err := ParseLoginConfig([]byte(`{"version":1,"mode":"oauth","sessionToken":"` + hex64() + `"}`)); err == nil {
		t.Fatal("an unknown mode must be refused")
	}
}

func TestLoginConfigSessionTokenShape(t *testing.T) {
	cases := []struct {
		name  string
		token string
		ok    bool
	}{
		{"valid 64 hex", hex64(), true},
		{"short", strings_63hex(), false},
		{"not hex", strings_64notHex(), false},
		{"empty", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ParseLoginConfig([]byte(`{"version":1,"mode":"webchannel","sessionToken":"` + tc.token + `"}`))
			if tc.ok && err != nil {
				t.Fatalf("expected ok, got %v", err)
			}
			if !tc.ok {
				if err == nil {
					t.Fatal("expected rejection")
				}
				var cfgErr *ConfigError
				if as := asErr(err, &cfgErr); as && cfgErr.Detail != "sessionTokenInvalid" {
					t.Fatalf("detail = %q", cfgErr.Detail)
				}
			}
		})
	}
}

func TestLoginConfigDefaults(t *testing.T) {
	cfg, err := ParseLoginConfig([]byte(`{"version":1,"sessionToken":"` + hex64() + `"}`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if cfg.Mode != LoginModeWebChannel {
		t.Fatalf("mode default = %q", cfg.Mode)
	}
	if cfg.VerifyTimeoutMs != DefaultVerifyTimeoutMs {
		t.Fatalf("verify timeout default = %d", cfg.VerifyTimeoutMs)
	}
	if cfg.RetryDelayMs != DefaultRetryDelayMs {
		t.Fatalf("retry delay default = %d", cfg.RetryDelayMs)
	}
}

func TestLoginConfigBudgetClamp(t *testing.T) {
	cfg, err := ParseLoginConfig([]byte(`{"version":1,"sessionToken":"` + hex64() + `","verifyTimeoutMs":10,"retryDelayMs":100}`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if cfg.VerifyTimeoutMs != MinVerifyTimeoutMs {
		t.Fatalf("clamped verify timeout = %d", cfg.VerifyTimeoutMs)
	}
}

func TestLoginConfigNotJSON(t *testing.T) {
	if _, err := ParseLoginConfig([]byte(`nope`)); err == nil {
		t.Fatal("non-JSON login config must fail")
	}
}

func hex64() string {
	s := ""
	for i := 0; i < 64; i++ {
		s += "a"
	}
	return s
}

func strings_63hex() string { return hex64()[:63] }

func strings_64notHex() string {
	s := ""
	for i := 0; i < 64; i++ {
		s += "z"
	}
	return s
}

func asErr(err error, target **ConfigError) bool {
	if ce, ok := err.(*ConfigError); ok {
		*target = ce
		return true
	}
	return false
}
