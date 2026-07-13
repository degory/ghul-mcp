#!/usr/bin/env bash
# End-to-end smoke test in two parts: the MCP protocol core driven with one
# request per method, then the analyser tools driven against a scratch copy
# of this project - including a mid-session file edit to prove queries see
# what is on disk.
set -euo pipefail

cd "$(dirname "$0")/.."

dotnet build -nologo

server=bin/Debug/net10.0/ghul-mcp.dll

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- part 1: protocol core ----------------------------------------------

qlog_tmp=$(mktemp -d)
qlog="$qlog_tmp/query-log.jsonl"

out=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"ping"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"version","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"no-such-tool"}}' \
    '{"jsonrpc":"2.0","id":6,"method":"no/such/method"}' \
    | dotnet "$server" --query-log "$qlog")

echo "$out"

count=$(echo "$out" | wc -l)
[ "$count" -eq 6 ] || fail "expected 6 responses (notification must not get one), got $count"

echo "$out" | sed -n 1p | grep -q '"protocolVersion":"2025-06-18"' || fail "initialize: protocolVersion"
echo "$out" | sed -n 1p | grep -q '"serverInfo":{"name":"ghul-mcp"' || fail "initialize: serverInfo"
echo "$out" | sed -n 2p | grep -q '"id":2,"result":{}' || fail "ping: empty result"
echo "$out" | sed -n 3p | grep -q '"tools":\[{"name":"version"' || fail "tools/list: version tool first"
echo "$out" | sed -n 3p | grep -q '"name":"diagnostics"' || fail "tools/list: diagnostics tool"
echo "$out" | sed -n 3p | grep -q '"name":"symbols"' || fail "tools/list: symbols tool"
echo "$out" | sed -n 4p | grep -q '"text":"ghul-mcp 0.8.0"' || fail "tools/call: version text"
echo "$out" | sed -n 4p | grep -q '"isError":false' || fail "tools/call: isError false"
echo "$out" | sed -n 5p | grep -q '"error":{"code":-32602,"message":"unknown tool: no-such-tool"}' || fail "unknown tool error"
echo "$out" | sed -n 6p | grep -q '"error":{"code":-32601' || fail "unknown method error"

# Every tools/call dispatch lands in the query log with a status.
[ -f "$qlog" ] || fail "query log: file not written"
grep -q '"event":"start"' "$qlog" || fail "query log: start entry"
grep -q '"tool":"version"' "$qlog" || fail "query log: version call entry"
grep -q '"status":"ok"' "$qlog" || fail "query log: ok status"
grep -q '"status":"unknown-tool"' "$qlog" || fail "query log: unknown-tool status"
qlog_calls=$(grep -c '"event":"call"' "$qlog")
[ "$qlog_calls" -eq 2 ] || fail "query log: expected 2 call entries, got $qlog_calls"

rm -rf "$qlog_tmp"

# --- part 2: analyser tools ---------------------------------------------

tmp=$(mktemp -d)
fifo="$tmp/requests"
responses="$tmp/responses"

cleanup() {
    exec 3>&- 2>/dev/null || true
    [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmp"
}
trap cleanup EXIT

cp -r src ghul-mcp.ghulproj .config "$tmp/"
(cd "$tmp" && dotnet tool restore >/dev/null)
cp "$tmp/src/main.ghul" "$tmp/main.pristine"

mkfifo "$fifo"
dotnet "$server" --default-project "$tmp" --query-log "$tmp/query-log.jsonl" <"$fifo" >"$responses" &
server_pid=$!
exec 3>"$fifo"

send() { echo "$1" >&3; }

await() {
    for _ in $(seq 1 240); do
        grep -q "\"id\":$1," "$responses" 2>/dev/null && return 0
        sleep 1
    done
    echo "--- responses so far ---" >&2
    cat "$responses" >&2 || true
    fail "timed out waiting for response id $1"
}

response() { grep "\"id\":$1," "$responses"; }

send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
await 1

send '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"diagnostics","arguments":{}}}'
await 2
response 2 | grep -q '"text":"no errors or warnings"' || fail "diagnostics: expected clean project"

# Break a source on disk mid-session: the next query must see it.
echo "this is not ghul" >> "$tmp/src/main.ghul"

send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"diagnostics","arguments":{}}}'
await 3
response 3 | grep -q 'main.ghul' || fail "diagnostics after edit: expected an error in main.ghul"
response 3 | grep -q 'error' || fail "diagnostics after edit: expected severity error"

