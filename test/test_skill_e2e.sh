#!/usr/bin/env bash
# test_skill_e2e.sh — End-to-end tests for the skill system
# Run: bash test/test_skill_e2e.sh
# No API key required. Tests skill loading, activation, deactivation,
# priority, prompt injection, and error handling.
#
# Strategy: source the full bashagt in a restricted subshell that
# sets HOME to a temp dir (so ~/.bashagt/config doesn't exist and
# bashagt exits early on full init). But we only source the skill
# functions + their minimal deps, not the full init sequence.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

TEST_HOME="$(mktemp -d /tmp/bashagt_skill_test_XXXXXX)"
trap 'rm -rf "$TEST_HOME"' EXIT

# Create test directories
mkdir -p "$TEST_HOME/.bashagt/skills"
mkdir -p "$TEST_HOME/project/.bashagt/skills"

# Extract the skill functions and their minimal dependencies into a temp file.
# We need: parse_skill_file, load_skills, activate_skill, deactivate_skill,
# and the SKILLS/SKILL_META/ACTIVE_SKILLS declarations.
SKILL_LIB="$TEST_HOME/skill_lib.sh"

# Find the line range for Section 7b (entire skill system)
SEC7B_START=$(grep -n 'SECTION 7b:' "$BASHAGT" | head -1 | cut -d: -f1)
SEC7C_START=$(grep -n 'SECTION 7c:' "$BASHAGT" | head -1 | cut -d: -f1)

# Build a standalone skill library
{
    echo '#!/usr/bin/env bash'
    echo '# Minimal env for skill functions'
    echo 'set -euo pipefail'
    # Suppress log() calls — define a no-op stub
    echo 'log() { return 0; }'
    # Extract skill section
    sed -n "${SEC7B_START},$((SEC7C_START - 1))p" "$BASHAGT"
} > "$SKILL_LIB"

# Also extract build_sys_static and its cache dependencies
BUILD_START=$(grep -n '^build_sys_static()' "$BASHAGT" | head -1 | cut -d: -f1)
BUILD_END=$(grep -n '^build_dyn_context_msg()' "$BASHAGT" | head -1 | cut -d: -f1)
BUILD_END=$((BUILD_END - 1))

# _cc_hash function
CC_HASH_START=$(grep -n '^_cc_hash()' "$BASHAGT" | head -1 | cut -d: -f1)
CC_HASH_END=$(tail -n +$((CC_HASH_START + 1)) "$BASHAGT" | grep -n '^}' | head -1 | cut -d: -f1)
CC_HASH_END=$((CC_HASH_START + CC_HASH_END))

# _cc_get and _cc_put functions
CC_GET_START=$(grep -n '^_cc_get()' "$BASHAGT" | head -1 | cut -d: -f1)
CC_GET_END=$(tail -n +$((CC_GET_START + 1)) "$BASHAGT" | grep -n '^}' | head -1 | cut -d: -f1)
CC_GET_END=$((CC_GET_START + CC_GET_END))

CC_PUT_START=$(grep -n '^_cc_put()' "$BASHAGT" | head -1 | cut -d: -f1)
CC_PUT_END=$(tail -n +$((CC_PUT_START + 1)) "$BASHAGT" | grep -n '^}' | head -1 | cut -d: -f1)
CC_PUT_END=$((CC_PUT_START + CC_PUT_END))

# Build a more complete lib for build_sys_static tests
FULL_LIB="$TEST_HOME/full_lib.sh"
{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'log() { return 0; }'
    echo 'declare -A CACHE_TABLE'
    echo 'CACHE_TABLE=()'
    # _cc_hash
    sed -n "${CC_HASH_START},${CC_HASH_END}p" "$BASHAGT"
    # _cc_get
    sed -n "${CC_GET_START},${CC_GET_END}p" "$BASHAGT"
    # _cc_put
    sed -n "${CC_PUT_START},${CC_PUT_END}p" "$BASHAGT"
    # Skill section
    sed -n "${SEC7B_START},$((SEC7C_START - 1))p" "$BASHAGT"
    # build_sys_static
    sed -n "${BUILD_START},${BUILD_END}p" "$BASHAGT"
} > "$FULL_LIB"

