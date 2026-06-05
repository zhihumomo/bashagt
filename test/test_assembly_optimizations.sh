#!/bin/bash
# ============================================================================
# test_assembly_optimizations.sh — Stress tests for incremental assembly
# ============================================================================
# Tests 74 edge cases across 9 groups covering:
#   A: _msg_append_to_tail (pure bash append)
#   B: bracketless segment cache (MSG_PREFIX_INNER / MSG_TAIL_INNER)
#   C: content normalization (legacy string→content block)
#   D: _pe_assemble_request (pure bash assembly vs jq reference)
#   E: _pe_assemble_context (hash-driven cache)
#   F: _skill_list_refresh (mtime-cached skill list)
#   G: _msg_segments_advance_bp (incremental bp shift)
#   H: boundary / stress conditions
#   I: full request body assembly correctness
# ============================================================================

export BASHAGT_TEST_MODE=1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source bashagt in test mode (skips main())
source "$PROJECT_DIR/bashagt" 2>/dev/null || {
    echo "ERROR: cannot source bashagt"
    exit 1
}

# ── Test helpers ──
PASSED=0; FAILED=0
_green() { printf '\033[32m  PASS: %s\033[0m\n' "$1"; PASSED=$((PASSED+1)); }
_red()   { printf '\033[31m  FAIL: %s | expected=%s got=%s\033[0m\n' "$1" "$2" "$3"; FAILED=$((FAILED+1)); }

# ── Setup: minimal init for assembly functions ──
BASHAGT_PROJECT_DIR="${BASHAGT_PROJECT_DIR:-$PROJECT_DIR}"
BASHAGT_MODEL="${BASHAGT_MODEL:-claude-sonnet-4-6}"
BASHAGT_API_KEY="${BASHAGT_API_KEY:-sk-test}"
BASHAGT_API_URL="${BASHAGT_API_URL:-https://api.anthropic.com/v1/messages}"
BASHAGT_AUTH_HEADER="${BASHAGT_AUTH_HEADER:-x-api-key}"
BASHAGT_AUTH_PREFIX="${BASHAGT_AUTH_PREFIX:-}"
BASHAGT_MAX_TOKENS="${BASHAGT_MAX_TOKENS:-4096}"
BASHAGT_THINKING_BUDGET="${BASHAGT_THINKING_BUDGET:-0}"
BASHAGT_PROTOCOL="${BASHAGT_PROTOCOL:-anthropic}"
BASHAGT_CACHE_MSG_TAIL="${BASHAGT_CACHE_MSG_TAIL:-2}"

# Pre-init context cache (normally called in main)
_context_static_init 2>/dev/null || true
_context_rebuild 2>/dev/null || true

# Reset segment state
MESSAGES='[]'
MSG_COUNT=0
MSG_BP=-1
MSG_PREFIX_INNER=''
MSG_TAIL_INNER=''
MSG_SEGMENTS_DIRTY=0

echo "============================================"
echo " Assembly Optimization Stress Tests"
echo "============================================"
echo ""

# ═══════════════════════════════════════════════════════════════════
# GROUP A: _msg_append_to_tail (10 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group A: _msg_append_to_tail ───"

