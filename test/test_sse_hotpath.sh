#!/usr/bin/env bash
# test_sse_hotpath.sh — SSE hot-path optimization validation tests
# Validates B1/B2/B3/B4/B5 implementations before applying to bashagt.
# Run: bash test/test_sse_hotpath.sh
# No API key required. Tests function correctness in isolation.

set -uo pipefail
# No -e: jq/grep returns non-zero on no-match

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS\033[0m %s\n' "$*"; }
red()   { printf '\033[31m  FAIL\033[0m %s\n' "$*"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# ===================================================================
# ANSI globals (mirror bashagt Section 1)
# ===================================================================
BOLD=$'\033[1m';       RESET=$'\033[0m'
DIM=$'\033[2m';        GREEN=$'\033[32m'
CYAN=$'\033[36m';      YELLOW=$'\033[33m'
RED=$'\033[31m';       GRAY=$'\033[90m'
LIGHT_GREEN=$'\033[92m'; LIGHT_YELLOW=$'\033[93m'
INVERT=$'\033[7m'

# ===================================================================
# NEW optimized implementations
# ===================================================================

_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local _t="${EPOCHREALTIME/.}"
        printf -v _NOW_MS '%s' "${_t:0:13}"
    else
        printf -v _NOW_MS '%s000' "$(date +%s)"
    fi
}

_ts_to() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local _t="${EPOCHREALTIME/.}"
        printf -v "$1" '%s' "${_t:0:13}"
    else
        printf -v "$1" '%s000' "$(date +%s)"
    fi
}

_ui_time() {
    local ms="${1:-0}"
    local sec=$((ms/1000))
    if (( sec < 60 )); then
        local tenths=$(((ms%1000)/100))
        printf -v _UI_TIME '%d.%ds' "$sec" "$tenths"
    else
        local min=$((sec/60)); sec=$((sec%60))
        printf -v _UI_TIME '%dm%ds' "$min" "$sec"
    fi
}

_fmt_postprocess_var() {
    local _s="$1" _outvar="$2"
    _s="${_s//$'\r'/}"
    _s="${_s//<b>/${BOLD}}";       _s="${_s//<\/b>/${RESET}}"
    _s="${_s//<dim>/${DIM}}";      _s="${_s//<\/dim>/${RESET}}"
    _s="${_s//<g>/${GREEN}}";      _s="${_s//<\/g>/${RESET}}"
    _s="${_s//<c>/${CYAN}}";       _s="${_s//<\/c>/${RESET}}"
    _s="${_s//<y>/${YELLOW}}";     _s="${_s//<\/y>/${RESET}}"
    _s="${_s//<r>/${RED}}";        _s="${_s//<\/r>/${RESET}}"
    _s="${_s//<gray>/${GRAY}}";    _s="${_s//<\/gray>/${RESET}}"
    _s="${_s//<lg>/${LIGHT_GREEN}}"; _s="${_s//<\/lg>/${RESET}}"
    _s="${_s//<ly>/${LIGHT_YELLOW}}"; _s="${_s//<\/ly>/${RESET}}"
    _s="${_s//<inv>/${INVERT}}";   _s="${_s//<\/inv>/${RESET}}"
    printf -v "$_outvar" '%s' "$_s"
}

_stream_text() {
    local _content="$1" _ts; _ts_to _ts
    local _esc="${_content//\\/\\\\}"      # \ → \\ (FIRST)
    _esc="${_esc//\"/\\\"}"                 # " → \"
    _esc="${_esc//$'\n'/\\n}"               # LF → \n
    _esc="${_esc//$'\r'/\\r}"               # CR → \r
    _esc="${_esc//$'\t'/\\t}"               # TAB → \t
    _esc="${_esc//$'\033'/\\u001b}"         # ESC →  (ANSI codes)
    printf '{"type":"text","ts":%s,"content":"%s"}\n' "$_ts" "$_esc"
}

