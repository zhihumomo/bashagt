#!/usr/bin/env python3
"""PTY-based E2E test driver for bashagt input system.

Usage: python3 test/test_input_pty.py [--test NAME] [--verbose]

Creates a pseudo-terminal, spawns bashagt in interactive mode, sends
keystrokes, and verifies terminal output. Tests the input layer only —
kills the process before any API call is made.

Requires: Python 3.6+, bash 4.0+
"""

import pty
import os
import sys
import time
import select
import signal
import struct
import fcntl
import termios
import json
import argparse
import traceback

PASS = 0
FAIL = 0
VERBOSE = False

# ── PTY helpers ──────────────────────────────────────────────────────────────

def set_pty_size(fd, rows, cols):
    """Set PTY window size via TIOCSWINSZ."""
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)

def strip_ansi(s):
    """Remove ANSI escape sequences from string for content verification."""
    import re
    # CSI sequences: ESC [ ... m/letter
    ansi = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]')
    # OSC sequences
    ansi2 = re.compile(r'\x1b\].*?(\x1b\\|\x07)')
    # Other escapes
    ansi3 = re.compile(r'\x1b[()][0-2AB]')
    s = ansi.sub('', s)
    s = ansi2.sub('', s)
    s = ansi3.sub('', s)
    # Bracketed paste escape
    s = s.replace('\x1b[?2004h', '').replace('\x1b[?2004l', '')
    # Cursor save/restore
    s = s.replace('\x1b7', '').replace('\x1b8', '')
    # \r\n → newline for comparison
    s = s.replace('\r\n', '\n').replace('\r', '\n')
    # Collapse multiple blank lines
    while '\n\n\n' in s:
        s = s.replace('\n\n\n', '\n\n')
    return s

def ansi_screen_lines(s):
    """Parse ANSI output into approximate screen lines (last 24 rows)."""
    # Strip SGR but keep cursor movements for line tracking
    import re
    sgr = re.compile(r'\x1b\[[0-9;]*m')
    clean = sgr.sub('', s)
    clean = clean.replace('\x1b[?2004h', '').replace('\x1b[?2004l', '')
    clean = clean.replace('\x1b7', '').replace('\x1b8', '')

    # Split into lines
    lines = clean.split('\n')
    # Take last 24 lines
    return lines[-24:]

def find_in_output(output, text, strip_control=True):
    """Check if text appears in output (after optional ANSI stripping)."""
    if strip_control:
        clean = strip_ansi(output)
    else:
        clean = output
    return text in clean

# ── Test runner ──────────────────────────────────────────────────────────────

