#!/usr/bin/env bash
# Test: verify portable awk comment-matching produces same results as GNU match()
set -euo pipefail

declare -i passed=0 failed=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        passed=$((passed+1))
        echo "  ✓ $label"
    else
        failed=$((failed+1))
        echo "  ✗ $label"
        printf "    expected: %q\n" "$expected"
        printf "    actual:   %q\n" "$actual"
    fi
}

# Check if gawk available
has_gawk=0
if echo | gawk 'BEGIN { exit 0 }' 2>/dev/null; then
    has_gawk=1
fi

# Portable awk program (same logic as the fix)
run_portable() {
    local input="$1"
    printf '%s\n' "$input" | awk '
    {
        line = $0
        if (line ~ /^[[:space:]]*#/) {
            m1 = line; sub(/[^[:space:]].*/, "", m1)
            m2 = line; sub(/^[[:space:]]*/, "", m2)
            printf "%s\n%s\n", m1, m2
        } else {
            printf "NO_MATCH\n"
        }
    }'
}

# GNU awk reference
run_gnu() {
    local input="$1"
    printf '%s\n' "$input" | gawk '
    {
        line = $0
        if (line ~ /^[[:space:]]*#/) {
            match(line, /^([[:space:]]*)(#.*)/, m)
            printf "%s\n%s\n", m[1], m[2]
        } else {
            printf "NO_MATCH\n"
        }
    }'
}

# Test cases: (input, expected_m1, expected_m2)
test_one() {
    local input="$1" exp_m1="$2" exp_m2="$3"
    local label="${input//$'\t'/\\t}"

    # Portable version
    local result
    result=$(run_portable "$input")
    local actual_m1 actual_m2
    { IFS= read -r actual_m1; IFS= read -r actual_m2; } <<< "$result"

    assert_eq "portable m1: [$label]" "$exp_m1" "$actual_m1"
    assert_eq "portable m2: [$label]" "$exp_m2" "$actual_m2"

    # Cross-validate with gawk
    if ((has_gawk)); then
        local gawk_result
        gawk_result=$(run_gnu "$input")
        local gawk_m1 gawk_m2
        { IFS= read -r gawk_m1; IFS= read -r gawk_m2; } <<< "$gawk_result"
        assert_eq "gawk m1: [$label]" "$exp_m1" "$gawk_m1"
        assert_eq "gawk m2: [$label]" "$exp_m2" "$gawk_m2"
    fi
}

echo "=== Comment extraction tests ==="
echo ""

test_one "# bare comment"            ""              "# bare comment"
test_one "  # indented comment"      "  "            "# indented comment"
test_one "    # 4 spaces"            "    "          "# 4 spaces"
test_one $'\t# tab indented'        $'\t'           "# tab indented"
test_one "  # hash # inside"        "  "            "# hash # inside"
test_one "#"                         ""              "#"
test_one "  #"                       "  "            "#"
test_one "            # deep"       "            "  "# deep"
test_one "## double hash"            ""              "## double hash"
test_one "  ## indented double"     "  "            "## indented double"
test_one "  # trailing spaces   "   "  "            "# trailing spaces   "
test_one $'\t\t# two tabs'          $'\t\t'         "# two tabs"

echo ""
echo "=== Non-matching lines ==="
echo ""

for input in "" "echo hello" "echo hello # inline" "    " "not a comment"; do
    result=$(run_portable "$input")
    assert_eq "non-match: [${input:-<empty>}]" "NO_MATCH" "$result"
    if ((has_gawk)); then
        gawk_result=$(run_gnu "$input")
        assert_eq "gawk non-match: [${input:-<empty>}]" "NO_MATCH" "$gawk_result"
    fi
done

echo ""
echo "=== Shebang (starts with #!) ==="
echo ""

result=$(run_portable "#!/usr/bin/env bash")
exp_m1=""
exp_m2="#!/usr/bin/env bash"
{ IFS= read -r actual_m1; IFS= read -r actual_m2; } <<< "$result"
assert_eq "shebang m1" "$exp_m1" "$actual_m1"
assert_eq "shebang m2" "$exp_m2" "$actual_m2"

if ((has_gawk)); then
    gawk_result=$(run_gnu "#!/usr/bin/env bash")
    { IFS= read -r gawk_m1; IFS= read -r gawk_m2; } <<< "$gawk_result"
    assert_eq "gawk shebang m1" "$exp_m1" "$gawk_m1"
    assert_eq "gawk shebang m2" "$exp_m2" "$gawk_m2"
fi

echo ""
echo ""
echo "=== Stress tests ==="
echo ""

# ── Stress 1: Long comment (4KB) ──
_long_prefix="  "
_long_body="# "; for ((_i=0; _i<4000; _i++)); do _long_body+="x"; done
_long_input="${_long_prefix}${_long_body}"
_long_result=$(run_portable "$_long_input")
{ IFS= read -r _lm1; IFS= read -r _lm2; } <<< "$_long_result"
assert_eq "long comment (4KB) m1" "$_long_prefix" "$_lm1"
assert_eq "long comment (4KB) m2 len" "${#_long_body}" "${#_lm2}"
[[ "$_long_body" == "$_lm2" ]] && { passed=$((passed+1)); echo "  ✓ long comment (4KB) content matches"; } || { failed=$((failed+1)); echo "  ✗ long comment (4KB) content mismatch"; }

if ((has_gawk)); then
    _gawk_long=$(run_gnu "$_long_input")
    { IFS= read -r _gm1; IFS= read -r _gm2; } <<< "$_gawk_long"
    assert_eq "gawk long comment (4KB) m1" "$_long_prefix" "$_gm1"
    assert_eq "gawk long comment (4KB) m2 len" "${#_long_body}" "${#_gm2}"
fi

# ── Stress 2: Deep indent (100 spaces) ──
_deep_prefix=$(printf '%100s' '')
_deep_input="${_deep_prefix}# deep comment"
_deep_result=$(run_portable "$_deep_input")
{ IFS= read -r _dm1; IFS= read -r _dm2; } <<< "$_deep_result"
assert_eq "deep indent (100sp) m1" "$_deep_prefix" "$_dm1"
assert_eq "deep indent (100sp) m2" "# deep comment" "$_dm2"

if ((has_gawk)); then
    _gawk_deep=$(run_gnu "$_deep_input")
    { IFS= read -r _gm1; IFS= read -r _gm2; } <<< "$_gawk_deep"
    assert_eq "gawk deep indent (100sp) m1" "$_deep_prefix" "$_gm1"
    assert_eq "gawk deep indent (100sp) m2" "# deep comment" "$_gm2"
fi

# ── Stress 3: Deep tab indent (20 tabs) ──
_tab_prefix=$(printf '\t%.0s' {1..20})
_tab_input="${_tab_prefix}# tab deep"
_tab_result=$(run_portable "$_tab_input")
{ IFS= read -r _tm1; IFS= read -r _tm2; } <<< "$_tab_result"
assert_eq "deep tab indent (20t) m1" "$_tab_prefix" "$_tm1"
assert_eq "deep tab indent (20t) m2" "# tab deep" "$_tm2"

if ((has_gawk)); then
    _gawk_tab=$(run_gnu "$_tab_input")
    { IFS= read -r _gm1; IFS= read -r _gm2; } <<< "$_gawk_tab"
    assert_eq "gawk deep tab indent (20t) m1" "$_tab_prefix" "$_gm1"
    assert_eq "gawk deep tab indent (20t) m2" "# tab deep" "$_gm2"
fi

# ── Stress 4: Unicode in comment ──
_uni_input="# 注释 comment コメント 💡 emoji — mdash"
_uni_result=$(run_portable "$_uni_input")
{ IFS= read -r _um1; IFS= read -r _um2; } <<< "$_uni_result"
assert_eq "unicode comment m1" "" "$_um1"
assert_eq "unicode comment m2" "$_uni_input" "$_um2"

if ((has_gawk)); then
    _gawk_uni=$(run_gnu "$_uni_input")
    { IFS= read -r _gm1; IFS= read -r _gm2; } <<< "$_gawk_uni"
    assert_eq "gawk unicode comment m1" "" "$_gm1"
    assert_eq "gawk unicode comment m2" "$_uni_input" "$_gm2"
fi

# ── Stress 5: Throughput — 1000 lines mixed code + comments ──
echo -n "  throughput: 1000 mixed lines..."
_thru_input=""
for ((_i=0; _i<1000; _i++)); do
    case $((_i % 5)) in
        0) _thru_input+="  # comment line $_i"$'\n' ;;
        1) _thru_input+="echo \"hello $_i\""$'\n' ;;
        2) _thru_input+="# bare comment $_i"$'\n' ;;
        3) _thru_input+="if [[ -f /tmp/x ]]; then"$'\n' ;;
        4) _thru_input+="    # indented comment $_i"$'\n' ;;
    esac
