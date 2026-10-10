# mooncram CLI behavior specification

[中文版本](CLI_SPEC_CN.md)

This document describes the CLI behavior of the current `0.0.3` module.
It covers the command line, Markdown input format, process execution, matching,
reporting, and updates. It is a description of the current implementation, not
a proposal for additional features. The English and Chinese versions have the
same section structure and should be maintained together.

Examples containing `mooncram` fences are enclosed in larger Markdown example
fences so that this specification does not itself introduce executable cases.
Paths such as `./hello.mbtx` in those examples are illustrative.

## 1. Invocation and command-line parsing

```text
mooncram [global-options] test [paths...] [global-options]
mooncram [global-options] update [paths...] [global-options] [--dry-run]
mooncram (-h | --help)
mooncram (-V | --version)
mooncram help [test|update]
mooncram test (-h | --help)
mooncram update (-h | --help)
```

From the repository checkout, the executable can be launched with:

```text
moon run . -- test README.md
moon run . -- update examples --dry-run
```

The `--` in these two examples separates `moon` arguments from mooncram
arguments. A later `--` can terminate mooncram's own option parsing.

| Command | Behavior |
| --- | --- |
| `test` | Execute cases and compare routed output and exit status with the expectations. |
| `update` | Execute the same cases and replace failing expectations with representations of the observed results. |
| `update --dry-run` | Execute cases and print proposed document changes without writing them. |
| `help`, `-h`, `--help` | Print the relevant help to stdout and exit with `0`, without discovering or executing cases. |
| `-V`, `--version` | At the top level, print the executable's version string followed by a newline to stdout and exit with `0`. |

A subcommand is required unless a help or version request is handled. An empty
command line is an argument error, not an implicit `test`. Version flags are
not available after `test` or `update`; for example, `mooncram test --version`
is an argument error.

### 1.1 Options and defaults

| Option | Scope | Default | Accepted values and effect |
| --- | --- | --- | --- |
| `--target VALUE` | Global | `wasm` | Exactly `wasm` or `native`; default backend for local package cases. |
| `--timeout-ms N` | Global | `60000` | Positive signed 32-bit integer in milliseconds; one deadline for each case's build and execution. |
| `--color VALUE` | Global | `auto` | Exactly `auto`, `always`, or `never`; controls mooncram's report coloring. |
| `--dry-run` | `update` only | Off | Print proposed document diffs instead of replacing documents. Takes no value. |

Global options can appear before the subcommand, before paths, between paths,
or after paths. Both `--target native` and `--target=native` forms are accepted;
the other value options also accept `--name=value`. These options have no short
aliases. Each global value option may be supplied only once, including across
both sides of the subcommand; repeated occurrences are errors rather than
overrides. Repeating `--dry-run` keeps it enabled.

`--dry-run` must occur after `update`. It is invalid at the top level and for
`test`. Unknown commands/options, missing option values, and invalid values
produce exit status `2`.

For `--timeout-ms`, only ASCII decimal digits are accepted, with value in
`1..2147483647`. Leading zeroes are allowed. Signs, spaces, fractions, zero,
and overflow are rejected. Validation after argument parsing checks target,
then timeout, then color.

`paths` accepts zero or more values. With no paths, it becomes `.`. After the
subcommand, `--` makes all remaining arguments paths, including names starting
with `-`:

```text
mooncram --target native test docs README.md --color never
mooncram update docs --timeout-ms=120000 --dry-run
mooncram test -- -example.md
```

Mooncram does not expand path globs itself. Expansion by the shell launching
mooncram happens before the CLI receives its arguments. A fence can declare its
module; target and timeout are controlled by the CLI options.

## 2. File discovery and ordering

Discovery completes before any document is read or any case is executed.

1. Resolve each supplied path against mooncram's invocation directory.
2. Recurse into actual directories. During enumeration, skip entries beginning
   with `.`, entries hidden according to the filesystem API, and entries named
   exactly `_build` or `target`. This includes Windows hidden attributes.
3. Select regular files whose encountered path ends in the case-sensitive
   suffix `.md`. A directly supplied regular file with another suffix is ignored.
4. For a file symlink with an encountered `.md` suffix, include its target if
   it is a regular file. Do not traverse directory symlinks.
5. Resolve selected files to canonical absolute paths, deduplicate those paths,
   and sort them lexicographically.

The skip rules apply to directory entries during traversal. An explicitly
supplied hidden file, hidden directory, `_build`, or `target` is not rejected
just because of its name; its contents still follow the normal discovery rules.
Deduplication uses canonical paths, not file contents or inode identity.
The suffix test is on the encountered path, so an `alias.md` symlink can select
a regular target whose own name has another suffix.

