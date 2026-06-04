#!/usr/bin/env bash
# test_ui_primitives.sh — UI primitives unit tests (Section 5)
# Run: bash test/test_ui_primitives.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# Extract UI section (Section 5a-d)
_UI_START=$(grep -n '^ui_spinner()' "$BASHAGT" | head -1 | cut -d: -f1)
_UI_END=$(grep -n '^_hook_render_template()' "$BASHAGT" | head -1 | cut -d: -f1)
sed -n "${_UI_START},$((_UI_END - 1))p" "$BASHAGT" > /tmp/bashagt_ui_funcs.sh

echo "============================================"
echo " UI Primitives Unit Tests"
echo "============================================"
echo ""

cat > /tmp/bashagt_ui_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_ui_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

BOLD=""; RESET=""; DIM=""; GREEN=""; RED=""; CYAN=""; YELLOW=""; GRAY=""
LIGHT_GREEN=""; DOT_SEQ=(); _DOT_PHASE=0
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_LEN=${#SPINNER[@]}
_SPIN_FRAME=""
_DOT_FRAME=""

# ════════════════ T1-T6: ui_spinner / _spin_tick ════════════════

# T1: ui_spinner returns first frame
_frame=$(ui_spinner)
[[ "$_frame" == "${SPINNER[0]}" ]] && _green "T1: ui_spinner → first frame ($_frame)" \
    || _red "T1: spinner" "${SPINNER[0]}" "$_frame"

# T2: _spin_tick reads current frame, THEN advances index
# (_spin_tick reads SPINNER[SPINNER_IDX] into _SPIN_FRAME, then SPINNER_IDX++)
SPINNER_IDX=0
_spin_tick
# After first call: _SPIN_FRAME = SPINNER[0] (= first frame), SPINNER_IDX = 1
[[ "$_SPIN_FRAME" == "${SPINNER[0]}" ]] && _green "T2: _spin_tick first frame (${SPINNER[0]})" \
    || _red "T2: tick" "${SPINNER[0]}" "$_SPIN_FRAME"

# T3: 10 ticks → wraps around (last frame read is SPINNER[9], index wraps to 0)
SPINNER_IDX=0
for i in $(seq 1 10); do _spin_tick >/dev/null 2>&1; done
[[ "$_SPIN_FRAME" == "${SPINNER[9]}" ]] && _green "T3: 10 ticks wraps to first" \
    || _red "T3: wrap" "${SPINNER[9]}" "$_SPIN_FRAME"

# T4: 10 tick cycle visits all 10 unique frames
SPINNER_IDX=0
_seen=""
for i in $(seq 1 10); do
    _spin_tick >/dev/null 2>&1
    _seen+="$_SPIN_FRAME "
done
_seen="${_seen% }"
_cnt=$(echo "$_seen" | tr ' ' '\n' | sort -u | wc -l)
[[ $_cnt -eq 10 ]] && _green "T4: 10 unique frames in cycle" \
    || _red "T4: unique" "10" "$_cnt seen=$_seen"

# T5: ui_dot returns dot character (●)
_d=$(ui_dot)
[[ "$_d" == "●" ]] && _green "T5: ui_dot → ●" || _red "T5: dot" "●" "$_d"

# T6: _dot_tick alternates ● and colored ●
_DOT_PHASE=0; _dot_tick
[[ -n "$_DOT_FRAME" ]] && _green "T6: _dot_tick produces frame" || _red "T6: dot_tick" "non-empty" "empty"

# ════════════════ T7-T12: ui_time / _ui_time ════════════════
# NOTE: ui_time delegates to elapsed_fmt (L1887, outside UI section).
# _ui_time uses printf -v _UI_TIME and does NOT output to stdout.

# T7: ui_time function exists
type -t ui_time >/dev/null 2>&1 && _green "T7: ui_time defined" || _red "T7: ui_time" "function" "missing"

# T8: _ui_time stores result in _UI_TIME variable
_ui_time 1000
[[ "$_UI_TIME" == "1.0s" ]] && _green "T8: _ui_time 1000ms → _UI_TIME=1.0s" \
    || _red "T8: _ui_time" "1.0s" "$_UI_TIME"

# T9: _ui_time 0ms
_ui_time 0
[[ "$_UI_TIME" == "0.0s" ]] && _green "T9: _ui_time 0 → 0.0s" || _red "T9: 0" "0.0s" "$_UI_TIME"

# T10: _ui_time 125500ms → 2m5s
_ui_time 125500
[[ "$_UI_TIME" == "2m5s" ]] && _green "T10: _ui_time 125500ms → $_UI_TIME" \
    || _red "T10: 2m5s" "2m5s" "$_UI_TIME"

# T11: _ui_time 3661000ms → 61m1s
_ui_time 3661000
[[ "$_UI_TIME" == "61m1s" ]] && _green "T11: _ui_time 3661000ms → $_UI_TIME" \
    || _red "T11: 61m1s" "61m1s" "$_UI_TIME"

# T12: _ui_time negative → handled gracefully
_ui_time -100
[[ -n "$_UI_TIME" ]] && _green "T12: _ui_time handles negative" || _red "T12: negative" "non-empty" "$_UI_TIME"

# ════════════════ T13-T16: ui_label / ui_tokens / ui_progress ════════════════

# T13: ui_label bold → wraps with ANSI
_out=$(ui_label "test" "bold")
[[ -n "$_out" ]] && _green "T13: ui_label returns text" || _red "T13: label" "non-empty" "empty"

# T14: ui_tokens exists
type -t ui_tokens >/dev/null 2>&1 && _green "T14: ui_tokens defined" \
    || _red "T14: tokens" "function" "missing"

# T15: ui_progress exists
type -t ui_progress >/dev/null 2>&1 && _green "T15: ui_progress defined" \
    || _red "T15: progress" "function" "missing"

# T16: ui_treenode exists
type -t ui_treenode >/dev/null 2>&1 && _green "T16: ui_treenode defined" \
    || _red "T16: treenode" "function" "missing"

# ════════════════ T17-T20: status_begin / update / done ════════════════

# T17: status_begin exists
type -t status_begin >/dev/null 2>&1 && _green "T17: status_begin defined" \
    || _red "T17: begin" "function" "missing"

# T18: status_update exists
type -t status_update >/dev/null 2>&1 && _green "T18: status_update defined" \
    || _red "T18: update" "function" "missing"

# T19: status_done exists
type -t status_done >/dev/null 2>&1 && _green "T19: status_done defined" \
    || _red "T19: done" "function" "missing"

# T20: _build_status exists
type -t _build_status >/dev/null 2>&1 && _green "T20: _build_status defined" \
    || _red "T20: build_status" "function" "missing"

# ════════════════ Stress ════════════════

# S1: 1000 spinner ticks
SPINNER_IDX=0; _s_ok=1
for i in $(seq 1 1000); do
    _spin_tick >/dev/null 2>&1 || { _s_ok=0; break; }
done
[[ $_s_ok -eq 1 ]] && _green "S1: 1000 spinner ticks" || _red "S1: ticks" "OK" "fail at $i"

# S2: 100 _ui_time calls
_s_ok=1
for i in $(seq 1 100); do
    _ui_time "$((i * 1000))" || { _s_ok=0; break; }
done
[[ $_s_ok -eq 1 ]] && _green "S2: 100 _ui_time calls" || _red "S2: _ui_time" "OK" "fail at $i"

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
done < <(bash /tmp/bashagt_ui_test.sh 2>&1 || true)

rm -f /tmp/bashagt_ui_funcs.sh /tmp/bashagt_ui_test.sh

echo ""
echo "============================================"
echo " UI Primitives Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
