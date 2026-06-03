#!/usr/bin/env bash
# test_input_pty.sh — Wrapper for PTY-based input system tests
# Run: bash test/test_input_pty.sh [--test NAME] [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure bashagt is on PATH
export PATH="$SCRIPT_DIR/..:$PATH"

# Use test API key if not set
export BASHAGT_API_KEY="${BASHAGT_API_KEY:-sk-test-dummy-key}"

exec python3 "$SCRIPT_DIR/test_input_pty.py" "$@"
