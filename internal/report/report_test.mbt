///|
fn parse_example(body : String) -> @markdown.Document raise {
  @markdown.parse_document("example.md", "```mooncram\n" + body + "```\n")
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

///|
test "failure report keeps unknown suffixes literal and escapes known suffixes" {
  let case = parse_example("$ ./a.mbtx\nold\n").cases[0]
  let report = @report.failure_report(
    "test.md",
    case,
    { output: "hello (foo)\nhello (glob)\n", diagnostic: "", exit_code: 0, },
    false,
  )
  assert_true(report.contains("+hello (foo)\n"), msg=report)
  assert_true(report.contains("+\"hello (glob)\" (escaped)\n"), msg=report)
}

///|
test "dual reports label failing streams and avoid duplicate stderr" {
  let case = parse_example("$ ./a.mbtx\n@STDOUT\nold out\n@STDERR\nold err\n").cases[0]
  let report = @report.failure_report(
    "test.md",
    case,
    { output: "new out\n", diagnostic: "new err\n", exit_code: 2, },
    false,
  )
  for
    wanted in [
      "expected @STDOUT", "actual @STDOUT", "expected @STDERR", "actual @STDERR",
      "-old out", "+new out", "-old err", "+new err", "expected 0, actual 2",
    ] {
    assert_true(report.contains(wanted), msg=report)
  }
  assert_true(!report.contains("diagnostic stderr"), msg=report)
  let report = @report.failure_report(
    "test.md",
    case,
    { output: "old out\n", diagnostic: "new err\n", exit_code: 0, },
    false,
  )
  assert_true(!report.contains("expected @STDOUT"), msg=report)
  assert_true(report.contains("expected @STDERR"), msg=report)
}

///|
test "ignored stderr stays available for diagnosis on other failures" {
  let case = parse_example("$ ./a.mbtx\n@STDOUT (empty)\n@STDERR (ignore)\n").cases[0]
  let report = @report.failure_report(
    "test.md",
    case,
    { output: "\n", diagnostic: "context\n", exit_code: 0, },
    false,
  )
  assert_true(report.contains("actual @STDOUT"), msg=report)
  assert_true(report.contains("+\"\" (escaped)"), msg=report)
  assert_true(!report.contains("expected @STDERR"), msg=report)
  assert_true(report.contains("diagnostic stderr\ncontext\n"), msg=report)
}
