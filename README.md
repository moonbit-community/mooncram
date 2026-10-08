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

Only backtick fences whose language is exactly `mooncram` are tests. Other
languages, tilde fences, and fences inside larger example fences are ignored.
Tests inside block quotes and lists are supported. Empty or unclosed test fences
are errors.

Each `$ ` line starts a case. The command must name an existing local `.mbtx`
file or a directory containing an executable MoonBit package (`is-main: true`).
Local packages are built with `moon run --build-only` and their artifact is run
with `moonrun` for Wasm or directly for native. Build diagnostics are kept out of
program output. Scripts are first checked with a build-only invocation, then
launched with `moonx`, so a compiler failure cannot become an expected program
exit status. `.mbtx` uses Wasm regardless of `--target`.

All relative command and stdin paths, and the program's working directory, are
relative to the Markdown file's directory (the canonical file for symlinks).
Arguments use single/double quotes and backslash escaping. Single quotes are
literal; outside them a backslash quotes the next character. Quoted empty
arguments are preserved. There is no variable, glob, tilde, or command
substitution. Unquoted `|`, `&`, `;`, `<`, `>`, backticks, and parentheses are
errors. Quote or escape these characters to pass them as ordinary arguments.

````markdown
```mooncram
$ ./hello.mbtx 'Moon Bit'
Hello, Moon Bit!

$ ./cmd/main --version
my-cli * (glob)
```
````

Lines after a command describe its output. By default each line must match
exactly, including trailing spaces. A final `[N]` sets the expected exit code;
otherwise it is `0`. Negative statuses denote termination by a signal as
reported by the process library. No expected output lines means the selected
stream must be empty.

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

## Block configuration

An optional JSON object after `mooncram` applies to every case in that block:

````markdown
```mooncram {"stream":"stderr","stdin":"./input.txt","env":{"MODE":"test"}}
$ ./cmd/main --invalid
unknown option: --invalid
[2]
```
````

| Field | Values/default |
| --- | --- |
| `stream` | `stdout` (default), `stderr`, or `merged` |
| `stdin` | File path; default is immediate EOF; reopened for each case |
| `env` | String-to-string mapping, overriding inherited environment variables |
| `target` | `wasm` or `native` for local packages; overrides CLI target (default `wasm`) |
| `timeout_ms` | Positive 32-bit integer; overrides CLI timeout (default `60000` ms) |

Unknown fields and wrong value types are errors. Both output streams are read
concurrently. `merged` connects stdout and stderr to one pipe, preserving pipe
write order (program buffering still applies). For separate streams, the other
stream is shown as diagnostic output on assertion failure.

The deadline includes builds and execution. On timeout the directly managed
process is cancelled and the case is an execution error. Programs must manage
their own detached child processes. Tests execute local code with the current
user's permissions and are not sandboxed or isolated in a temporary workspace.

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