# Expectations, line matching, and exit status

By default, a case asserts **stdout and the program exit code**, which defaults
to `0`. It does not assert stderr. To check stderr, include both `@STDOUT` and
`@STDERR` exactly once: use `@STDOUT (ignore)` to check stderr only, or
`@STDERR (empty)` alongside your stdout expectations to require stderr silence.

The final `[N]` specifies the tested program's expected exit code. It does not
specify mooncram's own exit code: a program returning `2` can pass a case ending
in `[2]`, making `mooncram test` return `0` when all cases pass. Build failures
and timeouts are execution errors, not assertable program exit codes.

## Prepare the examples

The annotation and paired-stream examples below share one script. Install
`mooncram` and a complete MoonBit toolchain, with its `bin` directory on `PATH`.
The script uses that installation's `moon` and `moonrun`. Create these files in a
new `demo` directory; no module configuration or repository checkout is needed.
The script pins its dependencies; the first build needs access to download them.

```text
demo/
└── tests/
    ├── output.mbtx
    ├── escaped.md
    └── streams.md
```

Complete contents of `tests/output.mbtx`:

```mbt
import {
  "moonbitlang/async@0.22.4",
  "moonbitlang/async@0.22.4/stdio",
  "moonbitlang/core/env",
  "moonbitlang/x@0.5.5/sys",
}

async fn main {
  match @env.args().get(1).unwrap_or("result") {
    "result" => @stdio.stdout.write("result\n")
    "special" => {
      @stdio.stdout.write("$ this is output\n[2]\n```\n")
      @stdio.stdout.write("\u001b[31mred\u001b[0m\n\nfinal text")
      @sys.exit(3)
    }
    "--invalid" => {
      @stdio.stderr.write("error: invalid argument\n")
      @sys.exit(2)
    }
    _ => @sys.exit(3)
  }
}
```

Copy the complete `escaped.md` and `streams.md` examples from their sections
below, omitting the outer four-backtick `markdown` wrappers.

## Choose a matching strategy

Start with exact output and deterministic inputs. Relax only fields whose
variation is part of the intended behavior:

| Strategy | Use when | Example expectation line |
| --- | --- | --- |
| Exact | Text, values and spacing should remain stable. This is the default and makes changes visible in review. | `processed 3 files` |
| Glob | A field may contain arbitrary text, but the surrounding wording must remain stable. | `saved report-*.json (glob)` |
| Regex | A variable field must still obey a particular format or set of allowed values. | `processed [0-9]+ files (regex)` |
| Escaped exact | Fixed output contains control characters, significant whitespace or text resembling test syntax. | `"ready> " (escaped) (no-eol)` |

Prefer a fixed fixture over a pattern when you can control the input. For
example, if exactly three files should be processed, keep `processed 3 files`;
the regex above would also accept a wrong count. Avoid whole-line `* (glob)` or
`.* (regex)` for meaningful output: they can hide changed labels, empty fields
and error messages. Keep stable prefixes, separators and units literal, and
constrain dynamic values as tightly as the contract permits. Patterns still
assert exactly one output line; extra lines and final-newline differences fail.

## What makes a case pass

For unmarked cases, a case passes only when all of the following match:

1. Program exit status.
2. Number of final stdout lines.
3. Every corresponding output line's matcher.
4. Whether the final output line lacks a newline.

The default exit status is `0`. After removing trailing empty separators, a
final line exactly shaped as `[N]` supplies the expected signed 32-bit status.
`N` is ASCII digits with an optional leading `-`; signs such as `+`, internal
spaces, and other contents do not make a status marker. Leading zeroes are
accepted. A syntactically numeric marker outside the integer range is a parse
error. A status-looking line earlier in the expectation is ordinary output.
Negative statuses represent signal termination as reported by the process
library. A nonzero program exit is a normal matchable result, except for remote `255`
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

## Output annotations

Annotations are case-sensitive suffixes, including the separating ASCII
space. Trailing spaces after an annotation stop it from being a suffix.

| Suffix | Semantics |
| --- | --- |
| None | Exact line equality, including whitespace. |
| ` (escaped)` | Parse the preceding text as a complete JSON string, then use exact equality. |
| ` (glob)` | Match the entire line with the glob syntax below. |
| ` (regex)` | Match the entire line with this CLI's regular-expression syntax, described below. |
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

Complete contents of `tests/escaped.md`:

````markdown
```mooncram
$ moonx ./output.mbtx special
"$ this is output" (escaped)
"[2]" (escaped)
"```" (escaped)
"\u001b[31mred\u001b[0m" (escaped)
"" (escaped)
final text (no-eol)
[3]
```
````

From `demo`, run `mooncram check tests/escaped.md`, then
`mooncram test tests/escaped.md`. They print `1 cases, 0 errors` and
`1 cases, 0 failed, 0 errors`, respectively, and both exit with `0`.
The script's exit code `3` is expected by `[3]`.

## Glob and regex details

Globs operate on Unicode characters, not bytes. `*` matches zero or more
characters, `?` matches one character, and sets/ranges include `[abc]`, `[a-z]`,
`[!a-z]`, and `[^a-z]`. `!` or `^` negates a set only at its beginning. Backslash
quotes the next character, including inside sets. A leading `]` in a set can
be literal, and `-` can be literal when not forming a range; `[]-]` matches `]`
or `-`. Reversed ranges, unclosed/empty sets, and dangling escapes are errors.
There is no filesystem expansion or special directory-separator treatment.

Regex patterns must match the entire output line, including when using
alternatives: `foo|bar` matches `foo` or `bar`, but not `foox` or `xbar`. You do
not need to add `^` and `$`. Neither glob nor regex spans multiple output lines.

Regex syntax and diagnostics come from the implementation bundled when this
mooncram executable was built. Updating the local MoonBit toolchain does not
change an existing executable's regex support; that requires a new mooncram build.

Common forms supported by this CLI include:

| Expectation line | Example matching output | Meaning |
| --- | --- | --- |
| `item [0-9]+ (regex)` | `item 42` | One or more ASCII digits. |
| `v[0-9]+\.[0-9]+\.[0-9]+ (regex)` | `v1.2.3` | Numeric version components separated by literal dots. |
| `status: (ok\|error) (regex)` | `status: ok` or `status: error` | Grouping and alternatives. |
| `colou?r (regex)` | `color` or `colour` | An optional character. |
| `[A-Za-z_][A-Za-z0-9_]* (regex)` | `name_1` | An ASCII identifier; `*` allows zero or more following characters. |
| `[[:digit:]]{2,4} (regex)` | `2026` | An ASCII POSIX character class with bounded repetition. |

Write backslashes directly in expectation lines, as in `\.` above. Use `[0-9]`,
`[[:space:]]`, and `[A-Za-z0-9_]` instead of `\d`, `\s`, and `\w`, respectively.
These shorthands and their uppercase variants are unsupported. POSIX classes
are ASCII-based.
Lookahead, lookbehind, and backreferences are also unsupported. Invalid patterns
are document parse errors; `mooncram check <file>` can validate them without
executing cases.

## Paired stdout and stderr assertions

Use `@STDOUT` and `@STDERR` to assert both streams in one execution:

Complete contents of `tests/streams.md`:

````markdown
```mooncram
$ moonx ./output.mbtx
@STDOUT
result
@STDERR (empty)

$ moonx ./output.mbtx --invalid
@STDOUT (ignore)
@STDERR
error: invalid argument
[2]
```
````

From `demo`, run `mooncram check tests/streams.md`, then
`mooncram test tests/streams.md`. They print `2 cases, 0 errors` and
`2 cases, 0 failed, 0 errors`, respectively, and both exit with `0`.

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

`@STDOUT` selects the final segment's stdout. `@STDERR` selects all
stderr, concatenated in pipeline order without added separators.
There is no comparison of timing between streams. Ignored streams are still
captured and checked for UTF-8, with the same deadlines and process cleanup.
Cases without stream markers assert only the final segment's stdout and the
pipeline exit status; stderr is available for diagnostics.

The two stream constraints and the case exit code must all match. Markers are
recognized only when the exact uppercase name is followed by end of line, a
space or a tab; any following text other than the exact supported annotation
is an error. `@stdout` and `@STDOUTish` are ordinary output. Bare empty lines
before the first marker are allowed separators. Bare empty lines within a
plain section remain output when followed by more output in that section.
An earlier `[N]` is output; only the final case line sets the exit code.
