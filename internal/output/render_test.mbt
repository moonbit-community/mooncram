///|
fn assert_rendering(
  body : String,
  actual : @output.Captured,
  wanted : Array[String],
) -> Unit raise {
  let expected = parse_example("$ moonx ./a.mbtx\n" + body).cases[0].expected
  assert_eq(@output.actual_expectation(actual, expected), wanted)
  assert_eq(
    @output.actual_expectation_layout(actual, expected).map(row => row.0),
    wanted,
  )
}

///|
test "exact reports and update layouts agree after insertions deletions and replacements" {
  let expected = parse_example("$ moonx ./a.mbtx\nhead\nkeep\ntail\n").cases[0].expected
  guard expected.body is Legacy(content) else { fail("expected stdout only") }
  for
    (output, wanted) in [
      (
        "head\ninsert\nkeep\ntail\n",
        [
          ("head", Some(0)),
          ("insert", None),
          ("keep", Some(1)),
          ("tail", Some(2)),
        ],
      ),
      ("head\ntail\n", [("head", Some(0)), ("tail", Some(2))]),
      (
        "head\nchanged\ntail\n",
        [("head", Some(0)), ("changed", Some(1)), ("tail", Some(2))],
      ),
    ] {
    let actual : @output.Captured = { output, diagnostic: "", exit_code: 0, }
    assert_eq(@output.actual_expectation_layout(actual, expected), wanted)
    assert_eq(
      @output.actual_expectation(actual, expected),
      wanted.map(row => row.0),
    )
    assert_eq(
      @output.actual_stream_expectation(output, content.lines),
      wanted.map(row => row.0),
    )
  }
}

///|
test "exact case rendering preserves blanks Unicode controls and status syntax" {
  for
    (output, code, wanted) in [
      ("", 0, []),
      ("\n", 0, ["\"\" (escaped)"]),
      ("\n\n", 0, ["", "\"\" (escaped)"]),
      ("value\n\n\n", 0, ["value", "", "\"\" (escaped)"]),
      ("\n", 2, ["", "[2]"]),
      ("中文😀  \n尾🚀", 0, ["中文😀  ", "尾🚀 (no-eol)"]),
      (
        "\u0000\t\r\u001b\u007f\n",
        0,
        ["\"\\u0000\\t\\r\\u001b\\u007f\" (escaped)"],
      ),
      ("[2]\n", 0, ["\"[2]\" (escaped)"]),
      ("[2147483648]\n", 0, ["\"[2147483648]\" (escaped)"]),
      ("[2]", 0, ["[2] (no-eol)"]),
      ("[2]\nlast\n", 0, ["[2]", "last"]),
      ("[2]\n", 2, ["[2]", "[2]"]),
      (
        "$ moonx ./other.mbtx\n#cwd(.)\n@STDERR\nliteral (glob)\nliteral (regex)\n",
        0,
        [
          "\"$ moonx ./other.mbtx\" (escaped)", "\"#cwd(.)\" (escaped)", "\"@STDERR\" (escaped)",
          "\"literal (glob)\" (escaped)", "\"literal (regex)\" (escaped)",
        ],
      ),
    ] {
    assert_rendering(
      "old\n",
      { output, diagnostic: "ignored", exit_code: code, },
      wanted,
    )
  }
}

///|
test "exact stream reports preserve empty output final newlines and literal status lines" {
  for
    (text, wanted) in [
      ("", []),
      ("\n", ["\"\" (escaped)"]),
      ("value\n\n", ["value", "\"\" (escaped)"]),
      ("tail", ["tail (no-eol)"]),
      ("[2]\n", ["[2]"]),
      ("@STDOUT\n", ["\"@STDOUT\" (escaped)"]),
    ] {
    assert_eq(@output.actual_stream_expectation(text, []), wanted)
  }
}

///|
test "report alignment retains shifted glob and regex spellings" {
  for
    (body, output, wanted) in [
      (
        "v* (glob)\n[0-9]+ (regex)\n",
        "insert\nversion\n123\n",
        ["insert", "v* (glob)", "[0-9]+ (regex)"],
      ),
      (
        "obsolete\nv* (glob)\n[0-9]+ (regex)\n",
        "version\n123\n",
        ["v* (glob)", "[0-9]+ (regex)"],
      ),
      (
        "v* (glob)\n[0-9]+ (regex)\n",
        "version\ninsert\n123",
        ["v* (glob)", "insert", "[0-9]+ (regex) (no-eol)"],
      ),
      (
        "v* (glob)\n[0-9]+ (regex)\n",
        "wrong\n123\n",
        ["wrong", "[0-9]+ (regex)"],
      ),
    ] {
    assert_rendering(body, { output, diagnostic: "", exit_code: 0, }, wanted)
    let expected = parse_example("$ moonx ./a.mbtx\n" + body).cases[0].expected
    guard expected.body is Legacy(content) else { fail("expected stdout only") }
    assert_eq(@output.actual_stream_expectation(output, content.lines), wanted)
  }
}

///|
test "paired report rendering preserves stream policies order separators and patterns" {
  for
    (body, output, diagnostic, code, wanted) in [
      (
        "\n@STDERR\nold err\n\n@STDOUT\nold out\n",
        "new out\n\n",
        "new err",
        0,
        [
          "", "@STDERR", "new err (no-eol)", "", "@STDOUT", "new out", "\"\" (escaped)",
        ],
      ),
      (
        "@STDOUT (ignore)\n\n@STDERR (empty)\n[2]\n",
        "ignored\n",
        "",
        2,
        ["@STDOUT (ignore)", "", "@STDERR (empty)", "[2]"],
      ),
      (
        "@STDERR (ignore)\n@STDOUT (empty)\n",
        "\n",
        "ignored",
        0,
        ["@STDERR (ignore)", "@STDOUT", "\"\" (escaped)"],
      ),
      (
        "@STDOUT\nold\nkeep\n@STDERR\nerror [0-9]+ (regex)\n",
        "new\nkeep\n",
        "insert\nerror 42\n",
        0,
        ["@STDOUT", "new", "keep", "@STDERR", "insert", "error [0-9]+ (regex)"],
      ),
      (
        "@STDERR\nold\n@STDOUT\nv* (glob)\n",
        "insert\nversion",
        "[2]\n",
        0,
        ["@STDERR", "[2]", "@STDOUT", "insert", "v* (glob) (no-eol)"],
      ),
    ] {
    assert_rendering(body, { output, diagnostic, exit_code: code, }, wanted)
  }
}
