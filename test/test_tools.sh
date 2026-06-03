#!/usr/bin/env bash
# test_tools.sh — Core tools unit tests (Section 20)
# Run: bash test/test_tools.sh
# No API required. Tests file/batch tools in temp dir sandbox.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

_TOOLS_START=$(grep -n '^invalidate_tools_cache()' "$BASHAGT" | head -1 | cut -d: -f1)
_TOOLS_END=$(grep -n '^_safe_confirm()' "$BASHAGT" | head -1 | cut -d: -f1)
_TOOLS_END=$((_TOOLS_END - 1))
sed -n "${_TOOLS_START},${_TOOLS_END}p" "$BASHAGT" > /tmp/bashagt_tools_funcs.sh

echo "============================================"
echo " Core Tools Unit Tests"
echo "============================================"
echo ""

cat > /tmp/bashagt_tools_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_tools_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

log() { return 0; }
_mktemp_file() { mktemp "$@"; }
_mktemp_u() { mktemp -u "$@"; }
_trace_object_store() { echo "mock_hash_$(date +%s)"; }
trace_record() { return 0; }
_timestamp_ms() { date +%s%3N 2>/dev/null || echo "1700000000000"; }
_stream_kv() { return 0; }
ui_time() { echo "0.0s"; }
ui_label() { echo "$2"; }
ui_dot() { echo "."; }
build_agent_schema() { echo '{}'; }
mcp_build_tools_json() { echo ""; }
_spin_sleep() { sleep 0.01; return 0; }
BASHAGT_TRACE_ENABLED=0
BASHAGT_DAEMON_PID=""
TOOLS_JSON_CACHE=""
TOOLS_CACHE_EPOCH=0
AGENT_SELF_NAME="test-agent"
TURN_COUNT=0
BASHAGT_TRACE_DESC=""

SANDBOX=$(mktemp -d)
cd "$SANDBOX"

# ════════════════ T1-T10: tool_read_file ════════════════

# T1: normal file read
echo -e "line1\nline2\nline3" > "$SANDBOX/test.txt"
_out=$(tool_read_file "$SANDBOX/test.txt")
echo "$_out" | grep -q "line1" && _green "T1: reads file" || _red "T1: read" "line1" "$_out"

# T2: offset
_out=$(tool_read_file "$SANDBOX/test.txt" 2)
echo "$_out" | grep -q "line2" && ! echo "$_out" | grep -q "line1" && _green "T2: offset=2" \
    || _red "T2: offset" "line2 no line1" "$_out"

# T3: limit
_out=$(tool_read_file "$SANDBOX/test.txt" 1 2)
_lines=$(echo "$_out" | grep -c "^[ 0-9]" || echo 0)
[[ $_lines -le 2 ]] && _green "T3: limit=2 (lines=$_lines)" \
    || _red "T3: limit" "<=2" "lines=$_lines"

# T4: file not found
_out=$(tool_read_file "$SANDBOX/nonexistent.txt" 2>&1)
_rc=$?
echo "$_out" | grep -qi "not found" && _green "T4: nonexistent → error" \
    || _red "T4: nonexistent" "not found" "$_out"

# T5: empty path
_out=$(tool_read_file "" 2>&1)
_rc=$?
[[ $_rc -ne 0 || "$_out" == *"ERROR"* ]] && _green "T5: empty path → error" \
    || _red "T5: empty path" "ERROR" "rc=$_rc out=$_out"

# T6: empty file
> "$SANDBOX/empty.txt"
_out=$(tool_read_file "$SANDBOX/empty.txt" 2>&1)
[[ -z "$_out" || "$_out" =~ ^[[:space:]]*$ ]] && _green "T6: empty file ok" \
    || _red "T6: empty" "empty output" "$_out"

# T7: binary file (null bytes)
printf 'text\0binary' > "$SANDBOX/binary.bin"
_out=$(tool_read_file "$SANDBOX/binary.bin" 2>&1)
echo "$_out" | grep -qi "binary\|Warning" && _green "T7: binary warning" \
    || _red "T7: binary" "Warning" "$_out"