done
_thru_start=$(_timestamp_ms 2>/dev/null || date +%s%3N 2>/dev/null || echo 0)
_thru_result=$(printf '%s' "$_thru_input" | awk '
{
    line = $0
    if (line ~ /^[[:space:]]*#/) {
        m1 = line; sub(/[^[:space:]].*/, "", m1)
        m2 = line; sub(/^[[:space:]]*/, "", m2)
    } else {
        m1 = "NO_MATCH"
        m2 = ""
    }
}
END { printf "%d\n", NR }')
_thru_elapsed=$(( $(_timestamp_ms 2>/dev/null || date +%s%3N 2>/dev/null || echo 0) - _thru_start ))
if [[ "$_thru_result" == "1000" ]]; then
    passed=$((passed+1))
    echo " ✓ (${_thru_elapsed}ms)"
else
    failed=$((failed+1))
    echo " ✗ expected 1000 lines, got $_thru_result"
fi

# ── Stress 6: Comment-like strings in code (must NOT match) ──
# Build input and expected programmatically to avoid quoting hell
_thru_fp_lines=(
    'echo "# not a comment"'
    "x='# also not a comment'"
    'var="## still not"'
    "cat <<'EOF'"
    '# heredoc content'
    'EOF'
    'echo done'
)
_thru_fp_input=''
_thru_fp_expected=''
for _line in "${_thru_fp_lines[@]}"; do
    _thru_fp_input+="$_line"$'\n'
    case "$_line" in
        '#'*) _thru_fp_expected+="COMMENT:$_line"$'\n' ;;
        *)    _thru_fp_expected+="CODE:$_line"$'\n' ;;
    esac
