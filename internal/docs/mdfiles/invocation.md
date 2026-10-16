# Invocation and command-line parsing

```text
mooncram check [paths...] [--color auto|always|never]
mooncram test [options] [paths...] [options]
mooncram update [options] [paths...] [options] [--dry-run]
mooncram docs --list
mooncram docs <document-name>
mooncram (-h | --help)
mooncram (-V | --version)
mooncram help [check|test|update|docs]
mooncram check (-h | --help)
mooncram test (-h | --help)
mooncram update (-h | --help)
mooncram docs (-h | --help)
```

From the repository checkout, the executable can be launched with:

```text
moon run . -- check README.md
moon run . -- test README.md
moon run . -- update examples --dry-run
```

The `--` in these examples separates `moon` arguments from mooncram
arguments. A later `--` can terminate mooncram's own option parsing.

| Command | Behavior |
| --- | --- |
| `check` | Validate documents and resolve local targets without building or executing cases. |
| `test` | Execute cases and compare routed output and exit status with the expectations. |
| `update` | Execute cases, then update and normalize their expectations from observed results, including passing cases. |
| `update --dry-run` | Execute cases and print proposed document changes without writing them. |
| `docs --list` | List embedded documentation topics and their summaries. |
| `docs <document-name>` | Print one embedded English Markdown document. |
| `help`, `-h`, `--help` | Print the relevant help to stdout and exit with `0`, without discovering or executing cases. |
| `-V`, `--version` | At the top level, print the executable's version string followed by a newline to stdout and exit with `0`. |

`test`, `update`, and `update --dry-run` all execute programs with your
permissions, without a sandbox or temporary workspace isolation. Dry-run only
disables writing the updated Markdown; it does not prevent program side effects.
Use `check` for validation without execution. Use `test` for CI: dry-run can
report expectation mismatches and still return `0`.

A subcommand is required unless a help or version request is handled. An empty
command line is an argument error, not an implicit `test`. Version flags are
not available after `check`, `test`, `update`, or `docs`; for example,
`mooncram test --version` is an argument error.

## Options and defaults

| Option | Scope | Default | Accepted values and effect |
| --- | --- | --- | --- |
| `--target VALUE` | `test`/`update` | `wasm` | Exactly `wasm` or `native`; backend for local packages. Scripts and remote packages always use Wasm. |
| `--timeout-ms N` | `test`/`update` | `60000` | Positive signed 32-bit integer in milliseconds; one deadline per case, including builds, remote fetching, execution, and output capture. |
| `--color VALUE` | `check`/`test`/`update` | `auto` | Exactly `auto`, `always`, or `never`; controls mooncram's report coloring. |
| `--dry-run` | `update` only | Off | Print proposed document diffs instead of replacing documents. Takes no value. |

Value options must follow their applicable subcommand. They can appear before
paths, between paths, or after paths. Both `--target native` and
`--target=native` forms are accepted;
the other value options also accept `--name=value`. These options have no short
aliases. Each value option may be supplied only once; repeated occurrences
are errors rather than overrides. Repeating `--dry-run` keeps it enabled.

`--dry-run` must occur after `update`. It is invalid at the top level and for
`check`, `test`, or `docs`. `check` and `docs` also reject explicit `--target`
and `--timeout-ms`, even when they equal the defaults. `check`, `test`, and
`update` accept `--color`; `docs` rejects all three value options. Top-level
help and `help` have no case options. Supplying `--target`, `--timeout-ms`, or
`--color` before any subcommand is an error. Unknown commands/options, missing
option values, and invalid values produce exit status `2`.

For `--timeout-ms`, only ASCII decimal digits are accepted, with value in
`1..2147483647`. Leading zeroes are allowed. Signs, spaces, fractions, zero,
and overflow are rejected.

For `check`, `test`, and `update`, `paths` accepts zero or more values. With no
paths, it becomes `.`. After one of these subcommands, `--` makes all remaining
arguments paths, including names starting with `-`:

```text
mooncram test --target native docs README.md --color never
mooncram update docs --timeout-ms=120000 --dry-run
mooncram test -- -example.md
```

Mooncram does not expand path globs itself. Expansion by the shell launching
mooncram happens before the CLI receives its arguments. A fence can declare its
module; target and timeout are controlled by the CLI options.

## Embedded documentation

Use `docs` without a repository checkout to find and read the embedded English
reference:

```text
mooncram docs --list
mooncram docs quickstart
mooncram docs recipes
mooncram docs troubleshooting
mooncram docs invocation
```

Start with `quickstart` for a complete first test and target selection,
`recipes` for runnable assertion templates, or `troubleshooting` for the next
action after a failure.

`--list` shows the available topic names and summaries. Pass one listed name to
read that topic as Markdown on stdout. Names are case-sensitive and accept
neither paths nor a `.md` suffix. Use either `--list` or one topic name, not both.
With no arguments, or with `-h`/`--help`, `docs` prints help.

Successful requests exit with `0`; invalid names or arguments exit with `2` and
report an error on stderr. `docs` does not build or execute cases or modify files.
Its only options are `--list` and `-h`/`--help`; case options are not accepted.

## Check without execution

`check` shares file discovery, Markdown parsing, command and expectation
validation, and document-level module/directory validation with `test` and
`update`. Configuration-only fences are validated too. It then resolves each
pipeline segment against the current filesystem, checking script existence,
full executable package names, module boundaries, and exact remote coordinates.
It reads local files and configuration without building,
downloading dependencies, starting subprocesses, or modifying Markdown.

A document parse or declaration-validation failure counts as one error and
prevents checking its cases. A target-resolution failure counts as one error for
that case, skips its remaining segments, and continues with later cases and files.
The summary is `N cases, E errors`. A run with no cases and no other errors
reports `ERROR no mooncram cases found`, exits with `2`, and prints no summary.

Command parsing does not query the environment. Arguments and assignment values
remain literal after quoting and escaping. Check results depend on the current
filesystem. A target generated by an earlier case
may be reported missing by `check`; `test` and `update` resolve targets at
execution time and support this pattern. `check` does not verify source
compilation, backend build support, remote-coordinate existence, or program
assertions. It has no per-case execution timeout.