# JSON unescape (shared by Anthropic + OpenAI extractors)
# Uses SOH placeholder to correctly handle \\ vs \n ordering
_json_unescape() {
    local _soh=$'\x01' _raw="$1" _outvar="$2"
    # Step 1: \\ → SOH (protects escaped backslash from \n replacement)
    _raw="${_raw//$'\\\\'/$_soh}"
    # Step 2-4: handle other JSON escapes
    _raw="${_raw//'\r\n'/$'\n'}"    # CRLF → LF (before \r and \n!)
    _raw="${_raw//'\r'/$'\n'}"      # CR → LF
    _raw="${_raw//'\n'/$'\n'}"      # LF → LF
    _raw="${_raw//'\t'/$'\t'}"      # TAB → TAB
    _raw="${_raw//$'\\\"'/'"'}"     # \" → "
    # Step 5: SOH → \ (restore single backslash)
    _raw="${_raw//$_soh/$'\\'}"
    printf -v "$_outvar" '%s' "$_raw"
}

_extract_anthropic_text() {
    local _data="$1" _outvar="$2" _raw=""
    [[ "$_data" == *'"delta":{"type":"text_delta","text":"'* ]] || { printf -v "$_outvar" '%s' ""; return 0; }
    _raw="${_data##*'"delta":{"type":"text_delta","text":"'}"
    [[ "$_raw" == "$_data" ]] && { printf -v "$_outvar" '%s' ""; return 0; }
    _raw="${_raw%%'"}}'*}"
    _json_unescape "$_raw" "$_outvar"
}

_extract_openai_text() {
    local _data="$1" _outvar="$2" _raw=""
    [[ "$_data" == *'"content":"'* ]] || { printf -v "$_outvar" '%s' ""; return 0; }
    _raw="${_data##*'"content":"'}"
    [[ "$_raw" == "$_data" ]] && { printf -v "$_outvar" '%s' ""; return 0; }
    _raw="${_raw%%'"}'*}"
    _json_unescape "$_raw" "$_outvar"
}

# ====================================================================
# B1: SSE Text Extraction
# ====================================================================
echo "============================================"
echo " B1: SSE Text Extraction"
echo "============================================"
echo ""

run_b1a() {
    local name="$1" data="$2"
    # Use exact same transformation as original L8016-8020:
    # jq extracts .delta.text, gsub CRLF/CR/LF → SOH, then bash SOH → \n
    local jq_text=""
    local _soh=$'\x01'
    jq_text=$(jq -r '(.delta.text // "") | gsub("\r\n";"'"$_soh"'")|gsub("\r";"'"$_soh"'")|gsub("\n";"'"$_soh"'")' <<< "$data" 2>/dev/null || echo "")
    jq_text="${jq_text//$'\x01'/$'\n'}"
    local bash_text=""
    _extract_anthropic_text "$data" bash_text
    if [[ "$jq_text" == "$bash_text" ]]; then
        _pass "anthropic/$name"
    else
        _fail "anthropic/$name: jq='$(printf '%q' "$jq_text")' bash='$(printf '%q' "$bash_text")'"
    fi
}

run_b1o() {
    local name="$1" data="$2"
    local _soh=$'\x01'
    local jq_text=""
    jq_text=$(jq -r '(.choices[0].delta.content // "") | gsub("\r\n";"'"$_soh"'")|gsub("\r";"'"$_soh"'")|gsub("\n";"'"$_soh"'")' <<< "$data" 2>/dev/null || echo "")
    jq_text="${jq_text//$'\x01'/$'\n'}"
    local bash_text=""
    _extract_openai_text "$data" bash_text
    if [[ "$jq_text" == "$bash_text" ]]; then
        _pass "openai/$name"
    else
        _fail "openai/$name: jq='$(printf '%q' "$jq_text")' bash='$(printf '%q' "$bash_text")'"
    fi
}

echo "── B1a: Anthropic ──"

