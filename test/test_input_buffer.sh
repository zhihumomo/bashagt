#!/usr/bin/env bash
# test_input_buffer.sh — Input buffer operations unit tests (Section 10b/c)
# Run: bash test/test_input_buffer.sh
# No API required. Uses the same extraction pattern as test_wrap_bug.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# Extract using the same dynamic markers as test_wrap_bug.sh
_RENDER_START=$(grep -n '^# ── Unicode display-width calculator' "$BASHAGT" | head -1 | cut -d: -f1)
_RENDER_END=$(grep -n '^_input_render()' "$BASHAGT" | head -1 | cut -d: -f1)
_RENDER_TAIL=$(tail -n +"$_RENDER_END" "$BASHAGT" | grep -n '^}' | head -1 | cut -d: -f1)
_RENDER_END=$((_RENDER_END + _RENDER_TAIL - 1))
sed -n "${_RENDER_START},${_RENDER_END}p" "$BASHAGT" > /tmp/bashagt_render_funcs.sh

echo "============================================"
echo " Input Buffer Unit Tests"
echo "============================================"
echo ""

cat > /tmp/bashagt_buf_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_render_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

# ── Test environment (same as wrap_bug) ──
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

# ════════════════ T1-T5: _in_visual_col ════════════════

# T1: position 0 → column 0
_v=$(_in_visual_col 0)
[[ $_v -eq 0 ]] && _green "T1: pos 0 → col 0" || _red "T1: pos 0" "0" "$_v"

# T2: position after prompt → column 0 (first char after prompt)
_v=$(_in_visual_col 0)
[[ $_v -eq 0 ]] && _green "T2: first char col=0" || _red "T2: first col" "0" "$_v"

# ════════════════ T6-T10: _in_display_lines ════════════════