A missing input or a filesystem error during discovery aborts the entire run
with status `2`; already discovered files are not executed. Symlinks ending in
`.md` whose targets cannot be inspected can also produce discovery errors.

Documents run in sorted canonical-path order, independently of argument order.
Cases run serially in document order. Filesystem side effects from earlier
cases remain visible to later cases. Each process starts in the canonical
document's directory and inherits mooncram's environment, overridden by the
exports in effect for that case.

A document without cases is allowed when other documents contain cases. If
there are no attempted cases and no recorded errors, the CLI reports
`ERROR no mooncram cases found` and exits with `2` without a summary.

## 3. Markdown recognition and case boundaries

Documents are read as UTF-8; decoding failures are document errors. Markdown
is parsed structurally with `cmark`, with source locations and layout retained.
Fenced code blocks with a backtick opening fence and the exact, case-sensitive
language `mooncram` contain tests; `mooncram-import` declares file tool imports. The info string accepts
optional whitespace and a single module name, such as `mooncram user/foo`.
The declaration is scoped to that fence; ordinary fences have no module name.
Multiple words, JSON settings, or invalid module names are document parsing
errors at the opening line. Module/package names use nonempty slash-separated
components with ASCII letters, digits, `_`, `-`, or `.`; `.` and `..` components
are prohibited. Valid longer backtick fences work as well as triple backticks.

Other languages, indented code blocks, tilde fences, and apparent fences inside
larger code examples are silently ignored. Cases inside block quotes and lists
are supported; the Markdown container prefix is not part of the command or
output. Normal Markdown indentation rules apply before parsing lines.

An eligible fence must have a closing fence and at least one command (an export
also satisfies this requirement). An unclosed or empty eligible fence is a
document parsing error. Ignored fences do not
produce mooncram parsing errors.

````markdown
```mooncram user/foo
$ ./hello.mbtx "Moon Bit"
Hello, Moon Bit!

$ cmd/main --version
my-cli * (glob)
```
````

Within the parsed code block:

- A line beginning exactly with `$ ` starts a command; an export sets the
  environment and any other command starts a case. A line consisting only of
  `$` is also treated as a command start, then rejected as an empty command.
- Before the first command, only completely empty lines are ignored. Any other
  line is an error. `$` followed only by a tab is not the `$ ` command prefix.
- Every following line up to the next command or closing fence is an
  expectation line, except completely empty lines at the end of that span.
- Trailing empty lines are separators and are excluded from expectations.
  Empty lines inside the remaining expectation span are real output lines;
  whitespace-only lines are not empty separators.
- Commands occupy one source line. There is no multiline command continuation,
  comment syntax, or separate setup/teardown syntax inside a test block.

A line of output that would look like a command must use a JSON string with
`(escaped)`.

The whole document, including all commands and expectations, is parsed before
executing any case in that document. A parsing error prevents
every case in that document from running, even cases before the error. Later
documents are still processed. Reported source line numbers are one-based
positions in the original Markdown document.

### 3.1 File tool imports

A document permits zero or one `mooncram-import` fence, with no settings after
its language name. Recognition follows the same backtick/container rules as
`mooncram`, including longer fences, lists and quotes. Tilde fences and fences
inside larger examples are ignored. An eligible import fence must close and
contain at least one declaration; blank or whitespace-only lines are allowed.
Imports never count as cases, and an import-only document is legal subject to
the overall no-cases rule.

Each nonblank line must be `alias : user/module[/package]@version`. Whitespace
around the colon and declaration is allowed. Aliases are case-sensitive
`[A-Za-z_][A-Za-z0-9_-]*`; `export` is reserved. Coordinates require at least two
path components, following the module/package name rules above. Versions must
be exact SemVer `MAJOR.MINOR.PATCH`, optionally followed by `-prerelease` and
`+build`. Core numbers and numeric prerelease identifiers have no leading zeros;
build identifiers may have them. Identifiers contain ASCII letters, digits and
hyphens, separated by dots, with no empty identifiers. Omitted versions, `latest`,
ranges, wildcards, default arguments and variable expansion are rejected.

All imports are collected and validated before commands and exports are parsed
in their original order. `Document.imports : Map[String, ToolImport]` stores each
alias's `name`, `coordinate` and one-based source `line`. Bindings apply to every
case in that document regardless of declaration position, and never cross files.
A duplicate alias reports both declaration lines; a second import fence is a
document parsing error reporting both opening positions. Other malformed input
is located at the offending line or opening fence.

````markdown
```mooncram-import
moongrep : moonbit-community/moongrep@0.3.5
```
```mooncram
$ moongrep --version
* (glob)
```
````