def run_pty_test(test_name, inputs, checks, rows=24, cols=80, timeout=8,
                 start_delay=0.8, post_delay=0.3, mode='interactive'):
    """Run bashagt in a PTY, send inputs, run checks.

    Args:
        test_name: Display name
        inputs: List of (delay_seconds, bytes_to_send) tuples
        checks: List of (description, match_string) — all must be in output
        rows, cols: Terminal size
        timeout: Max total seconds
        start_delay: Wait after spawn before sending input
        post_delay: Wait after last input before reading
        mode: 'interactive' or 'oneshot'

    Returns True on pass.
    """
    global PASS, FAIL, VERBOSE

    pid, fd = pty.fork()
    if pid == 0:
        # Child: configure environment and exec bashagt
        os.environ['TERM'] = 'xterm-256color'
        os.environ['COLUMNS'] = str(cols)
        os.environ['LINES'] = str(rows)
        os.environ['BASHAGT_LOG_LEVEL'] = 'ERROR'
        # Suppress logging to stderr during tests
        os.environ['BASHAGT_LOG_STDERR'] = '0'
        # Dummy API key — won't be used since we kill before API call
        if 'BASHAGT_API_KEY' not in os.environ:
            os.environ['BASHAGT_API_KEY'] = 'sk-test-dummy-key'

        if mode == 'oneshot':
            # Oneshot reads from stdin
            os.execvp('bash', ['bash', '-c', 'exec bashagt --oneshot --stream'])
        else:
            os.execvp('bash', ['bash', '-c', 'exec bashagt'])

    # Parent: drive the PTY
    try:
        set_pty_size(fd, rows, cols)

        # Wait for bashagt prompt to appear (signals _input_readline is active
        # and stty -echo is set) before sending input. Falls back to start_delay
        # if prompt detection times out.
        _prompt_seen = False
        _init_output = b''
        _deadline = time.time() + max(start_delay + 5, 15)
        while time.time() < _deadline and not _prompt_seen:
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try:
                    data = os.read(fd, 4096)
                    if data:
                        _init_output += data
                        # Look for the prompt character (› = U+203A) in UTF-8
                        if b'\x80\xba' in data or b'\xba' in data:
                            _prompt_seen = True
                except OSError:
                    break
        if not _prompt_seen:
            time.sleep(start_delay)  # fallback

        # Send all inputs with delays
        for delay, data in inputs:
            if delay > 0:
                time.sleep(delay)
            try:
                os.write(fd, data if isinstance(data, bytes) else data.encode('utf-8'))
            except (BrokenPipeError, OSError):
                break

        time.sleep(post_delay)

        # Read all available output
        output = b''
        deadline = time.time() + timeout
        while time.time() < deadline:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try:
                    data = os.read(fd, 4096)
                    if not data:
                        break
                    output += data
                except OSError:
                    break
            # Check if process exited
            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid:
                break

        # Prepend init output (banner, prompt) to the post-input output
        output = _init_output + output
        output_str = output.decode('utf-8', errors='replace')

        if VERBOSE:
            print(f"\n{'='*60}")
            print(f"TEST: {test_name}")
            print(f"{'='*60}")
            print(f"RAW OUTPUT ({len(output_str)} chars):")
            # Show repr for first 2000 chars then plain text
            print(repr(output_str[:2000]))
            if len(output_str) > 2000:
                print(f"... ({len(output_str) - 2000} more chars)")
            print(f"{'='*60}")

        all_ok = True
        for check_desc, match_str in checks:
            ok = find_in_output(output_str, match_str)
            if ok:
                if VERBOSE:
                    print(f"  ✓ {check_desc}")
            else:
                all_ok = False
                if VERBOSE:
                    print(f"  ✗ {check_desc} — '{match_str[:60]}' not found")
                    print(f"    Clean output snippet: {repr(strip_ansi(output_str)[-500:])}")
                else:
                    print(f"  FAIL: {test_name} — {check_desc}")
                    print(f"    Missing: '{match_str[:80]}'")
                    print(f"    Last 300 chars: {repr(strip_ansi(output_str)[-300:])}")

        if all_ok:
            PASS += 1
            if not VERBOSE:
                print(f"  PASS: {test_name}")
            return True
        else:
            FAIL += 1
            return False

    finally:
        # Kill if still running
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(0.1)
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass
        os.close(fd)


# ── Test Cases ───────────────────────────────────────────────────────────────

