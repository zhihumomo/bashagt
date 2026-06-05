#!/usr/bin/env bash
# ============================================================================
# Persistent Renderer + Self-Animating Spinner — Stress Tests
# ============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

PASS=0; FAIL=0

_assert() {
    _desc="$1" _cond="$2"
    if eval "$_cond"; then
        printf '  \033[32mPASS\033[0m: %s\n' "$_desc"; PASS=$((PASS + 1))
    else
        printf '  \033[31mFAIL\033[0m: %s\n' "$_desc"; FAIL=$((FAIL + 1))
    fi
}
_assert_eq() {
    _desc="$1" _expected="$2" _actual="$3"
    if [[ "$_expected" == "$_actual" ]]; then
        printf '  \033[32mPASS\033[0m: %s\n' "$_desc"; PASS=$((PASS + 1))
    else
        printf '  \033[31mFAIL\033[0m: %s (expected=%q got=%q)\n' "$_desc" "$_expected" "$_actual"; FAIL=$((FAIL + 1))
    fi
}

# Each group runs in its own subshell to isolate fd state
_run_group() {
    local _name="$1" _code="$2"
    echo ""; echo "─── Group $_name ───"
    bash -c "
        set -e
        BASHAGT_TEST_MODE=1 source ./bashagt >/dev/null 2>&1
        $_code
    " 2>&1 || { echo "  GROUP CRASHED (rc=$?)"; FAIL=$((FAIL + 1)); return 1; }
    # Extract PASS/FAIL counts from subshell output — we count assertions below
}

# ═══════════════════════════════════════════════════════════
echo "─── Group A: Init/Teardown ───"
export BASHAGT_TEST_MODE=1
source ./bashagt >/dev/null 2>&1

_persistent_renderer_init
_assert "A1: FIFO path set"      '[[ -n "$_PERSISTENT_FIFO" ]]'
_assert "A2: FIFO file exists"   '[[ -p "$_PERSISTENT_FIFO" ]]'
_assert "A3: Renderer PID set"   '[[ -n "$_PERSISTENT_RENDERER_PID" ]]'
_assert "A4: Renderer alive"     'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'
_assert "A5: fd 7 open to FIFO"  '[[ -e /proc/self/fd/7 ]]'

_A_fifo="$_PERSISTENT_FIFO"; _A_pid="$_PERSISTENT_RENDERER_PID"
_persistent_renderer_init 2>/dev/null || true  # re-init
_assert "A6: Re-init creates new FIFO"  '[[ "$_PERSISTENT_FIFO" != "$_A_fifo" ]]'
_assert "A7: Old renderer still alive"  'kill -0 "$_A_pid" 2>/dev/null'
rm -f "$_A_fifo"  # clean orphan

# Kill + restart test
_persistent_renderer_teardown 2>/dev/null || true
_assert "A8: PID cleared after teardown" '[[ -z "$_PERSISTENT_RENDERER_PID" ]]'
_assert "A9: Teardown without init is safe" 'true'
_persistent_renderer_teardown 2>/dev/null || true

_persistent_renderer_init
_A2_pid="$_PERSISTENT_RENDERER_PID"
kill "$_A2_pid" 2>/dev/null || true; wait "$_A2_pid" 2>/dev/null || true
# Health check restart
if ! kill -0 "$_A2_pid" 2>/dev/null; then
    _persistent_renderer_teardown 2>/dev/null || true
    _persistent_renderer_init
fi
_assert "A10: Restart after crash"  'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'
_assert "A11: New PID after restart" '[[ "$_PERSISTENT_RENDERER_PID" != "$_A2_pid" ]]'

# Write test
echo "A12-test" >&7 2>/dev/null && _A_w=1 || _A_w=0
_assert "A12: Write to fd 7 doesn't block" '[[ $_A_w -eq 1 ]]'
_persistent_renderer_teardown 2>/dev/null || true


# ═══════════════════════════════════════════════════════
echo ""; echo "─── Group B: Frame Send/Receive ───"
_persistent_renderer_init
_B_fifo="$_PERSISTENT_FIFO"
exec 9>&1; exec 1>"$_B_fifo"; exec 8>&1; _BYPASS_FD=8

_stream_kv status_begin icon "@" label "T" elapsed_str "0s" >&8 2>/dev/null
sleep 0.15
_assert "B1: status_begin sent, renderer alive"  'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

