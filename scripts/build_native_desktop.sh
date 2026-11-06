#!/usr/bin/env bash
# AETHONE — build all native components for the DESKTOP targets at the frozen
# pins (v4.36 desktop round). The desktop twin of scripts/build_native.sh:
# same pins, same proof machinery, same whitelist discipline — different
# outputs (host-target builds, no NDK, no cargo-ndk):
#
#   Linux (ubuntu runner):
#     aether  — cargo build --release --features tor (host x86_64-unknown-
#                linux-gnu) → libaether.so (cdylib, in-process C API)
#     lyrebird — pt-build.sh linux amd64 (pin-hardened, source-origin proof)
#     psiphon — go build ./ConsoleClient GOOS=linux (static, CGO off)
#     zeptun — zig build -Doptimize=ReleaseFast → zig-out/lib/libzeptun.so
#   Windows (windows runner, git-bash):
#     aether  — cargo build --release --features tor (host x86_64-pc-windows-
#                msvc) → aether.dll
#     lyrebird — pt-build.sh windows amd64
#     psiphon — go build GOOS=windows → psiphon.exe
#     zeptun — zig build → zig-out/lib/zeptun.dll + wintun.dll
#              (fetch_wintun.sh with the pinned sha256 — the adapter DLL the
#              engine loads from the application directory)
#
# Usage:
#   build_native_desktop.sh --os linux|windows --src-cache DIR --out DIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PT_PATCH="$SCRIPT_DIR/pt-build-pin.patch"
# The pin the employer accepted for the PATCHED pt-build.sh content (LF).
PT_PATCHED_SHA256="3fbee02f78a4613a1452c32037c78c9d3a51ea4cb84edd8c4ebe808c023c4b88"
# v4.36e: the pristine pt-build.sh @ AETHER d58f9d56 — the exact derivation
# base of pt-build-pin.patch. The desktop legs verify the clone against this
# pin before installing the vendored patched copy (fail-closed on drift).
PT_PRISTINE_SHA256="78eb66356edd92e6cd847637afa65022a595b30b81fd50ed69dba8960c0ab052"
# v4.36f: the CRLF variant of the PATCHED content — the state the git-apply
# era could leave in a restored cache (proven on the runner in run 42189918027:
# the v4.36b postimage). Recognized and replaced from the blob; never trusted.
PT_PATCHED_CRLF_SHA256="fd0d9aba0d2fc838a84f2ad1d8278e2b47786d4405007624b76c7fcab1e74a49"

OS=""; SRC_CACHE=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --os) OS="$2"; shift 2 ;;
    --src-cache) SRC_CACHE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
for req in OS SRC_CACHE OUT; do
  [ -n "${!req:-}" ] || { echo "missing --$(echo "$req" | tr 'A-Z' a-z | tr '_' '-')" >&2; exit 2; }
done
case "$OS" in
  linux|windows) ;;
  *) echo "--os must be linux or windows" >&2; exit 2 ;;
esac
die() { echo "FATAL: $*" >&2; exit 1; }
require_file() { [ -f "$1" ] || die "expected build output missing: $1"; }

: "${AETHER_REPO:=https://github.com/CluvexStudio/Aether.git}"
: "${AETHER_SHA:=d58f9d568083129ce2c767c85054021eb3ee6a38}"
: "${ZEPTUN_REPO:=https://github.com/Noisemux/zeptun.git}"
: "${ZEPTUN_SHA:=08a1ab05aab315b7872ed582c52b7c230930d05d}"
: "${PSIPHON_FORK_REPO:=https://github.com/CluvexStudio/psiphon-tunnel-core.git}"
: "${PSIPHON_FORK_SHA:=2956a96b56fe09b99e72a8eb4bed3e79d29e3543}"
: "${LYREBIRD_PIN:=fc105a03c0e0}"
[ -n "${ZIG:-}" ] || { echo "ZIG not set" >&2; exit 2; }
[ -x "$ZIG" ] || die "zig resolver is not an executable: $ZIG"
[ -f "$PT_PATCH" ] || die "pin-hardening patch not found: $PT_PATCH"

