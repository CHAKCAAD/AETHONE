#!/usr/bin/env bash
# DT-ENV-02/03 — install an APK and record its identity (sha256, signer, package).
# Usage: install.sh <apk> [--allow-uninstall]
#   Never uninstalls on its own: an install over a build with another signing
#   key fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE (expected for v1.0.2 ->
#   new key, see DT-MIG-02); --allow-uninstall removes the old app (ITS DATA
#   IS LOST — export first) and installs again.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
APK="${1:-}"; [ -f "$APK" ] || die "usage: install.sh <apk> [--allow-uninstall]"
ALLOW_UNINSTALL=0; [ "${2:-}" = "--allow-uninstall" ] && ALLOW_UNINSTALL=1
need_device
D="$(ev_dir DT-ENV-02)"
{
  echo "apk=$(basename "$APK")"
  echo "apk_sha256=$(sha256_file "$APK")"
  if command -v apksigner >/dev/null 2>&1; then
    apksigner verify --print-certs "$APK" 2>&1 | grep -E 'Signer #1 certificate (DN|SHA-256)' | sed 's/^/signer: /'
  else
    echo "signer: apksigner not on PATH (Android build-tools) — signer not checked on the host"
  fi
  if command -v aapt2 >/dev/null 2>&1; then aapt2 dump badging "$APK" 2>/dev/null | grep -E "^package:|^native-code" ; fi
} | tee "$D/apk.txt"
# compromised v1.0.2 key (docs/family-shield-release.md §4) — warn loudly
grep -qi 'EB:F3:9C:82\|ebf39c82' "$D/apk.txt" && echo "WARNING: this APK is signed by the OLD (compromised) key — only valid as the v1.0.2 baseline for DT-MIG-*."
O="$("$ADB" install -r "$APK" 2>&1 | tr -d '\r')"; echo "$O" | tee "$D/install.txt"
if grep -q INSTALL_FAILED_UPDATE_INCOMPATIBLE <<<"$O"; then
  echo "RESULT: signature mismatch with the installed app (expected when moving from the old key to the new one)."
  if [ "$ALLOW_UNINSTALL" -eq 1 ]; then
    PK="$(grep -o "Package [a-z.]*" <<<"$O" | awk '{print $2}' | head -1)"
    [ -n "$PK" ] || PK="$PKG_RELEASE"
    info "uninstalling $PK (data loss) and retrying"
    "$ADB" uninstall "$PK" 2>&1 | tr -d '\r' | tee -a "$D/install.txt"
    "$ADB" install "$APK" 2>&1 | tr -d '\r' | tee -a "$D/install.txt"
  else
    echo "Not uninstalling (data would be lost). Re-run with --allow-uninstall after the export step."
    exit 2
  fi
fi
grep -q Success "$D/install.txt" || { echo "install FAILED — see $D/install.txt"; exit 1; }
for pk in "$PKG_RELEASE" "$PKG_DA"; do
  installed "$pk" && ash dumpsys package "$pk" | grep -E 'versionName=|primaryCpuAbi=|pkgFlags=' | sed "s/^ */$pk: /" | tee -a "$D/apk.txt"
done
echo "evidence: $D"