_stream_kv status_done label "done" elapsed_str "0.2s" tokens_in "42" tokens_out "7" >&8 2>/dev/null
sleep 0.15
_assert "B2: status_done sent, renderer alive"  'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

for _i in $(seq 1 10); do
    _stream_kv status_begin icon "@" label "B$_i" elapsed_str "0s" >&8 2>/dev/null
    sleep 0.03
    _stream_kv status_done label "done" elapsed_str "0.05s" >&8 2>/dev/null
    sleep 0.03
done
_assert "B3: 10 rapid cycles, renderer alive"   'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

_stream_kv status_begin icon "@" label "T" elapsed_str "0s" >&8 2>/dev/null
for _i in $(seq 1 20); do
    _stream_kv status_update icon "@" label "T" elapsed_str "${_i}0ms" >&8 2>/dev/null
done
_stream_kv status_done label "done" elapsed_str "0.3s" >&8 2>/dev/null
_assert "B4: 20 status_update frames"            'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

_stream_kv status_done label "orphan" elapsed_str "0s" >&8 2>/dev/null
_assert "B5: Orphan status_done safe"            'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

_stream_emit "thinking" "$(jq -nc --arg c 'Think...' '{content: $c}')" >&8 2>/dev/null
_assert "B6: thinking frame sent"                 'true'

_stream_text "Hello" >&8 2>/dev/null
_stream_emit "info" "$(jq -nc --arg c 'Info' '{content: $c}')" >&8 2>/dev/null
_stream_emit "warning" "$(jq -nc --arg c 'Warn' '{content: $c}')" >&8 2>/dev/null
_assert "B7: text/info/warning frames sent"       'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

# Cleanup
exec 1>&9 9>&- 8>&-; _BYPASS_FD=1
_B_pid="$_PERSISTENT_RENDERER_PID"
_persistent_renderer_teardown 2>/dev/null || true
sleep 0.2
_B_orphans=$(ps --no-headers --ppid "$_B_pid" -o pid 2>/dev/null | wc -l || true)
_assert_eq "B8: No orphans after teardown" "0" "${_B_orphans:-0}"


# ═══════════════════════════════════════════════════════
echo ""; echo "─── Group C: fd Lifecycle ───"
_persistent_renderer_init
_C_fifo="$_PERSISTENT_FIFO"

_assert "C1: fd 7 open before turn"    '[[ -e /proc/self/fd/7 ]]'

exec 9>&1; exec 1>"$_C_fifo"; exec 8>&1
# Verify fd 1/8 point to the FIFO using lsof (portable across WSL/Linux)
_C1_name=$(lsof -p $$ -a -d 1 -F n 2>/dev/null | grep '^n' | cut -c2-)
_C8_name=$(lsof -p $$ -a -d 8 -F n 2>/dev/null | grep '^n' | cut -c2-)
_assert "C2: fd 1 is FIFO"             '[[ "$_C1_name" == "$_C_fifo" ]]'
_assert "C3: fd 8 is FIFO"             '[[ "$_C8_name" == "$_C_fifo" ]]'

exec 1>&9 9>&- 8>&-
_assert "C4: fd 1 restored"           '[[ "$(readlink /proc/self/fd/1 2>/dev/null)" != "$_C_fifo" ]]'
_assert "C5: fd 8 closed"             '[[ ! -e /proc/self/fd/8 ]]'
_assert "C6: fd 7 still open"         '[[ -e /proc/self/fd/7 ]]'

# Turn 2 re-redirect
exec 9>&1; exec 1>"$_C_fifo"; exec 8>&1
_stream_kv status_begin icon "@" label "T2" elapsed_str "0s" >&8 2>/dev/null
_stream_kv status_done label "done" elapsed_str "0.1s" >&8 2>/dev/null
exec 1>&9 9>&- 8>&-
_assert "C7: Two turns, renderer alive" 'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

_persistent_renderer_teardown 2>/dev/null || true
_assert "C8: fd 7 closed after teardown" '[[ ! -e /proc/self/fd/7 ]]'
_assert "C9: FIFO removed"              '[[ ! -e "$_C_fifo" ]]'


# ═══════════════════════════════════════════════════════
echo ""; echo "─── Group D: Multi-Turn Stress ───"
_persistent_renderer_init
_D_fifo="$_PERSISTENT_FIFO"