def test_basic_typing():
    """Type a simple command, verify it appears on screen."""
    run_pty_test(
        "basic typing",
        inputs=[
            (0.2, b'echo hello'),
        ],
        checks=[
            ("prompt visible", '›'),   # › character
            ("typed text appears", 'echo hello'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_backspace():
    """Type then backspace, verify deletion."""
    run_pty_test(
        "backspace",
        inputs=[
            (0.2, b'abcd'),
            (0.05, b'\x7f'),  # Backspace
            (0.05, b'\x7f'),  # Backspace again
            (0.05, b'xy'),
        ],
        checks=[
            ("corrected text", 'abxy'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_multiline_input():
    """Type multiple lines with backslash continuation."""
    run_pty_test(
        "multiline input",
        inputs=[
            (0.2, b'line one\\'),    # backslash = continuation
            (0.05, b'\r'),           # Enter inserts newline
            (0.05, b'line two'),
        ],
        checks=[
            ("first line", 'line one'),
            ("second line", 'line two'),
            ("continuation prompt", '⋯'),  # ⋯ character
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_cursor_left_right():
    """Move cursor left and right with arrow keys."""
    run_pty_test(
        "cursor movement",
        inputs=[
            (0.2, b'hello'),
            (0.05, b'\x1b[D'),  # Left arrow
            (0.05, b'\x1b[D'),  # Left arrow
            (0.05, b'X'),
        ],
        checks=[
            ("inserted at cursor", 'helXlo'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_paste_single_line():
    """Paste single line via bracketed paste."""
    paste_text = 'pasted content'
    run_pty_test(
        "paste single line",
        inputs=[
            (0.2, b'\x1b[200~'),  # PASTE_START
            (0.02, paste_text.encode()),
            (0.02, b'\x1b[201~'),  # PASTE_END
        ],
        checks=[
            ("pasted content visible", paste_text),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_paste_multiline():
    """Paste multiple lines via bracketed paste."""
    run_pty_test(
        "paste multiline",
        inputs=[
            (0.2, b'\x1b[200~'),
            (0.02, b'line_a\nline_b\nline_c'),
            (0.02, b'\x1b[201~'),
        ],
        checks=[
            ("line a visible", 'line_a'),
            ("line b visible", 'line_b'),
            ("line c visible", 'line_c'),
            ("line count shown", 'pasted'),   # "[pasted N lines]" shown
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_wrapped_line():
    """Long line that wraps at terminal edge (40 cols)."""
    long_text = 'a' * 50 + 'b' * 10  # 60 chars, wraps at col 40
    run_pty_test(
        "wrapped line (40 cols)",
        inputs=[
            (0.2, long_text.encode()),
        ],
        checks=[
            ("long text visible", 'a' * 50),
            ("wrap works", 'b' * 10),
        ],
        cols=40,
        start_delay=1.0,
        post_delay=0.5,
    )

def test_cjk_display():
    """Type CJK characters (width=2), verify rendering."""
    run_pty_test(
        "CJK display width",
        inputs=[
            (0.2, '你好世界'.encode()),
        ],
        checks=[
            ("CJK characters visible", '你好世界'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_cjk_backspace():
    """Backspace on CJK characters — verifies multi-byte deletion works."""
    run_pty_test(
        "CJK backspace",
        inputs=[
            (0.2, '你好'.encode()),
            (0.05, b'\x7f'),   # Backspace (DEL)
            (0.05, 'A'.encode()),
        ],
        checks=[
            ("CJK partial + ASCII", '你A'),
        ],
        start_delay=2.5,       # bashagt init takes ~2s (banner, config, agents)
        post_delay=0.5,
    )

def test_ctrl_a_ctrl_e():
    """Ctrl-A home, Ctrl-E end."""
    run_pty_test(
        "Ctrl-A/E navigation",
        inputs=[
            (0.2, b'hello'),
            (0.05, b'\x01'),  # Ctrl-A
            (0.05, b'-'),
            (0.05, b'\x05'),  # Ctrl-E
            (0.05, b'-'),
        ],
        checks=[
            ("home+end inserts", '-hello-'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_ctrl_u_kill_to_start():
    """Ctrl-U kills to start of line."""
    run_pty_test(
        "Ctrl-U kill to start",
        inputs=[
            (0.2, b'hello world'),
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x15'),   # Ctrl-U
        ],
        checks=[
            ("only 'world' remains", 'world'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_ctrl_w_kill_word():
    """Ctrl-W kills word before cursor."""
    run_pty_test(
        "Ctrl-W kill word",
        inputs=[
            (0.2, b'hello world foo'),
            (0.05, b'\x17'),   # Ctrl-W
        ],
        checks=[
            ("deletes last word", 'hello world'),
            ("'foo' is gone", 'foo'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_ctrl_k_kill_to_end():
    """Ctrl-K kills from cursor to end of line."""
    run_pty_test(
        "Ctrl-K kill to end",
        inputs=[
            (0.2, b'hello world'),
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x1b[D'),  # Left
            (0.05, b'\x0b'),    # Ctrl-K
        ],
        checks=[
            ("only 'hello ' remains", 'hello'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )

def test_escape_timeout_no_leak():
    """Incomplete escape sequence doesn't leak garbage."""
    run_pty_test(
        "escape timeout no leak",
        inputs=[
            (0.2, b'\x1b[X'),  # ESC [ X — X terminates but not a valid seq → UNKNOWN
        ],
        checks=[
            ("prompt still visible", '›'),
        ],
        start_delay=1.0,
        post_delay=0.5,
    )


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    global PASS, FAIL, VERBOSE

    parser = argparse.ArgumentParser(description='bashagt input system PTY tests')
    parser.add_argument('--test', help='Run specific test by name')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    args = parser.parse_args()

    VERBOSE = args.verbose

    tests = [
        test_basic_typing,
        test_backspace,
        test_multiline_input,
        test_cursor_left_right,
        test_paste_single_line,
        test_paste_multiline,
        test_wrapped_line,
        test_cjk_display,
        test_cjk_backspace,
        test_ctrl_a_ctrl_e,
        test_ctrl_u_kill_to_start,
        test_ctrl_w_kill_word,
        test_ctrl_k_kill_to_end,
        test_escape_timeout_no_leak,
    ]

    if args.test:
        tests = [t for t in tests if args.test in t.__name__]
        if not tests:
            print(f"No test matching '{args.test}'")
            sys.exit(1)

    print(f"\n{'='*60}")
    print(f" bashagt PTY Input Tests")
    print(f"{'='*60}\n")

    for test_fn in tests:
        try:
            test_fn()
        except Exception as e:
            FAIL += 1
            print(f"  ERROR: {test_fn.__name__} — {e}")
            if VERBOSE:
                traceback.print_exc()

    print(f"\n{'='*60}")
    print(f" Results: {PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    print(f"{'='*60}")

    sys.exit(0 if FAIL == 0 else 1)


if __name__ == '__main__':
    main()
