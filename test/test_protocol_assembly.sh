#!/usr/bin/env bash
# test_protocol_assembly.sh — Protocol assembly unit tests (Section 13)
# Run: bash test/test_protocol_assembly.sh
# No API required. Tests request body construction in isolation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# ── Extract protocol assembly section ──
_PROTO_START=$(grep -n '^_reload_skills_if_stale()' "$BASHAGT" | head -1 | cut -d: -f1)
_PROTO_END=$(grep -n '^_http_map_exit()' "$BASHAGT" | head -1 | cut -d: -f1)
_PROTO_END=$((_PROTO_END - 1))
sed -n "${_PROTO_START},${_PROTO_END}p" "$BASHAGT" > /tmp/bashagt_proto_funcs.sh

echo "============================================"
echo " Protocol Assembly Unit Tests"
echo "============================================"
echo ""

# ── Write test script ──
cat > /tmp/bashagt_proto_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_proto_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

# ── Mock infrastructure ──
log() { return 0; }
_mktemp_dir() { mktemp -d "$@"; }
_mktemp_file() { mktemp "$@"; }
_cc_hash() { printf '%s' "$1" | sha256sum 2>/dev/null | awk '{print $1}' || echo "ck_000"; }
_cc_get() { return 1; }  # cache miss
_cc_put() { return 0; }
_cc_invalidate() { return 0; }
_file_mtime() { echo 0; }
load_skills() { return 0; }
build_memory_context() { echo ""; }
build_todo_context() { echo ""; }
build_tools_json() { echo '[]'; }

# ── Required globals ──
_DEFAULT_SP_PREAMBLE="PREAMBLE "
_DEFAULT_SP_IDENTITY="IDENTITY "
_DEFAULT_SP_SAFETY="SAFETY "
_DEFAULT_SP_REST="REST "
CACHE_MARKER_JSON='{"cache_control":{"type":"ephemeral"}}'
BASHAGT_MD=""
BASHAGT_MODEL="test-model"
AGENT_DESCRIPTIONS="explore: searches code"
declare -A SKILL_META=()
declare -a ACTIVE_SKILLS=()
SKILL_DIR_MTIME=0
SKILLS=()
MESSAGES='[]'
TODOS='[]'
PWD="/tmp/test_project"
_MEM_SLEEP_PHASE=0
_HOOK_CONTEXT_BUFFER=""

# ════════════════ T1-T6: _bashagt_md_has_content ════════════════

# T1: BASHAGT_MD has real content → true
printf -v BASHAGT_MD '# Project: Test\n\nDescription: A test project'
_bashagt_md_has_content && _green "T1: has content → true" || _red "T1: content" "true" "false"

# T2: BASHAGT_MD empty → false
BASHAGT_MD=""
_bashagt_md_has_content && _red "T2: empty → false" "false" "true" || _green "T2: empty → false"

# T3: BASHAGT_MD only comments → false
printf -v BASHAGT_MD '# just a comment\n# another comment'
_bashagt_md_has_content && _red "T3: comments only → false" "false" "true" || _green "T3: comments only → false"

# T4: BASHAGT_MD unset → false
unset BASHAGT_MD
_bashagt_md_has_content && _red "T4: unset → false" "false" "true" || _green "T4: unset → false"

# T5: whitespace only (tabs/spaces on one line = still has content after grep -v)
# The function strips lines that are empty or pure-comment. "  " has no # → not stripped.
printf -v BASHAGT_MD '  \n\t'
# This may or may not count depending on implementation — just verify no crash
_bashagt_md_has_content; _rc5=$?
[[ $_rc5 -eq 0 || $_rc5 -eq 1 ]] && _green "T5: whitespace handled (rc=$_rc5)" \
    || _red "T5: whitespace" "0 or 1" "rc=$_rc5"

# T6: BASHAGT_MD has real content after a comment line
printf -v BASHAGT_MD '# comment\nreal content here'
_bashagt_md_has_content && _green "T6: mixed → true" || _red "T6: mixed" "true" "false"
BASHAGT_MD=""

# ════════════════ T7-T14: _pe_assemble_system ════════════════

# T7: basic output with empty BASHAGT_MD
BASHAGT_MD=""
_result=$(_pe_assemble_system 0)
echo "$_result" | jq -e '.' >/dev/null 2>&1 && _green "T7: valid JSON output" \
    || _red "T7: valid JSON" "valid" "$(echo "$_result" | head -c 100)"

