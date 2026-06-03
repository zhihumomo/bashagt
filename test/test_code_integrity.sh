#!/usr/bin/env bash
# test_code_integrity.sh — Static checks for non-portable patterns in bashagt
# Run: bash test/test_code_integrity.sh
# No API key required. Verifies all GNU-only patterns are properly wrapped.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

safe_grep() { command grep "$@" 2>/dev/null || true; }

# Check whether a given line number falls inside a function body.
# Usage: _line_in_func <line> <func_name>
_line_in_func() {
    local _target="$1" _func="$2"
    local _start; _start=$(grep -n "^${_func}()" "$BASHAGT" | head -1 | cut -d: -f1)
    [[ -z "$_start" ]] && return 1
    # Find the matching closing brace (first ^} after function start)
    local _end; _end=$(tail -n +$((_start + 1)) "$BASHAGT" | grep -n '^}' | head -1 | cut -d: -f1)
    _end=$((_start + _end))
    [[ $_target -ge $_start && $_target -le $_end ]]
}

echo "============================================"
echo " Code Integrity: Non-Portable Pattern Audit"
echo "============================================"
echo ""

# ── date +%s%3N / %N ──
echo "── GNU date format specifiers ──"
count=$(grep -c 'date +%s%3N\|date +%s%N' "$BASHAGT" 2>/dev/null || echo 0)
if [[ $count -eq 1 ]]; then
    line=$(grep -n 'date +%s%3N\|date +%s%N' "$BASHAGT" | head -1 | cut -d: -f1)
    if _line_in_func "$line" "_timestamp_ms"; then
        _pass "date +%s%3N/%N: 1 occurrence inside _timestamp_ms (L$line)"
    else
        _fail "date +%s%3N inside _timestamp_ms" "L$line in _timestamp_ms" "L$line not in _timestamp_ms"
    fi
else
    _fail "date +%s%3N/%N: 1 occurrence" "1" "$count"
fi

# ── sha256sum ──
echo "── sha256sum ──"
lines=$(safe_grep -n '\<sha256sum\>' "$BASHAGT")
# Allow: inside _cc_hash, command -v, or comments
bad=$(echo "$lines" | while IFS= read -r l; do
    ln=$(echo "$l" | cut -d: -f1)
    echo "$l" | grep -q 'command -v sha256sum\|#.*sha256sum\|#.*Hash\|#.*SHA256' && continue
    _line_in_func "$ln" "_cc_hash" && continue
    echo "$l"
done)
if [[ -z "$bad" ]]; then
    _pass "sha256sum: all occurrences are inside _cc_hash or command -v"
else
    _fail "sha256sum: all inside _cc_hash" "none outside" "$bad"
fi

# ── stat -c %Y ──
echo "── stat -c %Y ──"
lines=$(safe_grep -n 'stat -c %Y' "$BASHAGT")
bad=$(echo "$lines" | while IFS= read -r l; do
    ln=$(echo "$l" | cut -d: -f1)
    echo "$l" | grep -q '#.*file mtime\|#.*Portable file\|#.*stat\|#.*Portable mtime' && continue
    _line_in_func "$ln" "_file_mtime" && continue
    # Also allow inline _file_mtime inside keybinding heredoc templates
    _line_in_func "$ln" "_gen_keybindings_zsh" && continue
    _line_in_func "$ln" "_install_keybindings" && continue
    echo "$l"
done)
if [[ -z "$bad" ]]; then
    _pass "stat -c %Y: all occurrences are inside _file_mtime"
else
    _fail "stat -c %Y: all inside _file_mtime" "none outside" "$bad"
fi

# ── date -d @ ──
echo "── date -d @ ──"
lines=$(safe_grep -n 'date -d.*@' "$BASHAGT")
bad=$(echo "$lines" | while IFS= read -r l; do
    ln=$(echo "$l" | cut -d: -f1)
    _line_in_func "$ln" "_date_from_epoch" && continue
    echo "$l"
done)
if [[ -z "$bad" ]]; then
    _pass "date -d @: all occurrences are inside _date_from_epoch"
else
    _fail "date -d @: all inside _date_from_epoch" "none outside" "$bad"
fi

# ── fuser ──
echo "── fuser ──"
lines=$(safe_grep -n '\<fuser\>' "$BASHAGT")
bad=$(echo "$lines" | while IFS= read -r l; do
    ln=$(echo "$l" | cut -d: -f1)
    echo "$l" | grep -q 'command -v fuser\|#.*fuser\|#.*Portable port' && continue
    _line_in_func "$ln" "_port_is_busy" && continue
    _line_in_func "$ln" "_port_kill" && continue
    echo "$l"
done)
if [[ -z "$bad" ]]; then
    _pass "fuser: all occurrences inside _port_is_busy / _port_kill"
