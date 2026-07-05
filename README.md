# ghul-mcp

MCP (Model Context Protocol) server for the [ghūl programming
language](https://ghul.dev). It drives the ghūl compiler's analysis mode to
answer semantic queries — diagnostics, hover, definition, references, symbol
search — so AI coding agents can query ghūl code by meaning instead of
searching it as text.

Written in ghūl, consuming the `ghul.analysis.protocol` client library.

## Status

Working. Multi-project routing: every semantic tool takes an optional
`project` argument (absolute path to a ghūl project directory). Absent
uses the server's `--default-project`. The server keeps a pool of analyser
sessions (up to 8) keyed by canonical path and reaps least-recently-used
entries above the cap, so multiple git worktrees under one Claude session
can each stay warm.

Tools:

- Position-based: `diagnostics`, `hover`, `definition`, `references`,
  `implementations`.
- Name-based: `symbols` (substring search), `hover_of`, `definition_of`,
  `references_of`, `implementations_of` (resolve a name and return the
  answer, or the candidate list when a name is shared).
- Type-based: `members` (list the members of a type expression - works for
  ghūl-declared and imported types including `System.*`).

All lines and columns are 1-based, matching compiler diagnostics.

The server drives the target project's own pinned `ghul.compiler` tool in
analysis mode, seeds it with the project's assembly references and source
contents, and re-sends any file whose on-disk timestamp moved before
answering each query - results always reflect what is on disk.

## Install as a .NET tool

Published as `ghul.mcp` on NuGet. Add it to any project's local tool
manifest:

```sh
dotnet new tool-manifest      # if the project has no .config/dotnet-tools.json yet
dotnet tool install --local ghul.mcp
```

## Usage

Point the server at a ghūl project directory (its dotnet tools must be
restored; the assemblies list is generated automatically on first use):

```sh
dotnet ghul-mcp --default-project path/to/project
```

Registering with Claude Code:

```sh
claude mcp add ghul -- dotnet ghul-mcp --default-project <project-dir>
```

## Build and test

```sh
dotnet tool restore
./tests/smoke.sh
```
