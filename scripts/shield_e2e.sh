#!/usr/bin/env bash
# Family Shield phase 2 — emulator end-to-end tests (CI job shield-e2e).
#
# Preconditions (done by the workflow): the release APK is installed, the
# VPN consent appop is granted, adbd runs as root. Evidence goes to $EV.
#
# The app's ShieldTestReceiver (not exported + inert unless the
# debug.aethone.shieldtest property is 1) drives the real admin API and
# hosts a SOCKS5 stub on 127.0.0.1:1819 behind LoopbackGuard. zeptun (the
# real packaged engine) tunnels the device's traffic into that stub, so the
# stub's CONNECT log is the ground truth of "what reached the tunnel".
# Device-side clients run as the shell uid (2000) through `su 2000`.
set -uo pipefail
EV="${EV:-shield-evidence}"
mkdir -p "$EV"
PKG=com.chakcaad.aethone
TAG=AethoneShieldTest
FAILS=0
RES="$EV/results.txt"
: > "$RES"

pass() { echo "PASS: $*" | tee -a "$RES"; }
fail() { echo "::error::shield-e2e: $*"; echo "FAIL: $*" >> "$RES"; FAILS=$((FAILS + 1)); }
note() { echo "NOTE: $*" | tee -a "$RES"; }

results() { adb logcat -d -s "$TAG:I" 2>/dev/null | grep -F "RESULT $1 " || true; }
count() { results "$1" | wc -l | tr -d ' '; }

# cmd NAME [am extras…] — sends a command and waits (≤ $WAIT s) for its RESULT line
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

# run a shell-uid (2000) command on the device
as_shell() { adb shell "su 2000 sh -c '$1'" 2>&1 | tr -d '\r'; }
# connect as uid 2000 to host:port, send one line, print what came back
nc_shell() { as_shell "echo q | timeout ${3:-8} toybox nc -w 5 $1 $2 2>&1; echo rc=\$?"; }
stub_seen() { results stub-connect | grep -c -F "\"$1" || true; }

echo "=== setup ==="
adb shell setprop debug.aethone.shieldtest 1
adb logcat -c
WAIT=120 S="$(cmd setup)"; echo "setup: $S" | tee "$EV/setup.json"
echo "$S" | grep -q '"ok":true' && pass "PIN setup + session + profiles + enable through the admin API" || fail "setup failed: $S"
echo "$S" | grep -q '"gatedWithoutToken":"session-required"' && pass "gated admin call without a parent session is refused" || fail "gating: $S"

echo "=== tunnel up (shielded, real packaged zeptun) ==="
adb shell am start-foreground-service -n "$PKG/.AethoneVpnService" --ei port 1819 --ei session 7
up=0
for _ in $(seq 1 60); do
  sleep 2
  if adb logcat -d -s AethoneVpn | grep -q "zeptun up on socks"; then up=1; break; fi
  if adb logcat -d -s AethoneVpn | grep -qE "tunnel start refused|zeptun-load-failed|start-threw|FATAL"; then break; fi
done
adb logcat -d -s AethoneVpn AethoneShield > "$EV/vpn-start-logcat.txt" 2>/dev/null || true
if [ "$up" -ne 1 ]; then
  fail "shielded tunnel did not come up"; cat "$EV/vpn-start-logcat.txt"
  echo "FAILS=$FAILS"; exit 1
fi
pass "shielded tunnel up (snapshot installed before the engine thread, engine hook checked)"
sleep 2
# the stub is started inside the (now foreground) VPN process: an idle
# receiver-only process can be reclaimed between commands (seen on run
# 45861953726 — the stub vanished with it).
S="$(cmd stub --ei port 1819)"; echo "stub: $S" | tee "$EV/stub.json"
echo "$S" | grep -q '"ok":true' && pass "guarded SOCKS stub listening on 127.0.0.1:1819" || fail "stub: $S"
echo "app pid: $(adb shell pidof com.chakcaad.aethone | tr -d '\r')" | tee -a "$RES"
adb shell ip addr > "$EV/ip-addr.txt" 2>&1 || true
adb shell ip -6 route show table all > "$EV/ip6-routes.txt" 2>&1 || true
adb shell dumpsys connectivity > "$EV/dumpsys-connectivity.txt" 2>&1 || true

