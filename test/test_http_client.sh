#!/usr/bin/env bash
# test_http_client.sh — HTTP client unit tests (Section 14)
# Run: bash test/test_http_client.sh
# No API required. Uses mock curl via temp-file spy pattern.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASHAGT="$SCRIPT_DIR/../bashagt"
PASS=0; FAIL=0

green() { printf '\033[32m  PASS: %s\033[0m\n' "$*"; }
red()   { printf '\033[31m  FAIL: %s (expected: %s, got: %s)\033[0m\n' "$1" "$2" "${3:-N/A}"; }
_pass() { PASS=$((PASS+1)); green "$1"; }
_fail() { FAIL=$((FAIL+1)); red "$1" "$2" "${3:-N/A}"; }

[[ -f "$BASHAGT" ]] || { echo "ERROR: bashagt not found at $BASHAGT"; exit 1; }

# ── Extract HTTP client section ──
_HTTP_START=$(grep -n '^_http_map_exit()' "$BASHAGT" | head -1 | cut -d: -f1)
_AGENT_START=$(grep -n '^parse_agent_file()' "$BASHAGT" | head -1 | cut -d: -f1)
sed -n "${_HTTP_START},$((_AGENT_START - 1))p" "$BASHAGT" > /tmp/bashagt_http_funcs.sh

echo "============================================"
echo " HTTP Client Unit Tests"
echo "============================================"
echo ""

# ── Write test script ──
cat > /tmp/bashagt_http_test.sh << 'TESTEOF'
set +e
source /tmp/bashagt_http_funcs.sh

PASS=0; FAIL=0
_green() { printf 'PASS:%s\n' "$*"; }
_red() { printf 'FAIL:%s|%s|%s\n' "$1" "$2" "$3"; }

log() { return 0; }
_mktemp_file() { mktemp "$@"; }
_mktemp_u() { mktemp -u "$@"; }
_interrupted() { return 1; }
_poll_esc() { return 0; }
CURL_MOCK_RC=0
CURL_MOCK_OUTPUT="mock response body"
CURL_MOCK_STATUS="200|0.1|10"
BASHAGT_CONNECT_TIMEOUT=5
BASHAGT_PROXY_URL=""
BASHAGT_PROXY_USER=""
BASHAGT_PROXY_PASS=""
BASHAGT_PROXY_NOPROXY="localhost,127.0.0.1,::1"

_SPY_FILE="/tmp/bashagt_spy_$$.txt"
_spy_reset() { : > "$_SPY_FILE"; }
_spy_has() { grep -qFx "$1" "$_SPY_FILE" 2>/dev/null; }

curl() {
    local _i _o_file=""
    for ((_i=1; _i<=$#; _i++)); do
        case "${!_i}" in
            -X) _i=$((_i+1)); printf 'METHOD:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            -L) printf 'FLAG:L\n' >> "$_SPY_FILE" ;;
            -d) _i=$((_i+1)); printf 'BODY:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            -H) _i=$((_i+1)); printf 'HDR:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            --connect-timeout) _i=$((_i+1)); printf 'CT:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            --max-time) _i=$((_i+1)); printf 'MT:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            --proxy) _i=$((_i+1)); printf 'PROXY:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            --proxy-user) _i=$((_i+1)); printf 'PROXYUSER:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            --noproxy) _i=$((_i+1)); printf 'NOPROXY:%s\n' "${!_i}" >> "$_SPY_FILE" ;;
            -o) _i=$((_i+1)); _o_file="${!_i}" ;;
        esac
        [[ "${!_i}" != -* && "${!_i}" == http* ]] && printf 'URL:%s\n' "${!_i}" >> "$_SPY_FILE"
    done
    [[ -n "$_o_file" ]] && printf '%s' "$CURL_MOCK_OUTPUT" > "$_o_file"
    printf '%s' "${CURL_MOCK_STATUS:-200|0.0|0}"
    return "${CURL_MOCK_RC:-0}"
}

_hreq() { ( set +e; http_request "$@" >/dev/null 2>&1 ); return $?; }

# T1-T12 _http_map_exit
_test_map() {
    set +e; (_http_map_exit "$2" "$3" "$4"); local _a=$?; set -e
    [[ $_a -eq $5 ]] && _green "$1" || _red "$1" "exit=$5" "exit=$_a"
}
_test_map "T1: 200 success" 0 200 1 0
_test_map "T2: 201 created" 0 201 1 0
_test_map "T3: 404 not found" 0 404 1 3
_test_map "T4: 500 server error" 0 500 1 3
_test_map "T5: DNS failure rc=6" 6 0 0 4
_test_map "T6: connect refused rc=7" 7 0 0 4
_test_map "T7: timeout with data" 28 0 1 2
_test_map "T8: timeout no data" 28 0 0 1
_test_map "T9: TLS error rc=35" 35 0 0 5
_test_map "T10: TLS cert rc=60" 60 0 0 5
_test_map "T11: generic error rc=1" 1 0 0 6
_test_map "T12: unknown rc=99" 99 0 0 6

