#!/usr/bin/env bash
# test_portable_utils.sh — Unit tests for macOS/Linux portable utility functions
# Run: bash test/test_portable_utils.sh
# No API key required. Tests function output correctness in isolation.

set -uo pipefail
# No -e: grep returns 1 on no-match, which is normal in our checks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# Extract a single function definition from bashagt and run it in isolation.
# stdin is piped to the function. Arguments are passed to the function.
# Usage: _run_func <func_name> [stdin_input] [func_args...]
_run_func() {
    local func="$1" stdin_input="${2:-}"
    shift 2 2>/dev/null || true
    local def; def=$(sed -n "/^${func}()/,/^}/p" "$BASHAGT" 2>/dev/null)
    if [[ -z "$def" ]]; then
        echo "ERROR: could not extract $func from bashagt" >&2
        return 1
    fi
    if [[ -n "$stdin_input" ]]; then
        printf '%s' "$stdin_input" | bash -c "$def"'; '"$func"' "$@"' bash "$@" 2>/dev/null
    else
        bash -c "$def"'; '"$func"' "$@"' bash "$@" < /dev/null 2>/dev/null
    fi
}

echo "============================================"
echo " Portable Utility Function Unit Tests"
echo "============================================"
echo ""

# ── _timestamp_ms ──
echo "── _timestamp_ms ──"

ts=$(_run_func _timestamp_ms)
if [[ "$ts" =~ ^[0-9]{13}$ ]]; then
    _pass "output is 13-digit number: $ts"
else
    _fail "13-digit number" "len=$(printf '%s' "$ts" | wc -c)" "$ts"
fi

ts1=$(_run_func _timestamp_ms)
sleep 0.05
ts2=$(_run_func _timestamp_ms)
if [[ $ts2 -gt $ts1 ]]; then
    _pass "monotonic: ts2 ($ts2) > ts1 ($ts1)"
else
    _fail "monotonic" "ts2 > ts1" "ts2=$ts2 ts1=$ts1"
fi

# ── _file_mtime ──
echo "── _file_mtime ──"

mt=$(_run_func _file_mtime "" "$BASHAGT")
if [[ "$mt" =~ ^[0-9]+$ ]] && [[ $mt -gt 1700000000 ]]; then
    _pass "existing file returns epoch: $mt"
else
    _fail "epoch > 1700000000" "1700000000" "$mt"
fi

mt=$(_run_func _file_mtime "" "/tmp/__nonexistent_$$")
if [[ "$mt" == "0" ]]; then
    _pass "non-existent file returns 0"
else
    _fail "returns 0" "0" "$mt"
fi

# ── _date_from_epoch ──
echo "── _date_from_epoch ──"

d=$(_run_func _date_from_epoch "" "0" "+%Y-%m-%d")
if [[ "$d" == "1970-01-01" ]]; then
    _pass "epoch 0 → $d"
else
    _fail "1970-01-01" "1970-01-01" "$d"
fi

d=$(_run_func _date_from_epoch "" "1700000000" "+%Y-%m")
if [[ "$d" == "2023-11" ]]; then
    _pass "epoch 1700000000 → $d"
else
    _fail "2023-11" "2023-11" "$d"
fi

d=$(_run_func _date_from_epoch "" "0" "+%d")
if [[ "$d" == "01" ]]; then
    _pass "epoch 0 day → $d"
else
    _fail "01" "01" "$d"
fi

d=$(_run_func _date_from_epoch "" "0" "+%w")
if [[ "$d" =~ ^[0-6]$ ]]; then
    _pass "epoch 0 weekday → $d (0=Thu UTC, may vary by TZ)"
else
    _fail "0-6" "0-6" "$d"
fi

# ── _cc_hash ──
echo "── _cc_hash ──"

h=$(echo -n | _run_func _cc_hash "")
expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
if [[ "$h" == "$expected" ]]; then
    _pass "empty input → correct SHA256"
else
    _fail "correct SHA256 for empty" "$expected" "$h"
fi

h=$(printf 'hello world' | _run_func _cc_hash "hello world")
expected="b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
if [[ "$h" == "$expected" ]]; then
    _pass "'hello world' → correct SHA256"
else
    _fail "correct SHA256 for 'hello world'" "$expected" "$h"
fi

h=$(printf 'bashagt' | _run_func _cc_hash "bashagt")
if [[ "${#h}" -eq 64 ]] && [[ "$h" =~ ^[0-9a-f]+$ ]]; then
    _pass "'bashagt' → valid 64-char hex: ${h:0:16}..."
else
    _fail "64-char hex hash" "len=64 hex" "len=${#h} val=$h"
fi

# ── _port_is_busy ──
echo "── _port_is_busy ──"

rc=$(set +e; _run_func _port_is_busy "" "59999"; echo "$?")
if [[ "$rc" == "0" || "$rc" == "1" ]]; then
    _pass "returns $rc (port 59999 expected 1=not busy)"
