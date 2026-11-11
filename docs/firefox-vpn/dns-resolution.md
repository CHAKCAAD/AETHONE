# Firefox DNS — process-scoped resolver

Status: Go resolver backend is being integrated on the dedicated
Firefox feature branch. Flutter settings/persistence and the Android
WebView proxy bridge are separate follow-up steps; until those land,
the UI does not claim that WebView login follows the selected DoH mode.

## Scope

This resolver is installed only inside a `libfirefoxvpn` process.
It does not change Android Private DNS, the device-wide resolver, Aether,
Psiphon, Tor, or unrelated application traffic.

The tunnel, login, discovery, and DNS-probe roles accept an optional
`dns` object. An omitted object is backward-compatible and means
Android System DNS.

## Modes

- `system` (default): keep Go's original platform resolver. Android
  builds continue to use CGO + Bionic `getaddrinfo` under the A1
  build rule; the DNS feature does not replace that known-good path.
- `doh`: use RFC 8484 POST (`application/dns-message`) over
  HTTPS. Supported provider IDs are `cloudflare`, `google`,
  `quad9`, and `custom`. TLS certificate and hostname
  validation remain enabled; redirects are not followed.

The resolver uses a process-local `net.Resolver` (`PreferGo` is
scoped to that resolver), and therefore covers the Firefox engine's
`net.Dialer` and `net.DefaultResolver` calls without changing
the system resolver used by other processes.

## Bootstrap and split DNS

The DoH endpoint itself must be reachable before it can resolve other
names. If `bootstrapIps` is non-empty, those literal addresses are
used for the DoH server's TCP connection while TLS is still validated
against the HTTPS hostname. Otherwise the original platform resolver
resolves only the DoH endpoint hostname.

When `systemForLocalDomains` is enabled, `localhost` and
`.local` names use the captured system resolver. User-defined
`systemDomainExceptions` are suffix matches and also use system
DNS. Other names use DoH. A DoH failure does not silently fall back to
system DNS; the request fails visibly.

The first implementation synthesizes A/AAAA DNS replies for system-DNS
exceptions from the platform resolver results. The engine's hostname
connect path needs A/AAAA; arbitrary TXT/SRV lookups for those exception
domains are not a supported contract.

## Caching

In-flight duplicate lookups are coalesced by Go's resolver. Successful
DoH DNS messages with answer records are additionally cached in a
bounded per-process cache using the minimum answer-section TTL (capped
at one hour). Negative answers and zero-TTL answers are not cached.

## Current evidence boundaries

- Go package tests exercise configuration validation, suffix matching,
  DNS message handling, transaction-ID preservation, TTL handling, and
  a local TLS DoH endpoint using a test-only trust store.
- `--dns-probe` tests the same process-local resolver used by the
  engine and reports A/AAAA results for FxA, Remote Settings and Guardian.
- Host tests are not evidence that every Android ABI resolves over the
  actual mobile network. Per-ABI runtime evidence still requires a device.
- The login WebView is NOT yet covered by this Go resolver. Its next step
  uses an app-scoped AndroidX WebView proxy override plus a loopback
  CONNECT proxy; it must await proxy activation and clear the override
  on every exit path before the selected DNS mode can be claimed to cover
  the browser page.
- DNS success is not Guardian entitlement, OAuth success, VPN connection,
  or exit-IP verification.
