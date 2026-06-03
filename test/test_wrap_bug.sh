#!/usr/bin/env bash
# test_wrap_bug.sh — Reproduce and verify fix for wrapping display duplication
# Run: bash test/test_wrap_bug.sh

set -uo pipefail
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s\033[0m\n' "$*"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"

echo "============================================"
echo " Line Wrapping / Display Duplication Bug"
echo "============================================"
echo ""

_RENDER_START=$(grep -n '^# ── Unicode display-width calculator' "$BASHAGT" | head -1 | cut -d: -f1)
_RENDER_END=$(grep -n '^_input_render()' "$BASHAGT" | head -1 | cut -d: -f1)
_RENDER_TAIL=$(tail -n +"$_RENDER_END" "$BASHAGT" | grep -n '^}' | head -1 | cut -d: -f1)
_RENDER_END=$((_RENDER_END + _RENDER_TAIL - 1))
sed -n "${_RENDER_START},${_RENDER_END}p" "$BASHAGT" > /tmp/bashagt_render_funcs.sh

_run_test() {
    bash --norc -s 2>/dev/null <<'INNEREOF'
set +e
TERM_WIDTH=50
_IN_PROMPT="  › "
_IN_PROMPT_CONT="  ⋯ "
_IN_LINE=""
_IN_POS=0
_IN_DISPLAY_LINES=1
_IN_CURSOR_ROW=0
_IN_PASTING=0
_IN_HIST_IDX=-1
_IN_SUBMIT=0
_IN_MODE="line"
_in_hist_touch() { _IN_HIST_IDX=-1; }
source /tmp/bashagt_render_funcs.sh

# Use ASCII text that will wrap at TERM_WIDTH=50
# "Endpoint: api.deepseek.com/anthropic " = 40 chars → 2 copies = 80 display width > 50
_LONG="Endpoint: api.deepseek.com/anthropic Endpoint: api.deepseek.com/anthropic"

# ── T1-T3: _input_render state correctness ──

# T1: short line
_IN_LINE="hello"; _IN_POS=${#_IN_LINE}
_input_render >/dev/null 2>&1
if [[ $_IN_CURSOR_ROW -eq 0 && $_IN_DISPLAY_LINES -eq 1 ]]; then
    echo "PASS:T1: short line CURSOR_ROW=0 DISPLAY_LINES=1"
else
    echo "FAIL:T1: short line CURSOR_ROW=$_IN_CURSOR_ROW DISPLAY_LINES=$_IN_DISPLAY_LINES"
fi

# T2: long line CURSOR_ROW > 0
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_input_render >/dev/null 2>&1
if [[ $_IN_CURSOR_ROW -gt 0 ]]; then
    echo "PASS:T2: long line CURSOR_ROW=$_IN_CURSOR_ROW (>0, tracked)"
else
    echo "FAIL:T2: long line CURSOR_ROW=$_IN_CURSOR_ROW (should be >0)"
fi

# T3: long line DISPLAY_LINES > 1
if [[ $_IN_DISPLAY_LINES -gt 1 ]]; then
    echo "PASS:T3: long line DISPLAY_LINES=$_IN_DISPLAY_LINES (>1, tracked)"
else
    echo "FAIL:T3: long line DISPLAY_LINES=$_IN_DISPLAY_LINES (should be >1)"
fi

# ── T4-T5: Full edit cycle (in_buf_redraw path) ──

# T4: After full redraw, state is consistent
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_in_buf_redraw >/dev/null 2>&1
_VIS=$(_in_visual_row_at "$_IN_POS")
if [[ $_IN_CURSOR_ROW -eq $_VIS ]]; then
    echo "PASS:T4: after _in_buf_redraw, CURSOR_ROW=$_IN_CURSOR_ROW == visual_row=$_VIS"
else
    echo "FAIL:T4: after _in_buf_redraw, CURSOR_ROW=$_IN_CURSOR_ROW != visual_row=$_VIS"
fi

# T5: Delete char → guard triggers → in_buf_redraw → state stays consistent
_in_buf_delete_backward >/dev/null 2>&1
_VIS=$(_in_visual_row_at "$_IN_POS")
if [[ $_IN_CURSOR_ROW -eq $_VIS ]]; then
    echo "PASS:T5: after delete, CURSOR_ROW=$_IN_CURSOR_ROW == visual_row=$_VIS"
else
    echo "FAIL:T5: after delete, CURSOR_ROW=$_IN_CURSOR_ROW != visual_row=$_VIS"
fi

# ── T6-T8: Multi-edit sequence with ASCII text ──

_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_in_buf_redraw >/dev/null 2>&1

# Delete 10 chars one by one
for ((_k=0; _k<10; _k++)); do
    _in_buf_delete_backward >/dev/null 2>&1
done

_VIS=$(_in_visual_row_at "$_IN_POS")
if [[ $_IN_CURSOR_ROW -eq $_VIS ]]; then
    echo "PASS:T6: after 10 deletes, CURSOR_ROW=$_IN_CURSOR_ROW == visual_row=$_VIS"
else
    echo "FAIL:T6: after 10 deletes, CURSOR_ROW=$_IN_CURSOR_ROW != visual_row=$_VIS"
fi

# Insert 5 chars at cursor
for ((_k=0; _k<5; _k++)); do
    _in_buf_insert "X" >/dev/null 2>&1
done
_VIS=$(_in_visual_row_at "$_IN_POS")
if [[ $_IN_CURSOR_ROW -eq $_VIS ]]; then
    echo "PASS:T7: after 5 inserts, CURSOR_ROW=$_IN_CURSOR_ROW == visual_row=$_VIS"
else
    echo "FAIL:T7: after 5 inserts, CURSOR_ROW=$_IN_CURSOR_ROW != visual_row=$_VIS"
fi

# ── T8: Transition to short line and back ──
_IN_LINE="short"; _IN_POS=5
_input_render >/dev/null 2>&1
if [[ $_IN_CURSOR_ROW -eq 0 ]]; then
    echo "PASS:T8: back to short line, CURSOR_ROW=0 (recovered)"
else
    echo "FAIL:T8: back to short line, CURSOR_ROW=$_IN_CURSOR_ROW"
fi

# ── T9: Short → Long transition with _in_buf_insert ──
_IN_LINE=""; _IN_POS=0
# Build up long line char by char
for ((_j=0; _j<${#_LONG}; _j++)); do
    _in_buf_insert "${_LONG:_j:1}" >/dev/null 2>&1
done
_VIS=$(_in_visual_row_at "$_IN_POS")
if [[ $_IN_CURSOR_ROW -eq $_VIS ]]; then
    echo "PASS:T9: char-by-char insert to long line, CURSOR_ROW=$_IN_CURSOR_ROW == $_VIS"
else
    echo "FAIL:T9: char-by-char insert, CURSOR_ROW=$_IN_CURSOR_ROW != $_VIS"
fi

# ── T10: Verify ANSI output does NOT have duplicate prompts ──
# Capture the actual ANSI output of _in_buf_redraw for a long line
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_OUT=$(_in_buf_redraw 2>&1 || true)
# Count occurrences of prompt in output (should appear exactly once)
_PC=$(echo "$_OUT" | grep -oF "$_IN_PROMPT" | wc -l)
if [[ $_PC -eq 1 ]]; then
    echo "PASS:T10: prompt appears $_PC time(s) in render output"
else
    echo "FAIL:T10: prompt appears $_PC time(s) in render output (expected 1)"
fi

# ── T11: After one edit, prompt still appears once ──
_in_buf_delete_backward >/dev/null 2>&1
# Reset to long, render, then capture edit output
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_in_buf_redraw >/dev/null 2>&1  # first render to set state
_OUT=$(_in_buf_delete_backward 2>&1 || true)
_PC=$(echo "$_OUT" | grep -oF "$_IN_PROMPT" | wc -l)
# _in_buf_delete_backward calls _in_buf_redraw (via guard), which outputs prompt
if [[ $_PC -le 1 ]]; then
    echo "PASS:T11: delete re-render has $_PC prompt(s) (≤1)"
else
    echo "FAIL:T11: delete re-render has $_PC prompt(s)"
fi
INNEREOF
}

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
        PASS:*) _pass "${line#PASS:}" ;;
        FAIL:*) _fail "${line#FAIL:}" ;;
        *)      echo "  $line" ;;
    esac
done < <(_run_test)

rm -f /tmp/bashagt_render_funcs.sh

echo ""
echo "============================================"
echo " Wrap Bug Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
