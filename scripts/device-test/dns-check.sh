#!/usr/bin/env bash
# DT-DNS-* / protocol matrix DNS check (needs the DA build + shield set up).
# 1) allowed name resolves (fake IP 198.18.0.0/15 or fc00::/18 when tunnelled)
#    and answers HTTP; 2) blocked name -> unknown host and no HTTP;
# 3) cache: allowed name -> fake IP works, block it live, the SAME cached IP
#    must be refused, then unblock.
# Usage: dns-check.sh <TEST-ID> [--no-cache-test]
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ID="${1:?usage: dns-check.sh <TEST-ID> [--no-cache-test]}"
need_device
D="$(ev_dir "$ID")"
S="$(dirname "$0")/shield.sh"
fails=0
ok() { echo "PASS: $*" | tee -a "$D/dns-check.txt"; }
ko() { echo "FAIL: $*" | tee -a "$D/dns-check.txt"; fails=$((fails+1)); }
http_ok() { grep -q '^HTTP/1\.[01] [23]' <<<"$1"; }
: > "$D/dns-check.txt"
"$S" block "$DOMAIN_BLOCK" >> "$D/shield.txt" 2>&1
a="$(resolve "$DOMAIN_ALLOW")"; echo "resolve $DOMAIN_ALLOW -> $a" >> "$D/dns-check.txt"
case "$a" in 198.18.*|198.19.*|fc*|fd*) ok "$DOMAIN_ALLOW resolved to a fake IP ($a) — DNS answered by the tunnel";; unknown-host|"") ko "$DOMAIN_ALLOW did not resolve";; *) ko "$DOMAIN_ALLOW resolved to a REAL address $a (DNS did not go through the tunnel's fake-IP DNS)";; esac
h="$(http_get "$DOMAIN_ALLOW" /)"; echo "$h" > "$D/http-allow.txt"
http_ok "$h" && ok "$DOMAIN_ALLOW HTTP answered through the tunnel" || ko "$DOMAIN_ALLOW HTTP failed"
b="$(resolve "$DOMAIN_BLOCK")"; echo "resolve $DOMAIN_BLOCK -> $b" >> "$D/dns-check.txt"
[ "$b" = "unknown-host" ] && ok "$DOMAIN_BLOCK -> NXDOMAIN (unknown host)" || ko "$DOMAIN_BLOCK resolved to $b"
h="$(http_get "$DOMAIN_BLOCK" /)"; echo "$h" > "$D/http-block.txt"
http_ok "$h" && ko "$DOMAIN_BLOCK answered HTTP (filter bypassed)" || ok "$DOMAIN_BLOCK: no HTTP answer"
if [ "${2:-}" != "--no-cache-test" ]; then
  c="$(resolve "$DOMAIN_CACHE")"; echo "resolve $DOMAIN_CACHE -> $c" >> "$D/dns-check.txt"
  case "$c" in
    198.18.*|198.19.*)
      h="$(ash "printf 'GET / HTTP/1.0\r\nHost: $DOMAIN_CACHE\r\n\r\n' | timeout 12 toybox nc -w 8 $c 80 2>&1")"
      http_ok "$h" && ok "cached fake IP $c works while allowed" || ko "cached fake IP $c did not work while allowed"
      "$S" block "$DOMAIN_CACHE" >> "$D/shield.txt" 2>&1
      grep -q '"applied":"ok"' "$D/shield.txt" || echo "NOTE: block answer had no applied:ok (tunnel down?) — see shield.txt" >> "$D/dns-check.txt"
      h="$(ash "printf 'GET / HTTP/1.0\r\nHost: $DOMAIN_CACHE\r\n\r\n' | timeout 12 toybox nc -w 8 $c 80 2>&1")"; echo "$h" > "$D/http-cache-after-block.txt"
      http_ok "$h" && ko "cached fake IP $c still reached $DOMAIN_CACHE after the live block" || ok "cached fake IP $c refused after the live block"
      [ "$(resolve "$DOMAIN_CACHE")" = "unknown-host" ] && ok "$DOMAIN_CACHE now NXDOMAIN" || ko "$DOMAIN_CACHE still resolves after block"
      rid="$("$S" rules | grep -o "{[^{}]*\"value\":\"$DOMAIN_CACHE\"[^{}]*}" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)"
      [ -n "$rid" ] && "$S" unrule "$rid" >> "$D/shield.txt" 2>&1 || echo "NOTE: could not find the $DOMAIN_CACHE rule id to remove — remove it by hand (shield.sh rules / unrule)" >> "$D/dns-check.txt";;
    *) ko "$DOMAIN_CACHE did not get a fake IPv4 ($c) — cache test not meaningful";;
  esac
fi
"$S" status > "$D/shield-status.txt" 2>&1
echo "fails=$fails" | tee -a "$D/dns-check.txt"
echo "evidence: $D"
[ "$fails" -eq 0 ]
