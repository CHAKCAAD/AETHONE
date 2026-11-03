#!/usr/bin/env bash
# AETHONE — post-build ELF/ABI inspection (v4), pass/fail exit code.
#
# v4 (employer review of bundle v3, 2026-10-31) — one functional change:
#
#   0. MULTI-SEGMENT RELRO: EVERY PT_GNU_RELRO segment is now analyzed
#      INDEPENDENTLY with the full v3 two-case logic. v3 analyzed only the
#      FIRST segment and merely warned about the rest — an unchecked segment
#      could hide under a PASS. In v4 each segment gets its own covering
#      LOAD, placement decision and placement-specific rule; the aggregate
#      kb16_relro is  FAIL if ANY segment fails, WARN if any warns, N/A only
#      if every segment is N/A (4 KB arch), PASS only if EVERY segment
#      passes. A segment that cannot be analyzed (no covering LOAD) is a
#      FAIL — never a silent skip. The per-file manifest additionally
#      records relro.segment_count and, for multi-segment files, the full
#      per-segment raw data. Files with exactly one PT_GNU_RELRO segment
#      (all 9 official Aether v2.4.0 artifacts — raw counts in the
#      regenerated manifest) receive the identical v3 verdict; proof that
#      the multi-segment path itself works: evidence/relro_multi_segment_test.txt
#      (synthetic two-RELRO ELF, one passing + one failing segment).
#
# v3 (employer review of bundle v2, 2026-10-31) supersedes the v2 checker:
#
#   1. RELRO-16KB is NO LONGER the bare formula. Per the official Android
#      page-sizes doc, the formula
#            (VirtAddr + MemSiz) % 16384 == 0
#      applies ONLY when PT_GNU_RELRO shares its LOAD segment with subsequent
#      writable data (.data/.bss). When PT_GNU_RELRO sits in its own LOAD
#      segment (the LOAD contains only RELRO data), the formula does NOT
#      apply: what matters instead is that every subsequent writable LOAD
#      starts at/after page_up(relro_end), i.e. outside the linker's
#      mprotect range [page_down(relro_vaddr), page_up(relro_vaddr+memsz)).
#      v3 therefore extracts the FULL PT_GNU_RELRO row, the covering LOAD
#      (vaddr/memsz/flags), the data before/after the RELRO region inside
#      that LOAD, and every subsequent LOAD with flags, decides the placement
#      (own-load / shared-load / irregular), applies ONLY the rule that
#      belongs to that placement, and records all raw context.
#      Consequence for the official Aether v2.4.0 binaries: both arm64 and
#      x86_64 place RELRO in its own LOAD -> recorded as RELRO-16KB PASS
#      (the v2 "end%16384!=0 -> FAIL" verdicts for them were false positives
#      caused by applying the formula unconditionally — corrected here).
#   2. armeabi-v7a is a 4 KB architecture: its "kb16_load" is now "N/A"
#      (was misleadingly "PASS"). A separate 4 KB ELF-validity rule
#      (p_align >= 4096) still applies and fails hard when violated.
#   3. "needed" is [] for files with no NEEDED entries (was [""]).
#   4. Verdict semantics: an artifact with hard failures = FAIL; with
#      warnings but no failures = PASS_WITH_WARNINGS (was silently PASS);
#      in particular x86_64 Go executables whose min p_align < 16384 are
#      recorded kb16_load=FAIL (static ELF fact) while the artifact verdict
#      is PASS_WITH_WARNINGS — their runtime behaviour is NOT TESTED and the
#      fix (Go linker flags) is a frozen-build employer decision (N8).
#      STRICT_16KB_X86_64_EXEC=1 escalates it to a hard failure.
#   5. Static ELF compliance and RUNTIME 16 KB behaviour are kept separate:
#      every record carries runtime_16kb_env="NOT TESTED" — a green static
#      inspection proves nothing about execution in a real 16 KB Android
#      environment (emulator/device), which no CI run performs.
#   6. Artifact-tree hygiene: any unexpected file or directory inside the
#      inspected tree (zeptun-build/, *.o, zig-out/, .zig-cache/, obj/ ...)
#      is a hard failure in CI mode — intermediate build products must never
#      enter an uploaded artifact (employer fix #2).
#
# Retained from v2 (unchanged semantics):
#   * Static archives (.a) are inspected per MEMBER (Machine/Class) — an
#     archive is not an executable ELF and gets no LOAD-segment rules.
#   * Go "static" proof = empty NEEDED AND no PT_INTERP AND no PT_DYNAMIC.
#   * Aether PIE proof = DYN + PT_INTERP + DF_1_PIE bit.
#   * Every PT_LOAD p_align and p_vaddr = p_offset (mod p_align); on 16 KB
#     arches additionally = 0 (mod 16384); x86_64 is never skipped.
#   * ZIP alignment (zipalign -c -P 16 -v 4 app-release.apk) stays a
#     SEPARATE check with status NOT TESTED until a real APK exists.
#
# Modes:
#   default         : missing artifact = failure; violations -> exit 1
#   --allow-missing : expected artifacts not built in this run are recorded
#                     as MISSING (NOT TESTED), non-fatal
#   --evidence-mode : violations are recorded but do not affect the exit
#                     code (ONLY for runs over UPSTREAM release artifacts,
#                     never for AETHONE CI output)
#
# Usage: inspect_elf.sh --dir out [--allow-missing] [--evidence-mode]
set -uo pipefail

