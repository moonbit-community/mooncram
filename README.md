# mooncram

[中文](README_CN.md)

Test MoonBit command-line applications and scripts with examples written in
Markdown. Put a command next to its expected output, explain the behavior, and
let mooncram check that the example still works.

mooncram is **inspired by [scrut](https://facebookincubator.github.io/scrut/docs/)**.
It brings readable CLI tests to MoonBit, with support for local executable
packages, standalone `.mbtx` scripts, and tools from Mooncakes.

## Why mooncram?

Unit tests check your functions. CLI tests check what someone using your program
actually sees: arguments, output, error messages, and exit codes.

Use mooncram to test a greeting script, a command's `--version` output, an invalid
argument, or a pipeline of MoonBit tools. Your tests are ordinary Markdown
files, so you can explain the intent alongside each example. When the behavior
changes intentionally, mooncram can refresh the expected output for you.

## Getting started

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) first.
You need `moon`, `moonx`, and `moonrun` on your `PATH`.

To try the current source:

```sh
git clone https://github.com/moonbit-community/mooncram.git
cd mooncram
moon update
moon run . -- test README.md
```

That last command runs this example using [examples/hello.mbtx](examples/hello.mbtx):

```mooncram
$ moonx ./examples/hello.mbtx "Moon Bit"
Hello, Moon Bit!
```

A successful run ends with:

```text
1 cases, 0 failed, 0 errors
```

From this checkout, `moon run . -- <arguments>` launches mooncram. To install it
as a command for use in other projects, run:

```sh
moon install ./
mooncram --help
```

Keep the MoonBit binary directory on your `PATH`. The rest of this guide uses
the installed `mooncram` command.

## Write your first test

Create two files beside each other:

```text
tests/
├── hello.mbtx
└── hello.md
```

In `tests/hello.mbtx`, write a small program:

```mbt
fn main {
  println("Hello, MoonBit!")
}
```

In `tests/hello.md`, describe what you want to test:

````markdown
# Greeting

The script greets the user.

```mooncram
$ moonx ./hello.mbtx
Hello, MoonBit!
```
````

Then run:

```sh
mooncram test tests/hello.md
```

The `$ ` line is the command. The lines below it are the expected stdout.
The expected exit code is `0` unless you say otherwise. Programs run from the
directory containing the test document, so `./hello.mbtx` is the file beside it.

Each command starts a new case. A document can contain several blocks, with
headings and explanations between them. Only backtick fences labeled `mooncram`
are tests. Illustrative documents below appear inside larger `markdown` fences,
so they are not executed as part of the README.

## Choose what to run

### Local scripts

Write `moonx` followed by a relative or absolute path to a `.mbtx` file. Arguments support single
quotes, double quotes, and backslash escapes. For a script accepting a name,
such as this repository's `examples/hello.mbtx`:

````markdown
```mooncram
$ moonx ./hello.mbtx "Moon Bit"
Hello, Moon Bit!
```
````

### Packages in your project

Add your module's full name after `mooncram`. Suppose `moon.mod` declares
`name = "user/acme"` and your executable lives in `cmd/acme`:

````markdown
```mooncram user/acme
$ moonx user/acme/cmd/acme --version
acme 1.0.0
```
````

Launch mooncram from the directory containing that `moon.mod`. The declaration
must match its name exactly and applies only to that block. The package must be
executable, for example with `pkgtype(kind: "executable")` in `moon.pkg`.
Write `moonx` and the full package name, including the module name. For an
executable root package, use `moonx user/acme`.

mooncram builds local packages before running them. Build diagnostics stay
separate from the program output being tested. Packages use Wasm by default;
`mooncram test tests --target native` selects native and requires a C toolchain.
Standalone scripts always use Wasm.

Arguments after the target are passed directly to the program, including a
literal `--`. mooncram does not parse moonx options before the target.

### Tools from Mooncakes

Run a full coordinate and an exact version directly with `moonx`:

````markdown
```mooncram
$ moonx moonbit-community/mooncram@0.0.3 --version
0.0.3
```
````