## 4. Command tokenization and executable selection

The text after the leading `$` is tokenized directly into an array of pipeline
segments or a single export assignment. It is not passed to a shell. The command parser returns
`Command::Pipeline(Array[PipelineSegment])` or
`Command::Export(name~ : String, value~ : String)`, with `Debug` and `Eq`.
Its optional `lookup` callback resolves variables; without it references are
undefined. Returned arguments and assignment values have already been expanded.
`PipelineSegment` has `argv : Array[String]`, `stderr_to_stdout : Bool`, and
`stdout_to_null : Bool`, with `Debug` and `Eq`. Both flags default to `false`
when their markers are absent; `Case.pipeline` stores these segments.

| Syntax | Meaning |
| --- | --- |
| Unquoted, unescaped `\|` | Separate pipeline segments, even without surrounding spaces. |
| Unquoted space or tab | Separate arguments; consecutive separators are ignored. |
| `'text'` | Literal text until the next single quote; backslashes are literal. |
| `"text"` | Text until the next unescaped double quote. |
| Backslash outside single quotes | Quote exactly the next character, including inside double quotes. |
| `''` or `""` | An empty argument, which is preserved. |
| Adjacent quoted/unquoted fragments | Concatenated into the same argument; `a"b"c` becomes `abc`. |
| `${NAME}` outside single quotes, with an unescaped `$` | Expand one environment variable; never split or recursively expand the result. |

Backslash does not interpret C/JSON escape sequences: `\n` contributes `n`,
not a newline, unless the backslash is inside single quotes. A trailing
backslash, an unclosed quote, or a NUL/CR/LF in a command is a parsing error.

Empty pipeline segments, including leading/trailing `|` and `||`, are parsing
errors. Quoted or escaped `|` is an ordinary argument character. For example:

```text
$ ./producer.mbtx|cmd/filter|./consumer.mbtx
```

Except for the exact trailing redirection markers below, unquoted `&`, `;`,
`<`, `>`, backticks, `(`, and `)` are rejected wherever they occur in a word.
Quoting or escaping them passes them literally. There is no wildcard or tilde expansion or command substitution. For example, `'$HOME'`,
`*`, and `~` are literal arguments; `'$(cmd)'` is literal, while unquoted
`$(cmd)` is rejected because of its parentheses.

Each segment, including a single command, accepts these trailing markers:

| Markers | Original stdout | Original stderr |
| --- | --- | --- |
| None | Next segment or final capture | Diagnostic stderr |
| `2>&1` | Next segment or final capture | Same output pipe |
| `>/dev/null` | Discarded | Diagnostic stderr |
| Both, in either order | Discarded | Next segment or final capture |

Markers contain no spaces or tabs and require at least one space or tab between
the marker and the preceding command, argument or marker. The following `|`
needs no whitespace. Each kind may occur at most once, and no ordinary argument
may follow a marker in the same segment. Missing commands, duplicate markers,
internal whitespace, other redirection forms, and redirection on `export` are
parsing errors, retaining the document filename and command line number.

Classification uses exact raw tokens during tokenization, before variable
expansion. Fully quoted or correctly escaped markers and marker text produced by
expansion remain ordinary arguments. Literal `2>&1` requires quoting or `2\>\&1`,
escaping both `>` and `&`; literal `>/dev/null` can use `\>/dev/null`. The old
`stdout>/null` and `stderr>/stdout` syntax is rejected. Expanded argv is never
checked for redirection syntax. For example:

```text
$ ./producer.mbtx >/dev/null 2>&1|cmd/filter
```

`$ export NAME=value` sets exactly one variable. The assignment is split at the
first literal `=`; the name must match `[A-Za-z_][A-Za-z0-9_]*` and cannot contain
variable references. Empty values and additional `=` characters are allowed.
The value follows the argument quoting and expansion rules. Missing assignments,
invalid names, extra arguments, and an `export` segment in any pipeline are
parsing errors. An export accepts no expected output or exit code; any following
nonempty expectation span is a parsing error. Blank separator lines are allowed.
Exports do not count as cases, and export-only fences are valid. The existing
no-cases error still applies when the entire run contains no actual cases.

Exports take effect in source order across eligible blocks in one document and
reset at the next document. Lookup first checks earlier document exports, then
the parent process environment. An exported empty string is a defined value and
overrides the parent. Self-reference reads the value before the assignment.
Each actual case receives an independent `extra_env : Map[String, String]`
snapshot. The original command text is retained for reports, update and dry-run.

On Windows, export assignment, reference lookup and subsequent replacement are
case-insensitive. Export names and lookup keys are normalized to ASCII uppercase,
so differently cased assignments replace the same snapshot entry and child
processes receive only one exported entry per variable. Linux and macOS retain
case-sensitive names. These rules also apply to self-reference and empty values.

