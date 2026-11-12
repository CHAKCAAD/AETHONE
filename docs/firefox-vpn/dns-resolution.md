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

- `system` (default): keep Go's original platform resolver. Android
  builds continue to use CGO + Bionic `getaddrinfo` under the A1
  build rule; the DNS feature does not replace that path.
- `doh`: use RFC 8484 POST (`application/dns-message`) over
  HTTPS. Supported provider IDs are `cloudflare`, `google`,
  `quad9`, and `custom`. TLS certificate and hostname validation
  remain enabled; redirects are not followed.

The resolver is installed as a process-local Go `net.Resolver`.
DoH failures do not silently fall back to ordinary DNS.

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