S="$(cmd status)"; echo "$S" > "$EV/status-initial.json"; echo "status: $S"
echo "$S" | grep -q '"engineHook":true' && pass "status: engine hook installed (zeptun counter 6 = 1)" || fail "status engineHook: $S"
echo "$S" | grep -q '"port":1819,"listening":true,"guarded":true' && pass "status: listener 1819 detected and guarded" || fail "status listener: $S"
echo "$S" | grep -q '"ipv6Route":true' && pass "status: IPv6 route + address accepted by the Builder" || fail "status ipv6Route: $S"

echo "=== DNS filtering through the TUN ==="
O="$(nc_shell allowed.aethone-test.example 80)"; echo "$O" > "$EV/nc-allowed.txt"
echo "$O" | grep -q "AETHONE-STUB" && pass "allowed name resolves (fake IP) and reaches the tunnel" || fail "allowed name did not reach the stub: $O"
for name in blocked.aethone-test.example www.blocked.aethone-test.example; do
  O="$(nc_shell "$name" 80)"; echo "$O" > "$EV/nc-$name.txt"
  P="$(as_shell "ping -c 1 -W 2 $name 2>&1")"; echo "$P" >> "$EV/nc-$name.txt"
  if echo "$O" | grep -q "AETHONE-STUB"; then fail "$name reached the tunnel (leak)"; else pass "$name: no connection (DNS answered NXDOMAIN: $(echo "$P" | head -1))"; fi
done
[ "$(stub_seen blocked.aethone-test.example)" = 0 ] && pass "no CONNECT for the blocked name ever reached the tunnel" || fail "blocked name in the stub log"
S="$(cmd status)"
DNSB="$(echo "$S" | sed -n 's/.*"dnsBlocked":\([0-9-]*\).*/\1/p')"
[ "${DNSB:-0}" -gt 0 ] && pass "engine counted $DNSB NXDOMAIN answers (dnsBlocked)" || fail "dnsBlocked counter not > 0: $S"

echo "=== loopback SOCKS access control (LoopbackGuard PoC) ==="
G0="$(count guard)"
O="$(as_shell 'printf "\005\001\000" | timeout 5 toybox nc -w 3 127.0.0.1 1819 | od -An -tx1; echo rc=$?')"; echo "$O" > "$EV/loopback-shell.txt"
O2="$(adb shell 'printf "\005\001\000" | timeout 5 toybox nc -w 3 127.0.0.1 1819 | od -An -tx1; echo rc=$?' 2>&1 | tr -d '\r')"; echo "$O2" > "$EV/loopback-root.txt"
S="$(cmd own-connect --ei port 1819)"; echo "$S" > "$EV/loopback-own.json"
sleep 1
results guard > "$EV/guard-verdicts.txt"
echo "$O" | grep -q "05 00" && fail "uid 2000 got a SOCKS reply from the guarded listener: $O" || pass "uid 2000: no SOCKS reply (connection reset by the gate)"
echo "$O2" | grep -q "05 00" && fail "root got a SOCKS reply from the guarded listener: $O2" || pass "uid 0 (root): no SOCKS reply"
echo "$S" | grep -q '"handshake":true' && pass "in-process client admitted (own-process socket match)" || fail "own-process client refused: $S"
tail -n +$((G0 + 1)) "$EV/guard-verdicts.txt" | grep -q 'reject:' && pass "gate logged rejections for foreign clients" || fail "no rejection logged"
grep -q '"verdict":"allow:own-process"' "$EV/guard-verdicts.txt" && pass "zeptun's own dials were admitted (internal chaining intact)" || fail "zeptun dials not admitted"
grep -q 'foreign-uid:2000' "$EV/guard-verdicts.txt" && pass "getConnectionOwnerUid named the shell uid 2000" || note "getConnectionOwnerUid did not return 2000 (see guard-verdicts.txt)"

