#!/usr/bin/env bash
# Packs the evidence folder + the filled results files into one zip to send back.
# Usage: bundle.sh [results.csv] [RESULTS.md]
set -uo pipefail
. "$(dirname "$0")/lib.sh"
H="$(cd "$(dirname "$0")" && pwd)"
[ -d "$EV_ROOT" ] || die "no evidence folder at $EV_ROOT"
for f in "${1:-$EV_ROOT/results.csv}" "${2:-$EV_ROOT/RESULTS.md}"; do
  [ -f "$f" ] && cp "$f" "$EV_ROOT/" 2>/dev/null
done
[ -f "$EV_ROOT/results.csv" ] || { cp "$H/results-template.csv" "$EV_ROOT/results.csv"; echo "NOTE: results.csv was not filled — the empty template is included."; }
[ -f "$EV_ROOT/RESULTS.md" ] || cp "$H/RESULTS-TEMPLATE.md" "$EV_ROOT/RESULTS.md"
{
  echo "bundled_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host=$(uname -s 2>/dev/null) $(uname -m 2>/dev/null)"
  echo "adb=$("$ADB" version 2>/dev/null | head -1)"
  echo "scripts_sha256:"; for s in "$H"/*.sh; do echo "  $(basename "$s") $(sha256_file "$s")"; done
} > "$EV_ROOT/BUNDLE_INFO.txt"
OUT="aethone-device-evidence-$(ts).zip"
PARENT="$(cd "$(dirname "$EV_ROOT")" && pwd)"; BASE="$(basename "$EV_ROOT")"
if command -v zip >/dev/null 2>&1; then (cd "$PARENT" && zip -qr "$OLDPWD/$OUT" "$BASE")
elif command -v python3 >/dev/null 2>&1; then python3 -c "import shutil,sys; shutil.make_archive(sys.argv[1][:-4],'zip',sys.argv[2],sys.argv[3])" "$OUT" "$PARENT" "$BASE"
elif command -v python >/dev/null 2>&1; then python -c "import shutil,sys; shutil.make_archive(sys.argv[1][:-4],'zip',sys.argv[2],sys.argv[3])" "$OUT" "$PARENT" "$BASE"
elif command -v powershell.exe >/dev/null 2>&1; then powershell.exe -NoProfile -Command "Compress-Archive -Path '$EV_ROOT' -DestinationPath '$OUT'"
else OUT="${OUT%.zip}.tar.gz"; tar czf "$OUT" -C "$PARENT" "$BASE"; fi
echo "bundle: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes, sha256 $(sha256_file "$OUT"))"
echo "Send this file back. It contains logcat excerpts and network dumps of THIS phone (IP addresses, Wi-Fi/carrier names) — review before sharing publicly."
