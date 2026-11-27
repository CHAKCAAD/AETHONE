# shellcheck shell=bash
# AETHONE real-device test helpers — shared functions (sourced, not run).
# Works with bash on Linux, macOS (bash 3.2) and Windows Git Bash.
# Protocol: docs/family-shield-device-testing.md
#
# Environment (all optional):
#   ADB            adb binary (default: adb on PATH)
#   ANDROID_SERIAL device serial when more than one is attached (adb reads it)
#   EV_ROOT        evidence root directory (default: ./aethone-device-evidence)
#   PKG            package under test; default: auto (the DA build if installed
#                  and hooks are wanted, else com.chakcaad.aethone)

# Git Bash: stop MSYS from rewriting /sdcard/... and /data/... arguments.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

ADB="${ADB:-adb}"
EV_ROOT="${EV_ROOT:-./aethone-device-evidence}"
PKG_RELEASE="com.chakcaad.aethone"
PKG_DA="com.chakcaad.aethone.da"
HOOK_ACTION="com.chakcaad.aethone.DEVICE_TEST"
HOOK_RECEIVER="com.chakcaad.aethone.shield.DeviceTestReceiver"
HOOK_TAG="AethoneDeviceTest"
SOCKS_PORTS="1819 1820 1821 1822"
# Plain-HTTP egress probes (no TLS needed with toybox nc). The Cloudflare
# trace answers ip=, loc= and warp=on|off (warp=on => the exit is WARP).
TRACE_HOST="www.cloudflare.com"
IP4_HOST="ipv4.icanhazip.com"
IP6_HOST="ipv6.icanhazip.com"
# Neutral test names (IANA reserved example domains, real DNS + HTTP).
DOMAIN_BLOCK="${DOMAIN_BLOCK:-example.com}"
DOMAIN_ALLOW="${DOMAIN_ALLOW:-example.net}"
DOMAIN_CACHE="${DOMAIN_CACHE:-example.org}"

LOG_TAGS="AethoneVpn AethoneShield AethoneShieldCh AethoneHybrid AethoneGuard AethoneDeviceTest AethoneShieldTest AethoneLantern AethoneCoreHold AethoneMain AethoneMeter AethoneTile zeptun flutter AndroidRuntime DEBUG libc Vpn VpnManager ConnectivityService"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[$(date +%H:%M:%S)] $*"; }

# adb shell with CR stripped (Windows adb adds \r)
ash() { "$ADB" shell "$@" </dev/null 2>&1 | tr -d '\r'; }

need_device() {
  command -v "$ADB" >/dev/null 2>&1 || die "adb not found (install Android platform-tools, or set ADB=/path/to/adb)"
  local n
  n="$("$ADB" devices | tr -d '\r' | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')"
  if [ -z "${ANDROID_SERIAL:-}" ] && [ "$n" != "1" ]; then
    "$ADB" devices
    die "need exactly one authorized device (found $n) — or set ANDROID_SERIAL"
  fi
  [ "$(ash getprop sys.boot_completed)" = "1" ] || die "device not booted / not authorized"
}

ts() { date +%Y%m%d-%H%M%S; }
now_epoch() { date +%s; }

# evidence directory for one test id: $EV_ROOT/<ID>/<timestamp>
ev_dir() {
  local id="${1:?test id}"
  local d="$EV_ROOT/$id/$(ts)"
  mkdir -p "$d"
  echo "$d"
}

installed() { ash pm list packages "$1" | grep -qx "package:$1"; }
is_debuggable() { ash dumpsys package "$1" | grep -q 'pkgFlags=\[.*DEBUGGABLE'; }

# The package the tests talk to. Hooks need the DA build.
pick_pkg() {
  if [ -n "${PKG:-}" ]; then echo "$PKG"; return; fi
  if installed "$PKG_DA"; then echo "$PKG_DA"; else echo "$PKG_RELEASE"; fi
}

app_pid() { ash pidof "$1" | awk '{print $1}'; }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v certutil >/dev/null 2>&1; then certutil -hashfile "$1" SHA256 | sed -n 2p | tr -d ' \r'
  else echo "unavailable"; fi
}

# ---------------------------------------------------------------- hooks (DA)
hooks_available() {
  local p="${1:-$(pick_pkg)}"
  [ "$p" = "$PKG_DA" ] || return 1
  installed "$p" || return 1
  is_debuggable "$p" || return 1
  ash dumpsys package "$p" | grep -q "$HOOK_RECEIVER"
}

