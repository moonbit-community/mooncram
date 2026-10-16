# Command tokenization and executable selection

Commands are parsed directly, without a shell. Environment variables,
wildcards and `~` remain literal; shell redirection is unsupported. After any
temporary assignments, every pipeline segment must explicitly start with
`moonx`. Quoting groups arguments; it does not enable variable expansion.

## Path bases at a glance

Keep the startup directory, document directory, block working directory and
module directory distinct:

| Object | Path base |
| --- | --- |
| Input paths passed to `check`, `test` or `update` | The directory where mooncram starts. |
| Local module's `moon.mod` | Directly in the startup directory; no parent-directory search. |
| Cases without `#cwd` | The canonical Markdown file's parent directory. |
| Relative paths in `#cwd(path)` | The canonical Markdown file's parent directory. |
| Script paths and relative file arguments used by the program | The current block's working directory. |
| Full local package names | The module's source root (`source` in `moon.mod`, or the module root by default); local builds run from the module root. |

Canonical means the real path after resolving symlinks. A Markdown file symlink
therefore uses its target's parent directory. Absolute paths do not use a base.
`#cwd` applies only to its block and does not change module lookup or the base of
another block's `#cwd`. All declared directories must exist before any case in
the document executes.

For example, consider this layout:

```text
project/
├── moon.mod                 # name = "user/acme"
├── cmd/tool/                # executable local package
├── docs/
│   └── cases.md
└── fixtures/
    ├── read.mbtx
    └── input.txt
```

Launch `mooncram test docs/cases.md` from `project`. In a block beginning with
`#cwd(../fixtures)`, the command `moonx ./read.mbtx input.txt` selects
`project/fixtures/read.mbtx`; the program can open `input.txt` in
`project/fixtures`. Without that declaration, the same command would look for
`project/docs/read.mbtx` and use `project/docs` as its working directory.

If that block instead runs `moonx user/acme/cmd/tool input.txt`, declare
`mooncram user/acme` on its opening fence. With the default module source root,
mooncram builds `project/cmd/tool` using `project/moon.mod`, while the program
still runs in `project/fixtures`. Starting mooncram from `project/docs` would
make local module lookup fail; `#cwd(../fixtures)` cannot repair that.

## Command syntax

The text after the leading `$` is split into commands and arguments directly,
without a shell. Quotes and escapes are processed, but environment variables
are not expanded. Temporary assignments override inherited variables only for
that pipeline segment's build and run. Reports and updates retain the original
command text.

| Syntax | Meaning |
| --- | --- |
| Unquoted, unescaped `\|` | Separate pipeline segments, even without surrounding spaces. |
| Unquoted space or tab | Separate arguments; consecutive separators are ignored. |
| `'text'` | Literal text until the next single quote; backslashes are literal. |
| `"text"` | Text until the next unescaped double quote. |
| Backslash outside single quotes | Quote exactly the next character, including inside double quotes. |
| `''` or `""` | An empty argument, which is preserved. |
| Adjacent quoted/unquoted fragments | Concatenated into the same argument; `a"b"c` becomes `abc`. |
| `${NAME}` or `$NAME` | Ordinary text, using the same splitting, quoting and escaping rules as other text. |

Backslash does not interpret C/JSON escape sequences: `\n` contributes `n`,
not a newline, unless the backslash is inside single quotes. A trailing
backslash or an unclosed quote is a parsing error. Commands cannot contain
embedded CR or LF. Raw NUL characters in Markdown become `U+FFFD` (`�`).

Empty pipeline segments, including leading/trailing `|` and `||`, are parsing
errors. Quoted or escaped `|` is an ordinary argument character. For example:

```text
$ moonx ./producer.mbtx|moonx user/foo/cmd/filter|moonx ./consumer.mbtx
```

Unquoted, unescaped `&`, `;`, `<`, `>`, backticks, `(` and `)` are rejected
wherever they occur in a word. Output redirection, including `2>&1` and
`1>/dev/null`, is unsupported in every pipeline segment. Quoting or escaping
operators passes them literally: `'2>&1'`, `2\>\&1` and `1\>/dev/null` are ordinary
arguments. There is no wildcard or tilde expansion or command substitution.
For example, `'$HOME'`, `*`, `~` and `'$(cmd)'` are literal arguments; unquoted
`$(cmd)` is rejected because of its parentheses. Errors retain the document
filename and command line number.

