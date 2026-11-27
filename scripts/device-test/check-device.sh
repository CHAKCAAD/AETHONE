#!/usr/bin/env bash
# DT-ENV-01 / DT-ABI-01 — device facts: ABI, Android version, ROM, page size,
# IPv6, Private DNS, Always-on VPN, battery settings, installed AETHONE builds.
# Usage: check-device.sh            (writes $EV_ROOT/DT-ENV-01/<ts>/device.txt)
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_device
D="$(ev_dir DT-ENV-01)"
OUT="$D/device.txt"
p() { echo "$1=$(ash getprop "$2")"; }
{
  echo "collected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  p manufacturer ro.product.manufacturer
  p brand ro.product.brand
  p model ro.product.model
  p device ro.product.device
  p android_release ro.build.version.release
  p sdk ro.build.version.sdk
  p security_patch ro.build.version.security_patch
  p build_fingerprint ro.build.fingerprint
  p build_type ro.build.type
  p abi ro.product.cpu.abi
  p abilist ro.product.cpu.abilist
  p abilist64 ro.product.cpu.abilist64
  p abilist32 ro.product.cpu.abilist32
  p miui ro.miui.ui.version.name
  p hyperos ro.mi.os.version.name
  p oneui ro.build.version.oneui
  p coloros ro.build.version.opporom
  p emui ro.build.version.emui
  p qemu ro.kernel.qemu
  echo "page_size=$(ash getconf PAGE_SIZE)"
  echo "kernel=$(ash uname -r)"
  echo "shell_id=$(ash id)"
  echo "root_su=$(ash 'command -v su >/dev/null 2>&1 && echo present || echo absent')"
  echo "private_dns_mode=$(ash settings get global private_dns_mode)"
  echo "private_dns_specifier=$(ash settings get global private_dns_specifier)"
  echo "always_on_vpn_app=$(ash settings get secure always_on_vpn_app)"
  echo "always_on_vpn_lockdown=$(ash settings get secure always_on_vpn_lockdown)"
  echo "strongbox_feature=$(ash pm has-feature android.hardware.strongbox_keystore 2>/dev/null || echo unknown)"
  echo "fingerprint_feature=$(ash pm has-feature android.hardware.fingerprint 2>/dev/null || echo unknown)"
  for pk in "$PKG_RELEASE" "$PKG_DA"; do
    if installed "$pk"; then
      echo "pkg.$pk=installed"
      ash dumpsys package "$pk" | grep -E 'versionName=|versionCode=|primaryCpuAbi=|pkgFlags=|firstInstallTime=|lastUpdateTime=' | sed "s/^ */pkg.$pk./"
      echo "pkg.$pk.standby_bucket=$(ash am get-standby-bucket "$pk")"
      echo "pkg.$pk.doze_whitelisted=$(ash dumpsys deviceidle whitelist | grep -c "$pk")"
      echo "pkg.$pk.run_any_in_background=$(ash cmd appops get "$pk" RUN_ANY_IN_BACKGROUND)"
    else
      echo "pkg.$pk=not-installed"
    fi
  done
} | tee "$OUT"
ash ip addr > "$D/ip-addr.txt"
ash ip -6 addr > "$D/ip6-addr.txt"
ash ip route > "$D/ip-route.txt"
ash ip -6 route > "$D/ip6-route.txt"

ABI="$(sed -n 's/^abi=//p' "$OUT")"
SDK="$(sed -n 's/^sdk=//p' "$OUT")"
echo ""
case "$ABI" in
  arm64-v8a) echo "ABI: arm64-v8a — use the arm64 device-test APK. (DT-ABI-01 input)";;
  armeabi-v7a) echo "ABI: armeabi-v7a — 32-bit device: the arm64 APK will NOT install; use aethone-armeabi-v7a-r<run>.apk from the aethone-apk-r<run> artifact (protocol §2.3).";;
  x86_64|x86) echo "ABI: $ABI — this is an emulator/x86 device: results go in the EMULATOR column, never the device column.";;
  *) echo "ABI: $ABI — unexpected; record it.";;
esac
[ "$(sed -n 's/^qemu=//p' "$OUT")" = "1" ] && echo "WARNING: ro.kernel.qemu=1 — this is an EMULATOR, not a real device."
[ -n "$SDK" ] && [ "$SDK" -lt 29 ] && echo "NOTE: SDK $SDK < 29: app blocking and LoopbackGuard owner-uid lookup need Android 10+ (expect app-blocking-unsupported)."
echo "evidence: $D"