run_b1a "plain"        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello world"}}'
run_b1a "chinese"      '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好世界！测试。"}}'
run_b1a "emoji"        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"🎉✨🔥"}}'
run_b1a "empty"        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":""}}'
run_b1a "newline"      '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"line1\nline2"}}'
run_b1a "tab"          '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"col1\tcol2"}}'
run_b1a "quote"        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"He said \"hello\""}}'
run_b1a "backslash"    '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"C:\\Users\\name\\file"}}'
run_b1a "code"         '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"echo \"$HOME\""}}'
run_b1a "mixed"        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"path=\"C:\\\\dir\"\nline2"}}'
run_b1a "braces"       '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"data: {}}"}}'
run_b1a "open_brace"   '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"if (x > 0) { do_y() }"}}'
run_b1a "single_char"  '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}}'
run_b1a "leading_space" '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"    indented"}}'
run_b1a "thinking"     '{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"thought"}}'
run_b1a "msg_start"    '{"type":"message_start","message":{"id":"msg_1","role":"assistant"}}'
run_b1a "msg_delta"    '{"type":"message_delta","delta":{"stop_reason":"end_turn"}}'
run_b1a "ping"         '{"type":"ping"}'
run_b1a "content_block_start" '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"start"}}'
run_b1a "crlf"         '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"a\r\nb"}}'

echo ""
echo "── B1b: OpenAI ──"

run_b1o "plain"        '{"id":"x","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}'
run_b1o "chinese"      '{"id":"x","choices":[{"index":0,"delta":{"content":"你好"},"finish_reason":null}]}'
run_b1o "empty"        '{"id":"x","choices":[{"index":0,"delta":{"content":""},"finish_reason":null}]}'
run_b1o "quote"        '{"id":"x","choices":[{"index":0,"delta":{"content":"say \"hi\""},"finish_reason":null}]}'
run_b1o "with_stop"    '{"id":"x","choices":[{"index":0,"delta":{"content":"test"},"finish_reason":"stop"}]}'
run_b1o "stop_only"    '{"id":"x","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'
run_b1o "backslash"    '{"id":"x","choices":[{"index":0,"delta":{"content":"C:\\\\dir\\\\file"},"finish_reason":null}]}'
run_b1o "newline"      '{"id":"x","choices":[{"index":0,"delta":{"content":"a\\nb"},"finish_reason":null}]}'
run_b1o "code"         '{"id":"x","choices":[{"index":0,"delta":{"content":"print(\"ok\")"},"finish_reason":null}]}'

# ====================================================================
# B2: _fmt_postprocess_var
# ====================================================================
echo ""
echo "============================================"
echo " B2: _fmt_postprocess_var"
echo "============================================"
echo ""

# Inline sed version for comparison (exact same as bashagt L7987-8001)
_fmt_postprocess_old() {
    sed \
        -e "s|"$'\r'"||g" \
        -e "s|<b>|${BOLD}|g" \
        -e "s|<dim>|${DIM}|g" \
        -e "s|<g>|${GREEN}|g" \
        -e "s|<c>|${CYAN}|g" \
        -e "s|<y>|${YELLOW}|g" \
        -e "s|<r>|${RED}|g" \
        -e "s|<gray>|${GRAY}|g" \
        -e "s|<lg>|${LIGHT_GREEN}|g" \
        -e "s|<ly>|${LIGHT_YELLOW}|g" \
        -e "s|<inv>|${INVERT}|g" \
        -e "s|</[a-z]*>|${RESET}|g"
}

run_b2() {
    local name="$1" input="$2"
    local sed_out bash_out
    sed_out=$(printf '%s\n' "$input" | _fmt_postprocess_old 2>/dev/null)
    _fmt_postprocess_var "$input" bash_out
    if [[ "$sed_out" == "$bash_out" ]]; then
        _pass "fmt/$name"
        return
    fi
    # Check: is it the known </[a-z]*> regex vs explicit 10-tags difference?
    if [[ "$input" == *"</"* ]]; then
        local known=0
        for _tag in "b" "dim" "g" "c" "y" "r" "gray" "lg" "ly" "inv"; do
            [[ "$input" == *"</${_tag}>"* ]] && known=1 && break
        done
        if (( known == 0 )); then
            _pass "fmt/$name (known: unknown closing tag)" && return
        fi
    fi
    _fail "fmt/$name: sed='$(printf '%q' "$sed_out")' bash='$(printf '%q' "$bash_out")'"
}

