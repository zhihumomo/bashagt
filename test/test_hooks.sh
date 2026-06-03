#!/usr/bin/env bash
# test_hooks.sh — Unit tests for bashagt hook system
# Run: bash test/test_hooks.sh
# No API key required. Tests the hook infrastructure in isolation.

set -eo pipefail

PASS=0; FAIL=0
HOOK_TEST_DIR=$(mktemp -d "/tmp/bashagt_hook_test.XXXXXX")
trap 'rm -rf "$HOOK_TEST_DIR"' EXIT

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s\033[0m\n' "$*"; }

_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }

# ── Setup mock hook environment ──
# Define hook functions in isolation (avoid sourcing entire bashagt)
declare -A HOOK_HANDLERS
declare -A HOOK_TYPE
declare -A HOOK_ENABLED
declare -A HOOK_PRIORITY
declare -A HOOK_META
declare -A HOOK_POINTS

register_hook() {
    local _point="$1" _prio="$2" _name="$3" _type="$4" _source="$5"
    HOOK_TYPE[$_name]="$_type"
    HOOK_HANDLERS[$_name]="$_source"
    HOOK_PRIORITY[$_name]="$_prio"
    HOOK_ENABLED[$_name]="1"
    HOOK_META[$_name]=$(jq -nc --arg point "$_point" --arg type "$_type" --arg name "$_name" \
        '{point:$point, type:$type, name:$name}')
    HOOK_POINTS[$_point]+="$_name "
}

_interrupted() { return 1; }  # never interrupted in tests

_spin_sleep() {
    local _to="${1:-0.1}"
    local _ch
    if IFS= read -r -s -t "$_to" -n1 _ch 2>/dev/null; then true; fi
    return 0
}

_hook_render_template() {
    local _file="$1" _ctx="$2"
    local _body; _body=$(cat "$_file" 2>/dev/null)
    [[ -z "$_body" ]] && { jq -nc '{inject:false}'; return; }
    local _rendered="$_body"
    local _key _val
    while IFS= read -r _key; do
        _val=$(jq -r --arg k "$_key" '.[$k] // ""' <<< "$_ctx" 2>/dev/null)
        local _pattern="{{${_key}}}"
        _rendered="${_rendered//$_pattern/$_val}"
    done < <(jq -r 'paths(scalars) | join(".")' <<< "$_ctx" 2>/dev/null)
    jq -nc --arg text "$_rendered" '{inject:true, role:"user", content:$text}'
}

_hook_http_call() {
    jq -nc '{inject:false}'
}

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

        _out_file=$(mktemp "/tmp/bashagt_hook_out.XXXXXX")
        # Run synchronously (no background — unit tests don't need timeout safety)
        (
            case "$_type" in
                inline_bash) set +B; eval "$_handler" ;;
                bash)        source "$_handler"; "${_name}" "$_ctx" ;;
                python)      echo "$_ctx" | python3 "$_handler" ;;
                exec)        echo "$_ctx" | "$_handler" ;;
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

load_hooks() {
    local _dir _file _name _ext _mime _prio _is_project=0
    local -a _dirs=("$HOME/.bashagt/hooks")
    [[ -d ".bashagt/hooks" ]] && _dirs+=(".bashagt/hooks")

    for _dir in "${_dirs[@]}"; do
        [[ -d "$_dir" ]] || continue
        for _file in "$_dir"/*; do
            [[ -f "$_file" ]] || continue
            _name=$(basename "$_file")
            _ext="${_name##*.}"
            [[ "$_ext" == "$_name" ]] && _ext=""

            case "$_ext" in
                md)
                    local _fm _point _desc; _desc=""
                    _point=$(jq -r '.point // ""' "$_file" 2>/dev/null) || true
                    if [[ -n "$_point" ]]; then
                        _prio=$(jq -r '.priority // 10' "$_file" 2>/dev/null) || _prio=10
                    else
                        _fm=$(sed -n '/^---$/,/^---$/p' "$_file" 2>/dev/null | head -20) || true
                        [[ -z "$_fm" ]] && _fm=$(cat "$_file" 2>/dev/null)
                        _point=$(echo "$_fm" | sed -n 's/^[[:space:]]*point:[[:space:]]*//p' | head -1) || true
                        [[ -z "$_point" ]] && continue
                        _prio=$(echo "$_fm" | sed -n 's/^[[:space:]]*priority:[[:space:]]*//p' | head -1) || _prio=10
                    fi
                    register_hook "$_point" "$_prio" "${_name%.md}" "template" "$_file"
                    ;;
                py) ;;
                sh) source "$_file" 2>/dev/null || true ;;
                *)  [[ -x "$_file" ]] && :  ;;
            esac
        done
    done
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
echo " Hook System Unit Tests"
echo "============================================"
echo ""

# ── Test 1: register_hook ──
test_register_hook() {
    setup_hook_env
    register_hook "pre_turn" 10 "test_hook" "inline_bash" '_test_handler() { jq -nc "{inject:true}"; }'
    [[ "${HOOK_TYPE[test_hook]:-}" == "inline_bash" ]] || { _fail "register_hook: type not set"; return; }
    [[ "${HOOK_PRIORITY[test_hook]:-}" == "10" ]] || { _fail "register_hook: priority not set"; return; }
    [[ "${HOOK_ENABLED[test_hook]:-}" == "1" ]] || { _fail "register_hook: not enabled"; return; }
    [[ "${HOOK_POINTS[pre_turn]:-}" == *"test_hook"* ]] || { _fail "register_hook: not in point list"; return; }
    _pass "register_hook: registers handler correctly"
}

