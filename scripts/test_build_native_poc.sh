#!/usr/bin/env bash
# AETHONE — self-contained safety tests for scripts/build_native_poc.sh
# (Stage 2.1, 2026-11-18).
#
# Verifies the two owner-confirmed safety properties of the PoC wrapper:
#   1. Cleanup runs on BOTH success and failure — the wrapper must NOT exec
#      the child (an exec'd shell never exits, so the EXIT trap never runs
#      and the scratch copy leaks), and the child's exit status must be
#      preserved exactly.
#   2. Cleanup only ever removes a scratch directory THIS run created via
#      mktemp. A caller-supplied POC_SRC_CACHE is honored as the parent
#      location only — it (and anything that pre-existed inside it) is never
#      deleted.
#
# Runs WITHOUT the Android toolchain: the real build_native.sh is replaced by
# a stub inside a throwaway sandbox; the REAL build_native_poc.sh (copied
# verbatim) is the code under test. Exits non-zero if any check fails.
#
# Usage: bash scripts/test_build_native_poc.sh
set -uo pipefail

REAL_WRAPPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_native_poc.sh"
[ -f "$REAL_WRAPPER" ] || { echo "FATAL: wrapper not found next to this test" >&2; exit 1; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/zeptun_poc_test.XXXXXX")"
cleanup_test() { rm -rf -- "$SB"; }
trap cleanup_test EXIT

# --- sandbox: fake repo root with the REAL wrapper and a STUB child -------
mkdir -p "$SB/scripts" "$SB/native/zeptun/src"
cp "$REAL_WRAPPER" "$SB/scripts/build_native_poc.sh"
printf 'zig build stub\n' > "$SB/native/zeptun/build.zig"
printf 'stub root\n'   > "$SB/native/zeptun/src/root.zig"
printf 'vendored\n'    > "$SB/native/zeptun/src/MARKER"

cat > "$SB/scripts/build_native.sh" <<'EOF'
#!/usr/bin/env bash
# STUB — records what the wrapper handed over, then exits on cue.
set -u
printf 'ARGS:%s\n' "$*" >> "$STUB_LOG"
printf 'ZLS:%s\n' "${ZEPTUN_LOCAL_SRC:-}" >> "$STUB_LOG"
if [ -n "${ZEPTUN_LOCAL_SRC:-}" ] && [ -f "$ZEPTUN_LOCAL_SRC/src/MARKER" ]; then
  echo 'SRC_OK' >> "$STUB_LOG"
fi
if [ -n "${STUB_SLEEP:-}" ]; then sleep "$STUB_SLEEP"; fi
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$SB/scripts/build_native.sh"

LOG="$SB/stub.log"
export STUB_LOG="$LOG"
FAILURES=0

assert_eq() { # desc got expected
  if [ "$2" = "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1 — got '$2', want '$3'"; FAILURES=$((FAILURES+1)); fi
}
assert_exists() { if [ -e "$2" ]; then echo "PASS: $1"
  else echo "FAIL: $1 — $2 missing"; FAILURES=$((FAILURES+1)); fi; }
assert_gone()   { if [ ! -e "$2" ]; then echo "PASS: $1"
  else echo "FAIL: $1 — $2 still exists"; FAILURES=$((FAILURES+1)); fi; }
no_scratch_in() { # desc dir — no .zeptun_poc.* left inside dir
  if [ -z "$(find "$2" -maxdepth 1 -name '.zeptun_poc.*' 2>/dev/null)" ]; then
    echo "PASS: $1"
  else echo "FAIL: $1 — scratch left in $2"; FAILURES=$((FAILURES+1)); fi
}

ARGS="--abi arm64-v8a --rust-target aarch64-linux-android --goarch arm64 --api-level 29 --src-cache $SB/srccache --out $SB/out"

echo "== S1: success (default scratch) =="
rm -f "$LOG"
rc=0; bash "$SB/scripts/build_native_poc.sh" $ARGS >/dev/null 2>&1 || rc=$?
assert_eq "wrapper exits with the child's status (0)" "$rc" "0"
assert_eq "args forwarded verbatim" "$(sed -n 's/^ARGS://p' "$LOG")" "$ARGS"
zls="$(sed -n 's/^ZLS://p' "$LOG")"
if [ -n "$zls" ] && [ "${zls##*/}" = "zeptun" ]; then echo "PASS: ZEPTUN_LOCAL_SRC points at the copied tree"
else echo "FAIL: ZEPTUN_LOCAL_SRC wrong: '$zls'"; FAILURES=$((FAILURES+1)); fi
assert_eq "copied tree is the vendored source (marker present)" "$(grep -c '^SRC_OK$' "$LOG")" "1"
no_scratch_in "scratch cleaned after success" "$SB"

echo "== S2: failure (default scratch) =="
rm -f "$LOG"
rc=0; STUB_EXIT=7 bash "$SB/scripts/build_native_poc.sh" $ARGS >/dev/null 2>&1 || rc=$?
assert_eq "wrapper preserves the child's failure status (7)" "$rc" "7"
no_scratch_in "scratch cleaned after failure" "$SB"

echo "== S3: caller POC_SRC_CACHE pre-existing — success =="
rm -f "$LOG"; mkdir -p "$SB/usercache"; printf 'precious\n' > "$SB/usercache/sentinel"
rc=0; POC_SRC_CACHE="$SB/usercache" bash "$SB/scripts/build_native_poc.sh" $ARGS >/dev/null 2>&1 || rc=$?
assert_eq "wrapper exits 0" "$rc" "0"
assert_exists "caller's pre-existing directory survives" "$SB/usercache"
assert_exists "caller's pre-existing file survives" "$SB/usercache/sentinel"
no_scratch_in "fresh scratch subdir inside caller dir cleaned" "$SB/usercache"
no_scratch_in "nothing leaked in the repo root either" "$SB"

echo "== S4: caller POC_SRC_CACHE pre-existing — failure =="
rm -f "$LOG"; mkdir -p "$SB/usercache2"; printf 'precious\n' > "$SB/usercache2/sentinel"
rc=0; POC_SRC_CACHE="$SB/usercache2" STUB_EXIT=7 bash "$SB/scripts/build_native_poc.sh" $ARGS >/dev/null 2>&1 || rc=$?
assert_eq "wrapper preserves the child's failure status (7)" "$rc" "7"
assert_exists "caller's pre-existing file survives the failed run" "$SB/usercache2/sentinel"
no_scratch_in "fresh scratch subdir cleaned" "$SB/usercache2"

echo "== S5: caller POC_SRC_CACHE points at a missing directory =="
rm -f "$LOG"
rc=0; POC_SRC_CACHE="$SB/newcache" bash "$SB/scripts/build_native_poc.sh" $ARGS >/dev/null 2>&1 || rc=$?
assert_eq "wrapper exits 0" "$rc" "0"
assert_exists "missing parent was created (not a failure)" "$SB/newcache"
no_scratch_in "created parent kept, scratch inside cleaned" "$SB/newcache"

echo "== S6: vendored tree missing =="
mv "$SB/native/zeptun/src" "$SB/native/zeptun/src.hold"
rc=0; bash "$SB/scripts/build_native_poc.sh" $ARGS >/dev/null 2>&1 || rc=$?
assert_eq "wrapper fails fast (1) when the vendored tree is missing" "$rc" "1"
no_scratch_in "no scratch created on the early failure" "$SB"
mv "$SB/native/zeptun/src.hold" "$SB/native/zeptun/src"

echo "== S7: SIGTERM mid-build =="
rm -f "$LOG"
POC_SCRATCH_BEFORE="$(find "$SB" -maxdepth 1 -name '.zeptun_poc.*' | wc -l)"
STUB_SLEEP=2 bash "$SB/scripts/build_native_poc.sh" $ARGS >/dev/null 2>&1 &
wpid=$!
sleep 0.5
kill -TERM "$wpid" 2>/dev/null
rc=0; wait "$wpid" || rc=$?
assert_eq "wrapper exits 143 after SIGTERM (trap chain ran)" "$rc" "143"
no_scratch_in "scratch cleaned after SIGTERM" "$SB"
assert_eq "no extra scratch existed before S7 (sanity)" "$POC_SCRATCH_BEFORE" "0"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
fi
echo "$FAILURES CHECK(S) FAILED"
exit 1
