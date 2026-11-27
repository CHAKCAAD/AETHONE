#!/usr/bin/env bash
# Family Shield phase 2.1 — emulator e2e against the REAL cores (CI job
# shield-e2e, after scripts/shield_e2e.sh). Evidence goes to $EV/cores/.
#
# The packaged release APK's own cores are started IN the app process by the
# guarded ShieldTestReceiver (not exported + debug.aethone.shieldtest=1):
#   * Aether (libaether.so) through its C API (Zeptun.nativeAetherCall →
#     aether_core_start — the call the Flutter side makes with dart:ffi) with
#     `--loopback-gate <secret file>`;
#   * Psiphon (libpsiphon.so) as Aether starts it (--psiphon-only / --psiphon);
#   * Lantern (liblantern.so) through LanternSidecar.start (gate armed).
# Foreign clients: the shell uid 2000 (`su 2000`) and root (adbd root) with
# toybox nc. Internal clients: zeptun (TUN, uid-2000 traffic) and the app's
# own in-process SOCKS client (`own-socks`).
#
# Verdicts:
#   FAIL     — a guard is proven wrong (a foreign client got a no-auth SOCKS
#              session, a listening port is not reported guarded, a secret
#              listener accepted no/wrong credentials, a chain hop refused).
#   UNPROVEN — the core never reached the state the check needs (its network
#              was unreachable from the CI emulator); recorded, not a pass.
#   PASS     — proven on this emulator run.
set -uo pipefail
EV="${EV:-shield-evidence}/cores"
mkdir -p "$EV"
PKG=com.chakcaad.aethone
TAG=AethoneShieldTest
FAILS=0
RES="$EV/results.txt"
: > "$RES"
CORELOG="/data/data/$PKG/files/shield-e2e-core.log"

pass() { echo "PASS: $*" | tee -a "$RES"; }
fail() { echo "::error::shield-e2e-cores: $*"; echo "FAIL: $*" >> "$RES"; FAILS=$((FAILS + 1)); }
unproven() { echo "UNPROVEN: $*" | tee -a "$RES"; }
note() { echo "NOTE: $*" | tee -a "$RES"; }

results() { adb logcat -d -s "$TAG:I" 2>/dev/null | grep -F "RESULT $1 " || true; }
count() { results "$1" | wc -l | tr -d ' '; }
cmd() {
  local c="$1"; shift
  local before; before="$(count "$c")"
  adb shell am broadcast -a com.chakcaad.aethone.SHIELD_TEST -n "$PKG/.shield.ShieldTestReceiver" --es cmd "$c" "$@" > /dev/null
  for _ in $(seq 1 "${WAIT:-60}"); do
    if [ "$(count "$c")" -gt "$before" ]; then results "$c" | tail -1 | sed "s/^.*RESULT $c //"; return 0; fi
    sleep 1
  done
  echo "TIMEOUT"
  return 1
}
as_shell() { adb shell "su 2000 sh -c '$1'" 2>&1 | tr -d '\r'; }
# a no-auth SOCKS5 greeting from uid 2000 / root; prints the reply bytes (hex)
greet_shell() { as_shell "printf \"\\005\\001\\000\" | timeout 6 toybox nc -w 4 127.0.0.1 $1 | od -An -tx1"; }
greet_root() { adb shell "printf '\\005\\001\\000' | timeout 6 toybox nc -w 4 127.0.0.1 $1 | od -An -tx1" 2>&1 | tr -d '\r'; }
gatelog() { adb shell "cat $CORELOG 2>/dev/null" | tr -d '\r' | grep -F '[shield-gate]' || true; }
listeners() { WAIT=30 cmd listeners; }
port_field() { echo "$1" | jq -r --argjson p "$2" ".listeners[] | select(.port==\$p) | .$3" 2>/dev/null; }

