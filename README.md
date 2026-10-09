# mooncram

A simple and powerful testing toolkit for MoonBit CLI applications and Script

## Quick start

From this checkout:

```text
moon run . -- test README.md
moon run . -- test examples
moon run . -- update examples --dry-run
```

This is an executable example using [examples/hello.mbtx](examples/hello.mbtx):

```mooncram
$ ./examples/hello.mbtx "Moon Bit"
Hello, Moon Bit!
```

## Commands

```text
mooncram test [paths...] [--target wasm|native] [--timeout-ms N]
mooncram update [paths...] [--target wasm|native] [--timeout-ms N] [--dry-run]
mooncram --help
mooncram --version
```

Both commands support `--color auto|always|never` (default `auto`). `NO_COLOR`
disables automatic color. Global options can appear before the subcommand or
after paths. Use `--` before a path that starts with `-`.

With no paths, scan the current directory. Directories are searched recursively
for `.md` files. Directory traversal skips names starting with `.` on every
platform, entries with the Windows hidden attribute, `_build`, and `target`.
Directory symlinks are never traversed. File symlinks are resolved and duplicate
files are run once. Files run in sorted canonical path order, and cases run in
document order. Commands share filesystem side effects and run serially.

Exit status:

| Status | Meaning |
| --- | --- |
| `0` | All assertions pass, or update/dry-run completes successfully |
| `1` | One or more assertions fail in `test` |
| `2` | Invalid arguments, parsing/build/execution errors, or no cases found |

## Test blocks

Only backtick fences whose info string is `mooncram` followed by optional
whitespace are tests. Any non-whitespace trailing text—including former JSON
configuration syntax—causes the whole fence to be silently ignored. Other
languages, tilde fences, and fences inside larger example fences are also
ignored. Tests inside block quotes and lists are supported. Empty or unclosed
recognized test fences are errors.

Each `$ ` line starts a command. Except for `export`, each command starts a case.
Each pipeline segment must name an existing local
`.mbtx` file or a directory containing an executable MoonBit package
(`is-main: true`).
Local packages are built with `moon run --build-only` and their artifact is run
with `moonrun` for Wasm or directly for native. Build diagnostics are kept out of
program output. Scripts are first checked with a build-only invocation, then
launched with `moonx`, so a compiler failure cannot become an expected program
exit status. `.mbtx` uses Wasm regardless of `--target`.

All relative command paths and the program's working directory are relative to
the Markdown file's directory (the canonical file for symlinks).
Arguments use single/double quotes and backslash escaping. Single quotes are
literal; outside them a backslash quotes the next character. Quoted empty
arguments are preserved. `${NAME}` expands in unquoted or double-quoted
arguments; single quotes and escaped dollar signs preserve it literally. `$NAME`
is literal. There is no glob or tilde expansion or command substitution.
Unquoted, unescaped `|` separates pipeline segments, with or
without surrounding spaces. Empty segments (including `||`) are errors.
Unquoted `&`, `;`, `<`, `>`, backticks, and parentheses are errors, except for
the exact trailing redirection markers below. Quote or escape these characters
to pass them as ordinary arguments.

Any segment, including a single command, can end with `2>&1` to merge
stderr into its output pipe, or `>/dev/null` to discard its original stdout.
Combining both markers in either order discards original stdout and sends only
stderr to the next segment or final capture. Each marker must be separated from
the preceding command, argument or marker by a space or tab; it contains no
internal whitespace and may touch the following `|`. Each kind may occur once,
and ordinary arguments cannot follow a marker. Fully quoted markers, correctly
escaped markers, and marker text produced by variable expansion remain ordinary
arguments. To pass literal `2>&1`, quote it or use `2\>\&1` to escape both special
characters; literal `>/dev/null` can use `\>/dev/null`. The old `stdout>/null` and
`stderr>/stdout` syntax, other redirection forms, and redirection on `export` are
parsing errors with file and line numbers.

`$ export NAME=value` sets one variable for subsequent commands in the same
Markdown document, including later test blocks. Names must match
`[A-Za-z_][A-Za-z0-9_]*`; values may be empty or contain additional `=` characters.
Assignments can use `${NAME}` with the same quoting rules as arguments. Lookup
uses earlier exports first, then the parent environment; self-reference reads the
previous value, and an exported empty string overrides the parent value.
On Windows, variable names are case-insensitive: exports and lookup keys use
ASCII uppercase, so assigning `Name` and then `NAME` replaces one variable.
On Linux and macOS, variable names remain case-sensitive.
Expansion happens once, without splitting: spaces, quotes and `|` in a value stay
inside the original argument, and an empty result remains an argument.