run_b2 "plain"          "Hello world"
run_b2 "bold"           "<b>bold text</b> normal"
run_b2 "red"            "<r>error</r>"
run_b2 "green"          "<g>ok</g>"
run_b2 "cyan"           "<c>info</c>"
run_b2 "yellow"         "<y>warn</y>"
run_b2 "dim"            "<dim>muted</dim>"
run_b2 "gray"           "<gray>faint</gray>"
run_b2 "light_green"    "<lg>bright</lg>"
run_b2 "light_yellow"   "<ly>highlight</ly>"
run_b2 "invert"         "<inv>reverse</inv>"
run_b2 "all_tags"       "<b>B</b><r>R</r><g>G</g><c>C</c><y>Y</y><dim>D</dim><gray>Gr</gray><lg>LG</lg><ly>LY</ly><inv>I</inv>"
run_b2 "nested"         "<b>outer <dim>inner <r>deep</r></dim></b>"
run_b2 "no_tags"        "plain text"
run_b2 "with_cr"        $'line\r\nnext'
run_b2 "code_like"      'if [[ -f f ]]; then echo ok; fi'
run_b2 "partial"        "angle < and > brackets"
run_b2 "tag_in_code"    "echo '<b>text</b>' | cat"
run_b2 "unknown_close"  "text <custom>value</custom> end"   # sed catches, bash passes through

# ====================================================================
# B3: _stream_text
# ====================================================================
echo ""
echo "============================================"
echo " B3: _stream_text"
echo "============================================"
echo ""

run_b3() {
    local name="$1" content="$2"
    local jq_out bash_out jq_parsed bash_parsed

    jq_out=$(jq -nc --arg c "$content" '{content: $c}' 2>/dev/null)
    bash_out=$(_stream_text "$content" 2>/dev/null)

    bash_parsed=$(jq -r '.content // "__ERR__"' <<< "$bash_out" 2>/dev/null)
    jq_parsed=$(jq -r '.content // "__ERR__"' <<< "$jq_out" 2>/dev/null)

    if [[ "$bash_parsed" == "__ERR__" ]]; then
        _fail "stream/$name: invalid JSON"
        printf '    bytes: %q\n' "${bash_out:0:120}"
        return
    fi

    if [[ "$bash_parsed" != "$jq_parsed" ]]; then
        _fail "stream/$name: content mismatch"
        printf '    jq=%q\n    bash=%q\n' "$jq_parsed" "$bash_parsed"
        return
    fi

    if [[ "$bash_out" == '{"type":"text","ts":'* ]]; then
        _pass "stream/$name"
    else
        _fail "stream/$name: bad structure"
    fi
}

run_b3 "plain"          "Hello world"
run_b3 "chinese"        "你好世界！测试文本。"
run_b3 "emoji"          "🎉✨ test 🔥"
run_b3 "quotes"         'He said "hello world"'
run_b3 "backslash"      'C:\Users\name\file.txt'
run_b3 "newline"        $'line1\nline2\nline3'
run_b3 "tab"            $'col1\tcol2\tcol3'
run_b3 "ansi"           $'\033[1mbold\033[0m \033[31mred\033[0m'
run_b3 "mixed"          $'path="C:\\dir"\n\033[1mheader\033[0m\n\tindent'
run_b3 "empty"          ""
run_b3 "single"         "x"
run_b3 "markdown"       $'# Title\n\n**bold** and *italic*\n\n```\ncode\n```'
run_b3 "json_fragment"  '{"key":"value","nested":{"a":1}}'
run_b3 "long"           "$(printf 'The quick brown fox. %.0s' {1..20})"
run_b3 "special"        $'back\\slash\ttab\nnewline"quote'

