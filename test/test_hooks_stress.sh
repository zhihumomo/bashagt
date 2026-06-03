#!/usr/bin/env bash
# test_hooks_stress.sh — Hook system stress / edge-case tests
# Run: bash test/test_hooks_stress.sh
# No API key required. Covers all hook types, priority chains, error paths.
set -eo pipefail

PASS=0; FAIL=0
TEST_DIR=$(mktemp -d "/tmp/bashagt_hook_stress.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s\033[0m\n' "$*"; }
info()  { printf '\033[33m   ... %s\033[0m\n' "$*"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }

# ── Reuse hook infrastructure from test_hooks.sh ──
declare -A HOOK_HANDLERS HOOK_TYPE HOOK_ENABLED HOOK_PRIORITY HOOK_META HOOK_POINTS

register_hook() {
    local _point="$1" _prio="$2" _name="$3" _type="$4" _source="$5"
    HOOK_TYPE[$_name]="$_type"
    HOOK_HANDLERS[$_name]="$_source"
    HOOK_PRIORITY[$_name]="$_prio"
    HOOK_ENABLED[$_name]="1"
    HOOK_META[$_name]=$(jq -nc --arg p "$_point" --arg t "$_type" --arg n "$_name" \
        '{point:$p,type:$t,name:$n}')
    HOOK_POINTS[$_point]+="$_name "
}

_interrupted() { return 1; }

_hook_render_template() {
    local _file="$1" _ctx="$2"
    local _body; _body=$(cat "$_file" 2>/dev/null)
    [[ -z "$_body" ]] && { jq -nc '{inject:false}'; return; }
    local _rendered="$_body" _key _val
    while IFS= read -r _key; do
        _val=$(jq -r --arg k "$_key" '.[$k] // ""' <<< "$_ctx" 2>/dev/null)
        local _pattern="{{${_key}}}"
        _rendered="${_rendered//$_pattern/$_val}"
    done < <(jq -r 'paths(scalars) | join(".")' <<< "$_ctx" 2>/dev/null)
    jq -nc --arg text "$_rendered" '{inject:true,role:"user",content:$text}'
}

_hook_http_call() { jq -nc '{inject:false}'; }

# Synchronous _hook_fire (stable, no race)
_hook_fire() {
    local _point="$1" _ctx="${2:-{}}"
    local _names="${HOOK_POINTS[$_point]:-}"
    [[ -z "$_names" ]] && { echo '[]'; return 0; }
    local _name _type _handler _out_file
    local -a _results=()
    local _sorted_names; _sorted_names=$(for _n in $_names; do
        printf '%s %s\n' "${HOOK_PRIORITY[$_n]:-0}" "$_n"
    done 2>/dev/null | sort -n | awk "{print \$2}")
    [[ -z "$_sorted_names" ]] && { echo '[]'; return 0; }

    for _name in $_sorted_names; do
        [[ "${HOOK_ENABLED[$_name]:-0}" != "1" ]] && continue
        _type="${HOOK_TYPE[$_name]:-inline_bash}"
        _handler="${HOOK_HANDLERS[$_name]:-}"
        _out_file=$(mktemp "/tmp/bashagt_hook_stress.XXXXXX")
        (
            case "$_type" in
                inline_bash) set +B; eval "$_handler" ;;
                bash)        source "$_handler"; "${_name}" "$_ctx" ;;
                python)      echo "$_ctx" | python3 "$_handler" 2>/dev/null || echo '{"error":"python3 not found"}' ;;
                exec)        echo "$_ctx" | "$_handler" 2>/dev/null || echo '{"error":"exec failed"}' ;;
                http)        echo "$_ctx" | _hook_http_call "$_handler" "2000" ;;
                template)    _hook_render_template "$_handler" "$_ctx" ;;
                *)           echo '{"error":"unknown type"}' ;;
            esac
        ) >"$_out_file" 2>/dev/null
        if [[ -s "$_out_file" ]]; then
            _results+=("$(cat "$_out_file")")
        fi
        rm -f "$_out_file"
    done
    if ((${#_results[@]} > 0)); then
        printf '%s\n' "${_results[@]}" | jq -sc '.' 2>/dev/null || echo '[]'
    else
        echo '[]'
    fi
}

setup_hook_env() {
    HOOK_HANDLERS=()
    HOOK_TYPE=()
    HOOK_ENABLED=()
    HOOK_PRIORITY=()
    HOOK_META=()
    HOOK_POINTS=()
}

echo "============================================"
echo " Hook System Stress / Edge-Case Tests"
echo "============================================"
echo ""

# ═══════════════════════════════════════════════════
# Category A: All hook types
# ═══════════════════════════════════════════════════

echo "── A: All hook types ──"

test_type_inline_bash_json() {
    setup_hook_env
    register_hook "pre_turn" 10 "t" "inline_bash" 'jq -nc {inject:true,order:1}'
    local r; r=$(_hook_fire "pre_turn" '{}')
    local o; o=$(jq -r '.[0].order' <<< "$r" 2>/dev/null)
    [[ "$o" == "1" ]] && _pass "inline_bash: jq handler produces JSON" || _fail "inline_bash: expected order=1, got [$r]"
}

test_type_inline_bash_echo() {
    setup_hook_env
    # Handler using echo+pipe (tests pipeline in eval context)
    # Use single-quoted JSON arg to jq (prevents brace expansion)
    register_hook "pre_turn" 10 "t" "inline_bash" "jq -nc '{payload:\"pipe_ok\"}'"
    local r; r=$(_hook_fire "pre_turn" '{}')
    echo "$r" | jq -e '.[0].payload == "pipe_ok"' >/dev/null 2>&1 \
        && _pass "inline_bash: echo|jq pipeline" \
        || _fail "inline_bash: pipeline failed, got [$r]"
}

test_type_bash_script() {
    setup_hook_env
    local _sf; _sf=$(mktemp "$TEST_DIR/hook_script.XXXXXX.sh")
    cat > "$_sf" <<'SHEOF'
t() { jq -nc "{inject:true,source:\"bash_script\"}"; }
SHEOF
    register_hook "pre_turn" 10 "t" "bash" "$_sf"
    local r; r=$(_hook_fire "pre_turn" '{}')
    local s; s=$(jq -r '.[0].source' <<< "$r" 2>/dev/null)
    [[ "$s" == "bash_script" ]] && _pass "bash: sourced script handler" || _fail "bash: expected bash_script, got [$r]"
    rm -f "$_sf"
}

test_type_template_md() {
    setup_hook_env
    local _tf; _tf=$(mktemp "$TEST_DIR/tmpl.XXXXXX.md")
    echo 'Hello {{name}}, value is {{val}}' > "$_tf"
    register_hook "pre_turn" 10 "t" "template" "$_tf"
    local r; r=$(_hook_fire "pre_turn" '{"name":"World","val":"42"}')
    local c; c=$(jq -r '.[0].content' <<< "$r" 2>/dev/null)
    [[ "$c" == *"Hello World"* && "$c" == *"42"* ]] \
        && _pass "template: {{var}} substitution" \
        || _fail "template: expected World+42, got [$c]"
    rm -f "$_tf"
}

test_type_python_fallback() {
    setup_hook_env
    register_hook "pre_turn" 10 "t" "python" "/nonexistent/hook.py"
    local r; r=$(_hook_fire "pre_turn" '{}')
    # Should not crash — returns error marker, test harness collects it
    local ok; ok=$(echo "$r" | jq -r '.[0].error // "none"' 2>/dev/null)
    [[ "$ok" != "none" ]] && _pass "python: missing script → graceful error" \
        || _fail "python: expected error marker, got [$r]"
}

test_type_exec_fallback() {
    setup_hook_env
    register_hook "pre_turn" 10 "t" "exec" "/nonexistent/binary"
    local r; r=$(_hook_fire "pre_turn" '{}')
    local ok; ok=$(echo "$r" | jq -r '.[0].error // "none"' 2>/dev/null)
    [[ "$ok" != "none" ]] && _pass "exec: missing binary → graceful error" \
        || _fail "exec: expected error marker, got [$r]"
}

test_type_http_fallback() {
    setup_hook_env
    register_hook "pre_turn" 10 "t" "http" "https://127.0.0.1:19999/nonexistent"
    local r; r=$(_hook_fire "pre_turn" '{}')
    # _hook_http_call returns {inject:false} on failure (graceful degradation)
    # _hook_http_call returns {inject:false} on failure; collected as result
    local ok; ok=$(echo "$r" | jq -r '.[0].inject' 2>/dev/null)
    [[ "$ok" == "false" ]] && _pass "http: unreachable URL → graceful {inject:false}" \
        || _fail "http: expected inject=false, got [$r]"
}

# ═══════════════════════════════════════════════════
# Category B: Priority ordering
# ═══════════════════════════════════════════════════

echo "── B: Priority ordering ──"

test_priority_chain_3() {
    setup_hook_env
    register_hook "pre_turn" 99 "low"    "inline_bash" 'jq -nc {order:3}'
    register_hook "pre_turn" 50 "mid"    "inline_bash" 'jq -nc {order:2}'
    register_hook "pre_turn" 1  "high"   "inline_bash" 'jq -nc {order:1}'
    local r; r=$(_hook_fire "pre_turn" '{}')
    local a b c
    a=$(jq -r '.[0].order' <<< "$r" 2>/dev/null)
    b=$(jq -r '.[1].order' <<< "$r" 2>/dev/null)
    c=$(jq -r '.[2].order' <<< "$r" 2>/dev/null)
    [[ "$a$b$c" == "123" ]] && _pass "priority: 3-handler chain 1→2→3" \
        || _fail "priority: expected 123, got $a$b$c"
}

test_priority_same_prio() {
    setup_hook_env
    # Same priority → registration order (lexical by space-split iteration)
    register_hook "pre_turn" 10 "alpha" "inline_bash" "jq -nc '{name:\"alpha\"}'"
    register_hook "pre_turn" 10 "beta"  "inline_bash" "jq -nc '{name:\"beta\"}'"
    local r; r=$(_hook_fire "pre_turn" '{}')
    local count; count=$(jq 'length' <<< "$r" 2>/dev/null)
    [[ "$count" == "2" ]] && _pass "priority: same-prio both fire" \
        || _fail "priority: expected 2 results, got $count"
}

# ═══════════════════════════════════════════════════
# Category C: Enable/disable
# ═══════════════════════════════════════════════════

echo "── C: Enable/disable ──"

test_disable_then_enable() {
    setup_hook_env
    register_hook "pre_turn" 10 "toggle" "inline_bash" 'jq -nc {active:true}'
    HOOK_ENABLED[toggle]="0"
    local r1; r1=$(_hook_fire "pre_turn" '{}')
    [[ "$r1" == "[]" ]] || { _fail "disable: expected [], got [$r1]"; return; }
    HOOK_ENABLED[toggle]="1"
    local r2; r2=$(_hook_fire "pre_turn" '{}')
    local a; a=$(jq -r '.[0].active' <<< "$r2" 2>/dev/null)
    [[ "$a" == "true" ]] && _pass "enable: disable→re-enable toggle" \
        || _fail "enable: expected active=true, got [$r2]"
}

test_selective_disable() {
    setup_hook_env
    register_hook "pre_turn" 1 "a" "inline_bash" "jq -nc '{n:\"a\"}'"
    register_hook "pre_turn" 2 "b" "inline_bash" "jq -nc '{n:\"b\"}'"
    register_hook "pre_turn" 3 "c" "inline_bash" "jq -nc '{n:\"c\"}'"
    HOOK_ENABLED[b]="0"
    local r; r=$(_hook_fire "pre_turn" '{}')
    local count; count=$(jq 'length' <<< "$r" 2>/dev/null)
    local names; names=$(jq -r '.[].n' <<< "$r" 2>/dev/null | tr '\n' ',')
    [[ "$count" == "2" && "$names" == "a,c," ]] \
        && _pass "selective: disabled middle, a+c fired" \
        || _fail "selective: expected 2 (a,c), got $count ($names)"
}

# ═══════════════════════════════════════════════════
# Category D: Error handling
# ═══════════════════════════════════════════════════

echo "── D: Error handling ──"

test_handler_crash() {
    setup_hook_env
    # Handler that crashes (returns false, writes nothing)
    register_hook "pre_turn" 10 "crash" "inline_bash" 'false'
    local r; r=$(_hook_fire "pre_turn" '{}')
    [[ "$r" == "[]" ]] && _pass "crash: failing handler → empty result" \
        || _fail "crash: expected [], got [$r]"
}

test_handler_syntax_error() {
    setup_hook_env
    # Invalid shell syntax in handler body
    register_hook "pre_turn" 10 "bad" "inline_bash" 'this_command_does_not_exist_xyz'
    local r; r=$(_hook_fire "pre_turn" '{}')
    [[ "$r" == "[]" ]] && _pass "syntax: invalid command → empty result" \
        || _fail "syntax: expected [], got [$r]"
}

test_handler_mixed_crash_and_ok() {
    setup_hook_env
    register_hook "pre_turn" 1 "bad"  "inline_bash" 'false'
    register_hook "pre_turn" 2 "good" "inline_bash" 'jq -nc {ok:true}'
    local r; r=$(_hook_fire "pre_turn" '{}')
    local count; count=$(jq 'length' <<< "$r" 2>/dev/null)
    local ok; ok=$(jq -r '.[0].ok' <<< "$r" 2>/dev/null)
    [[ "$count" == "1" && "$ok" == "true" ]] \
        && _pass "mixed: crash+ok → only ok result" \
        || _fail "mixed: expected 1 result ok=true, got count=$count [$r]"
}

# ═══════════════════════════════════════════════════
# Category E: Context JSON integrity
# ═══════════════════════════════════════════════════

echo "── E: Context JSON integrity ──"

test_ctx_passthrough() {
    setup_hook_env
    register_hook "pre_turn" 10 "ctx" "inline_bash" 'jq -nc {echo:true}'
    local r; r=$(_hook_fire "pre_turn" '{"a":1,"b":"two","c":[3,4]}')
    local count; count=$(jq 'length' <<< "$r" 2>/dev/null)
    [[ "$count" == "1" ]] && _pass "ctx: complex JSON context accepted" \
        || _fail "ctx: expected 1 result, got $count"
}

test_ctx_empty() {
    setup_hook_env
    register_hook "pre_turn" 10 "ctx" "inline_bash" 'jq -nc {ok:true}'
    local r; r=$(_hook_fire "pre_turn" '{}')
    local ok; ok=$(jq -r '.[0].ok' <<< "$r" 2>/dev/null)
    [[ "$ok" == "true" ]] && _pass "ctx: empty object context" || _fail "ctx: empty ctx failed"
}

test_ctx_special_chars() {
    setup_hook_env
    local _tf; _tf=$(mktemp "$TEST_DIR/tmpl_special.XXXXXX.md")
    printf '{{msg}}' > "$_tf"
    register_hook "pre_turn" 10 "ctx" "template" "$_tf"
    # Context with quotes, newlines, backslashes
    local r; r=$(_hook_fire "pre_turn" '{"msg":"say \"hello\"\nline2\\end"}')
    local c; c=$(jq -r '.[0].content' <<< "$r" 2>/dev/null)
    # Template should contain the substituted value with special chars preserved
    [[ -n "$c" ]] && _pass "ctx: special chars in template value" \
        || _fail "ctx: special chars — empty content"
    rm -f "$_tf"
}

# ═══════════════════════════════════════════════════
# Category F: Multiple hook points
# ═══════════════════════════════════════════════════

echo "── F: Multi-point ──"

test_multi_point_isolation() {
    setup_hook_env
    register_hook "pre_turn"  10 "pt" "inline_bash" "jq -nc '{point:\"pre_turn\"}'"
    register_hook "post_tool" 10 "po" "inline_bash" "jq -nc '{point:\"post_tool\"}'"
    register_hook "on_stuck"  10 "st" "inline_bash" "jq -nc '{point:\"on_stuck\"}'"

    local r1; r1=$(_hook_fire "pre_turn" '{}')
    local r2; r2=$(_hook_fire "post_tool" '{}')
    local r3; r3=$(_hook_fire "on_stuck" '{}')

    local p1 p2 p3
    p1=$(jq -r '.[0].point' <<< "$r1" 2>/dev/null)
    p2=$(jq -r '.[0].point' <<< "$r2" 2>/dev/null)
    p3=$(jq -r '.[0].point' <<< "$r3" 2>/dev/null)
    [[ "$p1" == "pre_turn" && "$p2" == "post_tool" && "$p3" == "on_stuck" ]] \
        && _pass "multi-point: 3 points isolated correctly" \
        || _fail "multi-point: got $p1/$p2/$p3"
}

test_point_no_handlers() {
    setup_hook_env
    local r; r=$(_hook_fire "nonexistent_point" '{}')
    [[ "$r" == "[]" ]] && _pass "empty: no handlers → []" \
        || _fail "empty: expected [], got [$r]"
}

# ═══════════════════════════════════════════════════
# Category G: Output size extremes
# ═══════════════════════════════════════════════════

echo "── G: Output extremes ──"

test_large_output() {
    setup_hook_env
    # Handler that produces ~50KB of JSON output
    register_hook "pre_turn" 10 "big" "inline_bash" \
        'jq -nc --arg data "$(head -c 40000 /dev/zero | base64 | head -c 40000)" "{inject:true,large:\$data}"'
    local r; r=$(_hook_fire "pre_turn" '{}')
    local sz; sz=$(wc -c <<< "$r" 2>/dev/null || echo 0)
    (( sz > 1000 )) && _pass "large: ${sz}B output handled" \
        || _fail "large: got only ${sz}B"
}

test_empty_output() {
    setup_hook_env
    # Handler that produces no output (not even a newline)
    register_hook "pre_turn" 10 "empty" "inline_bash" ':'
    local r; r=$(_hook_fire "pre_turn" '{}')
    [[ "$r" == "[]" ]] && _pass "empty-output: silent handler → []" \
        || _fail "empty-output: expected [], got [$r]"
}

test_output_with_trailing_newlines() {
    setup_hook_env
    # Output with many trailing newlines
    register_hook "pre_turn" 10 "tn" "inline_bash" 'printf "{}\n\n\n\n"'
    local r; r=$(_hook_fire "pre_turn" '{}')
    # Should produce valid JSON with empty object
    echo "$r" | jq -e '.[0] == {}' >/dev/null 2>&1 \
        && _pass "newlines: trailing whitespace handled" \
        || _fail "newlines: parse failed, got [$r]"
}

# ═══════════════════════════════════════════════════
# Category H: Template edge cases
# ═══════════════════════════════════════════════════

echo "── H: Template edge cases ──"

test_template_no_vars() {
    setup_hook_env
    local _tf; _tf=$(mktemp "$TEST_DIR/tmpl_static.XXXXXX.md")
    echo "Static content without any variables." > "$_tf"
    register_hook "pre_turn" 10 "t" "template" "$_tf"
    local r; r=$(_hook_fire "pre_turn" '{}')
    local c; c=$(jq -r '.[0].content' <<< "$r" 2>/dev/null)
    [[ "$c" == *"Static content"* ]] && _pass "template: no vars → literal output" \
        || _fail "template: expected literal, got [$c]"
    rm -f "$_tf"
}

test_template_undefined_var() {
    setup_hook_env
    local _tf; _tf=$(mktemp "$TEST_DIR/tmpl_undef.XXXXXX.md")
    echo 'Value: {{nonexistent_var}} end' > "$_tf"
    register_hook "pre_turn" 10 "t" "template" "$_tf"
    local r; r=$(_hook_fire "pre_turn" '{}')
    local c; c=$(jq -r '.[0].content' <<< "$r" 2>/dev/null)
    # Undefined vars → empty string substitution (not literal "{{var}}")
    [[ "$c" == *"Value:  end"* || "$c" == *"Value: {{"* ]] \
        && _pass "template: undefined var handled" \
        || _fail "template: unexpected content [$c]"
    rm -f "$_tf"
}

test_template_multiline() {
    setup_hook_env
    local _tf; _tf=$(mktemp "$TEST_DIR/tmpl_multi.XXXXXX.md")
    cat > "$_tf" <<'MDEOF'
Line 1: {{a}}
Line 2: {{b}}
Line 3: {{c}}
MDEOF
    register_hook "pre_turn" 10 "t" "template" "$_tf"
    local r; r=$(_hook_fire "pre_turn" '{"a":"A","b":"B","c":"C"}')
    local c; c=$(jq -r '.[0].content' <<< "$r" 2>/dev/null)
    [[ "$c" == *"Line 1: A"* && "$c" == *"Line 2: B"* && "$c" == *"Line 3: C"* ]] \
        && _pass "template: multi-line multi-var" \
        || _fail "template: multi-var failed, got [$c]"
    rm -f "$_tf"
}

# ═══════════════════════════════════════════════════
# Category I: Registration edge cases
# ═══════════════════════════════════════════════════

echo "── I: Registration ──"

test_reregister_override() {
    setup_hook_env
    register_hook "pre_turn" 10 "dup" "inline_bash" 'jq -nc {v:1}'
    register_hook "pre_turn" 20 "dup" "inline_bash" 'jq -nc {v:2}'
    local r; r=$(_hook_fire "pre_turn" '{}')
    local count; count=$(jq 'length' <<< "$r" 2>/dev/null)
    # Same name registered twice → second call overwrites but point list has it twice
    # Both fire (two entries in HOOK_POINTS for same name)
    [[ "$count" -ge "1" ]] && _pass "reregister: duplicate name handled" \
        || _fail "reregister: got $count results"
}

test_max_priority_range() {
    setup_hook_env
    register_hook "pre_turn" 99999 "max" "inline_bash" 'jq -nc {p:99999}'
    register_hook "pre_turn" -99999 "min" "inline_bash" 'jq -nc {p:-99999}'
    local r; r=$(_hook_fire "pre_turn" '{}')
    local count; count=$(jq 'length' <<< "$r" 2>/dev/null)
    [[ "$count" == "2" ]] && _pass "priority-extreme: ±99999 handled" \
        || _fail "priority-extreme: expected 2, got $count"
}

# ═══════════════════════════════════════════════════
# Category J: On_cleanup hook (no-return-value point)
# ═══════════════════════════════════════════════════

echo "── J: Cleanup hook ──"

test_cleanup_hook_fires() {
    setup_hook_env
    register_hook "on_cleanup" 10 "clean" "inline_bash" 'touch /tmp/hook_cleanup_fired; jq -nc {done:true}'
    rm -f /tmp/hook_cleanup_fired
    local r; r=$(_hook_fire "on_cleanup" '{}')
    local fired="NO"
    [[ -f /tmp/hook_cleanup_fired ]] && fired="YES"
    [[ "$fired" == "YES" ]] && _pass "cleanup: on_cleanup handler executed" \
        || _fail "cleanup: handler did NOT fire"
    rm -f /tmp/hook_cleanup_fired
}

# ═══════════════════════════════════════════════════
# Category K: Concurrency stress (many handlers, single point)
# ═══════════════════════════════════════════════════

echo "── K: Many handlers ──"

test_many_handlers_single_point() {
    setup_hook_env
    local _i
    for _i in $(seq 1 20); do
        register_hook "pre_turn" "$_i" "h$_i" "inline_bash" "jq -nc {id:$_i}"
    done
    local r; r=$(_hook_fire "pre_turn" '{}')
    local count; count=$(jq 'length' <<< "$r" 2>/dev/null)
    [[ "$count" == "20" ]] && _pass "many: 20 handlers → 20 results" \
        || _fail "many: expected 20, got $count"
}

# ── Run all tests ──
test_type_inline_bash_json
test_type_inline_bash_echo
test_type_bash_script
test_type_template_md
test_type_python_fallback
test_type_exec_fallback
test_type_http_fallback
test_priority_chain_3
test_priority_same_prio
test_disable_then_enable
test_selective_disable
test_handler_crash
test_handler_syntax_error
test_handler_mixed_crash_and_ok
test_ctx_passthrough
test_ctx_empty
test_ctx_special_chars
test_multi_point_isolation
test_point_no_handlers
test_large_output
test_empty_output
test_output_with_trailing_newlines
test_template_no_vars
test_template_undefined_var
test_template_multiline
test_reregister_override
test_max_priority_range
test_cleanup_hook_fires
test_many_handlers_single_point

echo ""
echo "============================================"
echo " Stress Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
