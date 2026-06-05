#!/bin/bash
# Comprehensive test for bash_format.awk + sed line-breaking pipeline
AWK="test/bash_format.awk"
PASS=0; FAIL=0; TNUM=0

# awk-only test (no sed pre-processing)
check_raw() {
    local name="$1" desc="$2"; TNUM=$((TNUM+1))
    local output; output=$(awk -v dark=1 -f "$AWK" 2>&1)
    local rc=$?; local has_color=0
    [[ "$output" == *$'\033'* ]] && has_color=1
    printf '%-8s %-52s color=%d rc=%d\n' "$name" "$desc" "$has_color" "$rc"
    [[ "$name" == S* ]] && return
    printf '  > %s\n' "$output"
}

# Full pipeline test (awk handles line-breaking internally, no sed needed)
check_pipe() {
    local name="$1" desc="$2"; TNUM=$((TNUM+1))
    local output; output=$(awk -v dark=1 -f "$AWK" 2>&1)
    local rc=$?; local has_color=0
    [[ "$output" == *$'\033'* ]] && has_color=1
    # Count lines
    local lines; lines=$(printf '%s\n' "$output" | wc -l)
    printf '%-8s %-46s color=%d lines=%-3d rc=%d\n' "$name" "$desc" "$has_color" "$lines" "$rc"
    [[ "$name" == S* ]] && return
    printf '  > %s\n' "$output"
}

echo "=== Phase 1: awk-only (no sed) ==="

echo 'echo hello'                                    | check_raw T01 "simple"
echo '# comment'                                     | check_raw T02 "comment"
echo 'echo "hello world"'                            | check_raw T03 "dq string"
echo "echo 'hello world'"                            | check_raw T04 "sq string"
echo 'echo $HOME'                                    | check_raw T05 "variable"
echo 'if true; then echo yes; fi'                    | check_raw T06 "if/then/fi"
echo 'for f in *.txt; do echo "$f"; done'            | check_raw T07 "for/do/done"

echo ""
echo "=== Phase 2: awk line-breaking (; split + ;; intact, string-safe) ==="

# Simple semicolons
echo 'echo one; echo two; echo three'                | check_pipe P01 "three stmts"
echo 'echo hello; echo world'                        | check_pipe P02 "two stmts"

# for loops with semicolons
echo 'for i in {1..3}; do echo "$i"; sleep 1; done'  | check_pipe P03 "for loop one-liner"

# Full real-world command from user screenshot
echo 'for i in {1..10}; do echo "$(date +%H:%M:%S) → $RANDOM"; sleep 1; done; echo "DONE"' | check_pipe P04 "real-world 10s loop"

# if/then/fi one-liner
echo 'if [[ -f /tmp/x ]]; then echo yes; else echo no; fi' | check_pipe P05 "if/then/else one-liner"

# Multi-keyword
echo 'cd /tmp; export X=1; local y=2; echo "$X $y"; return 0' | check_pipe P06 "builtins chain"

# Semicolon inside string (edge case - breaks at ; inside string)
echo 'echo "hello; world"; echo done'               | check_pipe P07 "semicolon in dq string"

# Case statement one-liner
echo 'case $x in a) echo A;; b) echo B;; esac'       | check_pipe P08 "case one-liner"

echo ""
echo "=== Phase 3: Stress ==="
(for i in {1..50}; do echo "echo \"line $i\""; done)         | check_raw S01 "50 echo lines"
(for i in {1..100}; do echo "export VAR${i}=${i}"; done)     | check_raw S02 "100 export lines"
(echo 'x=0'; for i in {1..50}; do echo "x=\$((x + $i))"; echo "echo \$x"; done) | check_raw S03 "50 arithmetic"

echo ""
echo "Total tests: $TNUM"
