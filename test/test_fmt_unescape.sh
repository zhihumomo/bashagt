#!/usr/bin/env bash
# test_fmt_unescape.sh — Tests for _json_unescape + _fmt_stream_callback double-unescape bug
#
# Verifies that jq-decoded text (already unescaped) is NOT passed through
# _json_unescape, which would double-convert literal \n \t \" \\ sequences.

source "$(dirname "$0")/test_harness.sh"

# ── Extract needed functions from bashagt ──
BASHAGT="${BASHAGT:-$(dirname "$0")/../bashagt}"
EXTRACT_DIR="${TEST_TMPDIR:-/tmp}/fmt_unescape_extract"
mkdir -p "$EXTRACT_DIR"

sed -n '/^_json_unescape()/,/^}/p' "$BASHAGT" > "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"
sed -n '/^_FMT_LINEBUF=/p; /^_FMT_OUTFD=/p; /^_FMT_PREFIX=/p; /^_FMT_DONE_LABEL=/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"
echo 'export _FMT_LINEBUF="" _FMT_OUTFD=1 _FMT_PREFIX="" _FMT_DONE_LABEL="" _FMT_START_TS=0 _FMT_DONE_ITOK=0 _FMT_DONE_OTOK=0' >> "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"
sed -n '/^_fmt_stream_callback()/,/^}/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"
sed -n '/^_fmt_postprocess_var()/,/^}/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"
echo >> "$EXTRACT_DIR/funcs.sh"
sed -n '/^_fmt_postprocess()/,/^}/p' "$BASHAGT" >> "$EXTRACT_DIR/funcs.sh"

cat >> "$EXTRACT_DIR/funcs.sh" << 'STUB'
BOLD=""; DIM=""; RESET=""; OK_COLOR=""; ERR_COLOR=""
WARN_COLOR=""; PATH_COLOR=""; CMD_COLOR=""; META_COLOR=""
SEL_COLOR=""; VAR=""; LINK_COLOR=""
STUB

source "$EXTRACT_DIR/funcs.sh"

# ─── _json_unescape — raw JSON substring (old bash path, correct behavior) ───

describe "_json_unescape — raw JSON substring (old bash path)"

_test_raw_n() {
    _t_raw=$'hello\\nworld'
    _json_unescape "$_t_raw" _t_out
    assert_contains "$_t_out" "hello" "should contain hello"
    assert_contains "$_t_out" "world" "should contain world"
}

_test_raw_literal_backslash_n_preserved() {
    # Raw JSON substring for: printf(\"\\n\") — SOH protection kicks in
    printf -v _t_raw 'printf(\\\"\\\\n\\\")'
    _json_unescape "$_t_raw" _t_out
    # Expected: printf("\n") — ONE backslash + n (literal \n, NOT newline)
    _t_expected='printf("\n")'
    assert_equal "$_t_out" "$_t_expected" "literal \\n should be preserved"
}

_test_raw_quote() {
    printf -v _t_raw 'say \\\"hello\\\"'
    _json_unescape "$_t_raw" _t_out
    assert_equal "$_t_out" 'say "hello"' "quotes should be decoded"
}

_test_raw_backslash() {
    printf -v _t_raw 'path\\\\to\\\\file'
    _json_unescape "$_t_raw" _t_out
    assert_equal "$_t_out" 'path\to\file' "double-backslash → single"
}

_test_raw_tab() {
    printf -v _t_raw 'col1\\tcol2'
    _json_unescape "$_t_raw" _t_out
    assert_equal "$_t_out" 'col1	col2' "\\t → tab"
}

_test_raw_plain() {
    _t_raw="hello world"
    _json_unescape "$_t_raw" _t_out
    assert_equal "$_t_out" "hello world" "plain text passes through"
}

it "converts raw JSON \\n → literal newline"; _test_raw_n
it "preserves literal \\\\n (SOH protects n from LF)"; _test_raw_literal_backslash_n_preserved
it "converts raw JSON \\\" → literal quote"; _test_raw_quote
it "converts raw JSON \\\\ → single backslash"; _test_raw_backslash
it "converts raw JSON \\t → literal tab"; _test_raw_tab
it "passes through plain text unchanged"; _test_raw_plain

# ─── _json_unescape on jq-decoded text (DOUBLE UNESCAPE BUG) ───

describe "_json_unescape on jq-decoded text (double-unescape bug demo)"

_test_jq_literal_n_is_converted() {
    # jq -r on JSON {"text":"\\\\n"} produces: \n (backslash+n, 2 chars, NOT newline)
    printf -v _t_raw 'printf("\n")'         # literal backslash+n as 2 chars
    _json_unescape "$_t_raw" _t_out
    # BUG: _json_unescape converts \n → LF. Expected: ONE backslash + n preserved.
    _t_expected='printf("\n")'
    if [[ "$_t_out" != "$_t_expected" ]]; then
        printf '  %sBUG CONFIRMED%s: literal \\n → LF. got: %s\n' \
            "$_RED" "$_RESET" "$(printf '%s' "$_t_out" | cat -A)"
        _TESTS_TOTAL=$((_TESTS_TOTAL + 1))
        _TESTS_FAILED=$((_TESTS_FAILED + 1))
        printf '\r  %s✗%s %s\n' "$_RED" "$_RESET" "$_CURRENT_IT"
        printf '    %s→%s %s\n' "$_RED" "$_RESET" \
            "BUG: literal \\n converted to newline"
        return 0
    fi
    _pass
}