# foreign clients must get no no-auth session; a "secret" listener must answer 05 ff
foreign_checks() { # scenario port guard
  local sc="$1" port="$2" guard="$3" o r
  o="$(greet_shell "$port")"; r="$(greet_root "$port")"
  echo "uid2000 $port: $o" >> "$EV/$sc-foreign.txt"; echo "root $port: $r" >> "$EV/$sc-foreign.txt"
  if echo "$o" | grep -q "05 00"; then fail "$sc: uid 2000 got a no-auth SOCKS session on $port"; else pass "$sc: uid 2000 refused on $port ($(echo $o | head -c 20)${o:+…}${o:-no reply})"; fi
  if echo "$r" | grep -q "05 00"; then fail "$sc: root got a no-auth SOCKS session on $port"; else pass "$sc: root refused on $port ($(echo $r | head -c 20)${r:+…}${r:-no reply})"; fi
  if [ "$guard" = "secret" ]; then
    echo "$o" | grep -q "05 ff" && pass "$sc: $port demands authentication from uid 2000 (05 ff)" || fail "$sc: $port did not answer 05 ff to uid 2000: $o"
  fi
}

status_checks() { # scenario — every listening port must be guarded
  local sc="$1" S
  S="$(WAIT=40 cmd status)"; echo "$S" > "$EV/$sc-status.json"
  local open; open="$(echo "$S" | jq -c '[.listeners[] | select(.listening and (.guarded|not)) | .port]' 2>/dev/null)"
  local n; n="$(echo "$S" | jq '[.listeners[] | select(.listening)] | length' 2>/dev/null)"
  if [ "${n:-0}" -gt 0 ] && [ "$open" = "[]" ]; then pass "$sc: status — all $n listening ports guarded (runtime probe)"; else fail "$sc: status — unguarded listening ports $open (listening=$n)"; fi
  echo "$S" | grep -q 'local-socks-exposed' && fail "$sc: status reasons still name local-socks-exposed" || pass "$sc: no local-socks-exposed reason"
  echo "$sc: state=$(echo "$S" | jq -r .state) reasons=$(echo "$S" | jq -c .reasons) listeners=$(echo "$S" | jq -c '[.listeners[]|select(.listening)|{port,guard,probe,guarded}]')" | tee -a "$RES"
}

ups() { adb logcat -d -s AethoneVpn | grep "zeptun up on socks 127.0.0.1:$1" | grep -c "loopback-gate=armed" || true; }
vpn_up() { # port tcpOnly strict session
  local before; before="$(ups "$1")"
  adb shell am start-foreground-service -n "$PKG/.AethoneVpnService" --ei port "$1" --ez tcpOnly "$2" --ez socksStrict "$3" --ei session "$4" > /dev/null
  for _ in $(seq 1 40); do
    sleep 2
    [ "$(ups "$1")" -gt "$before" ] && return 0
  done
  return 1
}
vpn_down() { adb shell am stop-service "$PKG/.AethoneVpnService" > /dev/null 2>&1 || true; sleep 3; }

tun_http() { # scenario — uid 2000 traffic through the TUN → zeptun → the core
  local sc="$1" o
  o="$(as_shell "printf \"GET /cdn-cgi/trace HTTP/1.1\\r\\nHost: www.cloudflare.com\\r\\nConnection: close\\r\\n\\r\\n\" | timeout 40 toybox nc -w 30 www.cloudflare.com 80 | head -c 300")"
  echo "$o" > "$EV/$sc-tun-http.txt"
  if echo "$o" | grep -q "^HTTP/1.1 "; then pass "$sc: end-to-end through TUN → zeptun → core ($(echo "$o" | head -1))"; return 0; fi
  unproven "$sc: no HTTP answer through the tunnel within 40 s (core upstream unreachable from CI?)"; return 1
}

wait_listening() { # port seconds
  local L
  for _ in $(seq 1 $(( $2 / 5 ))); do
    L="$(listeners)"; echo "$L" > "$EV/last-listeners.json"
    [ "$(port_field "$L" "$1" listening)" = "true" ] && return 0
    sleep 5
  done
  return 1
}

wait_serving() { # port seconds — the in-process client's handshake is answered
  local S
  for _ in $(seq 1 $(( $2 / 10 ))); do
    S="$(WAIT=30 cmd own-socks --ei port "$1" --ez auth true --ez connect false)"
    echo "$S" >> "$EV/serving-$1.txt"
    echo "$S" | grep -q '"handshake":true' && return 0
    sleep 8
  done
  return 1
}

