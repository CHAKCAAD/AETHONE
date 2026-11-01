#!/usr/bin/env bash
# AETHONE — build all native components for ONE ABI at the frozen pins. (v4)
# Status: DELIVERED, NOT TESTED (no Android toolchain in the analysis
# environment; first execution happens on GitHub Actions after the employer
# pushes this repository). Every build command replicates the upstream
# evidence exactly. The lyrebird SOURCE-ORIGIN proof, however, was executed
# end-to-end in the analysis environment: evidence/lyrebird_pin_independent_test.txt.
#
# v4 changes (employer review of bundle v3, 2026-10-31):
#   Lyrebird pin proof reworked (fix #3) — the pin itself is UNCHANGED
#   (fc105a03c0e0, N8):
#     * pt-build-pin.patch v4 makes the proxy fallback prove the source:
#       the zip is verified against sum.golang.org (H1 dirhash locally
#       recomputed); mismatch/missing/unreachable => HARD ABORT. The proof
#       file $SRC_CACHE/lyrebird-source-proof.json (OUTSIDE the uploaded
#       artifact tree) is copied into manifest.json.
#     * The binary check becomes path-aware: git path still requires the
#       pin inside `go version -m` (vcs.revision == pin — mechanism proven
#       in evidence/lyrebird_pin_independent_test.txt [7]); proxy path
#       REQUIRES the sumdb-verified proof file instead — a binary built
#       from the .git-less proxy zip records NO main-module commit
#       ("(devel)"; proven in the same evidence file [6]), so the v3
#       grep-on-binary was structurally impossible there and would have
#       aborted every proxy-path build even with a perfectly pinned source.
#     * buildvcs HAZARD recorded: a proxy-path build inside ANY enclosing
#       git worktree stamps THAT worktree's unrelated vcs.revision — vcs.*
#       lines are never treated as pin evidence on this path.
#
# v3 changes (employer review of bundle v2, 2026-10-31):
#   1. Zeptun intermediate build products can no longer enter the artifact.
#      v2 ran zeptun's ndk-build with OUT="$OUT/zeptun-build", and since the
#      whole $OUT is uploaded, ndk-obj/, ndk-libs/ and jniLibs/ leaked into
#      the artifact. v3 builds them under "$SRC_CACHE/zeptun-build.tmp"
#      (NEVER inside $OUT), wipes that dir before AND after the build, and
#      copies out only libzeptun-jni.so. A final whitelist guard asserts the
#      artifact contains EXACTLY the expected final outputs + manifest.json.
#   2. The two remaining `|| true` (ZIG resolution, `go version -m`) are
#      converted to explicit fail-closed error handling. build_native.sh
#      now contains ZERO `|| true` (v2 still had two — its README claim
#      "no || true anywhere" was wrong and is corrected in v3).
#   3. Foreign-ABI export guard simplified (zeptun-build no longer exists
#      under $OUT, so no path exclusion is needed).
#
# v2 changes (kept from the employer review of v1, 2026-10-31):
#   1. Zeptun output paths corrected against the real frozen sources:
#      - libzeptun.so     <- $ZEPTUN_SRC/zig-out/android/jniLibs/$ABI/   (zig build android)
#      - libzeptun.a      <- $ZEPTUN_SRC/zig-out/android/prebuilt/$ABI/  (zig build android)
#      - libzeptun-jni.so <- $ZBUILD/jniLibs/$ABI/                       (ndk-build; the OUT
#        env var of zeptun's scripts/build_android.sh scopes the ndk-build output — v3: $ZBUILD
#        is OUTSIDE $OUT, under the source cache, and is wiped after the copy)
#      Every expected file is tested with [ -f ] BEFORE copying; a missing file
#      aborts the build with an explicit error.
#   2. zig-out is wiped before building so cached source trees can never leak
#      stale ABIs (the cache persists the whole source dir between CI runs).
#   3. Recorded upstream behaviour + hard guard: `zig build android` ALWAYS
#      builds all four upstream ABIs (x86 included) — build.zig hardcodes them;
#      zeptun's ABIS variable only scopes the ndk-build stage. AETHONE exports
#      ONLY the requested ABI into the artifact directory and asserts that no
#      other ABI directory appears there (N5: no x86 in the shipped bundle).
#   4. Lyrebird pin hardening: the frozen Aether pt-build.sh silently continued
#      on the default branch when its checkout failed (N8 violation). The
#      recorded patch scripts/pt-build-pin.patch turns that into a hard abort
#      and verifies HEAD == fc105a03c0e0. After the build, `go version -m`
#      must prove the pin inside the produced binary (vcs.revision or the
#      pinned pseudo-version) — and a failing `go version -m` itself is now a
#      hard abort (v3 fix 2). The v1 self-copy line (`cp X X || true`) is gone.
#   5. manifest.json records the real path (relative to OUT) and a proper
#      group/component per artifact.
#
# Usage (see native-ci.yml):
#   build_native.sh --abi arm64-v8a --rust-target aarch64-linux-android \
#                   --goarch arm64 --goarm "" --api-level 29 \
#                   --src-cache .srccache --out out/arm64-v8a
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # <repo>/scripts
PT_PATCH="$SCRIPT_DIR/pt-build-pin.patch"
# sha256 of the patched pt-build.sh
#   v4:   (Aether @ d58f9d56 + pt-build-pin.patch v4)    = 6bd5fa74...
#   v4.2: (Aether @ d58f9d56 + pt-build-pin.patch v4.2)  — v4.2 adds the
#         official Go-client (GOSUMDB) signed-record verification + zip
#         identity check on the proxy path (employer review of v4.1, item 2).
#         Pin fc105a03c0e0 unchanged (N8).
PT_PATCHED_SHA256="3fbee02f78a4613a1452c32037c78c9d3a51ea4cb84edd8c4ebe808c023c4b88"