`#cwd(path)` declares one working directory for the current fence. The declaration
occupies a whole logical line starting exactly with `#cwd(` and ending with `)`.
It takes all text between the opening prefix and the final `)`
as the nonempty path, without trimming, tokenization, escaping, variable expansion
or parenthesis matching. Spaces, backslashes, quotes, parentheses, Chinese text and
`${NAME}` remain literal. For example, `#cwd(../fixtures with spaces)` needs no
quotes; `#cwd("foo")` includes the double quotes in its path, and `#cwd(a)b(c))`
stores `a)b(c)`. Each block permits at most one declaration on its first nonempty
logical line; leading empty lines are allowed. Empty paths, missing final `)`,
duplicates and declarations after a test command are parsing errors with source
locations. A declaration accepts no expected output or exit code. It is not a case;
configuration-only fences are legal. If the whole run has no attempted cases and
no recorded errors, it reports `ERROR no mooncram cases found`, exits with `2`,
and prints no summary.

Output beginning with `#cwd(` must use a JSON string with `(escaped)`, even when
it would be a malformed declaration. The updater automatically escapes such
output so generated documents parse again and a second update is unchanged.
Updates preserve the declaration's original text and Markdown layout.

The working directory applies only to its block; without a declaration, cases
use the canonical Markdown file's parent directory. Relative `#cwd` paths are
also based on that document directory, never another block's working directory.
Absolute paths and symlinks to directories are accepted and resolved to real
absolute paths. Script paths and relative file arguments use the block's working
directory. Local module lookup still uses mooncram's startup directory, and local
packages are built from their module root.

Before any case or build in a document, mooncram validates every working-directory
declaration, including those in blocks without cases. Directories must already
exist; earlier cases cannot create them.

Validation failures are one document error, located at the directive and showing
the resolved path: zero cases execute and no update occurs in that document,
while later documents continue. A directory removed after validation causes an
execution error when used.

Environment variable expansion is not supported. `${NAME}`, `$NAME`, `${}`,
`${A-B}` and `${UNCLOSED` are ordinary text and do not trigger environment lookup
or reference validation. Normal splitting, quoting and escaping still apply:
`${A B}` is two arguments, while `"${A B}"` is one literal argument. Assignment
values follow the same rules. Expected output is literal too. The whole document
must parse before any case runs.

`$ NAME=value OTHER="${NAME}" moonx ./program.mbtx` sets temporary variables for one
pipeline segment and its build. Only consecutive assignments before the executable
are recognized, with an unquoted, unescaped name and `=`; names must match
`[A-Za-z_][A-Za-z0-9_]*`. Values follow the command quoting
and escaping rules, including empty values and additional `=`.
Assignments after the executable are ordinary arguments.
Words with invalid variable names, such as `9A=x` and `A-B=x`, are not recognized
as temporary assignments. They are ordinary words; before `moonx` they cause
a missing-moonx parsing error, and after the target they remain program arguments.

Temporary values override the parent environment, including with an empty string.
Values and arguments remain literal: `A=new B="${A}" moonx ./program.mbtx "${B}"` sets `B` to `${A}` and
passes `${B}` as its argument. Repeated names keep the last value. Each pipeline
segment has its own temporary environment, and later commands inherit the parent environment.
Windows names are normalized to ASCII uppercase and matched case-insensitively;
Linux and macOS names remain case-sensitive. Assignments without a command
are parsing errors.

After temporary assignments, every executable segment must begin with `moonx`
and a nonempty target. Missing prefixes, bare targets and empty targets are
parsing errors. No moonx options are accepted before the target. Target paths,
working directories and file arguments keep variable-like text literal.
An `export` executable is rejected with `command must start with moonx: export`.

A target ending in `.mbtx` is a local script, relative to the block's working
directory or absolute. This includes script filenames containing `@`.
Otherwise a target containing `@` must be a valid remote coordinate with exact
SemVer, even if its package name matches the declared local module.

Before processing any case, all module declarations must exactly match `name`
in the `moon.mod` directly in mooncram's startup cwd, including configuration-only
fences. Missing/invalid configuration or mismatches are document errors at the
opening fence. There is no parent-directory search.

Unversioned package targets require a module-declared fence and the full package
name. For module `user/foo`, `user/foo` selects the root package and
`user/foo/cmd/boo` selects that subpackage. `foo`, `cmd/boo`, other module names
and paths such as `./foo` are rejected. Missing, empty or null `source` means
the module root; otherwise the source root must remain inside the module.
Full names are mapped relative to this source root. Packages must declare
`pkgtype(kind: "executable")` or `options("is-main": true)`. Compilation and
backend errors propagate. Traversal, empty path components, nested `moon.mod`
boundaries and symlink escapes are prohibited. Invalid `moon.pkg` configurations
are errors.

Arbitrary binaries, shell commands and `.mbt` files are not targets, and user
targets are not searched through `PATH`. Every argument after the target,
including `--`, `--version` and `--target`, is forwarded unchanged to the program.