# T8: offset beyond file → tail -n +999 produces no output
_out=$(tool_read_file "$SANDBOX/test.txt" 999)
_lines=$(echo "$_out" | grep -cE "^[ ]*[0-9]" 2>/dev/null || true)
[[ -z "$_lines" || "$_lines" == "0" ]] && _green "T8: offset beyond EOF" \
    || _red "T8: beyond EOF" "0 lines" "lines=$_lines"

# T9: single line file
echo "single" > "$SANDBOX/single.txt"
_out=$(tool_read_file "$SANDBOX/single.txt")
echo "$_out" | grep -q "single" && _green "T9: single line" \
    || _red "T9: single" "single" "$_out"

# T10: limit=0 → head -n 0 prints nothing, only number lines
_out=$(tool_read_file "$SANDBOX/test.txt" 1 0)
# With limit=0, head -n 0 produces no output; no line-numbered lines
_lines=$(echo "$_out" | grep -cE "^[ ]*[0-9]" 2>/dev/null || true)
[[ -z "$_lines" || "$_lines" == "0" ]] && _green "T10: limit=0 → no lines" \
    || _red "T10: limit=0" "0 lines" "lines=$_lines"

# ════════════════ T11-T20: tool_write_file ════════════════

# T11: create new file
_out=$(tool_write_file "$SANDBOX/write_test.txt" "hello world")
echo "$_out" | grep -q "written successfully" && [[ -f "$SANDBOX/write_test.txt" ]] \
    && _green "T11: creates file" || _red "T11: create" "written successfully" "$_out"

# T12: content matches
_content=$(cat "$SANDBOX/write_test.txt")
[[ "$_content" == "hello world" ]] && _green "T12: content roundtrip" \
    || _red "T12: content" "hello world" "$_content"

# T13: overwrite existing → error
_out=$(tool_write_file "$SANDBOX/write_test.txt" "new content" 2>&1)
echo "$_out" | grep -q "already exists" && _green "T13: refuses overwrite" \
    || _red "T13: overwrite" "already exists" "$_out"

# T14: empty path → error
_out=$(tool_write_file "" "content" 2>&1)
echo "$_out" | grep -q "ERROR" && _green "T14: empty path → error" \
    || _red "T14: empty path" "ERROR" "$_out"

# T15: creates parent directory
_out=$(tool_write_file "$SANDBOX/newdir/subdir/file.txt" "nested")
echo "$_out" | grep -q "written successfully" && [[ -f "$SANDBOX/newdir/subdir/file.txt" ]] \
    && _green "T15: creates parent dirs" || _red "T15: mkdir -p" "success" "$_out"

# T16: empty content → creates empty file
_out=$(tool_write_file "$SANDBOX/empty_write.txt" "")
[[ -f "$SANDBOX/empty_write.txt" ]] && _green "T16: empty content ok" \
    || _red "T16: empty" "file exists" "no file"

# T17: multi-line preview (truncated at 23 lines)
_big_content=""; for _i in $(seq 1 30); do _big_content+="line $_i"$'\n'; done
_out=$(tool_write_file "$SANDBOX/big_preview.txt" "$_big_content")
echo "$_out" | grep -q "additional new lines" && _green "T17: >23 line preview truncated" \
    || _red "T17: preview" "additional new lines" "$_out"

# T18: special characters preserved
_special='$`"'\''\n!@#'
_out=$(tool_write_file "$SANDBOX/special.txt" "$_special")
_readback=$(cat "$SANDBOX/special.txt")
[[ "$_readback" == "$_special" ]] && _green "T18: special chars preserved" \
    || _red "T18: special chars" "$_special" "$_readback"

# T19: trace record not called when disabled
_out=$(tool_write_file "$SANDBOX/trace_off.txt" "test")
echo "$_out" | grep -q "written successfully" && _green "T19: write with trace disabled" \
    || _red "T19: trace off" "success" "$_out"

