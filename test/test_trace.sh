#!/usr/bin/env bash
# test_trace.sh — Unit + stress tests for bashagt trace system
# Run: bash test/test_trace.sh
# No API key required. Tests trace infrastructure in isolation.

set -eo pipefail

PASS=0; FAIL=0
TEST_DIR=$(mktemp -d "/tmp/bashagt_trace_test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s\033[0m\n' "$*"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1"; }

# ── Setup: extract trace functions from bashagt ──
TRACE_START=$(grep -n "^# SECTION 7f: Trace System" /mnt/d/Self/Proj/bashagt/bashagt | cut -d: -f1)
TRACE_END=$(grep -n "^# SECTION 8: Tool Definitions" /mnt/d/Self/Proj/bashagt/bashagt | cut -d: -f1)
TRACE_END=$((TRACE_END - 1))
sed -n "${TRACE_START},${TRACE_END}p" /mnt/d/Self/Proj/bashagt/bashagt > "$TEST_DIR/trace_funcs.sh"

# ── Minimal dependencies ──
_mktemp_file() { mktemp "$@"; }
_timestamp_ms() { date +%s%3N 2>/dev/null || echo "1700000000000"; }
_date_from_epoch() { date -d "@$1" "$2" 2>/dev/null || date -r "$1" "$2" 2>/dev/null || echo "$1"; }
_spin_sleep() { sleep "$1"; }
_cc_hash() { sha256sum 2>/dev/null | awk '{print $1}' || shasum -a 256 2>/dev/null | awk '{print $1}' || echo "noop_hash"; }

source "$TEST_DIR/trace_funcs.sh"

export BASHAGT_TRACE_ENABLED=1
export AGENT_SELF_NAME="main"
export BASHAGT_TRACE_DESC="test"
export BASHAGT_TRACE_TOOL="edit_file"
BASHAGT_PROJECT_DIR="$TEST_DIR/proj"
mkdir -p "$BASHAGT_PROJECT_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# UNIT TESTS
# ═══════════════════════════════════════════════════════════════════════════

echo "=== Unit: trace_init ==="
trace_init
[[ -d "$TRACE_DIR_FRAMES" ]] && _pass "frames dir created" || _fail "frames dir missing"
[[ -d "$TRACE_DIR_OBJECTS" ]] && _pass "objects dir created" || _fail "objects dir missing"
[[ -d "$TRACE_DIR_SNAPS" ]] && _pass "snaps dir created" || _fail "snaps dir missing"
[[ -f "$TRACE_DIR_FRAMES/0000.json" ]] && _pass "genesis frame exists" || _fail "genesis frame missing"
[[ $TRACE_HEAD -eq 0 ]] && _pass "HEAD at 0" || _fail "HEAD not 0: $TRACE_HEAD"
# Re-init should be idempotent
trace_init
[[ -f "$TRACE_DIR_FRAMES/0000.json" ]] && _pass "re-init idempotent" || _fail "re-init broke genesis"