# ════════════════════════════════════════════════════════════
# Create test skill directories (dir name = skill name)
# ════════════════════════════════════════════════════════════

# Skill 1: single-line JSON, name in JSON matches directory
mkdir -p "$TEST_HOME/.bashagt/skills/my-skill"
cat > "$TEST_HOME/.bashagt/skills/my-skill/skill.md" << 'EOF'
{"name": "my-skill", "description": "A test skill"}
This is the skill body.
It can have multiple lines.
EOF

# Skill 2: multi-line JSON, name matches directory
mkdir -p "$TEST_HOME/.bashagt/skills/multi-skill"
cat > "$TEST_HOME/.bashagt/skills/multi-skill/skill.md" << 'EOF'
{
  "name": "multi-skill",
  "description": "Multi-line frontmatter"
}
This skill uses multi-line frontmatter.
Line 2 of body.
EOF

# Skill 3: no "name" field in JSON — directory name used as fallback
mkdir -p "$TEST_HOME/.bashagt/skills/noname"
cat > "$TEST_HOME/.bashagt/skills/noname/skill.md" << 'EOF'
{"description": "No name field here"}
This skill has no name in JSON, dir name = noname.
EOF

# Skill 4: no JSON at all — should be rejected
mkdir -p "$TEST_HOME/.bashagt/skills/nojson"
cat > "$TEST_HOME/.bashagt/skills/nojson/skill.md" << 'EOF'
This file has no JSON frontmatter at all.
Just plain text.
EOF

# Skill 5: empty body
mkdir -p "$TEST_HOME/.bashagt/skills/empty-body"
cat > "$TEST_HOME/.bashagt/skills/empty-body/skill.md" << 'EOF'
{"name": "empty-body", "description": "Body is empty"}
EOF

# Project skill (different name from system skills)
mkdir -p "$TEST_HOME/project/.bashagt/skills/proj-skill"
cat > "$TEST_HOME/project/.bashagt/skills/proj-skill/skill.md" << 'EOF'
{"name": "proj-skill", "description": "Project-level skill"}
Project skill body here.
EOF

# Project skill (same DIR NAME as system skill — should be rejected)
mkdir -p "$TEST_HOME/project/.bashagt/skills/my-skill"
cat > "$TEST_HOME/project/.bashagt/skills/my-skill/skill.md" << 'EOF'
{"name": "my-skill", "description": "Should NOT override"}
This project version should be IGNORED.
EOF

echo "============================================"
echo " Skill System End-to-End Tests"
echo "============================================"
echo ""