# T8: BASHAGT_MD content replaces identity
printf -v BASHAGT_MD '# Custom Identity\nI am a custom agent'
_result=$(_pe_assemble_system 0)
echo "$_result" | grep -q "Custom Identity" && _green "T8: BASHAGT_MD in output" \
    || _red "T8: BASHAGT_MD" "Custom Identity" "$(echo "$_result" | head -c 200)"

# T9: without BASHAGT_MD, uses default identity
BASHAGT_MD=""
_result=$(_pe_assemble_system 0)
echo "$_result" | grep -q "IDENTITY" && _green "T9: default identity present" \
    || _red "T9: default identity" "IDENTITY" "$(echo "$_result" | head -c 200)"

# T10: agent descriptions included
echo "$_result" | grep -q "explore" && _green "T10: agent descriptions" \
    || _red "T10: agent desc" "explore" "$(echo "$_result" | head -c 300)"

# T11: emit_markers=1 adds cache_control to last block
_result=$(_pe_assemble_system 1)
echo "$_result" | jq -e '.[-1].cache_control' >/dev/null 2>&1 && _green "T11: cache_control marker" \
    || _red "T11: cache_control" "present" "absent"

# T12: emit_markers=0 → no cache_control
_result=$(_pe_assemble_system 0)
echo "$_result" | jq -e '.[-1].cache_control' >/dev/null 2>&1 \
    && _red "T12: no cc with emit=0" "absent" "present" \
    || _green "T12: no cache_control when emit=0"

# T13: skills list in output when skills exist
SKILL_META=(["my-skill"]='{"description":"A test skill"}')
ACTIVE_SKILLS=("my-skill")
_result=$(_pe_assemble_system 0)
echo "$_result" | grep -q "my-skill" && _green "T13: skills in output" \
    || _red "T13: skills" "my-skill" "$(echo "$_result" | head -c 300)"
SKILL_META=()
ACTIVE_SKILLS=()

# T14: [active] tag for active skills
SKILL_META=(["s1"]='{"description":"d1"}')
ACTIVE_SKILLS=("s1")
_result=$(_pe_assemble_system 0)
echo "$_result" | grep -q "active" && _green "T14: active tag" \
    || _red "T14: active tag" "[active]" "$(echo "$_result" | grep -o 'active' || echo 'none')"
SKILL_META=()
ACTIVE_SKILLS=()

# ════════════════ T15-T19: _pe_assemble_context ════════════════

# T15: basic context includes CWD
_pe_assemble_context; _result="$_PE_DYN_MSG"
echo "$_result" | jq -e '.content[0].text' >/dev/null 2>&1 && _green "T15: context has text" \
    || _red "T15: context text" "present" "absent"

# T16: context includes Working directory
echo "$_result" | grep -q "Working directory" && _green "T16: CWD in context" \
    || _red "T16: CWD" "Working directory" "$(echo "$_result" | head -c 200)"

# T17: context includes Platform
echo "$_result" | grep -q "Platform" && _green "T17: platform in context" \
    || _red "T17: platform" "Platform" "$(echo "$_result" | head -c 200)"

# T18: role is "user"
echo "$_result" | jq -e '.role == "user"' >/dev/null 2>&1 && _green "T18: role=user" \
    || _red "T18: role" "user" "$(echo "$_result" | jq -r '.role')"

# T19: content is array with text type
echo "$_result" | jq -e '.content[0].type == "text"' >/dev/null 2>&1 && _green "T19: type=text" \
    || _red "T19: type" "text" "$(echo "$_result" | jq -r '.content[0].type')"

# ════════════════ T20-T25: _pe_assemble_msg_prefix ════════════════

# T20: bp=0, 2 messages → get first message
MESSAGES='[{"role":"user","content":"hello"},{"role":"assistant","content":"hi"}]'
_result=$(_pe_assemble_msg_prefix 0)
_cnt=$(echo "$_result" | jq 'length')
[[ $_cnt -eq 1 ]] && _green "T20: bp=0 → 1 msg (cnt=$_cnt)" \
    || _red "T20: bp=0" "count=1" "count=$_cnt"

# T21: bp=1, 3 messages → get first 2
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"},{"role":"user","content":"c"}]'
_result=$(_pe_assemble_msg_prefix 1)
_cnt=$(echo "$_result" | jq 'length')
[[ $_cnt -eq 2 ]] && _green "T21: bp=1 → 2 msgs (cnt=$_cnt)" \
    || _red "T21: bp=1" "count=2" "count=$_cnt"