GOOS="$OS"
GOARCH=amd64
EXE=""
LIBAETHER=""
LIBZEPTUN=""
ZLIB_DIR="lib"
if [ "$OS" = "windows" ]; then
  EXE=".exe"
  LIBAETHER="aether.dll"
  LIBZEPTUN="zeptun.dll"
  # zig installs RUNTIME dlls under bin/ on Windows (lib/ carries only the
  # import library zeptun.lib) — proven by the x86_64-windows-gnu crossbuild
  # that located the artifacts; the hosted msvc run built the same layout.
  ZLIB_DIR="bin"
  RUST_TARGET="x86_64-pc-windows-msvc"
else
  LIBAETHER="libaether.so"
  LIBZEPTUN="libzeptun.so"
  RUST_TARGET="x86_64-unknown-linux-gnu"
fi
export GOOS GOARCH

echo "== build_native_desktop: os=$OS rust-target=$RUST_TARGET zig=$("$ZIG" version) =="
mkdir -p "$SRC_CACHE" "$OUT"

clone_pin() { # repo sha dir
  local repo="$1" sha="$2" dir="$3"
  # v4.36b: core.autocrlf=false keeps the working tree byte-identical to the
  # committed blobs (LF). On the git-bash runner the default autocrlf=true
  # converts pt-build.sh to CRLF, so the patched sha256 check (which pins the
  # LF content) failed — and bash itself needs LF scripts to run. The android
  # legs (build_native.sh) stay untouched; on ubuntu the default is already
  # false.
  if [ ! -d "$dir/.git" ]; then
    git -c core.autocrlf=false clone --filter=blob:none "$repo" "$dir"
  fi
  git -C "$dir" -c core.autocrlf=false checkout "$sha"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ] || { echo "pin mismatch in $dir" >&2; exit 1; }
}

# ---------------------------------------------------------------- zeptun ----
echo "== [1/4] zeptun @ $ZEPTUN_SHA (desktop shared library) =="
ZEPTUN_SRC="$SRC_CACHE/zeptun"
clone_pin "$ZEPTUN_REPO" "$ZEPTUN_SHA" "$ZEPTUN_SRC"
(
  cd "$ZEPTUN_SRC"
  rm -rf zig-out
  # Host-target build: installs zig-out/lib/<libzeptun.so|zeptun.dll> + the
  # static lib + the CLI + include/zeptun.h. ReleaseFast mirrors the Android
  # build's optimize mode.
  "$ZIG" build -Doptimize=ReleaseFast
)
ZLIB="$ZEPTUN_SRC/zig-out/$ZLIB_DIR/$LIBZEPTUN"
require_file "$ZLIB"
mkdir -p "$OUT/zeptun"
cp "$ZLIB" "$OUT/zeptun/$LIBZEPTUN"
cp "$ZEPTUN_SRC/zig-out/include/zeptun.h" "$OUT/zeptun/zeptun.h"
if [ "$OS" = "windows" ]; then
  # The Wintun adapter DLL (loaded from the application directory — see
  # src/device/wintun.zig: LOAD_LIBRARY_SEARCH_APPLICATION_DIR). Vendored by
  # the frozen fetch_wintun.sh (pinned version + sha256; falls back to the
  # committed third-part tree when present).
  ( cd "$ZEPTUN_SRC" && sh scripts/fetch_wintun.sh amd64 "$OUT/zeptun" )
  require_file "$OUT/zeptun/wintun.dll"
fi