DIR=""; ALLOW_MISSING=0; EVIDENCE_MODE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --allow-missing) ALLOW_MISSING=1; shift ;;
    --evidence-mode) EVIDENCE_MODE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$DIR" ] || { echo "missing --dir" >&2; exit 2; }
[ -d "$DIR" ] || { echo "no such dir: $DIR" >&2; exit 2; }

LOG="$DIR/elf_inspection_log.txt"
JSON="$DIR/elf_manifest.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: > "$LOG"
FAILURES=0; WARNINGS=0; MISSING=0
RECORDS="$TMP/records.jsonl"; : > "$RECORDS"

emit(){ echo "$@" | tee -a "$LOG"; }
fail(){ emit "  [FAIL] $*"; FAILURES=$((FAILURES+1)); }
warn(){ emit "  [WARN] $*"; WARNINGS=$((WARNINGS+1)); }
hex(){ # hex number -> decimal
  printf '%d' "$1" 2>/dev/null
}
json_escape() { local s="$1"; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }
abs_path() { readlink -f "$1"; }

machine_for() {
  case "$1" in
    arm64-v8a)   echo "AArch64|ELF64" ;;
    armeabi-v7a) echo "ARM|ELF32" ;;
    x86_64)      echo "Advanced Micro Devices X86-64|ELF64" ;;
    *) echo "unknown|unknown" ;;
  esac
}
is_16kb_arch() { [ "$1" = "arm64-v8a" ] || [ "$1" = "x86_64" ]; }

