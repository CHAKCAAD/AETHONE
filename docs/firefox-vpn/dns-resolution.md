# Firefox DNS — process-scoped resolver

Status: the Go process-scoped DNS backend, Flutter settings, and the
Android Firefox sign-in WebView proxy bridge are implemented on
`feature/firefox-guardian-psiphon-bootstrap`. CI/build and Android
device verification are tracked separately; implementation is not a
claim of device-tested success.

## Scope

The resolver is installed only inside a `libfirefoxvpn` process.
It does not change Android Private DNS, the device-wide resolver, Aether,
Psiphon, Tor, or unrelated native application traffic.

The tunnel, login, discovery, DNS-probe, and WebView-proxy roles accept
the same optional `dns` object. An omitted object is backward-compatible
and means Android System DNS.

## Modes

- `doh` with `provider: "auto"` (**the default since 1.9.0** — the
  reference's `DefaultDNSServers` + `fallback_to_system`, ported from
  arman-vpn-client `core/internal/resolver`): every IP-literal DoH
  endpoint — Cloudflare `https://1.1.1.1/dns-query`, Google
  `https://8.8.8.8/dns-query`, Quad9 `https://9.9.9.9/dns-query` — is
  queried AT ONCE and the first valid answer wins; the system resolver
  joins the race after 1 s (or at once, when every endpoint has
  errored) and its answer wins only when it is real. A filtering
  network must block ALL THREE endpoints AND answer its own DNS with
  real addresses to keep the control-plane names from resolving.
- `doh` with one provider (`cloudflare` | `google` | `quad9` |
  `custom`): RFC 8484 POST (`application/dns-message`) over HTTPS to
  the picked provider. TLS certificate and hostname validation remain
  enabled; redirects are not followed.
- `system`: keep Go's original platform resolver (an EXPLICIT pick —
  the empty/omitted dns object no longer means this). Android builds
  continue to use CGO + Bionic `getaddrinfo` under the A1 build rule.

### The block-page filter (1.9.0, the reference's `IsBlockPage` rule)

An answer whose addresses cannot be a public server's real address is
a filtering network's answer, not a resolution: private space
(RFC1918 — including Iran's block page `10.10.34.34-36`), loopback,
unspecified, link-local, and the filtering page's IPv6 block
`2001:4188:2:600:10:10:34:0/112` are STRIPPED from both the system's
and the DoH servers' answers. An answer that was ONLY block pages
never wins the race while another endpoint can still answer; the
system's block page is held as the last resort and returned only when
the endpoints' race then fails (on a filtering network only they can
give the real address). A system lookup failure (NXDOMAIN and the
like) never cancels the endpoints' race — exactly the reference's
`lookupWithSystem` state machine.

The resolver is installed as a process-local Go `net.Resolver`.

## DNS during Firefox over WARP

The Firefox VPN tunnel is carried inside the Aether/WARP outer tunnel.
Before the Go tunnel role makes its RemoteSettings, Guardian and token
refresh requests, its control-plane transport sends hostnames to the
Aether loopback SOCKS5 listener as domain targets; the H2/H3 Fastly
session uses the same mechanism. Those names are resolved by the Aether
core inside its outer tunnel, using the Aether core's own DNS settings.
The Firefox DNS choice does not override that carrier resolver during
an active Firefox-over-WARP session.

The Firefox-selected resolver remains relevant to separate processes
that run before the tunnel exists: the WebChannel sign-in exchange,
the standalone `--discover` role, the explicit `--dns-probe`, and the
embedded sign-in WebView's HTTPS CONNECT proxy. The account sign-in
and pre-connect discovery roles are not represented as tunneled by
Firefox over WARP; only the live tunnel-role control/data planes are
carried through Aether.

### 1.8.0 — the probe rides the carrier (the arman pattern)