core_scenario() { # scenario mode zeptun-port tcpOnly strict
  local sc="$1" mode="$2" zport="$3" tcp="$4" strict="$5"
  echo "=== $sc (mode $mode) ==="
  local L0; L0="$(adb shell "wc -l < $CORELOG 2>/dev/null" | tr -d '\r ')"; L0="${L0:-0}"
  local S; S="$(cmd core-start --es mode "$mode" --ez gate true)"; echo "$S" > "$EV/$sc-start.json"
  echo "$S" | grep -q '"ok":true' && pass "$sc: real Aether core started in-process with --loopback-gate" || { fail "$sc: core did not start: $S"; return; }
  if ! wait_listening 1819 60; then fail "$sc: 1819 never listening"; cmd core-poll > "$EV/$sc-poll.json"; cmd core-stop > /dev/null; return; fi
  pass "$sc: 1819 bound"
  local served=0
  if wait_serving "$zport" 240; then served=1; pass "$sc: in-process client admitted and answered on $zport (own-process$( [ "$zport" = 1819 ] || echo ' → chain'))"
  else unproven "$sc: $zport never served within 240 s (core not up) — foreign 'no reply' would not prove the gate"; fi
  L="$(listeners)"; echo "$L" > "$EV/$sc-listeners.json"
  echo "$sc declared: $(echo "$L" | jq -c .declared)" | tee -a "$RES"
  if [ "$served" -eq 1 ]; then
    for p in $(echo "$L" | jq -r '.listeners[] | select(.listening) | .port'); do
      foreign_checks "$sc" "$p" "$(port_field "$L" "$p" guard)"
    done
    sleep 2
    gatelog | tail -n +$((L0 + 1)) > "$EV/$sc-gate.log"
    grep -q 'refused' "$EV/$sc-gate.log" && pass "$sc: core gate logged refusals of the foreign clients" || note "$sc: no refusal line in the core log (see $sc-gate.log)"
    grep -q 'OwnProcess' "$EV/$sc-gate.log" && pass "$sc: core gate admitted in-process clients (OwnProcess)" || fail "$sc: no OwnProcess admission in the core log"
  fi
  # secret listeners (the Psiphon child): wrong / no credentials refused, right ones accepted
  for p in $(echo "$L" | jq -r '.declared[] | select(.guard=="secret") | .port'); do
    S="$(cmd own-socks --ei port "$p" --ez auth false --ez connect false)"; echo "noauth $p: $S" >> "$EV/$sc-secret.txt"
    echo "$S" | grep -q '"method":255' && pass "$sc: secret listener $p refuses a client without credentials (in-process too)" || fail "$sc: secret listener $p without credentials: $S"
    S="$(cmd own-socks --ei port "$p" --ez auth true --ez wrong true --ez connect false)"; echo "wrong $p: $S" >> "$EV/$sc-secret.txt"
    echo "$S" | grep -q '"auth":"refused"' && pass "$sc: secret listener $p refuses wrong credentials" || fail "$sc: secret listener $p wrong credentials: $S"
    S="$(cmd own-socks --ei port "$p" --ez auth true --ez connect false)"; echo "right $p: $S" >> "$EV/$sc-secret.txt"
    echo "$S" | grep -q '"auth":"ok"' && pass "$sc: secret listener $p accepts the session secret" || fail "$sc: secret listener $p session secret: $S"
  done
  if vpn_up "$zport" "$tcp" "$strict" 21; then
    pass "$sc: shielded TUN up on $zport with zeptun authenticating (loopback-gate=armed)"
    [ "$served" -eq 1 ] && tun_http "$sc"
    status_checks "$sc"
  else
    fail "$sc: TUN did not come up on $zport"
    adb logcat -d -s AethoneVpn > "$EV/$sc-vpn.txt" 2>/dev/null || true
  fi
  if [ "$mode" = "psiphon-chain" ]; then
    gatelog | tail -n +$((L0 + 1)) > "$EV/$sc-gate.log"
    grep -q '(Secret)' "$EV/$sc-gate.log" && pass "$sc: the Psiphon child was admitted to Aether's socks5 listener with the session secret (chain hop)" \
      || { [ "$served" -eq 1 ] && fail "$sc: chain served but no Secret admission logged" || unproven "$sc: chain hop psiphon → aether not reached"; }
  fi
  vpn_down
  cmd core-poll > "$EV/$sc-poll.json"
  cmd core-stop > /dev/null
  sleep 3
}

