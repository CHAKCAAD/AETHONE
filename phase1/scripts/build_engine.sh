#!/usr/bin/env bash
# build_engine.sh — the AETHONE Firefox VPN engine build (phase1/fxv).
#
# THE A1 DECREE (2026-11-08, real-device verified; extended to ALL
# Android ABIs by the 2026-11-09 multi-architecture amendment):
#
#   EVERY Android ABI builds with CGO + the NDK clang toolchain so name
#   resolution goes through the ANDROID SYSTEM RESOLVER (Bionic's
#   getaddrinfo). A pure-Go Android build uses Go's own resolver, which
#   on Android consults the dead local [::1]:53 and fails with
#   "lookup api.accounts.firefox.com on [::1]:53: connection refused" —
#   the exact 2026-11-08 field failure. This script REFUSES to build any
#   Android target with CGO_ENABLED=0.
#
# Toolchain pins (the project's evidence values):
#   Go 1.25.0 · Android NDK 28.2.13676358 (r28c) · API 34 compilers
#
# Targets:
#   android/arm64-v8a    CGO, aarch64-linux-android34-clang
#   android/armeabi-v7a  CGO, armv7a-linux-androideabi34-clang (GOARM=7)
#   android/x86_64       CGO, x86_64-linux-android34-clang
#   host/linux-amd64     pure Go (NOT a deliverable; the Dart
#                        integration/lifecycle tests run this binary)
#
# Usage:  phase1/scripts/build_engine.sh [arm64-v8a|armeabi-v7a|x86_64|host|all]
#         (default: all four)
#
# Output: phase1/build/<abi>/libfirefoxvpn.so (+ host/libfirefoxvpn),
#         phase1/build/SHA256SUMS.txt, per-ABI ELF inspection logs.
#
# Exit codes: 0 = all requested targets built+verified; 1 = any failure
# (a missing compiler, a CGO refusal, a build error — never hidden).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE1_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FXV_DIR="$PHASE1_DIR/fxv"
OUT_DIR="$PHASE1_DIR/build"
UPSTREAM_DIR="$PHASE1_DIR/firefox-vpn-client"

GO_BIN="${GO:-go}"
NDK_ROOT="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
NDK_VERSION_PIN="28.2.13676358"
API_LEVEL=34

# The upstream pin the module's replace directive expects (verified by
# fetch_upstream.sh; re-asserted here so a stale copy cannot build).
UPSTREAM_PIN="55ad91a2ccea1c93e69c82a08a7681e279884db5"