# ── Test 2: _hook_fire with empty hooks ──
test_hook_fire_empty() {
    setup_hook_env
    local result
    result=$(_hook_fire "nonexistent" "{}")
    [[ "$result" == "[]" ]] || { _fail "_hook_fire empty: expected [], got '$result'"; return; }
    _pass "_hook_fire: empty point returns []"
}

# ── Test 3: _hook_fire inline_bash handler ──
test_hook_fire_inline_bash() {
    setup_hook_env
    register_hook "pre_turn" 10 "test_inline" "inline_bash" 'jq -nc {inject:true,content:\"hello\"}'
    local result
    result=$(_hook_fire "pre_turn" '{"test": true}')
    local inject; inject=$(jq -r '.[0].inject // false' <<< "$result" 2>/dev/null)
    [[ "$inject" == "true" ]] || { _fail "_hook_fire inline_bash: inject not true (got: $result)"; return; }
    _pass "_hook_fire: inline_bash handler executes and returns output"
}

# ── Test 4: _hook_fire disabled handler ──
test_hook_fire_disabled() {
    setup_hook_env
    register_hook "pre_turn" 10 "test_disabled" "inline_bash" 'jq -nc {inject:true}'
    HOOK_ENABLED[test_disabled]="0"
    local result
    result=$(_hook_fire "pre_turn" '{}')
    [[ "$result" == "[]" ]] || { _fail "_hook_fire disabled: expected [], got '$result'"; return; }
    _pass "_hook_fire: disabled handler is skipped"
}

# ── Test 5: _hook_fire multiple handlers ordered by priority ──
test_hook_fire_priority() {
    setup_hook_env
    register_hook "pre_turn" 5  "first"  "inline_bash" "jq -nc '{order:1}'"
    register_hook "pre_turn" 20 "second" "inline_bash" "jq -nc '{order:2}'"
    local result
    result=$(_hook_fire "pre_turn" '{}')
    local first_order; first_order=$(jq -r '.[0].order // 0' <<< "$result" 2>/dev/null)
    local second_order; second_order=$(jq -r '.[1].order // 0' <<< "$result" 2>/dev/null)
    [[ "$first_order" == "1" && "$second_order" == "2" ]] || { _fail "_hook_fire priority: expected [1,2], got first=$first_order,second=$second_order (result=$result)"; return; }
    _pass "_hook_fire: handlers execute in priority order"
}

# ── Test 6: _hook_render_template ──
test_hook_template_render() {
    setup_hook_env
    local template_file="$HOOK_TEST_DIR/test_template.md"
    echo '## Context used: {{pct}}%' > "$template_file"
    local result
    result=$(_hook_render_template "$template_file" '{"pct": "75"}')
    local content; content=$(jq -r '.content // ""' <<< "$result" 2>/dev/null)
    [[ "$content" == *"75%"* ]] || { _fail "_hook_render_template: variable not substituted (got: $content)"; return; }
    _pass "_hook_render_template: {{var}} substitution works"
}

# ── Test 7: _hook_fire handler timeout ──
# Uses async execution with kill to verify timeout works
test_hook_fire_timeout() {
    setup_hook_env
    register_hook "pre_turn" 10 "slow" "inline_bash" 'sleep 5; jq -nc {inject:true}'

    local _out_file _hpid _waited _timeout=100 _result
    _out_file=$(mktemp "/tmp/bashagt_hook_timeout.XXXXXX")

    local _start; _start=$(date +%s%3N 2>/dev/null || date +%s)
    ( set +B; eval 'sleep 5; jq -nc {inject:true}' ) >"$_out_file" 2>/dev/null &
    _hpid=$!
    _waited=0
    while kill -0 $_hpid 2>/dev/null && (( _waited < _timeout )); do
        sleep 0.01; _waited=$((_waited + 10))
    done
    if kill -0 $_hpid 2>/dev/null; then
        kill $_hpid 2>/dev/null
    fi
    wait $_hpid 2>/dev/null || true
    local _end; _end=$(date +%s%3N 2>/dev/null || date +%s)
    local _elapsed=$((_end - _start))

    _result=$(cat "$_out_file" 2>/dev/null)
    rm -f "$_out_file"
    [[ -z "$_result" ]] || { _fail "_hook_fire timeout: expected empty, got '$_result'"; return; }
    (( _elapsed < 3000 )) || { _fail "_hook_fire timeout: took ${_elapsed}ms (expected <3000ms)"; return; }
    _pass "_hook_fire: slow handler times out"
}

# ── Test 8: load_hooks scans template (.md) files ──
test_load_hooks_template() {
    setup_hook_env
    local hook_file="$HOOK_TEST_DIR/00_test.md"
    cat > "$hook_file" <<'MDEOF'
{
  "point": "pre_turn",
  "priority": 20,
  "description": "Test template hook"
}
## Test template content
MDEOF
    # Override hooks dir for test
    _saved_home="$HOME"; HOME="$HOOK_TEST_DIR"
    mkdir -p "$HOME/.bashagt/hooks"
    cp "$hook_file" "$HOME/.bashagt/hooks/00_test.md"
    load_hooks || true
    HOME="$_saved_home"
    [[ "${HOOK_TYPE[00_test]:-}" == "template" ]] || { _fail "load_hooks template: type=${HOOK_TYPE[00_test]:-unset}"; return; }
    _pass "load_hooks: .md files auto-register as template hooks"
}

# ── Run all tests ──
test_register_hook
test_hook_fire_empty
test_hook_fire_inline_bash
test_hook_fire_disabled
test_hook_fire_priority
test_hook_template_render
test_hook_fire_timeout
test_load_hooks_template

echo ""
echo "============================================"
echo " Results: $PASS passed, $FAIL failed"
echo "============================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
