#!/usr/bin/env bash
# End-to-end smoke test: drive the built server over stdio with one request
# per MCP method the scaffold supports, and check each response.
set -euo pipefail

cd "$(dirname "$0")/.."

dotnet build -nologo

out=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"ping"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"version","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"no-such-tool"}}' \
    '{"jsonrpc":"2.0","id":6,"method":"no/such/method"}' \
    | dotnet bin/Debug/net10.0/ghul-mcp.dll)

echo "$out"

fail() { echo "FAIL: $1" >&2; exit 1; }

count=$(echo "$out" | wc -l)
[ "$count" -eq 6 ] || fail "expected 6 responses (notification must not get one), got $count"

echo "$out" | sed -n 1p | grep -q '"protocolVersion":"2025-06-18"' || fail "initialize: protocolVersion"
echo "$out" | sed -n 1p | grep -q '"serverInfo":{"name":"ghul-mcp"' || fail "initialize: serverInfo"
echo "$out" | sed -n 2p | grep -q '"id":2,"result":{}' || fail "ping: empty result"
echo "$out" | sed -n 3p | grep -q '"tools":\[{"name":"version"' || fail "tools/list: version tool"
echo "$out" | sed -n 3p | grep -q '"inputSchema":{"type":"object"' || fail "tools/list: inputSchema"
echo "$out" | sed -n 4p | grep -q '"text":"ghul-mcp 0.1.0"' || fail "tools/call: version text"
echo "$out" | sed -n 4p | grep -q '"isError":false' || fail "tools/call: isError false"
echo "$out" | sed -n 5p | grep -q '"error":{"code":-32602,"message":"unknown tool: no-such-tool"}' || fail "tools/call: unknown tool error"
echo "$out" | sed -n 6p | grep -q '"error":{"code":-32601' || fail "unknown method error"

echo "smoke test passed"
