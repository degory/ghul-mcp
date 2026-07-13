# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

An MCP (Model Context Protocol) server for the ghūl language, written in
ghūl. It speaks JSON-RPC 2.0 over stdio (one JSON object per line) and will
expose semantic queries about ghūl projects — diagnostics, hover, definition,
references, symbol search — by driving `ghul-compiler --analyse` through the
`ghul.analysis.protocol` client library.

## Layout

- `src/main.ghul` — entry point: parses `--project`, wires streams,
  registers tools, runs the server loop.
- `src/mcp/` — MCP protocol core: `wire.ghul` (JSON-RPC envelope, framing,
  serializer options), `server.ghul` (method dispatch and result DTOs),
  `tools.ghul` (the tool abstraction), `query_log.ghul` (the JSONL
  dispatch log every tools/call is recorded to - see README).
- `src/analyser/` — the semantic layer: `session.ghul` (spawns the target
  project's pinned compiler in analysis mode, seeds and freshens sources,
  speaks the `ghul.analysis.protocol` wire), `tools.ghul` (maps MCP tool
  calls onto analyser queries and renders responses as text).
- `tests/smoke.sh` — end-to-end test driving the built server over stdio,
  including analyser tools against a scratch project copy with a
  mid-session file edit; this is what CI runs.

## Build and test

```sh
dotnet tool restore     # once after clone
dotnet build
./tests/smoke.sh        # build + drive the server end-to-end
```

## Conventions

- Wire names are camelCase (MCP requirement); ghūl members stay snake_case.
  The bridge is the `SNAKE_TO_CAMEL_POLICY` naming policy in `wire.ghul` —
  never hand-rename a member to camelCase to influence the wire format.
- stdout carries protocol JSON only; anything human-readable goes to stderr.
- Responses serialize public fields via properties; keep DTO fields public
  and let the naming policy handle the rest. Don't enable `include_fields`
  on the serializer options: ghūl emits a property plus a `$`-prefixed
  backing field per declared field, so field serialization writes every
  value twice.
- Tool input schemas are JSON literals parsed at construction, not DTO
  trees.
