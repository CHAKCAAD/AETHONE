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

# v4.36k — THE x86-64 FLOOR (owner report: the desktop bundles die on
# weaker CPUs with glibc's 'Fatal glibc error: CPU ISA level is lower than
# required'). Every compiler in this script is pinned to the lowest x86-64
# compatibility level (SSE2 — every AMD64 CPU ever shipped):
#   * zig  -Dcpu=baseline (zeptun)  — zig's default for a native build is
#     the RUNNER's CPU model: Azure Xeons with AVX2 + AVX-512. The shipped
#     .so/.dll carried those instructions plus, on Linux, the GNU_PROPERTY
#     x86 ISA note — exactly what glibc enforces at load time.
#   * Go   GOAMD64=v1 (lyrebird + psiphon) — Go's documented amd64 floor.
#   * rustc stays on its default (baseline x86-64) — see the aether step.
# The linux leg additionally PROVES it: a fail-closed readelf gate rejects
# any shipped ELF whose 'x86 ISA needed' note goes past v1. The Android
# legs (build_native.sh) are untouched — different script, different
# architectures, no x86-64 in sight.

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
# v4.36g: hash via stdin redirect, never by file name. GNU sha256sum prefixes
# its output line with a '\' escape marker when the FILE NAME contains a
# backslash — and on the windows runner SRC_CACHE/OUT are D:\… paths
# (github.workspace), so `sha256sum "$file" | cut -d' ' -f1` returned
# "\78eb66…" and the pinned-state gate rejected a PRISTINE clone
# (run 42206207619, byte-dumped from the log: `): \78eb66…`). Hashing the
# redirect emits NO file name — no escaping possible — and reads the same
# bytes on every platform. The leading-backslash strip stays as a defensive
# net for any future named-file call path.
sha256_of() {
  local h
  h=$(sha256sum < "$1" | cut -d' ' -f1)
  printf '%s' "${h#\\}"
}

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
# v4.36k: exported at script scope so the vendored pt-build.sh inherits it
# for lyrebird — it sets GOOS/GOARCH/GOARM/CGO_ENABLED but never GOAMD64,
# so an inherited v1 is the effective floor (and beats any go-env default).
export GOAMD64=v1

