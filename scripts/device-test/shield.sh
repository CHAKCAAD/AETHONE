#!/usr/bin/env bash
# Family Shield driver for the DA device-test build (debug hooks).
# Every answer is printed and appended to $EV_ROOT/shield-calls.log.
#
# Usage:
#   shield.sh setup [preset]          PIN (test PIN) + profile "device-test" + enable
#   shield.sh status                  status JSON (state, reasons, counters, listeners)
#   shield.sh config
#   shield.sh block <domain>          parent rule: root <domain> -> block (live)
#   shield.sh allow <domain>          parent rule: root <domain> -> allow
#   shield.sh rules                   rules of the active profile
#   shield.sh unrule <ruleId>
#   shield.sh restrict-app <package> on|off     real restrictApp path (Android 10+)
#   shield.sh restrict-shell on|off   restrict the adb shell uid 2000 (test hook)
#   shield.sh category <name> on|off
#   shield.sh unknown allow|block
#   shield.sh strict on|off [dot quic altdns directip]   (flags default: dot quic altdns)
#   shield.sh enable | disable
#   shield.sh pin-state
#   shield.sh pin-try <pin>           pinVerify WITHOUT the script's session (backoff tests)
#   shield.sh recover <code>          pinRecover (one-time recovery code)
#   shield.sh export [file]           settings export -> app's external files dir, then pulled
#   shield.sh import <local-file>     push + import (needs the DA build installed)
#   shield.sh import-nosession <local-file>   import without a parent session (gating test)
#   shield.sh admin <method> [k=v | k:b=true | k:i=5 | a.b=v] ...   raw admin call
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_device
P="$(pick_pkg)"
hooks_available "$P" || { echo "UNAVAILABLE: Family Shield hooks need the DA device-test build ($PKG_DA). Release builds have none by design."; exit 2; }
mkdir -p "$EV_ROOT"
LOGF="$EV_ROOT/shield-calls.log"
say() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$LOGF"; echo "$*"; }
admin() { local m="$1"; shift; say "admin $m $* => $(hook admin --es method "$m" "$@")"; }
DIR_ON_DEVICE="/sdcard/Android/data/$P/files/device-test"

cmd="${1:-status}"; shift || true
case "$cmd" in
  setup) say "setup => $(hook setup --es preset "${1:-custom}")";;
  status) R="$(hook status)"; say "status => $R";;
  config) say "config => $(hook config)";;
  block) admin addRule --es a.profileId @active --es a.kind root --es a.value "${1:?domain}" --es a.action block;;
  allow) admin addRule --es a.profileId @active --es a.kind root --es a.value "${1:?domain}" --es a.action allow;;
  rules) admin rules --es a.profileId @active;;
  unrule) admin removeRule --es a.id "${1:?rule id}";;
  restrict-app) admin restrictApp --es a.profileId @active --es a.package "${1:?package}" --ez a.on "$([ "${2:-on}" = on ] && echo true || echo false)";;
  restrict-shell) say "restrict-uid 2000 ${1:-on} => $(hook restrict-uid --ei uid 2000 --ez on "$([ "${1:-on}" = on ] && echo true || echo false)")";;
  category) admin setCategory --es a.profileId @active --es a.category "${1:?category}" --ez a.on "$([ "${2:-on}" = on ] && echo true || echo false)";;
  unknown) admin setUnknownPolicy --es a.profileId @active --es a.policy "${1:?allow|block}";;
  strict)
    on="$([ "${1:-on}" = on ] && echo true || echo false)"; shift || true
    flags="${*:-dot quic altdns}"
    b() { grep -qw "$1" <<<"$flags" && echo true || echo false; }
    admin setStrict --es a.profileId @active --ez a.strict.enabled "$on" --ez a.strict.blockDot "$(b dot)" \
      --ez a.strict.blockQuic "$(b quic)" --ez a.strict.blockAltDns "$(b altdns)" --ez a.strict.blockDirectIp "$(b directip)";;
  enable) admin setEnabled --ez a.enabled true;;
  disable) admin setEnabled --ez a.enabled false;;
  pin-state) say "pinState => $(hook admin --es method pinState --ez nosession true)";;
  pin-try) say "pinVerify(nosession) => $(hook admin --es method pinVerify --es a.pin "${1:?pin}" --ez nosession true)";;
  recover) say "pinRecover => $(hook admin --es method pinRecover --es a.code "${1:?code}" --ez nosession true)";;
  export)
    f="${1:-aethone-settings-export.json}"
    R="$(hook export-file --es file "$f")"; say "export-file => $R"
    grep -q '"ok":true' <<<"$R" || exit 1
    mkdir -p "$EV_ROOT/exports"
    "$ADB" pull "$DIR_ON_DEVICE/$f" "$EV_ROOT/exports/$f" && say "pulled -> $EV_ROOT/exports/$f sha256=$(sha256_file "$EV_ROOT/exports/$f")";;
  import|import-nosession)
    lf="${1:?local file}"; [ -f "$lf" ] || die "no such file: $lf"
    f="$(basename "$lf")"
    hook ping >/dev/null  # app process up -> external files dir exists
    ash mkdir -p "$DIR_ON_DEVICE" >/dev/null
    "$ADB" push "$lf" "$DIR_ON_DEVICE/$f" || die "push to $DIR_ON_DEVICE failed (some ROMs block adb writes to Android/data — note it as BLOCKED)"
    extra=""; [ "$cmd" = import-nosession ] && extra="--ez nosession true"
    # shellcheck disable=SC2086
    say "$cmd $f => $(hook import-file --es file "$f" $extra)";;
  admin)
    m="${1:?method}"; shift
    args=()
    for kv in "$@"; do
      k="${kv%%=*}"; v="${kv#*=}"
      case "$k" in
        *:b) args+=(--ez "a.${k%:b}" "$v");;
        *:i) args+=(--ei "a.${k%:i}" "$v");;
        *:l) args+=(--el "a.${k%:l}" "$v");;
        *) args+=(--es "a.$k" "$v");;
      esac
    done
    admin "$m" ${args[@]+"${args[@]}"};;
  *) sed -n '2,25p' "$0"; exit 1;;
esac