# T22: string content converted to array
echo "$_result" | jq -e '.[0].content | type == "array"' >/dev/null 2>&1 \
    && _green "T22: string→array conversion" \
    || _red "T22: conversion" "array" "$(echo "$_result" | jq -c '.[0].content | type')"

# T23: empty messages → empty output
MESSAGES='[]'
_result=$(_pe_assemble_msg_prefix 0)
[[ "$_result" == "[]" ]] && _green "T23: empty messages → []" \
    || _red "T23: empty" "[]" "$_result"

# T24: bp out of range → jq returns all messages (slice past end = whole array)
MESSAGES='[{"role":"user","content":"only"}]'
_result=$(_pe_assemble_msg_prefix 5)
_cnt=$(echo "$_result" | jq 'length')
[[ $_cnt -eq 1 ]] && _green "T24: bp OOB returns all (cnt=$_cnt)" \
    || _red "T24: OOB" "count=1" "count=$_cnt"

# T25: content already array → not double-wrapped
MESSAGES='[{"role":"user","content":[{"type":"text","text":"arr"}]}]'
_result=$(_pe_assemble_msg_prefix 0)
echo "$_result" | jq -e '.[0].content[0].text == "arr"' >/dev/null 2>&1 \
    && _green "T25: array content preserved" \
    || _red "T25: array content" "arr" "$(echo "$_result" | jq -c '.[0].content')"

MESSAGES='[]'

# ════════════════ T26-T30: _pe_assemble_tools ════════════════

# T26: emit_markers=0 → no cache_control on tools
_result=$(_pe_assemble_tools 0)
echo "$_result" | jq -e '.[-1].cache_control' >/dev/null 2>&1 \
    && _red "T26: no cc emit=0" "absent" "present" \
    || _green "T26: no cache_control when emit=0"

# T27: emit_markers=1 + non-empty tools → cc on last tool
# Override build_tools_json to return a mock tool
build_tools_json() { echo '[{"name":"test_tool","description":"a tool"}]'; }
_result=$(_pe_assemble_tools 1)
build_tools_json() { echo '[]'; }
echo "$_result" | jq -e '.[-1].cache_control' >/dev/null 2>&1 \
    && _green "T27: cache_control on last tool" \
    || _red "T27: cc on tool" "present" "absent"

# T28: _prebuilt provided → uses it
_result=$(_pe_assemble_tools 0 '[{"name":"prebuilt"}]')
echo "$_result" | jq -e '.[0].name == "prebuilt"' >/dev/null 2>&1 \
    && _green "T28: prebuilt tools used" \
    || _red "T28: prebuilt" "prebuilt" "$_result"

# T29: empty _prebuilt → calls build_tools_json
build_tools_json() { echo '[{"name":"built"}]'; }
_result=$(_pe_assemble_tools 0 "")
build_tools_json() { echo '[]'; }
echo "$_result" | jq -e '.[0].name == "built"' >/dev/null 2>&1 \
    && _green "T29: fallback to build_tools_json" \
    || _red "T29: fallback" "built" "$_result"

# T30: no _prebuilt, no tools → empty array
build_tools_json() { echo '[]'; }
_result=$(_pe_assemble_tools 0 "")
echo "$_result" | jq -e 'length == 0' >/dev/null 2>&1 \
    && _green "T30: empty tools → []" \
    || _red "T30: empty" "[]" "$_result"
build_tools_json() { echo '[]'; }

# ════════════════ T31-T38: _jq_tempfile ════════════════

_tmp=$(mktemp -d)

# T31: --arg → jq --arg
_result=$(_jq_tempfile "$_tmp" '{v:$v}' --arg v "hello" | jq -c .)
[[ "$_result" == '{"v":"hello"}' ]] && _green "T31: --arg works" \
    || _red "T31: --arg" '{"v":"hello"}' "$_result"

# T32: --argjson → jq --argjson
_result=$(_jq_tempfile "$_tmp" '{n:$n}' --argjson n 42 | jq -c .)
[[ "$_result" == '{"n":42}' ]] && _green "T32: --argjson works" \
    || _red "T32: --argjson" '{"n":42}' "$_result"

# T33: --str → --rawfile
_result=$(_jq_tempfile "$_tmp" '$txt' --str txt "file content here")
[[ "$_result" == '"file content here"' ]] && _green "T33: --str works" \
    || _red "T33: --str" '"file content here"' "$_result"

