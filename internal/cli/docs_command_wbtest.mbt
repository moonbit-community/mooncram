///|
test "docs parses list and exact document names" {
  assert_true(parse_cli(["docs", "--list"]) is DocsList)
  assert_true(parse_cli(["docs", "invocation"]) is DocsShow("invocation"))
  assert_true(parse_cli(["docs", "--", "markdown"]) is DocsShow("markdown"))
}

///|
test "docs rejects conflicting or invalid arguments" {
  for
    args in [["docs", "--list", "invocation"], ["docs", "invocation", "--list"]] {
    assert_error_contains(
      () => ignore(parse_cli(args)),
      "docs --list cannot be combined with a document name",
    )
  }
  for
    args in [
      ["docs", "invocation", "discovery"],
      ["docs", "--unknown"],
      ["docs", "--dry-run"],
      ["docs", "--version"],
      ["docs", "--"],
      ["docs", "--color", "invalid", "--list"],
    ] {
    assert_error_contains(() => ignore(parse_cli(args)), "")
  }
  for
    (option, value) in [
      ("target", "wasm"),
      ("timeout-ms", "60000"),
      ("color", "always"),
    ] {
    for
      args in [
        ["--" + option, value, "docs", "--list"],
        ["docs", "invocation", "--" + option + "=" + value],
      ] {
      assert_error_contains(() => ignore(parse_cli(args)), "--" + option)
    }
  }
}

///|
test "docs list aligns summaries after padded document names" {
  let expected =
    #|quickstart       First test: targets, path bases, execution rules, and check/test/update workflow.
    #|recipes          Runnable templates: stderr, exit codes, patterns, env, pipes, no-eol.
    #|troubleshooting  Diagnose missing cases/paths/modules, build errors, timeouts, and failed updates.
    #|invocation       CLI options, defaults, check validation, and embedded docs.
    #|discovery        Find Markdown inputs: paths, exclusions, symlinks, and ordering.
    #|markdown         Write mooncram fences, local module declarations, and case boundaries.
    #|commands         Write commands without a shell; resolve #cwd/paths, local packages, env, pipes.
    #|execution        Select backends; run without isolation; share timeouts across builds, fetching, capture.
    #|expectations     Assert stdout/stderr and exit codes; choose exact, glob, regex, no-eol.
    #|reports          Read FAIL/ERROR diagnostics, output diffs, and report color.
    #|updates          Preview/apply updates: passing cases, normalization, preserved patterns, blocked documents.
    #|errors           Understand blocked updates, concurrent edits, and safe file replacement.
    #|summaries        Interpret counters, updated 0, CLI exit codes, and dry-run success versus test success.
  assert_eq(render_docs_list(), expected)
}

///|
test "docs show returns the embedded specification" {
  assert_eq(render_doc_body("invocation"), @docs.invocation_md)
  assert_true(
    render_doc_body("markdown").contains("## Remote package coordinates"),
  )
  assert_true(render_doc_body("execution").has_suffix("\n"))
}

///|
test "docs show rejects unknown names with a discovery hint" {
  for
    name in [
      "README", "README_CN", "MissingDoc", "Invocation", "invocation.md", "../invocation",
      "implementation",
    ] {
    assert_error_contains(
      () => ignore(render_doc_body(name)),
      "unknown document '" + name + "'; use mooncram docs --list",
    )
  }
}
