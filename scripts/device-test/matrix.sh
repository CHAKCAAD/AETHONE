#!/usr/bin/env bash
# DT-P-* / DT-H-* — guided protocol matrix (protocol §11, §12). For every
# single-tunnel protocol and every hybrid protocol x WARP-leg combination the
# app offers, the owner selects it in the app and connects; the script then runs
#   CON  connects (exit differs from the direct baseline) + evidence snapshot
#   LSN  local SOCKS listeners vs a foreign uid
#   DNS  shield DNS filtering (DA build only)
#   APP  shield app blocking (DA build only)
#   LEAK 30 s egress sampling, no sample equal to the direct baseline
#   KS   disruption (airplane on/off or Wi-Fi<->mobile) while sampling 90 s
# Auto verdicts go to $EV_ROOT/matrix-results.csv; the owner confirms them in
# results.csv. Nothing is marked PASS without evidence.
# Usage: matrix.sh [--list] [--only CODE[,CODE...]] [--from CODE] [--quick]
#   --quick skips KS (disruption) to save time; KS rows then stay NOT-RUN.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
H="$(dirname "$0")"
# CODE|what to select in the app|leg setting (or -)
COMBOS="
AUTO|AUTO / SMART (protocol grid)|-
MASQUE|MASQUE|-
WG|WIREGUARD|-
GOOL|GOOL|-
GOOLC|GOOL CLASSIC|-
MIM|MIM|-
TORONLY|TOR ONLY|-
PSIONLY|PSIPHON ONLY|-
LANTERN|LANTERN (wide card)|-
H-TORCHAIN-WG|AETHER -> TOR|Tor settings: WARP leg = WireGuard
H-TORCHAIN-MASQUE|AETHER -> TOR|Tor settings: WARP leg = MASQUE
H-TORCHAIN-GOOL|AETHER -> TOR|Tor settings: WARP leg = GOOL
H-TORCHAIN-GOOLC|AETHER -> TOR|Tor settings: WARP leg = GOOL Classic
H-TORCHAIN-MIM|AETHER -> TOR|Tor settings: WARP leg = MIM
H-TORREV-MASQUE|TOR -> AETHER|Tor settings: WARP leg = MASQUE
H-TORREV-GOOL|TOR -> AETHER|Tor settings: WARP leg = GOOL
H-TORREV-MIM|TOR -> AETHER|Tor settings: WARP leg = MIM
H-TORREV-WG2MASQUE|TOR -> AETHER|Tor settings: WARP leg = WireGuard (app maps it to MASQUE — check logcat --protocol masque)
H-TORREV-GOOLC2MASQUE|TOR -> AETHER|Tor settings: WARP leg = GOOL Classic (app maps it to MASQUE)
H-PSICHAIN-WG|AETHER -> PSIPHON|Psiphon settings: WARP leg = WireGuard
H-PSICHAIN-MASQUE|AETHER -> PSIPHON|Psiphon settings: WARP leg = MASQUE
H-PSICHAIN-GOOL|AETHER -> PSIPHON|Psiphon settings: WARP leg = GOOL
H-PSICHAIN-GOOLC|AETHER -> PSIPHON|Psiphon settings: WARP leg = GOOL Classic
H-PSICHAIN-MIM|AETHER -> PSIPHON|Psiphon settings: WARP leg = MIM
H-PSIREV-MASQUE|PSIPHON -> AETHER|Psiphon settings: WARP leg = MASQUE
H-PSIREV-GOOL|PSIPHON -> AETHER|Psiphon settings: WARP leg = GOOL
H-PSIREV-MIM|PSIPHON -> AETHER|Psiphon settings: WARP leg = MIM
H-PSIREV-WG2MASQUE|PSIPHON -> AETHER|Psiphon settings: WARP leg = WireGuard (app maps it to MASQUE)
H-PSIREV-GOOLC2MASQUE|PSIPHON -> AETHER|Psiphon settings: WARP leg = GOOL Classic (app maps it to MASQUE)
"
ONLY=""; FROM=""; QUICK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) echo "$COMBOS" | sed '/^$/d' | awk -F'|' '{printf "%-24s %-26s %s\n",$1,$2,$3}'; exit 0;;
    --only) ONLY=",$2,"; shift;;
    --from) FROM="$2"; shift;;
    --quick) QUICK=1;;
    *) die "unknown option $1";;
  esac; shift
