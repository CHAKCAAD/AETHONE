# AETHONE — CLI Reference of the Pinned Aether Commit

Generated **programmatically** from the pinned source (no hand-typed line numbers).
Source: `aether/src/cli.rs` @ commit `d58f9d568083129ce2c767c85054021eb3ee6a38`
(Aether 2.4.0), sha256 `c974d7f1…`; byte-identity of all six anchor files vs the live
commit is proven in `evidence/protocol_surface_pinned_commit_v43.txt`.

**v4.4:** one duplicated `RUST_LOG` row (both occurrences `L533`) removed;
environment-only variables = **28 distinct** (machine recount, assertion-checked in
`evidence/validation_v44_changes.txt`). Parser-arm table unchanged (113 arms).

Reading rules:
- **Line(L)** = line number in `aether/src/cli.rs` at the pinned commit (parser arm / USAGE text).
- Every flag sets one environment variable (`set`), or adds to it (`append` = repeatable).
- A flag **beats** its environment variable; either one stops the interactive question (USAGE L11–14).
- Statuses: *CLI attested* means the option exists in the pinned source — **not** a runtime capability proof (runtime on Android: `NOT TESTED`).

Totals: **113 parser arms** mapping **90 distinct flag-driven environment variables**, plus **28 environment-only variables** (v4.4 recount; the v4.3 file listed 29 rows with `RUST_LOG` duplicated); USAGE text spans cli.rs L3–542.

## Connection

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 1 | `--bind` | `AETHER_SOCKS` | set | `next_value!()` | L581 | L23 |
| 2 | `--http-proxy` | `AETHER_HTTP_PROXY` | set | `next_value!()` | L582 | L24 |
| 3 | `--upstream` | `AETHER_UPSTREAM` | set | `next_value!()` | L583 | L26 |
| 4 | `--mark` | `AETHER_MARK` | set | `next_value!()` | L612 | L30 |
| 5 | `--exit-loc` | `AETHER_EXIT_LOC` | set | `next_value!()` | L613 | L37 |
| 6 | `--exit-loc-secs` | `AETHER_EXIT_LOC_SECS` | set | `next_value!()` | L614 | L42 |
| 7 | `--stats` | `AETHER_STATS` | set | `1` | L615 | L43 |
| 8 | `--stats-secs` | `AETHER_STATS_SECS` | set | `next_value!()` | L616 | L45 |
| 9 | `--quick-reconnect` | `AETHER_QUICK_RECONNECT` | set | `1` | L617 | L46 |
| 10 | `--no-quick-reconnect` | `AETHER_QUICK_RECONNECT` | set | `0` | L618 | L47 |
| 11 | `-4` | `AETHER_IP` | set | `v4` | L620 | L48 |
| 12 | `-6` | `AETHER_IP` | set | `v6` | L621 | L49 |
| 13 | `--dual` | `AETHER_IP` | set | `both` | L622 | L50 |
| 14 | `--ip` | `AETHER_IP` | set | `next_value!()` | L623 | L51 |
| 15 | `--peer` | `AETHER_PEER` | set | `next_value!()` | L625 | L52 |
| 16 | `--wg-peer` | `AETHER_WG_PEER` | set | `next_value!()` | L626 | L53 |

## Protocol

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 17 | `--masque` | `AETHER_PROTOCOL` | set | `masque` | L637 | L56 |
| 18 | `--wg`, `--wireguard`, `--warp` | `AETHER_PROTOCOL` | set | `wg` | L638 | L57 |
| 19 | `--gool`, `--wiw` | `AETHER_PROTOCOL` | set | `gool` | L639 | L59 |
| 20 | `--mim`, `--masque-in-masque` | `AETHER_PROTOCOL` | set | `mim` | L648 | L69 |
| 21 | `--protocol` | `AETHER_PROTOCOL` | set | `next_value!()` | L653 | L74 |

## GOOL Classic (WARP-in-WARP) endpoints

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 22 | `--wiw-peers`, `--gool-peers` | `AETHER_WIW_PEERS` | set | `next_value!()` | L634 | L86 |
| 23 | `--wiw-scan`, `--gool-scan` | `AETHER_WIW_PEERS` | set | `auto` | L635 | L87 |

## MASQUE-in-MASQUE (MIM) endpoints

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 24 | `--mim-outer` | `AETHER_MIM_OUTER_PEER` | set | `next_value!()` | L649 | L94 |
| 25 | `--mim-inner` | `AETHER_MIM_INNER_PEER` | set | `next_value!()` | L650 | L95 |
| 26 | `--mim-peers` | `AETHER_MIM_PEERS` | set | `next_value!()` | L651 | L96 |
| 27 | `--mim-scan` | `AETHER_MIM_PEERS` | set | `auto` | L652 | L97 |