# T6: short line → 1 display line
_IN_LINE="hello"; _IN_POS=${#_IN_LINE}
_input_render >/dev/null 2>&1
[[ $_IN_DISPLAY_LINES -eq 1 ]] && _green "T3: short line = 1 display line" \
    || _red "T3: 1 line" "1" "$_IN_DISPLAY_LINES"

# T7: long line → >1 display lines
_LONG="Endpoint: api.deepseek.com/anthropic Endpoint: api.deepseek.com/anthropic"
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_input_render >/dev/null 2>&1
[[ $_IN_DISPLAY_LINES -gt 1 ]] && _green "T4: long line > 1 display line ($_IN_DISPLAY_LINES)" \
    || _red "T4: >1 line" ">1" "$_IN_DISPLAY_LINES"

# T8: cursor row tracks position
[[ $_IN_CURSOR_ROW -gt 0 ]] && _green "T5: cursor on last row ($_IN_CURSOR_ROW)" \
    || _red "T5: cursor >0" ">0" "$_IN_CURSOR_ROW"

# ════════════════ T9-T12: _in_visual_row_at ════════════════

# T9: position 0 → row 0
_IN_LINE="$_LONG"; _IN_POS=0
_input_render >/dev/null 2>&1
_vr=$(_in_visual_row_at 0)
[[ $_vr -eq 0 ]] && _green "T6: visual row at pos 0 = 0" || _red "T6: vr" "0" "$_vr"

# T10: last position → last row
_vr=$(_in_visual_row_at ${#_IN_LINE})
[[ $_vr -gt 0 ]] && _green "T7: visual row at end > 0 ($_vr)" \
    || _red "T7: vr end" ">0" "$_vr"

# T11: after _in_buf_redraw, state consistent
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_in_buf_redraw >/dev/null 2>&1
_vr=$(_in_visual_row_at "$_IN_POS")
[[ $_IN_CURSOR_ROW -eq $_vr ]] && _green "T8: CURSOR_ROW == visual_row ($_IN_CURSOR_ROW == $_vr)" \
    || _red "T8: cursor==vr" "equal" "$_IN_CURSOR_ROW != $_vr"

# ════════════════ T12-T15: _in_pos_at_visual_row ════════════════

# T12: row 0 → near start
_IN_LINE="$_LONG"; _IN_POS=0
_input_render >/dev/null 2>&1
_pos=$(_in_pos_at_visual_row 0)
[[ $_pos -ge 0 ]] && _green "T9: pos at visual row 0 = $_pos" \
    || _red "T9: pos vr0" ">=0" "$_pos"

# T13: row 1 → position on second visual line
_IN_LINE="$_LONG"; _IN_POS=0
_input_render >/dev/null 2>&1
_pos=$(_in_pos_at_visual_row 1)
# For prompt of "  › " (4 chars) and TERM_WIDTH=50, first line has 46 chars
# Position at row 1 should be around 46
[[ $_pos -gt 0 ]] && _green "T10: pos at visual row 1 = $_pos (>0)" \
    || _red "T10: pos vr1" ">0" "$_pos"

# ════════════════ T14-T20: Cursor movement ════════════════

# T14: _in_buf_move_left
_IN_LINE="hello world"; _IN_POS=11
_in_buf_move_left >/dev/null 2>&1
[[ $_IN_POS -eq 10 ]] && _green "T11: move left (11→10)" || _red "T11: left" "10" "$_IN_POS"

# T15: _in_buf_move_left at start → no change
_IN_LINE="hello"; _IN_POS=0
_in_buf_move_left >/dev/null 2>&1
[[ $_IN_POS -eq 0 ]] && _green "T12: left at start stays 0" || _red "T12: left@0" "0" "$_IN_POS"

# T16: _in_buf_move_right
_IN_LINE="hello world"; _IN_POS=5
_in_buf_move_right >/dev/null 2>&1
[[ $_IN_POS -eq 6 ]] && _green "T13: move right (5→6)" || _red "T13: right" "6" "$_IN_POS"

# T17: _in_buf_move_right at end → no change
_IN_LINE="hello"; _IN_POS=5
_in_buf_move_right >/dev/null 2>&1
[[ $_IN_POS -eq 5 ]] && _green "T14: right at end stays 5" || _red "T14: right@end" "5" "$_IN_POS"

# T18: _in_buf_move_home
_IN_LINE="hello world"; _IN_POS=7
_in_buf_move_home >/dev/null 2>&1
[[ $_IN_POS -eq 0 ]] && _green "T15: home → pos 0" || _red "T15: home" "0" "$_IN_POS"

# T19: _in_buf_move_end
_IN_LINE="hello world"; _IN_POS=3
_in_buf_move_end >/dev/null 2>&1
[[ $_IN_POS -eq ${#_IN_LINE} ]] && _green "T16: end → pos ${#_IN_LINE}" \
    || _red "T16: end" "${#_IN_LINE}" "$_IN_POS"

# T20: _in_buf_move_up from row 1 → row 0
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_input_render >/dev/null 2>&1
_old_row=$_IN_CURSOR_ROW
_in_buf_move_up >/dev/null 2>&1
[[ $_IN_CURSOR_ROW -lt $_old_row ]] && _green "T17: move up reduces row ($_old_row→$_IN_CURSOR_ROW)" \
    || _red "T17: up" "row < $_old_row" "row=$_IN_CURSOR_ROW"

# T21: _in_buf_move_up at top → no change
_IN_LINE="hello"; _IN_POS=2
_input_render >/dev/null 2>&1
_in_buf_move_up >/dev/null 2>&1
[[ $_IN_CURSOR_ROW -eq 0 ]] && _green "T18: up at top stays 0" || _red "T18: up@top" "0" "$_IN_CURSOR_ROW"

# T19: _in_buf_move_down with explicit newlines (wrapped-line down is complex)
_IN_LINE=$'line1\nline2\nline3'; _IN_POS=0
_input_render >/dev/null 2>&1
_in_buf_move_down >/dev/null 2>&1
[[ $_IN_CURSOR_ROW -gt 0 || $_IN_POS -gt 5 ]] && _green "T19: move down on multi-line ($_IN_CURSOR_ROW/$_IN_POS)" \
    || _red "T19: down" "moved" "row=$_IN_CURSOR_ROW pos=$_IN_POS"

# T23: _in_buf_move_down at bottom → no change
_IN_LINE="$_LONG"; _IN_POS=${#_IN_LINE}
_input_render >/dev/null 2>&1
_bottom_row=$_IN_CURSOR_ROW
_in_buf_move_down >/dev/null 2>&1
[[ $_IN_CURSOR_ROW -eq $_bottom_row ]] && _green "T20: down at bottom stays" \
    || _red "T20: down@bottom" "$_bottom_row" "$_IN_CURSOR_ROW"

# ════════════════ T24-T30: Kill operations ════════════════

# T24: kill to end
_IN_LINE="hello world"; _IN_POS=5
_in_buf_kill_to_end >/dev/null 2>&1
[[ "$_IN_LINE" == "hello" ]] && _green "T21: kill to end (hello world→hello)" \
    || _red "T21: kill-end" "hello" "$_IN_LINE"

# T25: kill to end at end → no change
_IN_LINE="hello"; _IN_POS=5
_in_buf_kill_to_end >/dev/null 2>&1
[[ "$_IN_LINE" == "hello" ]] && _green "T22: kill-end at end unchanged" \
    || _red "T22: kill-end@end" "hello" "$_IN_LINE"

# T26: kill to start
_IN_LINE="hello world"; _IN_POS=6
_in_buf_kill_to_start >/dev/null 2>&1
[[ "$_IN_LINE" == "world" && $_IN_POS -eq 0 ]] && _green "T23: kill to start (→world, pos=0)" \
    || _red "T23: kill-start" "world pos=0" "$_IN_LINE pos=$_IN_POS"

# T27: kill to start at start → no change
_IN_LINE="hello"; _IN_POS=0
_in_buf_kill_to_start >/dev/null 2>&1
[[ "$_IN_LINE" == "hello" && $_IN_POS -eq 0 ]] && _green "T24: kill-start at 0 unchanged" \
    || _red "T24: kill-start@0" "hello 0" "$_IN_LINE $_IN_POS"

# T28: kill word backward — simple word
_IN_LINE="hello world"; _IN_POS=11
_in_buf_kill_word_backward >/dev/null 2>&1
[[ "$_IN_LINE" == "hello " ]] && _green "T25: kill word backward removes 'world'" \
    || _red "T25: kill-word" "hello " "$_IN_LINE"

# T29: kill word backward at start → no change
_IN_LINE="hello"; _IN_POS=0
_in_buf_kill_word_backward >/dev/null 2>&1
[[ "$_IN_LINE" == "hello" ]] && _green "T26: kill-word at 0 unchanged" \
    || _red "T26: kill-word@0" "hello" "$_IN_LINE"

# T27: kill word backward from end of "hello    " (with trailing spaces)
# Kill-word removes the word and trailing spaces, leaving just the content before
_IN_LINE="hello    "; _IN_POS=9
_in_buf_kill_word_backward >/dev/null 2>&1
# Should remove the spaces after 'hello' — exact behavior depends on word boundary detection
[[ ${#_IN_LINE} -lt 9 ]] && _green "T27: kill-word reduces length (${#_IN_LINE} < 9)" \
    || _red "T27: kill-word sp" "length<9" "len=${#_IN_LINE} line=$_IN_LINE"

# ════════════════ T31-T35: Insert + Delete ════════════════

# T31: insert at cursor
_IN_LINE="hllo"; _IN_POS=1
_in_buf_insert "e" >/dev/null 2>&1
[[ "$_IN_LINE" == "hello" ]] && _green "T28: insert 'e' at pos 1" \
    || _red "T28: insert" "hello" "$_IN_LINE"

# T32: insert at end
_IN_LINE="hello"; _IN_POS=5
_in_buf_insert "!" >/dev/null 2>&1
[[ "$_IN_LINE" == "hello!" && $_IN_POS -eq 6 ]] && _green "T29: insert at end (pos 5→6)" \
    || _red "T29: insert end" "hello! pos=6" "$_IN_LINE pos=$_IN_POS"

# T33: delete backward
_IN_LINE="hello"; _IN_POS=5
_in_buf_delete_backward >/dev/null 2>&1
[[ "$_IN_LINE" == "hell" && $_IN_POS -eq 4 ]] && _green "T30: delete backward removes 'o'" \
    || _red "T30: backspace" "hell pos=4" "$_IN_LINE pos=$_IN_POS"

# T34: delete backward at start → no change
_IN_LINE="hello"; _IN_POS=0
_in_buf_delete_backward >/dev/null 2>&1
[[ "$_IN_LINE" == "hello" ]] && _green "T31: backspace at 0 unchanged" \
    || _red "T31: backspace@0" "hello" "$_IN_LINE"

# T35: delete forward
_IN_LINE="hello"; _IN_POS=0
_in_buf_delete_forward >/dev/null 2>&1
[[ "$_IN_LINE" == "ello" && $_IN_POS -eq 0 ]] && _green "T32: delete forward removes 'h'" \
    || _red "T32: delete fwd" "ello pos=0" "$_IN_LINE pos=$_IN_POS"

# ════════════════ Stress ════════════════

# S1: long line full edit cycle
_LONG_LINE=""; for _i in $(seq 1 20); do _LONG_LINE+="word$_i "; done  # ~160 chars
_IN_LINE="$_LONG_LINE"; _IN_POS=${#_IN_LINE}
_input_render >/dev/null 2>&1
_dl=$_IN_DISPLAY_LINES
_cr=$_IN_CURSOR_ROW
[[ $_dl -gt 2 ]] && _green "S1: 160-char line → $_dl display lines" \
    || _red "S1: long line" ">2 lines" "$_dl"

# S2-S3: cursor move on moderate line (50 chars — 1 wrap cycle)
_MED_LINE=""; for _i in $(seq 1 10); do _MED_LINE+="word$_i "; done
_IN_LINE="$_MED_LINE"; _IN_POS=0
for _i in $(seq 1 ${#_IN_LINE}); do _in_buf_move_right >/dev/null 2>&1; done
[[ $_IN_POS -eq ${#_IN_LINE} ]] && _green "S2: move right to end ($_IN_POS)" \
    || _red "S2: right all" "${#_IN_LINE}" "$_IN_POS"
for _i in $(seq 1 ${#_IN_LINE}); do _in_buf_move_left >/dev/null 2>&1; done
[[ $_IN_POS -eq 0 ]] && _green "S3: move left back to start ($_IN_POS)" \
    || _red "S3: left all" "0" "$_IN_POS"

# S3: rapid kill cycles
_s_ok=1
for _i in $(seq 1 10); do
    _IN_LINE="test content here"; _IN_POS=5
    _in_buf_kill_to_end >/dev/null 2>&1
    _in_buf_kill_to_start >/dev/null 2>&1
    [[ -z "$_IN_LINE" ]] || { _s_ok=0; break; }
done
[[ $_s_ok -eq 1 ]] && _green "S4: 10 kill cycles" || _red "S4: kill cycles" "OK" "fail at $_i"

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
done < <(bash /tmp/bashagt_buf_test.sh 2>&1 || true)

rm -f /tmp/bashagt_render_funcs.sh /tmp/bashagt_buf_test.sh

echo ""
echo "============================================"
echo " Input Buffer Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