ABI=""; RUST_TARGET=""; GOARCH=""; GOARM=""; API_LEVEL=""; SRC_CACHE=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --abi) ABI="$2"; shift 2 ;;
    --rust-target) RUST_TARGET="$2"; shift 2 ;;
    --goarch) GOARCH="$2"; shift 2 ;;
    --goarm) GOARM="${2}"; shift 2 ;;
    --api-level) API_LEVEL="$2"; shift 2 ;;
    --src-cache) SRC_CACHE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
for req in ABI RUST_TARGET GOARCH API_LEVEL SRC_CACHE OUT; do
  [ -n "${!req:-}" ] || { echo "missing --$(echo "$req" | tr 'A-Z' a-z | tr '_' '-')" >&2; exit 2; }
done
die() { echo "FATAL: $*" >&2; exit 1; }
require_file() { [ -f "$1" ] || die "expected build output missing: $1"; }

: "${AETHER_REPO:=https://github.com/CluvexStudio/Aether.git}"
: "${AETHER_SHA:=d58f9d568083129ce2c767c85054021eb3ee6a38}"
: "${ZEPTUN_REPO:=https://github.com/Noisemux/zeptun.git}"
: "${ZEPTUN_SHA:=08a1ab05aab315b7872ed582c52b7c230930d05d}"
: "${PSIPHON_FORK_REPO:=https://github.com/CluvexStudio/psiphon-tunnel-core.git}"
: "${PSIPHON_FORK_SHA:=2956a96b56fe09b99e72a8eb4bed3e79d29e3543}"
: "${LYREBIRD_PIN:=fc105a03c0e0}"
[ -n "${ANDROID_NDK_HOME:-}" ] || { echo "ANDROID_NDK_HOME not set" >&2; exit 2; }
# v3 fix 2a: explicit fail-closed zig resolution (was `|| true` in v2)
if [ -z "${ZIG:-}" ]; then
  ZIG="$(command -v zig)" || die "zig not on PATH and ZIG not set"
fi
[ -n "$ZIG" ] || die "zig resolver is empty"
[ -x "$ZIG" ] || die "zig resolver is not an executable: $ZIG"
[ -f "$PT_PATCH" ] || die "pin-hardening patch not found: $PT_PATCH"

clone_pin() { # repo sha dir
  local repo="$1" sha="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    git clone --filter=blob:none "$repo" "$dir"
  fi
  git -C "$dir" checkout "$sha"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ] || { echo "pin mismatch in $dir" >&2; exit 1; }
}

