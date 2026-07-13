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

- Whole-project: `diagnostics` (errors and warnings). A large result comes
  back as a summary - counts by severity, a by-code and top-files
  breakdown, every error in full - which you narrow with `file`,
  `severity`, `code`, or `exclude_codes`.
- File-scoped: `inlays` (the narrowing / flow annotations the editor shows
  inline for one file - where a value is narrowed and where a narrowing is
  killed); optional `code` filter.
- Position-based: `hover`, `definition`, `references`, `implementations`.
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

## Query log

The server appends one JSON line per `tools/call` dispatch to a query log:
timestamp, pid, tool name, raw arguments, status (`ok`, `error`,
`unknown-tool`, `invalid-request`), elapsed milliseconds, result size, and
the first 300 characters of the result text. Analyser failures - spawn
failures, timeouts, restart loops - surface as `error` entries carrying the
exception message, so the log answers "is this server actually working
reliably, and are its answers useful?" after the fact.

The log defaults to `$XDG_STATE_HOME/ghul-mcp/query-log.jsonl` (falling
back to `~/.local/state/ghul-mcp/query-log.jsonl`), shared by every server
instance - entries carry the pid to tell sessions apart. `--query-log
<path>` redirects it; `--no-query-log` disables it. At startup a log past
10 MB is rotated to `<path>.prev`. A logging failure never breaks the
server: it disables the log for the rest of the run and reports once on
stderr.

## Build and test

```sh
dotnet tool restore
./tests/smoke.sh
```
