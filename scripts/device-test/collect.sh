#!/usr/bin/env bash
# Evidence snapshot for one test id. Read-only on the device (never clears logcat).
# Usage: collect.sh <TEST-ID> [free-text note]
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ID="${1:?usage: collect.sh <TEST-ID> [note]}"; shift || true
need_device
D="$(ev_dir "$ID")"
P="$(pick_pkg)"
{
  echo "test_id=$ID"
  echo "note=${*:-}"
  echo "collected_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "device_time=$(ash date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "package=$P pid=$(app_pid "$P")"
  echo "model=$(ash getprop ro.product.model) sdk=$(ash getprop ro.build.version.sdk) abi=$(ash getprop ro.product.cpu.abi)"
  echo "private_dns=$(ash settings get global private_dns_mode) $(ash settings get global private_dns_specifier)"
  echo "always_on=$(ash settings get secure always_on_vpn_app) lockdown=$(ash settings get secure always_on_vpn_lockdown)"
  echo "standby_bucket=$(ash am get-standby-bucket "$P")"
  echo "deviceidle=$(ash dumpsys deviceidle get deep) light=$(ash dumpsys deviceidle get light)"
} > "$D/meta.txt"

# shellcheck disable=SC2046
"$ADB" logcat -d -v threadtime -s $(for t in $LOG_TAGS; do printf '%s:V ' "$t"; done) 2>/dev/null | tr -d '\r' > "$D/logcat-filtered.txt"
"$ADB" logcat -d -v threadtime -b crash 2>/dev/null | tr -d '\r' > "$D/logcat-crash.txt"
"$ADB" logcat -d -v threadtime 2>/dev/null | tr -d '\r' | grep -E "$(echo "$P" | sed 's/\./\\./g')|SIGSYS|seccomp|tombstone|Fatal signal" > "$D/logcat-app-and-crash-grep.txt" || true
ash dumpsys connectivity > "$D/dumpsys-connectivity.txt"
ash dumpsys vpn_management > "$D/dumpsys-vpn_management.txt"
ash ip addr > "$D/ip-addr.txt"
ash ip route > "$D/ip-route.txt"
ash ip -6 route > "$D/ip6-route.txt"
ash ip rule > "$D/ip-rule.txt"
ash ip -6 rule > "$D/ip6-rule.txt"
ash "ip route show table all" > "$D/ip-route-table-all.txt"
ash "ip -6 route show table all" > "$D/ip6-route-table-all.txt"
ash "netstat -ltnu 2>/dev/null; echo ---ss---; ss -ltnup 2>/dev/null; echo ---proc---; cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" > "$D/listeners-raw.txt"
{ for p in $(listening_ports); do echo "listening $p"; done; } > "$D/listeners-1819-1822.txt"
ash "ps -A -o USER,PID,PPID,RSS,NAME 2>/dev/null | grep -E 'aethone|lantern|psiphon|lyrebird|tor' " > "$D/processes.txt"
ash dumpsys meminfo "$P" > "$D/meminfo.txt"
if hooks_available "$P"; then
  hook status > "$D/shield-status.json" 2>&1 || true
else
  echo "N/A: no debug hook on $P (release build) — shield status not readable over adb by design" > "$D/shield-status.json"
fi
echo "evidence: $D"