# T13-T23 _sse_parse_line
_sse_event=""; _sse_data=""; _sse_id=""; _sse_retry=""; _sse_got_data=0
_sse_cb() { _sse_got_data=1; }
_callback="_sse_cb"

_sse_event="" _sse_data="" _sse_got_data=0
_sse_parse_line "data: hello"
[[ "$_sse_data" == "hello"$'\n' ]] && _green "T13: data line stored" || _red "T13: data" "hello\\n" "$_sse_data"

_sse_parse_line "data: world"
[[ "$_sse_data" == "hello"$'\n'"world"$'\n' ]] && _green "T14: multi-line" || _red "T14: multi" "hello\\nworld\\n" "$_sse_data"

_sse_got_data=0
_sse_parse_line ""
[[ $_sse_got_data -eq 1 && -z "$_sse_data" ]] && _green "T15: empty triggers" || _red "T15: empty" "got=1" "got=$_sse_got_data"

_sse_event="" _sse_data="" _sse_got_data=0
_sse_parse_line "event: update"
[[ "$_sse_event" == "update" ]] && _green "T16: event parsed" || _red "T16: event" "update" "$_sse_event"

_sse_id="" _sse_retry=""
_sse_parse_line "id: 42"; _sse_parse_line "retry: 3000"
[[ "$_sse_id" == "42" && "$_sse_retry" == "3000" ]] && _green "T17: id+retry" || _red "T17: id+retry" "42/3000" "$_sse_id/$_sse_retry"

_sse_event="" _sse_data="" _sse_got_data=0
_sse_parse_line ": comment"
[[ -z "$_sse_data" && -z "$_sse_event" ]] && _green "T18: comment ignored" || _red "T18: comment" "empty" "data=$_sse_data"

_sse_event="" _sse_data="trailing"$'\n' _sse_got_data=0 _callback="_sse_cb"
_sse_parse_line ""
[[ $_sse_got_data -eq 1 ]] && _green "T19: trailing nl" || _red "T19: trail" "got=1" "got=$_sse_got_data"

_sse_event="" _sse_data="" _sse_got_data=0 _callback="_sse_cb"
_sse_parse_line "event: done"; _sse_parse_line "data: {\"ok\":true}"; _sse_parse_line ""
[[ $_sse_got_data -eq 1 ]] && _green "T20: full SSE" || _red "T20: SSE" "got=1" "got=$_sse_got_data"

_sse_event="" _sse_data="" _sse_got_data=0
_sse_parse_line "data: hello"
[[ "$_sse_data" == "hello"$'\n' ]] && _green "T21: single space" || _red "T21: sp" "hello\\n" "$_sse_data"

_sse_event=""
_sse_parse_line "event: update"
[[ "$_sse_event" == "update" ]] && _green "T22: event space" || _red "T22: evsp" "update" "$_sse_event"

_sse_event="" _sse_data="" _sse_got_data=0
_sse_parse_line "data:  hello"
[[ "$_sse_data" == " hello"$'\n' ]] && _green "T23: double space" || _red "T23: dblsp" "' hello'\\n" "$_sse_data"

# T24-T37 http_request via spy
_spy_reset; _hreq "GET" "http://example.com/api" /tmp/test_http_out
_spy_has "METHOD:GET" && _spy_has "FLAG:L" && _green "T24: GET + -L" || _red "T24: GET+L" "METHOD:GET FLAG:L" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; _hreq "POST" "http://example.com/api" /tmp/test_http_out --body "hello world"
grep -q "BODY:@/tmp/bashagt_body" "$_SPY_FILE" && _green "T25: POST + body" || _red "T25: POST+body" "BODY:@..." "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; _hreq "GET" "http://example.com" /tmp/test_http_out --connect-timeout 15
_spy_has "CT:15" && _green "T26: connect-timeout=15" || _red "T26: CT" "CT:15" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; _hreq "GET" "http://example.com" /tmp/test_http_out --max-time 30
_spy_has "MT:30" && _green "T27: max-time=30" || _red "T27: MT" "MT:30" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; _hreq "GET" "http://example.com" /tmp/test_http_out --no-redirect
_spy_has "FLAG:L" && _red "T28: no-redirect" "no -L" "has -L" || _green "T28: no-redirect omits -L"

