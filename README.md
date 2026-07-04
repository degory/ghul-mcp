# ghul-mcp

MCP (Model Context Protocol) server for the [ghūl programming
language](https://ghul.dev). It drives the ghūl compiler's analysis mode to
answer semantic queries — diagnostics, hover, definition, references, symbol
search — so AI coding agents can query ghūl code by meaning instead of
searching it as text.

Written in ghūl, consuming the `ghul.analysis.protocol` client library.

## Status

Working. Tools: `diagnostics`, `hover`, `definition`, `references`,
`implementations`, `symbols` (workspace-wide substring search), `version`.
All lines and columns are 1-based, matching compiler diagnostics.

The server drives the target project's own pinned `ghul.compiler` tool in
analysis mode, seeds it with the project's assembly references and source
contents, and re-sends any file whose on-disk timestamp moved before
answering each query - results always reflect what is on disk.

## Usage

Point the server at a ghūl project directory (its dotnet tools must be
restored; the assemblies list is generated automatically on first use):

```sh
dotnet ghul-mcp.dll --project path/to/project
```

Registering with Claude Code:

```sh
claude mcp add ghul -- dotnet <path>/ghul-mcp.dll --project <project-dir>
```

## Build and test

```sh
dotnet tool restore
./tests/smoke.sh
```
