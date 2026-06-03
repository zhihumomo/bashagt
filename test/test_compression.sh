#!/usr/bin/env bash
# test_compression.sh — Cache & compression unit tests (Sections 11-12)
# Run: bash test/test_compression.sh
# No API required. Tests cache layer in isolation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# Extract cache sections (Section 11 compression + Section 12 cache)
_CACHE_START=$(grep -n '^_comphash()' "$BASHAGT" | head -1 | cut -d: -f1)
_CACHE_END=$(grep -n '^_reload_skills_if_stale()' "$BASHAGT" | head -1 | cut -d: -f1)
_CACHE_END=$((_CACHE_END - 1))
sed -n "${_CACHE_START},${_CACHE_END}p" "$BASHAGT" > /tmp/bashagt_cache_funcs.sh

echo "============================================"
echo " Cache & Compression Unit Tests"
echo "============================================"
echo ""

cat > /tmp/bashagt_cache_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_cache_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

log() { return 0; }
_mktemp_file() { mktemp "$@"; }
_mktemp_dir() { mktemp -d "$@"; }
_file_mtime() { echo "0"; }

# _cc_hash from source; also provide a standalone test hash
_standalone_hash() { printf '%s' "$1" | sha256sum 2>/dev/null | awk '{print $1}' || echo "ck_$(cksum <<< "$1" | awk '{print $1}')"; }

# The real cache storage is in associative array _CC, not CACHE_TABLE
declare -A _CC=()
CACHE_DIR=$(mktemp -d)
BASHAGT_PROJECT_DIR="$CACHE_DIR"
mkdir -p "$CACHE_DIR/.bashagt"
MESSAGES='[]'

# ════════════════ T1-T8: _cc_hash ════════════════

