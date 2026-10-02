///|
fn parse_example(body : String) -> @markdown.Document raise {
  @markdown.parse_document(
    "example.md",
    "```mooncram\n" + body + "```\n",
    @config.default_config(),
  )
}

///|
test "failure report includes location command diff exit and diagnostic stream" {
  let case = parse_example("$ ./a.mbtx arg\nold\n").cases[0]
  let report = @report.failure_report(
    "test.md",
    case,
    { output: "new", diagnostic: "bad\n", exit_code: 7, },
    false,
  )
  for
    expected in [
      "test.md:2", "$ ./a.mbtx arg", "expected 0, actual 7", "-old", "+new (no-eol)",
      "diagnostic stderr\nbad",
    ] {
    assert_true(report.contains(expected), msg=report)
  }
  assert_true(!report.contains("\u001b"))
}