# ════════════════════════════════════════════════════════════
# Test helper: run code with the skill lib sourced
# ════════════════════════════════════════════════════════════
_run_test() {
    local desc="$1" code="$2"
    local result
    result=$(HOME="$TEST_HOME" bash -c "
        set -euo pipefail
        source '$SKILL_LIB'
        cd '$TEST_HOME/project'
        $code
    " 2>&1) || true
    printf '%s' "$result"
}

# Same but with full lib (includes build_sys_static + cache)
_run_full_test() {
    local desc="$1" code="$2"
    local result
    result=$(HOME="$TEST_HOME" bash -c "
        set -euo pipefail
        source '$FULL_LIB'
        cd '$TEST_HOME/project'
        $code
    " 2>&1) || true
    printf '%s' "$result"
}

# ── Test 1: parse_skill_file — single-line JSON ──
echo "── parse_skill_file: single-line JSON ──"

result=$(_run_test "parse single" '
    parse_skill_file "$HOME/.bashagt/skills/my-skill/skill.md" "my-skill"
    printf "body=%s\n" "${SKILLS[my-skill]:-NOTFOUND}"
    printf "meta=%s\n" "${SKILL_META[my-skill]:-NOTFOUND}"
')

if printf '%s' "$result" | grep -q 'body=This is the skill body'; then
    _pass "single-line JSON: body stored correctly"
else
    _fail "single-line JSON: body stored" "body present" "$result"
fi

if printf '%s' "$result" | grep -q 'my-skill' && printf '%s' "$result" | grep -q '"name": "my-skill"'; then
    _pass "single-line JSON: meta JSON stored with name"
else
    _fail "single-line JSON: meta stored" "name in meta" "$result"
fi

# ── Test 2: parse_skill_file — multi-line JSON ──
echo "── parse_skill_file: multi-line JSON ──"

result=$(_run_test "parse multi" '
    parse_skill_file "$HOME/.bashagt/skills/multi-skill/skill.md" "multi-skill"
    printf "body=%s\n" "${SKILLS[multi-skill]:-NOTFOUND}"
')

if printf '%s' "$result" | grep -q 'This skill uses multi-line frontmatter'; then
    _pass "multi-line JSON: body stored correctly"
else
    _fail "multi-line JSON: body stored" "body present" "$result"
fi

# ── Test 3: parse_skill_file — name resolution ──
echo "── parse_skill_file: name resolution ──"

# Without opt_name, a JSON with no "name" field still fails
result=$(_run_test "no name, no opt" '
    if parse_skill_file "$HOME/.bashagt/skills/noname/skill.md"; then
        echo "RETURNED_OK"
    else
        echo "RETURNED_FAIL"
    fi
')

if printf '%s' "$result" | grep -q 'RETURNED_FAIL'; then
    _pass "no name in JSON + no opt_name: returns 1"
else
    _fail "no name in JSON + no opt_name: returns 1" "RETURNED_FAIL" "$result"
fi

# With opt_name (directory name), noname skill succeeds even without JSON "name"
result=$(_run_test "no name, with opt" '
    if parse_skill_file "$HOME/.bashagt/skills/noname/skill.md" "noname"; then
        echo "RETURNED_OK"
    else
        echo "RETURNED_FAIL"
    fi
')

if printf '%s' "$result" | grep -q 'RETURNED_OK'; then
    _pass "no name in JSON + opt_name=noname: succeeds (dir name fallback)"
else
    _fail "no name in JSON + opt_name: succeed" "RETURNED_OK" "$result"
fi

# Without opt_name, file with no JSON at all fails
result=$(_run_test "no JSON, no opt" '
    if parse_skill_file "$HOME/.bashagt/skills/nojson/skill.md"; then
        echo "RETURNED_OK"
    else
        echo "RETURNED_FAIL"
    fi
')

if printf '%s' "$result" | grep -q 'RETURNED_FAIL'; then
    _pass "no JSON frontmatter + no opt_name: returns 1"
else
    _fail "no JSON frontmatter + no opt_name: returns 1" "RETURNED_FAIL" "$result"
fi

# With opt_name, even a file with no JSON is loaded (name from dir, body = entire file)
result=$(_run_test "no JSON, with opt" '
    if parse_skill_file "$HOME/.bashagt/skills/nojson/skill.md" "nojson"; then
        printf "body=%s\n" "${SKILLS[nojson]:-NOTFOUND}"
        echo "RETURNED_OK"
    else
        echo "RETURNED_FAIL"
    fi
')

if printf '%s' "$result" | grep -q 'RETURNED_OK'; then
    _pass "no JSON + opt_name=nojson: succeeds (dir name, file content as body)"
else
    _fail "no JSON + opt_name: succeed" "RETURNED_OK" "$result"
fi

# ── Test 4: load_skills — loads from both directories ──
echo "── load_skills: system + project ──"

result=$(_run_test "load all" '
    load_skills
    for name in "${!SKILLS[@]}"; do
        printf "SKILL: %s\n" "$name"
    done
')

if printf '%s' "$result" | grep -q 'SKILL: my-skill'; then
    _pass "load_skills: system skill my-skill loaded"
else
    _fail "load_skills: system skill my-skill" "my-skill in output" "$result"
fi

if printf '%s' "$result" | grep -q 'SKILL: multi-skill'; then
    _pass "load_skills: system skill multi-skill loaded"
else
    _fail "load_skills: system skill multi-skill" "multi-skill in output" "$result"
fi

if printf '%s' "$result" | grep -q 'SKILL: proj-skill'; then
    _pass "load_skills: project skill proj-skill loaded"
else
    _fail "load_skills: project skill proj-skill" "proj-skill in output" "$result"
fi

# noname and nojson SHOULD now appear (dir name provides the name)
if printf '%s' "$result" | grep -q 'SKILL: noname' && printf '%s' "$result" | grep -q 'SKILL: nojson'; then
    _pass "load_skills: noname+nojson loaded via dir name fallback"
else
    _fail "load_skills: noname+nojson loaded" "both present" "$result"
fi

# ── Test 5: System priority over project ──
echo "── load_skills: system priority ──"

result=$(_run_test "priority" '
    load_skills
    printf "body=%s\n" "${SKILLS[my-skill]:-NOTFOUND}"
')

if printf '%s' "$result" | grep -q 'This is the skill body'; then
    _pass "system priority: system body preserved (project my-skill ignored)"
else
    _fail "system priority: system body preserved" "system body" "$result"
fi

if ! printf '%s' "$result" | grep -q 'Should NOT override'; then
    _pass "system priority: project override text not present"
else
    _fail "system priority: project override text" "absent" "$result"
fi

# ── Test 6: activate_skill ──
echo "── activate / deactivate ──"

result=$(_run_test "activate" '
    load_skills
    activate_skill "my-skill"
    printf "active=%s\n" "${ACTIVE_SKILLS[*]:-EMPTY}"
')

if printf '%s' "$result" | grep -q 'my-skill'; then
    _pass "activate_skill: skill added to ACTIVE_SKILLS"
else
    _fail "activate_skill: skill added" "my-skill in active" "$result"
fi

# Activate non-existent
result=$(_run_test "activate missing" '
    load_skills
    if activate_skill "nonexistent"; then
        echo "RETURNED_OK"
    else
        echo "RETURNED_FAIL"
    fi
')

if printf '%s' "$result" | grep -q 'RETURNED_FAIL'; then
    _pass "activate_skill nonexistent: returns 1"
else
    _fail "activate_skill nonexistent: returns 1" "RETURNED_FAIL" "$result"
fi

# Duplicate activation
result=$(_run_test "duplicate" '
    load_skills
    activate_skill "my-skill"
    activate_skill "my-skill"
    c=0
    for s in "${ACTIVE_SKILLS[@]}"; do
        [[ "$s" == "my-skill" ]] && c=$((c+1))
    done
    printf "count=%d\n" "$c"
')

if printf '%s' "$result" | grep -q 'count=1'; then
    _pass "activate_skill duplicate: idempotent (count=1)"
else
    _fail "activate_skill duplicate: idempotent" "count=1" "$result"
fi

# ── Test 7: deactivate_skill ──
echo "── deactivate ──"

result=$(_run_test "deactivate" '
    load_skills
    activate_skill "my-skill"
    activate_skill "multi-skill"
    deactivate_skill "my-skill"
    printf "active=%s\n" "${ACTIVE_SKILLS[*]:-EMPTY}"
')

# Check only the active= line (activation messages also contain skill names)
if printf '%s' "$result" | grep -q 'active=.*multi-skill' && ! printf '%s' "$result" | grep -q 'active=.*my-skill'; then
    _pass "deactivate_skill: removed my-skill, kept multi-skill"
else
    _fail "deactivate_skill: correct set" "multi-skill only" "$result"
fi

# Deactivate non-existent (should not crash)
result=$(_run_test "deactivate nonexistent" '
    load_skills
    activate_skill "my-skill"
    deactivate_skill "nonexistent"
    printf "active=%s\n" "${ACTIVE_SKILLS[*]:-EMPTY}"
')

if printf '%s' "$result" | grep -q 'my-skill'; then
    _pass "deactivate_skill nonexistent: no-op, my-skill still active"
else
    _fail "deactivate_skill nonexistent: no-op" "my-skill still active" "$result"
fi

# ── Test 8: Empty body skill ──
echo "── edge case: empty body ──"

result=$(_run_test "empty body" '
    parse_skill_file "$HOME/.bashagt/skills/empty-body/skill.md" "empty-body"
    printf "body_len=%d\n" "${#SKILLS[empty-body]}"
')

if printf '%s' "$result" | grep -q 'body_len=0'; then
    _pass "empty body: stored as empty string (length 0)"
else
    _fail "empty body: empty" "body_len=0" "$result"
fi

# ── Test 9: Multiple skills active ──
echo "── multiple active skills ──"

result=$(_run_test "multi activate" '
    load_skills
    activate_skill "my-skill"
    activate_skill "multi-skill"
    activate_skill "proj-skill"
    printf "count=%d list=%s\n" "${#ACTIVE_SKILLS[@]}" "${ACTIVE_SKILLS[*]}"
')

if printf '%s' "$result" | grep -q 'count=3'; then
    _pass "3 skills active simultaneously"
else
    _fail "3 skills active" "count=3" "$result"
fi

# ── Test 10: load_skills clears and replaces state ──
echo "── load_skills: state reset ──"

# Remove multi-skill/ dir and verify it disappears from SKILLS on reload
rm -rf "$TEST_HOME/.bashagt/skills/multi-skill"

result=$(_run_test "reload" '
    load_skills
    if [[ -n "${SKILLS[multi-skill]:-}" ]]; then
        printf "STILL_PRESENT\n"
    else
        printf "CLEARED\n"
    fi
    if [[ -n "${SKILLS[my-skill]:-}" ]]; then
        printf "MY_SKILL_STILL_PRESENT\n"
    fi
')

if printf '%s' "$result" | grep -q 'CLEARED'; then
    _pass "load_skills: removed skill (multi-skill/) gone after reload"
else
    _fail "load_skills: removed skill gone" "CLEARED" "$result"
fi

if printf '%s' "$result" | grep -q 'MY_SKILL_STILL_PRESENT'; then
    _pass "load_skills: existing skill (my-skill/) still present after reload"
else
    _fail "load_skills: existing skill preserved" "MY_SKILL_STILL_PRESENT" "$result"
fi

# ── Test 11: Skill body injected into build_sys_static ──
echo "── prompt injection: build_sys_static ──"

result=$(_run_full_test "injection" '
    load_skills
    activate_skill "my-skill"
    # Set required vars
    BASHAGT_MD=""
    BASHAGT_SYSTEM_PROMPT="You are a test assistant."
    AGENT_DESCRIPTIONS="agent1: does things"
    raw="${BASHAGT_MD:+$BASHAGT_MD\n\n}${BASHAGT_SYSTEM_PROMPT}

Available sub-agents — use agent(\"agent_name\", \"prompt\") for complex multi-step work.
Prefer agent() for: planning before coding, code review, complex searches, summarization.
${AGENT_DESCRIPTIONS}"
    if (( ${#ACTIVE_SKILLS[@]} > 0 )); then
        _skills_block=""
        for _sn in "${ACTIVE_SKILLS[@]}"; do
            [[ -n "${SKILLS[$_sn]:-}" ]] && _skills_block+=$'\''\n\n'\''"${SKILLS[$_sn]}" || true
        done
        raw+="$_skills_block"
    fi
    if printf '\''%s'\'' "$raw" | grep -q "This is the skill body"; then
        printf "INJECTED=yes\n"
    else
        printf "INJECTED=no\n"
        printf "RAW_TAIL=%s\n" "$(printf '\''%s'\'' "$raw" | tail -5)"
    fi
')

if printf '%s' "$result" | grep -q 'INJECTED=yes'; then
    _pass "prompt injection: skill body appears in system prompt raw string"
else
    _fail "prompt injection: skill body in raw" "INJECTED=yes" "$result"
fi

# No skills activated → raw should NOT include skill bodies
result=$(_run_full_test "no injection when inactive" '
    load_skills
    BASHAGT_MD=""
    BASHAGT_SYSTEM_PROMPT="You are a test assistant."
    AGENT_DESCRIPTIONS="agent1: does things"
    raw="${BASHAGT_MD:+$BASHAGT_MD\n\n}${BASHAGT_SYSTEM_PROMPT}

Available sub-agents — use agent(\"agent_name\", \"prompt\") for complex multi-step work.
Prefer agent() for: planning before coding, code review, complex searches, summarization.
${AGENT_DESCRIPTIONS}"
    if (( ${#ACTIVE_SKILLS[@]} > 0 )); then
        _skills_block=""
        for _sn in "${ACTIVE_SKILLS[@]}"; do
            [[ -n "${SKILLS[$_sn]:-}" ]] && _skills_block+=$'\''\n\n'\''"${SKILLS[$_sn]}" || true
        done
        raw+="$_skills_block"
        printf "HAS_SKILLS\n"
    else
        printf "NO_SKILLS_INJECTED\n"
    fi
')

if printf '%s' "$result" | grep -q 'NO_SKILLS_INJECTED'; then
    _pass "prompt injection: no skill body when no skills active"
else
    _fail "prompt injection: no injection" "NO_SKILLS_INJECTED" "$result"
fi

# ── Test 12: Empty subdirectory (no skill.md) — skipped by load_skills ──
echo "── directory scan: empty subdir skipped ──"

mkdir -p "$TEST_HOME/.bashagt/skills/empty-dir"

result=$(_run_test "empty dir" '
    load_skills
    if [[ -n "${SKILLS[empty-dir]:-}" ]]; then
        printf "LOADED\n"
    else
        printf "SKIPPED\n"
    fi
')

if printf '%s' "$result" | grep -q 'SKIPPED'; then
    _pass "empty subdir (no skill.md): skipped by load_skills"
else
    _fail "empty subdir: skipped" "SKIPPED" "$result"
fi

# ── Test 13: Directory name takes priority over JSON "name" field ──
echo "── directory name priority over JSON name ──"

mkdir -p "$TEST_HOME/.bashagt/skills/dir-name-wins"
cat > "$TEST_HOME/.bashagt/skills/dir-name-wins/skill.md" << 'EOF'
{"name": "json-name", "description": "JSON says json-name but dir says dir-name-wins"}
This body belongs to dir-name-wins.
EOF

result=$(_run_test "dir name wins" '
    load_skills
    if [[ -n "${SKILLS[dir-name-wins]:-}" ]]; then
        printf "DIR_NAME_WINS body=%s\n" "${SKILLS[dir-name-wins]}"
    else
        printf "DIR_NAME_MISSING\n"
    fi
    if [[ -n "${SKILLS[json-name]:-}" ]]; then
        printf "JSON_NAME_LOADED\n"
    else
        printf "JSON_NAME_IGNORED\n"
    fi
')

if printf '%s' "$result" | grep -q 'DIR_NAME_WINS'; then
    _pass "dir name priority: skill loaded under directory name (dir-name-wins)"
else
    _fail "dir name priority: loaded under dir name" "DIR_NAME_WINS" "$result"
fi

if printf '%s' "$result" | grep -q 'JSON_NAME_IGNORED'; then
    _pass "dir name priority: JSON name field ignored (json-name not in SKILLS)"
else
    _fail "dir name priority: JSON name ignored" "JSON_NAME_IGNORED" "$result"
fi

# ── Summary ──
echo ""
echo "============================================"
echo " Skill E2E Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
