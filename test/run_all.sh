#!/usr/bin/env bash
# run_all.sh — Run all bashagt test suites
# Usage: bash test/run_all.sh [--integration] [--e2e] [--daemon]
#   No flags:     unit + integrity tests only (no API needed)
#   --integration: also runs basic integration tests (requires API key)
#   --e2e:         also runs end-to-end oneshot + interactive tests
#   --daemon:      also runs daemon HTTP/SSE test (starts background daemon)
#   --all:         run EVERYTHING

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

OVERALL_PASS=0
OVERALL_FAIL=0
INTEGRATION_SKIP=0
MODE="${1:-}"

run_suite() {
    local name="$1" script="$2"
    echo ""
    echo "┌──────────────────────────────────────────┐"
    echo "│  Running: $name"
    echo "└──────────────────────────────────────────┘"
    echo ""
    if bash "$script" 2>&1; then
        echo ""
        echo "  ✅ $name: PASSED"
        OVERALL_PASS=$((OVERALL_PASS+1))
    else
        echo ""
        echo "  ❌ $name: FAILED"
        OVERALL_FAIL=$((OVERALL_FAIL+1))
    fi
}

# Always run unit + integrity + regression tests (no API needed)
run_suite "Portable Utility Unit Tests" "test/test_portable_utils.sh"
run_suite "Code Integrity Checks"      "test/test_code_integrity.sh"
run_suite "Regression Tests"           "test/test_regression.sh"
run_suite "Slash Command E2E Tests"    "test/test_e2e_slash.sh"

# Integration + E2E tests require --integration, --e2e, --daemon, or --all flag
if [[ "$MODE" == "--integration" || "$MODE" == "--e2e" || "$MODE" == "--daemon" || "$MODE" == "--all" ]]; then
    has_key=0
    grep -q '"api_key"' "$HOME/.bashagt/settings.json" 2>/dev/null && has_key=1

    if [[ $has_key -eq 1 ]]; then
        if [[ "$MODE" == "--integration" || "$MODE" == "--all" ]]; then
            run_suite "Integration Tests" "test/test_integration.sh"
        fi
        if [[ "$MODE" == "--e2e" || "$MODE" == "--all" ]]; then
            run_suite "E2E Oneshot Tests" "test/test_e2e_oneshot.sh"
            run_suite "E2E Interactive Tests" "test/test_e2e_interactive.sh"
        fi
        if [[ "$MODE" == "--daemon" || "$MODE" == "--all" ]]; then
            run_suite "E2E Daemon HTTP/SSE Tests" "test/test_e2e_daemon.sh"
        fi
    else
        echo ""
        echo "  ⚠️  Skipping API-dependent tests: no API key configured"
        INTEGRATION_SKIP=1
    fi
else
    echo ""
    echo "  ℹ️  Skipping API-dependent tests"
    echo "     --integration  : basic integration tests"
    echo "     --e2e          : oneshot + interactive E2E tests"
    echo "     --daemon       : daemon HTTP/SSE test"
    echo "     --all          : run everything"
fi

echo ""
echo "============================================"
if [[ $OVERALL_FAIL -eq 0 ]]; then
    echo " All suites passed ($OVERALL_PASS total)"
    [[ $INTEGRATION_SKIP -eq 1 ]] && echo " (integration tests skipped)"
    echo "============================================"
    exit 0
else
    echo " $OVERALL_PASS passed, $OVERALL_FAIL failed"
    echo "============================================"
    exit 1
fi