The first word of every pipeline segment is an executable path and cannot contain
an expandable `${NAME}`. File paths passed as ordinary arguments can expand.
Undefined variables, invalid or unclosed references, invalid assignments, and
`export` in a pipeline are parsing errors with file and line numbers. Exports
have no expected output or exit code and do not count as cases. Export-only
blocks are valid; a run with no actual cases still reports an error. Exports
reset for each document. The entire document is parsed before any case runs.

````markdown
```mooncram
$ export NAME='Moon Bit'
$ ./hello.mbtx "${NAME}"
Hello, Moon Bit!

$ ./cmd/main --version
my-cli * (glob)

$ ./producer.mbtx|./cmd/filter|./consumer.mbtx
filtered output
```
````

Lines after a command describe its output. By default each line must match
exactly, including trailing spaces. A final `[N]` sets the expected exit code;
otherwise it is `0`. Pipelines match the final segment's routed output and exit
code; upstream nonzero statuses do not override the final status. Negative statuses
denote termination by a signal as reported by the process library. No expected
output lines means the routed output must be empty.

Bare empty lines at the beginning/end of a block or immediately before the next
command are separators. Empty lines between nonempty expectations are output.
Use ` (equal)` or `"" (escaped)` for an explicit empty output line, especially at
the end of output. Thus empty output and a single newline remain distinct.

## Matching and escaping

| Suffix | Meaning |
| --- | --- |
| none or ` (equal)` | Exact line match |
| ` (glob)` | Whole-line glob: `*`, `?`, `[abc]`, `[a-z]`, `[!a-z]`, `[^a-z]`; backslash quotes a character |
| ` (regex)` | Whole-line standard-library `Regex` match |
| ` (escaped)` | Exact match of a JSON string, including control characters |
| ` (no-eol)` | The final output line has no terminating newline; follows any other suffix |

Glob `?` and sets match one Unicode character. Matching never repeats or skips
output lines. Unknown parenthesized suffixes such as `(foo)` or `(re)` are
literal text and match exactly. Malformed globs/regexes and non-final `(no-eol)`
are errors with file and line locations. To match output ending in a recognized
annotation literally, use `(equal)` or `(escaped)`.

`(escaped)` expects a complete JSON string. It can represent tabs, carriage
returns, NUL, ANSI escapes, and output that looks like a command, fence, status,
or matching suffix. It cannot contain LF: use separate expected output lines.

````markdown
```mooncram
$ ./special.mbtx
"$ this is output" (escaped)
"[2]" (escaped)
"```" (escaped)
"\u001b[31mred\u001b[0m" (escaped)
"" (escaped)
final text (no-eol)
[3]
```
````

Output must be valid UTF-8. CRLF is normalized to LF for comparisons; standalone
CR, empty lines, trailing spaces, and the final newline are preserved.

## Execution behavior

Block-level configuration is not supported. `--target` selects the backend for
all local package cases, and `--timeout-ms` supplies every case deadline;
`.mbtx` scripts still use Wasm. Build processes and every pipeline segment
inherit mooncram's environment with the case's document exports applied.
The first segment receives immediate EOF on stdin; later segments
receive the preceding segment's routed output as raw bytes.

Only the final routed output is compared with the expectation. Unredirected
stderr is drained concurrently and concatenated in segment order as
`diagnostic stderr` when an assertion fails. Merged stderr uses the same OS pipe
as routed stdout and is included in matching, without a second diagnostic copy.
Captured streams must be valid UTF-8 and have no configured size limit.
Intermediate pipe data is neither decoded nor normalized. Discarded stdout is
drained concurrently with a fixed 8 KiB byte buffer, without accumulation or
UTF-8 decoding; invalid bytes in discarded output are allowed. Build processes
always use the default routes.

All segments finish their build preflight before any tested program starts.
Segments then run concurrently, and mooncram waits for all of them to exit.
One deadline includes all builds and execution. On timeout or a startup/capture
error, all directly managed processes are cancelled and pipes are closed; the
case is an execution error. Programs must manage their own detached child
processes. Tests execute local code with the current user's permissions and are
not sandboxed or isolated in a temporary workspace.

## Updating expectations

`update` changes only failing expectations. Passing cases and still-matching
patterns keep their spelling. Commands, fence markers, container prefixes,
surrounding prose, and document line endings are preserved. Special output is
escaped automatically, including missing final newlines and nonzero statuses.

`--dry-run` runs the same commands and displays document diffs without writing
Markdown. Commands can still produce their normal filesystem side effects.
Both actual updates and dry runs return `0` when completed successfully, even
when changes are needed.

A document with parsing, build, or execution errors is never updated. Other
documents can still run and update. Before committing an update, mooncram checks
that the source content has not changed, then replaces it atomically using a
temporary file in the same directory. The replacement uses new-file permissions
(`0644`, subject to umask); original permissions, inode identity, and extended
filesystem metadata are not retained in this version.
