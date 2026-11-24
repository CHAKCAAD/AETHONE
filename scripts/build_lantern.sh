#!/usr/bin/env bash
# feature/lantern-core — builds the Lantern sidecar (native/lanternbridge →
# liblantern.so) for ONE Android ABI.
#
# Adapted from MSN-GUARD core/lanternbridge/build-android.sh
# (github.com/mbm110/MSN-GUARD, branch feature/lantern-prototype, AGPL-3.0).
#
#   bash scripts/build_lantern.sh --abi arm64-v8a --goarch arm64 \
#        [--goarm 7] [--api-level 29] --out out/lantern/arm64-v8a
#
# Output: $OUT/liblantern.so (+ $OUT/manifest.json). The APK job copies it
# to android/app/src/main/jniLibs/<abi>/liblantern.so; useLegacyPackaging
# (already on) extracts it into nativeLibraryDir with the exec bit, the same
# road libpsiphon.so / liblyrebird.so take.
#
# Pins:
#   * Go 1.26.10 (lanternbridge go.mod `go 1.26.10`; GOTOOLCHAIN=local)
#   * NDK r26d (26.3.11579264) — AETHONE's frozen NDK
#   * Radiance v0.0.0-20261121161923-0c920c73b969 (go.mod / go.sum)
#   * tags: novpn (SOCKS inbound, no TUN) + sing-box feature set
set -euo pipefail

ABI="" GOARCH_IN="" GOARM_IN="" API_LEVEL="29" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --abi) ABI="$2"; shift 2 ;;
    --goarch) GOARCH_IN="$2"; shift 2 ;;
    --goarm) GOARM_IN="$2"; shift 2 ;;
    --api-level) API_LEVEL="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$ABI" ] && [ -n "$GOARCH_IN" ] && [ -n "$OUT" ] || {
  echo "usage: $0 --abi <abi> --goarch <goarch> [--goarm 7] [--api-level 29] --out <dir>" >&2; exit 2; }

die() { echo "FATAL: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE="$ROOT/native/lanternbridge"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[ -d "$NDK" ] || die "ANDROID_NDK_HOME must point to NDK r26d"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"

case "$ABI" in
  arm64-v8a)   CC="aarch64-linux-android${API_LEVEL}-clang" ;;
  armeabi-v7a) CC="armv7a-linux-androideabi${API_LEVEL}-clang" ;;
  x86_64)      CC="x86_64-linux-android${API_LEVEL}-clang" ;;
  *) die "unsupported ABI $ABI" ;;
esac
[ -x "$TC/$CC" ] || die "NDK clang not found: $TC/$CC"
CXX="${CC%-clang}-clang++"

export GOTOOLCHAIN=local
GOV="$(go env GOVERSION)"
[ "$GOV" = "go1.26.10" ] || die "Go $GOV != pinned go1.26.10 (lanternbridge go.mod)"

TAGS="novpn,with_gvisor,with_quic,with_wireguard,with_utls,with_grpc"
# 16 KB page alignment (Android 15+), full RELRO — same rules as the other
# AETHONE natives (scripts/inspect_elf.sh).
LDFLAGS="-s -w -checklinkname=0 -extldflags '-Wl,-z,max-page-size=16384 -Wl,-z,relro -Wl,-z,now -static-libstdc++'"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"   # absolute: the build below runs inside $BRIDGE
cd "$BRIDGE"
go mod download
go mod verify
echo "Radiance pin:"; grep '^github.com/getlantern/radiance ' go.sum | head -2

# Local unit tests only (host build) — never contact Lantern servers in CI.
if [ "$ABI" = "x86_64" ]; then
  go test -tags="$TAGS" ./cmd/lanternsidecar
fi

echo "== building liblantern.so for $ABI ($GOARCH_IN${GOARM_IN:+ v$GOARM_IN}, API $API_LEVEL)"
env GOOS=android GOARCH="$GOARCH_IN" ${GOARM_IN:+GOARM="$GOARM_IN"} CGO_ENABLED=1 \
    CC="$TC/$CC" CXX="$TC/$CXX" \
  go build -trimpath -buildmode=pie -tags="$TAGS" -ldflags="$LDFLAGS" \
    -o "$OUT/liblantern.so" ./cmd/lanternsidecar
"$TC/llvm-strip" --strip-unneeded "$OUT/liblantern.so" || true
[ -s "$OUT/liblantern.so" ] || die "liblantern.so missing after go build"

# Same guard as aether: the sidecar must not need libc++_shared.so (AETHONE
# ships none). If a future Radiance pin starts needing it, fail loudly here.
needed="$("$TC/llvm-readelf" -d "$OUT/liblantern.so" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
echo "NEEDED: $(echo $needed)"
grep -qx 'libc++_shared.so' <<<"$needed" && die "liblantern.so needs libc++_shared.so"

sha=$(sha256sum "$OUT/liblantern.so" | cut -d' ' -f1)
cat > "$OUT/manifest.json" <<EOF
{
  "abi": "$ABI",
  "api_level": $API_LEVEL,
  "component": "lantern-sidecar",
  "radiance": "$(sed -n 's/^require github.com\/getlantern\/radiance //p' go.mod)",
  "go": "$GOV",
  "tags": "$TAGS",
  "artifact": {"path": "liblantern.so", "sha256": "$sha", "bytes": $(wc -c <"$OUT/liblantern.so")}
}
EOF
cat "$OUT/manifest.json"