# ---------------------------------------------------------------------------
# Static archive inspection (.a): every member must match the ABI machine.
# ---------------------------------------------------------------------------
inspect_archive() { # abi file group rel
  local abi="$1" file="$2" group="$3" rel="$4"
  local f0=$FAILURES w0=$WARNINGS
  emit "--- [$abi] $rel ($(wc -c <"$file") bytes) | kind=static-archive ---"
  local exp; exp=$(machine_for "$abi"); local em=${exp%%|*}; local ec=${exp##*|}
  local mdir="$TMP/ar.$$"; rm -rf "$mdir"; mkdir -p "$mdir"
  local members; members=$(ar t "$file" 2>/dev/null | sed 's:/$::')
  if [ -z "$members" ]; then
    fail "cannot read archive members (ar t failed or empty)"
    return 1
  fi
  local count=0 okmach=1 okclass=1
  # Zig-built archives store members under nested paths (e.g.
  # ".zig-cache/o/<hash>/libzeptun_zcu.o"). GNU ar x does NOT create
  # intermediate directories, so extraction fails with
  # "<member>: No such file or directory" unless every member's parent
  # directory is pre-created. v3.1: pre-create the whole tree first.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    mkdir -p -- "$mdir/$(dirname -- "$m")"
  done <<<"$members"
  ( cd "$mdir" && ar x "$(abs_path "$file")" ) || { fail "ar x failed"; return 1; }
  local mjson=""
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    count=$((count+1))
    local h mach cls
    h=$(readelf -h "$mdir/$m" 2>/dev/null) || { fail "member not readable ELF: $m"; continue; }
    mach=$(grep -m1 'Machine:' <<<"$h" | sed 's/^ *Machine: *//')
    cls=$(grep -m1 'Class:' <<<"$h" | awk '{print $2}')
    emit "    member: $m class=$cls machine=$mach"
    [ "$mach" = "$em" ] || { okmach=0; fail "member $m machine mismatch: expected '$em' got '$mach'"; }
    [ "$cls" = "$ec" ] || { okclass=0; fail "member $m class mismatch: expected '$ec' got '$cls'"; }
    mjson+="${mjson:+,}$(printf '{"name":"%s","machine":"%s","class":"%s"}' "$(json_escape "$m")" "$(json_escape "$mach")" "$cls")"
  done <<<"$members"
  emit "  archive members: $count | machine OK: $([ $okmach -eq 1 ] && echo yes || echo NO) | class OK: $([ $okclass -eq 1 ] && echo yes || echo NO)"
  local verdict="PASS"
  { [ $((okmach+okclass)) -ne 2 ] || [ $((FAILURES-f0)) -gt 0 ]; } && verdict="FAIL"
  emit "  verdict: $verdict"
  printf '{"abi":"%s","path":"%s","group":"%s","kind":"static-archive","members":[%s],"member_count":%d,"verdict":"%s","runtime_16kb_env":"NOT TESTED"}\n' \
    "$abi" "$rel" "$group" "$mjson" "$count" "$verdict" >> "$RECORDS"
}

# ---------------------------------------------------------------------------
# Dump program headers in a machine-friendly pipe format. Flags may contain
# spaces (e.g. "R E"), so they are captured as fields 7..NF-1:
#   LOAD |offset|vaddr|filesz|memsz|flags|align
#   RELRO|offset|vaddr|filesz|memsz|flags|align
# ---------------------------------------------------------------------------
dump_phdrs() { # file
  readelf -lW "$1" 2>/dev/null | awk '
    $1=="LOAD"      {flg=""; for(i=7;i<NF;i++) flg=flg$i" "; print "LOAD|"$2"|"$3"|"$5"|"$6"|"flg"|"$NF}
    $1=="GNU_RELRO" {flg=""; for(i=7;i<NF;i++) flg=flg$i" "; print "RELRO|"$2"|"$3"|"$5"|"$6"|"flg"|"$NF}
  '
}

# ---------------------------------------------------------------------------
# RELRO-16KB analysis per the OFFICIAL two-case rule (see header note 1).
# v4: EVERY PT_GNU_RELRO segment is analyzed independently (per-segment
# covering LOAD, placement and placement-specific rule). Aggregate:
#   any FAIL -> FAIL | any WARN -> WARN | all N/A -> N/A | else PASS.
# No segment is ever left unanalyzed under a PASS.
# Emits log lines; sets the globals RELRO_JSON and KB16_RELRO.
# ---------------------------------------------------------------------------
LOAD_ROWS=()                  # all PT_LOAD rows, file order: "vaddr|memsz|flags|align|off"
SEG_KB="ABSENT"; SEG_JSON="null"
RELRO_JSON="null"; KB16_RELRO="ABSENT"

# -- two-case analysis of ONE PT_GNU_RELRO row; sets SEG_KB + SEG_JSON ------
analyze_relro_seg() { # abi rrow
  local abi="$1" rrow="$2"
  IFS='|' read -r _ roff rvaddr rfilesz rmesz rflags ralign <<<"$rrow"
  SEG_KB="ABSENT"; SEG_JSON="null"
  local rv rm rend rem16
  rv=$(hex "$rvaddr"); rm=$(hex "$rmesz"); rend=$((rv + rm))
  rem16=$((rend % 16384))
  local rflags_t; rflags_t=$(echo "$rflags" | tr -d ' ')
  emit "  RELRO row: offset=$roff vaddr=$rvaddr filesz=$rfilesz memsz=$rmesz flags=$rflags_t"

  # find the covering LOAD: the LOAD whose [vaddr, vaddr+memsz) contains relro.vaddr
  local cov_i=-1 i
  for i in "${!LOAD_ROWS[@]}"; do
    IFS='|' read -r lv lmsz lflg lal loff <<<"${LOAD_ROWS[$i]}"
    local lvd lmd
    lvd=$(hex "$lv"); lmd=$(hex "$lmsz")
    if [ "$rv" -ge "$lvd" ] && [ "$rv" -lt "$((lvd + lmd))" ]; then
      cov_i=$i; break
    fi
  done

  local prot_start=$(( rv - (rv % 16384) ))
  local prot_end=$(( (rend + 16383) / 16384 * 16384 ))
  # pre-formatted hex values (kept out of JSON building to avoid nested quoting)
  local rend_hex prot_start_hex prot_end_hex
  rend_hex=$(printf '0x%x' "$rend")
  prot_start_hex=$(printf '0x%x' "$prot_start")
  prot_end_hex=$(printf '0x%x' "$prot_end")

  if [ "$cov_i" -lt 0 ]; then
    if is_16kb_arch "$abi"; then
      SEG_KB="FAIL"
      fail "RELRO vaddr $rvaddr not inside any PT_LOAD — layout irregular, 16KB safety NOT provable"
    else
      SEG_KB="N/A"
      emit "  RELRO vaddr not inside any PT_LOAD — recorded (4KB arch, 16KB rule N/A)"
    fi
    SEG_JSON=$(printf '{"vaddr":"%s","memsz":"%s","placement":"irregular","kb16_relro":"%s"}' "$rvaddr" "$rmesz" "$SEG_KB")
    return
  fi

  IFS='|' read -r clv clmsz clflg clal cloff <<<"${LOAD_ROWS[$cov_i]}"
  local clvd clmd clend data_before data_after cov_writable clflg_t clend_hex
  clvd=$(hex "$clv"); clmd=$(hex "$clmsz"); clend=$((clvd + clmd))
  data_before=$((rv - clvd))
  data_after=$((clend - rend))
  clflg_t=$(echo "$clflg" | tr -d ' ')
  clend_hex=$(printf '0x%x' "$clend")
  case "$clflg" in *W*) cov_writable=true ;; *) cov_writable=false ;; esac
  emit "  covering LOAD: vaddr=$clv memsz=$clmsz flags=$clflg_t end=$clend_hex"
  if [ "$data_after" -lt 0 ]; then
    emit "  RELRO data vs LOAD: before=$data_before bytes, after=$(( -data_after )) bytes (RELRO extends past the LOAD end)"
  else
    emit "  RELRO data vs LOAD: before=$data_before bytes, after=$data_after bytes"
  fi
  emit "  linker mprotect range (16KB pages): [$prot_start_hex, $prot_end_hex)"

  # subsequent LOAD rows (after the covering one), with flags
  local sub_json="" sub_log="" w after_ok lvd lvflg_t
  for i in "${!LOAD_ROWS[@]}"; do
    [ "$i" -gt "$cov_i" ] || continue
    IFS='|' read -r lv lmsz lflg lal loff <<<"${LOAD_ROWS[$i]}"
    lvd=$(hex "$lv")
    lvflg_t=$(echo "$lflg" | tr -d ' ')
    case "$lflg" in *W*) w=true ;; *) w=false ;; esac
    after_ok=false
    [ "$lvd" -ge "$prot_end" ] && after_ok=true
    sub_log+=$'\n'"    subsequent LOAD vaddr=$lv flags=$lvflg_t writable=$w starts_at_or_after_protection_end=$after_ok"
    sub_json+="${sub_json:+,}$(printf '{"vaddr":"%s","flags":"%s"}' "$lv" "$lvflg_t")"
  done
  [ -n "$sub_log" ] && emit "$sub_log"

  if ! is_16kb_arch "$abi"; then
    SEG_KB="N/A"
    emit "  RELRO-16KB: N/A (armeabi-v7a is a 4 KB architecture — placement recorded, no 16 KB requirement)"
    SEG_JSON=$(printf '{"present":true,"offset":"%s","vaddr":"%s","filesz":"%s","memsz":"%s","flags":"%s","end":"%s","formula_remainder_16384":%d,"placement":"recorded-4kb-arch","covering_load":{"vaddr":"%s","memsz":"%s","flags":"%s"},"protection_range":["%s","%s"],"subsequent_loads":[%s],"kb16_relro":"N/A"}' \
      "$roff" "$rvaddr" "$rfilesz" "$rmesz" "$rflags_t" "$rend_hex" "$rem16" "$clv" "$clmsz" "$clflg_t" "$prot_start_hex" "$prot_end_hex" "$sub_json")
    return
  fi

  local placement
  if [ "$data_before" -eq 0 ] && [ "$data_after" -le 0 ]; then
    placement="own-load"
  else
    placement="shared-load"
  fi

  # common JSON base (single-quoted printf format — no nested quoting)
  local base_json
  base_json=$(printf '{"present":true,"offset":"%s","vaddr":"%s","filesz":"%s","memsz":"%s","flags":"%s","end":"%s","end_dec":%d,"formula_remainder_16384":%d,"placement":"%s","covering_load":{"vaddr":"%s","memsz":"%s","flags":"%s","end":"%s","writable":%s},"data_before_dec":%d,"data_after_dec":%d,"protection_range":["%s","%s"],"subsequent_loads":[%s]' \
    "$roff" "$rvaddr" "$rfilesz" "$rmesz" "$rflags_t" "$rend_hex" "$rend" "$rem16" "$placement" \
    "$clv" "$clmsz" "$clflg_t" "$clend_hex" "$cov_writable" "$data_before" "$data_after" \
    "$prot_start_hex" "$prot_end_hex" "$sub_json")

  if [ "$placement" = "own-load" ]; then
    # OWN LOAD: the official formula does NOT apply here. Safety condition:
    # no subsequent writable LOAD may start inside the mprotect range.
    local viol=0
    for i in "${!LOAD_ROWS[@]}"; do
      [ "$i" -gt "$cov_i" ] || continue
      IFS='|' read -r lv lmsz lflg lal loff <<<"${LOAD_ROWS[$i]}"
      case "$lflg" in *W*) ;; *) continue ;; esac
      lvd=$(hex "$lv")
      if [ "$lvd" -lt "$prot_end" ]; then
        viol=1
        fail "RELRO-16KB (own-load): subsequent writable LOAD at $lv starts inside the linker mprotect range [$prot_start_hex, $prot_end_hex) — its writable bytes would be made read-only (segfault)"
      fi
    done
    if [ "$viol" -eq 0 ]; then
      SEG_KB="PASS"
      emit "  RELRO-16KB: PASS — own-LOAD placement (LOAD contains only RELRO data; official formula (VirtAddr+MemSiz)%16384 NOT applicable); remainder $rem16 is expected and harmless here; no subsequent writable LOAD enters the protection range [$prot_start_hex, $prot_end_hex)"
    else
      SEG_KB="FAIL"
    fi
    SEG_JSON="$base_json$(printf ',"rule_applied":"own-load: every subsequent writable LOAD must start at/after page_up(relro_end)","kb16_relro":"%s"}' "$SEG_KB")"
    return
  fi

  # SHARED LOAD: the official formula applies.
  emit "  RELRO-16KB: SHARED-LOAD placement — official formula applies: (VirtAddr+MemSiz) % 16384 = $rem16"
  if [ "$rem16" -eq 0 ]; then
    SEG_KB="PASS"
    emit "  RELRO-16KB: PASS (shared-load, formula satisfied)"
    SEG_JSON="$base_json$(printf ',"rule_applied":"shared-load: official formula (VirtAddr+MemSiz) %% 16384 == 0","kb16_relro":"%s","formula_result":"PASS"}' "$SEG_KB")"
  elif [ "$cov_writable" = "true" ]; then
    SEG_KB="FAIL"
    fail "RELRO-16KB (shared-load): (VirtAddr+MemSiz) % 16384 = $rem16 != 0 and the covering LOAD is writable — the loader would mprotect past the RELRO end over writable data (segfault per official doc)"
    SEG_JSON="$base_json$(printf ',"rule_applied":"shared-load: official formula (VirtAddr+MemSiz) %% 16384 == 0","kb16_relro":"%s","formula_result":"FAIL"}' "$SEG_KB")"
  else
    SEG_KB="WARN"
    warn "RELRO-16KB (shared-load): formula remainder $rem16 != 0, but the covering LOAD is not writable — recorded, no crash mechanism"
    SEG_JSON="$base_json$(printf ',"rule_applied":"shared-load: official formula (VirtAddr+MemSiz) %% 16384 == 0","kb16_relro":"%s","formula_result":"FAIL (covering LOAD not writable — no crash mechanism)"}' "$SEG_KB")"
  fi
}

