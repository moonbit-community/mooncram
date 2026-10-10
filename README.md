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

Only backtick fences with the case-sensitive language `mooncram` are tests.
The language can be followed by whitespace and one module name, such as
`mooncram user/foo`. A declaration applies only to its own fence. Multiple words,
JSON settings, and invalid module names are parsing errors at the opening line.
Other languages, tilde fences, and fences inside larger example fences are
ignored. Tests inside block quotes and lists are supported. Empty or unclosed
test fences are errors.

Each `$ ` line starts a command. Except for `export`, each command starts a case.
Plain `mooncram` fences support local `.mbtx` scripts and file import aliases.
Declared fences also support
executable packages in the module whose `moon.mod` is in mooncram's startup cwd.
Every declaration must exactly match that module's `name`; all declarations,
including export-only fences, are checked before any case in the document runs.
Local module declarations do not search parent directories or load registry modules.

Packages are resolved below the module's `source` directory (the module root if
`source` is omitted or empty). For `user/foo`, `foo` selects the executable root
package; `cmd/boo` selects `user/foo/cmd/boo`. If the root is not executable,
`foo` can select the executable subpackage `user/foo/foo`. Executability means
`pkgtype(kind: "executable")` or legacy `is-main: true`. If both candidates are
executable, the root wins and each ambiguous pipeline segment emits one
`WARNING` to mooncram's stderr, with the document position, both full package
names, and the selection. Warnings do not affect matching, updates, or error
counts. A selected package's build/target failure is an error without fallback.
Package names cannot be absolute paths, start with `./` or `../`, contain path
traversal, or enter nested modules. Package configurations use `moon.pkg`, with
`moon.pkg.json` supported for compatibility; invalid configurations are errors.

Local packages are built with `moon -C <module-root> run --build-only` and their
artifact runs with `moonrun` for Wasm or directly for native. Build diagnostics
are kept out of program output. Scripts are checked with a build-only invocation,
then launched with `moonx`. `.mbtx` always uses Wasm regardless of `--target`.
Script paths are relative to the Markdown directory and may also be absolute.
Every program runs in the Markdown file's directory (the canonical file for
symlinks), even when the module is elsewhere.
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

The first word of every pipeline segment selects an executable and cannot contain
an expandable `${NAME}`. File paths passed as ordinary arguments can expand.
Undefined variables, invalid or unclosed references, invalid assignments, and
`export` in a pipeline are parsing errors with file and line numbers. Exports
have no expected output or exit code and do not count as cases. Export-only
blocks are valid; a run with no actual cases still reports an error. Exports
reset for each document. The entire document is parsed before any case runs.

````markdown
```mooncram user/foo
$ export NAME='Moon Bit'
$ ./hello.mbtx "${NAME}"
Hello, Moon Bit!

$ cmd/main --version
my-cli * (glob)

$ ./producer.mbtx|cmd/filter|./consumer.mbtx
filtered output
```
````

Lines after a command describe its output. By default each line must match
exactly, including trailing spaces. A final `[N]` sets the expected exit code;
otherwise it is `0`. Pipelines match the final segment's routed output and use
pipefail by default: after every segment finishes, the exit code is `0` if all
succeeded, or the rightmost nonzero status in pipeline order otherwise,
regardless of completion order. Ordinary nonzero statuses can be asserted with
`[N]` and do not stop later cases.
Imported commands returning `255` or `-1` are execution errors in any segment. Negative statuses
denote termination by a signal as reported by the process library. No expected
output lines means the routed output must be empty.

Bare empty lines at the beginning/end of a block or immediately before the next
command are separators. Empty lines between nonempty expectations are output.
Use `"" (escaped)` for an explicit empty output line, especially at the end of
output. Thus empty output and a single newline remain distinct.

## Paired stdout and stderr assertions

Use `@STDOUT` and `@STDERR` to assert both streams in one execution:

````markdown
```mooncram
$ ./cli.mbtx
@STDOUT
result
@STDERR (empty)

$ ./cli.mbtx --invalid
@STDOUT (ignore)
@STDERR
error: invalid argument
[2]
```
````

Both case-sensitive markers must appear exactly once, in either order. A missing
partner, duplicate marker, nonempty expectation before the first marker, or
unknown marker annotation is a parse error with a file and line number.
Marker forms are exactly `@STDOUT` / `@STDERR`, optionally followed by
` (ignore)` or ` (empty)`. To match a marker-looking output line literally, use
JSON escaping, for example `"@STDOUT" (escaped)`.

A plain section uses the usual exact, glob, regex and escaped line matchers;
`(no-eol)` applies independently to the last line of each stream. A plain section
with no output lines requires empty output. `(ignore)` skips content assertions;
`(empty)` requires exactly zero characters, so even one newline fails. Neither
annotated form accepts output lines. Trailing bare empty lines in each section
are separators; use `"" (escaped)` to assert an empty output line. The final
`[N]` belongs to the whole case, with default exit code `0`.

`@STDOUT` selects the final segment's routed output. `@STDERR` selects all
unmerged stderr, concatenated in pipeline order without added separators.
Redirection still applies: merged or discarded bytes are not recovered.
There is no comparison of timing between streams. Ignored streams are still
captured and checked for UTF-8, with the same deadlines and process cleanup.
Cases without stream markers keep the existing single-output behavior.

