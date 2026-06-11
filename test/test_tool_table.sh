#!/usr/bin/env bash
# test_tool_table.sh — Test table() tool rendering correctness
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0; TNUM=0

# ── Extract required functions from bashagt ──
EXTRACT_DIR="${TEST_TMPDIR:-/tmp}/tool_table_test"
rm -rf "$EXTRACT_DIR" 2>/dev/null; mkdir -p "$EXTRACT_DIR"

# Extract _str_display_width + helpers
sed -n '/^_is_wide_codepoint()/,/^}/p' "$BASHAGT" > "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"
sed -n '/^_is_zero_width_codepoint()/,/^}/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"
sed -n '/^_str_display_width()/,/^}/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"

# Extract _strip_ansi_sgr
sed -n '/^_strip_ansi_sgr()/,/^}/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"

# Extract tool_table
sed -n '/^tool_table()/,/^}/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"

source "$EXTRACT_DIR/funcs.sh"

# ── Helpers ──
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TNUM=$((TNUM+1))
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS+1)); echo "  ✓ $label"
    else
        FAIL=$((FAIL+1))
        echo "  ✗ $label"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    TNUM=$((TNUM+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1)); echo "  ✓ $label"
    else
        FAIL=$((FAIL+1)); echo "  ✗ $label: missing '$needle'"
    fi
}

strip_ansi() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'; }

echo "=== Basic table with header ==="
out=$(tool_table '{"columns":["Name","Size"],"align":["left","right"],"rows":[["a.py","1.2K"],["b.py","8.0K"]]}')
assert_contains "top border" "$out" "┌"
assert_contains "bottom border" "$out" "└"
assert_contains "header Name" "$out" "Name"
assert_contains "header Size" "$out" "Size"
assert_contains "data a.py" "$out" "a.py"
assert_contains "separator" "$out" "├"
echo "$out"

echo "=== No header ==="
out=$(tool_table '{"rows":[["x","y"],["z","w"]]}')
assert_contains "no-header top" "$out" "┌"
if [[ "$out" != *"├"* ]]; then
    PASS=$((PASS+1)); echo "  ✓ no separator without header"
else
    FAIL=$((FAIL+1)); echo "  ✗ unexpected separator"
fi
echo "$out"

echo "=== Right alignment ==="
out=$(tool_table '{"columns":["Item","Count"],"align":["left","right"],"rows":[["apples","123"],["bananas","9"]]}')
assert_contains "right-align 9" "$out" " 9 "
echo "$out"

echo "=== CJK ==="
out=$(tool_table '{"columns":["文件","大小"],"align":["left","right"],"rows":[["测试.py","1.5K"],["数据.csv","2.0M"]]}')
assert_contains "CJK header" "$out" "文件"
assert_contains "CJK data" "$out" "测试.py"
echo "$out"

echo "=== Emoji ==="
out=$(tool_table '{"columns":["Status","File"],"rows":[["✔","pass.txt"],["✘","fail.txt"],["⚠","warn.txt"]]}')
assert_contains "emoji ✔" "$out" "✔"
assert_contains "emoji ✘" "$out" "✘"
echo "$out"

echo "=== Border width consistency ==="
out=$(tool_table '{"columns":["A","B","C"],"rows":[["1","2","3"]]}')
readarray -t lines <<< "$out"
_top_w=${#lines[0]}; _bot_w=${#lines[-1]}
assert_eq "top=bottom width" "$_top_w" "$_bot_w"
for ((i=0; i<${#lines[@]}; i++)); do
    _lw=${#lines[i]}
    [[ "$_lw" == "$_top_w" ]] || { FAIL=$((FAIL+1)); echo "  ✗ line $i width $_lw != $_top_w"; }
done
echo "$out"

echo "=== Wide table clamp ==="
# Create 10-column wide table to test TERM_WIDTH clamping
_cols='["A","B","C","D","E","F","G","H","I","J"]'
_rows='[["aaaaaaaaaa","bbbbbbbbbb","cccccccccc","dddddddddd","eeeeeeeeee","ffffffffff","gggggggggg","hhhhhhhhhh","iiiiiiiiii","jjjjjjjjjj"]]'
out=$(TERM_WIDTH=80 tool_table "{\"columns\":$_cols,\"rows\":$_rows}")
readarray -t lines <<< "$out"
_top_w=${#lines[0]}
# Should be <= TERM_WIDTH
if [[ $_top_w -le 80 ]]; then
    PASS=$((PASS+1)); echo "  ✓ wide table clamped to 80 (actual $_top_w)"
else
    FAIL=$((FAIL+1)); echo "  ✗ wide table NOT clamped: $_top_w > 80"
fi
echo "$out"

echo "=== Min column width 4 ==="
out=$(tool_table '{"rows":[["a","b"]]}')
echo "$out"
assert_contains "min col width" "$out" " a "

echo "=== Empty rows ==="
out=$(tool_table '{"rows":[]}')
assert_eq "empty rows" "" "$out"

echo ""
echo "================================================"
echo "Results: $PASS passed, $FAIL failed, $TNUM total"
(( FAIL > 0 )) && exit 1
exit 0
