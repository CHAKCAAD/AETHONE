#!/usr/bin/env bash
# DT-APP-* / matrix "app blocking": restrict the adb shell uid (2000) through the
# shield (DA build), verify its flows are refused while another uid is untouched
# (the owner checks a real app by hand: shield.sh restrict-app <pkg> on).
# Usage: appblock-check.sh <TEST-ID>
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ID="${1:?usage: appblock-check.sh <TEST-ID>}"
need_device
D="$(ev_dir "$ID")"
S="$(dirname "$0")/shield.sh"
http_ok() { grep -q '^HTTP/1\.[01] [23]' <<<"$1"; }
fails=0
h0="$(http_get "$DOMAIN_ALLOW" /)"; http_ok "$h0" && echo "PASS: before restriction uid 2000 reaches $DOMAIN_ALLOW" | tee -a "$D/app.txt" || { echo "FAIL: uid 2000 could not reach $DOMAIN_ALLOW before restriction (tunnel down?)" | tee -a "$D/app.txt"; fails=$((fails+1)); }
"$S" restrict-shell on >> "$D/shield.txt" 2>&1
sleep 1
h1="$(http_get "$DOMAIN_ALLOW" /)"; echo "$h1" > "$D/http-restricted.txt"
http_ok "$h1" && { echo "FAIL: restricted uid 2000 still reached $DOMAIN_ALLOW" | tee -a "$D/app.txt"; fails=$((fails+1)); } || echo "PASS: restricted uid 2000 refused" | tee -a "$D/app.txt"
"$S" restrict-shell off >> "$D/shield.txt" 2>&1
sleep 1
h2="$(http_get "$DOMAIN_ALLOW" /)"; http_ok "$h2" && echo "PASS: released uid 2000 reaches $DOMAIN_ALLOW again" | tee -a "$D/app.txt" || { echo "FAIL: uid 2000 still blocked after release" | tee -a "$D/app.txt"; fails=$((fails+1)); }
"$S" status > "$D/shield-status.txt" 2>&1
echo "fails=$fails" | tee -a "$D/app.txt"
echo "MANUAL: also run 'shield.sh restrict-app com.android.chrome on' (or any browser), confirm the app has no network while another app works, then 'off'."
[ "$fails" -eq 0 ]