analyze_relro() { # abi file
  local abi="$1" file="$2"
  KB16_RELRO="ABSENT"; RELRO_JSON="null"
  local rows; rows=$(dump_phdrs "$file")
  local rcount; rcount=$(grep -c '^RELRO|' <<<"$rows")
  # all LOAD rows in file order (shared by every RELRO segment of this file)
  LOAD_ROWS=()
  while IFS='|' read -r _ loff lvaddr lfilesz lmemsz lflags lalign; do
    [ -n "$lvaddr" ] || continue
    LOAD_ROWS+=("$lvaddr|$lmemsz|$lflags|$lalign|$loff")
  done < <(grep '^LOAD|' <<<"$rows")

  if [ "$rcount" -eq 0 ]; then
    emit "  RELRO: no PT_GNU_RELRO segment — no RELRO requirement (trivially compliant; recorded ABSENT)"
    RELRO_JSON='{"present":false,"segment_count":0,"placement":"absent","kb16_relro":"ABSENT"}'
    return
  fi
  if [ "$rcount" -eq 1 ]; then
    emit "  PT_GNU_RELRO segments found: 1 — full two-case analysis (v4; per-segment independent)"
  else
    emit "  PT_GNU_RELRO segments found: $rcount — MULTI-SEGMENT: each segment is analyzed independently (v4); aggregate FAIL>WARN>N/A>PASS; no segment left unanalyzed"
  fi

  local segs_json="" seg_kbs="" sidx=0 rrow
  while IFS= read -r rrow; do
    [ -n "$rrow" ] || continue
    sidx=$((sidx+1))
    [ "$rcount" -gt 1 ] && emit "  --- RELRO segment $sidx/$rcount ---"
    analyze_relro_seg "$abi" "$rrow"
    segs_json+="${segs_json:+,}$SEG_JSON"
    seg_kbs+="${seg_kbs:+,}$SEG_KB"
  done < <(grep '^RELRO|' <<<"$rows")

  # aggregate (v4): any FAIL -> FAIL, any WARN -> WARN, all N/A -> N/A, else PASS
  local agg="PASS" all_na=1 kb
  IFS=',' read -r -a SEG_KB_ARR <<<"$seg_kbs"
  for kb in "${SEG_KB_ARR[@]}"; do
    case "$kb" in
      FAIL) agg="FAIL" ;;
      WARN) [ "$agg" != "FAIL" ] && agg="WARN" ;;
      PASS) all_na=0 ;;
    esac
  done
  [ "$agg" = "PASS" ] && [ "$all_na" -eq 1 ] && agg="N/A"
  KB16_RELRO="$agg"
  if [ "$rcount" -gt 1 ]; then
    emit "  RELRO-16KB aggregate: $agg — per-segment results: ${seg_kbs} (all $rcount segments independently analyzed; a PASS cannot hide an unanalyzed segment)"
    RELRO_JSON=$(printf '{"present":true,"segment_count":%d,"placement":"multi-segment","segments":[%s],"kb16_relro":"%s"}' "$rcount" "$segs_json" "$agg")
  else
    # single segment: identical v3 JSON shape (flat), plus segment_count
    RELRO_JSON="${SEG_JSON%\}},\"segment_count\":1}"
  fi
}