done
_thru_fp_result=$(printf '%s' "$_thru_fp_input" | awk '
{
    line = $0
    if (line ~ /^[[:space:]]*#/) { print "COMMENT:" line }
    else { print "CODE:" line }
}')
# Trim trailing newline from expected (added by loop)
_thru_fp_expected="${_thru_fp_expected%$'\n'}"
if [[ "$_thru_fp_result" == "$_thru_fp_expected" ]]; then
    passed=$((passed+1))
    echo "  ✓ false-positive guard: code-like comments correctly classified"
else
    failed=$((failed+1))
    echo "  ✗ false-positive guard FAILED"
    echo "    expected: $_thru_fp_expected"
    echo "    actual:   $_thru_fp_result"
fi

# ── Stress 7: Only a single # character ──
_hash_result=$(run_portable "#")
{ IFS= read -r _hm1; IFS= read -r _hm2; } <<< "$_hash_result"
assert_eq "bare # m1" "" "$_hm1"
assert_eq "bare # m2" "#" "$_hm2"

# ── Stress 8: Spaces then # with no text after ──
_sp_hash_result=$(run_portable "    #")
{ IFS= read -r _sm1; IFS= read -r _sm2; } <<< "$_sp_hash_result"
assert_eq "spaces+# m1" "    " "$_sm1"
assert_eq "spaces+# m2" "#" "$_sm2"

echo ""
echo "================================================"
echo "Results: $passed passed, $failed failed"
if ((failed > 0)); then
    exit 1
fi
exit 0