# ---------------------------------------------------------------- aether ----
echo "== [2/4] aether @ $AETHER_SHA (cargo, host target, features tor) =="
AETHER_SRC="$SRC_CACHE/aether"
clone_pin "$AETHER_REPO" "$AETHER_SHA" "$AETHER_SRC"
(
  cd "$AETHER_SRC/aether"
  # The boring-sys 5.3.0 enum-name fix (identical to build_native.sh — the
  # helper is host-independent): fetch locked, patch the exact crate source,
  # clear the stale build-script caches.
  echo "== [boring-sys] fetch locked sources and apply 5.3.0 enum-name fix =="
  cargo fetch --locked --target "$RUST_TARGET"
  PY=python3
  command -v python3 >/dev/null 2>&1 || PY=python
  "$PY" - "${CARGO_HOME:-$HOME/.cargo}" <<'PY_BORING_SYS'
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

before = hashlib.sha256(source.encode("utf-8")).hexdigest()
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
      count=$(find "$dir" -mindepth 1 -maxdepth 1 \
        \( -name 'boring-sys-*' -o -name 'libboring_sys-*' \) -print | wc -l)
      if [ "$count" -gt 0 ]; then
        find "$dir" -mindepth 1 -maxdepth 1 \
          \( -name 'boring-sys-*' -o -name 'libboring_sys-*' \) -exec rm -rf {} +
        echo "Removed $count stale boring-sys entries from $dir"
        removed=$((removed + count))
      fi
    done
  done
  echo "Total stale boring-sys cache entries removed: $removed"

  cargo build --release --locked --features tor --target "$RUST_TARGET"
  cdylib="target/$RUST_TARGET/release/$LIBAETHER"
  [ -f "$cdylib" ] || die "aether cdylib missing: $cdylib (expected from the same cargo build)"
  mkdir -p "$OUT/aether"
  cp "$cdylib" "$OUT/aether/$LIBAETHER"
)

# ------------------------------------------- lyrebird (Aether's frozen script, pin-hardened) ----
echo "== [3/4] lyrebird via Aether pt-build.sh @ $AETHER_SHA (pin $LYREBIRD_PIN enforced) =="
PT_LYREBIRD_PROOF_FILE="$SRC_CACHE/lyrebird-source-proof.json"
rm -f "$PT_LYREBIRD_PROOF_FILE"
export PT_LYREBIRD_PROOF_FILE
# v4.36f: the DESKTOP legs install the pin-hardened pt-build.sh from the
# COMMITTED BLOB of scripts/pt-build.patched.sh (`git show HEAD:…`), never
# from the working tree, and never through `git apply`.
#
# Run 42203317747 (v4.36e) delivered the decisive proof: the vendored file
# — committed as pure LF, byte-exact the pin — hashed to fd0d9aba… (the CRLF
# variant) ON THE RUNNER, and the lf() repair never fired. Unified mechanism,
# now proven across all five windows rounds:
#
#   * actions/checkout on the windows runner smudges text files to CRLF in
#     the working tree (LF blob → CRLF tree). That has been true all along:
#     pt-build-pin.patch was CRLF in the working tree in every run — which
#     is why git apply failed on the LF clone (v4.36c/d) and succeeded on
#     the CRLF clone (v4.36b), and why the v4.36d "normalize the patch"
#     guards were no-ops: grep/sed on git-bash CANNOT SEE \r (they read
#     through a text-mode layer), while sha256sum reports the true bytes.
#     Working-tree reads of ANY text file are therefore untrustworthy on
#     that runner, and grep/sed-based CRLF repair is impossible there.
#   * The clone (clone_pin, explicit -c core.autocrlf=false) IS raw-LF —
#     proven by the pristine pin matching and by every apply that did match.
#
# The new flow takes the vendored bytes from the git object database
# (git show HEAD:scripts/pt-build.patched.sh — a raw blob dump, no eol
# filters, no working tree) and verifies by sha256, which sees true bytes
# on every platform:
#   1. the clone's pt-build.sh is verified against PT_PRISTINE_SHA256 (the
#      exact derivation base) — or it already matches the patched pin (a
#      cache that restored an installed tree), or it is the known CRLF
#      variant the git-apply era could leave behind (fd0d9aba… — replaced,
#      not trusted);
#   2. the patched script is materialized from the blob into the clone;
#   3. the result is re-verified against PT_PATCHED_SHA256 — fail-closed.
# scripts/pt-build-pin.patch stays in the repo as the derivation record and
# remains the mechanism on the Android legs (build_native.sh untouched —
# ubuntu neither smudges the checkout nor the patch; every android run is
# green through that path).
cur_sha=$(sha256sum "$AETHER_SRC/pt-build.sh" | cut -d' ' -f1)
if [ "$cur_sha" = "$PT_PATCHED_SHA256" ]; then
  echo "pt-build.sh already carries the pin-hardened patch (cached tree)"