Coordinates use `user/module[/package]@version`. Versions must be exact SemVer;
ranges, omitted versions and `latest` are rejected. No import block or alias is
needed. Old `mooncram-import` blocks are ignored as ordinary Markdown.

`moonx` downloads and caches remote tools. They always use Wasm, including
when local packages use `--target native`.

## Describe the expected result

### Output and exit codes

Output lines match exactly by default, including spaces. To test a failure,
place the expected exit code on the last line:

````markdown
```mooncram user/acme
$ moonx user/acme/cmd/acme --unknown
@STDOUT (empty)
@STDERR
error: unknown option --unknown
[2]
```
````

`@STDOUT` and `@STDERR` let you check both streams in one run. Include each
marker exactly once. Add `(empty)` to require no output at all, or `(ignore)` to
skip checking that stream. Without markers, only stdout is matched; stderr is
available in failure diagnostics.

A command with no expected output lines must produce empty stdout. If you only
care whether it succeeds, use `@STDOUT (ignore)` and `@STDERR (ignore)` together.

### Flexible output expectations

For output that varies, match the stable parts with a glob or regex:

````markdown
```mooncram user/acme
$ moonx user/acme/cmd/acme --version
acme * (glob)

$ moonx user/acme/cmd/acme --version
acme [0-9]+\.[0-9]+\.[0-9]+ (regex)
```
````

| Suffix | What it checks |
| --- | --- |
| None | The exact output line |
| ` (glob)` | A whole-line pattern with `*`, `?`, or character sets such as `[a-z]` |
| ` (regex)` | A regular expression matching the whole line |
| ` (escaped)` | An exact line written as a JSON string, such as `"a\tb"` |
| ` (no-eol)` | The last output line has no terminating newline; may follow another suffix |

Each expectation matches one output line. Use JSON escaping for lines that look
like test syntax: `"[2]" (escaped)` or `"$ this is output" (escaped)`.
Use `"" (escaped)` to assert an empty output line, especially at the end.
CRLF is normalized to LF; captured output must be valid UTF-8.

Prefer fixed input files when you can: a fixture makes a test reproducible while
keeping its expectations precise. Use patterns for parts that need to vary,
such as generated IDs or version numbers.

## Set up the test environment

### Environment variables

Commands inherit your environment. Use a prefix assignment to set a variable
for one command. The tested program reads the environment itself, for example
in `environment.mbtx`:

```mbt
import { "moonbitlang/core/env" }

fn main {
  let name = @env.get_env_var("NAME").unwrap_or("World")
  println("Hello, \{name}!")
}
```

````markdown
```mooncram
$ NAME='Moon Bit' moonx ./environment.mbtx
Hello, Moon Bit!

$ NAME=World moonx ./environment.mbtx
Hello, World!
```
````

Temporary assignments apply only to that pipeline segment and its build;
later commands inherit the original environment. Mooncram does not
expand environment variables: `${NAME}` and `$NAME` are ordinary text in
arguments, assignment values, executable paths, working directories and expected
output. Normal argument splitting, quoting and escaping still apply. For example,
`NAME=World moonx ./hello.mbtx "${NAME}"` passes the literal argument `${NAME}` while
setting `NAME` to `World` in the child process. To pass a name as an argument,
write it explicitly, as in `moonx ./hello.mbtx World`.

### Working directory and fixtures

Programs run in the directory containing the test document by default. Keep
fixtures beside the document and pass their relative paths as arguments.
To use another directory, set it before the first test command in a block:

````markdown
```mooncram
$ set-current-working-directory ../examples
$ moonx ./hello.mbtx "Moon Bit"
Hello, Moon Bit!
```
````

The directory is relative to the document, must already exist, and applies only
to that block. Local module lookup still uses the directory where you launched
mooncram. Cases run in document order; files created by one remain visible to
later cases. Programs use your current permissions and existing filesystem;
mooncram does not create an isolated temporary workspace.

