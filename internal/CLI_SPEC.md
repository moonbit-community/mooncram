# mooncram CLI behavior specification

[中文版本](CLI_SPEC_CN.md)

This document describes the CLI behavior of the current `0.0.1` module.
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
| `test` | Execute cases and compare their selected output stream and exit status with the expectations. |
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
mooncram happens before the CLI receives its arguments. There is no project
configuration file: defaults come from the CLI and individual fence settings.

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
cases remain visible to later cases. Each process still starts with its own
configured environment and working directory.

A document without cases is allowed when other documents contain cases. If
there are no attempted cases and no recorded errors, the CLI reports
`ERROR no mooncram cases found` and exits with `2` without a summary.

## 3. Markdown recognition and case boundaries

Documents are read as UTF-8; decoding failures are document errors. Markdown
is parsed structurally with `cmark`, with source locations and layout retained.
Only fenced code blocks with a backtick opening fence and the exact,
case-sensitive language name `mooncram` are considered. Valid longer backtick
fences work as well as triple backticks.

Other languages, indented code blocks, tilde fences, and apparent fences inside
larger code examples are ignored. Cases inside block quotes and lists are
supported; the Markdown container prefix is not part of the command or output.
Normal Markdown fence indentation rules apply before mooncram parses lines.

An eligible fence must have a closing fence and at least one case. An unclosed
or empty eligible fence is a document parsing error. The optional text after
the language name is parsed as block configuration (section 5).

````markdown
```mooncram
$ ./hello.mbtx "Moon Bit"
Hello, Moon Bit!

$ ./cmd/main --version
my-cli * (glob)
```
````

Within the parsed code block:

- A line beginning exactly with `$ ` starts a case. A line consisting only of
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

A line of output that would look like a command must use `(escaped)`. Merely
adding `(equal)` to a line starting with `$ ` does not prevent it from being
recognized as another command.

The whole document, including all commands, configurations, and expectations,
is parsed before executing any case in that document. A parsing error prevents
every case in that document from running, even cases before the error. Later
documents are still processed. Reported source line numbers are one-based
positions in the original Markdown document.

## 4. Command tokenization and executable selection

The text after the leading `$` is tokenized directly into an argument vector.
It is not passed to a shell.

| Syntax | Meaning |
| --- | --- |
| Unquoted space or tab | Separate arguments; consecutive separators are ignored. |
| `'text'` | Literal text until the next single quote; backslashes are literal. |
| `"text"` | Text until the next unescaped double quote. |
| Backslash outside single quotes | Quote exactly the next character, including inside double quotes. |
| `''` or `""` | An empty argument, which is preserved. |
| Adjacent quoted/unquoted fragments | Concatenated into the same argument; `a"b"c` becomes `abc`. |

Backslash does not interpret C/JSON escape sequences: `\n` contributes `n`,
not a newline, unless the backslash is inside single quotes. A trailing
backslash, an unclosed quote, or a NUL/CR/LF in a command is a parsing error.

Unquoted `|`, `&`, `;`, `<`, `>`, backticks, `(`, and `)` are rejected wherever
they occur in a word. Quoting or escaping them passes them literally. There
is no variable, wildcard, tilde, or command substitution. For example, `'$HOME'`,
`*`, and `~` are literal arguments; `'$(cmd)'` is literal, while unquoted
`$(cmd)` is rejected because of its parentheses.

The first argument must be nonempty. It is resolved as a local path relative
to the canonical Markdown file's directory, not searched through `PATH`.
Absolute paths are also accepted. It must resolve to either:

- A regular file with a case-sensitive `.mbtx` suffix; or
- A directory containing `moon.pkg` or `moon.pkg.json`. The `moon` tool then
  validates that it is an executable package and supports the requested target.

A bare name can work if it names an appropriate local path. Arbitrary binaries,
shell commands, `.mbt` files, and packages named only by registry identifiers
are not executable case targets. Missing paths, unsupported file kinds, and
nonexecutable packages are execution/build errors, not output mismatches.
Remaining arguments are forwarded to the tested program, so its `--version`
or `--target` is not interpreted as a mooncram option.

## 5. Block configuration and precedence

An optional JSON object after `mooncram` applies to every case in that fence.
Each fence starts from the CLI defaults independently; settings do not carry
over from preceding fences.

````markdown
```mooncram {"stream":"stderr","stdin":"./input.txt","env":{"MODE":"test"},"target":"native","timeout_ms":120000}
$ ./cmd/main --invalid
unknown option: --invalid
[2]
```
````

| Field | Default | Accepted value |
| --- | --- | --- |
| `stream` | `"stdout"` | Exactly `"stdout"`, `"stderr"`, or `"merged"`. |
| `stdin` | Immediate EOF | Nonempty string path without NUL. |
| `env` | `{}` | JSON object whose values are strings. |
| `target` | CLI `--target` | Exactly `"wasm"` or `"native"`. |
| `timeout_ms` | CLI `--timeout-ms` | JSON number with integral value in `1..2147483647`. |