log()  { printf 'build_engine: %s\n' "$*" >&2; }
fail() { printf 'build_engine: FAIL: %s\n' "$*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------

command -v "$GO_BIN" >/dev/null 2>&1 || fail "go not found (set GO=/path/to/go)"
GO_VERSION="$("$GO_BIN" version | awk '{print $3}')"
log "toolchain: $GO_VERSION"

if [ ! -d "$UPSTREAM_DIR" ]; then
    fail "the pinned upstream is absent — run phase1/scripts/fetch_upstream.sh first"
fi
if [ -f "$PHASE1_DIR/firefox-vpn-client.SHA256SUMS" ]; then
    (cd "$UPSTREAM_DIR" && sha256sum -c --quiet "$PHASE1_DIR/firefox-vpn-client.SHA256SUMS") \
        || fail "the vendored upstream copy does not match the pinned manifest — re-run fetch_upstream.sh"
    log "upstream manifest verified"
fi

# --- NDK discovery -----------------------------------------------------------

find_ndk() {
    if [ -n "$NDK_ROOT" ] && [ -x "$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${API_LEVEL}-clang" ]; then
        echo "$NDK_ROOT"
        return 0
    fi
    for candidate in \
        "${ANDROID_HOME:-}/ndk/$NDK_VERSION_PIN" \
        "${ANDROID_SDK_ROOT:-}/ndk/$NDK_VERSION_PIN" \
        "/opt/android-sdk/ndk/$NDK_VERSION_PIN" \
        "$HOME/Android/Sdk/ndk/$NDK_VERSION_PIN"; do
        if [ -x "$candidate/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${API_LEVEL}-clang" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

NDK_TOOLCHAIN=""
if find_ndk > /tmp/build_engine.ndk 2>/dev/null; then
    NDK_ROOT="$(cat /tmp/build_engine.ndk)"
    NDK_TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
    NDK_VERSION_DETECTED="$(basename "$NDK_ROOT")"
    [ "$NDK_VERSION_DETECTED" = "$NDK_VERSION_PIN" ] \
        || log "WARNING: NDK $NDK_VERSION_DETECTED != pin $NDK_VERSION_PIN (build proceeds; record the delta)"
    log "NDK: $NDK_ROOT"
else
    log "NDK not found — Android targets will be refused until ANDROID_NDK_HOME points at r28c"
    NDK_ROOT=""
fi

# --- the build matrix --------------------------------------------------------

# build_android <abi> <goarch> <compiler> [extra GO env assignments...]
build_android() {
    local abi="$1" goarch="$2" compiler="$3"
    shift 3

    [ -n "$NDK_TOOLCHAIN" ] || fail "Android target $abi requested but no NDK toolchain is available"
    local cc="$NDK_TOOLCHAIN/$compiler"
    [ -x "$cc" ] || fail "compiler not found/not executable: $cc"

    local out="$OUT_DIR/android/$abi"
    log "building android/$abi (CGO_ENABLED=1 CC=$compiler)"

    mkdir -p "$out"
    (
        cd "$FXV_DIR"
        # extra GO env assignments (e.g. GOARM=7) — exported, never run
        for kv in "$@"; do
            export "$kv"
        done
        # THE A1 RULE — enforced, not assumed:
        CGO_ENABLED=1 \
        GOOS=android \
        GOARCH="$goarch" \
        CC="$cc" \
        CGO_LDFLAGS="-Wl,-soname,libfirefoxvpn.so" \
        "$GO_BIN" build -trimpath -o "$out/libfirefoxvpn.so" ./cmd/libfirefoxvpn
    )

    chmod 0755 "$out/libfirefoxvpn.so"
    verify_elf "$out/libfirefoxvpn.so" "$abi"
}

# build_host — the pure-Go host binary (test/dart-integration vehicle).
build_host() {
    local out="$OUT_DIR/host"
    log "building host/linux-amd64 (pure Go; NOT an Android deliverable)"
    mkdir -p "$out"
    (cd "$FXV_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 "$GO_BIN" build -trimpath -o "$out/libfirefoxvpn" ./cmd/libfirefoxvpn)
    chmod 0755 "$out/libfirefoxvpn"
    file "$out/libfirefoxvpn" | tee "$out/libfirefoxvpn.file.txt"
}

# verify_elf — the honest post-build inspection (file + readelf + the
# Bionic resolver symbols; evidence recorded next to the binary).
verify_elf() {
    local bin="$1" abi="$2"
    local report="$bin.inspection.txt"
    {
        echo "== file =="
        file "$bin"
        echo
        echo "== readelf -h (header) =="
        readelf -h "$bin" 2>/dev/null | sed -n '1,20p'
        echo
        echo "== readelf -d (dynamic) =="
        readelf -d "$bin" 2>/dev/null
        echo
        echo "== NEEDED entries =="
        readelf -d "$bin" 2>/dev/null | grep NEEDED || echo "(none)"
        echo
        echo "== resolver symbols (Bionic getaddrinfo family) =="
        readelf --dyn-syms -W "$bin" 2>/dev/null | grep -E "getaddrinfo|freeaddrinfo|gai_strerror|res_search" || echo "(none found)"
        echo
        echo "== build id =="
        readelf -n "$bin" 2>/dev/null | grep -i "build id" || true
    } > "$report"
    cat "$report"

    # The CGO/Bionic evidence: an Android build MUST show the dynamic
    # linker and the getaddrinfo family (the A1 proof).
    if [ "${abi:-}" != "" ] && [ "${abi:-}" != "host" ]; then
        readelf -d "$bin" 2>/dev/null | grep -q NEEDED \
            || fail "$abi: no NEEDED entries — this is NOT a CGO/Bionic build (A1 violation)"
        readelf --dyn-syms -W "$bin" 2>/dev/null | grep -q "getaddrinfo" \
            || fail "$abi: getaddrinfo not imported — the Bionic system resolver is NOT wired (A1 violation)"
        log "$abi: CGO/Bionic evidence verified (NEEDED libc + getaddrinfo)"
    fi
}

# --- target selection --------------------------------------------------------

TARGETS="${1:-all}"
[ "$TARGETS" = "all" ] && TARGETS="arm64-v8a armeabi-v7a x86_64 host"

# Guard: an explicit CGO_ENABLED=0 in the environment is REFUSED for
# Android targets (the A1 decree — a pure-Go Android build regresses
# the real login).
if [ "${CGO_ENABLED:-1}" = "0" ]; then
    case "$TARGETS" in
        *arm64-v8a*|*armeabi-v7a*|*x86_64*)
            fail "CGO_ENABLED=0 refused for Android targets (the A1 decree: every Android ABI builds with CGO + NDK clang)"
            ;;
    esac
fi

for target in $TARGETS; do
    case "$target" in
        arm64-v8a)
            build_android arm64-v8a arm64 "aarch64-linux-android${API_LEVEL}-clang"
            ;;
        armeabi-v7a)
            build_android armeabi-v7a arm "armv7a-linux-androideabi${API_LEVEL}-clang" GOARM=7
            ;;
        x86_64)
            build_android x86_64 amd64 "x86_64-linux-android${API_LEVEL}-clang"
            ;;
        host)
            build_host
            ;;
        *)
            fail "unknown target: $target (arm64-v8a|armeabi-v7a|x86_64|host|all)"
            ;;
    esac
done

# --- the checksum manifest ---------------------------------------------------
# (written via a temp file OUTSIDE the output tree's listing so the
# manifest can never contain its own hash; existing artifacts are NEVER
# overwritten without a .bak backup)
if [ -f "$OUT_DIR/SHA256SUMS.txt" ]; then
    cp "$OUT_DIR/SHA256SUMS.txt" "$OUT_DIR/SHA256SUMS.txt.bak"
    log "previous manifest backed up (SHA256SUMS.txt.bak)"
fi
MANIFEST_TMP="$(mktemp /tmp/engine-sums.XXXXXX)"
(
    cd "$OUT_DIR"
    find . -type f \( -name 'libfirefoxvpn.so' -o -name 'libfirefoxvpn' \) -print0 \
        | sort -z | xargs -0 sha256sum
) > "$MANIFEST_TMP"
mv "$MANIFEST_TMP" "$OUT_DIR/SHA256SUMS.txt"

log "manifest: $OUT_DIR/SHA256SUMS.txt"
cat "$OUT_DIR/SHA256SUMS.txt"
log "done."