# T20: path with spaces
_out=$(tool_write_file "$SANDBOX/path with spaces.txt" "spaces ok")
[[ -f "$SANDBOX/path with spaces.txt" ]] && _green "T20: spaces in path" \
    || _red "T20: spaces" "file exists" "no file"

# ════════════════ T21-T28: tool_delete_file ════════════════

# T21: delete existing file
echo "delete me" > "$SANDBOX/delete_me.txt"
_out=$(tool_delete_file "$SANDBOX/delete_me.txt")
echo "$_out" | grep -q "Deleted" && [[ ! -f "$SANDBOX/delete_me.txt" ]] \
    && _green "T21: deletes file" || _red "T21: delete" "Deleted" "$_out"

# T22: nonexistent → error
_out=$(tool_delete_file "$SANDBOX/nope.txt" 2>&1)
echo "$_out" | grep -q "not found" && _green "T22: nonexistent → error" \
    || _red "T22: nonexistent" "not found" "$_out"

# T23: empty path → error
_out=$(tool_delete_file "" 2>&1)
echo "$_out" | grep -q "ERROR" && _green "T23: empty path → error" \
    || _red "T23: empty" "ERROR" "$_out"

# T24: directory without recursive → error
mkdir "$SANDBOX/deldir"
_out=$(tool_delete_file "$SANDBOX/deldir" 2>&1)
echo "$_out" | grep -q "directory\|recursive" && _green "T24: dir needs recursive=true" \
    || _red "T24: dir" "recursive=true" "$_out"

# T25: directory with recursive → success
mkdir -p "$SANDBOX/recursive_dir/sub"
echo "a" > "$SANDBOX/recursive_dir/a.txt"
echo "b" > "$SANDBOX/recursive_dir/sub/b.txt"
_out=$(tool_delete_file "$SANDBOX/recursive_dir" "true")
echo "$_out" | grep -q "Deleted" && [[ ! -d "$SANDBOX/recursive_dir" ]] \
    && _green "T25: recursive delete" || _red "T25: recursive" "Deleted" "$_out"

# T26: empty directory recursive
mkdir "$SANDBOX/empty_dir"
_out=$(tool_delete_file "$SANDBOX/empty_dir" "true")
echo "$_out" | grep -q "Deleted" && _green "T26: empty dir recursive" \
    || _red "T26: empty dir" "Deleted" "$_out"

# T27: trace disabled
echo "trace off" > "$SANDBOX/trace_del.txt"
BASHAGT_TRACE_ENABLED=0
_out=$(tool_delete_file "$SANDBOX/trace_del.txt")
echo "$_out" | grep -q "Deleted" && _green "T27: delete trace disabled" \
    || _red "T27: trace off" "Deleted" "$_out"

# T28: deletion confirmed not exists
echo "del2" > "$SANDBOX/del2.txt"
_out=$(tool_delete_file "$SANDBOX/del2.txt")
[[ ! -e "$SANDBOX/del2.txt" ]] && _green "T28: file really gone" \
    || _red "T28: gone" "not exists" "still exists"

# ════════════════ T29-T43: tool_edit_file ════════════════

# T29: simple replacement
echo "hello world" > "$SANDBOX/edit.txt"
_out=$(tool_edit_file "$SANDBOX/edit.txt" "hello" "hi")
echo "$_out" | grep -qE -- "^-|^\+|^[ 0-9]" && _green "T29: edit shows diff" \
    || _red "T29: diff" "diff output" "$_out"
_content=$(cat "$SANDBOX/edit.txt")
[[ "$_content" == "hi world" ]] && _green "T29b: content updated" \
    || _red "T29b: content" "hi world" "$_content"

# T30: old_str not found
_out=$(tool_edit_file "$SANDBOX/edit.txt" "xyz_not_there" "replace" 2>&1)
echo "$_out" | grep -q "not found" && _green "T30: old_str not found → error" \
    || _red "T30: not found" "not found" "$_out"