### Pipelines

Connect scripts, local packages, and remote tools with `|`. Every segment
must explicitly name `moonx`:

````markdown
```mooncram user/acme
$ moonx ./input.mbtx | moonx user/acme/cmd/acme --uppercase
HELLO, MOONBIT!
```
````

Segments run concurrently. The last segment's stdout is matched. The expected
exit code uses **pipefail**: the rightmost nonzero code, or `0` if all succeed.
The first segment receives EOF on stdin.

Each segment's stderr is captured separately, in pipeline order. Use `@STDOUT`
and `@STDERR` to check both streams. Output redirection, including `2>&1` and
`1>/dev/null`, is rejected in every segment. Quote or escape such text to pass it
as an ordinary argument.

Commands use mooncram's own parser, rather than a shell. Shell commands such as
`echo` and `cat`, operators such as `&&` and `;`, command substitution,
redirection, and multiline shell expressions are unsupported. Put setup logic
in a MoonBit script when needed.

## Keep tests up to date

If a program now prints a different greeting, `test` reports a diff between the
expected and actual output. After reviewing the new behavior, preview and apply
updated expectations:

```sh
mooncram update tests --dry-run
mooncram update tests
mooncram test tests
```

`update` writes directly into the original documents without a confirmation
prompt. It also normalizes passing cases and keeps glob/regex patterns that
still match. Commands and surrounding prose are preserved. A document with
parsing, build, or execution errors is not updated.

`--dry-run` displays edits without writing Markdown, but still runs programs,
which can change files themselves. For validation without execution, use:

```sh
mooncram check tests
```

`check` validates syntax, expectations, and local target resolution without
building, fetching tools, or running programs. Use `test` afterward to verify
compilation and behavior. A script generated by an earlier case may be reported
missing by `check`, since no cases execute during that check.

## Command reference and CI

```text
mooncram check [paths...] [--color auto|always|never]
mooncram test [paths...] [--target wasm|native] [--timeout-ms N]
mooncram update [paths...] [--target wasm|native] [--timeout-ms N] [--dry-run]
mooncram --help
mooncram --version
```

Pass files, directories, or both. Directories are searched recursively for `.md`
files; no paths means the current directory. Hidden entries, `_build`, and
`target` are skipped during traversal; directory symlinks are not followed.
Files are deduplicated and sorted before their cases run.

Execution errors include the source location, phase, pipeline segment, tool and
working directory when available. Captured stdout/stderr is included in full;
`partial` marks a stream cancelled before EOF. Invalid UTF-8 is shown as escaped
bytes in diagnostics. Timeouts identify the last execution phase.

The default target is `wasm`. The default timeout is `60000` milliseconds per
case, including builds, downloads, and execution. `check` does not accept
`--target` or `--timeout-ms`. All commands support `--color` (default `auto`);
`NO_COLOR` disables automatic color. Put `--` before paths starting with `-`.

In CI, install the toolchain and mooncram, then run
`mooncram test tests --color never`. Use the exit status to decide whether it passed:

| Status | Meaning |
| --- | --- |
| `0` | Check, test, or update completed successfully |
| `1` | An output or exit-code assertion failed in `test` |
| `2` | Invalid arguments, a parsing/build/execution error, or no cases found |

`update --dry-run` returns `0` when it completes, even if edits are proposed.
Use `test` for the CI pass/fail decision.

## Further reading

- [Example test document](examples/README.md)
- [Detailed CLI and format reference](internal/CLI_SPEC.md)
- [scrut documentation](https://facebookincubator.github.io/scrut/docs/), which inspired the Markdown testing workflow and this guide's tutorial structure

## Development

From the repository root:

```sh
moon test
moon test --target native
moon run . -- test README.md README_CN.md
node e2etests/integration.mjs
moon info && moon fmt
```

The integration suite requires Node.js and a native C toolchain and exercises
both Wasm and native. See [the CI workflow](.github/workflows/check.yml) for the
full checks.

## License

[Apache-2.0](LICENSE).