echo "== build_native: ABI=$ABI target=$RUST_TARGET goarch=$GOARCH goarm='$GOARM' api=$API_LEVEL =="
echo "== zig: $("$ZIG" version 2>/dev/null || echo unknown) | ndk: $ANDROID_NDK_HOME =="
mkdir -p "$SRC_CACHE" "$OUT"

# ---------------------------------------------------------------- zeptun ----
echo "== [1/4] zeptun @ $ZEPTUN_SHA (Zig $("$ZIG" version 2>/dev/null || echo unknown)) =="
ZEPTUN_SRC="$SRC_CACHE/zeptun"
clone_pin "$ZEPTUN_REPO" "$ZEPTUN_SHA" "$ZEPTUN_SRC"
# Cache hygiene: zig-out persists inside the cached source tree; wipe it so a
# restored cache can never export a stale or wrong-ABI library (see v2 note 2).
rm -rf "$ZEPTUN_SRC/zig-out"
# v3 fix 1: intermediate build dir OUTSIDE the artifact tree ($OUT is uploaded
# in full; SRC_CACHE is not). Wiped before the build (stale-cache hygiene) and
# after the copy (no intermediate ever survives a successful build).
ZBUILD="$SRC_CACHE/zeptun-build.tmp"
rm -rf "$ZBUILD"
(
  cd "$ZEPTUN_SRC"
  # NOTE (recorded upstream behaviour): `zig build android` unconditionally
  # builds ALL FOUR upstream ABIs (x86 included) — the ABIS variable below
  # only scopes the ndk-build (libzeptun-jni.so) stage. AETHONE ships three
  # ABIs (N5): only this job's $ABI is ever copied out of the build dirs,
  # and the guards below assert nothing else lands in the export directory.
  export ZIG ANDROID_NDK_HOME ABIS="$ABI" OUT="$ZBUILD"
  sh scripts/build_android.sh
)
# Real output locations, verified against zeptun @ 08a1ab05:
#   build.zig "android" step installs into zig-out/android/{jniLibs,prebuilt}/<abi>
#   scripts/build_android.sh puts the ndk-build output under $OUT/jniLibs/<abi>
ZSO="$ZEPTUN_SRC/zig-out/android/jniLibs/$ABI/libzeptun.so"
ZSA="$ZEPTUN_SRC/zig-out/android/prebuilt/$ABI/libzeptun.a"
JNI="$ZBUILD/jniLibs/$ABI/libzeptun-jni.so"
require_file "$ZSO"; require_file "$ZSA"; require_file "$JNI"
mkdir -p "$OUT/zeptun"
cp "$ZSO" "$OUT/zeptun/libzeptun.so"       # engine (Zig, 16KB-aligned via build.zig)
cp "$JNI" "$OUT/zeptun/libzeptun-jni.so"   # JNI bridge (ndk-build, Application.mk: android-29, max-page-size=16384)
cp "$ZSA" "$OUT/zeptun/libzeptun.a"        # static engine (source for the JNI link)
rm -rf "$ZBUILD"   # v3 fix 1: intermediates never survive the copy
# Export guard: exactly the three zeptun files, and no foreign ABI anywhere in
# the exported tree (N5 — an x86 file must never ship).
nfiles=$(find "$OUT/zeptun" -maxdepth 1 -type f | wc -l)
[ "$nfiles" -eq 3 ] || die "zeptun export must contain exactly 3 files, got $nfiles"
# N5: reject only the forbidden legacy 32-bit x86 ABI in exported artifacts.
while IFS= read -r forbidden; do
  [ -z "$forbidden" ] && continue
  die "forbidden x86 ABI directory in export dir (N5): $forbidden"
done < <(find "$OUT" -mindepth 1 -type d -name x86 -print 2>/dev/null)
echo "[zeptun $ABI] exported: libzeptun.so libzeptun-jni.so libzeptun.a (intermediates wiped: $ZBUILD)"

