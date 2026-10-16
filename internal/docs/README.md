# Embedded CLI documentation

[中文](README_CN.md)

This package bundles the documentation available through `mooncram docs --list`
and `mooncram docs <document-name>`. The embedded documents are primarily for
people using the mooncram CLI, who typically do not read mooncram's source code
directly.

## Content guidelines

Describe information that helps CLI users choose a command, write a test,
understand a result, or resolve a failure. Prefer behavior that users can
observe and verify through the CLI:

- Supported commands, options, defaults, prerequisites, and input syntax.
- Path and working-directory rules, stdout and stderr, exit codes, diagnostics,
  and changes to files.
- Runnable examples with explicit setup, commands, and expected results.
- Limitations and edge cases that affect a user's workflow, with ways to check
  the behavior or confirm a fix.

Explain what users need to do, what they will see, and how they can verify it.
Examples should state required files, tools, and working directories rather than
depend on unstated repository context. Describe current behavior and keep claims
consistent with CLI behavior and tests.

Include implementation details only when they explain a consequence relevant to
CLI users. Internal types, helper functions, call sequences, and architectural
notes belong in code comments or developer documentation unless they are needed
to understand an observable result.

## Maintaining the documents

Edit the Markdown sources in [`mdfiles/`](mdfiles/). The embedding rules in
[`moon.pkg`](moon.pkg) generate the corresponding `.mbt` files; edit the sources
instead of the generated copies. Topic names, summaries, and embedded bodies are
registered in [`export.mbt`](export.mbt).

When changing a document, verify its examples and stated outcomes through the
CLI. Keep its topic summary and any corresponding translations consistent.