## Scan mode

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 28 | `--scan` | `AETHER_SCAN` | set | `next_value!()` | L655 | L101 |
| 29 | `--turbo` | `AETHER_SCAN` | set | `turbo` | L656 | L102 |
| 30 | `--balanced` | `AETHER_SCAN` | set | `balanced` | L657 | L103 |
| 31 | `--thorough` | `AETHER_SCAN` | set | `thorough` | L658 | L104 |
| 32 | `--verified`, `--stealth` | `AETHER_SCAN` | set | `verified` | L659 | L105 |
| 33 | `--ironclad` | `AETHER_SCAN` | set | `ironclad` | L660 | L109 |

## Obfuscation

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 34 | `--noize` | `AETHER_NOIZE` | set | `next_value!()` | L662 | L114 |

## MASQUE transport

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 35 | `--h2`, `--http2` | `AETHER_MASQUE_HTTP2` | set | `1` | L664 | L120 |
| 36 | `--h3`, `--quic` | `AETHER_MASQUE_HTTP2` | set | `0` | L665 | L121 |
| 37 | `--no-quic-v2` | `AETHER_QUIC_V2` | set | `0` | L666 | L122 |
| 38 | `--h2-peer` | `AETHER_MASQUE_H2_PEER` | set | `next_value!()` | L667 | L125 |
| 39 | `--startup-secs` | `AETHER_MASQUE_STARTUP_SECS` | set | `next_value!()` | L681 | L128 |
| 40 | `--dns` | `AETHER_DNS` | set | `next_value!()` | L687 | L130 |
| 41 | `--fragment` | `AETHER_MASQUE_H2_FRAGMENT` | set | `1` | L688 | L131 |
| 42 | `--fragment-size` | `AETHER_MASQUE_H2_FRAGMENT_SIZE` | set | `next_value!()` | L689 | L136 |
| 43 | `--fragment-delay` | `AETHER_MASQUE_H2_FRAGMENT_DELAY` | set | `next_value!()` | L690 | L137 |

## TLS

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 44 | `--masque-sni` | `AETHER_MASQUE_SNI` | set | `next_value!()` | L668 | L144 |
| 45 | `--ech` | `AETHER_ECH` | set | `next_value!()` | L669 | L154 |
| 46 | `--ech-dns` | `AETHER_ECH_DNS` | set | `next_value!()` | L670 | L159 |
| 47 | `--ech-domain` | `AETHER_ECH_DOMAIN` | set | `next_value!()` | L671 | L167 |
| 48 | `--tls-groups` | `AETHER_TLS_GROUPS` | set | `next_value!()` | L714 | L179 |
| 49 | `--tls-key-shares` | `AETHER_TLS_KEY_SHARES` | set | `next_value!()` | L715 | L180 |
| 50 | `--tls-ciphers` | `AETHER_TLS_CIPHERS` | set | `next_value!()` | L716 | L169 |
| 51 | `--tls13-ciphers` | `AETHER_TLS13_CIPHERS` | set | `next_value!()` | L717 | L174 |
| 52 | `--disable-grease` | `AETHER_DISABLE_GREASE` | set | `1` | L718 | L184 |
| 53 | `--enable-grease-sigalgs` | `AETHER_ENABLE_GREASE_SIGALGS` | set | `1` | L719 | L187 |
| 54 | `--tls-sigalgs` | `AETHER_TLS_SIGALGS` | set | `next_value!()` | L720 | L189 |
| 55 | `--tls-cert-compression` | `AETHER_TLS_CERT_COMPRESSION` | set | `next_value!()` | L721 | L195 |
| 56 | `--tls-alps` | `AETHER_TLS_ALPS` | set | `next_value!()` | L722 | L200 |
| 57 | `--tls-trust-anchors` | `AETHER_TLS_TRUST_ANCHORS` | set | `next_value!()` | L723 | L203 |
| 58 | `--tls-server-padding` | `AETHER_TLS_SERVER_PADDING` | set | `next_value!()` | L724 | L207 |
| 59 | `--enable-ech-grease` | `AETHER_ENABLE_ECH_GREASE` | set | `1` | L725 | L209 |
| 60 | `--disable-ocsp-stapling` | `AETHER_DISABLE_OCSP_STAPLING` | set | `1` | L726 | L211 |
| 61 | `--disable-sct` | `AETHER_DISABLE_SCT` | set | `1` | L727 | L212 |
| 62 | `--disable-session-ticket` | `AETHER_DISABLE_SESSION_TICKET` | set | `1` | L728 | L214 |
| 63 | `--disable-extension-permutation` | `AETHER_DISABLE_EXTENSION_PERMUTATION` | set | `1` | L729 | L215 |
| 64 | `--tls-verify` | `AETHER_TLS_VERIFY` | set | `1` | L730 | L151 |

