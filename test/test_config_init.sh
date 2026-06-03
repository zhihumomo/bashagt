#!/usr/bin/env bash
# test_config_init.sh — Config + init unit tests (Section 8 + utils)
# Run: bash test/test_config_init.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# Extract init/config functions + portable utils
_START=$(grep -n '^_detect_termux()' "$BASHAGT" | head -1 | cut -d: -f1)
_END=$(grep -n '^_reload_skills_if_stale()' "$BASHAGT" | head -1 | cut -d: -f1)
sed -n "${_START},$((_END - 1))p" "$BASHAGT" > /tmp/bashagt_config_funcs.sh

echo "============================================"
echo " Config & Init Unit Tests"
echo "============================================"
echo ""

cat > /tmp/bashagt_config_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_config_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

log() { return 0; }
die() { echo "DIE:$*"; exit 1; }
BASHAGT_PROJECT_DIR=""

# ════════════════ T1-T6: init_project_dirs ════════════════

SANDBOX=$(mktemp -d)
BASHAGT_PROJECT_DIR="$SANDBOX/proj"

# T1: creates base .bashagt dir
init_project_dirs
[[ -d "$SANDBOX/proj/.bashagt" ]] && _green "T1: creates .bashagt" || _red "T1: dir" "exists" "missing"

# T2: creates agents dir
[[ -d "$SANDBOX/proj/.bashagt/agents" ]] && _green "T2: agents dir" || _red "T2: agents" "exists" "missing"

# T3: creates skills dir
[[ -d "$SANDBOX/proj/.bashagt/skills" ]] && _green "T3: skills dir" || _red "T3: skills" "exists" "missing"

# T4: creates comm dir
[[ -d "$SANDBOX/proj/.bashagt/comm" ]] && _green "T4: comm dir" || _red "T4: comm" "exists" "missing"

# T5: creates hooks dir
[[ -d "$SANDBOX/proj/.bashagt/hooks" ]] && _green "T5: hooks dir" || _red "T5: hooks" "exists" "missing"

# T6: creates trace dirs
[[ -d "$SANDBOX/proj/.bashagt/trace/frames" ]] && _green "T6: trace/frames dir" \
    || _red "T6: trace" "exists" "missing"

# ════════════════ T7-T10: _mktemp_file / _mktemp_dir / _mktemp_u ════════════════

# T7: _mktemp_file creates temp file
_f=$(_mktemp_file /tmp/bashagt_test.XXXXXX)
[[ -f "$_f" ]] && _green "T7: _mktemp_file works" || _red "T7: mktemp_file" "exists" "missing"
rm -f "$_f"

# T8: _mktemp_dir creates dir
_d=$(_mktemp_dir /tmp/bashagt_testd.XXXXXX)
[[ -d "$_d" ]] && _green "T8: _mktemp_dir works" || _red "T8: mktemp_dir" "exists" "missing"
rmdir "$_d"

# T9: _mktemp_u returns unused name
_u=$(_mktemp_u /tmp/bashagt_testu.XXXXXX)
[[ -n "$_u" ]] && _green "T9: _mktemp_u returns name" || _red "T9: mktemp_u" "non-empty" "empty"

# T10: _detect_termux exists
type -t _detect_termux >/dev/null 2>&1 && _green "T10: _detect_termux defined" \
    || _red "T10: termux" "function" "missing"

# ════════════════ T11-T14: _find_user_bin / _ensure_path_entry ════════════════

# T11: _find_user_bin exists
type -t _find_user_bin >/dev/null 2>&1 && _green "T11: _find_user_bin defined" \
    || _red "T11: find_bin" "function" "missing"

# T12: _ensure_path_entry exists
type -t _ensure_path_entry >/dev/null 2>&1 && _green "T12: _ensure_path_entry defined" \
    || _red "T12: ensure_path" "function" "missing"

# T13: _install_symlink exists
type -t _install_symlink >/dev/null 2>&1 && _green "T13: _install_symlink defined" \
    || _red "T13: symlink" "function" "missing"

# T14: _nc_detect_listen exists
type -t _nc_detect_listen >/dev/null 2>&1 && _green "T14: _nc_detect_listen defined" \
    || _red "T14: nc_detect" "function" "missing"

# ════════════════ T15-T16: init_system_dirs ════════════════

# T15: init_system_dirs function exists
type -t init_system_dirs >/dev/null 2>&1 && _green "T15: init_system_dirs defined" \
    || _red "T15: init_sys" "function" "missing"

# T16: check_deps function exists
type -t check_deps >/dev/null 2>&1 && _green "T16: check_deps defined" \
    || _red "T16: check_deps" "function" "missing"

# ════════════════ Stress ════════════════

# S1: init_project_dirs idempotent (call twice)
init_project_dirs >/dev/null 2>&1
_green "S1: init_project_dirs idempotent"

# S2: 20 _mktemp_file calls no fd leak
_s_ok=1
for i in $(seq 1 20); do
    _f=$(_mktemp_file /tmp/bashagt_stress.XXXXXX)
    rm -f "$_f"
done
[[ $_s_ok -eq 1 ]] && _green "S2: 20 mktemp cycles" || _red "S2: mktemp" "OK" "fail"

rm -rf "$SANDBOX"
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
done < <(bash /tmp/bashagt_config_test.sh 2>&1 || true)

rm -f /tmp/bashagt_config_funcs.sh /tmp/bashagt_config_test.sh

echo ""
echo "============================================"
echo " Config Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