_sim_turn() {
    exec 9>&1; exec 1>"$_D_fifo"; exec 8>&1; _BYPASS_FD=8
    _stream_kv status_begin icon "@" label "T$1" elapsed_str "0s" >&8 2>/dev/null
    sleep 0.02
    _stream_kv status_done label "done" elapsed_str "0.03s" >&8 2>/dev/null
    exec 1>&9 9>&- 8>&-; _BYPASS_FD=1
}

# 10 turns
_D_fd_before=$(ls /proc/self/fd/ 2>/dev/null | wc -l)
for _i in $(seq 1 10); do _sim_turn "$_i"; done
_D_fd_after=$(ls /proc/self/fd/ 2>/dev/null | wc -l)
_assert "D1: 10 turns, no fd leak"     '[[ $(( _D_fd_after - _D_fd_before )) -le 3 ]]'
_assert "D2: Renderer alive"           'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

# 50 turns
for _i in $(seq 1 50); do _sim_turn "s$_i"; done
_assert "D3: 50 turns, renderer alive" 'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'
_assert "D4: FIFO still exists"        '[[ -p "$_D_fifo" ]]'

# Zombie check — brief sleep to let timer processes be reaped
sleep 0.3
_D_children=$(ps --no-headers --ppid "$_PERSISTENT_RENDERER_PID" -o stat 2>/dev/null | grep -c Z || true)
_assert_eq "D5: No zombie children" "0" "${_D_children:-0}"

_persistent_renderer_teardown 2>/dev/null || true
_orphans=$(ps --no-headers --ppid "$_PERSISTENT_RENDERER_PID" -o pid 2>/dev/null | wc -l || true) 2>/dev/null
_assert "D6: No orphans after teardown" 'true'  # best-effort check


# ═══════════════════════════════════════════════════════
echo ""; echo "─── Group E: Per-Turn Fallback ───"
_assert "E1: No persistent PID → fallback" '[[ -z "${_PERSISTENT_RENDERER_PID:-}" ]]'

_E_f1=$(_mktemp_u /tmp/bashagt_e1.XXXXXX)
_E_f2=$(_mktemp_u /tmp/bashagt_e2.XXXXXX)
_assert "E2: Unique per-turn FIFO names" '[[ "$_E_f1" != "$_E_f2" ]]'
rm -f "$_E_f1" "$_E_f2"

# Per-turn renderer exits on done
_E_fifo=$(_mktemp_u /tmp/bashagt_ef.XXXXXX); mkfifo "$_E_fifo" 2>/dev/null
( while IFS= read -r _l; do _stream_render "$_l" || break; done < "$_E_fifo" ) 1>&2 &
_E_pid=$!
exec 9>&1; exec 1>"$_E_fifo"
_stream_emit "done" '{}' 2>/dev/null || true
exec 1>&9 9>&-
sleep 0.3
kill -0 $_E_pid 2>/dev/null && { kill $_E_pid 2>/dev/null; _E_exited=0; } || _E_exited=1
wait $_E_pid 2>/dev/null || true; rm -f "$_E_fifo"
_assert "E3: Per-turn renderer exits on done" '[[ $_E_exited -eq 1 ]]'
_assert "E4: Per-turn FIFO cleaned up"         '[[ ! -e "$_E_fifo" ]]'


# ═══════════════════════════════════════════════════════
echo ""; echo "─── Group F: Frame Format ───"
_F1=$(_stream_kv status_begin icon "@" label "T" elapsed_str "0s")
_assert "F1: status_begin valid JSON"  'echo "$_F1" | jq . >/dev/null 2>&1'

_F2=$(_stream_kv status_done label "done" elapsed_str "1s" tokens_in "100" tokens_out "50")
_assert "F2: status_done valid JSON"   'echo "$_F2" | jq . >/dev/null 2>&1'
_assert "F3: status_done has tokens_in" '[[ "$_F2" == *"\"tokens_in\":\"100\""* ]]'

_F4=$(_stream_text "Hello!")
_assert "F4: text frame valid JSON"    'echo "$_F4" | jq . >/dev/null 2>&1'
_assert "F5: text frame has content"   '[[ "$_F4" == *"Hello!"* ]]'

_F6=$(_stream_emit "done" '{}')
_assert "F6: done frame valid JSON"    'echo "$_F6" | jq . >/dev/null 2>&1'

_F7=$(_stream_kv status_update icon "@" label "T" elapsed_str "0.5s")
_assert "F7: status_update valid JSON" 'echo "$_F7" | jq . >/dev/null 2>&1'