## WireGuard

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 65 | `--keepalive` | `AETHER_WG_KEEPALIVE` | set | `next_value!()` | L692 | L220 |
| 66 | `--no-profile-retry` | `AETHER_WG_NO_PROFILE_RETRY` | set | `1` | L693 | L221 |

## Tor

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 67 | `--tor` | `AETHER_TOR` | set | `chain` | L584 | L227 |
| 68 | `--tor-reverse` | `AETHER_TOR` | set | `reverse` | L585 | L232 |
| 69 | `--tor-only` | `AETHER_TOR` | set | `only` | L586 | L238 |
| 70 | `--tor-bridge` | `AETHER_TOR_BRIDGES` | append | `next_value!()` | L587 | L303 |
| 71 | `--tor-bridges` | `AETHER_TOR_BRIDGES` | set | `auto` | L588 | L301 |
| 72 | `--no-tor-bridges` | `AETHER_TOR_BRIDGES` | set | `off` | L592 | L302 |
| 73 | `--tor-bridge-file` | `AETHER_TOR_BRIDGE_FILE` | set | `next_value!()` | L589 | L243 |
| 74 | `--tor-relays` | `AETHER_TOR_RELAYS` | set | `next_value!()` | L590 | L245 |
| 75 | `--tor-relay-ports` | `AETHER_TOR_RELAY_PORTS` | set | `next_value!()` | L591 | L251 |
| 76 | `--tor-pt` | `AETHER_TOR_PT` | append | `next_value!()` | L593 | L306 |
| 77 | `--tor-pt-dir` | `AETHER_TOR_PT_DIR` | append | `next_value!()` | L594 | L309 |
| 78 | `--tor-bind` | `AETHER_TOR_BIND` | set | `next_value!()` | L595 | L239 |
| 79 | `--tor-http` | `AETHER_TOR_HTTP` | set | `next_value!()` | L596 | L241 |
| 80 | `--tor-dir` | `AETHER_TOR_DIR` | set | `next_value!()` | L597 | L255 |
| 81 | `--psiphon` | `AETHER_PSIPHON` | set | `chain` | L598 | L258 |
| 82 | `--psiphon-reverse` | `AETHER_PSIPHON` | set | `reverse` | L599 | L260 |
| 83 | `--psiphon-only` | `AETHER_PSIPHON` | set | `only` | L600 | L264 |
| 84 | `--psiphon-config` | `AETHER_PSIPHON_CONFIG` | set | `next_value!()` | L601 | L268 |
| 85 | `--psiphon-bind` | `AETHER_PSIPHON_BIND` | set | `next_value!()` | L602 | L282 |
| 86 | `--psiphon-http` | `AETHER_PSIPHON_HTTP` | set | `next_value!()` | L603 | L284 |
| 87 | `--psiphon-region` | `AETHER_PSIPHON_REGION` | set | `next_value!()` | L604 | L285 |
| 88 | `--psiphon-mode` | `AETHER_PSIPHON_MODE` | set | `next_value!()` | L605 | L265 |
| 89 | `--psiphon-cdn-ips` | `AETHER_PSIPHON_CDN_IPS` | set | `next_value!()` | L606 | L271 |
| 90 | `--psiphon-cdn-sni` | `AETHER_PSIPHON_CDN_SNI` | set | `next_value!()` | L607 | L274 |
| 91 | `--psiphon-cdn-sets` | `AETHER_PSIPHON_CDN_SETS` | set | `next_value!()` | L608 | L275 |
| 92 | `--psiphon-dir` | `AETHER_PSIPHON_DIR` | set | `next_value!()` | L609 | L287 |
| 93 | `--psiphon-bin` | `AETHER_PSIPHON_BIN` | set | `next_value!()` | L610 | L289 |
| 94 | `--psiphon-server-entries` | `AETHER_PSIPHON_SERVER_ENTRIES` | set | `next_value!()` | L611 | L291 |