# ---------------------------------------------------------------------------
# ELF inspection (executables + shared libraries).
# ---------------------------------------------------------------------------
inspect_elf_one() { # abi file group rel kind
  local abi="$1" file="$2" group="$3" rel="$4" kind="$5"
  local f0=$FAILURES w0=$WARNINGS
  local base; base=$(basename "$file")
  emit "--- [$abi] $rel ($(wc -c <"$file") bytes) | kind=$kind ---"
  local exp; exp=$(machine_for "$abi"); local em=${exp%%|*}; local ec=${exp##*|}

  local hdr mach cls typ entry
  hdr=$(readelf -h "$file" 2>/dev/null) || { fail "readelf -h failed"; return 1; }
  cls=$(grep -m1 'Class:' <<<"$hdr" | awk '{print $2}')
  mach=$(grep -m1 'Machine:' <<<"$hdr" | sed 's/^ *Machine: *//')
  typ=$(grep -m1 'Type:' <<<"$hdr" | awk '{print $2}')
  entry=$(grep -m1 'Entry point' <<<"$hdr" | awk '{print $NF}')
  emit "  class=$cls machine=$mach type=$typ entry=$entry"
  [ "$mach" = "$em" ] || fail "machine mismatch: expected '$em' got '$mach'"
  [ "$cls" = "$ec" ] || fail "class mismatch: expected '$ec' got '$cls'"

  local has_interp has_dyn pie_flag needed needed_json needed_count
  has_interp=$(readelf -lW "$file" 2>/dev/null | awk '$1=="INTERP"{print "yes"; exit}')
  has_dyn=$(readelf -lW "$file" 2>/dev/null | awk '$1=="DYNAMIC"{print "yes"; exit}')
  pie_flag=$(readelf -d "$file" 2>/dev/null | grep 'FLAGS_1' | grep -cw 'PIE')
  pie_flag=${pie_flag:-0}
  needed=$(readelf -d "$file" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
  # v3: an empty NEEDED list must serialize as [] — blank lines filtered first
  needed_json=$(grep -v '^[[:space:]]*$' <<<"$needed" | awk 'BEGIN{ORS=""} {gsub(/"/, "\\\""); printf "%s\"%s\"", (NR>1?",":""), $0}')
  needed_count=$(grep -c '[^[:space:]]' <<<"$needed")
  needed_count=${needed_count:-0}
  emit "  PT_INTERP: ${has_interp:-no} | PT_DYNAMIC: ${has_dyn:-no} | DF_1_PIE: $([ "$pie_flag" -eq 1 ] && echo yes || echo no)"
  if [ "$needed_count" -gt 0 ]; then
    emit "  NEEDED: ${needed//$'\n'/ ; } [count: $needed_count]"
  else
    emit "  NEEDED: (none) [count: 0]"
  fi

  local warn_only_exec16=0
  case "$kind" in
    go-static)
      # static proof: empty NEEDED AND no PT_INTERP AND no PT_DYNAMIC
      if [ "$needed_count" -gt 0 ] || [ -n "$has_interp" ] || [ -n "$has_dyn" ]; then
        fail "$base is NOT provably static: NEEDED-empty=$([ "$needed_count" -eq 0 ] && echo yes || echo no), PT_INTERP=${has_interp:-no}, PT_DYNAMIC=${has_dyn:-no}"
      else
        emit "  static proof: NEEDED empty + no PT_INTERP + no PT_DYNAMIC (link type $typ recorded)"
      fi
      if [ "$abi" = "x86_64" ]; then
        warn_only_exec16=1   # upstream GOOS=linux Go yields 0x1000 align on x86_64 (open employer decision, N8)
      fi
      ;;
    executable-pie)
      [ "$typ" = "DYN" ] || fail "aether must be ET_DYN (PIE), got $typ"
      [ -n "$has_interp" ] || fail "aether: DYN but no PT_INTERP — PIE-executable nature NOT proven"
      [ "$pie_flag" -eq 1 ] || fail "aether: DT_FLAGS_1 PIE bit missing"
      grep -qx 'libc++_shared.so' <<<"$needed" && fail "aether needs libc++_shared.so (static libc++ link failed)"
      local ok=1
      while IFS= read -r n; do
        case "$n" in libdl.so|libm.so|libc.so|"") ;; *) ok=0; warn "aether has unexpected NEEDED '$n'" ;; esac
      done <<<"$needed"
      [ $ok -eq 1 ] || fail "aether NEEDED outside allowlist {libdl,libm,libc}"
      ;;
    shared-lib)
      [ "$typ" = "DYN" ] || fail "$base must be ET_DYN shared library, got $typ"
      [ -n "$has_dyn" ] || fail "$base has no PT_DYNAMIC segment"
      case "$base" in
        libzeptun-jni.so)
          local okj=1
          while IFS= read -r n; do
            case "$n" in liblog.so|libc.so|"") ;; *) okj=0; warn "libzeptun-jni unexpected NEEDED '$n'" ;; esac
          done <<<"$needed"
          [ $okj -eq 1 ] || warn "libzeptun-jni NEEDED outside {liblog,libc} — record and review"
          ;;
        libzeptun.so)
          [ "$needed_count" -gt 0 ] && warn "$base has NEEDED entries — record and review (Zig android expected libc-free)"
          ;;
      esac
      ;;
  esac

  # ---- PT_LOAD: every segment, raw-data derived minimum, congruence ----
  local min=0 first=1 congruent16=1 congruent_seg=1 nload=0
  local load_json="" lflg_t
  while IFS='|' read -r _ loff lvaddr lfilesz lmemsz lflags lalign; do
    [ -n "$lvaddr" ] || continue
    local offd vad al
    offd=$(hex "$loff"); vad=$(hex "$lvaddr"); al=$(hex "$lalign")
    lflg_t=$(echo "$lflags" | tr -d ' ')
    nload=$((nload+1))
    [ "$al" -gt 0 ] || { fail "LOAD segment $nload: p_align = 0 (invalid)"; continue; }
    [ $first -eq 1 ] && min=$al; first=0
    [ "$al" -lt "$min" ] && min=$al
    emit "    LOAD off=$loff vaddr=$lvaddr memsz=$lmemsz flags=$lflg_t align=$lalign (dec: $al)"
    # ELF validity: p_offset = p_vaddr (mod p_align)
    local dseg=$(( (vad - offd) % al ))
    [ "$dseg" -ne 0 ] && { congruent_seg=0; fail "LOAD segment $nload: (vaddr-offset) mod p_align = $dseg (must be 0)"; }
    if is_16kb_arch "$abi"; then
      local d16=$(( (vad - offd) % 16384 ))
      [ "$d16" -ne 0 ] && { congruent16=0; fail "LOAD segment $nload: (vaddr-offset) mod 16384 = $d16 (bionic 16KB requirement)"; }
    fi
    load_json+="${load_json:+,}$(printf '{"off":"%s","vaddr":"%s","memsz":"%s","flags":"%s","align":"%s","align_dec":%d}' "$loff" "$lvaddr" "$lmemsz" "$lflg_t" "$lalign" "$al")"
  done < <(dump_phdrs "$file" | grep '^LOAD|')
  [ "$nload" -gt 0 ] || fail "no PT_LOAD program headers found"
  emit "  min p_align = $min dec (raw-derived)"

  # ---- 16 KB / 4 KB LOAD rule ----
  local kb16_load="N/A"
  if [ "$nload" -gt 0 ]; then
    if is_16kb_arch "$abi"; then
      if [ "$min" -ge 16384 ]; then
        kb16_load="PASS"
        emit "  16KB LOAD rule: PASS (min p_align $min >= 16384) [static ELF fact — runtime NOT TESTED]"
      else
        kb16_load="FAIL"
        if [ "$warn_only_exec16" -eq 1 ] && [ "${STRICT_16KB_X86_64_EXEC:-0}" != "1" ]; then
          warn "16KB LOAD rule on x86_64 Go executable: min p_align $min < 16384 — static ELF fact recorded as kb16_load=FAIL; artifact verdict downgraded to PASS_WITH_WARNINGS (upstream Go linux/amd64 linker default; changing the build is a frozen-pin employer decision, N8; runtime behaviour NOT TESTED; set STRICT_16KB_X86_64_EXEC=1 to hard-fail)"
        else
          fail "16KB LOAD rule: min p_align $min < required 16384"
        fi
      fi
      if [ "$congruent16" -eq 1 ] && [ "$congruent_seg" -eq 1 ]; then
        emit "  16KB congruence: PASS (all LOAD vaddr = offset mod p_align and mod 16384)"
      fi
    else
      # 4 KB architecture: the 16 KB rule does not apply — N/A.
      if [ "$min" -ge 4096 ]; then
        kb16_load="N/A"
        emit "  16KB LOAD rule: N/A (armeabi-v7a = 4 KB architecture; 4 KB ELF validity PASS: min p_align $min >= 4096)"
      else
        kb16_load="FAIL"
        fail "4KB ELF validity (armeabi-v7a): min p_align $min < 4096 — invalid even for a 4 KB device"
      fi
    fi
  fi

  # ---- PT_GNU_RELRO two-case analysis (v3) ----
  analyze_relro "$abi" "$file"

  # ---- verdict ----
  local verdict="PASS"
  if [ $((FAILURES-f0)) -gt 0 ]; then
    verdict="FAIL"
  elif [ $((WARNINGS-w0)) -gt 0 ]; then
    verdict="PASS_WITH_WARNINGS"
  fi
  emit "  verdict: $verdict (static ELF inspection only — runtime in a 16 KB Android environment: NOT TESTED)"
  printf '{"abi":"%s","path":"%s","group":"%s","kind":"%s","class":"%s","machine":"%s","type":"%s","pt_interp":%s,"pt_dynamic":%s,"df_1_pie":%s,"needed":[%s],"needed_count":%d,"load_segment_count":%d,"min_load_align_dec":%d,"kb16_load":"%s","kb16_relro":"%s","relro":%s,"congruent_mod_p_align":%s,"congruent_mod_16384":%s,"verdict":"%s","runtime_16kb_env":"NOT TESTED"}\n' \
    "$abi" "$rel" "$group" "$kind" "$cls" "$(json_escape "$mach")" "$typ" \
    "$([ -n "$has_interp" ] && echo true || echo false)" \
    "$([ -n "$has_dyn" ] && echo true || echo false)" \
    "$([ "$pie_flag" -eq 1 ] && echo true || echo false)" \
    "$needed_json" "$needed_count" "$nload" "$min" "$kb16_load" "$KB16_RELRO" "$RELRO_JSON" \
    "$([ "$congruent_seg" -eq 1 ] && echo true || echo false)" \
    "$([ "$congruent16" -eq 1 ] && echo true || echo false)" \
    "$verdict" >> "$RECORDS"
}