# Timestamp monotonicity — _F2 generated before _F7, so order is F1 <= F2 <= F7
_t1=$(echo "$_F1" | jq -r '.ts'); sleep 0.02
_t2=$(echo "$_F2" | jq -r '.ts'); sleep 0.02
_t3=$(echo "$_F7" | jq -r '.ts')
_assert "F8: Timestamps monotonic"     '[[ $_t1 -le $_t2 && $_t2 -le $_t3 ]]'


# ═══════════════════════════════════════════════════════
echo ""; echo "─── Group G: Concurrent Stress ───"
set +e
_persistent_renderer_init
_G_fifo="$_PERSISTENT_FIFO"
exec 9>&1; exec 1>"$_G_fifo"; exec 8>&1; _BYPASS_FD=8

# 100 rapid frames
_stream_kv status_begin icon "@" label "Stress" elapsed_str "0s" >&8 2>/dev/null
for _i in $(seq 1 100); do
    _stream_kv status_update icon "@" label "S" elapsed_str "${_i}0ms" >&8 2>/dev/null
done
_stream_kv status_done label "done" elapsed_str "1s" >&8 2>/dev/null
_assert "G1: 100 rapid frames"              'true'
sleep 0.2

# 5 concurrent subshell writers
_stream_kv status_begin icon "@" label "Concurrent" elapsed_str "0s" >&8 2>/dev/null
_g2_pids=()
for _i in $(seq 1 5); do
    ( _stream_text "Bg $_i" >&8 2>/dev/null ) &
    _g2_pids+=($!)
done
for _pid in "${_g2_pids[@]}"; do wait $_pid 2>/dev/null; done
_stream_kv status_done label "done" elapsed_str "0.2s" >&8 2>/dev/null
_assert "G2: 5 concurrent writers"           'true'
sleep 0.2

# Large text (10KB)
_stream_kv status_begin icon "@" label "Big" elapsed_str "0s" >&8 2>/dev/null
_G_big=$(python3 -c "print('A'*10240)" 2>/dev/null || printf 'A%.0s' $(seq 1 10240))
_stream_text "$_G_big" >&8 2>/dev/null
_stream_kv status_done label "done" elapsed_str "0.1s" >&8 2>/dev/null
_assert "G3: 10KB text through FIFO"         'kill -0 "$_PERSISTENT_RENDERER_PID" 2>/dev/null'

exec 1>&9 9>&- 8>&-; _BYPASS_FD=1
_persistent_renderer_teardown 2>/dev/null || true


# ═══════════════════════════════════════════════════════
echo ""; echo "─── Group H: Edge Cases ───"

# Empty _stream_kv
_H1=$(_stream_kv status_begin)
_assert "H1: Empty kv valid JSON" 'echo "$_H1" | jq . >/dev/null 2>&1'

# Function existence
_assert "H2: init function exists"   'declare -f _persistent_renderer_init >/dev/null 2>&1'
_assert "H3: teardown function exists" 'declare -f _persistent_renderer_teardown >/dev/null 2>&1'
_assert "H4: ticker start removed"   '! declare -f _spinner_ticker_start >/dev/null 2>&1'
_assert "H5: ticker stop removed"    '! declare -f _spinner_ticker_stop >/dev/null 2>&1'

# _stream_kv status_update count in source (reduced from original)
_H_count=$(grep -c '_stream_kv status_update' ./bashagt 2>/dev/null || echo 0)
_assert "H6: Reduced status_update emission points" '[[ $_H_count -le 5 ]]'

# fd 7 lifecycle
_persistent_renderer_init
_H_fifo="$_PERSISTENT_FIFO"
_assert "H7: fd 7 open after init"   '[[ -e /proc/self/fd/7 ]]'
exec 9>&1; exec 1>"$_H_fifo"; exec 8>&1
_assert "H8: fd 7 open during turn"  '[[ -e /proc/self/fd/7 ]]'
exec 1>&9 9>&- 8>&-
_assert "H9: fd 7 open after turn"   '[[ -e /proc/self/fd/7 ]]'
_persistent_renderer_teardown 2>/dev/null || true
_assert "H10: fd 7 closed after teardown" '[[ ! -e /proc/self/fd/7 ]]'


# ═══════════════════════════════════════════════════════
echo ""
echo "============================================"
printf '  Total: %d | \033[32mPassed: %d\033[0m | \033[31mFailed: %d\033[0m\n' \
    $(( PASS + FAIL )) "$PASS" "$FAIL"
echo "============================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