# v4.40 — THE PRE-FMA FLOOR FOR THE GO ENGINES (defense in depth, the
# honest record): Go's amd64 ASSEMBLY math.Exp (math.archExp) carries an
# FMA path — `vfmadd213sd` sites selected by a runtime `useFMA` byte
# (cpu.X86.HasAVX && HasFMA — the dispatch exists in Go 1.26.3, VERIFIED
# in the shipped r86 binaries by disassembly). The floor below REMOVES
# the assembly path entirely (`haveArchExp = false` → the pure-Go MULSD/
# ADDSD implementation), so the engines can never execute FMA regardless
# of dispatch — and the zero-vfmadd gates in the build scripts + the CI
# PE audit PROVE it on every build. The first v4.40 dispatch's fail-closed
# gate fired exactly as designed: Go 1.26.3 keeps the const in
# src/math/exp_asm.go (NOT exp_amd64.go — that file only declares the
# useFMA byte now); the patch below targets the real file.
patch_go_math_exp_floor() {
  local goroot exp_asm
  goroot="$(go env GOROOT)"
  exp_asm="$goroot/src/math/exp_asm.go"
  [ -f "$exp_asm" ] || die "math FMA floor: $exp_asm not found in the pinned Go toolchain — layout changed, refusing to build FMA-unsafe engines"
  if grep -q '^const haveArchExp = true$' "$exp_asm"; then
    sed -i 's/^const haveArchExp = true$/const haveArchExp = false/' "$exp_asm"
    echo "[fma-floor] math.archExp (the amd64 asm with its FMA path) disabled — math.Exp now pure-Go: $exp_asm"
  elif grep -q '^const haveArchExp = false$' "$exp_asm"; then
    echo "[fma-floor] math.archExp already disabled (cached toolchain): $exp_asm"
  else
    die "math FMA floor: $exp_asm does not carry 'const haveArchExp = true' — the Go toolchain layout changed; refusing to build FMA-unsafe engines"
  fi
}
patch_go_math_exp_floor

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
  # static lib + the CLI + include/zeptun.h.
  #
  # v4.36k: -Dcpu=baseline clamps codegen to the x86-64 floor (SSE2).
  # build.zig uses standardTargetOptions, so -Dcpu is a registered option.
  # The TARGET stays native (same libc/MSVC linkage as every previous run —
  # no new failure mode); only the CPU model is pinned down. Without this,
  # zig compiles for the runner's Xeon (AVX2 + AVX-512), and glibc refuses
  # the .so on any weaker CPU: 'CPU ISA level is lower than required'.
  #
  # v4.40: ReleaseSafe on the DESKTOP legs (Android stays ReleaseFast — it
  # works and is frozen). In ReleaseFast, Zig compiles `unreachable` and
  # safety-check violations to UD2 — on Windows that raises
  # STATUS_ILLEGAL_INSTRUCTION (0xc000001d) with NO message, which is one of
  # the owner's r86 device reports (VPN-mode connect closes the app with
  # nothing on screen). ReleaseSafe keeps the same codegen floor but turns
  # every one of those sites into a printed panic ("panic: reached
  # unreachable code" etc.) on stderr — which the desktop core-log capture
  # records — followed by a clean abort. A tunnel bug becomes a readable
  # failure instead of a silent crash; the per-packet bounds-check cost is
  # the price of diagnosability on the beta channel.
  "$ZIG" build -Doptimize=ReleaseSafe -Dcpu=baseline
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

  # v4.39 — THE HIDDEN CHILD CORES ON WINDOWS. The owner's device report of
  # the r85 bundle: on Windows, every connect popped a visible console
  # window — the engine cores the aether cdylib spawns (psiphon.exe via
  # aether/src/psiphon.rs, the lyrebird PT probe via aether/src/bridges.rs)
  # and the lyrebird PT that arti itself spawns (tor-ptmgr 0.46.0,
  # registry/src/.../ipc.rs). A console child of a GUI app gets its own
  # console window; CREATE_NO_WINDOW (0x0800_0000) hides them all. The
  # child cores keep their piped stdio — only the window goes away
  # (the owner's decree: «psiphon.exe باید در پس زمینه سیستم اجرا بشه»).
  # Same fail-closed discipline as the boring-sys patch above: the exact
  # pristine text must match once, or the already-applied state; anything
  # else dies.
  "$PY" - "${CARGO_HOME:-$HOME/.cargo}" <<'PY_CHILD_CORES'
import sys
from pathlib import Path

cargo_home = Path(sys.argv[1]).expanduser()

def patch_file(path, old, new, what):
    source = path.read_text(encoding="utf-8")
    n_old, n_new = source.count(old), source.count(new)
    if n_old == 1:
        path.write_text(source.replace(old, new, 1), encoding="utf-8")
        state = "APPLIED"
    elif n_old == 0 and n_new == 1:
        state = "ALREADY_APPLIED"
    else:
        raise SystemExit(
            f"FATAL: {what}: expected the pristine text exactly once or the "
            f"patched state exactly once; got old={n_old} new={n_new} at {path}"
        )
    print(f"[v4.39 hidden-child-cores] {path.name}: {state} ({what})")

# 1. aether/src/psiphon.rs — the psiphon child core spawn (tokio Command:
#    creation_flags is an inherent windows-only method, no import needed).
#    The anchor extends past the chain into the NEXT statement: the old
#    text must NOT be a substring of the new one, or the patch would
#    double-apply on a cached tree (proven by the local idempotency run).
patch_file(
    Path("src/psiphon.rs").resolve(),
    """    let mut command = Command::new(&exe);
    command
        .args(client_arguments(&config_path, state, entries.as_deref()))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    if let Some((key, value)) = ca_store_env() {""",
    """    let mut command = Command::new(&exe);
    command
        .args(client_arguments(&config_path, state, entries.as_deref()))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    // AETHONE v4.39 — the psiphon child core runs hidden on Windows: a
    // console child of a GUI app otherwise gets its own visible console
    // window on every connect (the owner's device report).
    #[cfg(windows)]
    command.creation_flags(0x0800_0000);
    if let Some((key, value)) = ca_store_env() {""",
    "psiphon.rs hidden child core",
)