_spy_reset; _hreq "GET" "http://example.com" /tmp/test_http_out --header "X-Custom: val"
_spy_has "HDR:X-Custom: val" && _green "T29: custom header" || _red "T29: HDR" "HDR:X-Custom: val" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; _hreq "GET" "http://example.com" /tmp/test_http_out --auth-header "Authorization" --auth-value "Bearer tok"
_spy_has "HDR:Authorization: Bearer tok" && _green "T30: auth header" || _red "T30: auth" "HDR:Auth: Bearer tok" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; _hreq "GET" "http://example.com/search" /tmp/test_http_out --query-param "q" "hello world"
grep -q "URL:.*q=hello%20world" "$_SPY_FILE" && _green "T31: query param" || _red "T31: query" "q=hello%20world" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; _hreq "GET" "http://example.com/search" /tmp/test_http_out --query-param "a" "1" --query-param "b" "2"
grep -q "URL:.*a=1&b=2" "$_SPY_FILE" && _green "T32: multi query" || _red "T32: multiq" "a=1&b=2" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset; BASHAGT_PROXY_URL="http://proxy:8080"
_hreq "GET" "http://example.com" /tmp/test_http_out
BASHAGT_PROXY_URL=""
_spy_has "PROXY:http://proxy:8080" && _green "T33: proxy URL" || _red "T33: proxy" "PROXY:http://proxy:8080" "$(tr '\n' ' ' < $_SPY_FILE)"

# T34-T35 http_get/http_post delegation
_spy_reset
( set +e; http_get "http://example.com" /tmp/test_http_out >/dev/null 2>&1 ); set +e
_spy_has "METHOD:GET" && _green "T34: http_get=GET" || _red "T34: http_get" "METHOD:GET" "$(tr '\n' ' ' < $_SPY_FILE)"

_spy_reset
( set +e; http_post "http://example.com" /tmp/test_http_out >/dev/null 2>&1 ); set +e
_spy_has "METHOD:POST" && _green "T35: http_post=POST" || _red "T35: http_post" "METHOD:POST" "$(tr '\n' ' ' < $_SPY_FILE)"

# T36: curl error mapping
_spy_reset
CURL_MOCK_RC=7; CURL_MOCK_STATUS="0|0|0"
set +e; _hreq "GET" "http://example.com" /tmp/test_http_out; _rc=$?; set +e
CURL_MOCK_RC=0; CURL_MOCK_STATUS="200|0.1|10"
[[ $_rc -eq 4 ]] && _green "T36: curl rc=7→exit 4" || _red "T36: rcmap" "exit=4" "exit=$_rc"

# T37: empty body → no -d
_spy_reset; _hreq "POST" "http://example.com" /tmp/test_http_out
grep -q "BODY:" "$_SPY_FILE" && _red "T37: empty body" "no BODY" "has BODY" || _green "T37: no body = no -d"

# Stress
_sse_event="" _sse_data="" _sse_got_data=0 _callback="_sse_s_cb" _sse_count=0
_sse_s_cb() { _sse_count=$((_sse_count + 1)); }
for i in $(seq 1 100); do _sse_parse_line "data: event $i"; _sse_parse_line ""; done
[[ $_sse_count -eq 100 ]] && _green "S1: 100 SSE events" || _red "S1: 100 SSE" "100" "$_sse_count"

CURL_MOCK_RC=0; CURL_MOCK_STATUS="200|0|5"; _s_ok=1
set +e; for i in $(seq 1 50); do _hreq "GET" "http://example.com/$i" /tmp/test_http_stress || { _s_ok=0; break; }; done; set +e
[[ $_s_ok -eq 1 ]] && _green "S2: 50 rapid requests" || _red "S2: 50 rapid" "OK" "fail at $i"

echo "---DONE---"
TESTEOF

# ── Execute and parse ──
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
        PASS:*) _pass "${line#PASS:}" ;;
        FAIL:*) _fail "${line#FAIL:}" "$(echo "$line" | cut -d'|' -f2)" "$(echo "$line" | cut -d'|' -f3)" ;;
        ---DONE---) ;;
        *) echo "  $line" ;;
    esac
done < <(bash /tmp/bashagt_http_test.sh 2>&1 || true)

rm -f /tmp/bashagt_http_funcs.sh /tmp/bashagt_http_test.sh /tmp/test_http_out /tmp/test_http_stress /tmp/bashagt_spy_*.txt

echo ""
echo "============================================"
echo " HTTP Client Results: $PASS passed, $FAIL failed"
echo "============================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