## Zero Trust (WARP for organizations)

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 95 | `--team`, `--organization` | `AETHER_TEAM` | set | `next_value!()` | L703 | L312 |
| 96 | `--access-id` | `AETHER_ACCESS_CLIENT_ID` | set | `next_value!()` | L704 | L313 |
| 97 | `--access-secret` | `AETHER_ACCESS_CLIENT_SECRET` | set | `next_value!()` | L705 | L314 |
| 98 | `--access-token` | `AETHER_ACCESS_TOKEN` | set | `next_value!()` | L706 | L316 |
| 99 | `--access-email` | `AETHER_ACCESS_EMAIL` | set | `next_value!()` | L707 | L315 |
| 100 | `--gateway` | `AETHER_GATEWAY` | set | `1` | L708 | L318 |

## Routing

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 101 | `--route-block` | `AETHER_ROUTE_BLOCK` | set | `next_value!()` | L710 | L323 |
| 102 | `--route-direct` | `AETHER_ROUTE_DIRECT` | set | `next_value!()` | L711 | L324 |
| 103 | `--routes` | `AETHER_ROUTES_FILE` | set | `next_value!()` | L712 | L325 |

## Config files

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 104 | `--config` | `AETHER_CONFIG` | set | `next_value!()` | L695 | L339 |
| 105 | `--wg-config` | `AETHER_WG_CONFIG` | set | `next_value!()` | L696 | L340 |
| 106 | `--masque-config` | `AETHER_MASQUE_CONFIG` | set | `next_value!()` | L697 | L341 |
| 107 | `--register` | `AETHER_REGISTER` | set | `next_value!()` | L698 | L344 |
| 108 | `--api-address` | `AETHER_API_ADDRESS` | set | `next_value!()` | L699 | L357 |
| 109 | `--api-sni` | `AETHER_API_SNI` | set | `next_value!()` | L700 | L364 |
| 110 | `--api-host` | `AETHER_API_HOST` | set | `next_value!()` | L701 | L367 |

## Advanced

| # | Flag(s) | Env var | Mode | Literal value set | cli.rs parser L | USAGE L |
|---|---|---|---|---|---|---|
| 111 | `--perf` | `AETHER_PERF_PROFILE` | set | `next_value!()` | L731 | L377 |
| 112 | `--log-level` | `AETHER_LOG_LEVEL` | set | `next_value!()` | L732 | L379 |
| 113 | `--verbose` | `AETHER_LOG_LEVEL` | set | `debug` | L733 | L383 |

## Environment-only variables (no flag of their own)

| # | Env var | Meaning (USAGE text) | USAGE L |
|---|---|---|---|
| 1 | `AETHER_PSIPHON_READY_SECS` | how long to wait for psiphon to tunnel (180) | L423 |
| 2 | `AETHER_TOR_DIRECT_SECS` | how long to try tor plainly before bridges (75) | L425 |
| 3 | `AETHER_TOR_STALL_SECS` | give up on a bridge after this long with no headway, however far it got (75) | L426 |
| 4 | `AETHER_TOR_BRIDGE_SECS` | the longest any one bridge may take (360) | L428 |
| 5 | `AETHER_TOR_COUNTRY` | ask bridgedb for this country, e.g. ir | L429 |
| 6 | `AETHER_TOR_CHECK` | host:port tor must reach before it counts as working (check.torproject.org:443) | L430 |
| 7 | `AETHER_TOR_LOG` | how loud tor is: info, debug or trace | L432 |
| 8 | `AETHER_GOOL_INNER` | --gool-peer | L438 |
| 9 | `AETHER_GOOL_MODE` | classic for --gool-classic | L439 |
| 10 | `AETHER_WIW_OUTER_PEER` | --wiw-outer | L440 |
| 11 | `AETHER_WIW_INNER_PEER` | --wiw-inner | L441 |
| 12 | `AETHER_MASQUE_NO_DATA_CHECK` | --no-data-check, MASQUE side | L451 |
| 13 | `AETHER_WG_NO_DATA_CHECK` | --no-data-check, WireGuard side | L452 |
| 14 | `AETHER_MASQUE_VALIDATE_SECS` | --validate-secs, MASQUE side | L453 |
| 15 | `AETHER_WG_VALIDATE_SECS` | --validate-secs, WireGuard side | L454 |
| 16 | `AETHER_MASQUE_RECONNECT_SECS` | --reconnect-secs, MASQUE side | L456 |
| 17 | `AETHER_WG_RECONNECT_SECS` | --reconnect-secs, WireGuard side | L457 |
| 18 | `AETHER_ROUTE_SNIFF` | 0 to stop reading the server name from the first bytes of a connection (on by default, which is what makes routing rules work behind a tun front end) | L505 |
| 19 | `AETHER_ROUTE_SNIFF_MS` | how long to wait for those bytes (default 400) | L509 |
| 20 | `AETHER_WG_STALE_SECS` | silence on a wireguard tunnel before it counts as dead (default 10) | L513 |
| 21 | `AETHER_MASQUE_H2_KEEPALIVE_SECS` | HTTP/2 keepalive interval (default 15) | L515 |
| 22 | `AETHER_IRONCLAD_PORT` | port the ironclad scan makes its real HTTP request to (default 80) | L518 |
| 23 | `AETHER_MAX_CLIENTS` | proxy clients served at once; past it new ones wait for a free slot (default by resources, 512 to 8192) | L520 |
| 24 | `AETHER_HALF_CLOSE_SECS` | how long a connection the client has finished sending on may sit silent before it is closed (default 30) | L523 |
| 25 | `AETHER_TCP_KEEPALIVE_SECS` | idle time before a keep-alive checks that the other end of a connection is still there; three unanswered ones close it (default 60) | L526 |
| 26 | `AETHER_TCP_CONNECT_SECS` | how long a connection through the tunnel may take to open (default 30) | L529 |
| 27 | `AETHER_REPROVISION` | 0 to stop replacing an identity Cloudflare has refused with a freshly registered one | L531 |
| 28 | `RUST_LOG` | standard rust log filter; overrides --log-level | L533 |