# ---------------------------------------------------------------- aether ----
echo "== [2/4] aether @ $AETHER_SHA (cargo-ndk --platform $API_LEVEL, features tor) =="
AETHER_SRC="$SRC_CACHE/aether"
clone_pin "$AETHER_REPO" "$AETHER_SHA" "$AETHER_SRC"
(
  cd "$AETHER_SRC/aether"
  under=$(echo "$RUST_TARGET" | tr '-' '_')
  export "BORING_BSSL_RUST_CPPLIB_${under}=static:-bundle=c++"   # exactly as upstream release.yml

  # Aether's Cargo.lock pins boring-sys 5.3.0. Its upstream helper searches for
  # the literal "ERR_LIB_SSL:", but Bindgen 0.72 emits
  # "pub const ERR_LIB_SSL : _bindgen_ty_2 = ...". That whitespace makes the
  # helper fall back to the wrong anonymous type (_bindgen_ty_1).
  # Fetch with --locked, patch only that exact helper in the exact pinned
  # crate source, then clear both the host-side build-script cache and this
  # Android target's boring-sys cache. With Cargo --target, build scripts are
  # compiled for the host in target/release, separately from target/<triple>.
  # Clearing only target/<triple> leaves the old host build script executable.
  echo "== [boring-sys] fetch locked sources and apply 5.3.0 enum-name fix =="
  cargo fetch --locked --target "$RUST_TARGET"
  python3 - "${CARGO_HOME:-$HOME/.cargo}" <<'PY_BORING_SYS'
import hashlib
import sys
from pathlib import Path

cargo_home = Path(sys.argv[1]).expanduser()
lock_path = Path("Cargo.lock")
if not lock_path.is_file():
    raise SystemExit("FATAL: Cargo.lock is missing; refusing an unpinned boring-sys patch.")

lock_text = lock_path.read_text(encoding="utf-8")
if 'name = "boring-sys"\nversion = "5.3.0"\n' not in lock_text:
    raise SystemExit("FATAL: Cargo.lock does not pin boring-sys 5.3.0 exactly.")

registry_src = cargo_home / "registry" / "src"
matches = sorted(registry_src.glob("*/boring-sys-5.3.0/build/main.rs"))
if len(matches) != 1:
    raise SystemExit(
        "FATAL: expected exactly one boring-sys 5.3.0 build/main.rs under "
        f"{registry_src}, found {len(matches)}."
    )

path = matches[0]
source = path.read_text(encoding="utf-8")
old = """    let enum_type = src
        .split_once("ERR_LIB_SSL:")
        .and_then(|(_, def)| Some(def.split_once('=')?.0))
        .unwrap_or("_bindgen_ty_1");"""
new = """    let enum_type = src
        .split_once("pub const ERR_LIB_SSL")
        .and_then(|(_, def)| {
            let declaration = def.split_once('=')?.0;
            declaration.rsplit_once(':').map(|(_, ty)| ty.trim())
        })
        .filter(|ty| {
            !ty.is_empty() && ty.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        })
        .unwrap_or("_bindgen_ty_1");"""

before = hashlib.sha256(source.encode("utf-8")).hexdigest()
if source.count(old) == 1:
    source = source.replace(old, new, 1)
    path.write_text(source, encoding="utf-8")
    state = "APPLIED"
elif source.count(new) == 1:
    state = "ALREADY_APPLIED"
else:
    raise SystemExit(
        "FATAL: boring-sys 5.3.0 helper did not match the one expected upstream "
        "implementation; no source was changed."
    )

after = hashlib.sha256(source.encode("utf-8")).hexdigest()
print(f"boring-sys source: {path}")
print(f"Patch state: {state}")
print(f"SHA256 before: {before}")
print(f"SHA256 after:  {after}")
PY_BORING_SYS

  removed=0
  for profile_root in "target/release" "target/$RUST_TARGET/release"; do
    for subdir in build .fingerprint deps; do
      dir="$profile_root/$subdir"
      [ -d "$dir" ] || continue
      count=$(find "$dir" -mindepth 1 -maxdepth 1 \\
        \\( -name 'boring-sys-*' -o -name 'libboring_sys-*' \\) -print | wc -l)
      if [ "$count" -gt 0 ]; then
        find "$dir" -mindepth 1 -maxdepth 1 \\
          \\( -name 'boring-sys-*' -o -name 'libboring_sys-*' \\) -exec rm -rf {} +
        echo "Removed $count stale boring-sys entries from $dir"
        removed=$((removed + count))
      fi
    done
  done
  echo "Total stale boring-sys cache entries removed: $removed"

  # Fail closed if a stale build-script output directory survived.
  for dir in target/release/build "target/$RUST_TARGET/release/build"; do
    if [ -d "$dir" ] && find "$dir" -mindepth 1 -maxdepth 1 \\
       -type d -name 'boring-sys-*' -print -quit | grep -q .; then
      echo "FATAL: stale boring-sys build directory remains under $dir" >&2
      exit 1
    fi
  done

  # The upstream cargo-ndk build invocation remains unchanged.
  if cargo ndk -t "$ABI" --platform "$API_LEVEL" build --release --features tor; then
    :
  else
    cargo_status=$?
    echo "========== BORING-SYS FAILURE SNAPSHOT =========="
    echo "ABI=$ABI TARGET=$RUST_TARGET"
    build_root="target/$RUST_TARGET/release/build"

    mapfile -d '' binding_files < <(
      find "$build_root" -type f \
        -path '*/boring-sys-*/out/bindings.rs' -print0 2>/dev/null
    )

    if [ "${#binding_files[@]}" -eq 0 ]; then
      echo "No bindings.rs found after cargo failure."
    fi

    for f in "${binding_files[@]}"; do
      outdir="${f%/bindings.rs}"
      build_dir="$(dirname "$outdir")"

      echo "========== BINDINGS FILE =========="
      echo "PATH=$f"
      stat "$f"
      wc -lc "$f"
      sha256sum "$f"
      echo "--- First 80 lines ---"
      sed -n '1,80p' "$f"
      echo "--- Relevant Rust declarations ---"
      if grep -n -E 'ERR_LIB_SSL|ERR_LIB_NONE|bindgen_ty_1|ErrLib' "$f"; then
        :
      else
        echo "No relevant declaration found."
      fi

      echo "========== BORINGSSL ERR.H =========="
      for h in \
        "$outdir/boringssl/include/openssl/err.h" \
        "$outdir/boringssl/src/include/openssl/err.h"; do
        if [ -f "$h" ]; then
          echo "HEADER=$h"
          grep -n -C 5 -E 'ERR_LIB_SSL|ERR_LIB_NONE|ERR_LIB_SYS' "$h" || :
        fi
      done

      echo "========== BORING-SYS BUILD OUTPUT =========="
      if [ -f "$build_dir/output" ]; then
        sed -n '1,240p' "$build_dir/output"
      else
        echo "No build output file."
      fi
    done

    exit "$cargo_status"
  fi
  bin="target/$RUST_TARGET/release/aether"
  [ -f "$bin" ] || { echo "FATAL: aether binary missing: $bin" >&2; exit 1; }
  # Upstream's own guard: aether must never need libc++_shared.so
  needed=$(readelf -d "$bin" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
  echo "[aether $ABI] NEEDED: $needed"
  grep -qx 'libc++_shared.so' <<<"$needed" && { echo "ERROR: aether needs libc++_shared.so"; exit 1; }
  mkdir -p "$OUT/aether"
  cp "$bin" "$OUT/aether/aether"
)

# ------------------------------------------- lyrebird (Aether's frozen script, pin-hardened) ----
echo "== [3/4] lyrebird via Aether pt-build.sh @ $AETHER_SHA (pin $LYREBIRD_PIN enforced) =="
# The frozen script's fallback ("pinned commit is gone, using the default
# branch") violates N8. Apply the recorded patch (aborts on checkout failure,
# verifies HEAD == pin, proves the proxy zip against sum.golang.org).
# v4: the patch writes a source-origin PROOF file; it lives under $SRC_CACHE
# (never inside $OUT, which is uploaded as the artifact and guarded by an
# exact whitelist).
PT_LYREBIRD_PROOF_FILE="$SRC_CACHE/lyrebird-source-proof.json"
rm -f "$PT_LYREBIRD_PROOF_FILE"
export PT_LYREBIRD_PROOF_FILE
if grep -q "AETHONE (N8 pin hardening" "$AETHER_SRC/pt-build.sh"; then
  echo "pt-build.sh already carries the pin-hardening patch (cached tree)"
else
  git -C "$AETHER_SRC" apply --whitespace=nowarn "$PT_PATCH"
fi
patched_sha=$(sha256sum "$AETHER_SRC/pt-build.sh" | cut -d' ' -f1)
[ "$patched_sha" = "$PT_PATCHED_SHA256" ] || die "patched pt-build.sh sha256 mismatch: $patched_sha"
(
  cd "$AETHER_SRC"
  # Upstream android job replicates: GOOS=linux static transports (see release.yml
  # comment: android needs cgo, a CGO_ENABLED=0 linux ELF runs as-is under Android).
  bash pt-build.sh linux "$GOARCH" "$OUT/aether/pt" "$GOARM" ""
)
require_file "$OUT/aether/pt/lyrebird"
# ---- Artifact-level lyrebird source-origin proof (v4, employer fix #3) -----
#   git path   -> proof file (path=git, head=FULL sha) AND the binary's
#                 `go version -m` contains the pin (vcs.revision == pin;
#                 buildvcs mechanism proven in
#                 evidence/lyrebird_pin_independent_test.txt [7])
#   proxy path -> proof file (path=proxy, version, zip sha256, dirhash
#                 verified against sum.golang.org). A binary built from the
#                 .git-less proxy zip records NO main-module commit —
#                 "(devel)", no vcs.* lines when built outside any git
#                 worktree, and UNRELATED worktree metadata when built
#                 inside one (proven in the same evidence file [6]). The
#                 v3 grep-on-binary was therefore structurally impossible
#                 on this path; the sumdb-verified zip is the proof here.
# Any missing proof still aborts the build with an explicit message (N8).
[ -f "$PT_LYREBIRD_PROOF_FILE" ] || die "lyrebird source-origin proof file missing — pt-build.sh did not record it; pin NOT proven (N8)"
proof_path=$(sed -n 's/.*"path":"\([^"]*\)".*/\1/p' "$PT_LYREBIRD_PROOF_FILE")
prov=$(go version -m "$OUT/aether/pt/lyrebird" 2>&1) || die "go version -m failed on lyrebird — build info cannot be recorded (N8)"
echo "$prov" | sed -n '1,40p'
binary_pin="absent (expected on the proxy path: no .git in the source; proven in evidence/lyrebird_pin_independent_test.txt [6])"
case "$proof_path" in
  git)
    grep -q "${LYREBIRD_PIN}" <<<"$prov" || die "lyrebird pin NOT proven in the built binary (go version -m lacks $LYREBIRD_PIN; git path requires vcs.revision == pin)"
    binary_pin="vcs.revision contains the pin"
    echo "[lyrebird $ABI] pin $LYREBIRD_PIN proven in binary (git path)"
    ;;
  proxy)
    grep -q '"pin":"'"${LYREBIRD_PIN}"'"' "$PT_LYREBIRD_PROOF_FILE" || die "lyrebird proof file does not reference the pin (N8)"
    grep -q '"dirhash":"h1:' "$PT_LYREBIRD_PROOF_FILE" || die "lyrebird proof file lacks the sumdb-verified dirhash (N8)"
    if grep -q "${LYREBIRD_PIN}" <<<"$prov"; then
      binary_pin="build info contains the pin"
    else
      echo "[lyrebird $ABI] NOTE: binary build info carries no pin — EXPECTED on the proxy path (no .git; evidence/lyrebird_pin_independent_test.txt [6]); pin proven via the sumdb-verified source zip instead"
    fi
    echo "[lyrebird $ABI] pin $LYREBIRD_PIN proven via sumdb-verified source zip (proxy path)"
    ;;
  *)
    die "unknown lyrebird source-origin path in proof file: '$proof_path' (N8)"
    ;;