The `--dns-probe` role gained the SAME `upstreamSocks` seam the other
roles have (the shared `dns + upstreamSocks` config line). With a
carrier the probe changes its evidence model: each control-plane
domain is dialed THROUGH the carrier BY HOSTNAME on :443 (socks5h
semantics — remote DNS at the WARP egress, exactly the path the
login/discovery/usage control-plane walks take). The local resolver is
NOT consulted — that is the point: on a network with a poisoned system
DNS and blocked DoH endpoints (the direct probes fail for every
provider), the through-carrier probe answers the question that matters
(«can the app's control plane reach Mozilla the way it will?»). Every
event and the summary carry `via: "carrier"` (`"direct"` otherwise)
so the host labels the evidence honestly. The Dart host rides a LIVE
carrier when one exists (a connected session's, or the login screen's)
and boots the login carrier only for the EXPLICIT test press — the
round-6 rule (no carrier churn on page open) stands.

## Bootstrap and split DNS

The DoH endpoint itself must be reachable before it can resolve other
names. If `bootstrapIps` is non-empty, those literal addresses are used
for the DoH server's TCP connection while TLS is still validated against
the HTTPS hostname. Otherwise the original platform resolver resolves
only the DoH endpoint hostname.

When `systemForLocalDomains` is enabled, `localhost` and `.local`
names use the captured system resolver. User-defined
`systemDomainExceptions` are suffix matches and also use system DNS.

The first implementation synthesizes A/AAAA DNS replies for system-DNS
exceptions from platform resolver results. Arbitrary TXT/SRV lookups for
those exception domains are not a supported contract.

## Embedded Firefox sign-in WebView

The Android sign-in page now uses the same selected DNS configuration
for the hostname lookup of its actual HTTPS network requests:

1. Flutter awaits restoration of the saved DNS preferences.
2. It starts the extracted `libfirefoxvpn.so --webview-proxy` child
   with an empty environment and sends the DNS object on stdin.
3. The child installs the same Go resolver as the Firefox engine, binds
   an ephemeral listener on `127.0.0.1`, and reports its address.
4. AndroidX WebKit `ProxyController` installs an HTTP proxy override.
   Flutter waits for AndroidX's completion callback before constructing
   the WebView and loading `accounts.firefox.com`.
5. For an HTTPS request, Chromium sends HTTP CONNECT to the loopback
   proxy. The Go child resolves the CONNECT hostname using the selected
   System/DoH resolver, connects to the resulting public IP on port 443,
   and relays bytes in both directions. It does not terminate or inspect
   the site's TLS session; WebView continues to validate the site's TLS
   certificate and hostname.
6. The proxy accepts CONNECT only on port 443 and rejects private,
   loopback, link-local, unspecified, and multicast destination IPs.
   There is no direct-network fallback if the proxy or DoH path fails.

The AndroidX proxy override is process-wide for WebViews in this Android
application, not attached to one WebView instance. AETHONE currently
installs it only for the Firefox sign-in flow and clears it before
stopping the Go child. The Android Activity also performs a last-resort
clear during teardown. If the WebView provider does not support
`PROXY_OVERRIDE`, sign-in initialization fails closed and the page is
not loaded directly.

### Honest DNS coverage boundary

This covers the destination-name resolution for actual HTTPS requests
that travel through the HTTP CONNECT proxy. It does **not** prove that
every DNS-related action by Chromium is routed through DoH. Chromium's
DNS-prefetch implementation can use the operating system's normal DNS
resolver outside the browser network stack, so speculative/prefetch
lookups may still use Android System DNS. WebRTC or other non-HTTP
UDP traffic is also outside this CONNECT proxy. The UI states this
prefetch limitation.

The proxy is not a TLS-interception proxy: passwords, cookies, WebChannel
messages and page contents remain encrypted end-to-end between WebView
and Mozilla. The session token is still delivered to Dart only through
the existing WebChannel bridge, then to the separate `--login` child
through its private stdin pipe.

## Caching

In-flight duplicate lookups are coalesced by Go's resolver. Successful
DoH DNS messages with answer records are additionally cached in a
bounded per-process cache using the minimum answer-section TTL (capped
at one hour). Negative answers and zero-TTL answers are not cached.

## Current evidence boundaries

- Go package tests exercise configuration validation, suffix matching,
  DNS message handling, transaction-ID preservation, TTL handling, a
  local TLS DoH endpoint, and the WebView CONNECT proxy lifecycle/relay.
- `--dns-probe` tests the same process-local resolver used by the
  engine and reports A/AAAA results for FxA, Remote Settings and Guardian.
  1.8.0: with `upstreamSocks` set it reports the through-carrier
  connect evidence instead (`via: "carrier"`, no local lookups) —
  tested against a local SOCKS5 server that accepts domain CONNECTs.
- Host tests are not evidence that every Android ABI resolves over the
  actual mobile network. Per-ABI runtime evidence still requires a device.
- Flutter settings persist the mode, provider, custom HTTPS endpoint and
  optional bootstrap IPs in SharedPreferences. The selected config is
  sent to the tunnel, login, discovery, DNS-probe, and WebView-proxy roles
  over stdin.
- A WebView sign-in on a real Android device, real account completion,
  proxy clear after Activity recreation, and end-to-end DNS observation
  are **not yet device-verified**.
- DNS success is not Guardian entitlement, OAuth success, VPN connection,
  or exit-IP verification.