## Verified key defaults (USAGE text)

| Item | Default | USAGE L |
|---|---|---|
| `--bind` (main SOCKS5 listener) | 127.0.0.1:1819 | L23 |
| `--http-proxy` | off by default | L24 |
| `--exit-loc` | off unless passed | L37 |
| `--stats` | off by default | L43 |
| IP version | IPv4-only (`-4`) default | L48 |
| protocol default | MASQUE (QUIC/HTTP-3) | L56 |
| `--protocol` values | `masque \| wg \| gool \| mim` (NO `gool-classic` value) | L74 |
| scan default | balanced | L103 |
| noise default | firewall for MASQUE, balanced for WireGuard and gool | L114 |
| `--tor-bind` (second listener) | 127.0.0.1:1820 | L239 |
| `--psiphon-bind` (second listener) | 127.0.0.1:1821 | L282 |
| `--psiphon-mode` | auto (other values: cdn, direct) | L265 |
| `--validate-secs` | 10 | L127 |
| `--startup-secs` | 30 | L128 |
| `--reconnect-secs` | 2 | L129 |
| `--dns` | 1.1.1.1,1.0.0.1 | L130 |
| `--keepalive` | 5 | L220 |
| `--log-level` | info | L379 |

## Mapping rules proven in the pinned source (beyond cli.rs)

| Rule | Evidence (file, lines) |
|---|---|
| `Protocol` enum has exactly **4** members: Masque, WireGuard, WarpInWarp, MasqueInMasque | lib.rs L3444–3449 |
| `--gool-classic` is **not** a protocol value: parser sets `AETHER_PROTOCOL=gool` **and** `AETHER_GOOL_MODE=classic` | cli.rs L644–647 |
| `Protocol::parse` accepts `wg\|wireguard`, `gool\|wiw\|warp-in-warp\|warpinwarp`, `mim\|m2\|masque-in-masque\|masqueinmasque`, default Masque | lib.rs L3452–3460 |
| GOOL = WireGuard inside MASQUE; GOOL Classic = WireGuard inside WireGuard (submode of the WarpInWarp family) | lib.rs L3364–3380; cli.rs L68–72, L47–53 of USAGE |
| Tor is gated by cargo feature `tor` (optional Arti 0.46 deps); without it every entry point returns the explicit error | Cargo.toml L57–66; tor.rs L191–221 |
| `AETHER_TOR_COUNTRY` is the **BridgeDB/Moat request country** (POST `{"country": …}`), **not** a Tor exit-country control | bridges.rs L410–427, L444–448, L9; cli.rs L429 |
| Tor Reverse and Psiphon Reverse force the HTTP/2 carrier (`AETHER_MASQUE_HTTP2=1`) and refuse UDP-to-WARP protocols (WireGuard, GOOL Classic) | lib.rs L203–218, L229–244, L216, L242 |
| `needs_udp_to_warp`: WireGuard → true; WarpInWarp → only when classic; Masque/MasqueInMasque → false | lib.rs L3007–3013 |
| `select_protocol()` is an **interactive numbered menu** — it is NOT an automatic ranking algorithm | lib.rs L3281–3337 |

