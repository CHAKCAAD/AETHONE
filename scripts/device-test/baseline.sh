#!/usr/bin/env bash
# DT-IP-01 — direct (no VPN) egress baseline. Run with AETHONE DISCONNECTED and
# Always-on/Lockdown OFF. Later probes flag any sample equal to these addresses
# as a LEAK. Re-run after changing network (Wi-Fi <-> mobile): the baseline is
# per network.
# Usage: baseline.sh [label]     (label e.g. wifi-home, mobile-mci)
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_device
L="${1:-default}"
D="$(ev_dir DT-IP-01)"
if ash dumpsys connectivity | grep -q 'VPN CONNECTED\|type: VPN\[\|VPN, ' ; then
  echo "WARNING: a VPN network seems up — the baseline must be taken with the VPN OFF."
fi
E="$(egress_line)"
echo "$E" | tee "$D/egress.txt"
ash ip addr > "$D/ip-addr.txt"; ash ip -6 route > "$D/ip6-route.txt"
ash dumpsys connectivity | grep -iE 'DnsAddresses|PrivateDns|ValidatedPrivateDnsAddresses|LinkAddresses' > "$D/dns-and-addresses.txt"
mkdir -p "$EV_ROOT"
{
  echo "label=$L"
  echo "taken_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "direct_v4=$(sed -n 's/.*v4=\([^ ]*\).*/\1/p' <<<"$E")"
  echo "direct_v6=$(sed -n 's/.*v6=\([^ ]*\).*/\1/p' <<<"$E")"
  echo "direct_trace_ip=$(sed -n 's/.*trace_ip=\([^ ]*\).*/\1/p' <<<"$E")"
} > "$EV_ROOT/baseline-$L.txt"
cp "$EV_ROOT/baseline-$L.txt" "$EV_ROOT/baseline-current.txt"
cat "$EV_ROOT/baseline-current.txt"
grep -q 'direct_v6=none' "$EV_ROOT/baseline-current.txt" && echo "NOTE: no direct IPv6 on this network — IPv6 leak tests need a dual-stack or IPv6-only network (protocol §4)."
echo "evidence: $D"