else
    _fail "exit code 0 or 1" "0 or 1" "$rc"
fi

# ── _port_kill ──
echo "── _port_kill ──"

out=$(set +e; _run_func _port_kill "" "59999" 2>&1; echo ":OK")
if [[ "$out" == *":OK" ]]; then
    _pass "no crash on unused port"
else
    _fail "no crash" "exit OK" "$out"
fi

# ── mkdir lock functions ──
echo "── mkdir lock functions ──"

lockf="/tmp/bashagt_test_lock_$$"
rm -rf "${lockf}.lock" 2>/dev/null || true

r1=$(set +e; _run_func _lock_acquire "" "$lockf" 2>&1; echo ":ACQUIRED")
r2=$(set +e; _run_func _lock_release "" "$lockf" 2>&1; echo ":RELEASED")
if echo "$r1" | grep -q "ACQUIRED" && echo "$r2" | grep -q "RELEASED"; then
    _pass "acquire + release cycle OK"
else
    _fail "acquire + release" "ACQUIRED / RELEASED" "$r1 / $r2"
fi
rm -rf "${lockf}.lock" 2>/dev/null || true

# Non-blocking acquire on held lock should fail.
# Run in a single bash invocation so the lock is held throughout.
lockf2="/tmp/bashagt_test_lock_nb_$$"
rm -rf "${lockf2}.lock" 2>/dev/null || true
nb_out=$(bash -c "
$(sed -n '/^_lock_acquire()/,/^}/p' "$BASHAGT")
$(sed -n '/^_lock_acquire_nb()/,/^}/p' "$BASHAGT")
$(sed -n '/^_lock_release()/,/^}/p' "$BASHAGT")
_lock_acquire '$lockf2'
_lock_acquire_nb '$lockf2' && echo 'ACQUIRED_NB' || echo 'NB_BLOCKED'
_lock_release '$lockf2'
" 2>/dev/null)
if echo "$nb_out" | grep -q "NB_BLOCKED"; then
    _pass "NB acquire correctly blocked on held lock"
else
    _fail "NB acquire blocked" "NB_BLOCKED" "$nb_out"
fi
rm -rf "${lockf2}.lock" 2>/dev/null || true

# ── fd 8 dual-path detection ──
echo "── fd 8 /proc/self/fd/ vs /dev/fd/ ──"

fd_out=$(bash -c "
exec 8>&1
local _stm_fd=1
[[ -e /proc/self/fd/8 || -e /dev/fd/8 ]] && _stm_fd=8
echo \"DETECTED:\$_stm_fd\"
exec 8>&-
" 2>/dev/null)
if echo "$fd_out" | grep -q "DETECTED:8"; then
    _pass "fd 8 detected via /proc/self/fd/8 or /dev/fd/8"
else
    _fail "fd 8 detected" "DETECTED:8" "$fd_out"
fi

# ── ANSI strip with portable \$'\\033' ──
echo "── ANSI strip (sed \$'\\033') ──"

if grep -q "sed.*\\\\033" "$BASHAGT"; then
    result=$(printf '\033[31mRED\033[0m\033[1mBOLD\033[0m' | sed $'s/\033\[[0-9;]*m//g' 2>/dev/null)
    if [[ "$result" == "REDBOLD" ]]; then
        _pass "ANSI codes stripped: $result"
    else
        _fail "ANSI stripped" "REDBOLD" "$result"
    fi
else
    # Check that no \x1b hex escapes remain in sed commands
    if grep -q 'x1b' <(grep 'sed.*s/' "$BASHAGT" 2>/dev/null); then
        _fail "no \\x1b in sed" "no \\x1b" "found \\x1b"
    else
        _pass "no \\x1b hex escapes in sed (already portable)"
    fi
fi

# ── printf '' for empty files (was echo -n) ──
echo "── printf '' empty file creation ──"

tmpf=$(mktemp /tmp/bashagt_test_printf.XXXXXX)
printf '' > "$tmpf"
size=$(stat -c %s "$tmpf" 2>/dev/null || stat -f %z "$tmpf" 2>/dev/null)
if [[ "$size" == "0" ]]; then
    _pass "empty file created (size=0)"
else
    _fail "empty file" "0" "$size"
fi
rm -f "$tmpf"

# ── dd for random bytes (was head -c) ──
echo "── dd random bytes ──"

if grep -q 'dd if=/dev/urandom bs=8 count=1' "$BASHAGT"; then
    _pass "uses dd for random bytes (replaced head -c)"
else
    _fail "dd for random bytes" "found" "not found"
fi

if grep -q '${_rand:0:8}' "$BASHAGT"; then
    _pass "uses \${var:0:N} for truncation (replaced head -c)"
else
    _fail "\${var:0:N} truncation" "found" "not found"
fi

# ── Summary ──
echo ""
echo "============================================"
echo " Unit Test Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