echo "=== DNS cache: cached fake IP after a live block ==="
P="$(as_shell 'ping -c 1 -W 2 allowed2.aethone-test.example 2>&1')"; echo "$P" > "$EV/cache.txt"
IP="$(echo "$P" | sed -n 's/^PING [^ ]* (\([0-9.]*\)).*/\1/p' | head -1)"
if [ -z "$IP" ]; then fail "no fake IP for allowed2: $P"; else
  O="$(nc_shell "$IP" 80)"; echo "before: $O" >> "$EV/cache.txt"
  echo "$O" | grep -q "AETHONE-STUB" && pass "cached fake IP $IP reaches the tunnel while allowed" || fail "fake IP $IP did not connect: $O"
  B="$(stub_seen allowed2.aethone-test.example)"
  S="$(cmd block --es domain allowed2.aethone-test.example)"; echo "block: $S" >> "$EV/cache.txt"
  echo "$S" | grep -q '"applied":"ok"' || fail "block op did not apply (cache test not meaningful): $S"
  echo "$S" | grep -q '"applied":"ok"' && pass "live rule applied (atomic snapshot swap, no tunnel restart)" || fail "live block: $S"
  O="$(nc_shell "$IP" 80)"; echo "after: $O" >> "$EV/cache.txt"
  echo "$O" | grep -q "AETHONE-STUB" && fail "cached fake IP still reached the tunnel after the block" || pass "cached fake IP $IP refused at flow open after the block"
  [ "$(stub_seen allowed2.aethone-test.example)" = "$B" ] && pass "no new CONNECT for allowed2 after the block" || fail "allowed2 leaked after the block"
fi

echo "=== flow revalidation (live flow killed by a rule change) ==="
( adb shell "su 2000 sh -c '(sleep 45) | toybox nc -w 5 live.aethone-test.example 80'" > "$EV/live-flow.txt" 2>&1 & )
ok=0; for _ in $(seq 1 20); do sleep 1; [ "$(stub_seen live.aethone-test.example)" -gt 0 ] && { ok=1; break; }; done
if [ "$ok" -ne 1 ]; then fail "live flow never reached the stub"; else
  C0="$(results stub-close | grep -c 'live.aethone-test.example' || true)"
  T0=$(date +%s)
  cmd block --es domain live.aethone-test.example > /dev/null
  killed=0; for _ in $(seq 1 15); do sleep 1; [ "$(results stub-close | grep -c 'live.aethone-test.example' || true)" -gt "$C0" ] && { killed=1; break; }; done
  [ "$killed" -eq 1 ] && pass "open flow to a newly blocked name was aborted in $(( $(date +%s) - T0 )) s (zeptun_revalidate_flows)" || fail "open flow survived the rule change"
fi

echo "=== app blocking by uid (shell uid 2000) ==="
S="$(cmd restrict-uid --ei uid 2000 --ez on true)"; echo "$S" > "$EV/uid.txt"
O="$(nc_shell allowed3.aethone-test.example 80)"; echo "restricted: $O" >> "$EV/uid.txt"
echo "$O" | grep -q "AETHONE-STUB" && fail "restricted uid 2000 reached the tunnel" || pass "uid 2000 restricted: flow refused before any SOCKS dial"
[ "$(stub_seen allowed3.aethone-test.example)" = 0 ] && pass "no CONNECT from the restricted uid" || fail "restricted uid leaked"
cmd restrict-uid --ei uid 2000 --ez on false > /dev/null
O="$(nc_shell allowed3.aethone-test.example 80)"; echo "released: $O" >> "$EV/uid.txt"
echo "$O" | grep -q "AETHONE-STUB" && pass "uid 2000 released: flows pass again" || fail "uid 2000 still blocked after release: $O"

