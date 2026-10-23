# Reports and color

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

Errors are written to **stderr** with the available source location, execution
context, and underlying reason. The `ERROR` header uses the most precise
available source location:

```text
ERROR <file>[:<line>[:<column>]]: <summary>
  <line> | <source before>⟦<highlighted range>⟧<source after>
  note: <related file>:<line>[:<column>]: <message>
  <line> | <related source excerpt>
  $ <original command text>
  phase: <resolve|build|start|run|capture>
  segment: <index>/<count> (<executable>)
  tool: <actual tool or artifact>
  cwd: <working directory>
  cause: <underlying reason>
  hint: <actionable suggestion>
--- captured <build|run> <stdout|stderr> (segment <index>/<count> (<executable>))
<captured output>
```

Line and column numbers are one-based positions in the original Markdown,
including list and block-quote prefixes. Columns count UTF-16 code units: a tab
counts as one and `😀` counts as two. If an exact source range is unavailable,
a known source line may be highlighted in full without a column number.

Parser diagnostics can show source excerpts with `⟦…⟧` around the affected text;
an empty `⟦⟧` marks a position without selecting a character. Related locations
appear as `note` entries with their own source excerpts when available. Tabs,
control characters and literal `⟦`/`⟧` in the source are escaped in excerpts;
column numbers still refer to the original, unescaped line.

Only available fields appear. Argument errors without a document location omit
the file prefix; document parse errors without a command omit the command line.
The separate command line is also omitted when a primary or related source
excerpt already shows the command.
Option-value validation errors include the option name, actual value, and accepted
range or values. Argument-parser syntax errors retain contextual help. Operating
system and dependency reasons appear under `cause`, with wording that can vary
by environment. Detailed configuration-parser reports also appear as causes.

Build failures, startup failures, reserved remote-tool statuses, output-read
failures, and timeouts retain captured logs. The final segment's stdout and each
segment's unmerged stderr are labeled separately, with final stdout first and
segment stderr in pipeline order. Empty logs are omitted, captured output is not
truncated, and successful build artifact information is not repeated.
Nonempty logs that have not reached EOF have `; partial` in their headers and
contain only bytes read so far. Invalid UTF-8 errors identify the stream
and pipeline endpoint; the diagnostic log shows the complete captured byte
sequence with byte escapes and a `; escaped bytes` marker.

Log readers continue while directly managed processes are cancelled and reaped.
After an ordinary error, reading can continue for up to 100 ms after process
cleanup, still within the original case deadline. No extra reading time is added
after that deadline, and readers do not wait indefinitely for pipe handles held
by descendants. The first recorded error remains primary; secondary errors during
log reading or cleanup do not replace it.

Timeout reports include `timed out after N ms (including build)`, along with the
last execution phase, build target, or unfinished pipeline segments. Downloads
and execution inside `moonx` belong to the `run` phase; waiting for output EOF
after all programs have exited belongs to `capture`.

Color selection is evaluated once after discovery:

- `always` enables mooncram's colors, even with `NO_COLOR` or `TERM=dumb`.
- `never` disables mooncram's colors.
- `auto` disables them if `NO_COLOR` exists, even with an empty value, or if
  `TERM` equals `dumb`. Otherwise it enables colors only when inspecting
  `/dev/stdout` reports a character device; inspection errors disable colors.

`FAIL` headings and deleted diff lines are red; added diff lines are green.
Summaries and `ERROR` prefixes are not colorized. The color option does not
strip ANSI bytes emitted by tested programs or control their own color policy.