elif [ "$cur_sha" = "$PT_PRISTINE_SHA256" ]; then
  echo "pt-build.sh: verified against the pristine derivation base (sha256 $PT_PRISTINE_SHA256)"
elif [ "$cur_sha" = "$PT_PATCHED_CRLF_SHA256" ]; then
  echo "pt-build.sh: recognized as the CRLF variant the git-apply era could leave in a cache — replacing from the blob"
else
  die "pt-build.sh in the clone matches none of the pinned states (pristine $PT_PRISTINE_SHA256 / patched $PT_PATCHED_SHA256 / legacy-CRLF $PT_PATCHED_CRLF_SHA256): $cur_sha"
fi
if [ "$cur_sha" = "$PT_PATCHED_SHA256" ]; then
  echo "pt-build.sh: keeping the installed copy (byte-identical to the blob)"
else
  git -C "$SCRIPT_DIR" show "HEAD:scripts/pt-build.patched.sh" > "$AETHER_SRC/pt-build.sh" \
    || die "git show failed to materialize HEAD:scripts/pt-build.patched.sh"
  echo "pt-build.sh: installed from the committed blob (raw bytes, no working tree)"
fi
patched_sha=$(sha256sum "$AETHER_SRC/pt-build.sh" | cut -d' ' -f1)
[ "$patched_sha" = "$PT_PATCHED_SHA256" ] || die "patched pt-build.sh sha256 mismatch: $patched_sha (the blob materialization did not produce the pinned bytes)"
(
  cd "$AETHER_SRC"
  bash pt-build.sh "$GOOS" "$GOARCH" "$OUT/aether/pt" "" ""
)
# v4.36d: pt-build.sh names its output lyrebird$ext (ext=.exe on windows) —
# the checks and the go-version proof must follow the same name or the
# windows leg dies right after the patch step (the manifest/whitelist
# already expected lyrebird.exe; only these two checks lagged behind).
require_file "$OUT/aether/pt/lyrebird$EXE"
[ -f "$PT_LYREBIRD_PROOF_FILE" ] || die "lyrebird source-origin proof file missing — pt-build.sh did not record it; pin NOT proven (N8)"
proof_path=$(sed -n 's/.*"path":"\([^"]*\)".*/\1/p' "$PT_LYREBIRD_PROOF_FILE")
prov=$(go version -m "$OUT/aether/pt/lyrebird$EXE" 2>&1) || die "go version -m failed on lyrebird (N8)"
echo "$prov" | sed -n '1,20p'
case "$proof_path" in
  git)
    grep -q "${LYREBIRD_PIN}" <<<"$prov" || die "lyrebird pin NOT proven in the built binary (git path requires vcs.revision == pin)"
    echo "[lyrebird $OS] pin $LYREBIRD_PIN proven in binary (git path)"
    ;;
  proxy)
    grep -q '"pin":"'"${LYREBIRD_PIN}"'"' "$PT_LYREBIRD_PROOF_FILE" || die "lyrebird proof file does not reference the pin (N8)"
    grep -q '"dirhash":"h1:' "$PT_LYREBIRD_PROOF_FILE" || die "lyrebird proof file lacks the sumdb-verified dirhash (N8)"
    echo "[lyrebird $OS] pin $LYREBIRD_PIN proven via sumdb-verified source zip (proxy path)"
    ;;
  *)
    die "unknown lyrebird source-origin path in proof file: '$proof_path' (N8)"
    ;;
esac