_hook_results() { "$ADB" logcat -d -s "$HOOK_TAG:I" 2>/dev/null | tr -d '\r' | grep -F "RESULT $1 " || true; }
_hook_count() { _hook_results "$1" | wc -l | tr -d ' '; }

# hook CMD [am extras...] — prints the JSON answer (or TIMEOUT / DISABLED)
hook() {
  local c="$1"; shift
  local p; p="$(pick_pkg)"
  hooks_available "$p" || { echo "UNAVAILABLE"; return 2; }
  local before dis; before="$(_hook_count "$c")"; dis="$(_hook_count disabled)"
  "$ADB" shell am broadcast -a "$HOOK_ACTION" -n "$p/$HOOK_RECEIVER" --es cmd "$c" "$@" </dev/null >/dev/null 2>&1
  local i=0
  while [ "$i" -lt "${HOOK_WAIT:-45}" ]; do
    if [ "$(_hook_count "$c")" -gt "$before" ]; then _hook_results "$c" | tail -1 | sed "s/^.*RESULT $c //"; return 0; fi
    if [ "$(_hook_count disabled)" -gt "$dis" ]; then echo "DISABLED (run: hooks.sh on)"; return 3; fi
    i=$((i + 1)); sleep 1
  done
  echo "TIMEOUT"; return 1
}

json_field() { sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" <<<"$1" | head -1; }

# ---------------------------------------------------------------- probes
# All probes run as the adb shell user (uid 2000). Shell traffic is routed
# like an app's: through the VPN when it is up (unless excluded).
# http_get HOST PATH [-4|-6] — raw HTTP/1.0 over toybox nc, prints the body
http_get() {
  local host="$1" path="$2" fam="${3:-}"
  ash "printf 'GET $path HTTP/1.0\r\nHost: $host\r\nUser-Agent: curl/8.0\r\nConnection: close\r\n\r\n' | timeout 12 toybox nc $fam -w 8 $host 80 2>&1; echo \"[rc=\$?]\""
}
# one line: v4=<ip> v6=<ip> warp=<on|off> loc=<cc>
egress_line() {
  local t v4 v6
  t="$(http_get "$TRACE_HOST" /cdn-cgi/trace)"
  v4="$(http_get "$IP4_HOST" / -4 | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)"
  v6="$(http_get "$IP6_HOST" / -6 | grep -Eio '^[0-9a-f:]*:[0-9a-f:]+$' | tail -1)"
  echo "trace_ip=$(sed -n 's/^ip=//p' <<<"$t" | head -1) warp=$(sed -n 's/^warp=//p' <<<"$t" | head -1) loc=$(sed -n 's/^loc=//p' <<<"$t" | head -1) v4=${v4:-none} v6=${v6:-none}"
}
# resolve NAME — the address ping prints, or "unknown-host"
resolve() {
  local o; o="$(ash "ping -c 1 -W 2 $1 2>&1 | head -2")"
  if grep -qi 'unknown host\|bad address' <<<"$o"; then echo "unknown-host"; return; fi
  sed -n 's/^PING [^ ]* (\([^)]*\)).*/\1/p' <<<"$o" | head -1
}
# SOCKS5 greeting from the shell uid; prints "socks-reply" when the listener
# answered method 00 (= usable by a foreign uid), else "no-reply"
socks_probe() {
  local o; o="$(ash "printf '\005\001\000' | timeout 6 toybox nc -w 4 127.0.0.1 $1 | od -An -tx1; echo rc=\$?")"
  if grep -q '05 00' <<<"$o"; then echo "socks-reply"; elif grep -q '05 ff' <<<"$o"; then echo "socks-refused-method"; else echo "no-reply"; fi
}
listening_ports() {
  # toybox netstat first, then the raw /proc tables (hex ports)
  local o; o="$(ash 'netstat -ltn 2>/dev/null; ss -ltn 2>/dev/null')"
  for p in $SOCKS_PORTS; do
    if grep -Eq "[:.]${p}[[:space:]]" <<<"$o"; then echo "$p"; continue; fi
    local hex; hex="$(printf '%04X' "$p")"
    ash "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" | awk -v h=":$hex" '$2 ~ h"$" && $4=="0A"{f=1} END{exit !f}' && echo "$p"
  done
}