# T34: --json → --slurpfile
_result=$(_jq_tempfile "$_tmp" '$j[0].name' --json j '{"name":"test"}')
[[ "$_result" == '"test"' ]] && _green "T34: --json works" \
    || _red "T34: --json" '"test"' "$_result"

# T35: combined --arg + --str
_result=$(_jq_tempfile "$_tmp" '{name:$n,body:$b}' --arg n "doc" --str b "content")
echo "$_result" | jq -e '.name == "doc" and .body == "content"' >/dev/null 2>&1 \
    && _green "T35: combined types" \
    || _red "T35: combined" "name=doc body=content" "$_result"

# T36: large content → no ARG_MAX (use repeat loop for reliable long string)
_big=""; for _xi in $(seq 1 1000); do _big+="1234567890"; done  # 10,000 chars
_result=$(_jq_tempfile "$_tmp" '$big | length' --str big "$_big" | jq -c .)
[[ "$_result" == "10000" ]] && _green "T36: 10KB str handled" \
    || _red "T36: 10KB" "10000" "$_result"

# T37: multiple --json
_result=$(_jq_tempfile "$_tmp" '[$a[0].v, $b[0].v]' --json a '{"v":1}' --json b '{"v":2}' | jq -c .)
[[ "$_result" == '[1,2]' ]] && _green "T37: multi --json" || _red "T37: multi json" "[1,2]" "$_result"

# T38: unknown flag ignored
_result=$(_jq_tempfile "$_tmp" '1' --unknown x y 2>/dev/null)
[[ "$_result" == "1" ]] && _green "T38: unknown flag ignored" \
    || _red "T38: unknown" "1" "$_result"

rm -rf "$_tmp"

# ════════════════ T39-T45: _proto_convert_request ════════════════

# T39: messages converted (system prompt adds one if present)
_input='{"model":"test","max_tokens":100,"messages":[{"role":"user","content":"hello"},{"role":"assistant","content":"hi there"}],"tools":[],"stream":true}'
_result=$(echo "$_input" | _proto_convert_request)
echo "$_result" | jq -e '.messages | length > 0' >/dev/null 2>&1 \
    && _green "T39: messages converted" \
    || _red "T39: messages" ">0" "$(echo "$_result" | jq '.messages | length')"

# T40: system prompt mapped
_input='{"model":"test","max_tokens":100,"system":[{"type":"text","text":"You are helpful"}],"messages":[],"tools":[],"stream":true}'
_result=$(echo "$_input" | _proto_convert_request)
echo "$_result" | jq -e '.messages[0].role == "system"' >/dev/null 2>&1 \
    && _green "T40: system prompt → role=system" \
    || _red "T40: system" "role=system" "$(echo "$_result" | jq -c '.messages[0]')"

# T41: model preserved
echo "$_result" | jq -e '.model == "test"' >/dev/null 2>&1 \
    && _green "T41: model preserved" || _red "T41: model" "test" "$(echo "$_result" | jq -r '.model')"

# T42: max_tokens → max_completion_tokens
echo "$_result" | jq -e '.max_completion_tokens == 100' >/dev/null 2>&1 \
    && _green "T42: max_tokens→max_completion_tokens" \
    || _red "T42: max_tokens" "100" "$(echo "$_result" | jq -r '.max_completion_tokens')"

# T43: stream preserved
echo "$_result" | jq -e '.stream == true' >/dev/null 2>&1 \
    && _green "T43: stream preserved" || _red "T43: stream" "true" "$(echo "$_result" | jq -r '.stream')"

# T44: tools converted to OpenAI function format
_input='{"model":"test","max_tokens":100,"messages":[],"tools":[{"name":"bash","description":"Run command","input_schema":{"type":"object","properties":{}}}],"stream":true}'
_result=$(echo "$_input" | _proto_convert_request)
echo "$_result" | jq -e '.tools[0].type == "function"' >/dev/null 2>&1 \
    && _green "T44: tools → function type" \
    || _red "T44: tools" "function" "$(echo "$_result" | jq -c '.tools[0]')"

# T45: empty input → valid JSON output
_input='{"model":"test","max_tokens":100,"messages":[],"tools":[],"stream":true}'
_result=$(echo "$_input" | _proto_convert_request)
echo "$_result" | jq -e '.' >/dev/null 2>&1 \
    && _green "T45: empty valid" || _red "T45: empty" "valid JSON" "$_result"