# Repair it: the next query must go clean again.
cp "$tmp/main.pristine" "$tmp/src/main.ghul"

send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"diagnostics","arguments":{}}}'
await 4
response 4 | grep -q '"text":"no errors or warnings"' || fail "diagnostics after repair: expected clean again"

line=$(grep -n "class ANALYSER_SESSION" src/analyser/session.ghul | head -1 | cut -d: -f1)
send '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"hover","arguments":{"file":"src/analyser/session.ghul","line":'"$line"',"column":11}}}'
await 5
response 5 | grep -q 'ANALYSER_SESSION' || fail "hover: expected the class signature"

send '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"symbols","arguments":{"query":"ensure_fresh"}}}'
await 6
response 6 | grep -q 'session.ghul' || fail "symbols: expected a match in session.ghul"

send '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"hover_of","arguments":{"name":"ANALYSER_SESSION"}}}'
await 7
response 7 | grep -q 'ANALYSER_SESSION' || fail "hover_of: expected class signature"
response 7 | grep -q '"isError":false' || fail "hover_of: unexpected error"

send '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"references_of","arguments":{"name":"ANALYSER_SESSION"}}}'
await 8
response 8 | grep -q 'tools.ghul' || fail "references_of: expected uses in tools.ghul"

send '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"hover_of","arguments":{"name":"init"}}}'
await 9
response 9 | grep -q 'share the name init' || fail "hover_of ambiguous: expected candidate list"

send '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"hover_of","arguments":{"name":"no_such_symbol_xyz"}}}'
await 10
response 10 | grep -q 'no symbol named' || fail "hover_of unknown: expected miss message"

send '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"members","arguments":{"type":"System.Text.StringBuilder"}}}'
await 11
response 11 | grep -q 'append' || fail "members(StringBuilder): expected append in members"
response 11 | grep -q 'length' || fail "members(StringBuilder): expected length property"

# --- part 3: multi-project routing ----------------------------------------
# Spawn a second scratch project alongside the first and verify a query with
# an explicit `project` argument spawns a separate analyser session, while
# no-arg queries continue to use the default.

tmp2=$(mktemp -d)
trap 'exec 3>&- 2>/dev/null || true; [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null || true; rm -rf "$tmp" "$tmp2"' EXIT

cp -r src ghul-mcp.ghulproj .config "$tmp2/"
(cd "$tmp2" && dotnet tool restore >/dev/null)

send '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"sessions","arguments":{}}}'
await 20
response 20 | grep -q "$tmp" || fail "sessions: expected default project warm after diagnostics"
response 20 | grep -q "$tmp2" && fail "sessions: second project should NOT be warm yet"

send "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"tools/call\",\"params\":{\"name\":\"diagnostics\",\"arguments\":{\"project\":\"$tmp2\"}}}"
await 21
response 21 | grep -q '"text":"no errors or warnings"' || fail "diagnostics: expected clean second project"

send '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"sessions","arguments":{}}}'
await 22
response 22 | grep -q "$tmp" || fail "sessions after 2nd project: default still warm"
response 22 | grep -q "$tmp2" || fail "sessions after 2nd project: second project should now be warm"

# Break a file in project 2 and verify only that project's diagnostics
# report it — the pool must not have crossed sources between sessions.
echo "this is not ghul" >> "$tmp2/src/main.ghul"

send '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"diagnostics","arguments":{}}}'
await 23
response 23 | grep -q '"text":"no errors or warnings"' || fail "default diagnostics after 2nd broken: still clean"

send "{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"tools/call\",\"params\":{\"name\":\"diagnostics\",\"arguments\":{\"project\":\"$tmp2\"}}}"
await 24
response 24 | grep -q 'main.ghul' || fail "2nd diagnostics: expected broken main.ghul"

# --- part 4: inlays -----------------------------------------------------
# The narrowing / flow information the editor shows inline is surfaced by the
# file-scoped `inlays` tool. The fixture narrows a local under a presence
# test and then reassigns it, killing the narrowing - a narrowing-presence
# inlay followed by a narrowing-killed one.