record_missing() { # abi rel group
  local abi="$1" rel="$2" group="$3"
  MISSING=$((MISSING+1))
  emit "--- [$abi] $rel | MISSING — component not built in this run — NOT TESTED ---"
  printf '{"abi":"%s","path":"%s","group":"%s","kind":"missing","verdict":"MISSING","runtime_16kb_env":"NOT TESTED"}\n' "$abi" "$rel" "$group" >> "$RECORDS"
}

emit "=== AETHONE ELF/ABI inspection v4 — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
emit "dir: $DIR"
emit "mode: $([ $EVIDENCE_MODE -eq 1 ] && echo 'EVIDENCE (violations recorded, exit 0 — upstream artifact runs only)' || echo 'CI (strict)') / missing-artifacts: $([ $ALLOW_MISSING -eq 1 ] && echo 'allowed+recorded (NOT TESTED)' || echo 'fatal')"
emit "rules: developer.android.com/guide/practices/page-sizes —"
emit "  LOAD: p_align >= 16384 on arm64-v8a & x86_64 (16KB arches), p_vaddr = p_offset (mod p_align) and (mod 16384); armeabi-v7a = 4KB arch -> 16KB N/A, 4KB validity enforced"
emit "  RELRO (two-case, v4): EVERY PT_GNU_RELRO segment analyzed independently; shared-load -> official formula (VirtAddr+MemSiz)%16384==0; own-load -> formula NOT applicable, every subsequent writable LOAD must start at/after page_up(relro_end); aggregate FAIL>WARN>N/A>PASS"
emit "  zipalign -P 16 stays a SEPARATE check (no APK exists — NOT TESTED)"
emit "  static ELF compliance != runtime proof: runtime_16kb_env = NOT TESTED for every artifact"
emit ""