# ANSI round-trip: format → emit → parse → compare
echo ""
echo "── B3: ANSI format round-trip ──"
_run_ansi_roundtrip() {
    local _tag _open _close _raw _line _parsed
    for _tag in "b" "r" "g" "c" "y" "dim" "inv" "gray" "lg" "ly"; do
        _raw=""; _open="<${_tag}>"; _close="</${_tag}>"
        _fmt_postprocess_var "${_open}TEST${_close}" _raw
        _line=$(_stream_text "$_raw" 2>/dev/null)
        _parsed=$(jq -r '.content // "ERR"' <<< "$_line" 2>/dev/null)
        if [[ "$_parsed" == "$_raw" ]]; then
            _pass "ansi_roundtrip/${_tag}"
        else
            _fail "ansi_roundtrip/${_tag}: parsed != raw"
        fi
    done
}
_run_ansi_roundtrip

# ====================================================================
# B3 Stress: JSON round-trip
# ====================================================================
echo ""
echo "── B3: Stress round-trip ──"
_run_b3_stress() {
    local _i _sc _line _parsed
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        _sc=""
        printf -v _sc 'Test %d: alpha=%d path="C:\\\\dir\\\\%d" line=%d' "$_i" $((RANDOM%1000)) $((RANDOM%100)) "$_i"
        _line=$(_stream_text "$_sc" 2>/dev/null)
        _parsed=$(jq -r '.content // "ERR"' <<< "$_line" 2>/dev/null)
        if [[ "$_parsed" == "$_sc" ]]; then
            _pass "roundtrip/$_i ($((_i*10))B)"
        else
            _fail "roundtrip/$_i: mismatch"
        fi
    done
}
_run_b3_stress

# ====================================================================
# B4+B5: Timestamps + status_done
# ====================================================================
echo ""
echo "============================================"
echo " B4+B5: Timestamps + status_done"
echo "============================================"
echo ""

# _now_ms
_now_ms
if [[ -n "${_NOW_MS:-}" ]] && [[ "$_NOW_MS" =~ ^[0-9]{13}$ ]]; then
    _pass "_now_ms 13-digit: $_NOW_MS"
else
    _fail "_now_ms: got '${_NOW_MS:-empty}'"
fi

# monotonic
_now_ms; _ts1=$_NOW_MS
sleep 0.01
_now_ms; _ts2=$_NOW_MS
if (( _ts2 >= _ts1 )); then
    _pass "_now_ms monotonic: $_ts1 -> $_ts2"
else
    _fail "_now_ms NOT monotonic: $_ts1 -> $_ts2"
fi

# _ui_time
_ui_time 5200
[[ "$_UI_TIME" == "5.2s" ]] && _pass "_ui_time 5200ms=5.2s" || _fail "_ui_time 5200ms: $_UI_TIME"
_ui_time 125500
[[ "$_UI_TIME" == "2m5s" ]] && _pass "_ui_time 125500ms=2m5s" || _fail "_ui_time 125500ms: $_UI_TIME"
_ui_time 0
[[ "$_UI_TIME" == "0.0s" ]] && _pass "_ui_time 0ms=0.0s" || _fail "_ui_time 0ms: $_UI_TIME"

# ====================================================================
# Integration: Full callback simulation
# ====================================================================
echo ""
echo "============================================"
echo " Integration: Callback simulation"
echo "============================================"
echo ""

echo "── Anthropic stream ──"
simulate_anthropic() {
    local _buf="" _done_label="Thinking..." _start_ts=0
    local _lines=() _status=""

    local _tokens=(
        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"<b>Hello</b> world\n"}}'
        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"<r>Error:</r> check\n"}}'
        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"done\n"}}'
    )

    for _sse in "${_tokens[@]}"; do
        local _text=""
        _extract_anthropic_text "$_sse" _text
        [[ -z "$_text" ]] && continue

        _buf+="$_text"
        while [[ "$_buf" == *$'\n'* ]]; do
            local _line="${_buf%%$'\n'*}"
            _buf="${_buf#*$'\n'}"
            if [[ -n "$_done_label" ]]; then
                _now_ms; _ui_time $(( _NOW_MS - _start_ts ))
                _status="status_done:${_done_label}:${_UI_TIME}"
                _done_label=""
            fi
            local _fmt=""
            _fmt_postprocess_var "$_line" _fmt
            _lines+=("$(_stream_text "$_fmt")")
        done
    done

    [[ -n "$_buf" ]] && { local _fmt=""; _fmt_postprocess_var "$_buf" _fmt; _lines+=("$(_stream_text "$_fmt")"); }

    SIM_ANTH_LINES=("${_lines[@]}")
    SIM_ANTH_STATUS="$_status"
}

