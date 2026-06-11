#!/usr/bin/env bash
# test_and_wrap_stress.sh — Stress tests for && line-breaking in _bash_format()
set -euo pipefail

AWK="${AWK:-test/bash_format.awk}"
PASS=0; FAIL=0; TNUM=0

# ── Test helpers ──
check() {
    local name="$1" desc="$2" expected_lines="$3"
    TNUM=$((TNUM+1))
    local output; output=$(printf '%s\n' "$4" | awk -v dark=1 -f "$AWK" 2>&1)
    local rc=$? lines
    lines=$(printf '%s\n' "$output" | wc -l)
    if [[ "$lines" == "$expected_lines" ]]; then
        PASS=$((PASS+1))
        echo "  ✓ $name — $desc (lines=$lines)"
    else
        FAIL=$((FAIL+1))
        echo "  ✗ $name — $desc (expected $expected_lines lines, got $lines)"
        echo "    output:"
        printf '%s\n' "$output" | sed 's/^/      /'
    fi
}

# Run awk, verify output contains expected count of backslash-continuations
check_wraps() {
    local name="$1" desc="$2" expected_wraps="$3"
    TNUM=$((TNUM+1))
    local output; output=$(printf '%s\n' "$4" | awk -v dark=1 -f "$AWK" 2>&1)
    # Count lines ending with \
    local wraps; wraps=$(printf '%s\n' "$output" | grep -c '\\$' || true)
    if [[ "$wraps" == "$expected_wraps" ]]; then
        PASS=$((PASS+1))
        echo "  ✓ $name — $desc (wraps=$wraps)"
    else
        FAIL=$((FAIL+1))
        echo "  ✗ $name — $desc (expected $expected_wraps wraps, got $wraps)"
        echo "    output:"
        printf '%s\n' "$output" | sed 's/^/      /'
    fi
}

echo "=== Phase 1: Long && chains ==="
echo ""

# 10 commands, 9 &&
_long9=""; for ((i=1; i<=10; i++)); do [[ -n "$_long9" ]] && _long9+=" && "; _long9+="cmd$i"; done
check A01 "9 ands — 7 wraps (3rd..9th)" 8 "$_long9"

# 20 commands, 19 &&
_long19=""; for ((i=1; i<=20; i++)); do [[ -n "$_long19" ]] && _long19+=" && "; _long19+="cmd$i"; done
check A02 "19 ands — 17 wraps (3rd..19th)" 18 "$_long19"

# 50 commands, 49 &&
_long49=""; for ((i=1; i<=50; i++)); do [[ -n "$_long49" ]] && _long49+=" && "; _long49+="cmd$i"; done
check A03 "49 ands — 47 wraps (3rd..49th)" 48 "$_long49"

# 100 commands, 99 &&
_long99=""; for ((i=1; i<=100; i++)); do [[ -n "$_long99" ]] && _long99+=" && "; _long99+="cmd$i"; done
check A04 "99 ands — 97 wraps (3rd..99th)" 98 "$_long99"

echo ""
echo "=== Phase 2: Mixed && with ; ==="
echo ""

# 3 ; breaks, each with 2 && (total 6 && across line, wraps at 3rd && overall)
check A05 "3 semis × 2 ands each — 4 ands total, wraps at 3rd/4th" 6 \
    "cmd1 && cmd2; cmd3 && cmd4; cmd5 && cmd6; cmd7 && cmd8"

# Alternating ; and &&
check A06 "; && ; && ; && pattern" 5 \
    "echo one; echo two && echo three; echo four && echo five; echo six && echo seven"

# Dense: many ; and && intermixed
_dense="a1 && a2; b1 && b2 && b3 && b4; c1 && c2 && c3; d1 && d2 && d3 && d4 && d5"
check A07 "dense ; + && mix" 12 "$_dense"

echo ""
echo "=== Phase 3: && inside strings (must NOT count) ==="
echo ""

check A08 "quoted ands not counted, 4 real ands → 2 wraps" 4 \
    'echo "a && b && c && d" && cmd1 && cmd2 && cmd3 && cmd4 && cmd5'

check A09 "sq and dq mix with ands inside" 4 \
    "echo 'x && y' && printf \"a && b\" && cmd1 && cmd2 && cmd3 && cmd4"

check A10 "ands inside backticks (state 0, counted correctly)" 5 \
    'result=`cmd1 && cmd2 && cmd3` && cmd4 && cmd5 && cmd6 && cmd7'

check A11 "ands inside \$() (state 0, counted correctly)" 5 \
    'result=$(cmd1 && cmd2 && cmd3) && cmd4 && cmd5 && cmd6 && cmd7'

echo ""
echo "=== Phase 4: Edge cases ==="
echo ""

# Exactly 2 && — no wrap
check A12 "exactly 2 ands — no wrap" 1 "cmd1 && cmd2 && cmd3"

# Exactly 3 && — wrap at 3rd
check A13 "exactly 3 ands — wrap 3rd" 2 "cmd1 && cmd2 && cmd3 && cmd4"

# Single & (background) mixed with &&
check A14 "bg & mixed with && chains" 3 \
    "cmd1 & cmd2 && cmd3 && cmd4 && cmd5 && cmd6"

# &> redirection with &&
check A15 "&> redirect with && chains" 3 \
    "cmd1 &>/dev/null && cmd2 && cmd3 && cmd4 && cmd5"

# >& redirection with &&
check A16 ">& redirect with && chains" 3 \
    "cmd1 >&2 && cmd2 && cmd3 && cmd4 && cmd5"