# Layout sanity checks — a contaminated artifact tree must never pass silently.
if [ -d "$DIR/zeptun" ] || [ -d "$DIR/aether" ]; then
  fail "flattened layout detected (zeptun/ or aether/ at the root) — the three ABI trees must stay separate (out/<abi>/...)"
fi
hygiene_hits=$(find "$DIR" \( -name 'zeptun-build' -o -name 'zig-out' -o -name '.zig-cache' -o -name 'obj' -o -name '*.o' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' \) 2>/dev/null | head -20)
if [ -n "$hygiene_hits" ]; then
  if [ $EVIDENCE_MODE -eq 1 ]; then
    warn "intermediate build products inside the tree (recorded; evidence tree): $(echo "$hygiene_hits" | tr '\n' ' ')"
  else
    while IFS= read -r h; do
      [ -n "$h" ] && fail "intermediate build product inside the artifact tree (must never be uploaded): $h"
    done <<<"$hygiene_hits"
  fi
fi

found=0
for abi in arm64-v8a armeabi-v7a x86_64; do
  [ -d "$DIR/$abi" ] || { emit "[abi $abi] no directory — leg not built / not downloaded"; continue; }
  emit "================ [$abi] ================"
  # registry: rel-path|group|kind
  while IFS='|' read -r rel group kind; do
    f="$DIR/$abi/$rel"
    if [ ! -f "$f" ]; then
      record_missing "$abi" "$rel" "$group"
      continue
    fi
    found=$((found+1))
    case "$kind" in
      static-archive) inspect_archive "$abi" "$f" "$group" "$abi/$rel" || true ;;
      *)              inspect_elf_one "$abi" "$f" "$group" "$abi/$rel" "$kind" || true ;;
    esac
    emit ""
  done <<EOF