Empty settings text and `{}` retain defaults. Invalid JSON, a non-object
configuration, unknown fields, and incorrect value types are parsing errors
located at the opening fence. Fields cannot be reset with `null`. JSON numeric
values such as `1000.0` are valid for `timeout_ms` if their numeric value is an
integer; the CLI's digit-only timeout syntax is a separate rule.

Environment names must be nonempty and contain neither `=` nor NUL. Values
must not contain NUL; empty string values are valid. The mapping overrides
inherited variables for both build and execution processes; other variables
remain inherited. It does not provide an unset-variable operation.

Command paths, stdin paths, and the working directory of builds and programs
all use the canonical document's parent directory as their base. A stdin file
is reopened for each case. Without `stdin`, the tested program receives immediate
EOF rather than mooncram's interactive stdin. Build preflights always receive
EOF, even when the block configures an input file.

## 6. Build, execution, capture, and timeout

Mooncram uses external MoonBit tools. `moon` must be available to build cases;
scripts also require `moonx`, Wasm packages require `moonrun`, and native
package builds require the corresponding native toolchain. The backend used
to run mooncram itself is separate from the backend selected for a test case.

The following argument vectors use resolved absolute paths. Angle-bracket
items are placeholders, not shell syntax:

| Case kind | Build preflight | Program invocation |
| --- | --- | --- |
| `.mbtx` script | `moon run --build-only --target wasm <script>` | `moonx <script> -- <args...>` |
| Wasm package | `moon -C <package> run --build-only --target wasm <package>` | `moonrun <artifact> -- <args...>` |
| Native package | `moon -C <package> run --build-only --target native <package>` | `<artifact> <args...>` |

Scripts always use Wasm, including when CLI or fence settings specify `native`.
Mooncram requests a build for every case; any build reuse is performed by the
underlying tools. Script preflight checks compilation before `moonx` runs so
that preflight compiler failures cannot be accepted as expected program exits.

A successful build must return stdout containing JSON with an `artifacts_path`
array containing exactly one string. Additional object fields are allowed.
Relative artifact paths are resolved against the document directory. The script
preflight validates this response too, although `moonx` receives the script path.
Nonzero build status, invalid JSON, or a missing/invalid artifact array is an
execution error. Build stdout/stderr are included in build-error diagnostics;
successful build output is not part of the program expectation.

Both program streams are drained concurrently and buffered to completion:

| `stream` | Compared output | Other stream |
| --- | --- | --- |
| `stdout` | stdout | stderr retained for mismatch diagnostics. |
| `stderr` | stderr | stdout retained for mismatch diagnostics. |
| `merged` | stdout and stderr connected to the same OS pipe | No separate diagnostic stream. |

Merged mode preserves the order in which bytes reach the common pipe. Program
buffering can affect that order. Separate streams have no combined ordering.
The unselected stream does not affect matching, but it is still read and must
decode successfully. There is no configured output-size limit or live relay of
program output.

Captured output must be valid UTF-8. Invalid UTF-8 in either captured stream
is an execution error. Every CRLF pair is normalized to LF before comparison
and reporting. Standalone CR, NUL, ANSI escapes, trailing spaces, blank lines,
and the presence or absence of a final newline otherwise remain significant.

One deadline wraps path inspection, build, execution, and output capture for
each case. It is not a fresh timeout per subprocess or a timeout for the whole
run. On expiry the case reports
`timed out after N ms (including build)` as an execution error. Directly managed
processes use hard cancellation; the implementation does not promise cleanup
of detached descendants or rollback of their effects. Discovery, document
parsing, reporting, and document replacement are outside this per-case deadline.

Cases execute local code with the invoking user's permissions, in the actual
document directory. Mooncram provides no sandbox or temporary workspace
isolation. This also applies to `test` and `update --dry-run`.

## 7. Expectations, line matching, and exit status

A case passes only when all of the following match:

1. Program exit status.
2. Number of output lines in the selected stream.
3. Every corresponding output line's matcher.
4. Whether the final output line lacks a newline.

The default exit status is `0`. After removing trailing empty separators, a
final line exactly shaped as `[N]` supplies the expected signed 32-bit status.
`N` is ASCII digits with an optional leading `-`; signs such as `+`, internal
spaces, and other contents do not make a status marker. Leading zeroes are
accepted. A syntactically numeric marker outside the integer range is a parse
error. A status-looking line earlier in the expectation is ordinary output.
Negative statuses represent signal termination as reported by the process
library. A nonzero program exit is a normal matchable result; a build failure
or timeout is not.

No expectation lines require empty selected output. Empty output, one newline,
and a nonempty final line without a newline are distinct:

| Actual selected output, in JSON notation | Expectation text |
| --- | --- |
| `""` | No output lines. |
| `"\n"` | One ` (equal)` or `"" (escaped)` line. |
| `"hello\n"` | `hello` |
| `"hello"` | `hello (no-eol)` |
| `"hello\n\n"` | `hello` followed by `"" (escaped)`. |

### 7.1 Output annotations

Annotations are case-sensitive suffixes, including the separating ASCII
space. Trailing spaces after an annotation stop it from being a suffix.