Only `${NAME}` references expand; `$NAME` is literal. Unquoted and double-quoted
references expand, while single quotes and escaped dollar signs protect them.
Expansion occurs once and never retokenizes: whitespace, quotes, `|` and even
another `${NAME}` in the result remain inside the same argument. Empty results
remain arguments; `prefix${NAME}suffix` concatenates into one argument. Undefined
variables and invalid or unclosed references are document parsing errors, with
file and source line numbers. The whole document must parse before any case runs.

The first word of every pipeline segment cannot contain an expandable `${NAME}`;
this is a parsing error even if the variable is defined. Single-quoted or escaped
references may appear literally in executable paths. File paths passed as ordinary
arguments follow the normal expansion rules.

The first argument of each segment must be nonempty. A case in an ordinary
`mooncram` fence can execute a file import alias or a regular `.mbtx` file. Script paths are resolved
against the canonical Markdown directory; absolute script paths are accepted.
Scripts are also allowed in fences with a module declaration.

Before executing any case in a document, all declarations must exactly match
`name` in the `moon.mod` located directly in mooncram's startup cwd. This includes
export-only fences. Missing/invalid configuration or a mismatched declaration is
a document error reported at the declaring fence's opening line. No parent
search or registry module loading occurs. `Case.module_name` stores the optional
name; `Document.module_declarations` stores names and opening line numbers.
The execution context stores the module name, startup root, and source root.

Declared fences additionally accept executable package names relative to the
module's `source` directory. Missing, empty, or null `source` means the module
root; otherwise it must resolve to a subdirectory inside the module root.
For `user/foo`, `cmd/boo` refers to `user/foo/cmd/boo`. The short name `foo` first
considers root package `user/foo`, then same-name subpackage `user/foo/foo`.
A package is callable if its configuration declares `pkgtype(kind: "executable")`
or legacy `is-main: true`. If only the subpackage is callable it is selected;
if both are callable the root wins. If neither is callable the case errors.
A selected package's compilation or backend failure errors without fallback.

Each ambiguous pipeline segment emits one independent `WARNING` on mooncram's
stderr with document position, both full names, and the chosen package. Warnings
never enter captured program output, mismatch diagnostics, updated expectations,
or error counts. Package names cannot be absolute directory paths, use `./` or
`../`, contain traversal, or cross another `moon.mod`/`moon.mod.json` boundary,
including through symlinks. `moon.pkg` is parsed with `moonbitlang/moon_config@0.4.2`;
legacy `moon.pkg.json` is read as JSON. Invalid configurations are errors.
Arbitrary binaries, shell commands and `.mbt` files are not case targets.
Remote packages can only be accessed through declared aliases. User targets
are never searched through `PATH`.
Remaining arguments are forwarded to the tested program, so its `--version`
or `--target` is not interpreted as a mooncram option.

Each pipeline segment independently checks its first argument against
`Document.imports`. An alias becomes `moonx --target wasm <coordinate> -- <args...>`;
`Case.command` and the parsed pipeline are retained unchanged. Imported tools
inherit the case cwd, environment snapshot and output routes. CLI `--target`
continues to control local packages; imports always use Wasm. In a declared
fence, probe the same local candidates used by local resolution (including root
short-name and same-name subpackage candidates). If any is executable, fail
before pipeline startup and require a different import alias. Local configuration
read/parse failures propagate normally; they must not be treated as missing
packages. Non-alias segments retain their existing resolution behavior.

## 5. Build, execution, capture, and timeout

Mooncram uses external MoonBit tools. `moon` must be available to build cases;
scripts and imports also require `moonx`, Wasm packages require `moonrun`, and native
package builds require the corresponding native toolchain. The backend used
to run mooncram itself is separate from the backend selected for a test case.

The following argument vectors use resolved absolute paths. Angle-bracket
items are placeholders, not shell syntax:

| Case kind | Build preflight | Program invocation |
| --- | --- | --- |
| `.mbtx` script | `moon run --build-only --target wasm <script>` | `moonx <script> -- <args...>` |
| Wasm package | `moon -C <module-root> run --build-only --target wasm <package>` | `moonrun <artifact> -- <args...>` |
| Native package | `moon -C <module-root> run --build-only --target native <package>` | `<artifact> <args...>` |
| Imported package | None; moonx fetches/builds it | `moonx --target wasm <coordinate> -- <args...>` |

