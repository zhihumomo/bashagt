#!/usr/bin/env bash
# test_harness.sh — Lightweight pure-bash test framework for bashagt
#
# Usage:
#   source ./test_harness.sh   # from individual test files
#   run_test_file test_utils.sh  # inside run_all.sh
#
# Provides: describe, it, assert_*, and colored TAP-like output.

# Guard: prevent counter reset when re-sourced by individual test files.
# counters are initialized only once, in run_all.sh or on first source.
if [[ -n "${_TEST_HARNESS_LOADED:-}" ]]; then
    return 0
fi
_TEST_HARNESS_LOADED=1

set -euo pipefail

# ── Global counters ──
_TESTS_TOTAL=0
_TESTS_PASSED=0
_TESTS_FAILED=0
_CURRENT_DESCRIBE=""
_CURRENT_IT=""

# ── Color output ──
_GREEN='\033[0;32m'
_RED='\033[0;31m'
_YELLOW='\033[0;33m'
_DIM='\033[2m'
_RESET='\033[0m'

# ── describe <name> — start a test group ──
describe() {
    _CURRENT_DESCRIBE="$1"
    printf '\n%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf '  %s\n' "$_CURRENT_DESCRIBE"
    printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── it <name> — start a single test case (sets label, does not count) ──
it() {
    _CURRENT_IT="$1"
    printf '  … %s' "$_CURRENT_IT"
}

# ── Internal: mark assertion as passed ──
# Each assertion = one test unit in the tally.
_pass() {
    _TESTS_TOTAL=$((_TESTS_TOTAL + 1))
    _TESTS_PASSED=$((_TESTS_PASSED + 1))
    printf '\r  %s✓%s %s\n' "$_GREEN" "$_RESET" "$_CURRENT_IT"
}

# ── Internal: mark assertion as failed with reason ──
_fail() {
    local _reason="$1"
    _TESTS_TOTAL=$((_TESTS_TOTAL + 1))
    _TESTS_FAILED=$((_TESTS_FAILED + 1))
    printf '\r  %s✗%s %s\n' "$_RED" "$_RESET" "$_CURRENT_IT"
    printf '    %s→%s %s\n' "$_RED" "$_RESET" "$_reason"
}

# ── assert_equal <got> <expected> [message] ──
assert_equal() {
    local _got="$1" _expected="$2" _msg="${3:-}"
    if [[ "$_got" == "$_expected" ]]; then
        _pass
        return 0
    fi
    local _reason="expected '$_expected', got '$_got'"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_not_equal <got> <not_expected> [message] ──
assert_not_equal() {
    local _got="$1" _not_expected="$2" _msg="${3:-}"
    if [[ "$_got" != "$_not_expected" ]]; then
        _pass
        return 0
    fi
    local _reason="expected value != '$_not_expected', got '$_got'"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_contains <haystack> <needle> [message] ──
assert_contains() {
    local _haystack="$1" _needle="$2" _msg="${3:-}"
    if [[ "$_haystack" == *"$_needle"* ]]; then
        _pass
        return 0
    fi
    local _reason="expected string to contain '$_needle'"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_not_contains <haystack> <needle> [message] ──
assert_not_contains() {
    local _haystack="$1" _needle="$2" _msg="${3:-}"
    if [[ "$_haystack" != *"$_needle"* ]]; then
        _pass
        return 0
    fi
    local _reason="expected string to NOT contain '$_needle'"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_true <value> [message] ──
assert_true() {
    local _val="$1" _msg="${2:-}"
    if [[ "$_val" == "true" || "$_val" == "0" ]]; then
        _pass
        return 0
    fi
    local _reason="expected truthy, got '$_val'"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_success <command> [message] — run command and assert exit 0 ──
assert_success() {
    local _cmd="$1" _msg="${2:-}"
    local _out
    if _out=$(eval "$_cmd" 2>&1); then
        _pass
        return 0
    fi
    local _reason="command failed (exit=$?): $_cmd — $_out"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_failure <command> [message] — run command and assert exit != 0 ──
assert_failure() {
    local _cmd="$1" _msg="${2:-}"
    if ! eval "$_cmd" 2>/dev/null; then
        _pass
        return 0
    fi
    local _reason="command unexpectedly succeeded: $_cmd"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_file_exists <path> [message] ──
assert_file_exists() {
    local _path="$1" _msg="${2:-}"
    if [[ -f "$_path" ]]; then
        _pass
        return 0
    fi
    local _reason="file not found: $_path"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── assert_dir_exists <path> [message] ──
assert_dir_exists() {
    local _path="$1" _msg="${2:-}"
    if [[ -d "$_path" ]]; then
        _pass
        return 0
    fi
    local _reason="directory not found: $_path"
    [[ -n "$_msg" ]] && _reason="$_msg: $_reason"
    _fail "$_reason"
    return 1
}

# ── Print a summary line ──
print_summary() {
    printf '\n%s\n' "──────────────────────────────────────────"
    if (( _TESTS_FAILED == 0 )); then
        printf '  %sResult: %d/%d passed ✓%s\n' \
            "$_GREEN" "$_TESTS_PASSED" "$_TESTS_TOTAL" "$_RESET"
    else
        printf '  %sResult: %d/%d passed, %d FAILED ✗%s\n' \
            "$_RED" "$_TESTS_PASSED" "$_TESTS_TOTAL" "$_TESTS_FAILED" "$_RESET"
    fi
    printf '%s\n' "──────────────────────────────────────────"
}

# ── run_test_file <path> — source and run a single test file, return exit code ──
# Each test file should call describe/it/assert_*; the harness counts totals.
run_test_file() {
    local _file="$1"
    local _label="${_file##*/}"

    printf '\n%s %s %s\n' "$_DIM" "═══ $_label ═══" "$_RESET"

    # Track totals per-file so we can report file-level stats
    local _before_total=$_TESTS_TOTAL
    local _before_passed=$_TESTS_PASSED
    local _before_failed=$_TESTS_FAILED

    # Source the test file; it should call describe/it/assert_*
    if ! source "$_file"; then
        printf '  %sERROR:%s test file %s failed to execute (exit code %d)\n' \
            "$_RED" "$_RESET" "$_label" "$?"
        return 1
    fi

    local _file_total=$((_TESTS_TOTAL - _before_total))
    local _file_passed=$((_TESTS_PASSED - _before_passed))
    local _file_failed=$((_TESTS_FAILED - _before_failed))

    if (( _file_failed == 0 )); then
        printf '%s  %s: %d/%d passed%s\n' \
            "$_GREEN" "$_label" "$_file_passed" "$_file_total" "$_RESET"
    else
        printf '%s  %s: %d/%d passed, %d FAILED%s\n' \
            "$_RED" "$_label" "$_file_passed" "$_file_total" "$_file_failed" "$_RESET"
    fi

    return 0
}

# ── Cleanup hook: restore a clean temp dir ──
# Callers should set TEST_TMPDIR before sourcing test files.
setup_test_tmpdir() {
    TEST_TMPDIR="${TMPDIR:-/tmp}/bashagt_test_$$"
    rm -rf "$TEST_TMPDIR" 2>/dev/null || true
    mkdir -p "$TEST_TMPDIR"
    export TEST_TMPDIR
}

teardown_test_tmpdir() {
    rm -rf "$TEST_TMPDIR" 2>/dev/null || true
}
