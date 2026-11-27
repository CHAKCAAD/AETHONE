#!/usr/bin/env bash
# Debug test hooks — DA (debuggable) build ONLY. Release builds carry no
# reachable hook by design; this script then says so and does nothing.
# Usage: hooks.sh on | off | probe
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_device
P="$(pick_pkg)"
case "${1:-probe}" in
  on)
    if ! hooks_available "$P"; then
      echo "hooks: UNAVAILABLE for $P (release build or DA build without DeviceTestReceiver) — by design; Family Shield checks are N/A on this build."
      exit 2
    fi
    ash setprop debug.aethone.shieldtest 1
    [ "$(ash getprop debug.aethone.shieldtest)" = "1" ] || die "could not set debug.aethone.shieldtest (this ROM refuses debug.* props from adb shell)"
    R="$(hook ping)"; echo "hooks: $R"
    grep -q '"ok":true' <<<"$R" || exit 1
    ;;
  off)
    ash setprop debug.aethone.shieldtest 0
    echo "hooks: off (property 0; a reboot also clears it)"
    ;;
  probe)
    echo "package=$P installed=$(installed "$P" && echo yes || echo no) debuggable=$(is_debuggable "$P" && echo yes || echo no)"
    echo "receiver_declared=$(ash dumpsys package "$P" | grep -c "$HOOK_RECEIVER")"
    echo "property=$(ash getprop debug.aethone.shieldtest)"
    hooks_available "$P" && echo "hooks: available" || echo "hooks: UNAVAILABLE"
    ;;
  *) die "usage: hooks.sh on|off|probe";;
esac
