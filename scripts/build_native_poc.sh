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
# The wrapper COPIES the vendored tree into a scratch dir (never builds
# inside the repository) so the build's cache hygiene (zig-out wipe, cache
# restore semantics) keeps working.
#
# Stage 2.1 safety fix (2026-11-18, owner review of the first PoC cut):
#   * the wrapper used to `exec` build_native.sh — an exec'd shell never
#     exits, so the EXIT trap never ran and the scratch copy leaked on every
#     run. The child is now a normal subprocess and the wrapper exits with
#     the child's exact status (trap runs on success AND failure).
#   * the trap used to `rm -rf "$POC_SRC_CACHE"` — a caller-provided env
#     value, i.e. an ARBITRARY pre-existing path a user could point at any
#     directory. Cleanup now only ever removes POC_SCRATCH_DIR: a directory
#     THIS run created via mktemp (fresh by construction, ownership proven).
#     POC_SRC_CACHE, when set, is honored only as the PARENT into which the
#     fresh scratch dir is placed — it is mkdir -p'd if missing and NEVER
#     deleted. No path that existed before this run is ever removed.
# Verified by scripts/test_build_native_poc.sh (stubbed child; success,
# failure, signal, user-path and missing-tree scenarios).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDORED="$REPO_ROOT/native/zeptun"

[ -d "$VENDORED/src" ] || { echo "FATAL: vendored zeptun tree missing: $VENDORED" >&2; exit 1; }

# Scratch-directory lifecycle. POC_SCRATCH_DIR is the ONLY path this script
# ever deletes, and it is always a directory mktemp just created inside this
# run (default: next to the repo; or inside the caller-supplied POC_SRC_CACHE
# parent, which itself is never touched by cleanup).
POC_SCRATCH_DIR=""
cleanup() {
  if [ -n "$POC_SCRATCH_DIR" ]; then
    rm -rf -- "$POC_SCRATCH_DIR"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT   # run the EXIT trap (=> cleanup) on Ctrl-C too
trap 'exit 143' TERM  # ... and on SIGTERM

if [ -n "${POC_SRC_CACHE:-}" ]; then
  # Caller-chosen location: create it if missing (creating is safe; we never
  # delete it), then put OUR fresh scratch dir inside it.
  mkdir -p -- "$POC_SRC_CACHE"
  POC_SCRATCH_DIR="$(mktemp -d "$POC_SRC_CACHE/.zeptun_poc.XXXXXX")"
else
  POC_SCRATCH_DIR="$(mktemp -d "$REPO_ROOT/.zeptun_poc.XXXXXX")"
fi
POC_SRC_DIR="$POC_SCRATCH_DIR"

# Fresh empty scratch => the copy target can never pre-exist (no nesting).
cp -a "$VENDORED" "$POC_SRC_DIR/zeptun"
# The vendored export carries no .git (it is part of the parent repo).
echo "== build_native_poc: zeptun source = vendored patch at $VENDORED (copied to $POC_SRC_DIR/zeptun) =="

export ZEPTUN_LOCAL_SRC="$POC_SRC_DIR/zeptun"

# NOT exec: the wrapper must survive the child so the EXIT trap can clean up
# the scratch copy. The child's exit status is preserved exactly (0 on
# success, its own code on failure — `|| rc=$?` keeps set -e from firing).
rc=0
bash "$SCRIPT_DIR/build_native.sh" "$@" || rc=$?
exit "$rc"