# 2. aether/src/bridges.rs — the lyrebird PT capability probe. std Command
#    here, so the trait method is called fully-qualified (no import).
patch_file(
    Path("src/bridges.rs").resolve(),
    """    let mut child = Command::new(path)
        .env("TOR_PT_MANAGED_TRANSPORT_VER", "1")
        .env("TOR_PT_STATE_LOCATION", &state)
        .env("TOR_PT_EXIT_ON_STDIN_CLOSE", "1")
        .env("TOR_PT_CLIENT_TRANSPORTS", ASKABLE.join(","))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;""",
    """    let mut pt_probe = Command::new(path);
    pt_probe
        .env("TOR_PT_MANAGED_TRANSPORT_VER", "1")
        .env("TOR_PT_STATE_LOCATION", &state)
        .env("TOR_PT_EXIT_ON_STDIN_CLOSE", "1")
        .env("TOR_PT_CLIENT_TRANSPORTS", ASKABLE.join(","))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    // AETHONE v4.39 — the PT probe runs hidden on Windows (same reason as
    // the psiphon child core: no console window beside the GUI app).
    #[cfg(windows)]
    std::os::windows::process::CommandExt::creation_flags(
        &mut pt_probe, 0x0800_0000);
    let mut child = pt_probe.spawn().ok()?;""",
    "bridges.rs hidden PT probe",
)

# 3. tor-ptmgr 0.46.0 (the registry source cargo fetched) — arti's own PT
#    child spawn. Exactly one extracted copy must exist, like boring-sys.
registry_src = cargo_home / "registry" / "src"
matches = sorted(registry_src.glob("*/tor-ptmgr-0.46.0/src/ipc.rs"))
if len(matches) != 1:
    raise SystemExit(
        "FATAL: expected exactly one tor-ptmgr-0.46.0/src/ipc.rs under "
        f"{registry_src}, found {len(matches)}."
    )
patch_file(
    matches[0],
    """            let child = Command::new(binary_path)
                .args(arguments.iter())
                .envs(all_env_vars)
                .stdout(Stdio::piped())
                .stdin(Stdio::piped())
                .spawn()
                .map_err(|e| PtError::ChildSpawnFailed {
                    path: binary_path.clone(),
                    error: Arc::new(e),
                })?;""",
    """            let mut pt_child = Command::new(binary_path);
            pt_child
                .args(arguments.iter())
                .envs(all_env_vars)
                .stdout(Stdio::piped())
                .stdin(Stdio::piped());
            // AETHONE v4.39 — arti's PT child (lyrebird) runs hidden on
            // Windows: without this, every tor connect that uses bridges
            // pops a visible console window beside the GUI app.
            #[cfg(windows)]
            std::os::windows::process::CommandExt::creation_flags(
                &mut pt_child, 0x0800_0000);
            let child = pt_child
                .spawn()
                .map_err(|e| PtError::ChildSpawnFailed {
                    path: binary_path.clone(),
                    error: Arc::new(e),
                })?;""",
    "tor-ptmgr ipc.rs hidden PT child",
)
print("[v4.39 hidden-child-cores] all three spawn sites now CREATE_NO_WINDOW on Windows")
PY_CHILD_CORES

  # v4.36k ISA note: rustc needs no flag here — its default codegen for both
  # host targets is baseline x86-64 (SSE2, no elevated ISA note in the ELF).
  # Deliberately NOT exporting RUSTFLAGS: aether's .cargo/config.toml pins
  # target-feature=+crt-static for x86_64-pc-windows-msvc (the VCRUNTIME140
  # fix), and an env RUSTFLAGS would clobber the config file wholesale and
  # quietly reintroduce that bug.
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
cur_sha=$(sha256_of "$AETHER_SRC/pt-build.sh")
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
patched_sha=$(sha256_of "$AETHER_SRC/pt-build.sh")
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
  # v4.36k: GOAMD64=v1 restated explicitly (the script-scope export already
  # carries it — this line is the self-documenting proof at the build site).
  export GOOS="$GOOS" GOARCH="$GOARCH" GOARM="" GOAMD64=v1 CGO_ENABLED=0 GOFLAGS=-mod=vendor GOTOOLCHAIN=local
  mkdir -p "$OUT/aether/pt"
  go build -trimpath -ldflags "-s -w" -o "$OUT/aether/pt/psiphon-tunnel-core$EXE" ./ConsoleClient
  [ -f "$OUT/aether/pt/psiphon-tunnel-core$EXE" ] || die "psiphon-tunnel-core missing after go build"
)

