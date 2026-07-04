# ghul-mcp

MCP (Model Context Protocol) server for the [ghūl programming
language](https://ghul.dev). It drives the ghūl compiler's analysis mode to
answer semantic queries — diagnostics, hover, definition, references, symbol
search — so AI coding agents can query ghūl code by meaning instead of
searching it as text.

Written in ghūl, consuming the `ghul.analysis.protocol` client library.

## Status

The MCP core works: initialize, ping, tools/list and tools/call over stdio,
with a placeholder `version` tool. The analysis-mode tools are not wired up
yet.

## Build and test

```sh
dotnet tool restore
./tests/smoke.sh
```
