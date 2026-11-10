package upstream

// renewalFailCode unit tests — the guardian-bootstrap Stage 1 renewal
// seam: the renewal loop's OnRenewalFail callback now carries the fferr
// class of the SAME failure the initial-pass walk would classify
// (classifyGuardian in cmd/libfirefoxvpn), the Guardian 451 region class
// included, so the host can tell a region block from a DNS/timeout/
// auth failure while the pass renews.

import (
        "context"
        "errors"
        "net"
        "net/url"
        "testing"

        vpnclient "firefox-vpn-client"
)

func TestRenewalFailCode(t *testing.T) {
        dnsErr := &url.Error{Op: "Get", URL: "https://vpn.mozilla.org/api/v1/fpn/token",
                Err: &net.OpError{Op: "dial", Net: "tcp",
                        Err: &net.DNSError{Err: "no such host", Name: "vpn.mozilla.org", IsNotFound: true}}}

        cases := []struct {
                name string
                err  error
                want string
        }{
                {"guardian 451 region body", &vpnclient.GuardianHTTPError{Operation: "guardian", StatusCode: 451, Body: `{"error":"unavailable_in_region"}`}, "guardianRegionUnavailable"},
                {"guardian 451 empty body", &vpnclient.GuardianHTTPError{Operation: "guardian", StatusCode: 451, Body: ""}, "guardianRegionUnavailable"},
                {"guardian 451 other structured reason", &vpnclient.GuardianHTTPError{Operation: "guardian", StatusCode: 451, Body: `{"error":"maintenance"}`}, "serverRejection"},
                {"guardian 503", &vpnclient.GuardianHTTPError{Operation: "guardian", StatusCode: 503, Body: ""}, "serverRejection"},
                {"token-invalid sentinel", vpnclient.ErrTokenInvalid, "sessionRejected"},
                {"dns transport class", dnsErr, "dnsError"},
                {"deadline transport class", context.DeadlineExceeded, "timeout"},
                {"unclassifiable", errors.New("mystery"), ""},
        }
        for _, tc := range cases {
                got := renewalFailCode(tc.err)
                if got != tc.want {
                        t.Fatalf("%s: renewalFailCode = %q, want %q", tc.name, got, tc.want)
                }
                t.Logf("%s -> %q", tc.name, got)
        }
}