hints_dir=$(mktemp -d)
trap 'exec 3>&- 2>/dev/null || true; [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null || true; rm -rf "$tmp" "$tmp2" "$hints_dir"' EXIT

mkdir -p "$hints_dir/src"
cat > "$hints_dir/src/test.ghul" <<'EOF'
class WIDGET is
    init() is si
    make() -> WIDGET? => WIDGET();
    run() is
        let w mut = make();
        if w? then
            w = make();
        fi
    si
si

entry() is
    WIDGET().run();
si
EOF
cp ghul-mcp.ghulproj "$hints_dir/hints-test.ghulproj"
cp -r .config "$hints_dir/"
(cd "$hints_dir" && dotnet tool restore >/dev/null)

# baseline: the project compiles clean (inlays are not diagnostics)
send "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"tools/call\",\"params\":{\"name\":\"diagnostics\",\"arguments\":{\"project\":\"$hints_dir\"}}}"
await 30
response 30 | grep -q '"text":"no errors or warnings"' || fail "inlays: baseline diagnostics should be clean"

# the inlays tool surfaces both narrowing sites for the file
send "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"tools/call\",\"params\":{\"name\":\"inlays\",\"arguments\":{\"project\":\"$hints_dir\",\"file\":\"src/test.ghul\"}}}"
await 31
response 31 | grep -q 'narrowing-presence' || fail "inlays: expected a narrowing-presence inlay"
response 31 | grep -q 'narrowing-killed' || fail "inlays: expected a narrowing-killed inlay"
response 31 | grep -q 'reassigned' || fail "inlays: expected the reassignment detail"

# a code filter narrows to one family
send "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"tools/call\",\"params\":{\"name\":\"inlays\",\"arguments\":{\"project\":\"$hints_dir\",\"file\":\"src/test.ghul\",\"code\":\"narrowing-killed\"}}}"
await 32
response 32 | grep -q 'narrowing-killed' || fail "inlays: code filter should keep the matching family"
response 32 | grep -q 'narrowing-presence' && fail "inlays: code filter should drop other families"

# a code filter matching nothing returns a clean miss
send "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"tools/call\",\"params\":{\"name\":\"inlays\",\"arguments\":{\"project\":\"$hints_dir\",\"file\":\"src/test.ghul\",\"code\":\"no-such-code\"}}}"
await 33
response 33 | grep -q 'no inlays in src/test.ghul match' || fail "inlays: expected miss message for an unmatched code"

# --- part 5: pool operations --------------------------------------------
# Verify the pool exposes per-session detail, that heap_check returns
# ok on a fresh session, and that release_session tears one down.

send '{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"sessions","arguments":{}}}'
await 40
response 40 | grep -q "pid " || fail "sessions: expected a pid in the listing"
response 40 | grep -q "sources" || fail "sessions: expected a source count in the listing"

send "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"tools/call\",\"params\":{\"name\":\"heap_check\",\"arguments\":{\"project\":\"$tmp\"}}}"
await 41
response 41 | grep -q "heap check ok" || fail "heap_check: expected ok on a fresh session"

send "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"tools/call\",\"params\":{\"name\":\"release_session\",\"arguments\":{\"project\":\"$tmp\"}}}"
await 42
response 42 | grep -q "released session for" || fail "release_session: expected release confirmation"

send "{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"tools/call\",\"params\":{\"name\":\"release_session\",\"arguments\":{\"project\":\"$tmp\"}}}"
await 43
response 43 | grep -q "no warm session" || fail "release_session: expected miss after release"

exec 3>&-
wait "$server_pid" 2>/dev/null || true
server_pid=""

# The long-lived server logged every analyser dispatch, and none of the
# calls above should have surfaced as an error status.
qlog2="$tmp/query-log.jsonl"
[ -f "$qlog2" ] || fail "query log: long-lived server wrote no log"
grep -q '"tool":"diagnostics"' "$qlog2" || fail "query log: diagnostics entries"
grep -q '"tool":"hover"' "$qlog2" || fail "query log: hover entry"
grep -q '"tool":"inlays"' "$qlog2" || fail "query log: inlays entries"
grep -q '"status":"error"' "$qlog2" && fail "query log: unexpected error status"

echo "smoke test passed"
