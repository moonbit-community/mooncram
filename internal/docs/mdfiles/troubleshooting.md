# Troubleshooting: choose the next action

Start with one failing document so the source location, report and next command
refer to the same input. In the commands below, replace `tests/example.md` with
your document; for local package cases, launch from the module directory.

## From failure to a verified result

1. Run `mooncram check tests/example.md` to validate Markdown, expectations,
   declarations and targets against the current filesystem. It does not build,
   fetch remote packages or verify behavior. A target created by an earlier
   case can be reported missing here; inspect that setup and use `test` to
   exercise the sequence.
2. Run `mooncram test tests/example.md --color never` to build and test behavior.
   `FAIL` on stdout means a completed case did not match its expectations.
   `ERROR` on stderr means parsing, configuration, target resolution or execution
   could not complete; inspect its source location, phase, cwd and captured output.
3. For a mismatch, decide whether the program is wrong or its intended behavior
   changed. Fix unintended behavior in the program, then rerun `test`. Do not
   accept a regression by updating its expectation.
4. For an intentional change, run `mooncram update tests/example.md --dry-run`.
   Review the proposed output and exit-code changes, including normalization of
   passing cases and fences. If correct, run `mooncram update tests/example.md`.
5. Run `mooncram test tests/example.md --color never` again. Use this result,
   rather than the update exit status, to decide whether the tests now pass.

Keep the same `--target` and `--timeout-ms` options on `test`, dry-run and
`update` if your run needs nondefault values. `check` accepts neither option.
Both `test` and dry-run execute code with your permissions and can leave side
effects; there is no sandbox or temporary workspace isolation.

| Mooncram exit code | Meaning and action |
| --- | --- |
| `0` | The command completed successfully. For `test`, assertions passed; for `check`, only structure and current targets were validated. An update/dry-run may still have reported mismatches. |
| `1` | `test` found mismatches and no errors. Review the diff and decide whether to fix the program or update the expectation. |
| `2` | An argument, discovery, document or execution error occurred, or no cases were found. Fix the error before relying on the run. Errors take precedence over mismatches. |

These are mooncram's exit codes. A tested program that returns `2` can pass a
case ending in `[2]`, making `mooncram test` return `0`.

## Symptoms, checks and next commands

| Symptom | What to check | Next command or action |
| --- | --- | --- |
| `no mooncram cases found` | Input files must end in lowercase `.md`. Cases need a backtick `mooncram` fence and a `$ ` command line. Outer example fences hide inner fences; configuration-only blocks are not cases. Directory scans skip hidden entries, `_build` and `target`, and do not follow directory symlinks. | Name the intended file explicitly: `mooncram check tests/example.md`; correct its fence or command if still empty. |
| Script not found | Resolve the script from the block's `#cwd` directory or the canonical document's parent, not the startup directory. Check spelling, `.mbtx` suffix and whether an earlier case creates it. | Correct the script path and run `mooncram check tests/example.md`; for a generated script, verify its setup with `mooncram test tests/example.md`. |
| `#cwd` directory missing or no cases run in a document | All block directories must exist before any case in that document runs. A relative `#cwd` is based on the document directory; quotes become part of the directory name. | Create the directory before invoking mooncram, or correct `#cwd`, then run `mooncram check tests/example.md`. |
| Module missing or module name mismatch | The startup directory must directly contain `moon.mod`; mooncram does not search parents. The fence must declare exactly its `name`, and a local target must use the full module/package name. `#cwd` does not change module lookup. | Change your terminal directory to the module root, correct the declaration/target, then run `mooncram check tests/example.md` with a path relative to that root. |
| Build error | Read the `phase: build` context and captured compiler output. Check dependencies, executable package configuration, selected backend and tool availability. A build failure cannot satisfy a program's `[N]`. | Fix the reported build problem, then rerun `mooncram test tests/example.md --color never` with the same backend. |
| Timeout | The deadline includes local builds, remote fetching, execution and output capture. Inspect the reported phase and partial output for a slow build/download, blocked input or a program that never exits. | Fix a hang; if the work legitimately needs more time, retry `mooncram test tests/example.md --timeout-ms 120000`. |
| Output looks identical but the case fails | Check the reported exit status as well as trailing spaces, tabs, blank lines, ANSI escapes and the final newline. CRLF is normalized, but other characters remain significant. A diff shows expectation syntax, not raw bytes. | Run `mooncram test tests/example.md --color never`; inspect `(escaped)` and `(no-eol)` in the actual side, and correct the program or the precise expectation. |
| An unexpected stderr message still passes | Unmarked cases assert stdout only. Both stream markers are required to opt into stderr assertions. | Add the expected stdout under `@STDOUT` and `@STDERR (empty)` to require silence, or `@STDOUT (ignore)` plus `@STDERR` to check stderr only; rerun `mooncram test tests/example.md`. |
| Update prints `FAIL` but reports `updated 0` | An execution error anywhere in a document suppresses all its edits; look for `ERROR` and `Not updating ...: execution errors in this document`. Replacement or update-validation errors can also prevent edits. Other documents may already have updated. | Fix the reported error, rerun `mooncram update tests/example.md --dry-run`, review the diff, then apply and retest. |
| Dry-run returns `0` while printing `FAIL` or `would update N` | Successful update exit status means the update operation completed without errors; it does not mean assertions passed. | Run `mooncram test tests/example.md --color never` for the assertion result; use `test` in CI. |

For invisible output, an empty stream, one newline and a line without its final
newline need different expectations: no lines, `"" (escaped)`, and
`text (no-eol)`, respectively. Disabling report color does not remove ANSI
escapes emitted by the tested program. Avoid hiding a mismatch with a whole-line
`* (glob)`; preserve the stable text and relax only the field intended to vary.
