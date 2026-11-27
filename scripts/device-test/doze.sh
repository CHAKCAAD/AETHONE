#!/usr/bin/env bash
# DT-DOZE-* — force Doze / App Standby with the tunnel up, sample egress during
# idle, restore, and check the tunnel survived (same pid, still routing).
# Usage: doze.sh <TEST-ID> <idle-minutes> [deep|light|standby-rare|standby-restricted]
# Always restores (battery reset, deviceidle unforce, bucket active) on exit.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ID="${1:?usage: doze.sh <TEST-ID> <minutes> [deep|light|standby-rare|standby-restricted]}"
MIN="${2:-10}"; MODE="${3:-deep}"
need_device
P="$(pick_pkg)"
D="$(ev_dir "$ID")"
restore() {
  ash dumpsys deviceidle unforce >/dev/null
  ash dumpsys battery reset >/dev/null
  ash am set-standby-bucket "$P" active >/dev/null 2>&1
  ash am set-inactive "$P" false >/dev/null 2>&1
  info "restored: deviceidle unforced, battery reset, bucket active"
}
trap restore EXIT
PID0="$(app_pid "$P")"
{
  echo "mode=$MODE minutes=$MIN package=$P pid_before=$PID0"
  echo "before: $(egress_line)"
  echo "bucket_before=$(ash am get-standby-bucket "$P")"
  echo "whitelisted=$(ash dumpsys deviceidle whitelist | grep -c "$P")"
} | tee "$D/doze.txt"
case "$MODE" in
  deep) ash dumpsys battery unplug >/dev/null; ash dumpsys deviceidle force-idle deep | tee -a "$D/doze.txt";;
  light) ash dumpsys battery unplug >/dev/null; ash dumpsys deviceidle force-idle light | tee -a "$D/doze.txt";;
  standby-rare) ash am set-inactive "$P" true; ash am set-standby-bucket "$P" rare; echo "bucket=$(ash am get-standby-bucket "$P")" | tee -a "$D/doze.txt";;
  standby-restricted) ash am set-inactive "$P" true; ash am set-standby-bucket "$P" restricted; echo "bucket=$(ash am get-standby-bucket "$P")" | tee -a "$D/doze.txt";;
  *) die "unknown mode $MODE";;
esac
echo "deep=$(ash dumpsys deviceidle get deep) light=$(ash dumpsys deviceidle get light)" | tee -a "$D/doze.txt"
info "idle for $MIN min — screen may stay off; sampling every ~60 s"
END=$(( $(now_epoch) + MIN * 60 ))
while [ "$(now_epoch)" -lt "$END" ]; do
  echo "$(date -u +%H:%M:%S) pid=$(app_pid "$P") deep=$(ash dumpsys deviceidle get deep) $(egress_line)" | tee -a "$D/during.txt"
  sleep 60
done
PID1="$(app_pid "$P")"
{
  echo "pid_after_idle=$PID1"
  echo "during_idle_last: $(tail -1 "$D/during.txt")"
} | tee -a "$D/doze.txt"
restore; trap - EXIT
sleep 5
echo "after_restore: $(egress_line)" | tee -a "$D/doze.txt"
[ -n "$PID0" ] && [ "$PID0" = "$PID1" ] && echo "process: SAME pid ($PID0) — not killed during idle" | tee -a "$D/doze.txt" || echo "process: pid changed or gone ($PID0 -> ${PID1:-none}) — record whether the tunnel came back by itself" | tee -a "$D/doze.txt"
"$(dirname "$0")/collect.sh" "$ID" "after doze $MODE $MIN min" >/dev/null
echo "evidence: $D (+ collect snapshot)"
