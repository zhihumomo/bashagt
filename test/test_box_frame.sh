#!/usr/bin/env bash
# test_box_frame.sh — Box-drawing frame correctness & stress test
# Pure bash, no external deps, < 1 second runtime.
# Tests the L14252-14316 box logic using simulated _bash_format output.

set -euo pipefail
shopt -s extglob

# ══════════════════════════════════════════════════════════════
# Minimal _strip_ansi (same logic as bashagt _strip_ansi_sgr)
# ══════════════════════════════════════════════════════════════
_strip_ansi() {
    local _s="$1"
    while [[ "$_s" == *$'\033['*'m'* ]]; do
        _s="${_s%%$'\033['*}${_s#*m}"
    done
    printf '%s' "$_s"
}

# ══════════════════════════════════════════════════════════════
# Mock _stream_emit — capture text events
# ══════════════════════════════════════════════════════════════
declare -a BOX_EVENTS=()
_stream_emit() {
    local _type="$1" _content="$2"
    if [[ "$_type" == "text" ]]; then
        BOX_EVENTS+=("$_content")
    fi
}

# ══════════════════════════════════════════════════════════════
# _run_box — exact copy of box-drawing logic from bashagt
# $1 = lines with ANSI (simulating _bash_format output)
# $2 = TERM_WIDTH (default 80)
# ══════════════════════════════════════════════════════════════
_run_box() {
    local _pre_fmt="$1" _term_w="${2:-80}"
    BOX_EVENTS=()
    [[ -z "$_pre_fmt" ]] && return 1

    local _pf_max=30 _pf_i _pf_line _pf_count
    local -a _pf_lines
    mapfile -t _pf_lines <<< "$_pre_fmt"
    _pf_count=${#_pf_lines[@]}

    # Phase 1: scan max display width
    local _max_w=0 _bare _w _pf_limit
    _pf_limit=$((_pf_count < _pf_max ? _pf_count : _pf_max))
    for ((_pf_i=0; _pf_i<_pf_limit; _pf_i++)); do
        _pf_line="${_pf_lines[_pf_i]}"
        [[ -z "$_pf_line" ]] && _pf_line=" "
        _bare=$(_strip_ansi "$_pf_line")
        _w=${#_bare}
        (( _w > _max_w )) && _max_w=$_w
    done

    # Phase 2: box dimensions
    local _box_w _inner _max_disp
    _box_w=$((_max_w + 6))
    (( _box_w < 14 )) && _box_w=14
    (( _box_w > _term_w - 2 )) && _box_w=$((_term_w - 2))
    _inner=$((_box_w - 2))
    _max_disp=$((_inner - 2))

    local _h="────────────────────────────────────────────────────────────────────────────────────────────────"
    local _lty=$'\033[93m' _rst=$'\033[0m'

    # Phase 3: top border
    local _pad_w=$((_box_w - 14))
    (( _pad_w < 0 )) && _pad_w=0
    _stream_emit "text" "${_lty}╭── Script ──${_h:0:_pad_w}╮${_rst}" || true

    # Phase 4: content lines
    local _disp _disp_w
    for ((_pf_i=0; _pf_i<_pf_limit; _pf_i++)); do
        _pf_line="${_pf_lines[_pf_i]}"
        [[ -z "$_pf_line" ]] && _pf_line=" "
        _bare=$(_strip_ansi "$_pf_line")
        _w=${#_bare}
        if (( _w > _max_disp )); then
            local _cut=$((_max_disp - 1))
            _disp="${_bare:0:_cut}…"
            _disp_w=$((_cut + 1))
        else
            _disp="$_pf_line"
            _disp_w=$_w
        fi
        _pad_w=$((_box_w - 4 - _disp_w))
        (( _pad_w < 0 )) && _pad_w=0
        local _pad_spaces; printf -v _pad_spaces "%${_pad_w}s" ""
        _stream_emit "text" "${_lty}│${_rst}  ${_disp}${_pad_spaces}${_lty}│${_rst}" || true
    done

    if (( _pf_count > _pf_max )); then
        local _pf_remaining=$((_pf_count - _pf_max))
        _stream_emit "text" "  ...(${_pf_remaining} more lines)" || true
    fi

    # Phase 5: bottom border
    _stream_emit "text" "${_lty}╰${_h:0:$((_box_w - 2))}╯${_rst}" || true
}

# ══════════════════════════════════════════════════════════════
# Helpers — simulate _bash_format output (with ANSI colors)
# ══════════════════════════════════════════════════════════════
_kw=$'\033[38;2;86;156;214m'  # keyword blue
_rst_c=$'\033[0m'
_fmt_cmd() { printf '%s%s%s %s' "$_kw" "$1" "$_rst_c" "${*:2}"; }

# ══════════════════════════════════════════════════════════════
# Test harness
# ══════════════════════════════════════════════════════════════
_G='\033[0;32m'; _R='\033[0;31m'; _RC='\033[0m'
_T=0; _P=0; _F=0
_ok() { _T=$((_T+1)); _P=$((_P+1)); printf '\r  %sok%s %s\n' "$_G" "$_RC" "${_CUR:-}"; }
_bad() { _T=$((_T+1)); _F=$((_F+1)); printf '\r  %sFAIL%s %s\n    %s→%s %s\n' "$_R" "$_RC" "${_CUR:-}" "$_R" "$_RC" "$1"; }
_desc() { _CUR=""; printf '\n%s\n  %s\n%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$1" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
_it() { _CUR="$1"; printf '  … %s' "$_CUR"; }
_vis() { _strip_ansi "$1"; }
_eq() { [[ "$1" == "$2" ]] && _ok || _bad "$3: expected '$2' got '$1'"; }
_ge() { (( $1 >= $2 )) && _ok || _bad "$3: expected >= $2 got $1"; }
_has() { [[ "$1" == *"$2"* ]] && _ok || _bad "$3: should contain '$2'"; }
_nohas() { [[ "$1" != *"$2"* ]] && _ok || _bad "$3: should NOT contain '$2'"; }

_lty=$'\033[93m'
_rst=$'\033[0m'

# ══════════════════════════════════════════════════════════════
# Phase 1: Width calculation
# ══════════════════════════════════════════════════════════════

_desc "Width calculation"

_test_w1() {
    _run_box "$(_fmt_cmd ls) -la"
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    _eq "${#_top}" "14" "short (6) → box_w=14"
}
_it "short cmd (6 chars) → box_w=14"; _test_w1

_test_w2() {
    local _txt; _txt="$(_fmt_cmd echo) \"hello world test\""  # 24 chars after strip
    _run_box "$_txt"
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    local _bare; _bare=$(_strip_ansi "$_txt")
    _eq "${#_top}" "$(( ${#_bare} + 6 ))" "box_w = max_w + 6"
}
_it "box_w = max_w + 6"; _test_w2

_test_w3() {
    local _txt; _txt=$(printf '%s' '' | awk 'BEGIN{for(i=0;i<110;i++)printf "x"}')  # 110 chars
    _run_box "$_txt" 80
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    _eq "${#_top}" "78" "long line → clamped to TERM-2=78"
}
_it "long line TERM=80 → clamped to 78"; _test_w3

_test_w4() {
    _run_box "x" 40
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    _eq "${#_top}" "14" "1-char TERM=40 → min box=14"
}
_it "1-char TERM=40 → box_w=14 (minimum)"; _test_w4

# ══════════════════════════════════════════════════════════════
# Phase 2: Box structure
# ══════════════════════════════════════════════════════════════

_desc "Box structure"

_test_s1() {
    _run_box "ls"
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    _has "$_top" "╭" "top-left ╭"
    _has "$_top" "╮" "top-right ╮"
}
_it "top: ╭ ╮ corners"; _test_s1

_test_s2() {
    _run_box "ls"
    local _bot; _bot=$(_vis "${BOX_EVENTS[-1]}")
    _has "$_bot" "╰" "bottom-left ╰"
    _has "$_bot" "╯" "bottom-right ╯"
}
_it "bottom: ╰ ╯ corners"; _test_s2

_test_s3() {
    _run_box "ls"
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    _has "$_top" "Script" "label Script"
}
_it "label 'Script' in top border"; _test_s3

_test_s4() {
    _run_box "ls"
    local _l; _l=$(_vis "${BOX_EVENTS[1]}")
    [[ "$_l" == "│"* && "$_l" == *"│" ]] && _ok || _bad "missing │: '$_l'"
}
_it "content: │...│ borders"; _test_s4

_test_s5() {
    _run_box "echo one"
    _eq "${#BOX_EVENTS[@]}" "3" "1-line → 3 events"
}
_it "1-line → 3 events"; _test_s5

_test_s6() {
    _run_box $'line1\nline2\nline3'
    _eq "${#BOX_EVENTS[@]}" "5" "3-line → 5 events"
}
_it "3-line → 5 events"; _test_s6

_test_s7() {
    _run_box "ls"
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    local _bot; _bot=$(_vis "${BOX_EVENTS[-1]}")
    _eq "${#_top}" "${#_bot}" "top/bottom width equal"
}
_it "top/bottom equal width"; _test_s7

# ══════════════════════════════════════════════════════════════
# Phase 3: Color wrapping
# ══════════════════════════════════════════════════════════════

_desc "Color wrapping"

_test_c1() {
    _run_box "ls"
    local _top="${BOX_EVENTS[0]}"
    [[ "$_top" == "$_lty"* ]] && _ok || _bad "top missing LIGHT_YELLOW"
    [[ "$_top" == *"$_rst" ]] && _ok || _bad "top missing RESET"
}
_it "top: LIGHT_YELLOW + RESET"; _test_c1

_test_c2() {
    _run_box "ls"
    local _bot="${BOX_EVENTS[-1]}"
    [[ "$_bot" == "$_lty"* && "$_bot" == *"$_rst" ]] && _ok || _bad "bottom color broken"
}
_it "bottom: LIGHT_YELLOW...RESET"; _test_c2

_test_c3() {
    _run_box "ls"
    local _l="${BOX_EVENTS[1]}"
    [[ "$_l" == "${_lty}│${_rst}"* ]] && _ok || _bad "left border not _lty│_rst"
    [[ "$_l" == *"${_lty}│${_rst}" ]] && _ok || _bad "right border not _lty│_rst"
}
_it "content: │ in LIGHT_YELLOW"; _test_c3

_test_c4() {
    _run_box "ls"
    local _l="${BOX_EVENTS[1]}"
    local _inner="${_l#${_lty}│${_rst}}"
    _inner="${_inner%${_lty}│${_rst}}"
    _nohas "$_inner" "$_lty" "text not yellow"
}
_it "text between │ not yellow"; _test_c4

# ══════════════════════════════════════════════════════════════
# Phase 4: Multi-line with ANSI
# ══════════════════════════════════════════════════════════════

_desc "Multi-line with ANSI colors"

_test_m1() {
    local _l1; _l1="$(_fmt_cmd cd) /tmp && \\"
    local _l2; _l2="   $(_fmt_cmd echo) \"hello\""
    _run_box "$_l1"$'\n'"$_l2"
    _ge "${#BOX_EVENTS[@]}" "4" "backslash cont → ≥4 events"
}
_it "backslash continuation renders"; _test_m1

_test_m2() {
    local _l1; _l1="$(_fmt_cmd cat) /tmp/log | $(_fmt_cmd grep) ERROR | $(_fmt_cmd wc) -l"
    _run_box "$_l1"
    _ge "${#BOX_EVENTS[@]}" "3" "pipe chain → ≥3 events"
}
_it "pipe chain renders"; _test_m2

_test_m3() {
    local _l1; _l1="$(_fmt_cmd echo) one; $(_fmt_cmd echo) two; $(_fmt_cmd echo) three"
    _run_box "$_l1"
    _ge "${#BOX_EVENTS[@]}" "3" "semicolons → renders"
}
_it "semicolon chain renders"; _test_m3

_test_m4() {
    local _txt; _txt="$(_fmt_cmd for) i in 1 2 3; $(_fmt_cmd do) $(_fmt_cmd echo) \"\$i\"; $(_fmt_cmd done)"
    _run_box "$_txt"
    _ge "${#BOX_EVENTS[@]}" "3" "for loop → renders"
}
_it "for/do/done renders"; _test_m4

_test_m5() {
    local _l1; _l1="$(_fmt_cmd if) [[ -f /tmp/x ]]; $(_fmt_cmd then) $(_fmt_cmd echo) yes; $(_fmt_cmd else) $(_fmt_cmd echo) no; $(_fmt_cmd fi)"
    _run_box "$_l1"
    _ge "${#BOX_EVENTS[@]}" "3" "if/fi → renders"
}
_it "if/then/else/fi renders"; _test_m5

# ══════════════════════════════════════════════════════════════
# Phase 5: Truncation
# ══════════════════════════════════════════════════════════════

_desc "Truncation"

_test_t1() {
    local _txt; _txt=$(printf 'echo "%s"' "$(printf '%0100s' 'x')")  # ~108 chars
    _run_box "$_txt" 80
    local _l1; _l1=$(_vis "${BOX_EVENTS[1]}")
    _has "$_l1" "…" "long line truncated"
}
_it "long line TERM=80 → truncated with …"; _test_t1

_test_t2() {
    local _txt; _txt=$(printf 'echo "%s"' "$(printf '%0100s' 'x')")
    _run_box "$_txt" 80
    local _l1="${BOX_EVENTS[1]}"
    local _inner="${_l1#*${_rst}}"
    _inner="${_inner%${_lty}*}"
    _nohas "$_inner" $'\033[' "no ANSI leak in truncated content"
}
_it "truncated: no raw ANSI leak"; _test_t2

_test_t3() {
    _run_box 'echo "short"' 80
    local _l1; _l1=$(_vis "${BOX_EVENTS[1]}")
    _nohas "$_l1" "…" "short → not truncated"
}
_it "short cmd: not truncated"; _test_t3

_test_t4() {
    local _txt; _txt="$(_fmt_cmd echo) \"this is a long command that overflows narrow terminal\""
    _run_box "$_txt" 40
    local _l1; _l1=$(_vis "${BOX_EVENTS[1]}")
    _has "$_l1" "…" "narrow TERM=40 truncated"
}
_it "narrow TERM=40: truncated"; _test_t4

# ══════════════════════════════════════════════════════════════
# Phase 6: Edge cases
# ══════════════════════════════════════════════════════════════

_desc "Edge cases"

_test_e1() {
    _run_box "" && _bad "expected return 1" || _ok
}
_it "empty → return 1"; _test_e1

_test_e2() {
    _run_box "x"
    local _top; _top=$(_vis "${BOX_EVENTS[0]}")
    _eq "${#_top}" "14" "1-char → box_w=14"
}
_it "1 char → min box"; _test_e2

_test_e3() {
    _run_box 'echo "$HOME" $((1+2)) ${var//a/b}'
    _eq "${#BOX_EVENTS[@]}" "3" "vars+expansion → 3 events"
}
_it "quotes, vars, expansions → renders"; _test_e3

_test_e4() {
    local _tok; _tok=$(printf '%0100s' 'A')
    _run_box "echo $_tok" 80
    local _l1; _l1=$(_vis "${BOX_EVENTS[1]}")
    _has "$_l1" "…" "100-char token truncated"
}
_it "100-char token → truncated"; _test_e4

_test_e5() {
    _run_box $'echo a\n\necho b'
    _ge "${#BOX_EVENTS[@]}" "3" "blank line → no crash"
}
_it "blank line → no crash"; _test_e5

_test_e6() {
    local _l1; _l1="$(_fmt_cmd echo) \"hello\" && $(_fmt_cmd echo) world"
    _run_box "$_l1"
    local _l; _l="${BOX_EVENTS[1]}"
    # ANSI-colored cmd should still have color codes inside
    [[ "$_l" == *"$_kw"* ]] && _ok || _bad "missing ANSI keyword color in content"
}
_it "ANSI colors preserved in content"; _test_e6

# ══════════════════════════════════════════════════════════════
# Phase 7: Stress — many rapid iterations
# ══════════════════════════════════════════════════════════════

_desc "Stress stability"

_test_stress1() {
    local _i _rc=0
    for ((_i=0; _i<100; _i++)); do
        _run_box "echo iteration_${_i}" 80 || { _rc=1; break; }
        local _top; _top=$(_vis "${BOX_EVENTS[0]}")
        [[ "$_top" == "╭"* ]] || { _rc=2; break; }
    done
    (( _rc == 0 )) && _ok || _bad "i=$_i rc=$_rc"
}
_it "100 iterations: structure valid"; _test_stress1

_test_stress2() {
    local _cmds=("ls" "echo hello" "echo 'hello world'" "cd /tmp && ls -la" "grep -rn x /tmp | head")
    local _c _rc=0
    for _c in "${_cmds[@]}"; do
        _run_box "$_c" 80 || { _rc=1; break; }
        local _top; _top=$(_vis "${BOX_EVENTS[0]}")
        local _bot; _bot=$(_vis "${BOX_EVENTS[-1]}")
        (( ${#_top} == ${#_bot} )) || { _rc=2; break; }
    done
    (( _rc == 0 )) && _ok || _bad "cmd='$_c' rc=$_rc"
}
_it "varied cmds: top/bottom widths match"; _test_stress2

_test_stress3() {
    local _i _j _rc=0
    for ((_i=0; _i<50; _i++)); do
        _run_box "echo test_${_i}" 80 || { _rc=1; break; }
        for ((_j=0; _j<${#BOX_EVENTS[@]}; _j++)); do
            local _ev="${BOX_EVENTS[$_j]}"
            [[ "$_ev" == *"$_rst" ]] || { _rc=2; break 2; }
        done
    done
    (( _rc == 0 )) && _ok || _bad "i=$_i j=$_j rc=$_rc"
}
_it "50 iterations: every event ends with RESET"; _test_stress3

_test_stress4() {
    local _i _rc=0
    for ((_i=0; _i<50; _i++)); do
        local _ml; printf -v _ml 'line_%d_a\nline_%d_b\nline_%d_c' $_i $_i $_i
        _run_box "$_ml" 80 || { _rc=1; break; }
        (( ${#BOX_EVENTS[@]} >= 4 )) || { _rc=2; break; }
    done
    (( _rc == 0 )) && _ok || _bad "i=$_i rc=$_rc"
}
_it "50 multi-line iterations: stable"; _test_stress4

_test_stress5() {
    local _w _rc=0
    for _w in 30 40 60 80 100 120; do
        _run_box "echo hello from terminal width $_w" "$_w" || { _rc=1; break; }
        local _top; _top=$(_vis "${BOX_EVENTS[0]}")
        (( ${#_top} <= _w - 2 )) || { _rc=2; break; }
    done
    (( _rc == 0 )) && _ok || _bad "w=$_w rc=$_rc"
}
_it "6 terminal widths (30-120): box within bounds"; _test_stress5

# ══════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════

echo ""
echo "══════════════════════════════════════════════════════════════════"
printf '  Box Frame: %s%d passed%s, %s%d failed%s, %d total\n' \
    "$_G" "$_P" "$_RC" "$_R" "$_F" "$_RC" "$_T"
echo "══════════════════════════════════════════════════════════════════"

(( _F > 0 )) && exit 1
exit 0