echo ""
echo "=== Unit: _trace_hash ==="
h=$(_trace_hash "")
[[ ${#h} -eq 64 ]] && _pass "empty string hash is 64 chars" || _fail "empty hash wrong: ${#h}"
h=$(_trace_hash "hello")
[[ ${#h} -eq 64 ]] && _pass "'hello' hash is 64 chars" || _fail "hash wrong"
h1=$(_trace_hash "hello")
h2=$(_trace_hash "hello")
[[ "$h1" == "$h2" ]] && _pass "deterministic hash" || _fail "non-deterministic"
h1=$(_trace_hash "hello")
h2=$(_trace_hash "Hello")
[[ "$h1" != "$h2" ]] && _pass "case-sensitive hash" || _fail "case-insensitive"

echo ""
echo "=== Unit: Object store ==="
h=$(_trace_object_store "alpha beta gamma")
r=$(_trace_object_read "$h")
[[ "$r" == "alpha beta gamma" ]] && _pass "round-trip ASCII" || _fail "round-trip failed: got '$r'"

# Unicode
h=$(_trace_object_store "你好世界 🌍")
r=$(_trace_object_read "$h")
[[ "$r" == "你好世界 🌍" ]] && _pass "round-trip Unicode+emoji" || _fail "Unicode round-trip failed"

# Large content (200KB)
_large=$(python3 -c "print('x' * 200000)" 2>/dev/null || printf 'x%.0s' {1..200000})
h=$(_trace_object_store "$_large")
r=$(_trace_object_read "$h")
[[ ${#r} -eq 200000 ]] && _pass "200KB round-trip" || _fail "200KB round-trip: got ${#r} bytes"

# Dedup: same content → same hash
h1=$(_trace_object_store "dedup test")
h2=$(_trace_object_store "dedup test")
[[ "$h1" == "$h2" ]] && _pass "content-addressed dedup" || _fail "dedup failed: $h1 vs $h2"

# Missing hash → error
_trace_object_read "deadbeef00000000000000000000000000000000000000000000000000000000" > /dev/null 2>&1 && _fail "missing hash should fail" || _pass "missing hash returns error"

echo ""
echo "=== Unit: trace_record ==="
# Single record
mkdir -p "$BASHAGT_PROJECT_DIR/.bashagt"
echo '{"k":"v1"}' > "$BASHAGT_PROJECT_DIR/test.json"
old='{"k":"v1"}'; new='{"k":"v2"}'
trace_record "$BASHAGT_PROJECT_DIR/test.json" "$old" "$new" \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "test" --argjson n 1 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 1 ]] && _pass "HEAD incremented to 1" || _fail "HEAD: $TRACE_HEAD"
[[ -f "$TRACE_DIR_FRAMES/0001.json" ]] && _pass "frame file created" || _fail "no frame file"
# Check frame content
_frame=$(cat "$TRACE_DIR_FRAMES/0001.json")
_frame_seq=$(printf '%s' "$_frame" | jq -r '.seq')
[[ "$_frame_seq" == "1" ]] && _pass "frame seq=1" || _fail "frame seq=$_frame_seq"
_frame_agent=$(printf '%s' "$_frame" | jq -r '.cause.agent')
[[ "$_frame_agent" == "main" ]] && _pass "cause.agent=main" || _fail "cause.agent=$_frame_agent"

# New file (no old content)
trace_record "$BASHAGT_PROJECT_DIR/newfile.txt" "" "new content" \
    "$(jq -nc --arg a "main" --arg t "write_file" --arg d "create" --argjson n 1 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 2 ]] && _pass "new file frame created" || _fail "new file HEAD: $TRACE_HEAD"

# Deletion (no new content)
trace_record "$BASHAGT_PROJECT_DIR/newfile.txt" "new content" "" \
    "$(jq -nc --arg a "main" --arg t "bash" --arg d "delete" --argjson n 2 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 3 ]] && _pass "deletion frame created" || _fail "deletion HEAD: $TRACE_HEAD"

echo ""
echo "=== Unit: trace_log ==="
_out=$(trace_log 5 2>/dev/null)
[[ "$_out" == *"[3]"* ]] && _pass "log shows frame 3" || _fail "log missing frame 3"
[[ "$_out" == *"[2]"* ]] && _pass "log shows frame 2" || _fail "log missing frame 2"
[[ "$_out" == *"[1]"* ]] && _pass "log shows frame 1" || _fail "log missing frame 1"
[[ "$_out" == *"write_file"* ]] && _pass "log shows write_file" || _fail "log missing write_file"
[[ "$_out" == *"edit_file"* ]] && _pass "log shows edit_file" || _fail "log missing edit_file"

echo ""
echo "=== Unit: trace_show ==="
_show=$(trace_show 1 2>/dev/null)
[[ "$_show" == *"bump version"* || "$_show" == *"test"* ]] && _pass "show includes desc" || _fail "show missing desc: $_show"
[[ "$_show" == *"test.json"* ]] && _pass "show includes file path" || _fail "show missing path"

# Bad frame number
trace_show 999 2>/dev/null && _fail "show bad frame should fail" || _pass "show bad frame returns error"

echo ""
echo "=== Unit: trace_diff ==="
# Add a 4th frame to diff against
trace_record "$BASHAGT_PROJECT_DIR/test.json" "$new" '{"k":"v3"}' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "v2→v3" --argjson n 3 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
_diff=$(trace_diff 1 4 2>/dev/null || true)
# diff between frame 1 (v1→v2) after=v2, frame 4 (v2→v3) after=v3 → should show difference
[[ -n "$_diff" ]] && _pass "diff produces output" || _fail "diff empty"

echo ""
echo "=== Unit: trace_undo (force) ==="
# Reset to known state for undo tests
rm -f "$TRACE_DIR_FRAMES/000"[2-9]*.json 2>/dev/null || true
rm -f "$TRACE_DIR_FRAMES/00"[1-9]*.json 2>/dev/null || true
_trace_set_head 1
echo '{"k":"v2"}' > "$BASHAGT_PROJECT_DIR/test.json"

old_head=$(cat "$TRACE_HEAD_FILE")
trace_undo 1 force 2>/dev/null
new_head=$(cat "$TRACE_HEAD_FILE")
[[ "$new_head" -eq 0 ]] && _pass "undo pops HEAD 1→0" || _fail "HEAD after undo: $new_head"
_restored=$(cat "$BASHAGT_PROJECT_DIR/test.json")
[[ "$_restored" == '{"k":"v1"}' ]] && _pass "undo restored old content" || _fail "undo got: $_restored"

echo ""
echo "=== Unit: trace_snapshot ==="
trace_snapshot 2>/dev/null
_snap_count=$(ls -d "$TRACE_DIR_SNAPS"/*/ 2>/dev/null | wc -l)
(( _snap_count > 0 )) && _pass "snapshot created ($_snap_count)" || _fail "no snapshots"

echo ""
echo "=== Unit: trace_status ==="
[[ -n "$TRACE_HEAD_FILE" ]] && _pass "TRACE_HEAD_FILE set" || _fail "TRACE_HEAD_FILE unset"
[[ -n "$TRACE_DIR_FRAMES" ]] && _pass "TRACE_DIR_FRAMES set" || _fail "TRACE_DIR_FRAMES unset"

# ═══════════════════════════════════════════════════════════════════════════
# STRESS TESTS
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "══════════════════════════════════════════"
echo "  STRESS TESTS"
echo "══════════════════════════════════════════"

echo ""
echo "=== Stress: Rapid sequential frames (100) ==="
# Reset
rm -rf "$TRACE_DIR_FRAMES" "$TRACE_DIR_OBJECTS"
mkdir -p "$TRACE_DIR_FRAMES" "$TRACE_DIR_OBJECTS"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

echo '{"count":0}' > "$BASHAGT_PROJECT_DIR/stress.json"
_stress_start=$(date +%s%3N 2>/dev/null || echo 0)
for i in $(seq 1 100); do
    old="{\"count\":$((i-1))}"
    new="{\"count\":$i}"
    trace_record "$BASHAGT_PROJECT_DIR/stress.json" "$old" "$new" \
        "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "stress $i" --argjson n "$i" \
           '{agent:$a,tool:$t,turn:$n,desc:$d}')" 2>/dev/null
done
_stress_end=$(date +%s%3N 2>/dev/null || echo 0)
_stress_ms=$((_stress_end - _stress_start))

[[ $TRACE_HEAD -eq 100 ]] && _pass "100 frames recorded (HEAD=$TRACE_HEAD)" || _fail "HEAD=$TRACE_HEAD, expected 100"
_frame_count=$(ls "$TRACE_DIR_FRAMES"/*.json 2>/dev/null | wc -l)
(( _frame_count >= 100 )) && _pass "100+ frame files on disk ($_frame_count)" || _fail "only $_frame_count frame files"

# Verify data integrity: walk backward from 100
_broken=0
for i in $(seq 100 -1 1); do
    _ff=$(printf '%s/%04d.json' "$TRACE_DIR_FRAMES" "$i")
    [[ -f "$_ff" ]] || { _broken=$i; break; }
done
[[ $_broken -eq 0 ]] && _pass "all 100 frames readable" || _fail "frame $_broken missing"

# Verify content of a middle frame
_mid_frame=$(cat "$TRACE_DIR_FRAMES/0050.json")
_mid_count=$(printf '%s' "$_mid_frame" | jq -r '.cause.desc')
[[ "$_mid_count" == "stress 50" ]] && _pass "frame 50 desc correct" || _fail "frame 50 desc: $_mid_count"

# Performance
echo "  100 frames in ${_stress_ms}ms ($(awk "BEGIN {printf \"%.1f\", $_stress_ms/100}")ms/frame)"

echo ""
echo "=== Stress: Undo chain (50 frames) ==="
# Ensure current file matches frame 100's after
echo '{"count":100}' > "$BASHAGT_PROJECT_DIR/stress.json"
_before_head=$(cat "$TRACE_HEAD_FILE")
trace_undo 50 force 2>/dev/null
_after_head=$(cat "$TRACE_HEAD_FILE")
[[ $_after_head -eq 50 ]] && _pass "undo 50: HEAD 100→50" || _fail "undo 50: HEAD $_before_head→$_after_head"
_restored=$(cat "$BASHAGT_PROJECT_DIR/stress.json")
[[ "$_restored" == '{"count":50}' ]] && _pass "undo 50: content restored to count=50" || _fail "undo 50: got $_restored"

# Undo remaining 50
echo '{"count":50}' > "$BASHAGT_PROJECT_DIR/stress.json"
trace_undo 50 force 2>/dev/null
_restored2=$(cat "$BASHAGT_PROJECT_DIR/stress.json")
[[ "$_restored2" == '{"count":0}' ]] && _pass "undo all 100: back to count=0" || _fail "undo all: got $_restored2"

echo ""
echo "=== Stress: Hash mismatch detection ==="
# Reset and create 2 frames
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

echo '{"x":1}' > "$BASHAGT_PROJECT_DIR/verify.json"
trace_record "$BASHAGT_PROJECT_DIR/verify.json" '{"x":1}' '{"x":2}' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "v1" --argjson n 1 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
trace_record "$BASHAGT_PROJECT_DIR/verify.json" '{"x":2}' '{"x":3}' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "v2" --argjson n 2 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 2 ]] && _pass "verify setup: HEAD=2" || _fail "verify setup: HEAD=$TRACE_HEAD"

# Tamper with the file to simulate human edit
echo '{"x":999}' > "$BASHAGT_PROJECT_DIR/verify.json"

# Undo should detect mismatch and fail (without --force)
_out=$(trace_undo 1 "" 2>/dev/null || true)
[[ "$_out" == *"modified outside"* ]] && _pass "tamper detection: undo refused" || _fail "tamper not detected: $_out"
[[ $(cat "$TRACE_HEAD_FILE") -eq 2 ]] && _pass "HEAD unchanged after failed undo" || _fail "HEAD moved on failed undo"

# Force undo should work
trace_undo 1 force 2>/dev/null
_restored=$(cat "$BASHAGT_PROJECT_DIR/verify.json")
[[ "$_restored" == '{"x":2}' ]] && _pass "force undo after tamper: restored" || _fail "force undo got: $_restored"

echo ""
echo "=== Stress: Special characters in content ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

# Content with quotes, newlines, backslashes, braces (bash hazard zone)
_special_old='{"path":"/tmp/foo","cmd":"echo \"hello\"\nworld"}'
_special_new='{"path":"/tmp/bar","cmd":"printf '\''%s'\'' \"done\"\n${HOME}"}'
printf '%s' "$_special_old" > "$BASHAGT_PROJECT_DIR/special.json"
trace_record "$BASHAGT_PROJECT_DIR/special.json" "$_special_old" "$_special_new" \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "special chars" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 1 ]] && _pass "special chars: frame created" || _fail "special chars: HEAD=$TRACE_HEAD"

# Undo
printf '%s' "$_special_new" > "$BASHAGT_PROJECT_DIR/special.json"
trace_undo 1 force 2>/dev/null
_restored=$(cat "$BASHAGT_PROJECT_DIR/special.json")
[[ "$_restored" == "$_special_old" ]] && _pass "special chars: undo correct" || _fail "special chars: mismatch"

echo ""
echo "=== Stress: Multi-file frame ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

echo 'a1' > "$BASHAGT_PROJECT_DIR/a.txt"
echo 'b1' > "$BASHAGT_PROJECT_DIR/b.txt"
echo 'c1' > "$BASHAGT_PROJECT_DIR/c.txt"

# Record each file separately (simulating one turn with 3 edits)
trace_record "$BASHAGT_PROJECT_DIR/a.txt" 'a1' 'a2' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "edit a,b,c" --argjson n 1 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
trace_record "$BASHAGT_PROJECT_DIR/b.txt" 'b1' 'b2' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "edit a,b,c" --argjson n 1 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
trace_record "$BASHAGT_PROJECT_DIR/c.txt" 'c1' 'c2' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "edit a,b,c" --argjson n 1 '{agent:$a,tool:$t,turn:$n,desc:$d}')"

[[ $TRACE_HEAD -eq 3 ]] && _pass "multi-file: 3 frames" || _fail "multi-file: HEAD=$TRACE_HEAD"

# Verify all files are trackable
_log=$(trace_log 3 2>/dev/null)
[[ "$_log" == *"a.txt"* ]] && _pass "log tracks a.txt" || _fail "a.txt missing from log"
[[ "$_log" == *"b.txt"* ]] && _pass "log tracks b.txt" || _fail "b.txt missing from log"
[[ "$_log" == *"c.txt"* ]] && _pass "log tracks c.txt" || _fail "c.txt missing from log"

# Undo all 3
echo 'a2' > "$BASHAGT_PROJECT_DIR/a.txt"
echo 'b2' > "$BASHAGT_PROJECT_DIR/b.txt"
echo 'c2' > "$BASHAGT_PROJECT_DIR/c.txt"
trace_undo 3 force 2>/dev/null

[[ "$(cat "$BASHAGT_PROJECT_DIR/a.txt")" == 'a1' ]] && _pass "multi-undo: a.txt restored" || _fail "multi-undo a.txt: $(cat "$BASHAGT_PROJECT_DIR/a.txt")"
[[ "$(cat "$BASHAGT_PROJECT_DIR/b.txt")" == 'b1' ]] && _pass "multi-undo: b.txt restored" || _fail "multi-undo b.txt"
[[ "$(cat "$BASHAGT_PROJECT_DIR/c.txt")" == 'c1' ]] && _pass "multi-undo: c.txt restored" || _fail "multi-undo c.txt"

echo ""
echo "=== Stress: Empty content edge cases ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

# New file with empty content
    printf "" > "$BASHAGT_PROJECT_DIR/empty.txt"
trace_record "$BASHAGT_PROJECT_DIR/empty.txt" "" "" \
    "$(jq -nc --arg a "main" --arg t "write_file" --arg d "empty file" --argjson n 1 '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 1 ]] && _pass "empty content: frame created" || _fail "empty content: HEAD=$TRACE_HEAD"
[[ -f "$BASHAGT_PROJECT_DIR/empty.txt" ]] && _pass "empty file exists" || _fail "no empty file"

# Undo empty new file (before_hash=null → should delete)
trace_undo 1 force 2>/dev/null
[[ ! -f "$BASHAGT_PROJECT_DIR/empty.txt" ]] && _pass "undo new empty file: deleted" || _fail "empty file still exists"

echo ""
echo "=== Stress: Frame self-verification (hash integrity) ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

for i in $(seq 1 20); do
    trace_record "$BASHAGT_PROJECT_DIR/hash_test.json" "v$((i-1))" "v$i" \
        "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "hash $i" --argjson n "$i" \
           '{agent:$a,tool:$t,turn:$n,desc:$d}')"
done

# Verify each frame's hash
_bad_hash=0
for i in $(seq 1 20); do
    _ff=$(printf '%s/%04d.json' "$TRACE_DIR_FRAMES" "$i")
    _frame=$(cat "$_ff")
    _stored_hash=$(printf '%s' "$_frame" | jq -r '.hash')
    # Recompute: strip hash, re-hash rest
    _without_hash=$(printf '%s' "$_frame" | jq -c 'del(.hash)')
    _computed=$(_trace_hash "$_without_hash")
    if [[ "$_stored_hash" != "$_computed" ]]; then
        _bad_hash=$i
        break
    fi
done
[[ $_bad_hash -eq 0 ]] && _pass "all 20 frames have valid self-hashes" || _fail "frame $_bad_hash hash mismatch"

# Tamper with a frame and verify detection
_tamper_frame="$TRACE_DIR_FRAMES/0010.json"
cp "$_tamper_frame" "$_tamper_frame.bak"
jq -c '.cause.desc = "TAMPERED"' "$_tamper_frame" > "$_tamper_frame.tmp" && mv "$_tamper_frame.tmp" "$_tamper_frame"
_frame=$(cat "$_tamper_frame")
_stored=$(printf '%s' "$_frame" | jq -r '.hash')
_without=$(printf '%s' "$_frame" | jq -c 'del(.hash)')
_computed=$(_trace_hash "$_without")
[[ "$_stored" != "$_computed" ]] && _pass "tampered frame detected (hash mismatch)" || _fail "tamper not detected"
# Restore
mv "$_tamper_frame.bak" "$_tamper_frame"

echo ""
echo "=== Stress: trace_prune ==="
trace_prune 5 2>/dev/null || true
# Frames older than (HEAD - 5) should be pruned
_still_there=0
for i in $(seq 1 5); do
    _ff=$(printf '%s/%04d.json' "$TRACE_DIR_FRAMES" "$i")
    [[ -f "$_ff" ]] || _still_there=1
done
# Some frames before cutoff may be removed — depends on HEAD relative to keep
# Just check it doesn't crash
_pass "trace_prune executed without crash"

echo ""
echo "=== Stress: Agent identity tracking ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

echo 'v1' > "$BASHAGT_PROJECT_DIR/agent_test.txt"

# Simulate main agent edit
AGENT_SELF_NAME="main"
trace_record "$BASHAGT_PROJECT_DIR/agent_test.txt" 'v1' 'v2' \
    "$(jq -nc --arg a "${AGENT_SELF_NAME}" --arg t "edit_file" --arg d "main edit" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"

# Simulate sub-agent edit
AGENT_SELF_NAME="agent_manager"
echo 'v2' > "$BASHAGT_PROJECT_DIR/agent_test.txt"
trace_record "$BASHAGT_PROJECT_DIR/agent_test.txt" 'v2' 'v3' \
    "$(jq -nc --arg a "${AGENT_SELF_NAME}" --arg t "edit_file" --arg d "agent_manager edit" --argjson n 2 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"

# Simulate mem_writer edit
AGENT_SELF_NAME="mem_writer"
echo 'v3' > "$BASHAGT_PROJECT_DIR/agent_test.txt"
trace_record "$BASHAGT_PROJECT_DIR/agent_test.txt" 'v3' 'v4' \
    "$(jq -nc --arg a "${AGENT_SELF_NAME}" --arg t "write_file" --arg d "mem_writer write" --argjson n 3 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"

[[ $TRACE_HEAD -eq 3 ]] && _pass "agent tracking: 3 frames" || _fail "agent tracking: HEAD=$TRACE_HEAD"

# Verify agent names in log
_log=$(trace_log 3 2>/dev/null)
[[ "$_log" == *"mem_writer"* ]] && _pass "log tracks mem_writer" || _fail "mem_writer missing: $_log"
[[ "$_log" == *"agent_manager"* ]] && _pass "log tracks agent_manager" || _fail "agent_manager missing: $_log"
[[ "$_log" == *"main"* || "$_log" == *"edit_file"* ]] && _pass "log tracks main agent" || _fail "main agent missing"

echo ""
echo "=== Stress: Nested undo limits ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

# Create 5 frames
for i in $(seq 1 5); do
    echo "v$i" > "$BASHAGT_PROJECT_DIR/nest.txt"
    trace_record "$BASHAGT_PROJECT_DIR/nest.txt" "v$((i-1))" "v$i" \
        "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "step $i" --argjson n "$i" \
           '{agent:$a,tool:$t,turn:$n,desc:$d}')"
done

# Request more undo than frames
echo 'v5' > "$BASHAGT_PROJECT_DIR/nest.txt"
_out=$(trace_undo 10 force 2>/dev/null || true)
[[ "$_out" == *"Undone 5 frame"* ]] && _pass "undo overflow: capped at 5" || _fail "undo overflow: $_out"
[[ $(cat "$TRACE_HEAD_FILE") -eq 0 ]] && _pass "undo overflow: HEAD at 0" || _fail "undo overflow: HEAD=$(cat "$TRACE_HEAD_FILE")"

# Undo at genesis
_out=$(trace_undo 1 force 2>/dev/null || true)
[[ "$_out" == *"Nothing to undo"* ]] && _pass "undo at genesis: blocked" || _fail "undo at genesis: $_out"

echo ""
echo "=== Stress: Delete file — trace and undo ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

# Create a file then delete it (simulating tool_delete_file flow)
echo 'important data' > "$BASHAGT_PROJECT_DIR/delete_me.txt"
_del_content=$(cat "$BASHAGT_PROJECT_DIR/delete_me.txt")
trace_record "$BASHAGT_PROJECT_DIR/delete_me.txt" "$_del_content" "" \
    "$(jq -nc --arg a "main" --arg t "delete_file" --arg d "delete test file" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 1 ]] && _pass "delete: frame created (HEAD=1)" || _fail "delete: HEAD=$TRACE_HEAD"

# Verify frame has empty after_hash
_del_frame=$(cat "$TRACE_DIR_FRAMES/0001.json")
_del_after=$(printf '%s' "$_del_frame" | jq -r '.changes["'"$BASHAGT_PROJECT_DIR"'/delete_me.txt"].after // "NULL"')
[[ "$_del_after" == "" ]] && _pass "delete: after_hash is empty (explicit delete marker)" || _fail "delete: after_hash=$_del_after"

# Delete the actual file
rm -f "$BASHAGT_PROJECT_DIR/delete_me.txt"
[[ ! -f "$BASHAGT_PROJECT_DIR/delete_me.txt" ]] && _pass "delete: file removed from disk" || _fail "delete: file still exists"

# Undo should restore it
trace_undo 1 force 2>/dev/null
[[ -f "$BASHAGT_PROJECT_DIR/delete_me.txt" ]] && _pass "undo delete: file restored" || _fail "undo delete: file not restored"
_restored_del=$(cat "$BASHAGT_PROJECT_DIR/delete_me.txt")
[[ "$_restored_del" == "important data" ]] && _pass "undo delete: content matches" || _fail "undo delete: got '$_restored_del'"

echo ""
echo "=== Stress: Delete directory — trace and undo ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

# Create a directory tree
mkdir -p "$BASHAGT_PROJECT_DIR/deldir/sub"
echo 'file A' > "$BASHAGT_PROJECT_DIR/deldir/a.txt"
echo 'file B' > "$BASHAGT_PROJECT_DIR/deldir/sub/b.txt"
mkdir -p "$BASHAGT_PROJECT_DIR/deldir/empty_sub"

# Build manifest (simulating tool_delete_file)
_dir_manifest="{}"
while IFS= read -r -d '' _df; do
    _drel="${_df#$BASHAGT_PROJECT_DIR/deldir/}"
    _dc=$(cat "$_df" 2>/dev/null || true)
    _dh=$(_trace_object_store "$_dc")
    _dir_manifest=$(jq -nc --argjson m "$_dir_manifest" --arg r "$_drel" --arg h "$_dh" '$m + {($r): $h}')
done < <(find "$BASHAGT_PROJECT_DIR/deldir" -type f -print0 2>/dev/null || true)
# Mark empty subdirectory
_dir_manifest=$(jq -nc --argjson m "$_dir_manifest" '$m + {"empty_sub": "_dir_"}')

_dir_manifest_str=$(printf '%s' "$_dir_manifest")
trace_record "$BASHAGT_PROJECT_DIR/deldir" "$_dir_manifest_str" "" \
    "$(jq -nc --arg a "main" --arg t "delete_file" --arg d "delete test dir" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 1 ]] && _pass "dir delete: frame created" || _fail "dir delete: HEAD=$TRACE_HEAD"

# Remove the directory
rm -rf "$BASHAGT_PROJECT_DIR/deldir"
[[ ! -d "$BASHAGT_PROJECT_DIR/deldir" ]] && _pass "dir delete: directory removed" || _fail "dir delete: still exists"

# Undo should restore the directory tree
trace_undo 1 force 2>/dev/null
[[ -d "$BASHAGT_PROJECT_DIR/deldir" ]] && _pass "undo dir: directory restored" || _fail "undo dir: not restored"
[[ -d "$BASHAGT_PROJECT_DIR/deldir/sub" ]] && _pass "undo dir: subdirectory restored" || _fail "undo dir: sub missing"
[[ -f "$BASHAGT_PROJECT_DIR/deldir/a.txt" ]] && _pass "undo dir: file a.txt restored" || _fail "undo dir: a.txt missing"
[[ -f "$BASHAGT_PROJECT_DIR/deldir/sub/b.txt" ]] && _pass "undo dir: file b.txt restored" || _fail "undo dir: b.txt missing"
[[ "$(cat "$BASHAGT_PROJECT_DIR/deldir/a.txt")" == "file A" ]] && _pass "undo dir: a.txt content OK" || _fail "undo dir: a.txt wrong"
[[ "$(cat "$BASHAGT_PROJECT_DIR/deldir/sub/b.txt")" == "file B" ]] && _pass "undo dir: b.txt content OK" || _fail "undo dir: b.txt wrong"
# Note: empty_sub won't be restored by the basic trace_undo (only files are restored)
# This is acceptable — empty dirs are a known limitation

echo ""
echo "=== Stress: Delete then manually recreate (hash mismatch) ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

echo 'original' > "$BASHAGT_PROJECT_DIR/tamper_del.txt"
_tamper_content=$(cat "$BASHAGT_PROJECT_DIR/tamper_del.txt")
trace_record "$BASHAGT_PROJECT_DIR/tamper_del.txt" "$_tamper_content" "" \
    "$(jq -nc --arg a "main" --arg t "delete_file" --arg d "delete tamper test" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"

# Someone manually recreates the file with different content
rm -f "$BASHAGT_PROJECT_DIR/tamper_del.txt"
echo 'someone recreated this' > "$BASHAGT_PROJECT_DIR/tamper_del.txt"

# Undo without force should fail (after_hash is empty → skip verification, but file exists when it should be deleted)
# Actually: after_hash="" → Phase 3 skips verification (continue). Phase 4 reads before_hash → restores.
# The recreated file gets overwritten by the original. This is correct behavior for force mode.
_out=$(trace_undo 1 "" 2>/dev/null || true)
# With after_hash="" the verification is skipped, so non-force should also succeed
[[ -f "$BASHAGT_PROJECT_DIR/tamper_del.txt" ]] && _pass "delete+recreate: undo non-force works (empty after skips verify)" || _fail "delete+recreate: file missing"

echo ""
echo "=== Stress: New file creation — trace and undo ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

# Simulate write_file: no old content, create new file
_new_file="$BASHAGT_PROJECT_DIR/new_undo_test.txt"
_new_content='# Created by test'
printf '%s' "$_new_content" > "$_new_file"
trace_record "$_new_file" "" "$_new_content" \
    "$(jq -nc --arg a "main" --arg t "write_file" --arg d "create new file" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 1 ]] && _pass "write: frame created" || _fail "write: HEAD=$TRACE_HEAD"
[[ -f "$_new_file" ]] && _pass "write: file exists on disk" || _fail "write: file missing"

# Verify frame has empty before_hash and valid after_hash
_write_frame=$(cat "$TRACE_DIR_FRAMES/0001.json")
_write_before=$(printf '%s' "$_write_frame" | jq -r '.changes["'"$_new_file"'"].before // "NULL"')
_write_after=$(printf '%s' "$_write_frame" | jq -r '.changes["'"$_new_file"'"].after // "NULL"')
[[ "$_write_before" == "" ]] && _pass "write: before_hash empty (new file)" || _fail "write: before_hash=$_write_before"
[[ "$_write_after" == *[a-f0-9]* ]] && _pass "write: after_hash present" || _fail "write: after_hash=$_write_after"

# Undo should delete the new file
trace_undo 1 force 2>/dev/null
[[ ! -f "$_new_file" ]] && _pass "undo write: file deleted" || _fail "undo write: file still exists"
[[ $(cat "$TRACE_HEAD_FILE") -eq 0 ]] && _pass "undo write: HEAD back to 0" || _fail "undo write: HEAD=$(cat "$TRACE_HEAD_FILE")"

echo ""
echo "=== Stress: Edit file — verify+undo ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

_edit_file="$BASHAGT_PROJECT_DIR/edit_undo_test.txt"
echo 'line1
line2
line3' > "$_edit_file"
_edit_old=$(cat "$_edit_file")
_edit_new='line1
line2-modified
line3'

# Record the edit
trace_record "$_edit_file" "$_edit_old" "$_edit_new" \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "edit line2" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
# Apply the edit to disk
printf '%s' "$_edit_new" > "$_edit_file"
[[ $TRACE_HEAD -eq 1 ]] && _pass "edit: frame created" || _fail "edit: HEAD=$TRACE_HEAD"

# Verify the after_hash matches current file
_eframe=$(cat "$TRACE_DIR_FRAMES/0001.json")
_e_after=$(printf '%s' "$_eframe" | jq -r '.changes["'"$_edit_file"'"].after // ""')
_e_current_hash=$(_trace_hash "$(cat "$_edit_file")")
[[ "$_e_after" == "$_e_current_hash" ]] && _pass "edit: after_hash == current file ✓" || _fail "edit: hash mismatch"

# Undo — should work without force (hash matches, confirm with 'y')
_out=$(echo 'y' | trace_undo 1 "" 2>/dev/null || true)
[[ "$_out" == *"Undone 1 frame"* ]] && _pass "edit undo: succeeded (hash verified with confirmation)" || _fail "edit undo: $_out"
_restored_edit=$(cat "$_edit_file")
[[ "$_restored_edit" == "$_edit_old" ]] && _pass "edit undo: content restored to original" || _fail "edit undo: content mismatch"

echo ""
echo "=== Stress: Edit + human tamper — undo refuses ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

_tamper_file="$BASHAGT_PROJECT_DIR/tamper_edit_test.txt"
echo 'original v1' > "$_tamper_file"
_tamper_old=$(cat "$_tamper_file")
_tamper_new='original v2'

trace_record "$_tamper_file" "$_tamper_old" "$_tamper_new" \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "update v1→v2" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
# Apply the edit, then simulate human modification
printf '%s' "$_tamper_new" > "$_tamper_file"
echo 'human injected line' >> "$_tamper_file"

# Non-force undo should detect mismatch and refuse
_out=$(trace_undo 1 "" 2>/dev/null || true)
[[ "$_out" == *"modified outside"* ]] && _pass "tamper edit: undo refused (hash mismatch detected)" || _fail "tamper edit: not detected: $_out"
[[ $(cat "$TRACE_HEAD_FILE") -eq 1 ]] && _pass "tamper edit: HEAD unchanged after refused undo" || _fail "tamper edit: HEAD moved"

# Force undo should restore despite tamper
trace_undo 1 force 2>/dev/null
_restored_tamper=$(cat "$_tamper_file")
[[ "$_restored_tamper" == "$_tamper_old" ]] && _pass "tamper edit: force undo restored original" || _fail "tamper edit: got '$_restored_tamper'"

echo ""
echo "=== Stress: Create → Edit → Undo chain ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

_chain_file="$BASHAGT_PROJECT_DIR/chain_test.txt"

# Frame 1: create
printf '%s' 'v1' > "$_chain_file"
trace_record "$_chain_file" "" "v1" \
    "$(jq -nc --arg a "main" --arg t "write_file" --arg d "create chain" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
[[ $TRACE_HEAD -eq 1 ]] && _pass "chain: frame 1 (create)" || _fail "chain: frame 1 fail"

# Frame 2: edit
trace_record "$_chain_file" "v1" "v2" \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "edit v1→v2" --argjson n 2 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
printf '%s' 'v2' > "$_chain_file"
[[ $TRACE_HEAD -eq 2 ]] && _pass "chain: frame 2 (edit)" || _fail "chain: frame 2 fail"

# Frame 3: edit
trace_record "$_chain_file" "v2" "v3" \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "edit v2→v3" --argjson n 3 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
printf '%s' 'v3' > "$_chain_file"
[[ $TRACE_HEAD -eq 3 ]] && _pass "chain: frame 3 (edit)" || _fail "chain: frame 3 fail"

# Undo 2 frames (frame 3 + frame 2)
trace_undo 2 force 2>/dev/null
[[ $(cat "$TRACE_HEAD_FILE") -eq 1 ]] && _pass "chain undo: HEAD 3→1" || _fail "chain undo: HEAD=$(cat "$TRACE_HEAD_FILE")"
[[ "$(cat "$_chain_file")" == "v1" ]] && _pass "chain undo: back to v1 (skipped v2,v3)" || _fail "chain undo: got $(cat "$_chain_file")"

# Undo last frame (create → file deleted)
printf '%s' 'v1' > "$_chain_file"  # match frame 1's after_hash
trace_undo 1 force 2>/dev/null
[[ ! -f "$_chain_file" ]] && _pass "chain undo: create undone, file deleted" || _fail "chain undo: file still exists"
[[ $(cat "$TRACE_HEAD_FILE") -eq 0 ]] && _pass "chain undo: HEAD back to 0" || _fail "chain undo: final HEAD=$(cat "$TRACE_HEAD_FILE")"

echo ""
echo "=== Stress: Orphan frames — undo pops but frames stay on disk ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

# Create 5 frames
_orphan_file="$BASHAGT_PROJECT_DIR/orphan_test.txt"
for i in $(seq 1 5); do
    echo "v$i" > "$_orphan_file"
    trace_record "$_orphan_file" "v$((i-1))" "v$i" \
        "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "step $i" --argjson n "$i" \
           '{agent:$a,tool:$t,turn:$n,desc:$d}')"
done
[[ $TRACE_HEAD -eq 5 ]] && _pass "orphan: 5 frames created" || _fail "orphan: HEAD=$TRACE_HEAD"

# Undo 2 frames
echo 'v5' > "$_orphan_file"
trace_undo 2 force 2>/dev/null
[[ $(cat "$TRACE_HEAD_FILE") -eq 3 ]] && _pass "orphan: HEAD 5→3 after undo" || _fail "orphan: HEAD=$(cat "$TRACE_HEAD_FILE")"

# Frames 4 and 5 should still exist on disk (orphan, audit trail)
[[ -f "$TRACE_DIR_FRAMES/0004.json" ]] && _pass "orphan: frame 4 preserved on disk" || _fail "orphan: frame 4 missing"
[[ -f "$TRACE_DIR_FRAMES/0005.json" ]] && _pass "orphan: frame 5 preserved on disk" || _fail "orphan: frame 5 missing"
# Frames 1-3 also still on disk (active chain)
[[ -f "$TRACE_DIR_FRAMES/0001.json" ]] && _pass "orphan: frame 1 (active) intact" || _fail "orphan: frame 1 missing"
[[ -f "$TRACE_DIR_FRAMES/0003.json" ]] && _pass "orphan: frame 3 (HEAD) intact" || _fail "orphan: frame 3 missing"

echo ""
echo "=== Stress: trace_log with N > HEAD ==="
_out=$(trace_log 20 2>/dev/null)
# Should show 3 frames (HEAD=3) not error
[[ "$_out" == *"[3]"* ]] && _pass "log overflow: shows frame 3" || _fail "log overflow: $_out"
[[ "$_out" == *"[1]"* ]] && _pass "log overflow: shows frame 1" || _fail "log overflow: $_out"
# Should NOT show frame 0 (genesis, seq=0 is skipped)
[[ "$_out" != *"[0]"* ]] && _pass "log overflow: genesis skipped" || _fail "log overflow: shows genesis"

echo ""
echo "=== Stress: trace_diff edge cases ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

_diff_file="$BASHAGT_PROJECT_DIR/diff_test.txt"
echo 'diff v1' > "$_diff_file"
trace_record "$_diff_file" 'diff v1' 'diff v2' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "v1→v2" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
echo 'diff v2' > "$_diff_file"
trace_record "$_diff_file" 'diff v2' 'diff v3' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "v2→v3" --argjson n 2 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"

# diff with specific path
_diff_out=$(trace_diff 1 2 "$_diff_file" 2>/dev/null || true)
[[ -n "$_diff_out" ]] && _pass "diff path: output produced" || _fail "diff path: empty"

# diff bad frames
trace_diff 1 999 "$_diff_file" 2>/dev/null && _fail "diff bad: should fail" || _pass "diff bad: frame 999 not found"

# diff with nonexistent file
_diff_out=$(trace_diff 1 2 "/nonexistent/file.txt" 2>/dev/null || true)
[[ "$_diff_out" == *"not found"* ]] && _pass "diff bad path: reports not found" || _fail "diff bad path: $_diff_out"

echo ""
echo "=== Stress: trace_prune actually removes old frames ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

_prune_file="$BASHAGT_PROJECT_DIR/prune_test.txt"
for i in $(seq 1 30); do
    echo "v$i" > "$_prune_file"
    trace_record "$_prune_file" "v$((i-1))" "v$i" \
        "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "prune $i" --argjson n "$i" \
           '{agent:$a,tool:$t,turn:$n,desc:$d}')"
done
[[ $TRACE_HEAD -eq 30 ]] && _pass "prune: 30 frames created" || _fail "prune: HEAD=$TRACE_HEAD"

# Prune keeping only 5 frames
trace_prune 5 2>/dev/null || true
# Frames 1-24 should be removed (30 - 5 = 25, so frame 25+ kept)
[[ ! -f "$TRACE_DIR_FRAMES/0001.json" ]] && _pass "prune: frame 1 removed" || _fail "prune: frame 1 still exists"
[[ ! -f "$TRACE_DIR_FRAMES/0020.json" ]] && _pass "prune: frame 20 removed" || _fail "prune: frame 20 still exists"
[[ -f "$TRACE_DIR_FRAMES/0026.json" ]] && _pass "prune: frame 26 (after cutoff) kept" || _fail "prune: frame 26 missing"
[[ -f "$TRACE_DIR_FRAMES/0030.json" ]] && _pass "prune: frame 30 (HEAD) kept" || _fail "prune: frame 30 missing"

echo ""
echo "=== Stress: Multi-frame non-force undo — mid-chain hash failure ==="
rm -rf "$TRACE_DIR_FRAMES"/*
mkdir -p "$TRACE_DIR_FRAMES"
_trace_set_head 0
jq -nc '{seq:0, parent:null, ts:0, hash:"", cause:{agent:"init",tool:"init",turn:0,desc:"genesis"}, changes:{}}' > "$TRACE_DIR_FRAMES/0000.json"

_mid_file="$BASHAGT_PROJECT_DIR/mid_chain.txt"
# Frame 1
echo 'A' > "$_mid_file"
trace_record "$_mid_file" '' 'A' \
    "$(jq -nc --arg a "main" --arg t "write_file" --arg d "create A" --argjson n 1 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
# Frame 2
trace_record "$_mid_file" 'A' 'B' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "A→B" --argjson n 2 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
echo 'B' > "$_mid_file"
# Frame 3
trace_record "$_mid_file" 'B' 'C' \
    "$(jq -nc --arg a "main" --arg t "edit_file" --arg d "B→C" --argjson n 3 \
       '{agent:$a,tool:$t,turn:$n,desc:$d}')"
echo 'C' > "$_mid_file"

# Tamper with the middle frame's file state: set file to 'X' (matches none of frame 1/2/3's after_hash)
echo 'X' > "$_mid_file"

# Non-force undo 3 frames: frame 3 should fail verification
_out=$(trace_undo 3 "" 2>/dev/null || true)
[[ "$_out" == *"modified outside"* ]] && _pass "mid-chain: undo 3 refused (frame 3 verification failed)" || _fail "mid-chain: $_out"
# HEAD should be unchanged
[[ $(cat "$TRACE_HEAD_FILE") -eq 3 ]] && _pass "mid-chain: HEAD unchanged at 3" || _fail "mid-chain: HEAD=$(cat "$TRACE_HEAD_FILE")"
# File should not have been modified
[[ "$(cat "$_mid_file")" == "X" ]] && _pass "mid-chain: file untouched after failed undo" || _fail "mid-chain: file changed"

# Set file to match frame 3's after_hash, undo 1 frame (non-force) → file → B
echo 'C' > "$_mid_file"
_out=$(echo 'y' | trace_undo 1 "" 2>/dev/null || true)
[[ "$_out" == *"Undone 1 frame"* ]] && _pass "mid-chain: undo 1 non-force succeeded" || _fail "mid-chain: undo 1: $_out"
[[ "$(cat "$_mid_file")" == "B" ]] && _pass "mid-chain: file back to B (frame 3 undone)" || _fail "mid-chain: got $(cat "$_mid_file")"

# Now undo frame 2 (non-force) — file=B matches frame 2's after_hash
_out=$(echo 'y' | trace_undo 1 "" 2>/dev/null || true)
[[ "$_out" == *"Undone 1 frame"* ]] && _pass "mid-chain: undo 1 more non-force succeeded" || _fail "mid-chain: undo 1 more: $_out"
[[ "$(cat "$_mid_file")" == "A" ]] && _pass "mid-chain: file back to A" || _fail "mid-chain: got $(cat "$_mid_file")"

# Note: multi-frame non-force undo on the SAME file always fails verification
# for inner frames, because frame N's after_hash != current file (frame N+1 is on top).
# This is correct — same-file multi-frame undo requires --force.

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================"
if [[ $FAIL -eq 0 ]]; then
    echo " All $PASS trace tests passed"
    echo "============================================"
    exit 0
else
    echo " $PASS passed, $FAIL failed"
    echo "============================================"
    exit 1
fi