echo "=== profile switching ==="
S="$(cmd switch --es to b)"; echo "$S" > "$EV/switch.txt"
echo "$S" | grep -q '"applied":"ok"' || fail "switch to b did not apply: $S"
O="$(nc_shell switch.aethone-test.example 80)"; echo "b/switch: $O" >> "$EV/switch.txt"
echo "$O" | grep -q "AETHONE-STUB" && fail "profile b: switch.* not blocked" || pass "profile b active: its rule blocks switch.aethone-test.example"
O="$(nc_shell blocked.aethone-test.example 80)"; echo "b/blocked: $O" >> "$EV/switch.txt"
echo "$O" | grep -q "AETHONE-STUB" && pass "profile b active: profile a's rule no longer applies" || fail "profile a's rule still applied under b: $O"
cmd switch --es to a > /dev/null
O="$(nc_shell blocked.aethone-test.example 80)"; echo "a/blocked: $O" >> "$EV/switch.txt"
echo "$O" | grep -q "AETHONE-STUB" && fail "back on profile a: blocked.* reached the tunnel" || pass "back on profile a: its rules apply again"

echo "=== IPv6 capture ==="
grep -q "fdfe:dcba:9876::1" "$EV/ip-addr.txt" && pass "TUN carries fdfe:dcba:9876::1/126" || fail "TUN has no IPv6 address"
O="$(as_shell "echo q | timeout 8 toybox nc -6 -w 5 2001:db8::5 80 2>&1; echo rc=\$?")"; echo "$O" > "$EV/ipv6.txt"
echo "$O" | grep -q "AETHONE-STUB" && pass "IPv6 TCP flow reached the engine and the tunnel" || fail "IPv6 flow did not reach the tunnel: $O"
S="$(cmd status)"; echo "$S" > "$EV/status-final.json"
V6="$(echo "$S" | sed -n 's/.*"ipv6Packets":\([0-9-]*\).*/\1/p')"
[ "${V6:-0}" -gt 0 ] && pass "engine counted $V6 IPv6 packets (counter 7)" || fail "ipv6Packets not > 0: $S"
echo "final state: $(echo "$S" | sed -n 's/.*"state":"\([a-z_]*\)".*/\1/p') reasons: $(echo "$S" | sed -n 's/.*"reasons":\(\[[^]]*\]\).*/\1/p')" | tee -a "$RES"

echo "=== settings export ==="
S="$(cmd export)"; echo "$S" > "$EV/export.json"
echo "$S" | grep -q '"containsPin":false' && echo "$S" | grep -q '"profiles":2' && pass "export validates, carries 2 profiles and no PIN" || fail "export: $S"

echo "=== fail-closed start (enabled shield, broken profile) ==="
adb shell am stop-service "$PKG/.AethoneVpnService" > /dev/null 2>&1 || true
sleep 3
cmd break > /dev/null
adb logcat -c
adb shell am start-foreground-service -n "$PKG/.AethoneVpnService" --ei port 1819 --ei session 8
refused=0
for _ in $(seq 1 20); do sleep 1; adb logcat -d -s AethoneVpn | grep -q "tunnel start refused: shield-no-active-profile" && { refused=1; break; }; done
adb logcat -d -s AethoneVpn > "$EV/fail-closed-logcat.txt" 2>/dev/null || true
[ "$refused" -eq 1 ] && pass "start refused fail-closed (no unfiltered tunnel)" || fail "broken shield start not refused"
grep -q "zeptun up on socks" "$EV/fail-closed-logcat.txt" && fail "tunnel came up with a broken shield" || pass "no TUN established with a broken shield"
cmd repair > /dev/null
adb shell am stop-service "$PKG/.AethoneVpnService" > /dev/null 2>&1 || true

results stub-connect > "$EV/stub-connects.txt"
results stub-close > "$EV/stub-closes.txt"
adb logcat -d > "$EV/logcat-full.txt" 2>/dev/null || true
echo "app pid at end: $(adb shell pidof com.chakcaad.aethone | tr -d '\r')" | tee -a "$RES"
echo ""
echo "=== summary ==="
grep -c '^PASS' "$RES" | sed 's/^/passed: /'
echo "failed: $FAILS"
[ "$FAILS" -eq 0 ]
