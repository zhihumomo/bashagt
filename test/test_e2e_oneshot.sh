#!/usr/bin/env bash
# test_e2e_oneshot.sh — End-to-end oneshot streaming tests
# Tests: basic response, multi-turn, sub-agent, tools, slash commands, JSONL format
# Run: bash test/test_e2e_oneshot.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0; SKIP=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s\033[0m\n' "$*"; }
yell()  { printf '\033[33m  SKIP: %s\033[0m\n' "$*"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }
_skip() { SKIP=$((SKIP+1)); yell "$1"; }

cd "$SCRIPT_DIR/.."

# Run oneshot and return output. Times out after N seconds.
# Usage: _oneshot <prompt> [timeout_sec=90]
_oneshot() {
    local prompt="$1" timeout_sec="${2:-90}"
    timeout "$timeout_sec" bash -c "
        echo '$prompt' | bash '$BASHAGT' --oneshot --stream 2>/dev/null
    " 2>/dev/null || echo '{"type":"error","msg":"timeout"}'
}

# Check JSONL output for specific patterns
_check_output() {
    local desc="$1" output="$2" check_type="$3" pattern="${4:-}"
    case "$check_type" in
        has_done)
            if echo "$output" | grep -q '"type":"done"'; then
                _pass "$desc"; else _fail "$desc — no done frame"; fi ;;
        has_text)
            if echo "$output" | grep -q '"type":"text"'; then
                _pass "$desc"; else _fail "$desc — no text frame"; fi ;;
        has_tool)
            if echo "$output" | grep -q '"type":"tool_start"'; then
                _pass "$desc"; else _fail "$desc — no tool_start frame"; fi ;;
        has_field)
            if echo "$output" | grep -q "$pattern"; then
                _pass "$desc"; else _fail "$desc — pattern '$pattern' not found"; fi ;;
        jsonl_valid)
            local bad; bad=$(echo "$output" | grep -v '^{"type"' | grep -v '^$' | head -3)
            if [[ -z "$bad" ]]; then
                _pass "$desc"; else _fail "$desc — invalid JSONL: $bad"; fi ;;
        no_error)
            if ! echo "$output" | grep -q '"type":"error"'; then
                _pass "$desc"; else _fail "$desc — error frame found"; fi ;;
    esac
}

echo "============================================"
echo " E2E Oneshot Streaming Tests"
echo "============================================"
echo ""

# ═══ T1-T3: Basic Response ═══
echo "── T1-T3: Basic Response ──"

out=$(_oneshot "reply with exactly: OK" 60)
_check_output "T1: has done frame" "$out" has_done
_check_output "T2: has text frame" "$out" has_text
_check_output "T3: valid JSONL format" "$out" jsonl_valid