esac
echo "$prov" > "$SRC_CACHE/lyrebird-buildinfo.txt"   # raw, for the record

# ---------------------------------- psiphon (AETHONE N1 pin 2956a96 — NOT aether's 83aa73b) ----
echo "== [4/4] psiphon @ $PSIPHON_FORK_SHA (N1 pin; fork of 83aa73b, +566/-3 noise profiles) =="
PSIPHON_SRC="$SRC_CACHE/psiphon-fork"
clone_pin "$PSIPHON_FORK_REPO" "$PSIPHON_FORK_SHA" "$PSIPHON_SRC"
(
  cd "$PSIPHON_SRC"
  # Build env replicated from Aether's psiphon-build.sh (GOOS=linux static,
  # CGO_ENABLED=0 — runs as-is under Android per upstream release.yml note):
  export GOOS=linux GOARCH="$GOARCH" GOARM="$GOARM" CGO_ENABLED=0 GOFLAGS=-mod=vendor GOTOOLCHAIN=local
  mkdir -p "$OUT/aether/pt"
  go build -trimpath -ldflags "-s -w" -o "$OUT/aether/pt/psiphon-tunnel-core" ./ConsoleClient
  [ -f "$OUT/aether/pt/psiphon-tunnel-core" ] || { echo "FATAL: psiphon-tunnel-core missing after go build" >&2; exit 1; }
)