| Suffix | Semantics |
| --- | --- |
| None | Exact line equality, including whitespace. |
| ` (equal)` | Exact equality with the text before this suffix. |
| ` (escaped)` | Parse the preceding text as a complete JSON string, then use exact equality. |
| ` (glob)` | Match the entire line with the glob syntax below. |
| ` (regex)` | Match the entire line with the installed standard-library `Regex`. |
| ` (no-eol)` | Require no terminating LF on the last output line; follows the matcher suffix, if any. |

Only one matcher suffix is interpreted, after removing a final `(no-eol)`.
For example, `literal (glob) (equal)` means the literal text `literal (glob)`.
Unknown parenthesized suffixes are ordinary text and match exactly. For example,
`hello (foo)` and `hello (glob) (foo)` each match their entire literal line.
`hello (foo) (no-eol)` matches `hello (foo)` without a terminating LF.
Use `(equal)` or `(escaped)` to match a recognized annotation suffix literally.
There are no optional-line, repetition, or line-skipping annotations.

`(escaped)` supports control characters and syntax-looking output through JSON
escapes. Its decoded value must not contain LF; use separate expectation lines
for separate output lines. `(no-eol)` is allowed only on the final output line,
optionally followed by the final exit-status marker. An exact empty line with
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

### 7.2 Glob and regex details

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

## 8. Reports and color

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
matching patterns. It is not a raw dump of program output. If an unselected
stream is nonempty, the report appends `--- diagnostic stderr` or
`--- diagnostic stdout` and that stream's normalized text, ensuring a final
newline. Successful cases do not print that diagnostic stream.

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

## 9. Update rendering and preservation

`update` uses the same parser, execution, comparisons, and failure reports as
`test`. Only mismatching cases receive edits; passing cases remain untouched.
Edits replace the expectation span after the command, leaving the command,
fences, settings, surrounding prose, and separator lines in place.

For each actual output line at index `i`, rendering first tries to retain the
existing expectation at the same index if its matcher still matches. This
preserves still-valid glob/regex patterns and explicit equality/escaping even
when another line or the exit status fails. A bare empty expectation and a raw
line beginning with `[` and ending with `]` are rendered afresh to avoid
separator/status ambiguity. Matching is by line index, not by searching for
the same text elsewhere in the output.

New exact output lines are JSON-escaped with `(escaped)` when they are empty,
begin with a space, `$`, or `[`, contain a backtick or a control character below
U+0020 or U+007F, or end with a recognized annotation suffix: ` (equal)`,
` (escaped)`, ` (glob)`, ` (regex)`, or ` (no-eol)`. Other lines, including unknown
parenthesized suffixes, are written literally. The last output line gets
`(no-eol)` exactly when needed. A nonzero actual status appends `[N]`; zero
requires no marker.

For replacement line `i`, an existing output line's Markdown container prefix
and newline spelling are reused when available. Extra lines use the command
line's prefix and newline. This preserves list/quote layout and LF/CRLF/CR
spellings, including mixed line endings, by source position. Text outside the
edited spans is retained, including a missing final document newline.

In dry-run mode, each document with eligible edits additionally prints:

```text
--- <canonical-file>
+++ <canonical-file> (updated)
<document diff hunks>
```

This is in addition to individual failure reports. Dry runs do not replace
documents or perform the final source-recheck/write sequence. They still build
and run every case, so program effects and build artifacts can be created.

## 10. Error isolation and safe replacement

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

## 11. Counters, summaries, and process exit status

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
| `total` | Cases whose execution was attempted, incremented before execution. Includes cases with execution errors; excludes cases in documents that failed to parse. |
| `failed` | Completed cases whose output and/or exit status mismatched. Execution errors are counted separately. Printed only for `test`. |
| `errors` | Caught per-case errors plus document read/parse/update errors. A parse failure counts as one document error. |
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

## 12. Implementation and verification map

| Behavior | Implementation | Existing verification |
| --- | --- | --- |
| Entry point and arguments | [main.mbt](../main.mbt), [cli/cli.mbt](cli/cli.mbt), [cli/run.mbt](cli/run.mbt) | [cli/cli_wbtest.mbt](cli/cli_wbtest.mbt) |
| Scheduling, counters, error isolation | [cli/runner.mbt](cli/runner.mbt) | [tests/integration.mjs](../tests/integration.mjs) |
| Discovery and atomic replacement | [files/files.mbt](files/files.mbt), [files/path.mbt](files/path.mbt) | [files/files_test.mbt](files/files_test.mbt) |
| Markdown, commands, configuration | [markdown/markdown.mbt](markdown/markdown.mbt), [markdown/command.mbt](markdown/command.mbt), [config/config.mbt](config/config.mbt) | [markdown/parser_wbtest.mbt](markdown/parser_wbtest.mbt) |
| Execution and artifact parsing | [execute/execute.mbt](execute/execute.mbt) | [execute/execute_wbtest.mbt](execute/execute_wbtest.mbt), [tests/integration.mjs](../tests/integration.mjs) |
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