zeptun/libzeptun.so|zeptun|shared-lib
zeptun/libzeptun-jni.so|zeptun|shared-lib
zeptun/libzeptun.a|zeptun|static-archive
aether/aether|aether|executable-pie
aether/libaether.so|aether|shared-lib
aether/pt/psiphon-tunnel-core|aether/pt|go-static
aether/pt/lyrebird|aether/pt|go-static
EOF
done
[ $found -eq 0 ] && fail "no artifacts found under $DIR (did native-build run?)"

[ $MISSING -gt 0 ] && [ $ALLOW_MISSING -eq 0 ] && fail "$MISSING expected artifact(s) missing (strict CI mode)"

# count PASS_WITH_WARNINGS records for the summary
warn_recs=$(grep -c '"verdict":"PASS_WITH_WARNINGS"' "$RECORDS")
warn_recs=${warn_recs:-0}

verdict="PASS"
[ "$warn_recs" -gt 0 ] && verdict="PASS_WITH_WARNINGS"
[ $((FAILURES)) -gt 0 ] && verdict="FAIL"
{
  echo '{'
  echo "  \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"inspector_version\": \"v4 (independent multi-PT_GNU_RELRO analysis, two-case RELRO, armv7 N/A, [] NEEDED, PASS_WITH_WARNINGS, runtime separation)\","
  echo "  \"mode\": \"$([ $EVIDENCE_MODE -eq 1 ] && echo evidence || echo ci)\","
  echo "  \"inspected\": $found,"
  echo "  \"missing\": $MISSING,"
  echo "  \"failures\": $FAILURES,"
  echo "  \"warnings\": $WARNINGS,"
  echo "  \"pass_with_warnings_records\": $warn_recs,"
  echo "  \"verdict\": \"$verdict\","
  echo "  \"runtime_16kb_env\": \"NOT TESTED\","
  echo "  \"runtime_note\": \"static ELF compliance does not prove execution in a real 16 KB Android environment; no runtime/device/emulator test has been performed\","
  echo "  \"zipalign_p16\": \"NOT TESTED (no APK exists)\","
  echo "  \"artifacts\": ["
  sed '$!s/$/,/' "$RECORDS" | sed 's/^/    /'
  echo '  ]'
  echo '}'
} > "$JSON"

emit "=== verdict: $verdict — failures=$FAILURES warnings=$WARNINGS missing=$MISSING pass_with_warnings=$warn_recs ==="
emit "=== runtime 16 KB environment: NOT TESTED (static ELF inspection only) | zipalign -P 16: NOT TESTED (no APK) ==="
cat "$JSON" | tee -a "$LOG" >/dev/null
if [ $EVIDENCE_MODE -eq 1 ]; then
  emit "evidence-mode: exit 0 (violations above are FINDINGS about the inspected upstream artifacts, not CI results)"
  exit 0
fi
[ $FAILURES -eq 0 ] || exit 1
exit 0