Scripts always use Wasm, including when the CLI specifies `native`.
Mooncram requests a build for every local segment of every case, in segment order.
All local segments must pass preflight before any tested program starts; build
reuse is performed by the underlying tools. Script preflight checks compilation
before `moonx` runs so that preflight compiler failures cannot be accepted as
expected program exits.

A successful build must return stdout containing JSON with an `artifacts_path`
array containing exactly one string. Additional object fields are allowed.
Relative artifact paths are resolved against the document directory. The script
preflight validates this response too, although `moonx` receives the script path.
Nonzero build status, invalid JSON, or a missing/invalid artifact array is an
execution error. Build stdout/stderr are included in build-error diagnostics;
successful build output is not part of the program expectation.

Pipeline segments run concurrently, with OS pipes passing intermediate routed
output to the next stdin as raw bytes, without decoding or newline normalization.
Only the final routed output is captured for stdout assertions.
Unredirected stderr is drained concurrently and buffered, then concatenated in
segment order without added separator bytes for mismatch diagnostics and paired
`@STDERR` assertions. Unmarked cases do not match stderr.
`2>&1` sends stderr to the same OS pipe as routed stdout, preserving
pipe write order, and excludes it from diagnostic collection. When both markers
are present, only original stderr uses the output pipe. `>/dev/null` drains
original stdout concurrently with a fixed 8 KiB byte buffer, without accumulating
or decoding it. If neither stream uses the output pipe, its unused write end is
closed immediately so downstream or final capture can observe EOF. Build
processes always use the default routes. All captured streams must decode
successfully. Pipelines use pipefail by default: Mooncram waits for every segment
to finish and returns `0` if all succeeded, or the rightmost nonzero exit status
in pipeline order otherwise. Completion order does not affect this result.
Ordinary nonzero statuses remain assertable with `[N]` and do not stop later
cases. Reserved imported statuses follow the error rules below. There is no
configured output-size limit or live relay of program output.

Builds and every tested pipeline segment inherit mooncram's environment and
override names using the case's export snapshot. Their working directory is the
canonical document's parent directory. Build processes
and the first pipeline segment receive immediate EOF on stdin rather than
mooncram's interactive input. Later segments receive the preceding routed output.

Captured output must be valid UTF-8. Invalid UTF-8 in either captured stream
is an execution error. Discarded stdout need not be valid UTF-8; intermediate
routed bytes remain undecoded. Every CRLF pair is normalized to LF before
comparison and reporting. Standalone CR, NUL, ANSI escapes, trailing spaces, blank lines,
and the presence or absence of a final newline otherwise remain significant.

One deadline wraps path inspection, build, remote fetching, execution, and output capture for
each case. It is not a fresh timeout per subprocess or a timeout for the whole
run. On expiry the case reports
`timed out after N ms (including build)` as an execution error. Directly managed
processes use hard cancellation. A startup or capture error also cancels every
started segment, and all unconsumed pipe handles are closed on exit. The
implementation does not promise cleanup of detached descendants or rollback of
their effects. Discovery, document parsing, reporting, and document replacement
are outside this per-case deadline.

Cases execute code with the invoking user's permissions, in the actual
document directory. Mooncram provides no sandbox or temporary workspace
isolation. This also applies to `test` and `update --dry-run`.

Only imported commands reserve statuses `255` and `-1` as execution errors,
even if the imported program itself returns them. Statuses are monitored
concurrently for all segments. Any imported segment returning either reserved
status raises an error naming the alias, coordinate, one-based pipeline segment
and status; remaining processes are immediately cancelled and reaped. A final
success cannot hide an earlier reserved status, and waiting on a slow upstream
must not delay detection of a later one. Other statuses follow the pipefail
rule above. Reserved statuses, startup/capture
failures and timeouts cancel all document updates and dry-run document diffs.

mooncram adds no remote dependency installation or cache mechanism. moonx owns
fetching/building/caching, which begins after its process starts. Other segments
may run and produce effects before remote fetching fails; no pre-fetch guarantee
is provided. Remote fetching shares the existing case deadline with local builds
and execution. `test`, `update` and `update --dry-run` use the same flow.

## 6. Expectations, line matching, and exit status

For unmarked cases, a case passes only when all of the following match:

1. Program exit status.
2. Number of routed output lines.
3. Every corresponding output line's matcher.
4. Whether the final output line lacks a newline.

The default exit status is `0`. After removing trailing empty separators, a
final line exactly shaped as `[N]` supplies the expected signed 32-bit status.
`N` is ASCII digits with an optional leading `-`; signs such as `+`, internal
spaces, and other contents do not make a status marker. Leading zeroes are
accepted. A syntactically numeric marker outside the integer range is a parse
error. A status-looking line earlier in the expectation is ordinary output.
Negative statuses represent signal termination as reported by the process
library. A nonzero program exit is a normal matchable result, except for imported `255`
or `-1`; a build failure
or timeout is not.