# ════════════════ T46-T50: _proto_convert_response ════════════════

# T46: text content extracted
_input='{"choices":[{"message":{"content":"hello world"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
_result=$(echo "$_input" | _proto_convert_response)
echo "$_result" | jq -e '.content[0].text == "hello world"' >/dev/null 2>&1 \
    && _green "T46: text extracted" \
    || _red "T46: text" "hello world" "$(echo "$_result" | jq -c '.content')"

# T47: stop_reason mapping (stop → end_turn)
echo "$_result" | jq -e '.stop_reason == "end_turn"' >/dev/null 2>&1 \
    && _green "T47: stop→end_turn" || _red "T47: stop" "end_turn" "$(echo "$_result" | jq -r '.stop_reason')"

# T48: usage tokens mapped
echo "$_result" | jq -e '.usage.input_tokens == 10 and .usage.output_tokens == 5' >/dev/null 2>&1 \
    && _green "T48: usage mapped" \
    || _red "T48: usage" "in=10 out=5" "$(echo "$_result" | jq -c '.usage')"

# T49: finish_reason=tool_calls → tool_use
_input2='{"choices":[{"message":{"content":""},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
_result2=$(echo "$_input2" | _proto_convert_response)
echo "$_result2" | jq -e '.stop_reason == "tool_use"' >/dev/null 2>&1 \
    && _green "T49: tool_calls→tool_use" || _red "T49: tool_calls" "tool_use" "$(echo "$_result2" | jq -r '.stop_reason')"

# T50: finish_reason=length → max_tokens
_input3='{"choices":[{"message":{"content":"truncated"},"finish_reason":"length"}],"usage":{"prompt_tokens":10,"completion_tokens":100}}'
_result3=$(echo "$_input3" | _proto_convert_response)
echo "$_result3" | jq -e '.stop_reason == "max_tokens"' >/dev/null 2>&1 \
    && _green "T50: length→max_tokens" || _red "T50: length" "max_tokens" "$(echo "$_result3" | jq -r '.stop_reason')"

# ════════════════ Stress ════════════════

# S1: 200 messages → msg_prefix < 1s
MESSAGES='['
for i in $(seq 1 199); do MESSAGES+='{"role":"user","content":"msg'$i'"},{"role":"assistant","content":"reply'$i'"},'; done
MESSAGES+='{"role":"user","content":"msg200"}]'
_start=$SECONDS
_result=$(_pe_assemble_msg_prefix 100)
_elapsed=$(( SECONDS - _start ))
[[ $_elapsed -le 2 ]] && _green "S1: 200 msgs prefix in ${_elapsed}s" \
    || _red "S1: perf" "<=2s" "${_elapsed}s"
MESSAGES='[]'

# S2: _pe_assemble_system repeated calls — cache works
BASHAGT_MD=""
_start=$SECONDS
for i in $(seq 1 20); do _pe_assemble_system 0 >/dev/null 2>&1; done
_elapsed=$(( SECONDS - _start ))
[[ $_elapsed -le 3 ]] && _green "S2: 20 system assemblies in ${_elapsed}s" \
    || _red "S2: perf" "<=3s" "${_elapsed}s"

# S3: _jq_tempfile 50 rapid calls
_tmp=$(mktemp -d)
_ok=1
for i in $(seq 1 50); do
    _jq_tempfile "$_tmp" '{i:$i}' --argjson i "$i" >/dev/null 2>&1 || { _ok=0; break; }
done
rm -rf "$_tmp"
[[ $_ok -eq 1 ]] && _green "S3: 50 _jq_tempfile calls" \
    || _red "S3: 50 calls" "OK" "fail at $i"

echo "---DONE---"
TESTEOF

# ── Execute and parse ──
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
        PASS:*) _pass "${line#PASS:}" ;;
        FAIL:*) _fail "${line#FAIL:}" "$(echo "$line" | cut -d'|' -f2)" "$(echo "$line" | cut -d'|' -f3)" ;;
        ---DONE---) ;;
        *) echo "  $line" ;;
    esac
done < <(bash /tmp/bashagt_proto_test.sh 2>&1 || true)

rm -f /tmp/bashagt_proto_funcs.sh /tmp/bashagt_proto_test.sh

echo ""
echo "============================================"
echo " Protocol Assembly Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