# ---------------------------------- psiphon (AETHONE N1 pin 2956a96) ----
echo "== [4/4] psiphon @ $PSIPHON_FORK_SHA (N1 pin) =="
PSIPHON_SRC="$SRC_CACHE/psiphon-fork"
clone_pin "$PSIPHON_FORK_REPO" "$PSIPHON_FORK_SHA" "$PSIPHON_SRC"
(
  cd "$PSIPHON_SRC"
  export GOOS="$GOOS" GOARCH="$GOARCH" GOARM="" CGO_ENABLED=0 GOFLAGS=-mod=vendor GOTOOLCHAIN=local
  mkdir -p "$OUT/aether/pt"
  go build -trimpath -ldflags "-s -w" -o "$OUT/aether/pt/psiphon-tunnel-core$EXE" ./ConsoleClient
  [ -f "$OUT/aether/pt/psiphon-tunnel-core$EXE" ] || die "psiphon-tunnel-core missing after go build"
)

# ---------------------------------------------------------------- manifest ----
MANIFEST="$OUT/manifest.json"
{
  echo '{'
  echo "  \"os\": \"$OS\","
  echo "  \"arch\": \"x86_64\","
  echo "  \"pins\": {"
  echo "    \"aether\": \"$AETHER_SHA\","
  echo "    \"zeptun\": \"$ZEPTUN_SHA\","
  echo "    \"psiphon_fork\": \"$PSIPHON_FORK_SHA\","
  echo "    \"lyrebird\": \"$LYREBIRD_PIN (desktop: vendored scripts/pt-build.patched.sh, sha256 $PT_PATCHED_SHA256; derivation scripts/pt-build-pin.patch @ AETHER $AETHER_SHA)\""
  echo "  },"
  echo '  "artifacts": ['
  first=1
  if [ "$OS" = "windows" ]; then
    list="zeptun/zeptun.dll|zeptun|zeptun-shared
zeptun/wintun.dll|zeptun|wintun-adapter
zeptun/wintun-LICENSE.txt|zeptun|wintun-license
aether/aether.dll|aether|aether-cdylib
aether/pt/lyrebird.exe|aether/pt|lyrebird
aether/pt/psiphon-tunnel-core.exe|aether/pt|psiphon-fork
zeptun/zeptun.h|zeptun|zeptun-header"
  else
    list="zeptun/libzeptun.so|zeptun|zeptun-shared
aether/libaether.so|aether|aether-cdylib
aether/pt/lyrebird|aether/pt|lyrebird
aether/pt/psiphon-tunnel-core|aether/pt|psiphon-fork
zeptun/zeptun.h|zeptun|zeptun-header"
  fi
  echo "$list" | while IFS='|' read -r rel group component; do
    [ -f "$OUT/$rel" ] || { echo "MISSING artifact: $OUT/$rel" >&2; exit 1; }
    sha=$(sha256sum "$OUT/$rel" | cut -d' ' -f1)
    [ $first -eq 1 ] || echo ','
    first=0
    echo "    {\"path\": \"$rel\", \"group\": \"$group\", \"component\": \"$component\", \"sha256\": \"$sha\", \"bytes\": $(wc -c <"$OUT/$rel")}"
  done
  echo '  ]'
  echo '}'
} > "$MANIFEST"

# ---------------------------------------------- artifact whitelist guard ----
if [ "$OS" = "windows" ]; then
  expected_files="aether/aether.dll
aether/pt/lyrebird.exe
aether/pt/psiphon-tunnel-core.exe
manifest.json
zeptun/wintun-LICENSE.txt
zeptun/wintun.dll
zeptun/zeptun.dll
zeptun/zeptun.h"
else
  expected_files="aether/libaether.so
aether/pt/lyrebird
aether/pt/psiphon-tunnel-core
manifest.json
zeptun/libzeptun.so
zeptun/zeptun.h"
fi
actual_files=$(cd "$OUT" && find . -type f | sed 's|^\./||' | sort)
expected_files=$(sort <<<"$expected_files")
if [ "$actual_files" != "$expected_files" ]; then
  die "artifact tree does not match the expected file set:
--- expected (sorted) ---
$expected_files
--- actual (sorted) ---
$actual_files"
fi
echo "== done: $OUT (manifest at $MANIFEST) =="
cat "$MANIFEST"