## File tool imports

Declare fixed-version Mooncakes executable packages once per Markdown file:

````markdown
```mooncram-import
moongrep : moonbit-community/moongrep@0.3.5
```

```mooncram
$ moongrep --version
* (glob)
```
````

A file accepts zero or one `mooncram-import` block. Bindings apply to every test
block in that file, even before the import block, and reset for the next file.
Imports do not count as cases. Each nonblank line is `alias : coordinate`; empty
blocks, duplicate aliases, a second import block, and invalid declarations are
parsing errors with source positions. A second block reports both locations.
Import fences follow the same Markdown rules as test fences, including quotes,
lists and longer backtick fences, and accept no settings after the language.

Aliases are case-sensitive `[A-Za-z_][A-Za-z0-9_-]*`; `export` is reserved.
Coordinates are `user/module[/package]@version`, using the same path-component
rules as local package names. The version must be exact SemVer; prerelease and
build identifiers are supported. Omitted versions, `latest`, ranges, wildcards,
default arguments and variable expansion in declarations are rejected.

Each pipeline segment resolves its alias independently and runs
`moonx --target wasm <coordinate> -- <args...>`, preserving the parsed arguments,
cwd, exports and redirection. Imported tools always use Wasm, including under
`--target native`. In a module-declared fence, an alias matching an executable
local candidate is an execution error: choose a different import alias. Invalid
local configuration is also an error. Non-alias commands follow the local rules.
Remote packages can only be called through declared aliases.

Only imported commands reserve statuses `255` and `-1` as execution errors,
including when the imported program itself returns them. Every segment is
monitored concurrently; either status cancels and reaps the remaining processes
and prevents all expectation updates in the document, including dry-run diffs.
Other nonzero statuses remain assertable and follow the pipefail rule above.
Other documents continue processing after errors.

moonx handles remote downloading and caching. Remote fetching begins after
moonx starts, so other segments may run and produce effects before a fetch
failure is known. Fetching and execution share the case timeout. `test`,
`update` and `update --dry-run` use the same execution flow.

## Matching and escaping

| Suffix | Meaning |
| --- | --- |
| none | Exact line match |
| ` (glob)` | Whole-line glob: `*`, `?`, `[abc]`, `[a-z]`, `[!a-z]`, `[^a-z]`; backslash quotes a character |
| ` (regex)` | Whole-line standard-library `Regex` match |
| ` (escaped)` | Exact match of a JSON string, including control characters |
| ` (no-eol)` | The final output line has no terminating newline; follows any other suffix |

Glob `?` and sets match one Unicode character. Matching never repeats or skips
output lines. Unknown parenthesized suffixes such as `(equal)`, `(foo)`, or `(re)`
are literal text and match exactly. Malformed globs/regexes and non-final `(no-eol)`
are errors with file and line locations. To match output ending in a recognized
annotation literally, use a JSON string with `(escaped)`.

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

The fence suffix declares only the module; backend and timeout remain CLI
options. `--target` selects the backend for all local package cases, and `--timeout-ms` supplies every case deadline;
`.mbtx` scripts still use Wasm. Build processes and every pipeline segment
inherit mooncram's environment with the case's document exports applied.
The first segment receives immediate EOF on stdin; later segments
receive the preceding segment's routed output as raw bytes.

Unmarked cases compare the final routed output. Paired cases also compare
unmerged stderr with `@STDERR`. Unredirected stderr is drained concurrently and
concatenated in segment order without added separators; it is available as
`diagnostic stderr` when an assertion fails, unless already shown in a stderr diff. Merged stderr uses the same OS pipe
as routed stdout and is included in matching, without a second diagnostic copy.
Captured streams must be valid UTF-8 and have no configured size limit.
Intermediate pipe data is neither decoded nor normalized. Discarded stdout is
drained concurrently with a fixed 8 KiB byte buffer, without accumulation or
UTF-8 decoding; invalid bytes in discarded output are allowed. Build processes
always use the default routes.

All local segments finish their build preflight before any tested program starts.
Segments then run concurrently, and mooncram waits for all of them to exit.
One deadline includes builds, remote fetching and execution. On timeout, a
startup/capture error, or an imported segment returning `255` or `-1`, all directly managed processes are cancelled and pipes are closed; the
case is an execution error. Programs must manage their own detached child
processes. Tests execute code with the current user's permissions and are
not sandboxed or isolated in a temporary workspace.

## Updating expectations

`update` changes only failing expectations. Passing cases and still-matching
patterns keep their spelling. Commands, fence markers, container prefixes,
surrounding prose, and document line endings are preserved. Special output is
escaped automatically, including missing final newlines and nonzero statuses.

Paired updates keep marker order and unchanged sections, including `(ignore)`.
A satisfied `(empty)` remains; a nonempty actual stream replaces it with a plain
marker and concrete expectations. Patterns are retained independently per
stream. Marker-looking actual lines are escaped automatically. Failure reports
label each failing stream `@STDOUT` or `@STDERR` and show stderr once.

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
