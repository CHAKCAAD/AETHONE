#!/usr/bin/env bash
# Egress sampler: every ~2 s records the IPv4/IPv6 exit and compares it with
# the direct baseline (baseline.sh). Use it across a VPN restart, protocol
# switch, network handover, reboot, Doze, or while the core is killed.
# Usage: leakwatch.sh <TEST-ID> <seconds>
# Output: samples.csv (utc,epoch,trace_ip,warp,loc,v4,v6,verdict) + summary.txt
# verdict: LEAK (equals the direct baseline) | BLOCKED (no answer) | TUNNEL
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ID="${1:?usage: leakwatch.sh <TEST-ID> <seconds>}"; SECS="${2:-60}"
need_device
[ -f "$EV_ROOT/baseline-current.txt" ] || die "no baseline — run baseline.sh first (VPN off)"
B4="$(sed -n 's/^direct_v4=//p' "$EV_ROOT/baseline-current.txt")"
B6="$(sed -n 's/^direct_v6=//p' "$EV_ROOT/baseline-current.txt")"
BT="$(sed -n 's/^direct_trace_ip=//p' "$EV_ROOT/baseline-current.txt")"
D="$(ev_dir "$ID")"
CSV="$D/samples.csv"
echo "utc,epoch,trace_ip,warp,loc,v4,v6,verdict" > "$CSV"
END=$(( $(now_epoch) + SECS )); leaks=0; blocked=0; tunnel=0
info "sampling $SECS s -> $CSV (baseline v4=$B4 v6=$B6)"
while [ "$(now_epoch)" -lt "$END" ]; do
  E="$(egress_line)"
  t="$(sed -n 's/.*trace_ip=\([^ ]*\).*/\1/p' <<<"$E")"; w="$(sed -n 's/.*warp=\([^ ]*\).*/\1/p' <<<"$E")"
  l="$(sed -n 's/.*loc=\([^ ]*\).*/\1/p' <<<"$E")"; v4="$(sed -n 's/.*v4=\([^ ]*\).*/\1/p' <<<"$E")"; v6="$(sed -n 's/.*v6=\([^ ]*\).*/\1/p' <<<"$E")"
  v=TUNNEL
  if { [ -n "$B4" ] && [ "$B4" != none ] && { [ "$v4" = "$B4" ] || [ "$t" = "$B4" ]; }; } \
     || { [ -n "$B6" ] && [ "$B6" != none ] && { [ "$v6" = "$B6" ] || [ "$t" = "$B6" ]; }; } \
     || { [ -n "$BT" ] && [ "$BT" != none ] && [ "$t" = "$BT" ]; }; then v=LEAK
  elif [ -z "$t" ] && [ "$v4" = none ] && [ "$v6" = none ]; then v=BLOCKED; fi
  case "$v" in LEAK) leaks=$((leaks+1));; BLOCKED) blocked=$((blocked+1));; *) tunnel=$((tunnel+1));; esac
  echo "$(date -u +%H:%M:%S),$(now_epoch),$t,$w,$l,$v4,$v6,$v" | tee -a "$CSV"
  sleep 1
done
{
  echo "test_id=$ID seconds=$SECS"
  echo "samples_tunnel=$tunnel samples_blocked=$blocked samples_leak=$leaks"
  [ "$leaks" -eq 0 ] && echo "verdict=NO-LEAK-OBSERVED" || echo "verdict=LEAK ($leaks samples equal the direct baseline)"
  echo "note: a probe takes ~1-25 s; a gap shorter than one probe can be missed — repeat the action 3x."
} | tee "$D/summary.txt"