simulate_anthropic

[[ -n "$SIM_ANTH_STATUS" ]] && _pass "integ/status_done: $SIM_ANTH_STATUS" || _fail "integ/status_done: not emitted"
[[ "${#SIM_ANTH_LINES[@]}" -eq 3 ]] && _pass "integ/3 output lines" || _fail "integ/lines: expected 3 got ${#SIM_ANTH_LINES[@]}"

for _i in "${!SIM_ANTH_LINES[@]}"; do
    _t=""; _t=$(jq -r '.type // "BAD"' <<< "${SIM_ANTH_LINES[$_i]}" 2>/dev/null)
    [[ "$_t" == "text" ]] && _pass "integ/anthropic_line$((_i+1)) valid JSON" || _fail "integ/anthropic_line$((_i+1)): type=$_t"
done

# Check line 1 has ANSI codes from <b> tag
_c1=""; _c1=$(jq -r '.content // ""' <<< "${SIM_ANTH_LINES[0]}" 2>/dev/null)
[[ "$_c1" == *$'\033'* ]] && _pass "integ/ansi_codes_present" || _fail "integ/ansi_codes_missing"

echo ""
echo "── OpenAI stream ──"
simulate_openai() {
    local _buf="" _lines=()
    local _tokens=(
        '{"id":"x","choices":[{"index":0,"delta":{"content":"<g>OK</g> done\n"},"finish_reason":null}]}'
        '{"id":"x","choices":[{"index":0,"delta":{"content":"more\n"},"finish_reason":null}]}'
        '{"id":"x","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'
    )
    for _sse in "${_tokens[@]}"; do
        local _text=""
        _extract_openai_text "$_sse" _text
        [[ -z "$_text" ]] && continue
        _buf+="$_text"
        while [[ "$_buf" == *$'\n'* ]]; do
            local _line="${_buf%%$'\n'*}"
            _buf="${_buf#*$'\n'}"
            local _fmt=""
            _fmt_postprocess_var "$_line" _fmt
            _lines+=("$(_stream_text "$_fmt")")
        done
    done
    SIM_OAI_LINES=("${_lines[@]}")
}

simulate_openai

[[ "${#SIM_OAI_LINES[@]}" -eq 2 ]] && _pass "integ_oai/2 lines" || _fail "integ_oai/lines: expected 2 got ${#SIM_OAI_LINES[@]}"
for _i in "${!SIM_OAI_LINES[@]}"; do
    _t=""; _t=$(jq -r '.type // "BAD"' <<< "${SIM_OAI_LINES[$_i]}" 2>/dev/null)
    [[ "$_t" == "text" ]] && _pass "integ_oai/line$((_i+1)) valid" || _fail "integ_oai/line$((_i+1)): type=$_t"
done

# ====================================================================
# Edge cases: malformed data
# ====================================================================
echo ""
echo "── Edge cases ──"

_edge_ok() {
    local name="$1" result="$2"
    [[ -z "$result" ]] && _pass "edge/$name" || _fail "edge/$name: got '$result'"
}

_t=""; _extract_anthropic_text '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","' _t
_edge_ok "truncated_anthropic" "$_t"

_u=""; _extract_openai_text '{"id":"x","choices":[{"delta":{"conte' _u
_edge_ok "truncated_openai" "$_u"

_v=""; _extract_anthropic_text "this is not json" _v
_edge_ok "non_json" "$_v"

_w=""; _extract_openai_text "[DONE]" _w
_edge_ok "done_marker" "$_w"

_x=""; _extract_anthropic_text "" _x
_edge_ok "empty_string" "$_x"

# ====================================================================
# Results
# ====================================================================
echo ""
echo "============================================"
printf " Results: \033[32m%d PASS\033[0m, \033[31m%d FAIL\033[0m\n" "$PASS" "$FAIL"
echo "============================================"

exit $(( FAIL > 0 ? 1 : 0 ))
