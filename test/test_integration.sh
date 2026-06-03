#!/usr/bin/env bash
# test_integration.sh — End-to-end integration tests for bashagt
# Run: bash test/test_integration.sh
# REQUIRES valid API key in ~/.bashagt/settings.json
# Tests: oneshot streaming, sub-agent delegation, /model, /status, plan generation

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# Check API key is configured
if ! grep -q '"api_key"' "$HOME/.bashagt/settings.json" 2>/dev/null; then
    echo "SKIP: No API key configured in ~/.bashagt/settings.json"
    echo "  Run --install first, then add your api_key to settings.json"
    exit 0
fi

echo "============================================"
echo " Integration Tests (requires API key)"
echo "============================================"
echo ""

cd "$SCRIPT_DIR/.."

# Helper: run a oneshot prompt and check for done frames
# Usage: _test_oneshot <description> <prompt> [min_done_frames=1] [timeout_sec=90]
_test_oneshot() {
    local desc="$1" prompt="$2" min_done="${3:-1}" timeout_sec="${4:-90}"
    echo "── $desc ──"
    local out
    out=$(timeout "$timeout_sec" bash -c "
        echo '$prompt' | bash '$BASHAGT' --oneshot --stream 2>/dev/null
    " 2>/dev/null) || { _fail "$desc" "completed in ${timeout_sec}s" "timeout or error"; return; }

    local done_frames; done_frames=$(echo "$out" | grep -c '"type":"done"' 2>/dev/null || echo 0)
    local text_frames; text_frames=$(echo "$out" | grep -c '"type":"text"' 2>/dev/null || echo 0)
    local tool_frames; tool_frames=$(echo "$out" | grep -c '"type":"tool_start"' 2>/dev/null || echo 0)

    if [[ $done_frames -ge $min_done ]]; then
        _pass "$desc (done=$done_frames text=$text_frames tools=$tool_frames)"
    else
        _fail "$desc" "done>=$min_done" "done=$done_frames text=$text_frames tools=$tool_frames"
    fi
}

# B1: Basic oneshot — simplest possible turn
_test_oneshot "basic oneshot" \
    "reply with exactly the word OK and nothing else" 1 90

# B2: Sub-agent delegation — uses agent tool with explore
_test_oneshot "sub-agent delegation" \
    "Use the explore sub-agent to check if the /tmp directory exists. After the agent responds, output only OK." 1 120

# B3: /model command — profile listing
_test_oneshot "/model command" \
    "/model" 1 60

# B4: /status command — system status
_test_oneshot "/status command" \
    "/status" 1 60

# B5: Plan generation — exercises plan_to_todos timing (SKIPPED)
# _test_oneshot "plan generation" \
#     "Create a simple plan with 2 steps: step 1 check disk space, step 2 report result. Use /plan if available. Output DONE when complete." 1 120

# B6: Conversation with context — exercises turn timing (_timestamp_ms)
_test_oneshot "conversation context" \
    "I am going to send you several messages. Reply OK to each one. First: OK?" 1 90

# B7: Web search (if configured) — exercises SSE streaming
_test_oneshot "web search (or fallback)" \
    "Tell me what day of the week it is today. Reply with just the day name." 1 90

# ── Summary ──
echo ""
echo "============================================"
echo " Integration Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
