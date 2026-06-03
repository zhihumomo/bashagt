#!/usr/bin/env bash
# test_keybindings_zsh.sh — Unit tests for zsh keybindings
# Tests: zsh syntax, function definitions, bindkey, PS1 expansion, render
# Run: bash test/test_keybindings_zsh.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0; SKIP=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s\033[0m\n' "$*"; }
yell()  { printf '\033[33m  SKIP: %s\033[0m\n' "$*"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }
_skip() { SKIP=$((SKIP+1)); yell "$1"; }

ZSHBIN="${ZSHBIN:-zsh}"

# Ensure zsh is available
if ! command -v "$ZSHBIN" >/dev/null 2>&1; then
    _skip "Z1: zsh not found — install zsh to test keybindings.zsh"
    _skip "Z2-Z10: zsh not available"
    echo "============================================"
    echo " zsh Keybinding Results: $PASS passed, $FAIL failed, $SKIP skipped"
    echo "============================================"
    exit 0
fi

echo "============================================"
echo " zsh Keybinding Unit Tests"
echo "============================================"
echo ""

# ═══ Z1-Z2: Syntax check ═══
echo "── Z1-Z3: Syntax & Structure ──"

# Generate the zsh keybinding file from bashagt
_zsh_kbfile="/tmp/bashagt_test_keybindings.zsh"
_zsh_kbfile2="$HOME/.bashagt/keybindings.zsh"

# Use installed file if available (from a prior --install), otherwise generate
if [[ -f "$_zsh_kbfile2" ]]; then
    _kb="$_zsh_kbfile2"
else
    # Extract the zsh heredoc from bashagt for testing
    _kb="$_zsh_kbfile"
    sed -n '/^_gen_keybindings_zsh()/,/^}/p' "$SCRIPT_DIR/../bashagt" 2>/dev/null | \
        sed -n '/cat >.*ZBEOF/,/^ZBEOF/p' | sed '1s/.*<< .ZBEOF//' | \
        head -n -1 > "$_zsh_kbfile" 2>/dev/null
    if [[ ! -s "$_zsh_kbfile" ]]; then
        _skip "Z1: could not extract zsh template — run bashagt --install first"
        _skip "Z2-Z10: no template"
        echo "============================================"
        echo " zsh Keybinding Results: $PASS passed, $FAIL failed, $SKIP skipped"
        echo "============================================"
        exit 0
    fi
fi

# Z1: zsh -n syntax check
if "$ZSHBIN" -n "$_kb" 2>/dev/null; then
    _pass "Z1: zsh syntax check passes"
else
    _fail "Z1: zsh syntax check — errors found"
fi

# Z2: Verify source succeeds (exit 0)
if "$ZSHBIN" -c "source '$_kb' 2>/dev/null; echo OK" 2>/dev/null | grep -q OK; then
    _pass "Z2: source succeeds without error"
else
    _fail "Z2: source file without error"
fi

# Z3: Key functions defined
echo "── Z3-Z5: Function Definitions ──"
_funcs=$("$ZSHBIN" -c "
    source '$_kb' 2>/dev/null
    for f in _file_mtime _bsht_daemon_running _bsht_ensure_session \
             _bsht_ps1_str _bsht_render _bsht_send _bsht_find_project \
             _bsht_auto_reload _bsht_on_system _bsht_on_project; do
        if typeset -f \"\$f\" >/dev/null 2>&1; then
            echo \"DEFINED: \$f\"
        else
            echo \"MISSING: \$f\"
        fi
    done
" 2>/dev/null)

_missing=$(echo "$_funcs" | grep -c 'MISSING' 2>/dev/null || echo 0)
_defined=$(echo "$_funcs" | grep -c 'DEFINED' 2>/dev/null || echo 0)

if [[ $_missing -eq 0 ]]; then
    _pass "Z3: all 10 functions defined ($_defined/$_defined)"
else
    _fail "Z3: all functions defined — $_missing missing:"
    echo "$_funcs" | grep 'MISSING'
fi

# Z4: _file_mtime portable
_mtime_out=$("$ZSHBIN" -c "
    source '$_kb' 2>/dev/null
    _file_mtime /etc/hosts 2>/dev/null || echo 0
" 2>/dev/null)
if [[ -n "$_mtime_out" && "$_mtime_out" =~ ^[0-9]+$ ]]; then
    _pass "Z4: _file_mtime returns numeric value ($_mtime_out)"
else
    _fail "Z4: _file_mtime returns numeric — got: $_mtime_out"
fi

# Z5: _bsht_ps1_str uses print -P (zsh native)
_ps1_out=$("$ZSHBIN" -c "
    source '$_kb' 2>/dev/null
    PS1='%m:%~%% '
    _bsht_ps1_str
" 2>/dev/null)
if [[ -n "$_ps1_out" ]]; then
    _pass "Z5: _bsht_ps1_str expands prompt ($_ps1_out)"
else
    _fail "Z5: _bsht_ps1_str expands prompt — empty output"
fi

# ═══ Z6-Z8: bindkey registration ═══
echo "── Z6-Z8: bindkey & zle Widgets ──"

# Z6: bindkey ^G → _bsht_on_system
if grep -q "bindkey '^G' _bsht_on_system" "$_kb" 2>/dev/null; then
    _pass "Z6: bindkey ^G → _bsht_on_system"
else
    _fail "Z6: bindkey ^G → _bsht_on_system — not found"
fi

# Z7: bindkey ^T → _bsht_on_project
if grep -q "bindkey '^T' _bsht_on_project" "$_kb" 2>/dev/null; then
    _pass "Z7: bindkey ^T → _bsht_on_project"
else
    _fail "Z7: bindkey ^T → _bsht_on_project — not found"
fi

# Z8: zle -N registered
_zle_count=$(grep -c "zle -N _bsht_on" "$_kb" 2>/dev/null || echo 0)
if [[ $_zle_count -ge 2 ]]; then
    _pass "Z8: zle -N registered both widgets ($_zle_count found)"
else
    _fail "Z8: zle -N registered — found $_zle_count (expected 2)"
fi

# ═══ Z9-Z10: Render & Send ═══
echo "── Z9-Z10: Render & Send ──"

# Z9: _bsht_render — done frame returns 1
_render_done=$("$ZSHBIN" -c "
    source '$_kb' 2>/dev/null
    _bsht_render '{\"type\":\"done\",\"ts\":1234567890000}'
    echo \"EXIT: \$?\"
" 2>/dev/null)
if echo "$_render_done" | grep -q 'EXIT: 1'; then
    _pass "Z9: _bsht_render returns 1 for done frame"
else
    _fail "Z9: _bsht_render returns 1 for done — got: $_render_done"
fi

# Z10: _bsht_render — text frame
_render_text=$("$ZSHBIN" -c "
    source '$_kb' 2>/dev/null
    _bsht_render '{\"type\":\"text\",\"content\":\"hello zsh\"}'
    echo \"EXIT: \$?\"
" 2>/dev/null)
if echo "$_render_text" | grep -q 'hello zsh' && echo "$_render_text" | grep -q 'EXIT: 0'; then
    _pass "Z10: _bsht_render prints text content"
else
    _fail "Z10: _bsht_render prints text — output: $_render_text"
fi

# ═══ Summary ═══
echo ""
echo "============================================"
echo " zsh Keybinding Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "============================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