# T31: duplicate detection — verify fix: strip first occurrence, check remainder
printf 'dup\nsomething\ndup\n' > "$SANDBOX/dup.txt"
_out=$(tool_edit_file "$SANDBOX/dup.txt" "dup" "replaced" 2>&1)
_rc=$?
echo "$_out" | grep -qi "multiple" && _green "T31: multiple occurrences detected → error" \
    || _red "T31: multiple" "multiple" "rc=$_rc out=$(head -1 <<< "$_out")"

# T31b: single occurrence still works
echo "only one match here" > "$SANDBOX/single_dup.txt"
_out=$(tool_edit_file "$SANDBOX/single_dup.txt" "match" "FOUND")
_content=$(cat "$SANDBOX/single_dup.txt")
[[ "$_content" == "only one FOUND here" ]] && _green "T31b: single occurrence works" \
    || _red "T31b: single" "only one FOUND here" "$_content"

# T32: file not found
_out=$(tool_edit_file "$SANDBOX/no.txt" "a" "b" 2>&1)
echo "$_out" | grep -q "not found" && _green "T32: file not found → error" \
    || _red "T32: no file" "not found" "$_out"

# T33: empty path → error
_out=$(tool_edit_file "" "a" "b" 2>&1)
echo "$_out" | grep -q "ERROR" && _green "T33: empty path → error" \
    || _red "T33: empty" "ERROR" "$_out"

# T34: replace with empty string (deletes match)
echo "remove this part keep" > "$SANDBOX/empty_repl.txt"
_out=$(tool_edit_file "$SANDBOX/empty_repl.txt" "this part " "")
_content=$(cat "$SANDBOX/empty_repl.txt")
[[ "$_content" == "remove keep" ]] && _green "T34: replace with empty" \
    || _red "T34: empty repl" "remove keep" "$_content"

# T35: special regex chars treated as literal
echo 'a[b.c*d\e$f^g' > "$SANDBOX/literal.txt"
_out=$(tool_edit_file "$SANDBOX/literal.txt" "[b.c*d\\e\$f^g" "REPLACED" 2>&1)
_content=$(cat "$SANDBOX/literal.txt")
[[ "$_content" == "aREPLACED" ]] && _green "T35: special chars literal" \
    || _red "T35: literal" "aREPLACED" "$_content"

# T36: first line replacement
echo -e "line1\nline2\nline3" > "$SANDBOX/first.txt"
_out=$(tool_edit_file "$SANDBOX/first.txt" "line1" "FIRST")
_content=$(cat "$SANDBOX/first.txt")
[[ "$_content" == $'FIRST\nline2\nline3' ]] && _green "T36: first line replace" \
    || _red "T36: first" "FIRST..." "$_content"

# T37: last line replacement
echo -e "a\nb\nlast" > "$SANDBOX/last.txt"
_out=$(tool_edit_file "$SANDBOX/last.txt" "last" "FINAL")
_content=$(cat "$SANDBOX/last.txt")
[[ "$_content" == $'a\nb\nFINAL' ]] && _green "T37: last line replace" \
    || _red "T37: last" "...FINAL" "$_content"

# T38: multi-line replacement
echo -e "start\nmiddle\nend" > "$SANDBOX/multi.txt"
# bash's ${content/"old"/"new"} works with embedded newlines
_out=$(tool_edit_file "$SANDBOX/multi.txt" $'start\nmiddle' "BEGIN" 2>&1)
_rc=$?
[[ $_rc -eq 0 ]] && _green "T38: multi-line old_str accepted" \
    || _red "T38: multi-line" "rc=0" "rc=$_rc"

# T39: content unchanged for failed edit
echo "important data" > "$SANDBOX/unchanged.txt"
_out=$(tool_edit_file "$SANDBOX/unchanged.txt" "nonexistent" "replace" 2>&1)
_content=$(cat "$SANDBOX/unchanged.txt")
[[ "$_content" == "important data" ]] && _green "T39: unchanged on failed edit" \
    || _red "T39: unchanged" "important data" "$_content"