_test_jq_literal_t_is_converted() {
    printf -v _t_raw 'col1\tcol2'           # literal backslash+t as 2 chars
    _json_unescape "$_t_raw" _t_out
    if [[ "$_t_out" != 'col1\tcol2' ]]; then
        printf '  %sBUG CONFIRMED%s: literal \\t → tab. got: %s\n' \
            "$_RED" "$_RESET" "$(printf '%s' "$_t_out" | cat -A)"
        _TESTS_TOTAL=$((_TESTS_TOTAL + 1))
        _TESTS_FAILED=$((_TESTS_FAILED + 1))
        printf '\r  %s✗%s %s\n' "$_RED" "$_RESET" "$_CURRENT_IT"
        printf '    %s→%s %s\n' "$_RED" "$_RESET" \
            "BUG: literal \\t converted to tab"
        return 0
    fi
    _pass
}

it "BUG: jq-decoded literal \\n wrongly → newline"; _test_jq_literal_n_is_converted
it "BUG: jq-decoded literal \\t wrongly → tab"; _test_jq_literal_t_is_converted

# ─── _fmt_stream_callback integration ───

describe "_fmt_stream_callback — SSE data extraction (jq-first)"

_test_fmt_standard() {
    _FMT_LINEBUF=""
    _fmt_stream_callback "" '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello world"}}' "" ""
    assert_equal "$_FMT_LINEBUF" "hello world"
}

_test_fmt_reversed_fields() {
    _FMT_LINEBUF=""
    _fmt_stream_callback "" '{"delta":{"type":"text_delta","text":"hello world"},"type":"content_block_delta","index":0}' "" ""
    assert_equal "$_FMT_LINEBUF" "hello world"
}

_test_fmt_preserve_literal_n() {
    _FMT_LINEBUF=""
    # JSON \\n encodes literal \n (backslash+n, 2 chars in source text)
    _t_data='{"delta":{"type":"text_delta","text":"code: \\n means newline"}}'
    _fmt_stream_callback "" "$_t_data" "" ""
    _t_expected='code: \n means newline'
    assert_equal "$_FMT_LINEBUF" "$_t_expected" "literal \\n should be preserved"
}

_test_fmt_preserve_literal_t() {
    _FMT_LINEBUF=""
    _t_data='{"delta":{"type":"text_delta","text":"format: \\t is tab"}}'
    _fmt_stream_callback "" "$_t_data" "" ""
    _t_expected='format: \t is tab'
    assert_equal "$_FMT_LINEBUF" "$_t_expected" "literal \\t should be preserved"
}

_test_fmt_extra_fields() {
    _FMT_LINEBUF=""
    _fmt_stream_callback "" '{"delta":{"type":"text_delta","text":"result"},"type":"content_block_delta","index":0,"custom":"extra"}' "" ""
    assert_equal "$_FMT_LINEBUF" "result"
}

_test_fmt_empty_text() {
    _FMT_LINEBUF=""
    _fmt_stream_callback "" '{"delta":{"type":"text_delta","text":""}}' "" ""
    assert_equal "$_FMT_LINEBUF" ""
}

_test_fmt_accumulate() {
    _FMT_LINEBUF=""
    _fmt_stream_callback "" '{"delta":{"type":"text_delta","text":"part1 "}}' "" ""
    _fmt_stream_callback "" '{"delta":{"type":"text_delta","text":"part2"}}' "" ""
    assert_equal "$_FMT_LINEBUF" "part1 part2"
}

_test_fmt_non_json() {
    _FMT_LINEBUF="before"
    _fmt_stream_callback "" "event: ping" "" ""
    assert_equal "$_FMT_LINEBUF" "before"
}

it "extracts std Anthropic format"; _test_fmt_standard
it "extracts reversed fields (BaiLian)"; _test_fmt_reversed_fields
it "preserves literal \\\\n in code (no double-unescape)"; _test_fmt_preserve_literal_n
it "preserves literal \\\\t in code (no double-unescape)"; _test_fmt_preserve_literal_t
it "extracts with extra unknown fields"; _test_fmt_extra_fields
it "handles empty text field"; _test_fmt_empty_text
it "accumulates across calls before flush"; _test_fmt_accumulate
it "ignores non-JSON data"; _test_fmt_non_json

# ─── Cleanup ───
rm -rf "$EXTRACT_DIR"

echo ""
echo "Note: 'BUG CONFIRMED' tests should PASS after fix (no double-unescape),"
echo "      and FAIL before fix (current behavior)."
