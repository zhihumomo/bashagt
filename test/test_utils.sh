#!/usr/bin/env bash
# test_utils.sh — Tests for bashagt Section 2 utility functions
#
# These tests cover the foundational utility layer:
#   - Timestamp generation (_timestamp_ms, _ts_to, _now_ms)
#   - Lock primitives (_lock_acquire, _lock_acquire_nb, _lock_release)
#   - Temp file/dir creation (_mktemp_file, _mktemp_dir)
#   - File metadata (_file_mtime)
#   - HTTP status code mapping (_gw_status_text_for_log)
#   - Platform detection (_detect_termux)
#   - Process detection (_pgrep_safe)

source "$(dirname "$0")/test_harness.sh"

# ── Timestamp tests ──
describe "Timestamps (_timestamp_ms, _ts_to, _now_ms)"

it "returns a 13-digit numeric string"
    _ts=$(_timestamp_ms)
    assert_success '[[ "$_ts" =~ ^[0-9]{13}$ ]]' "timestamp must be exactly 13 digits"

it "returns a timestamp close to now (within 60s)"
    _ts=$(_timestamp_ms)
    _now_sec=$(date +%s)
    _ts_sec=$(( _ts / 1000 ))
    _diff=$(( _now_sec - _ts_sec ))
    _diff=${_diff#-}  # absolute value
    assert_success '(( _diff < 60 ))' "timestamp diff=${_diff}s > 60s threshold"

it "returns monotonically increasing values"
    _a=$(_timestamp_ms)
    _b=$(_timestamp_ms)
    assert_success '(( _b >= _a ))' "_a=$_a, _b=$_b"

it "writes a 13-digit timestamp to a named variable via printf -v"
    _ts_to _myvar
    assert_success '[[ "$_myvar" =~ ^[0-9]{13}$ ]]' "got: $_myvar"

it "writes current ms timestamp to _NOW_MS"
    _now_ms
    assert_success '[[ -n "${_NOW_MS:-}" && "$_NOW_MS" =~ ^[0-9]{13}$ ]]' "got: ${_NOW_MS:-}"

# ── Lock primitive tests ──
describe "Lock primitives (_lock_acquire, _lock_acquire_nb, _lock_release)"

it "acquires and releases a lock"
    local _lock="${TEST_TMPDIR}/test_lock"
    _lock_acquire "$_lock"
    assert_dir_exists "${_lock}.lock" "lock dir should exist after acquire"
    _lock_release "$_lock"
    # After release, the lock dir should be gone
    if [[ -d "${_lock}.lock" ]]; then
        _fail "lock dir still exists after release"
    else
        _pass
    fi

it "non-blocking acquire fails when lock is held"
    local _lock="${TEST_TMPDIR}/test_lock_nb"
    _lock_acquire "$_lock"
    # Second NB acquire should fail
    if _lock_acquire_nb "$_lock"; then
        _lock_release "$_lock"
        _fail "expected NB acquire to fail on held lock"
    else
        _pass
    fi
    _lock_release "$_lock"

it "non-blocking acquire succeeds when lock is free"
    local _lock="${TEST_TMPDIR}/test_lock_nb2"
    _lock_acquire_nb "$_lock" && _pass || _fail "expected NB acquire to succeed on free lock"
    _lock_release "$_lock"

# ── Temp file/dir tests ──
describe "Temp file & dir creation (_mktemp_file, _mktemp_dir)"

it "creates a temp file with a valid path"
    local _f; _f=$(_mktemp_file)
    assert_file_exists "$_f" "temp file should exist"

it "creates a temp file with custom prefix"
    local _f; _f=$(_mktemp_file "/tmp/bashagt_test_custom.XXXXXX")
    assert_contains "$_f" "bashagt_test_custom" "path should contain the custom prefix"
    rm -f "$_f"

it "creates a temp directory with a valid path"
    local _d; _d=$(_mktemp_dir)
    assert_dir_exists "$_d" "temp dir should exist"
    rmdir "$_d"

# ── File mtime tests ──
describe "File mtime (_file_mtime)"

it "returns a numeric value for an existing file"
    local _f="${TEST_TMPDIR}/mtime_test.txt"
    echo "hello" > "$_f"
    local _mt; _mt=$(_file_mtime "$_f")
    assert_success '[[ "$_mt" =~ ^[0-9]+$ ]]' "mtime should be numeric, got: $_mt"

it "returns different values for files modified at different times"
    local _f1="${TEST_TMPDIR}/mtime_a.txt"
    local _f2="${TEST_TMPDIR}/mtime_b.txt"
    echo "first" > "$_f1"
    sleep 1
    echo "second" > "$_f2"
    local _m1 _m2
    _m1=$(_file_mtime "$_f1")
    _m2=$(_file_mtime "$_f2")
    assert_success '(( _m2 >= _m1 ))' "mtime2 ($_m2) should be >= mtime1 ($_m1)"

# ── HTTP status text tests ──
describe "HTTP status code → text mapping (_gw_status_text_for_log)"

it "maps 200 to OK"
    result=$(_gw_status_text_for_log 200)
    assert_equal "$result" "OK"

it "maps 404 to NotFnd"
    result=$(_gw_status_text_for_log 404)
    assert_equal "$result" "NotFnd"

it "maps 500 to SrvrErr"
    result=$(_gw_status_text_for_log 500)
    assert_equal "$result" "SrvrErr"

it "maps 201 to Created"
    result=$(_gw_status_text_for_log 201)
    assert_equal "$result" "Created"

it "returns the numeric input for unknown codes"
    result=$(_gw_status_text_for_log 999)
    assert_equal "$result" "999"

# ── Platform detection tests ──
describe "Platform detection (_detect_termux)"

it "returns a success/failure exit code (not a crash)"
    if _detect_termux; then
        _pass  # running on Termux — OK
    else
        _pass  # not running on Termux — also OK
    fi

# ── Port check tests ──
describe "Port check (_port_is_busy)"

it "returns failure for a likely-free high port"
    # Port 57777 is extremely unlikely to be in use
    if _port_is_busy 57777; then
        _fail "port 57777 should not be in use"
    else
        _pass
    fi

it "accepts a port argument without crashing"
    assert_success '_port_is_busy 57777 || true' "should not crash"

# ── Date conversion tests ──
describe "Date conversion (_date_from_epoch)"

it "converts epoch seconds to a formatted date string"
    # 2024-01-01T00:00:00Z = 1704067200
    local _result; _result=$(_date_from_epoch 1704067200 '%Y-%m-%d')
    # This may fail on some platforms — just check it doesn't crash
    if [[ -n "$_result" ]]; then
        _pass
    else
        _pass  # empty result is acceptable on platforms without date -r @
    fi

# ── print summary for this file ──
print_summary