No expectation lines require empty selected output. Empty output, one newline,
and a nonempty final line without a newline are distinct:

| Actual selected output, in JSON notation | Expectation text |
| --- | --- |
| `""` | No output lines. |
| `"\n"` | One `"" (escaped)` line. |
| `"hello\n"` | `hello` |
| `"hello"` | `hello (no-eol)` |
| `"hello\n\n"` | `hello` followed by `"" (escaped)`. |

### 6.1 Output annotations

Annotations are case-sensitive suffixes, including the separating ASCII
space. Trailing spaces after an annotation stop it from being a suffix.

| Suffix | Semantics |
| --- | --- |
| None | Exact line equality, including whitespace. |
| ` (escaped)` | Parse the preceding text as a complete JSON string, then use exact equality. |
| ` (glob)` | Match the entire line with the glob syntax below. |
| ` (regex)` | Match the entire line with the installed standard-library `Regex`. |
| ` (no-eol)` | Require no terminating LF on the last output line; follows the matcher suffix, if any. |

Only one matcher suffix is interpreted, after removing a final `(no-eol)`.
For example, `"literal (glob)" (escaped)` matches the literal text `literal (glob)`.
Unknown parenthesized suffixes, including `(equal)`, are ordinary text and match
exactly. For example, `hello (equal)`, `hello (foo)`, and `hello (glob) (foo)`
each match their entire literal line.
`hello (foo) (no-eol)` matches `hello (foo)` without a terminating LF.
Use a JSON string with `(escaped)` to match a recognized annotation suffix
literally.
There are no optional-line, repetition, or line-skipping annotations.

`(escaped)` supports control characters and syntax-looking output through JSON
escapes. Its decoded value must not contain LF; use separate expectation lines
for separate output lines. `(no-eol)` is allowed only on the final output line,
in that stream, optionally followed by the final case exit-status marker. An exact empty line with
`(no-eol)` is invalid: represent empty output by omitting output lines.

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

### 6.2 Glob and regex details

Globs operate on Unicode characters, not bytes. `*` matches zero or more
characters, `?` matches one character, and sets/ranges include `[abc]`, `[a-z]`,
`[!a-z]`, and `[^a-z]`. `!` or `^` negates a set only at its beginning. Backslash
quotes the next character, including inside sets. A leading `]` in a set can
be literal, and `-` can be literal when not forming a range; `[]-]` matches `]`
or `-`. Reversed ranges, unclosed/empty sets, and dangling escapes are errors.
There is no filesystem expansion or special directory-separator treatment.

Regex patterns are compiled as `^(?:PATTERN)$`, and the match's content must
equal the entire actual line. This also anchors alternatives such as
`foo|bar`. Supported regex syntax and compilation diagnostics come from the
installed MoonBit standard library. Invalid patterns are document parse errors.
Neither glob nor regex matching spans multiple output lines.

### 6.3 Paired stdout and stderr assertions

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

The two stream constraints and the case exit code must all match. Markers are
recognized only when the exact uppercase name is followed by end of line, a
space or a tab; any following text other than the exact supported annotation
is an error. `@stdout` and `@STDOUTish` are ordinary output. Bare empty lines
before the first marker are allowed separators. Bare empty lines within a
plain section remain output when followed by more output in that section.
An earlier `[N]` is output; only the final case line sets the exit code.
No CLI options or fence settings are added.

## 7. Reports and color

Passing cases produce no individual report. Expectation mismatches produce a report
on **stdout** in both `test` and `update`, including dry runs:

```text
FAIL <canonical-file>:<command-line>
  $ <original command text>
  exit: expected <expected-status>, actual <actual-status>
--- expected
+++ actual
<diff hunks>
```

Diffs use three lines of context. The actual side is rendered in expectation
syntax, including escaping, `(no-eol)`, nonzero status markers, and retained
matching patterns. It is not a raw dump of program output. If diagnostic stderr is
nonempty, the report appends `--- diagnostic stderr` and its normalized text,
ensuring a final newline. Successful cases do not print diagnostic stderr.

For paired cases, only failed content constraints produce diffs. Their headers
are `--- expected @STDOUT` / `+++ actual @STDOUT`, or the equivalent `@STDERR`
headers. Ignored streams produce no content diff. Exit status is shown once in
the case header. Stderr shown in its own diff is not repeated as diagnostic
stderr; ignored stderr remains available for diagnosis if another assertion
fails.

Errors are written to **stderr**:

| Error scope | Report form |
| --- | --- |
| Arguments or discovery | `ERROR <message>` |
| Read, parse, or update of a document | `ERROR <canonical-file>: <message>` |
| Execution of one case | `ERROR <canonical-file>:<command-line>: <message>`, followed by the indented command. |

Argument-parser errors include contextual help. A document parse message
already contains its file and source line; the outer document error handler
currently adds the file prefix again. Dependency/OS error wording and build
diagnostics are passed through and can vary with the environment.

Color selection is evaluated once after discovery:

- `always` enables mooncram's colors, even with `NO_COLOR` or `TERM=dumb`.
- `never` disables mooncram's colors.
- `auto` disables them if `NO_COLOR` exists, even with an empty value, or if
  `TERM` equals `dumb`. Otherwise it enables colors only when inspecting
  `/dev/stdout` reports a character device; inspection errors disable colors.

`FAIL` headings and deleted diff lines are red; added diff lines are green.
Summaries and `ERROR` prefixes are not colorized. The color option does not
strip ANSI bytes emitted by tested programs or control their own color policy.

## 8. Update rendering and preservation

`update` uses the same parser, execution, comparisons, and failure reports as
`test`. Only mismatching cases receive edits; passing cases remain untouched.
Edits replace the expectation span after the command, leaving the command,
fences, surrounding prose, and separator lines in place. The line rendering
rules below apply within each matched stream.

For each actual output line at index `i`, rendering first tries to retain the
existing expectation at the same index if its matcher still matches. This
preserves still-valid glob/regex patterns and explicit escaping even
when another line or the exit status fails. A bare empty expectation and a raw
line beginning with `[` and ending with `]` are rendered afresh to avoid
separator/status ambiguity. Matching is by line index, not by searching for
the same text elsewhere in the output.

New exact output lines are JSON-escaped with `(escaped)` when they are empty,
begin with a space, `$`, or `[`, look like a stream marker, contain a backtick or a control character below
U+0020 or U+007F, or end with a recognized annotation suffix: ` (escaped)`,
` (glob)`, ` (regex)`, or ` (no-eol)`. Other lines, including unknown
parenthesized suffixes, are written literally. The last output line gets
`(no-eol)` exactly when needed. A nonzero actual status appends `[N]`; zero
requires no marker.

For replacement line `i`, an existing output line's Markdown container prefix
and newline spelling are reused when available. Extra lines use the command
line's prefix and newline. This preserves list/quote layout and LF/CRLF/CR
spellings, including mixed line endings, by source position. Text outside the
edited spans is retained, including a missing final document newline.

For paired cases, rendering keeps the original section order, leading and
section separator blanks, and every unchanged section. `(ignore)` remains.
A satisfied `(empty)` remains; a violated `(empty)` becomes a plain marker
with rendered output. Still-matching patterns are retained by line index
independently within each stream. All marker-looking output is JSON-escaped,
including in legacy cases, so re-parsing and repeated updates are idempotent.
Rows retain their own section's existing prefixes and newline spellings; newly
added output rows use the command's layout without shifting the other section's
layout. An unchanged explicit final status marker also keeps its spelling.

In dry-run mode, each document with eligible edits additionally prints:

```text
--- <canonical-file>
+++ <canonical-file> (updated)
<document diff hunks>
```

This is in addition to individual failure reports. Dry runs do not replace
documents or perform the final source-recheck/write sequence. They still build
and run every case, so program effects and build artifacts can be created.

## 9. Error isolation and safe replacement

After a case execution error, later cases in the same document still run.
However, any execution/build/timeout error suppresses **all** expectation edits
for that document. If edits had been collected, stderr also receives:

```text
Not updating <canonical-file>: execution errors in this document
```

The same suppression applies to proposed dry-run document diffs. Parsing
errors prevent execution altogether. Errors in one document do not prevent
other discovered documents from running and updating, and do not undo earlier
updates or program effects.

For an actual update with edits and no case execution errors, mooncram:

1. Creates an exclusive `.mooncram-<stamp>-<attempt>.tmp` sibling file, trying
   up to 100 names.
2. Writes the updated document, syncs the file, and closes it.
3. Rereads the destination and compares its content with the original source.
4. Refuses replacement if it changed, reporting
   `source changed during execution; refusing to update <path>`.
5. Otherwise renames the temporary file over the destination on the same
   filesystem. Temporary-file removal is attempted on exit, including errors.

Replacement is atomic per file; updates across documents are not a transaction.
The content check is not a filesystem lock, and there is a window between the
check and rename. File symlinks were resolved during discovery, so replacement
targets the canonical document. Original permissions, inode identity, hard-link
relationships, and extended metadata are not preserved. On Unix, the replacement
uses new-file permissions `0644`, subject to umask; the filesystem library
ignores this permission parameter on Windows.