done
need_device
[ -f "$EV_ROOT/baseline-current.txt" ] || die "run baseline.sh first (VPN off) — LEAK verdicts need it"
P="$(pick_pkg)"
HOOKS=0; hooks_available "$P" && [ "$(ash getprop debug.aethone.shieldtest)" = "1" ] && HOOKS=1
[ "$HOOKS" -eq 1 ] && "$H/shield.sh" status >/dev/null || echo "NOTE: no shield hooks on $P (release build or hooks off) — DNS/APP rows become N/A for this pass."
R="$EV_ROOT/matrix-results.csv"
[ -f "$R" ] || echo "test_id,auto_verdict,evidence,utc" > "$R"
rec() { echo "$1,$2,$3,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$R"; echo "  -> $1: $2"; }
last_ev() { ls -1d "$EV_ROOT/$1"/*/ 2>/dev/null | tail -1; }
started=1; [ -n "$FROM" ] && started=0
echo "$COMBOS" | sed '/^$/d' > "$EV_ROOT/.combos"
while IFS='|' read -r CODE SEL LEG <&3; do
  [ "$started" -eq 0 ] && { [ "$CODE" = "$FROM" ] && started=1 || continue; }
  [ -n "$ONLY" ] && ! grep -q ",$CODE," <<<"$ONLY" && continue
  case "$CODE" in H-*) ID="DT-$CODE";; *) ID="DT-P-$CODE";; esac
  echo ""
  echo "=================== $ID ==================="
  echo "In AETHONE: select [$SEL]   leg: [$LEG]   then CONNECT."
  printf "Press Enter when the app shows connected, 'f' if it failed to connect, 's' to skip: "
  read -r ans 
  case "$ans" in
    s|S) rec "$ID-CON" NOT-RUN "-"; continue;;
    f|F) "$H/collect.sh" "$ID-CON" "owner: failed to connect" >/dev/null; rec "$ID-CON" FAIL "$(last_ev "$ID-CON")"
         for c in LSN DNS APP LEAK KS; do rec "$ID-$c" BLOCKED "-"; done; continue;;
  esac
  "$H/collect.sh" "$ID-CON" "connected: $SEL / $LEG" >/dev/null
  E="$(egress_line)"; echo "$E" > "$(last_ev "$ID-CON")/egress.txt"
  B4="$(sed -n 's/^direct_v4=//p' "$EV_ROOT/baseline-current.txt")"
  t="$(sed -n 's/.*trace_ip=\([^ ]*\).*/\1/p' <<<"$E")"
  if [ -z "$t" ]; then rec "$ID-CON" FAIL-NO-EGRESS "$(last_ev "$ID-CON")"
  elif [ "$t" = "$B4" ]; then rec "$ID-CON" FAIL-DIRECT-IP "$(last_ev "$ID-CON")"
  else rec "$ID-CON" PASS "$(last_ev "$ID-CON")"; fi
  echo "  egress: $E"
  "$H/socks-probe.sh" "$ID-LSN" "$SEL / $LEG" > /dev/null
  grep -q 'verdict=PASS' "$(last_ev "$ID-LSN")/socks-probe.txt" && rec "$ID-LSN" PASS "$(last_ev "$ID-LSN")" || rec "$ID-LSN" FAIL-KNOWN-GAP "$(last_ev "$ID-LSN")"
  if [ "$HOOKS" -eq 1 ]; then
    "$H/dns-check.sh" "$ID-DNS" --no-cache-test > /dev/null && rec "$ID-DNS" PASS "$(last_ev "$ID-DNS")" || rec "$ID-DNS" FAIL "$(last_ev "$ID-DNS")"
    "$H/appblock-check.sh" "$ID-APP" > /dev/null && rec "$ID-APP" PASS "$(last_ev "$ID-APP")" || rec "$ID-APP" FAIL "$(last_ev "$ID-APP")"
  else
    rec "$ID-DNS" NA-NO-HOOK "-"; rec "$ID-APP" NA-NO-HOOK "-"
  fi
  "$H/leakwatch.sh" "$ID-LEAK" 30 > /dev/null
  grep -q 'NO-LEAK-OBSERVED' "$(last_ev "$ID-LEAK")/summary.txt" && rec "$ID-LEAK" PASS "$(last_ev "$ID-LEAK")" || rec "$ID-LEAK" FAIL "$(last_ev "$ID-LEAK")"
  if [ "$QUICK" -eq 1 ]; then rec "$ID-KS" NOT-RUN "-"; else
    echo "  KS: sampling 90 s. NOW: airplane mode ON, wait 10 s, OFF (or switch Wi-Fi <-> mobile). Do not touch the app."
    "$H/leakwatch.sh" "$ID-KS" 90 > /dev/null
    grep -q 'NO-LEAK-OBSERVED' "$(last_ev "$ID-KS")/summary.txt" && rec "$ID-KS" PASS-NO-LEAK "$(last_ev "$ID-KS")" || rec "$ID-KS" FAIL-LEAK "$(last_ev "$ID-KS")"
    printf "  KS: did the tunnel come back by itself without touching the app? [y/n]: "; read -r back 
    echo "owner_reports_tunnel_recovered=$back" >> "$(last_ev "$ID-KS")/summary.txt"
  fi
  printf "Disconnect in the app, then press Enter for the next combination: "; read -r _ 
done 3< "$EV_ROOT/.combos"
rm -f "$EV_ROOT/.combos"
echo ""
echo "auto verdicts: $R  (copy into results.csv after checking each evidence folder)"