# ---------------------------------------------------------------- manifest ----
MANIFEST="$OUT/manifest.json"
{
  echo '{'
  echo "  \"abi\": \"$ABI\","
  echo "  \"api_level\": $API_LEVEL,"
  echo "  \"pins\": {"
  echo "    \"aether\": \"$AETHER_SHA\","
  echo "    \"zeptun\": \"$ZEPTUN_SHA\","
  echo "    \"psiphon_fork\": \"$PSIPHON_FORK_SHA\","
  echo "    \"lyrebird\": \"$LYREBIRD_PIN (enforced by scripts/pt-build-pin.patch @ $AETHER_SHA)\""
  echo "  },"
  # v4: record HOW the pinned lyrebird source was proven (git checkout or
  # sumdb-verified proxy zip) + the binary build-info check outcome.
  echo "  \"lyrebird_pin_proof\": $(sed "s/}$/,\"binary_build_info_pin\":\"$binary_pin\"}/" "$PT_LYREBIRD_PROOF_FILE" | tr -d '\n'),"
  echo '  "artifacts": ['
  first=1
  # path  = real location relative to OUT
  # group = real directory group under OUT
  for spec in \
    "zeptun/libzeptun.so|zeptun|zeptun-engine" \
    "zeptun/libzeptun-jni.so|zeptun|zeptun-jni" \
    "zeptun/libzeptun.a|zeptun|zeptun-static" \
    "aether/aether|aether|aether" \
    "aether/pt/lyrebird|aether/pt|lyrebird" \
    "aether/pt/psiphon-tunnel-core|aether/pt|psiphon-fork"; do
    IFS='|' read -r rel group component <<<"$spec"
    f="$OUT/$rel"
    [ -f "$f" ] || { echo "MISSING artifact: $f" >&2; exit 1; }
    [ $first -eq 1 ] || echo ','
    first=0
    sha=$(sha256sum "$f" | cut -d' ' -f1)
    echo "    {\"path\": \"$rel\", \"group\": \"$group\", \"component\": \"$component\", \"sha256\": \"$sha\", \"bytes\": $(wc -c <"$f")}"
  done
  echo '  ]'
  echo '}'
} > "$MANIFEST"

# ---------------------------------------------- artifact whitelist guard (v3) ----
# The uploaded artifact must contain EXACTLY the expected final outputs and
# the manifest — nothing else. This is the build-time counterpart of the
# hygiene check in scripts/inspect_elf.sh (employer fix #2).
expected_files="aether/aether
aether/pt/lyrebird
aether/pt/psiphon-tunnel-core
manifest.json
zeptun/libzeptun-jni.so
zeptun/libzeptun.a
zeptun/libzeptun.so"
actual_files=$(cd "$OUT" && find . -type f | sed 's|^\./||' | sort)
expected_files=$(sort <<<"$expected_files")
if [ "$actual_files" != "$expected_files" ]; then
  die "artifact tree does not match the expected file set (intermediates must never be uploaded):
--- expected (sorted) ---
$expected_files
--- actual (sorted) ---
$actual_files"
fi
echo "== done: $OUT (manifest at $MANIFEST; artifact contains exactly the 6 expected outputs + manifest) =="
cat "$MANIFEST"