# && at very start of line (after indent)
check A17 "&& at line start (continuation from prev line)" 4 \
    "    && cmd2 && cmd3 && cmd4 && cmd5 && cmd6"

# Empty commands between &&
check A18 "empty between ands" 3 "a && b && c && d && e"

echo ""
echo "=== Phase 5: Real-world patterns ==="
echo ""

check B01 "apt full system update chain" 5 \
    "apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove --purge -y && apt autoclean && snap refresh && flatpak update -y"

check B02 "docker build && push && deploy" 3 \
    "docker build -t app . && docker tag app:latest app:v2 && docker push app:v2 && kubectl apply -f deploy.yaml && kubectl rollout status deploy/app"

check B03 "git workflow chain" 4 \
    "git add -A && git commit -m 'fix' && git pull --rebase && git push && git tag v1.0 && git push --tags"

check B04 "npm/node toolchain" 4 \
    "npm ci && npm run lint && npm run test && npm run build && npm run deploy && npx sentry-cli releases new v1"

check B05 "python data pipeline" 4 \
    "python fetch_data.py && python clean.py && python transform.py && python analyze.py && python visualize.py && python deploy_report.py"

check B06 "systemd service restart chain" 3 \
    "systemctl stop app && systemctl daemon-reload && systemctl start app && systemctl status app && journalctl -u app -n 20"

echo ""
echo "=== Phase 6: Throughput (many lines) ==="
echo ""

# Generate 500 mixed lines
_thru=""
for ((_i=0; _i<500; _i++)); do
    case $((_i % 6)) in
        0) _thru+="echo line$_i"$'\n' ;;
        1) _thru+="# comment $_i"$'\n' ;;
        2) _thru+="cmd1 && cmd2 && cmd3 && cmd4 && cmd5 && cmd6"$'\n' ;;
        3) _thru+="a=$_i; b=$((_i+1)); c=$((_i+2)); d=$((_i+3))"$'\n' ;;
        4) _thru+="for i in {1..3}; do echo \"\$i\"; done"$'\n' ;;
        5) _thru+="apt update && apt upgrade && apt autoremove && snap refresh"$'\n' ;;
    esac
done
_start=$(_timestamp_ms 2>/dev/null || date +%s%3N 2>/dev/null || echo 0)
_lines=$(printf '%s' "$_thru" | awk -v dark=1 -f "$AWK" 2>&1 | wc -l)
_elapsed=$(( $(_timestamp_ms 2>/dev/null || date +%s%3N 2>/dev/null || echo 0) - _start ))
TNUM=$((TNUM+1))
echo "  ✓ throughput: 500 mixed lines → $_lines output lines in ${_elapsed}ms"
PASS=$((PASS+1))

echo ""
echo "=== Phase 7: Correctness — verify && count per line ==="
echo ""

# Verify that a line with N && operators produces correct output:
# First 2 && keep inline, 3rd+ gets wrapped (1 wrap per && beyond 2nd)
# So for N &&: wraps = max(0, N-2), output lines = wraps + 1
verify_and_count() {
    local name="$1" n_and="$2" input="$3"
    TNUM=$((TNUM+1))
    local output; output=$(printf '%s\n' "$input" | awk -v dark=1 -f "$AWK" 2>&1)
    # Count && in output (all lines)
    local out_ands; out_ands=$(printf '%s\n' "$output" | grep -o '&&' | wc -l)
    # Count \ at end of lines (wraps)
    local wraps; wraps=$(printf '%s\n' "$output" | grep -c '\\$' || true)
    local expected_wraps=$(( n_and > 2 ? n_and - 2 : 0 ))
    local expected_lines=$(( expected_wraps + 1 ))
    local actual_lines; actual_lines=$(printf '%s\n' "$output" | wc -l)

    local _errs=0
    [[ "$out_ands" == "$n_and" ]] || { _errs=$((_errs+1)); echo "    AND MISMATCH: expected $n_and &&, got $out_ands"; }
    [[ "$wraps" == "$expected_wraps" ]] || { _errs=$((_errs+1)); echo "    WRAP MISMATCH: expected $expected_wraps wraps, got $wraps"; }

    if [[ $_errs -eq 0 ]]; then
        PASS=$((PASS+1))
        echo "  ✓ $name: $n_and && → $wraps wraps, $actual_lines lines (all && preserved)"
    else
        FAIL=$((FAIL+1))
        echo "  ✗ $name FAILED"
        printf '%s\n' "$output" | sed 's/^/    /'
    fi
}

verify_and_count C01 2 "a && b && c"
verify_and_count C02 3 "a && b && c && d"
verify_and_count C03 4 "a && b && c && d && e"
verify_and_count C04 5 "a && b && c && d && e && f"
verify_and_count C05 7 "a && b && c && d && e && f && g && h"
verify_and_count C06 10 "a && b && c && d && e && f && g && h && i && j && k"
verify_and_count C07 15 "a && b && c && d && e && f && g && h && i && j && k && l && m && n && o && p"
verify_and_count C08 3 "x1 && x2; y1 && y2 && y3"
# total 4 ands per input line → wraps at 3rd, 4th
verify_and_count C09 4 "x1 && x2; y1 && y2 && y3 && y4"

echo ""
echo "================================================"
echo "Stress Results: $PASS passed, $FAIL failed, $TNUM total"
if ((FAIL > 0)); then
    exit 1
fi
exit 0