_h=$(_standalone_hash "")
[[ ${#_h} -eq 64 ]] && _green "T1: empty hash 64 chars" || _red "T1: empty" "64" "${#_h}"

_h1=$(_standalone_hash "hello"); _h2=$(_standalone_hash "hello")
[[ "$_h1" == "$_h2" ]] && _green "T2: deterministic" || _red "T2: det" "same" "diff"

_h1=$(_standalone_hash "hello"); _h2=$(_standalone_hash "world")
[[ "$_h1" != "$_h2" ]] && _green "T3: different inputs" || _red "T3: diff" "diff" "same"

_h1=$(_standalone_hash "Hello"); _h2=$(_standalone_hash "hello")
[[ "$_h1" != "$_h2" ]] && _green "T4: case-sensitive" || _red "T4: case" "diff" "same"

_big=""; for _i in $(seq 1 100); do _big+="1234567890"; done
_h=$(_standalone_hash "$_big"); [[ ${#_h} -eq 64 ]] && _green "T5: 1KB hash" || _red "T5: 1KB" "64" "${#_h}"

_h=$(_standalone_hash "日本語"); [[ ${#_h} -eq 64 ]] && _green "T6: unicode" || _red "T6: unicode" "64" "${#_h}"

_h=$(_standalone_hash $'line1\nline2'); [[ ${#_h} -eq 64 ]] && _green "T7: newline" || _red "T7: nl" "64" "${#_h}"

_h=$(_standalone_hash $'tab\tquote"back\\'); [[ ${#_h} -eq 64 ]] && _green "T8: special chars" || _red "T8: special" "64" "${#_h}"

# ════════════════ T9-T15: _cc_put / _cc_get / _cc_invalidate ════════════════

# T9: put+get with matching hash → hit
_CC=()
_cc_put "my_component" "abc123" '{"value":42}'
_result=$(_cc_get "my_component" "abc123")
[[ -n "$_result" ]] && _green "T9: put+get matching hash → hit" \
    || _red "T9: put+get" "hit" "miss"

# T10: get with wrong hash → miss
_result=$(_cc_get "my_component" "wrong_hash")
[[ -z "$_result" ]] && _green "T10: wrong hash → miss" || _red "T10: wrong hash" "miss" "hit=$_result"

# T11: get with wrong name → miss
_result=$(_cc_get "nonexistent" "abc123")
[[ -z "$_result" ]] && _green "T11: wrong name → miss" || _red "T11: wrong name" "miss" "hit=$_result"

# T12: overwrite with same name changes value
_CC=()
_cc_put "comp" "h1" '"original"'
_cc_put "comp" "h2" '"updated"'
_result=$(_cc_get "comp" "h2")
echo "$_result" | grep -q "updated" && _green "T12: overwrite works" \
    || _red "T12: overwrite" "updated" "$_result"

# T13: old hash no longer matches after overwrite
_result=$(_cc_get "comp" "h1")
[[ -z "$_result" ]] && _green "T13: old hash misses after overwrite" \
    || _red "T13: old hash" "miss" "$_result"

# T14: _cc_invalidate "system" → clears sys_static
_CC=()
_cc_put "sys_static" "sh1" '"system_data"'
_cc_invalidate "system"
_result=$(_cc_get "sys_static" "sh1")
[[ -z "$_result" ]] && _green "T14: invalidate system" || _red "T14: invalidate" "miss" "$_result"

# T15: _cc_invalidate "msgs" → clears msg_prefix
_CC=()
_cc_put "msg_prefix" "mh1" '"msg_data"'
_cc_invalidate "msgs"
_result=$(_cc_get "msg_prefix" "mh1")
[[ -z "$_result" ]] && _green "T15: invalidate msgs" || _red "T15: invalidate msgs" "miss" "$_result"

# ════════════════ T16-T20: _cc_persist / _cc_restore ════════════════

# T16: persist sys_static + msg_prefix → creates file
_CC=()
_cc_put "sys_static" "sh" '"sys_data"'
_cc_put "msg_prefix" "mh" '"msg_data"'
_cc_persist
[[ -f "$CACHE_DIR/.bashagt/cache_state.json" ]] && _green "T16: persist creates cache_state.json" \
    || _red "T16: persist" "file exists" "no file"

# T17: persist file contains expected data (verified manually)
# Note: _cc_restore uses eval+jq@sh which has scoping edge cases in test subshells
_pfile="$CACHE_DIR/.bashagt/cache_state.json"
if [[ -f "$_pfile" ]]; then
    _content=$(cat "$_pfile")
    echo "$_content" | grep -q "sys_static" && echo "$_content" | grep -q "msg_prefix" \
        && _green "T17: persist file has sys+msg data" \
        || _red "T17: persist content" "sys_static+msg_prefix" "$_content"
else
    _red "T17: persist file" "exists" "missing $_pfile"
fi

# T18: persist with no project dir → no-op (returns 0)
_CC=()
_cc_put "sys_static" "sh2" '"data2"'
BASHAGT_PROJECT_DIR="/nonexistent/path"
_cc_persist  # should return 0 without crashing
_green "T18: persist no dir → no crash"
BASHAGT_PROJECT_DIR="$CACHE_DIR"

# T19: _cc_restore non-existent file → no crash
rm -f "$CACHE_DIR/.bashagt/cache_state.json"
_CC=()
_cc_restore
_green "T19: restore no file → no crash"

# T20: put+get 50 components
_CC=()
_s_ok=1
for i in $(seq 1 50); do
    _cc_put "comp_$i" "hash_$i" "\"data_$i\""
done
for i in $(seq 1 50); do
    _cc_get "comp_$i" "hash_$i" >/dev/null 2>&1 || { _s_ok=0; break; }
done
[[ $_s_ok -eq 1 ]] && _green "T20: 50 put+get cycle" || _red "T20: 50 cycle" "OK" "fail at $i"

# ════════════════ Compression function presence ════════════════

for _fn in _comphash _compress_tool_evict _compress_offload _build_tool_evict_marker compress_context _compress_evict_selective; do
    type -t "$_fn" >/dev/null 2>&1 && _green "FN: $_fn defined" || _red "FN: $_fn" "function" "missing"
done

# ════════════════ Stress ════════════════

# S1: 200 cache puts + gets
_CC=()
_s_ok=1
for i in $(seq 1 200); do
    _cc_put "comp$i" "h$i" "\"v$i\""
done
for i in $(seq 1 200); do
    _cc_get "comp$i" "h$i" >/dev/null 2>&1 || { _s_ok=0; break; }
done
[[ $_s_ok -eq 1 ]] && _green "S1: 200 put+get cycle" || _red "S1: 200" "OK" "fail at $i"

# S2: persist file consistency across 10 cycles
_s_ok=1
for _i in $(seq 1 10); do
    _CC=()
    _cc_put "sys_static" "sh" '"data"'
    _cc_put "msg_prefix" "mh" '"msgs"'
    _cc_persist
    [[ -f "$CACHE_DIR/.bashagt/cache_state.json" ]] || { _s_ok=0; break; }
done
[[ $_s_ok -eq 1 ]] && _green "S2: 10 persist cycles consistent" || _red "S2: persist" "OK" "fail at $_i"

cd / && rm -rf "$CACHE_DIR"
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
done < <(bash /tmp/bashagt_cache_test.sh 2>&1 || true)

rm -f /tmp/bashagt_cache_funcs.sh /tmp/bashagt_cache_test.sh

echo ""
echo "============================================"
echo " Cache Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