echo "=== setup (real cores) ==="
adb shell setprop debug.aethone.shieldtest 1
WAIT=120 S="$(cmd setup)"; echo "$S" > "$EV/setup.json"
echo "$S" | grep -q '"ok":true' && pass "shield enabled through the admin API" || fail "setup: $S"
cmd stub-stop > /dev/null
adb shell am stop-service "$PKG/.AethoneVpnService" > /dev/null 2>&1 || true
sleep 2

# single tunnels
core_scenario psiphon-only psiphon-only 1819 true true
core_scenario aether masque 1819 false false
# hybrid chains (Aether → Psiphon, Aether → Tor)
core_scenario psiphon-chain psiphon-chain 1821 true true
core_scenario tor-chain tor-chain 1820 true false

echo "=== lantern (sidecar) ==="
L0="$(adb shell "wc -l < $CORELOG 2>/dev/null" | tr -d '\r ')"
S="$(cmd lantern-start --ez gate true)"; echo "$S" > "$EV/lantern-start.json"
echo "$S" | grep -q '"authArmed":true' && pass "lantern: sidecar started with --socks-auth-file" || fail "lantern: start: $S"
if wait_listening 1822 180; then
  pass "lantern: 1822 listening"
  foreign_checks lantern 1822 secret
  H="$(as_shell "printf \"GET http://www.cloudflare.com/ HTTP/1.1\\r\\nHost: www.cloudflare.com\\r\\n\\r\\n\" | timeout 8 toybox nc -w 5 127.0.0.1 1822 | head -1")"
  echo "$H" > "$EV/lantern-http.txt"
  echo "$H" | grep -q " 407" && pass "lantern: HTTP proxy demands Proxy-Authorization (407) from uid 2000" || fail "lantern: HTTP proxy answer to uid 2000: $H"
  S="$(cmd own-socks --ei port 1822 --ez auth false --ez connect false)"; echo "$S" >> "$EV/lantern-secret.txt"
  echo "$S" | grep -q '"method":255' && pass "lantern: no-credential client refused" || fail "lantern: no-credential client: $S"
  S="$(cmd own-socks --ei port 1822 --ez auth true --ez wrong true --ez connect false)"; echo "$S" >> "$EV/lantern-secret.txt"
  echo "$S" | grep -q '"auth":"refused"' && pass "lantern: wrong credentials refused" || fail "lantern: wrong credentials: $S"
  S="$(cmd own-socks --ei port 1822 --ez auth true --ez connect false)"; echo "$S" >> "$EV/lantern-secret.txt"
  echo "$S" | grep -q '"auth":"ok"' && pass "lantern: session secret accepted" || fail "lantern: session secret: $S"
  if vpn_up 1822 true false 31; then
    adb logcat -d -s AethoneVpn | grep "127.0.0.1:1822" | grep -q "udp=disabled" && pass "lantern: zeptun runs TCP-only under the gate" || fail "lantern: zeptun UDP not disabled under the gate"
    tun_http lantern
    status_checks lantern
  else
    fail "lantern: TUN did not come up on 1822"
  fi
  vpn_down
else
  unproven "lantern: 1822 never listening within 180 s (Radiance could not reach Lantern from CI?) — Lantern guard not proven"
  cmd lantern-status > "$EV/lantern-status.json"
fi
cmd lantern-stop > /dev/null

adb shell "cat $CORELOG" > "$EV/core-log.txt" 2>/dev/null || true
adb logcat -d -b all > "$EV/logcat-full.txt" 2>/dev/null || true
adb logcat -d -b crash > "$EV/logcat-crash.txt" 2>/dev/null || true
grep -q 'SIGSYS' "$EV/logcat-crash.txt" && note "SIGSYS in the crash buffer (see logcat-crash.txt)"
echo ""
echo "=== summary (real cores) ==="
echo "passed: $(grep -c '^PASS' "$RES")"
echo "unproven: $(grep -c '^UNPROVEN' "$RES")"
echo "failed: $FAILS"
[ "$FAILS" -eq 0 ]