else
    _fail "fuser: all inside _port_* helpers" "none outside" "$bad"
fi

# ── flock ──
echo "── flock ──"
lines=$(safe_grep -n '\<flock\>' "$BASHAGT")
bad=$(echo "$lines" | while IFS= read -r l; do
    echo "$l" | grep -q '#.*flock' && continue
    _line_in_func "$(echo "$l" | cut -d: -f1)" "_lock_" 2>/dev/null && continue
    echo "$l"
done)
if [[ -z "$bad" ]]; then
    _pass "flock: all replaced with mkdir-based _lock_*"
else
    _fail "flock: all replaced" "none" "$bad"
fi

# ── timeout N ──
echo "── timeout ──"
lines=$(safe_grep -n '\<timeout [0-9]' "$BASHAGT")
bad=$(echo "$lines" | safe_grep -v 'TIMEOUT_CMD\|connect-timeout\|max-time')
if [[ -z "$bad" ]]; then
    _pass "timeout: all use \${TIMEOUT_CMD:-timeout} or connect-timeout/max-time"
else
    _fail "timeout: 0 bare calls" "none" "$bad"
fi

# ── echo -n ──
echo "── echo -n ──"
count=$(safe_grep -c 'echo -n' "$BASHAGT")
if [[ $count -eq 0 ]]; then
    _pass "echo -n: all replaced with printf ''"
else
    _fail "echo -n: 0 occurrences" "0" "$count"
fi

# ── head -c ──
echo "── head -c ──"
count=$(safe_grep -c 'head -c' "$BASHAGT")
if [[ $count -eq 0 ]]; then
    _pass "head -c: all replaced with dd"
else
    _fail "head -c: 0 occurrences" "0" "$count"
fi

# ── /proc/self/fd/8 with /dev/fd/8 fallback ──
echo "── /proc/self/fd/ ──"
if safe_grep -q '/dev/fd/8' "$BASHAGT"; then
    _pass "/proc/self/fd/8 has /dev/fd/8 fallback"
else
    _fail "/dev/fd/8 fallback" "present" "missing"
fi

# ── ss -tlnp fallback chain ──
echo "── ss -tlnp fallback ──"
if safe_grep -q 'ss.*tlnp.*netstat.*lsof' "$BASHAGT"; then
    _pass "ss -tlnp has netstat/lsof fallback chain"
else
    _fail "ss -tlnp fallback chain" "present" "missing"
fi

# ── Bash version ──
echo "── bash version ──"
if safe_grep -q 'bash >= 4.1 required' "$BASHAGT"; then
    _pass "version check requires 4.1+"
else
    _fail "version check 4.1+" "present" "missing"
fi

if safe_grep -q 'brew install bash' "$BASHAGT"; then
    _pass "early version check includes brew hint"
else
    _fail "brew hint" "present" "missing"
fi

# Verify early check comes before first declare -A
early_line=$(grep -n 'brew install bash' "$BASHAGT" | head -1 | cut -d: -f1)
first_declare=$(grep -n '^declare -A' "$BASHAGT" | head -1 | cut -d: -f1)
if [[ -n "$early_line" && -n "$first_declare" ]] && [[ $early_line -lt $first_declare ]]; then
    _pass "early check (L$early_line) is before first declare -A (L$first_declare)"
else
    _fail "early check before declare -A" "early < first" "early=$early_line first=$first_declare"
fi

# ── Portable helper functions all defined ──
echo "── portable helper function definitions ──"
for fn in _timestamp_ms _port_is_busy _port_kill _lock_acquire _lock_acquire_nb _lock_release _file_mtime _date_from_epoch _cc_hash; do
    if safe_grep -q "^${fn}()" "$BASHAGT"; then
        _pass "$fn is defined"
    else
        _fail "$fn is defined" "present" "missing"
    fi
done

# ── Syntax check ──
echo "── bash syntax ──"
if bash -n "$BASHAGT" 2>&1; then
    _pass "bash -n: clean"
else
    _fail "bash -n" "clean" "syntax errors"
fi

# ── Input system modernized invariants ──
echo "── input system invariants ──"

# Helper for checking existence of a pattern (not just non-zero exit)
_grep_exists() { command grep -q "$@" 2>/dev/null; }