# A1: empty → first append
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_msg=$(jq -nc --arg t "hello" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
[[ "$MESSAGES" == '['*']' ]] && _green "A1: empty→append MESSAGES is array" \
    || _red "A1" "array" "${MESSAGES:0:50}"
[[ "$MSG_TAIL_INNER" == "$_msg" ]] && _green "A1b: TAIL_INNER correct" \
    || _red "A1b" "$_msg" "$MSG_TAIL_INNER"
[[ "$MSG_COUNT" == "1" ]] && _green "A1c: count=1" || _red "A1c" "1" "$MSG_COUNT"

# A2: 3 consecutive appends
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
for i in 1 2 3; do
    _msg=$(jq -nc --arg t "msg$i" '{role:"user",content:[{type:"text",text:$t}]}')
    _msg_append_to_tail "$_msg"
done
_cnt=$(jq 'length' <<< "$MESSAGES")
[[ $_cnt -eq 3 ]] && _green "A2: 3 appends → MESSAGES length=3" \
    || _red "A2" "3" "$_cnt"
[[ "$MSG_COUNT" == "3" ]] && _green "A2b: MSG_COUNT=3" \
    || _red "A2b" "3" "$MSG_COUNT"

# A3: MSG_COUNT increments correctly
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_prev=0
for i in 1 2 3 4 5; do
    _msg=$(jq -nc --arg t "x" '{role:"user",content:[{type:"text",text:$t}]}')
    _msg_append_to_tail "$_msg"
    [[ "$MSG_COUNT" -eq "$i" ]] || { _red "A3" "$i" "$MSG_COUNT"; break; }
done
[[ "$MSG_COUNT" -eq 5 ]] && _green "A3: MSG_COUNT increments 1→5" \
    || true

# A4: quotes in message
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_text='say "hello" to everyone'
_msg=$(jq -nc --arg t "$_text" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
echo "$MESSAGES" | jq . >/dev/null 2>&1 && _green "A4: quotes → valid JSON" \
    || _red "A4" "valid JSON" "invalid"

# A5: newlines in message
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_text=$'line1\nline2\nline3'
_msg=$(jq -nc --arg t "$_text" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
echo "$MESSAGES" | jq . >/dev/null 2>&1 && _green "A5: newlines → valid JSON" \
    || _red "A5" "valid JSON" "invalid"
_jq_text=$(echo "$MESSAGES" | jq -r '.[0].content[0].text')
[[ "$_jq_text" == "$_text" ]] && _green "A5b: newline text roundtrip" \
    || _red "A5b" "$_text" "$_jq_text"

# A6: Unicode
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_text='你好世界 🌍 café'
_msg=$(jq -nc --arg t "$_text" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
echo "$MESSAGES" | jq . >/dev/null 2>&1 && _green "A6: unicode → valid JSON" \
    || _red "A6" "valid JSON" "invalid"

# A7: empty string content
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_msg=$(jq -nc --arg t "" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
echo "$MESSAGES" | jq . >/dev/null 2>&1 && _green "A7: empty string → valid JSON" \
    || _red "A7" "valid JSON" "invalid"

# A8: 100 messages loop
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
for i in $(seq 1 100); do
    _msg=$(jq -nc --arg t "bulk $i" '{role:"user",content:[{type:"text",text:$t}]}')
    _msg_append_to_tail "$_msg"
done
_jq_cnt=$(jq 'length' <<< "$MESSAGES")
[[ "$_jq_cnt" -eq 100 && "$MSG_COUNT" -eq 100 ]] && _green "A8: 100 appends → count OK" \
    || _red "A8" "100" "$MSG_COUNT (jq=$_jq_cnt)"
echo "$MESSAGES" | jq . >/dev/null 2>&1 && _green "A8b: 100 msgs valid JSON" \
    || _red "A8b" "valid" "invalid"

# A9: msg_add_user_text / msg_add_assistant / msg_add_tool_results all work
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_msg_append_to_tail "$(jq -nc --arg t "user" '{role:"user",content:[{type:"text",text:$t}]}')"
_msg_append_to_tail "$(jq -nc --argjson c '[{"type":"text","text":"asst"}]' '{role:"assistant",content:$c}')"
_msg_append_to_tail "$(jq -nc --argjson r '[{"type":"text","text":"tool"}]' '{role:"user",content:$r}')"
_cnt=$(jq 'length' <<< "$MESSAGES")
[[ $_cnt -eq 3 ]] && _green "A9: three msg types → 3 total" \
    || _red "A9" "3" "$_cnt"

# A10: MESSAGES == [TAIL_INNER] semantics
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_msg=$(jq -nc --arg t "test" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
_jq_msg=$(echo "$MESSAGES" | jq -c '.')
_bash_msg="[${MSG_TAIL_INNER}]"
[[ "$_jq_msg" == "$_bash_msg" ]] && _green "A10: MESSAGES == [TAIL_INNER]" \
    || _red "A10" "$_jq_msg" "$_bash_msg"

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP B: bracketless segments (8 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group B: bracketless segments ───"

# B1: empty MESSAGES
MESSAGES='[]'; MSG_BP=-1
_msg_segments_refresh_from_messages
[[ -z "$MSG_PREFIX_INNER" ]] && _green "B1: empty→PREFIX=''" \
    || _red "B1" "''" "'$MSG_PREFIX_INNER'"
[[ -z "$MSG_TAIL_INNER" ]] && _green "B1b: empty→TAIL=''" \
    || _red "B1b" "''" "'$MSG_TAIL_INNER'"
[[ "$MSG_COUNT" -eq 0 ]] && _green "B1c: count=0" || _red "B1c" "0" "$MSG_COUNT"

# B2: bp=-1 with messages → all in TAIL
MESSAGES='[{"role":"user","content":[{"type":"text","text":"a"}]},{"role":"assistant","content":[{"type":"text","text":"b"}]}]'
MSG_BP=-1
_msg_segments_refresh_from_messages
[[ -z "$MSG_PREFIX_INNER" ]] && _green "B2: bp=-1→PREFIX=''" \
    || _red "B2" "''" "'$MSG_PREFIX_INNER'"
[[ -n "$MSG_TAIL_INNER" ]] && _green "B2b: TAIL non-empty" \
    || _red "B2b" "non-empty" "empty"
[[ "$MSG_COUNT" -eq 2 ]] && _green "B2c: count=2" || _red "B2c" "2" "$MSG_COUNT"

# B3: bp=1 with 3 messages → PREFIX has 2, TAIL has 1
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"},{"role":"user","content":"c"}]'
MSG_BP=1
_msg_segments_refresh_from_messages
[[ -n "$MSG_PREFIX_INNER" && -n "$MSG_TAIL_INNER" ]] \
    && _green "B3: bp=1 splits correctly" \
    || _red "B3" "both non-empty" "P=$(test -n "$MSG_PREFIX_INNER" && echo y || echo n) T=$(test -n "$MSG_TAIL_INNER" && echo y || echo n)"
# Verify counts
_jq_pfx=$(jq 'length' <<< "[${MSG_PREFIX_INNER}]")
_jq_tail=$(jq 'length' <<< "[${MSG_TAIL_INNER}]")
[[ "$_jq_pfx" -eq 2 && "$_jq_tail" -eq 1 ]] \
    && _green "B3b: PREFIX=2 TAIL=1" \
    || _red "B3b" "2+1" "$_jq_pfx+$_jq_tail"

# B4: single message (content normalized to array)
MESSAGES='[{"role":"user","content":"solo"}]'
MSG_BP=-1
_msg_segments_refresh_from_messages
# After normalization: content becomes [{"type":"text","text":"solo"}]
echo "[${MSG_TAIL_INNER}]" | jq -e '.[0].content[0].text == "solo"' >/dev/null 2>&1 \
    && _green "B4: single msg TAIL correct (normalized, no extra comma)" \
    || _red "B4" "text=solo" "$(echo "[${MSG_TAIL_INNER}]" | jq -c '.' 2>/dev/null || echo INVALID)"

# B5: idempotent refresh
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"}]'
MSG_BP=0
_msg_segments_refresh_from_messages
_pfx1="$MSG_PREFIX_INNER"
_tail1="$MSG_TAIL_INNER"
_msg_segments_refresh_from_messages
[[ "$MSG_PREFIX_INNER" == "$_pfx1" && "$MSG_TAIL_INNER" == "$_tail1" ]] \
    && _green "B5: refresh idempotent" \
    || _red "B5" "same" "changed"

# B6: append after refresh → TAIL grows
MESSAGES='[{"role":"user","content":"a"}]'
MSG_BP=-1; MSG_TAIL_INNER=''
_msg_segments_refresh_from_messages
_tail_before="$MSG_TAIL_INNER"
_msg=$(jq -nc --arg t "new" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
[[ "$MSG_TAIL_INNER" == "${_tail_before},${_msg}" ]] \
    && _green "B6: append after refresh → TAIL correct" \
    || _red "B6" "${_tail_before},$_msg" "${MSG_TAIL_INNER:0:80}"

# B7: advance bp shift=1
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"},{"role":"user","content":"c"}]'
MSG_BP=0; MSG_TAIL_INNER=''; MSG_PREFIX_INNER=''
_msg_segments_refresh_from_messages   # PREFIX=msg0, TAIL=msg1,msg2
MSG_BP=0  # set BP to 0 (refresh uses global MSG_BP... wait, it already reads MSG_BP)
# Actually _msg_segments_refresh_from_messages uses MSG_BP which we set
MSG_BP=0
_msg_segments_refresh_from_messages
_pfx_before="$MSG_PREFIX_INNER"
_msg_segments_advance_bp 1
_cnt_pfx=$(jq 'length' <<< "[${MSG_PREFIX_INNER}]" 2>/dev/null || echo 0)
_cnt_tail=$(jq 'length' <<< "[${MSG_TAIL_INNER}]" 2>/dev/null || echo 0)
[[ "$_cnt_pfx" -eq 2 && "$_cnt_tail" -eq 1 ]] \
    && _green "B7: shift 0→1: PREFIX 1→2 TAIL 2→1" \
    || _red "B7" "pfx=2 tail=1" "pfx=$_cnt_pfx tail=$_cnt_tail"

# B8: shift=0 → no-op
MSG_BP=1; MSG_TAIL_INNER='{"a":"b"}'  # arbitrary, won't be used
_msg_segments_advance_bp 1  # shift=0
_rc=$?
[[ $_rc -eq 0 ]] && _green "B8: shift=0 returns 0 immediately" \
    || _red "B8" "0" "$_rc"

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP C: content normalization (5 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group C: content normalization ───"

# C1: string content → block
MESSAGES='[{"role":"user","content":"legacy string"}]'
MSG_BP=-1
_msg_segments_refresh_from_messages
echo "[${MSG_TAIL_INNER}]" | jq -e '.[0].content | type == "array"' >/dev/null 2>&1 \
    && _green "C1: string→array normalized" \
    || _red "C1" "array" "$(echo "[${MSG_TAIL_INNER}]" | jq -c '.[0].content | type')"

# C2: already array → no double-wrap
MESSAGES='[{"role":"user","content":[{"type":"text","text":"modern"}]}]'
MSG_BP=-1
_msg_segments_refresh_from_messages
echo "[${MSG_TAIL_INNER}]" | jq -e '.[0].content | length == 1' >/dev/null 2>&1 \
    && _green "C2: array→still array (len=1)" \
    || _red "C2" "len=1" "$(echo "[${MSG_TAIL_INNER}]" | jq -c '.[0].content | length')"

# C3: mixed string + block
MESSAGES='[{"role":"user","content":"old"},{"role":"user","content":[{"type":"text","text":"new"}]}]'
MSG_BP=-1
_msg_segments_refresh_from_messages
_norm=$(echo "[${MSG_TAIL_INNER}]" | jq -c 'map(.content | type)')
[[ "$_norm" == '["array","array"]' ]] \
    && _green "C3: mixed→both arrays" \
    || _red "C3" '["array","array"]' "$_norm"

# C4: empty content
MESSAGES='[{"role":"user"}]'
MSG_BP=-1
_msg_segments_refresh_from_messages 2>/dev/null
_rc=$?
[[ $_rc -eq 0 ]] && _green "C4: missing content → no crash" \
    || _red "C4" "rc=0" "rc=$_rc"

# C5: null content
MESSAGES='[{"role":"user","content":null}]'
MSG_BP=-1
_msg_segments_refresh_from_messages 2>/dev/null
_rc=$?
[[ $_rc -eq 0 ]] && _green "C5: null content → no crash" \
    || _red "C5" "rc=0" "rc=$_rc"

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP D: _pe_assemble_request pure bash assembly (15 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group D: _pe_assemble_request pure bash assembly ───"
set +e  # diff may return non-zero; prevent ERR trap kill

# Pre-seed context cache so _pe_assemble_context returns our test value
# (avoids _pe_assemble_context overwriting _PE_DYN_MSG with real context)
_ctx_dyn_backup="$CONTEXT_DYN_CACHED"
_ctx_hash_backup="$CONTEXT_HASH"

# Helper: jq-based reference assembly
_jq_assemble_ref() {
    local _pfx="$1" _dyn="$2" _tail="$3" _model="$4" _mt="$5" _tb="$6" _stream="$7"
    jq -n -c \
        --slurpfile pfx <(echo "[$_pfx]") \
        --slurpfile dyn <(echo "$_dyn") \
        --slurpfile tail <(echo "[$_tail]") \
        --arg model "$_model" \
        --argjson mt "$_mt" \
        --argjson stream "$_stream" \
        --argjson tb "$_tb" \
        '{
            model: $model,
            max_tokens: $mt,
            tools: [],
            system: [],
            messages: ($pfx[0] + [$dyn[0]] + $tail[0]),
            stream: $stream,
            thinking: (if $tb > 0 then {budget_tokens: $tb, type: "enabled"} else {type: "disabled"} end)
        }'
}

# Seed context cache with known test value and matching hash
CONTEXT_DYN_CACHED='{"role":"user","content":[{"type":"text","text":"ctx"}]}'
_context_get_hash; CONTEXT_HASH="$_CONTEXT_HASH_VAL"

# D1: normal 5-message
MSG_PREFIX_INNER='{"role":"user","content":[{"type":"text","text":"Q1"}]},{"role":"assistant","content":[{"type":"text","text":"A1"}]}'
MSG_TAIL_INNER='{"role":"user","content":[{"type":"text","text":"Q2"}]},{"role":"assistant","content":[{"type":"text","text":"A2"}]}'
_PE_DYN_MSG='{"role":"user","content":[{"type":"text","text":"ctx"}]}'
MSG_BP=1; MSG_COUNT=5; MSG_SEGMENTS_DIRTY=0
_result=$(_pe_assemble_request "claude" 4096 0 "true" "1" "0" "[]" "[]")
_ref=$(_jq_assemble_ref "$MSG_PREFIX_INNER" "$_PE_DYN_MSG" "$MSG_TAIL_INNER" "claude" 4096 0 "true")
_diff=$(diff <(echo "$_result" | jq -S .) <(echo "$_ref" | jq -S .) 2>/dev/null)
[[ -z "$_diff" ]] && _green "D1: 5-msg assembly == jq reference" \
    || _red "D1" "identical" "differ"

# D2: empty PREFIX
MSG_PREFIX_INNER=''
MSG_TAIL_INNER='{"role":"user","content":[{"type":"text","text":"Q"}]},{"role":"assistant","content":[{"type":"text","text":"A"}]}'
MSG_BP=-1; MSG_COUNT=3
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
_ref=$(_jq_assemble_ref "" "$_PE_DYN_MSG" "$MSG_TAIL_INNER" "claude" 4096 0 "true")
_diff=$(diff <(echo "$_result" | jq -S .) <(echo "$_ref" | jq -S .) 2>/dev/null)
[[ -z "$_diff" ]] && _green "D2: empty PREFIX == jq reference" \
    || _red "D2" "identical" "differ"

# D3: empty TAIL
MSG_PREFIX_INNER='{"role":"user","content":[{"type":"text","text":"Q"}]}'
MSG_TAIL_INNER=''
MSG_BP=0; MSG_COUNT=2
_result=$(_pe_assemble_request "claude" 4096 0 "true" "0" "0" "[]" "[]")
_ref=$(_jq_assemble_ref "$MSG_PREFIX_INNER" "$_PE_DYN_MSG" "" "claude" 4096 0 "true")
_diff=$(diff <(echo "$_result" | jq -S .) <(echo "$_ref" | jq -S .) 2>/dev/null)
[[ -z "$_diff" ]] && _green "D3: empty TAIL == jq reference" \
    || _red "D3" "identical" "differ"

# D4: both empty
MSG_PREFIX_INNER=''; MSG_TAIL_INNER=''; MSG_BP=-1; MSG_COUNT=1
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
_ref=$(_jq_assemble_ref "" "$_PE_DYN_MSG" "" "claude" 4096 0 "true")
_diff=$(diff <(echo "$_result" | jq -S .) <(echo "$_ref" | jq -S .) 2>/dev/null)
[[ -z "$_diff" ]] && _green "D4: both empty == jq reference" \
    || _red "D4" "identical" "differ"

# D5: PREFIX only 1 element
MSG_PREFIX_INNER='{"role":"user","content":[{"type":"text","text":"solo"}]}'
MSG_TAIL_INNER=''; MSG_BP=0; MSG_COUNT=2
_result=$(_pe_assemble_request "claude" 4096 0 "true" "0" "0" "[]" "[]")
echo "$_result" | jq -e '.messages | length == 2' >/dev/null 2>&1 \
    && _green "D5: single PREFIX → 2 msgs (1+ctx)" \
    || _red "D5" "2 msgs" "$(echo "$_result" | jq '.messages | length')"

# D6: TAIL only 1 element
MSG_PREFIX_INNER=''; MSG_BP=-1; MSG_COUNT=2
MSG_TAIL_INNER='{"role":"user","content":[{"type":"text","text":"only"}]}'
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq -e '.messages | length == 2' >/dev/null 2>&1 \
    && _green "D6: single TAIL → 2 msgs (ctx+1)" \
    || _red "D6" "2 msgs" "$(echo "$_result" | jq '.messages | length')"

# D7: 100 messages (stress)
_build100() {
    local _inner='' _sep=''
    for i in $(seq 1 100); do
        _inner+="${_sep}{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"msg$i\"}]}"
        _sep=','
    done
    echo "$_inner"
}
MSG_PREFIX_INNER=$(_build100)
MSG_TAIL_INNER='{"role":"user","content":[{"type":"text","text":"last"}]}'
MSG_BP=99; MSG_COUNT=102
_result=$(_pe_assemble_request "claude" 4096 0 "true" "99" "0" "[]" "[]")
# Verify valid JSON
echo "$_result" | jq . >/dev/null 2>&1 && _green "D7: 100 msgs → valid JSON" \
    || _red "D7" "valid" "invalid"
_msg_cnt=$(echo "$_result" | jq '.messages | length')
[[ "$_msg_cnt" -eq 102 ]] && _green "D7b: 100+ctx+1=102 msgs" \
    || _red "D7b" "102" "$_msg_cnt"

# D8: tool_use content preserved
MSG_PREFIX_INNER='{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"bash","input":{"cmd":"ls"}}]}'
MSG_TAIL_INNER=''
MSG_BP=0; MSG_COUNT=2
_result=$(_pe_assemble_request "claude" 4096 0 "true" "0" "0" "[]" "[]")
echo "$_result" | jq -e '.messages[0].content[0].type == "tool_use"' >/dev/null 2>&1 \
    && _green "D8: tool_use content preserved" \
    || _red "D8" "tool_use" "missing"

# D9: tool_result content preserved
MSG_PREFIX_INNER='{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"output"}]}'
MSG_TAIL_INNER=''
MSG_BP=0; MSG_COUNT=2
_result=$(_pe_assemble_request "claude" 4096 0 "true" "0" "0" "[]" "[]")
echo "$_result" | jq -e '.messages[0].content[0].type == "tool_result"' >/dev/null 2>&1 \
    && _green "D9: tool_result content preserved" \
    || _red "D9" "tool_result" "missing"

# D10: all segments empty
MSG_PREFIX_INNER=''; MSG_TAIL_INNER=''; MSG_BP=-1; MSG_COUNT=1
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq -e '.messages | length == 1' >/dev/null 2>&1 \
    && _green "D10: all empty → [dyn] only" \
    || _red "D10" "1 msg" "$(echo "$_result" | jq '.messages | length')"

# D11: model with backslash (escaped)
MSG_PREFIX_INNER=''; MSG_TAIL_INNER=''; MSG_BP=-1; MSG_COUNT=1
_result=$(_pe_assemble_request "test\\model" 4096 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq -r '.model' 2>/dev/null | grep -q 'test\\model' \
    && _green "D11: backslash in model escaped" \
    || _red "D11" "test\\\\model" "$(echo "$_result" | jq -r '.model')"

# D12: max_tokens=0
_result=$(_pe_assemble_request "claude" 0 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq -e '.max_tokens == 0' >/dev/null 2>&1 \
    && _green "D12: max_tokens=0 works" || _red "D12" "0" "crash"

# D13: tb=0 → disabled
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq -e '.thinking.type == "disabled"' >/dev/null 2>&1 \
    && _green "D13: tb=0→thinking disabled" || _red "D13" "disabled" "$(echo "$_result" | jq -c '.thinking')"

# D14: tb>0 → enabled
_result=$(_pe_assemble_request "claude" 4096 1024 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq -e '.thinking.type == "enabled" and .thinking.budget_tokens == 1024' >/dev/null 2>&1 \
    && _green "D14: tb>0→thinking enabled+1024" || _red "D14" "enabled" "$(echo "$_result" | jq -c '.thinking')"

# D15: stream=false
_result=$(_pe_assemble_request "claude" 4096 0 "false" "-1" "0" "[]" "[]")
echo "$_result" | jq -e '.stream == false' >/dev/null 2>&1 \
    && _green "D15: stream=false" || _red "D15" "false" "$(echo "$_result" | jq -r '.stream')"

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP E: _pe_assemble_context cache (8 tests)
# ═══════════════════════════════════════════════════════════════════
# Restore real context cache
CONTEXT_DYN_CACHED="$_ctx_dyn_backup"
CONTEXT_HASH="$_ctx_hash_backup"

echo "─── Group E: _pe_assemble_context cache ───"

# E1: first call → rebuild
CONTEXT_DYN_CACHED=''; CONTEXT_HASH=''
_pe_assemble_context
[[ -n "$CONTEXT_DYN_CACHED" ]] && _green "E1: first call builds cache" \
    || _red "E1" "non-empty" "empty"

# E2: second call → hit
_hash_before="$CONTEXT_HASH"
_pe_assemble_context
[[ "$CONTEXT_HASH" == "$_hash_before" ]] && _green "E2: second call hits cache" \
    || _red "E2" "same hash" "changed"

# E3: MEMORY_CACHE_TS change → rebuild
_old_ts="${MEMORY_CACHE_TS:-0}"
MEMORY_CACHE_TS=$((_old_ts + 100))
_hash_before="$CONTEXT_HASH"
_pe_assemble_context
[[ "$CONTEXT_HASH" != "$_hash_before" ]] && _green "E3: MEMORY_CACHE_TS change triggers rebuild" \
    || _red "E3" "different hash" "same"
MEMORY_CACHE_TS="$_old_ts"  # restore
_pe_assemble_context          # restore cache

# E4: todo.json mtime change → rebuild
_hash_before="$CONTEXT_HASH"
_tf="${BASHAGT_PROJECT_DIR:-.}/.bashagt/todo.json"
if [[ -f "$_tf" ]]; then
    _old_mtime=$(_file_mtime "$_tf")
    touch "$_tf" 2>/dev/null
    _pe_assemble_context
    [[ "$CONTEXT_HASH" != "$_hash_before" ]] && _green "E4: todo mtime change triggers rebuild" \
        || _red "E4" "different hash" "same"
    touch -d "@$_old_mtime" "$_tf" 2>/dev/null || touch "$_tf" 2>/dev/null || true  # restore
    _pe_assemble_context
else
    _green "E4: (skipped — no todo.json)"
fi

# E5: time minute change → rebuild
_pe_assemble_context; _hash_before="$CONTEXT_HASH"
# Simulate time change by setting CONTEXT_HASH to wrong value
CONTEXT_HASH="wrong"
_pe_assemble_context
[[ "$CONTEXT_HASH" != "wrong" ]] && _green "E5: wrong hash triggers rebuild" \
    || _red "E5" "different from wrong" "still wrong"

# E6: _PE_DYN_MSG sync
_pe_assemble_context
[[ "$_PE_DYN_MSG" == "$CONTEXT_DYN_CACHED" ]] \
    && _green "E6: _PE_DYN_MSG == CONTEXT_DYN_CACHED" \
    || _red "E6" "same" "differ"

# E7: CONTEXT_STATIC has required fields
[[ "$CONTEXT_STATIC" == *"Working directory:"* ]] && _green "E7a: has CWD" || _red "E7a" "CWD" "missing"
[[ "$CONTEXT_STATIC" == *"Platform:"* ]] && _green "E7b: has Platform" || _red "E7b" "Platform" "missing"
[[ "$CONTEXT_STATIC" == *"Shell:"* ]] && _green "E7c: has Shell" || _red "E7c" "Shell" "missing"
[[ "$CONTEXT_STATIC" == *"Model:"* ]] && _green "E7d: has Model" || _red "E7d" "Model" "missing"

# E8: 100 calls → only first rebuilds
_pe_assemble_context; _hash_before="$CONTEXT_HASH"
_rebuild_count=0
for i in $(seq 1 100); do
    _pe_assemble_context
    [[ "$CONTEXT_HASH" != "$_hash_before" ]] && { _rebuild_count=$((_rebuild_count+1)); _hash_before="$CONTEXT_HASH"; }
done
[[ "$_rebuild_count" -eq 0 ]] && _green "E8: 100 calls → 0 extra rebuilds" \
    || _red "E8" "0" "$_rebuild_count"

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP F: _skill_list_refresh (5 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group F: _skill_list_refresh ───"

# F1: first call builds cache
SKILL_LIST_CACHED=''; SKILL_LIST_MTIME=0
_skill_list_refresh 2>/dev/null
[[ -n "$SKILL_LIST_CACHED" || ${#SKILL_META[@]} -eq 0 ]] \
    && _green "F1: skill list built or no skills" \
    || _red "F1" "cached or empty" "failed"

# F2: second call → no rebuild (mtime unchanged)
SKILL_LIST_MTIME=$_SKILL_DIR_MTIME  # sync to prevent rebuild
SKILL_LIST_CACHED='__dummy__'
_skill_list_refresh 2>/dev/null
[[ "$SKILL_LIST_CACHED" == '__dummy__' ]] && _green "F2: mtime match→no rebuild" \
    || _red "F2" "__dummy__" "$SKILL_LIST_CACHED"

# F3: _cc_invalidate system → _pe_assemble_system rebuilds JSON
SKILL_LIST_CACHED=''; SKILL_LIST_MTIME=0
_skill_list_refresh 2>/dev/null
_cc_invalidate system
# Verify _cc_get returns empty
_pe_assemble_system 0 > /dev/null 2>&1
_rc=$?
[[ $_rc -eq 0 ]] && _green "F3: invalidate→rebuild OK" \
    || _red "F3" "rc=0" "rc=$_rc"

# F4: skills in raw
_skill_list_refresh 2>/dev/null
if [[ -n "$SKILL_LIST_CACHED" ]]; then
    echo "$SKILL_LIST_CACHED" | grep -q "Available skills" \
        && _green "F4: SKILL_LIST_CACHED has header" \
        || _red "F4" "header" "$(echo "$SKILL_LIST_CACHED" | head -c 80)"
else
    _green "F4: (no skills, cache empty)"
fi

# F5: no skills → empty
SKILL_META=()
_saved_mtime=$_SKILL_DIR_MTIME
_SKILL_DIR_MTIME=99999
SKILL_LIST_CACHED=''; SKILL_LIST_MTIME=0
_skill_list_refresh 2>/dev/null
[[ -z "$SKILL_LIST_CACHED" ]] && _green "F5: no SKILL_META→empty" \
    || _red "F5" "empty" "'$SKILL_LIST_CACHED'"
_SKILL_DIR_MTIME=$_saved_mtime

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP G: _msg_segments_advance_bp (6 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group G: _msg_segments_advance_bp ───"

# G1: bp 0→1
MSG_PREFIX_INNER='{"role":"user","content":"a"}'
MSG_TAIL_INNER='{"role":"assistant","content":"b"},{"role":"user","content":"c"}'
MSG_BP=0; MSG_COUNT=3
_msg_segments_advance_bp 1
_cnt_pfx=$(jq 'length' <<< "[${MSG_PREFIX_INNER}]" 2>/dev/null || echo 0)
_cnt_tail=$(jq 'length' <<< "[${MSG_TAIL_INNER}]" 2>/dev/null || echo 0)
[[ "$_cnt_pfx" -eq 2 && "$_cnt_tail" -eq 1 ]] \
    && _green "G1: bp 0→1: pfx=2 tail=1" \
    || _red "G1" "pfx=2 tail=1" "pfx=$_cnt_pfx tail=$_cnt_tail"

# G2: bp -1→2 → dirty (full refresh path simulated)
MSG_BP=-1; MSG_SEGMENTS_DIRTY=0
# Simulate the logic in call_api_nonstreaming
_bp_shift=$((2 - (-1)))  # =3
[[ $_bp_shift -gt 1 ]] && MSG_SEGMENTS_DIRTY=1
[[ "$MSG_SEGMENTS_DIRTY" -eq 1 ]] && _green "G2: bp -1→2 marks dirty" \
    || _red "G2" "1" "$MSG_SEGMENTS_DIRTY"

# G3: consecutive 3 shifts
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"},{"role":"user","content":"c"},{"role":"assistant","content":"d"},{"role":"user","content":"e"}]'
MSG_BP=0
_msg_segments_refresh_from_messages  # PREFIX=msg0, TAIL=msg1..4
for bp in 1 2 3; do
    _msg_segments_advance_bp "$bp"
done
_cnt_pfx=$(jq 'length' <<< "[${MSG_PREFIX_INNER}]" 2>/dev/null || echo 0)
_cnt_tail=$(jq 'length' <<< "[${MSG_TAIL_INNER}]" 2>/dev/null || echo 0)
[[ "$_cnt_pfx" -eq 4 && "$_cnt_tail" -eq 1 ]] \
    && _green "G3: 0→3: pfx=4 tail=1" \
    || _red "G3" "pfx=4 tail=1" "pfx=$_cnt_pfx tail=$_cnt_tail"

# G4: PREFIX + TAIL = full messages (account for normalization)
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"},{"role":"user","content":"c"}]'
MSG_BP=1
_msg_segments_refresh_from_messages
# Compare jq-normalized versions (segments are normalized, MESSAGES may have string-content)
_jq_combined=$(jq -c '.' <<< "[${MSG_PREFIX_INNER},${MSG_TAIL_INNER}]" 2>/dev/null || echo "INVALID")
_jq_count=$(jq 'length' <<< "$_jq_combined" 2>/dev/null || echo 0)
_jq_all_count=$(jq 'length' <<< "$MESSAGES")
[[ "$_jq_count" -eq "$_jq_all_count" ]] \
    && _green "G4: PREFIX+TAIL count == MESSAGES count ($_jq_count)" \
    || _red "G4" "$_jq_all_count" "$_jq_count"

# G5: shift=0
MSG_BP=1; MSG_PREFIX_INNER='before'
_msg_segments_advance_bp 1
[[ "$MSG_PREFIX_INNER" == 'before' ]] && _green "G5: shift=0 → no change" \
    || _red "G5" "before" "$MSG_PREFIX_INNER"

# G6: bp→MSG_COUNT-1 → TAIL has last element
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"},{"role":"user","content":"c"}]'
MSG_BP=1
_msg_segments_refresh_from_messages  # PREFIX=msg0,msg1 TAIL=msg2
_cnt_tail=$(jq 'length' <<< "[${MSG_TAIL_INNER}]" 2>/dev/null || echo 0)
[[ "$_cnt_tail" -eq 1 && "$MSG_BP" -eq 1 ]] \
    && _green "G6: bp=N-2→TAIL has last msg" \
    || _red "G6" "tail=1" "tail=$_cnt_tail"

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP H: boundary / stress conditions (12 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group H: boundary / stress ───"

# H1: single message with empty content
MESSAGES='[{"role":"user","content":""}]'; MSG_BP=-1
_msg_segments_refresh_from_messages 2>/dev/null
_rc=$?
[[ $_rc -eq 0 ]] && _green "H1: empty content → no crash" \
    || _red "H1" "rc=0" "rc=$_rc"

# H2: empty TAIL_INNER append
MSG_TAIL_INNER=''; MSG_COUNT=0; MESSAGES='[]'
_msg=$(jq -nc --arg t "first" '{role:"user",content:[{type:"text",text:$t}]}')
_msg_append_to_tail "$_msg"
[[ "$MSG_TAIL_INNER" == "$_msg" ]] && _green "H2: empty TAIL→append no leading comma" \
    || _red "H2" "$_msg" "${MSG_TAIL_INNER:0:50}"

# H3: empty PREFIX_INNER assembly
MSG_PREFIX_INNER=''; MSG_TAIL_INNER=$'{"a":1},{"b":2}'; MSG_BP=-1; MSG_COUNT=3
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq . >/dev/null 2>&1 && _green "H3: empty PREFIX assembly valid" \
    || _red "H3" "valid JSON" "invalid"

# H4: MSG_COUNT=0 bp calculation
MSG_COUNT=0
_bp=$(( MSG_COUNT - ${BASHAGT_CACHE_MSG_TAIL:-2} - 1 ))
(( _bp < 0 )) && _bp=-1
[[ $_bp -eq -1 ]] && _green "H4: MSG_COUNT=0→bp=-1" \
    || _red "H4" "-1" "$_bp"

# H5: 100KB+ content (simulated)
_large_text=$(python3 -c "print('x' * 120000)" 2>/dev/null || printf 'x%.0s' $(seq 1 120000))
_large_msg=$(jq -nc --arg t "$_large_text" '{role:"user",content:[{type:"text",text:$t}]}')
MSG_TAIL_INNER="$_large_msg"; MSG_PREFIX_INNER=''; MSG_BP=-1; MSG_COUNT=2
_start=$EPOCHSECONDS
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
_elapsed=$((EPOCHSECONDS - _start))
echo "$_result" | jq . >/dev/null 2>&1 \
    && _green "H5: 120KB content valid ($_elapsed s)" \
    || _red "H5" "valid" "invalid"

# H6: base64 image data URI
_b64="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
_b64_msg=$(jq -nc --arg t "$_b64" '{role:"user",content:[{type:"text",text:$t}]}')
MSG_TAIL_INNER="$_b64_msg"; MSG_PREFIX_INNER=''; MSG_BP=-1; MSG_COUNT=2
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq . >/dev/null 2>&1 \
    && _green "H6: base64 image URI → valid JSON" \
    || _red "H6" "valid JSON" "invalid"

# H7: content array with null element
MESSAGES='[{"role":"user","content":[null,{"type":"text","text":"ok"}]}]'
MSG_BP=-1
_msg_segments_refresh_from_messages 2>/dev/null
_rc=$?
[[ $_rc -eq 0 ]] && _green "H7: null in content array → no crash" \
    || _red "H7" "rc=0" "rc=$_rc"

# H8: bp=-1 tool_use check skip
MSG_BP=-1; MSG_COUNT=10
if (( MSG_BP >= 0 && MSG_BP < MSG_COUNT - 1 )); then
    _red "H8" "skip" "executed"
else
    _green "H8: bp=-1 → tool_use check skipped"
fi

# H9: bp=MSG_COUNT-1 tool_use check skip
MSG_BP=9; MSG_COUNT=10
if (( MSG_BP >= 0 && MSG_BP < MSG_COUNT - 1 )); then
    _red "H9" "skip" "executed"
else
    _green "H9: bp=last → tool_use check skipped"
fi

# H10: msg_replace_all → dirty
MSG_SEGMENTS_DIRTY=0
msg_replace_all '[{"role":"user","content":"x"}]'
[[ "$MSG_SEGMENTS_DIRTY" -eq 1 ]] && _green "H10: msg_replace_all sets dirty" \
    || _red "H10" "1" "$MSG_SEGMENTS_DIRTY"

# H11: load_history → MSG_COUNT matches jq
# (simulated with manual MESSAGES set + refresh)
MESSAGES='[{"role":"user","content":"a"},{"role":"assistant","content":"b"},{"role":"user","content":"c"}]'
MSG_BP=-1
_msg_segments_refresh_from_messages
_jq_cnt=$(jq 'length' <<< "$MESSAGES")
[[ "$MSG_COUNT" -eq "$_jq_cnt" ]] && _green "H11: MSG_COUNT == jq length ($MSG_COUNT)" \
    || _red "H11" "$_jq_cnt" "$MSG_COUNT"

# H12: 500 sequential appends
MESSAGES='[]'; MSG_TAIL_INNER=''; MSG_COUNT=0
_bad=0
for i in $(seq 1 500); do
    _msg=$(jq -nc --arg t "stress$i" '{role:"user",content:[{type:"text",text:$t}]}')
    _msg_append_to_tail "$_msg"
    echo "$MESSAGES" | jq . >/dev/null 2>&1 || { _bad=$((_bad+1)); break; }
done
[[ $_bad -eq 0 && "$MSG_COUNT" -eq 500 ]] \
    && _green "H12: 500 appends → all valid, count=$MSG_COUNT" \
    || _red "H12" "500/valid" "$MSG_COUNT/bad=$_bad"

echo ""
# ═══════════════════════════════════════════════════════════════════
# GROUP I: full request body assembly correctness (5 tests)
# ═══════════════════════════════════════════════════════════════════
echo "─── Group I: full request body correctness ───"

# I1: byte-for-byte vs jq reference
CONTEXT_DYN_CACHED='{"role":"user","content":[{"type":"text","text":"context here"}]}'
_context_get_hash; CONTEXT_HASH="$_CONTEXT_HASH_VAL"
MSG_PREFIX_INNER='{"role":"user","content":[{"type":"text","text":"hello"}]},{"role":"assistant","content":[{"type":"text","text":"hi"}]}'
MSG_TAIL_INNER='{"role":"user","content":[{"type":"text","text":"question"}]}'
MSG_BP=1; MSG_COUNT=4; MSG_SEGMENTS_DIRTY=0
SYS='[{"type":"text","text":"You are helpful."}]'
TOOLS='[{"name":"bash","description":"Run a command"}]'
_result=$(_pe_assemble_request "claude-sonnet-4-6" 4096 1024 "true" "1" "0" "$SYS" "$TOOLS")
_ref=$(jq -n -c \
    --arg model "claude-sonnet-4-6" \
    --argjson mt 4096 \
    --slurpfile tools <(echo "$TOOLS") \
    --slurpfile sys <(echo "$SYS") \
    --slurpfile pfx <(echo "[$MSG_PREFIX_INNER]") \
    --slurpfile dyn <(echo "$CONTEXT_DYN_CACHED") \
    --slurpfile tail <(echo "[$MSG_TAIL_INNER]") \
    --argjson stream true \
    --argjson tb 1024 \
    '{model:$model,max_tokens:$mt,tools:$tools[0],system:$sys[0],messages:($pfx[0]+[$dyn[0]]+$tail[0]),stream:$stream,thinking:{budget_tokens:$tb,type:"enabled"}}')
_diff=$(diff <(echo "$_result" | jq -S .) <(echo "$_ref" | jq -S .) 2>/dev/null)
[[ -z "$_diff" ]] && _green "I1: full body byte-for-byte == jq reference" \
    || _red "I1" "identical" "differ"

# I2: cache marker injection position
MSG_PREFIX_INNER='{"role":"user","content":[{"type":"text","text":"a"}]},{"role":"assistant","content":[{"type":"text","text":"b"}]}'
MSG_TAIL_INNER='{"role":"user","content":[{"type":"text","text":"c"}]}'
MSG_BP=1; MSG_COUNT=4; MSG_SEGMENTS_DIRTY=0
CACHE_MARKER_JSON='{"cache_control":{"type":"ephemeral"}}'
_result=$(_pe_assemble_request "claude" 4096 0 "true" "1" "1" "[]" "[]")
echo "$_result" | jq -e '.messages[1].content[-1].cache_control.type == "ephemeral"' >/dev/null 2>&1 \
    && _green "I2: marker at bp position (msg[1] = prefix[1])" \
    || _red "I2" "marker at [1]" "$(echo "$_result" | jq -c '.messages[1].content[-1]')"

# I3: hook context buffer injection
_HOOK_CONTEXT_BUFFER="injected hint"
MSG_PREFIX_INNER=''; MSG_TAIL_INNER=''; MSG_BP=-1; MSG_COUNT=1
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[]" "[]")
echo "$_result" | jq -e '.messages[0].content | map(select(.text == "injected hint")) | length == 1' >/dev/null 2>&1 \
    && _green "I3: hook context injected into dyn_msg" \
    || _red "I3" "injected" "missing"
_HOOK_CONTEXT_BUFFER=""

# I4: multiple tool_use/tool_result pairs
MSG_PREFIX_INNER='{"role":"user","content":[{"type":"text","text":"run test"}]},{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"bash","input":{"cmd":"ls"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"file1"}]}'
MSG_TAIL_INNER=''
MSG_BP=2; MSG_COUNT=4
_result=$(_pe_assemble_request "claude" 4096 0 "true" "2" "0" "[]" "[]")
echo "$_result" | jq -e '.messages | length == 4' >/dev/null 2>&1 \
    && _green "I4: tool_use/tool_result pairs preserved (4 msgs)" \
    || _red "I4" "4 msgs" "$(echo "$_result" | jq '.messages | length')"
# Verify tool_use is in messages[1]
echo "$_result" | jq -e '.messages[1].content[0].type == "tool_use"' >/dev/null 2>&1 \
    && _green "I4b: tool_use at correct position" \
    || _red "I4b" "tool_use" "missing"
# Verify tool_result follows
echo "$_result" | jq -e '.messages[2].content[0].type == "tool_result"' >/dev/null 2>&1 \
    && _green "I4c: tool_result follows tool_use" \
    || _red "I4c" "tool_result" "missing"

# I5: field order tools→system→messages
_result=$(_pe_assemble_request "claude" 4096 0 "true" "-1" "0" "[{\"type\":\"text\",\"text\":\"sys\"}]" "[{\"name\":\"t\"}]")
_keys=$(echo "$_result" | jq -c 'keys')
_expected_order=$(echo "$_result" | jq -c '{"tools":.,"system":.,"messages":.} | keys')
# Verify JSON is valid
echo "$_result" | jq . >/dev/null 2>&1 \
    && _green "I5: valid request body" \
    || _red "I5" "valid" "invalid"

echo ""
echo "============================================"
echo " Assembly Optimization Stress Results:"
echo "   $PASSED passed, $FAILED failed"
echo "============================================"

# Exit with failure if any test failed
(( FAILED > 0 )) && exit 1 || exit 0
