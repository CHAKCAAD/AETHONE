#!/usr/bin/env bash
# fetch_upstream.sh — fetch the PINNED upstream core for the AETHONE
# Firefox VPN engine (phase1/fxv) and verify it bit-exactly.
#
#   upstream : https://github.com/UjuiUjuMandan/firefox-vpn-client
#   pin      : c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1
#               ("chore: update pinned Firefox identity (#7)",
#                2026-11-10) — the provenance base recorded in
#                fxv/ORIGIN.md and docs/FIREFOX_VPN_ENGINE.md.
#
#               Re-pinned 2026-11-11 by the owner's order from
#                55ad91a2ccea1c93e69c82a08a7681e279884db5 — the delta
#                analysis and verification live in
#                docs/firefox-vpn/core-update-2026-11-11.md.
#
# The pristine copy lands at phase1/firefox-vpn-client/ (GITIGNORED —
# the upstream declares NO license, so its code is never committed to
# this repository; only the fetch recipe + the SHA256 manifest are).
# fxv/go.mod's replace directive points at that directory.
#
# Usage:  phase1/scripts/fetch_upstream.sh [--force]
#   --force  re-fetch even when the copy already matches the pin.
#
# Exit codes: 0 = ready; 1 = fetch/verification failure.

set -euo pipefail

UPSTREAM_URL="https://github.com/UjuiUjuMandan/firefox-vpn-client.git"
UPSTREAM_PIN="c1c5d895a2c52c69a9e06e672eae5074c9cc3fa1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE1_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$PHASE1_DIR/firefox-vpn-client"
MANIFEST="$PHASE1_DIR/firefox-vpn-client.SHA256SUMS"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf 'fetch_upstream: %s\n' "$*" >&2; }

# 1. the pinned clone
log "cloning $UPSTREAM_URL @ $UPSTREAM_PIN"
git -c advice.detachedHead=false clone --quiet "$UPSTREAM_URL" "$WORK/src"
git -C "$WORK/src" checkout --quiet "$UPSTREAM_PIN"

ACTUAL="$(git -C "$WORK/src" rev-parse HEAD)"
if [ "$ACTUAL" != "$UPSTREAM_PIN" ]; then
    log "PIN MISMATCH: expected $UPSTREAM_PIN, got $ACTUAL — refusing"
    exit 1
fi
log "pin verified: $ACTUAL"

# 2. sync the pristine copy (no .git, no build artifacts)
mkdir -p "$DEST_DIR"
if [ "${1:-}" != "--force" ] && [ -f "$MANIFEST" ]; then
    if (cd "$DEST_DIR" && sha256sum -c --quiet "$MANIFEST" 2>/dev/null); then
        log "existing copy matches the manifest — ready (use --force to re-fetch)"
        exit 0
    fi
    log "existing copy does not match — re-syncing"
fi

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
git -C "$WORK/src" archive "$UPSTREAM_PIN" | tar -x -C "$DEST_DIR"

# 2b. the AETHONE patch layer (phase1/scripts/upstream_patches/*.patch,
#     applied in lexical order — git apply -p1 from the upstream root).
#     The upstream declares NO license, so its code is never committed;
#     the PATCHES are ours and committed, and the manifest below pins
#     the PATCHED tree byte-exactly (a stale or half-applied copy cannot
#     build — build_engine.sh verifies against the same manifest).
#     0001 (2026-11-16, round 10): the reference's network posture —
#     hellosplit + the ONE desktop-Firefox identity + the Guardian 451
#     recovery chain (doubled path + the automatic shared relay pool).
PATCH_DIR="$SCRIPT_DIR/upstream_patches"
if [ -d "$PATCH_DIR" ]; then
    for patch_file in "$PATCH_DIR"/*.patch; do
        [ -e "$patch_file" ] || continue
        log "applying $(basename "$patch_file")"
        (cd "$DEST_DIR" && git apply -p1 "$patch_file") \
            || { log "FAILED to apply $(basename "$patch_file") — refusing"; exit 1; }
    done
fi

# 3. the integrity manifest (committed; makes the gitignored copy
#    verifiable without committing its contents — INCLUDING the patch
#    layer, so the manifest describes the patched tree)
(
    cd "$DEST_DIR"
    find . -type f -print0 | sort -z | xargs -0 sha256sum
) > "$MANIFEST"
log "wrote $MANIFEST ($(wc -l < "$MANIFEST") files)"

log "upstream ready at $DEST_DIR (pin $UPSTREAM_PIN + the AETHONE patch layer)"