# ---------------------------- v4.40: the Go FMA-floor gate (fail-closed) ----
# The GOROOT math patch above must actually disarm the assembly: zero
# vfmadd/vfmsub instructions may remain in either Go engine (the r86
# binaries carried 8 sites inside math.archExp — runtime-dispatched by
# Go's useFMA byte, but the floor removes the path ENTIRELY; the gate
# keeps it that way on every future toolchain).
# Tool-portable: llvm-objdump on the windows runner, objdump on ubuntu;
# mnemonics are syntax-independent (ATT/Intel both print vfmadd…).
go_fma_gate() { # file
  local f="$1" od out n
  [ -f "$f" ] || die "Go FMA gate: expected artifact missing: $f"
  od="$(command -v llvm-objdump || command -v objdump || true)"
  [ -n "$od" ] || die "Go FMA gate: no objdump on this host — cannot prove the FMA floor"
  out="$("$od" -d --no-show-raw-insn "$f" 2>/dev/null | grep -cE 'vfmadd|vfmsub' || true)"
  n="${out:-0}"
  if [ "$n" -ne 0 ]; then
    die "Go FMA gate FAILED: $f still contains $n vfmadd/vfmsub sites — the math.archExp floor did not apply (check the pinned toolchain patch step)"
  fi
  echo "[fma-gate] $f: 0 vfmadd/vfmsub sites (pre-FMA CPUs safe)"
}
go_fma_gate "$OUT/aether/pt/lyrebird$EXE"
go_fma_gate "$OUT/aether/pt/psiphon-tunnel-core$EXE"

# ------------------------------------------------- x86 ISA gate (linux, fail-closed) ----
# v4.36k: glibc enforces the ELF's GNU_PROPERTY 'x86 ISA needed' note at
# load time — a v2+ requirement (SSE4.2/AVX2/AVX-512) is exactly what kills
# the bundle on a weaker CPU with 'CPU ISA level is lower than required'.
# The build flags above keep every artifact at the v1 floor; this gate
# PROVES it on every shipped ELF and fails the leg on any regression.
# (git-bash has no readelf, so the ELF proof runs on the linux leg — the
# windows leg builds from the same flags in the same script.)
if [ "$OS" = "linux" ]; then
  command -v readelf >/dev/null 2>&1 || die "readelf not found — cannot run the x86 ISA gate"
  isa_gate() { # file
    local f="$1" notes bad
    [ -f "$f" ] || die "x86 ISA gate: expected artifact missing: $f"
    # v4.36n: readelf prints ALL ISA levels on ONE line ('x86 ISA needed:
    # x86-64-baseline, x86-64-v2, x86-64-v3'). The old '[^ ,]*' pattern
    # truncated at the first comma and would have MISSED elevated levels —
    # grep the whole line, then look for v[2-4] inside it.
    notes=$(readelf --notes --wide "$f" 2>/dev/null | grep -oE 'x86 ISA needed:.*' || true)
    bad=$(printf '%s\n' "$notes" | grep -o 'x86-64-v[2-4]' | sort -u | tr '\n' ' ' || true)
    if [ -n "$bad" ]; then
      die "x86 ISA gate FAILED: $f requires ${bad}— the build regressed past the x86-64 floor (rebuild with -Dcpu=baseline / GOAMD64=v1)"
    fi
    if [ -n "$notes" ]; then
      echo "[isa-gate] $f: $notes (within the x86-64-v1 floor)"
    else
      echo "[isa-gate] $f: no x86 ISA requirement note (baseline)"
    fi
  }
  isa_gate "$OUT/zeptun/libzeptun.so"
  isa_gate "$OUT/aether/libaether.so"
  isa_gate "$OUT/aether/pt/lyrebird"
  isa_gate "$OUT/aether/pt/psiphon-tunnel-core"
  echo "[isa-gate] GOAMD64=$(go env GOAMD64 2>/dev/null || echo v1) (go env at gate time)"
fi

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
    sha=$(sha256_of "$OUT/$rel")
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