# _str_display_width is defined (Unicode display-width calculator)
if _grep_exists "^_str_display_width()" "$BASHAGT"; then
    _pass "_str_display_width() is defined"
else
    _fail "_str_display_width() is defined" "present" "missing"
fi

# _str_char_display_width is defined (single-char variant)
if _grep_exists "^_str_char_display_width()" "$BASHAGT"; then
    _pass "_str_char_display_width() is defined"
else
    _fail "_str_char_display_width() is defined" "present" "missing"
fi

# _update_term_width is defined (SIGWINCH handler)
if _grep_exists "^_update_term_width()" "$BASHAGT"; then
    _pass "_update_term_width() is defined"
else
    _fail "_update_term_width() is defined" "present" "missing"
fi

# SIGWINCH trap registered in _input_init
if _grep_exists "trap.*_update_term_width.*WINCH" "$BASHAGT"; then
    _pass "SIGWINCH trap registered for _update_term_width"
else
    _fail "SIGWINCH trap in _input_init" "present" "missing"
fi

# _IN_ESC_TIMEOUT constant is defined
if _grep_exists '_IN_ESC_TIMEOUT=' "$BASHAGT"; then
    _pass "_IN_ESC_TIMEOUT constant is defined"
else
    _fail "_IN_ESC_TIMEOUT constant" "present" "missing"
fi

# _req_disp_width delegates to _str_display_width (not its own broken logic)
_req_dw_count=$(safe_grep -A3 "^_req_disp_width()" "$BASHAGT" | safe_grep -c '_str_display_width' || echo 0)
if (( _req_dw_count > 0 )); then
    _pass "_req_disp_width delegates to _str_display_width"
else
    _fail "_req_disp_width delegates to _str_display_width" "calls _str_display_width" "does not call it"
fi

# _in_complete uses readarray -t (not read -ra which splits on spaces)
_in_complete_count=$(safe_grep -A15 '_in_complete()' "$BASHAGT" | safe_grep -c 'readarray.*-t' || echo 0)
if (( _in_complete_count > 0 )); then
    _pass "_in_complete uses readarray -t (preserves spaces)"
else
    _fail "_in_complete uses readarray -t" "readarray -t" "still uses read -ra"
fi

# No bare read -n without LC_ALL=C in input processing functions
# (read -n counts chars not bytes; LC_ALL=C ensures byte-count for ASCII-safe contexts)
# Pattern: 'read' followed by whitespace, then '-n' not followed by '1' or a letter (catches read -n N)
bare_read_n=$(safe_grep -n 'read.* -n [0-9]' "$BASHAGT" | safe_grep -v 'LC_ALL=C\|#' || true)
if [[ -z "$bare_read_n" ]]; then
    _pass "no bare read -n (chars-for-bytes) in input paths"
else
    _fail "no bare read -n" "none" "$bare_read_n"
fi

# dd used for HTTP body byte-exact read (not read -n)
_http_body_count=$(safe_grep -A1 '_content_length > 0' "$BASHAGT" | safe_grep -c 'dd' || echo 0)
if (( _http_body_count > 0 )); then
    _pass "HTTP body uses dd for byte-exact read"
else
    _fail "HTTP body uses dd" "dd present" "dd missing"
fi

# $(cat) replaced with size-capped dd in oneshot/pipe path
_oneshot_count=$(safe_grep -c 'input=\$(dd bs=1048576' "$BASHAGT" || echo 0)
if (( _oneshot_count > 0 )); then
    _pass "oneshot input uses dd with size cap (not unlimited \$(cat))"
else
    _fail "oneshot input size cap" "dd present" "still using \$(cat)"
fi

# _request_ui uses _input_read_key (not its own inline escape parser)
_req_ui_count=$(safe_grep -A50 '^_request_ui()' "$BASHAGT" | safe_grep -c '_input_read_key' || echo 0)
if (( _req_ui_count > 0 )); then
    _pass "_request_ui uses _input_read_key instead of inline escape parser"
else
    _fail "_request_ui uses _input_read_key" "calls _input_read_key" "does not use it"
fi

# Ctrl-R history search is implemented (not stub)
hist_search_count=$(safe_grep -c 'TODO.*history search\|not yet implemented' "$BASHAGT" || echo 0)
if (( hist_search_count == 0 )); then
    _pass "Ctrl-R history search is implemented (not stub)"
else
    _fail "Ctrl-R history search" "implemented" "still stub"
fi

# ── Summary ──
echo ""
echo "============================================"
echo " Code Integrity Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
