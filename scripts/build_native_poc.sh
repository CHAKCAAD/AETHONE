#!/usr/bin/env bash
# AETHONE — Stage 2 per-app routing PoC native build (Stage 2, 2026-11-18).
#
# Thin wrapper around scripts/build_native.sh that builds the zeptun stage
# from the VENDORED, PATCHED tree (native/zeptun/ — byte-identical to the
# frozen pin 08a1ab0 plus the per-app-routing patch) instead of the upstream
# clone. Every other component (aether, lyrebird, psiphon) still builds from
# its frozen pin exactly like the CI recipe. The underlying script's default
# path is untouched: a run WITHOUT this wrapper stays byte-for-byte the
# original supply chain.
#
# Usage (same arguments as build_native.sh; ANDROID_NDK_HOME + ZIG required):
#   scripts/build_native_poc.sh --abi arm64-v8a --rust-target aarch64-linux-android \
#       --goarch arm64 --api-level 29 --src-cache .srccache --out out/arm64-v8a
#
# The wrapper COPIES the vendored tree into the source cache (never builds
# inside the repository) so the build's cache hygiene (zig-out wipe, cache
# restore semantics) keeps working.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDORED="$REPO_ROOT/native/zeptun"

[ -d "$VENDORED/src" ] || { echo "FATAL: vendored zeptun tree missing: $VENDORED" >&2; exit 1; }

# A scratch copy outside the repository: the build wipes zig-out and the
# ndk-build stage writes into the tree — the vendored reference export must
# stay pristine.
POC_SRC_CACHE="${POC_SRC_CACHE:-$(mktemp -d "$REPO_ROOT/.zeptun_poc.XXXXXX")}"
trap 'rm -rf "$POC_SRC_CACHE"' EXIT
cp -a "$VENDORED" "$POC_SRC_CACHE/zeptun"
# The vendored export carries no .git (it is part of the parent repo).
echo "== build_native_poc: zeptun source = vendored patch at $VENDORED (copied to $POC_SRC_CACHE/zeptun) =="

export ZEPTUN_LOCAL_SRC="$POC_SRC_CACHE/zeptun"
exec bash "$SCRIPT_DIR/build_native.sh" "$@"