## 10. Counters, summaries, and process exit status

After processing all discovered files, normal summaries go to stdout:

```text
<total> cases, <failed> failed, <errors> errors
<total> cases, updated <updated>, <errors> errors
<total> cases, would update <updated>, <errors> errors
```

For example:

```text
3 cases, 1 failed, 0 errors
3 cases, updated 1, 0 errors
3 cases, would update 1, 0 errors
```

| Counter | Meaning |
| --- | --- |
| `total` | Cases whose execution was attempted, incremented before execution. Includes cases with execution errors; excludes exports, imports and cases in documents that failed to parse or validate module declarations. |
| `failed` | Completed cases whose output and/or exit status mismatched. Execution errors are counted separately. Printed only for `test`. |
| `errors` | Caught per-case errors plus document read/parse/module-validation/update errors. A parse or module-validation failure counts as one document error. |
| `updated` | Mismatching cases in documents successfully written, or eligible for a dry-run document diff. Counts cases, not files or changed lines. |

Documents whose updates are suppressed or whose write fails do not contribute
to `updated`. An update can print `FAIL` reports and still have `updated 0`
because a later execution error suppressed that document's changes.

| Exit status | Condition |
| --- | --- |
| `0` | Help/version succeeded; or at least one case ran with no errors and all `test` expectations passed; or `update`/dry-run finished without errors, regardless of mismatches. |
| `1` | `test` has at least one mismatch and no errors. |
| `2` | Argument/discovery failure, any recorded document or case error, or no cases found. |

Errors take precedence over mismatches. A document error with zero attempted
cases still produces a summary such as `0 cases, 0 failed, 1 errors`; the
special no-cases message applies only when both total and errors are zero.
Argument/discovery failures, help/version, and that no-cases path have no normal
summary. These statuses belong to mooncram, independently of tested programs'
expected exit statuses.

## 11. Implementation and verification map

| Behavior | Implementation | Existing verification |
| --- | --- | --- |
| Entry point and arguments | [main.mbt](../main.mbt), [cli/cli.mbt](cli/cli.mbt), [cli/run.mbt](cli/run.mbt) | [cli/cli_wbtest.mbt](cli/cli_wbtest.mbt) |
| Scheduling, counters, error isolation | [cli/runner.mbt](cli/runner.mbt) | [tests/integration.mjs](../tests/integration.mjs) |
| Discovery and atomic replacement | [files/files.mbt](files/files.mbt), [files/path.mbt](files/path.mbt) | [files/files_test.mbt](files/files_test.mbt) |
| Markdown and commands | [markdown/markdown.mbt](markdown/markdown.mbt), [markdown/command.mbt](markdown/command.mbt) | [markdown/parser_wbtest.mbt](markdown/parser_wbtest.mbt) |
| File tool imports | [markdown/imports.mbt](markdown/imports.mbt), [markdown/types.mbt](markdown/types.mbt) | [markdown/imports_wbtest.mbt](markdown/imports_wbtest.mbt), [tests/integration.mjs](../tests/integration.mjs) |
| Execution and artifact parsing | [execute/execute.mbt](execute/execute.mbt), [execute/module.mbt](execute/module.mbt) | [execute/module_wbtest.mbt](execute/module_wbtest.mbt), [execute/execute_wbtest.mbt](execute/execute_wbtest.mbt), [tests/integration.mjs](../tests/integration.mjs) |
| Matching and output rendering | [output/expectation.mbt](output/expectation.mbt), [output/glob.mbt](output/glob.mbt), [output/render.mbt](output/render.mbt) | [output/matcher_test.mbt](output/matcher_test.mbt), [update/update_test.mbt](update/update_test.mbt) |
| Reports and local edits | [report/report.mbt](report/report.mbt), [update/update.mbt](update/update.mbt) | [report/report_test.mbt](report/report_test.mbt), [update/update_test.mbt](update/update_test.mbt) |

The CLI also inherits help, option parsing, and regex details from the installed
MoonBit standard library, and process/filesystem details from its declared
dependencies. When those change, verify the observable behavior as well as the
project sources before updating this specification.

Existing project checks are:

```text
moon test
node tests/integration.mjs
moon info && moon fmt
```

The integration runner exercises both Wasm and native mooncram executables by
default, using real scripts and packages. `--target wasm` or `--target native`
selects one CLI backend; those integration-runner options are separate from
mooncram's case-target option.

Import integration checks replace moonx with a locally built fixture executable,
so pinned remote tools are tested without registry/network dependencies. The
fixture validates the exact wasm invocation, reserved exits and cancellation.