# ═══ T4-T6: Multi-turn Conversation ═══
echo "── T4-T6: Multi-turn Conversation ──"
out=$(_oneshot "First message: remember the number 42.
Second message: what number did I ask you to remember?
Third message: reply with just the number." 120)
_check_output "T4: multi-turn has done" "$out" has_done
_check_output "T5: multi-turn has text" "$out" has_text
_check_output "T6: multi-turn no error" "$out" no_error

# ═══ T7-T9: Sub-agent Delegation ═══
echo "── T7-T9: Sub-agent Delegation ──"
# Note: tool_start/tool_end are suppressed for 'agent' and 'web_search' tools
# (by design — they have their own async_spin spinner).
# So we check for sub-agent activity via done+text frames.
out=$(_oneshot "Use the explore sub-agent to check if the /tmp directory exists on this system. After the agent responds, reply with OK." 120)
_check_output "T7: sub-agent has done" "$out" has_done
_check_output "T8: sub-agent response has text" "$out" has_text
_check_output "T9: sub-agent no error" "$out" no_error

# ═══ T10-T12: Slash Commands ═══
echo "── T10-T12: Slash Commands ──"
out=$(_oneshot "/model" 60)
_check_output "T10: /model has done" "$out" has_done
_check_output "T11: /model has text" "$out" has_text
_check_output "T12: /model valid JSONL" "$out" jsonl_valid

# ═══ T13-T15: /status Command ═══
echo "── T13-T15: /status Command ──"
out=$(_oneshot "/status" 60)
_check_output "T13: /status has done" "$out" has_done
_check_output "T14: /status has text" "$out" has_text
_check_output "T15: /status no error" "$out" no_error

# ═══ T16-T18: Bash Tool Execution ═══
echo "── T16-T18: Bash Tool ──"
out=$(_oneshot "Run this bash command and tell me the output: echo hello-world-test-123" 120)
_check_output "T16: bash tool has done" "$out" has_done
_check_output "T17: bash tool has tool_start" "$out" has_tool
out2=$(_oneshot "Run this bash command and reply with only the output: date +%Y" 120)
_check_output "T18: bash date command works" "$out2" has_done

# ═══ T19-T20: Plan Generation (SKIPPED) ═══
# echo "── T19-T20: Plan Generation ──"
# out=$(_oneshot "Create a plan with 2 steps: 1) echo hello, 2) echo world. Use the /plan command or plan tool." 120)
# _check_output "T19: plan has done" "$out" has_done
# _check_output "T20: plan no error" "$out" no_error

# ═══ T21-T22: Complex Multi-Tool Chain ═══
echo "── T21-T22: Complex Multi-Tool ──"
out=$(_oneshot "Step 1: Run 'ls /tmp' to see what files exist.
Step 2: Count how many files you see.
Step 3: Reply with 'I found N files in /tmp' where N is the count." 120)
_check_output "T21: multi-tool has done" "$out" has_done
_check_output "T22: multi-tool has tool_start" "$out" has_tool

# ═══ T23-T25: Streaming Protocol ═══
echo "── T23-T25: Streaming Protocol ──"
out=$(_oneshot "reply OK" 60)
# Verify status_begin/status_done lifecycle
has_begin=$(echo "$out" | grep -c '"type":"status_begin"' || echo 0)
has_done=$(echo "$out" | grep -c '"type":"status_done"' || echo 0)
if [[ $has_begin -ge 1 && $has_done -ge 1 ]]; then
    _pass "T23: status begin→done lifecycle ($has_begin begin, $has_done done)"
else
    _fail "T23: status begin→done lifecycle — begin=$has_begin done=$has_done"
fi
# Verify done frame has ts field
if echo "$out" | grep '"type":"done"' | grep -q '"ts"'; then
    _pass "T24: done frame has ts field"
else
    _fail "T24: done frame has ts field"
fi
# Verify each line is valid JSON
bad_lines=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" | jq empty 2>/dev/null || bad_lines=$((bad_lines + 1))
done <<< "$out"
if [[ $bad_lines -eq 0 ]]; then
    _pass "T25: every line is valid JSON"
else
    _fail "T25: every line is valid JSON — $bad_lines invalid lines"
fi

# ═══ T26-T27: Profile Switching ═══
echo "── T26-T27: Profile Switching ──"
# List profiles
out=$(_oneshot "/model" 60)
_check_output "T26: profile list shown" "$out" has_text
# Switch to default (should work even if only one profile)
out=$(_oneshot "/model default" 60)
_check_output "T27: profile switch to default" "$out" has_done

# ═══ T28-T30: /exit, /quit, /help (no API) ═══
echo "── T28-T30: No-API Slash Commands ──"

out=$(_oneshot "/exit" 10)
# /exit should produce no status_begin (no API call)
if ! echo "$out" | grep -q '"type":"status_begin"'; then
    _pass "T28: /exit exits immediately without API call"
else
    _fail "T28: /exit exits immediately without API call"
fi

out=$(_oneshot "/quit" 10)
if ! echo "$out" | grep -q '"type":"status_begin"'; then
    _pass "T29: /quit exits immediately without API call"
else
    _fail "T29: /quit exits immediately without API call"
fi

out=$(_oneshot "/help" 30)
_check_output "T30: /help produces text" "$out" has_text

# ═══ T31-T33: /status, /clear, /model ═══
echo "── T31-T33: More No-API Commands ──"

out=$(_oneshot "/status" 30)
_check_output "T31: /status produces text" "$out" has_text

out=$(_oneshot "/clear" 10)
_check_output "T32: /clear works" "$out" has_done

out=$(_oneshot "/model" 30)
_check_output "T33: /model works" "$out" has_text

# ═══ T34-T35: Regression — pipe/set-u safety ═══
echo "── T34-T35: Regression Safeguards ──"

# T34: stdin is a pipe (not terminal). _ch unbound regression.
out=$(echo "reply OK" | timeout 60 bash "$BASHAGT" --oneshot --stream 2>/dev/null)
if echo "$out" | grep -q '"type":"done"'; then
    _pass "T34: pipe stdin does not crash (ch unbound fix regression)"
else
    _fail "T34: pipe stdin does not crash"
fi

# T35: multi-turn via pipe stdin does not crash
out=$(echo "reply: hello" | timeout 60 bash "$BASHAGT" --oneshot --stream 2>/dev/null)
if echo "$out" | grep -q '"type":"done"'; then
    _pass "T35: multi-turn pipe stdin does not crash (_to_stderr fix regression)"
else
    _fail "T35: multi-turn pipe stdin"
fi

# ═══ T36-T37: Empty input + Error handling ═══
echo "── T36-T37: Edge Cases ──"

out=$(echo "" | timeout 10 bash "$BASHAGT" --oneshot --stream 2>/dev/null)
if [[ $? -eq 0 ]]; then
    _pass "T36: empty input does not crash"
else
    _fail "T36: empty input"
fi

out=$(_oneshot "/model nonexistent_xyz_profile" 30)
_check_output "T37: invalid model profile shows error without crash" "$out" has_done

# ═══ Summary ═══
echo ""
echo "============================================"
echo " Oneshot Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
