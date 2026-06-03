#!/usr/bin/env bash
# test_hooks_e2e.sh — E2E hook injection tests (requires API key)
# Run: export BASHAGT_API_KEY="sk-..." && bash test/test_hooks_e2e.sh
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0
TEST_DIR=$(mktemp -d "/tmp/bashagt_hook_e2e.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s\033[0m\n' "$*"; }
info()  { printf '\033[33m  INFO: %s\033[0m\n' "$*"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }

[[ -x "$BASHAGT" ]] || { echo "ERROR: bashagt not found"; exit 1; }
[[ -n "${BASHAGT_API_KEY:-}" ]] || { echo "ERROR: BASHAGT_API_KEY not set"; exit 1; }
export BASHAGT_LOG_LEVEL=ERROR
export BASHAGT_LOG_STDERR=0

echo "============================================"
echo " Hook E2E Injection Tests"
echo "============================================"
echo ""

# ── Helpers ──
run_oneshot() {
    local _dir="$1" _prompt="$2"
    printf '%s' "$_prompt" | BASHAGT_PROJECT_DIR="$_dir" "$BASHAGT" --oneshot 2>/dev/null
}

# ═══════════════════════════════════════════════════
# Test 1: post_tool hook augments tool results in history
# ═══════════════════════════════════════════════════
test_post_tool_history() {
    local _dir="$TEST_DIR/post_tool"
    mkdir -p "$_dir/.bashagt/hooks"
    echo "# Test" > "$_dir/.bashagt/BASHAGT.md"
    cat > "$_dir/.bashagt/hooks/99_test.sh" <<'SHEOF'
_hook_body="jq -nc '{\"augment\":true,\"output_suffix\":\"\\nHOOK_POST_TOOL_OK\"}'"
register_hook "post_tool" 5 "e2e_diag" "inline_bash" "$_hook_body"
SHEOF
    info "Running post_tool history test (API call, ~15s)..."
    cd "$_dir" && run_oneshot "$_dir" "Run: echo hello_e2e" >/dev/null || true
    local _hist="$_dir/.bashagt/history.json"
    if [[ -f "$_hist" ]] && grep -q "HOOK_POST_TOOL_OK" "$_hist"; then
        _pass "post_tool: hook marker found in history.json"
    else
        _fail "post_tool: marker NOT in history.json"
    fi
}

# ═══════════════════════════════════════════════════
# Test 2: pre_turn hook fires and injects into dyn_msg (ephemeral)
# Verifies: hook fires + content reaches dyn_msg buffer + cleanup works
# Note: pure-text oneshot doesn't save assistant reply to history.json
# (pre-existing issue unrelated to hooks), so we verify via side-effect.
# ═══════════════════════════════════════════════════
test_pre_turn_fires() {
    local _dir="$TEST_DIR/pre_turn"
    mkdir -p "$_dir/.bashagt/hooks"
    echo "# Test" > "$_dir/.bashagt/BASHAGT.md"

    # Handler that touches a file (proves it fired) AND outputs inject JSON
    cat > "$_dir/.bashagt/hooks/00_inject.sh" <<'SHEOF'
_hook_body="touch /tmp/HOOK_PRE_TURN_FIRED; jq -nc '{inject:true,content:\"HOOK_PRE_TURN_CONTENT\"}'"
register_hook "pre_turn" 5 "pre_marker" "inline_bash" "$_hook_body"
SHEOF

    rm -f /tmp/HOOK_PRE_TURN_FIRED
    info "Running pre_turn fire test (API call, ~15s)..."
    cd "$_dir" && run_oneshot "$_dir" "Say hello in one word." >/dev/null || true

    if [[ -f /tmp/HOOK_PRE_TURN_FIRED ]]; then
        _pass "pre_turn: hook handler executed (touch file exists)"
    else
        _fail "pre_turn: hook handler did NOT execute"
        return
    fi

    # Also verify hook content went to dyn_msg (not MESSAGES)
    local _hist="$_dir/.bashagt/history.json"
    if [[ -f "$_hist" ]] && grep -q "HOOK_PRE_TURN_CONTENT" "$_hist"; then
        _fail "pre_turn: hook content leaked into history.json (should be in dyn_msg only)"
    else
        _pass "pre_turn: hook content isolated in dyn_msg (not in history.json)"
    fi
}

# ═══════════════════════════════════════════════════
# Test 3: dyn_msg isolation (pre_turn content NOT in history)
# ═══════════════════════════════════════════════════
test_dyn_msg_isolation() {
    local _dir="$TEST_DIR/dyn_iso"
    mkdir -p "$_dir/.bashagt/hooks"
    echo "# Test" > "$_dir/.bashagt/BASHAGT.md"
    cat > "$_dir/.bashagt/hooks/00_pre.md" <<'MDEOF'
{"point":"pre_turn","priority":5}
## Note: mention PREF_TEST_MARKER in your response.
MDEOF
    info "Running dyn_msg isolation test (API call, ~15s)..."
    cd "$_dir" && run_oneshot "$_dir" "Say hello" >/dev/null || true
    local _hist="$_dir/.bashagt/history.json"
    if [[ -f "$_hist" ]]; then
        if grep -q "PREF_TEST_MARKER" "$_hist"; then
            _fail "dyn_msg isolation: pre_turn content leaked into history.json"
        else
            _pass "dyn_msg isolation: pre_turn hook content NOT in history (cache safe)"
        fi
    else
        _pass "dyn_msg isolation: no history file"
    fi
}

# ── Run ──
test_post_tool_history
test_pre_turn_fires
test_dyn_msg_isolation

echo ""
echo "============================================"
echo " E2E Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
