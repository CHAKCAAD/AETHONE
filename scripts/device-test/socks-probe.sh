#!/usr/bin/env bash
# DT-LSN-* — which of 1819-1822 listen, on which address, and whether a FOREIGN
# uid (the adb shell, uid 2000) gets a SOCKS5 answer from them.
# Required result: no foreign uid can use any listener (no "socks-reply").
# Known state at this commit: the real cores' listeners are NOT guarded
# (docs/family-shield-security.md §5 A, §8) -> expect socks-reply = FAIL.
# Usage: socks-probe.sh <TEST-ID> [protocol-label]
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ID="${1:?usage: socks-probe.sh <TEST-ID> [label]}"
need_device
D="$(ev_dir "$ID")"
ash "netstat -ltn 2>/dev/null; cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" > "$D/listeners-raw.txt"
fail=0
{
  echo "label=${2:-}"
  for p in $SOCKS_PORTS; do
    hex="$(printf '%04X' "$p")"
    bind="$(awk -v h=":$hex" '$2 ~ h"$" && $4=="0A"{print $2}' "$D/listeners-raw.txt" | sort -u | tr '\n' ' ')"
    if [ -z "$bind" ] && ! grep -Eq "[:.]${p}[[:space:]]" "$D/listeners-raw.txt"; then echo "port=$p listening=no"; continue; fi
    any=""; grep -Eq "^ *[0-9]+: 00000000:$hex |^ *[0-9]+: 00000000000000000000000000000000:$hex " "$D/listeners-raw.txt" && any=" WILDCARD-BIND(all interfaces!)"
    r="$(socks_probe "$p")"
    [ "$r" = "socks-reply" ] && fail=$((fail+1))
    echo "port=$p listening=yes proc_local=[$bind]$any foreign_uid2000=$r"
  done
  [ "$fail" -eq 0 ] && echo "verdict=PASS (no listener answered a foreign uid)" || echo "verdict=FAIL ($fail listener(s) usable by uid 2000)"
} | tee "$D/socks-probe.txt"
echo "evidence: $D"