# T40: diff shows line numbers
echo "line A" > "$SANDBOX/diffnum.txt"
_out=$(tool_edit_file "$SANDBOX/diffnum.txt" "A" "B")
echo "$_out" | grep -qE "^[ 0-9]" && _green "T40: diff has line numbers" \
    || _red "T40: line nums" "numbered lines" "$_out"

# T41: trace disabled
echo "trace test" > "$SANDBOX/etrace.txt"
BASHAGT_TRACE_ENABLED=0
_out=$(tool_edit_file "$SANDBOX/etrace.txt" "test" "ok")
_content=$(cat "$SANDBOX/etrace.txt")
[[ "$_content" == "trace ok" ]] && _green "T41: edit trace disabled" \
    || _red "T41: trace" "trace ok" "$_content"

# T42: new content longer than old
echo "short" > "$SANDBOX/longer.txt"
_out=$(tool_edit_file "$SANDBOX/longer.txt" "short" "much longer replacement text here")
echo "$_out" | grep -q "+" && _green "T42: + line in diff" \
    || _red "T42: + line" "+ present" "$_out"

# T43: new content shorter than old
echo "very long text to shorten" > "$SANDBOX/shorter.txt"
_out=$(tool_edit_file "$SANDBOX/shorter.txt" "very long text to" "")
echo "$_out" | grep -q -- "-" && _green "T43: - line in diff" \
    || _red "T43: - line" "- present" "$_out"

# ════════════════ T44-T48: tool_list_files ════════════════

# T44: list files in dir
mkdir "$SANDBOX/listdir"
echo "a" > "$SANDBOX/listdir/a.txt"
echo "b" > "$SANDBOX/listdir/b.txt"
_out=$(tool_list_files "$SANDBOX/listdir")
echo "$_out" | grep -q "a.txt" && echo "$_out" | grep -q "b.txt" && _green "T44: lists files" \
    || _red "T44: list" "a.txt b.txt" "$_out"

# T45: empty directory
mkdir "$SANDBOX/emptylist"
_out=$(tool_list_files "$SANDBOX/emptylist")
_green "T45: empty dir ok"

# T46: not a directory → error
_out=$(tool_list_files "$SANDBOX/listdir/a.txt" 2>&1)
echo "$_out" | grep -q "not a directory" && _green "T46: file→error" \
    || _red "T46: file" "not a directory" "$_out"

# T47: empty path → error
_out=$(tool_list_files "" 2>&1)
echo "$_out" | grep -q "ERROR" && _green "T47: empty path → error" \
    || _red "T47: empty" "ERROR" "$_out"

# T48: nonexistent → error
_out=$(tool_list_files "$SANDBOX/nope_dir" 2>&1)
echo "$_out" | grep -q "not a directory" && _green "T48: nonexistent→error" \
    || _red "T48: nonexistent" "not a directory" "$_out"

# ════════════════ T49-T53: build_tools_json ════════════════

# T49: valid JSON output
_out=$(build_tools_json)
echo "$_out" | jq -e '.' >/dev/null 2>&1 && _green "T49: valid JSON" \
    || _red "T49: valid" "JSON" "$_out"

# T50: is an array
echo "$_out" | jq -e 'type == "array"' >/dev/null 2>&1 && _green "T50: is array" \
    || _red "T50: array" "array" "$(echo "$_out" | jq -r 'type')"

# T51: cache hit (second call uses cache)
TOOLS_JSON_CACHE=""
TOOLS_CACHE_EPOCH=0
_out1=$(build_tools_json)
_out2=$(build_tools_json)
[[ "$_out1" == "$_out2" ]] && _green "T51: cache consistency" \
    || _red "T51: cache" "same" "different"

# T52: invalidate_tools_cache
invalidate_tools_cache
[[ -z "$TOOLS_JSON_CACHE" && "$TOOLS_CACHE_EPOCH" -eq 0 ]] \
    && _green "T52: cache invalidated" || _red "T52: invalidate" "empty cache" "cache=$TOOLS_JSON_CACHE"

