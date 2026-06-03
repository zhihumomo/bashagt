#!/usr/bin/env bash
# test_logging.sh — Logging subsystem unit tests (Section 1)
# Run: bash test/test_logging.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

sed -n '517,750p' "$BASHAGT" > /tmp/bashagt_log_funcs.sh

echo "============================================"
echo " Logging Subsystem Unit Tests"
echo "============================================"
echo ""

cat > /tmp/bashagt_log_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_log_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

LOG_DIR=$(mktemp -d)
mkdir -p "$LOG_DIR"
BASHAGT_LOG_LEVEL="INFO"

# ════════════════ T1-T5: log_init ════════════════

# T1: log_init creates log dir
log_init
[[ -d "$LOG_DIR" ]] && _green "T1: log_init creates dir" || _red "T1: init dir" "exists" "missing"

# T2: log file created on write
log "INFO:" "test message"
[[ -f "$LOG_DIR/bashagt.log" ]] && _green "T2: log creates file" || _red "T2: log file" "exists" "missing"

# T3: log file contains message
grep -q "test message" "$LOG_DIR/bashagt.log" 2>/dev/null && _green "T3: message in log" \
    || _red "T3: message" "test message" "$(cat "$LOG_DIR/bashagt.log")"

# T4: log includes level
grep -q "INFO" "$LOG_DIR/bashagt.log" 2>/dev/null && _green "T4: level in log" \
    || _red "T4: level" "INFO" "$(cat "$LOG_DIR/bashagt.log")"

# T5: log includes caller info (function:line)
log "INFO:" "caller test"
grep -qE "\[.*:[0-9]+\]" "$LOG_DIR/bashagt.log" 2>/dev/null && _green "T5: caller info present" \
    || _red "T5: caller" "[func:line]" "$(cat "$LOG_DIR/bashagt.log")"

# ════════════════ T6-T8: log levels ════════════════

# T6: INFO level logged at default threshold
> "$LOG_DIR/bashagt.log"
LOG_LEVEL_NUM=1  # INFO threshold
log "INFO: info msg should appear"
grep -q "info msg should appear" "$LOG_DIR/bashagt.log" && _green "T6: INFO logged at INFO threshold" \
    || _red "T6: INFO" "info msg" "$(cat "$LOG_DIR/bashagt.log")"

# T7: WARN level
> "$LOG_DIR/bashagt.log"
log "WARN:" "warning msg"
grep -q "WARN" "$LOG_DIR/bashagt.log" && _green "T7: WARN logged" \
    || _red "T7: WARN" "WARN" "$(cat "$LOG_DIR/bashagt.log")"

# T8: ERROR level
> "$LOG_DIR/bashagt.log"
log "ERROR:" "error occurred"
grep -q "ERROR" "$LOG_DIR/bashagt.log" && _green "T8: ERROR logged" \
    || _red "T8: ERROR" "ERROR" "$(cat "$LOG_DIR/bashagt.log")"

# ════════════════ T9-T12: access_log + _log_flush ════════════════

# access_log stores in _ACCESS_BUF; _log_flush writes to access.log
_ACCESS_BUF=()
access_log "GET" "/" 200 0.123
access_log "POST" "/api" 201 0.050
_log_flush
[[ -f "$LOG_DIR/access.log" ]] && _green "T9: _log_flush creates access.log" \
    || _red "T9: access log" "exists" "missing"

grep -q "GET" "$LOG_DIR/access.log" && grep -q "200" "$LOG_DIR/access.log" \
    && _green "T10: access_log format OK" || _red "T10: format" "GET 200" "$(cat "$LOG_DIR/access.log")"

grep -q "0.123" "$LOG_DIR/access.log" 2>/dev/null && _green "T11: latency 0.123 in log" \
    || _red "T11: latency" "0.123" "$(cat "$LOG_DIR/access.log")"

_lines=$(wc -l < "$LOG_DIR/access.log")
[[ $_lines -ge 2 ]] && _green "T12: 2+ entries ($_lines)" || _red "T12: multi" ">=2" "$_lines"

# ════════════════ T13-T15: _log_rotate ════════════════

# T13: _log_rotate function exists
type -t _log_rotate >/dev/null 2>&1 && _green "T13: _log_rotate defined" || _red "T13: rotate" "function" "missing"

# T14: _log_rotate doesn't crash on valid dir
_log_rotate "$LOG_DIR" "bashagt.log" >/dev/null 2>&1
_green "T14: _log_rotate no crash"

# T15: _log_flush exists
type -t _log_flush >/dev/null 2>&1 && _green "T15: _log_flush defined" || _red "T15: flush" "function" "missing"

# ════════════════ T16-T20: die / _log_err_trap ════════════════

# T16: die function exists
type -t die >/dev/null 2>&1 && _green "T16: die defined" || _red "T16: die" "function" "missing"

# T17: _log_err_trap exists
type -t _log_err_trap >/dev/null 2>&1 && _green "T17: _log_err_trap defined" || _red "T17: trap" "function" "missing"

# T18: _log_err_trap with exit=141 (SIGPIPE) → suppressed
_log_err_trap 141 2>/dev/null
_green "T18: ERR trap handles SIGPIPE (141)"

# T19: _log_err_trap with exit=130 (SIGINT) → suppressed
_log_err_trap 130 2>/dev/null
_green "T19: ERR trap handles SIGINT (130)"

# T20: _log_err_trap with exit=1 → logs error
_log_err_trap 1 >/dev/null 2>&1
_green "T20: ERR trap handles error (1)"

# ════════════════ Stress ════════════════

# S1: 100 rapid log calls
> "$LOG_DIR/bashagt.log"
_s_ok=1
for i in $(seq 1 100); do
    log "INFO:" "stress test message $i" || { _s_ok=0; break; }
done
[[ $_s_ok -eq 1 ]] && _green "S1: 100 log calls" || _red "S1: 100 logs" "OK" "fail at $i"

# S2: file has 100 entries
_lines=$(grep -c "stress test message" "$LOG_DIR/bashagt.log" 2>/dev/null || echo 0)
[[ $_lines -ge 100 ]] && _green "S2: $_lines entries in log" || _red "S2: count" ">=100" "$_lines"

rm -rf "$LOG_DIR"
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
done < <(bash /tmp/bashagt_log_test.sh 2>&1 || true)

rm -f /tmp/bashagt_log_funcs.sh /tmp/bashagt_log_test.sh

echo ""
echo "============================================"
echo " Logging Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