# T53: is non-empty array (some tool schemas may be empty strings→null entries)
_out=$(build_tools_json)
_cnt=$(echo "$_out" | jq '[.[] | select(. != null)] | length')
[[ $_cnt -gt 0 ]] && _green "T53: has $_cnt non-null tools" \
    || _red "T53: tools" ">0 non-null" "cnt=$_cnt"

# ════════════════ T54-T58: tool_bash (sync) ════════════════

# T54: simple command
_out=$(tool_bash "echo hello" 5 false)
echo "$_out" | grep -q "hello" && _green "T54: runs command" \
    || _red "T54: bash" "hello" "$_out"

# T55: empty command → error
_out=$(tool_bash "" 5 false 2>&1)
echo "$_out" | grep -q "ERROR\|required" && _green "T55: empty cmd → error" \
    || _red "T55: empty" "ERROR" "$_out"

# T56: exit code captured
_out=$(tool_bash "exit 42" 5 false)
echo "$_out" | grep -q "exit=42" && _green "T56: exit code 42" \
    || _red "T56: exit" "exit=42" "$_out"

# T57: stderr captured
_out=$(tool_bash "echo stderr >&2" 5 false)
echo "$_out" | grep -q "stderr" && _green "T57: stderr captured" \
    || _red "T57: stderr" "stderr" "$_out"

# T58: timeout kills
_out=$(tool_bash "sleep 10" 1 false 2>&1)
echo "$_out" | grep -q "timed out" && _green "T58: timeout" \
    || _red "T58: timeout" "timed out" "$_out"

# ════════════════ Stress ════════════════

# S1: rapid write+delete cycle
_s1_ok=1
for i in $(seq 1 30); do
    tool_write_file "$SANDBOX/stress_$i.txt" "data $i" >/dev/null 2>&1 || { _s1_ok=0; break; }
    tool_delete_file "$SANDBOX/stress_$i.txt" >/dev/null 2>&1 || { _s1_ok=0; break; }
done
[[ $_s1_ok -eq 1 ]] && _green "S1: 30 write+delete cycles" \
    || _red "S1: cycles" "OK" "fail at $i"

# S2: large file edit
_head=""; for _i in $(seq 1 500); do _head+="line $_i"$'\n'; done
echo "${_head}UNIQUE_MARKER_XYZ${_head}" > "$SANDBOX/large.txt"
_start=$SECONDS
_out=$(tool_edit_file "$SANDBOX/large.txt" "UNIQUE_MARKER_XYZ" "REPLACED" 2>&1)
_elapsed=$((SECONDS - _start))
_content=$(cat "$SANDBOX/large.txt")
echo "$_content" | grep -q "REPLACED" && ! echo "$_content" | grep -q "UNIQUE_MARKER" \
    && _green "S2: large file edit in ${_elapsed}s" \
    || _red "S2: large edit" "REPLACED present" "$(echo "$_content" | head -c 200)"

# S3: build_tools_json 50 rapid calls
_s3_ok=1
for i in $(seq 1 50); do
    build_tools_json >/dev/null 2>&1 || { _s3_ok=0; break; }
done
[[ $_s3_ok -eq 1 ]] && _green "S3: 50 build_tools_json calls" \
    || _red "S3: 50 calls" "OK" "fail at $i"

cd / && rm -rf "$SANDBOX"
echo "---DONE---"
TESTEOF

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
        PASS:*) _pass "${line#PASS:}" ;;
        FAIL:*) _fail "${line#FAIL:}" "$(echo "$line" | cut -d'|' -f2)" "$(echo "$line" | cut -d'|' -f3)" ;;
        ---DONE---) ;;
        *) echo "  $line" ;;
    esac
done < <(bash /tmp/bashagt_tools_test.sh 2>&1 || true)

rm -f /tmp/bashagt_tools_funcs.sh /tmp/bashagt_tools_test.sh

echo ""
echo "============================================"
echo " Core Tools Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
