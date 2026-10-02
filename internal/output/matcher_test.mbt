///|
fn parse_example(body : String) -> @markdown.Document raise {
  @markdown.parse_document(
    "example.md",
    "```mooncram\n" + body + "```\n",
    @config.default_config(),
  )
}

///|
fn assert_error_contains(f : () -> Unit raise, expected : String) -> Unit raise {
  try f() catch {
    e =>
      assert_true(
        @diagnostic.error_text(e).contains(expected),
        msg=@diagnostic.error_text(e),
      )
  } noraise {
    _ => fail("expected error containing: " + expected)
  }
}

///|
fn assert_output(
  body : String,
  output : String,
  code : Int,
  matches : Bool,
) -> Unit raise {
  let expected = parse_example("$ ./a.mbtx\n" + body).cases[0].expected
  assert_eq(
    expected.matches({
      output: @output.normalize_output(output),
      diagnostic: "ignored",
      exit_code: code,
    }),
    matches,
  )
}

///|
test "empty output empty lines whitespace and exit status" {
  assert_output("", "", 0, true)
  assert_output("", "\n", 0, false)
  assert_output(" (equal)\n", "\n", 0, true)
  assert_output("hello  \n", "hello  \n", 0, true)
  assert_output("hello  \n", "hello\n", 0, false)
  assert_output("a\n\nb\n", "a\n\nb\n", 0, true)
  assert_output("a\n[2]\n", "a\n", 2, true)
  assert_output("a\n[2]\n", "a\n", 0, false)
  assert_output("[-9]\n", "", -9, true)
  assert_output("a\n", "a\r\n", 0, true)
}

///|
test "no-eol escaped controls and syntax conflicts" {
  assert_output("tail (no-eol)\n", "tail", 0, true)
  assert_output("tail (no-eol)\n", "tail\n", 0, false)
  assert_output("tail\n", "tail", 0, false)
  assert_output(
    "\"\\u001b[31m\\t\\r\\u0000\" (escaped) (no-eol)\n[3]\n", "\u001b[31m\t\r\u0000",
    3, true,
  )
  assert_output(
    "\"$ ./looks-like-command\" (escaped)\n\"[1]\" (escaped)\n", "$ ./looks-like-command\n[1]\n",
    0, true,
  )
  assert_output("literal (glob) (equal)\n", "literal (glob)\n", 0, true)
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx\na (no-eol)\nb\n")),
    "example.md:4:",
  )
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx\n\"\" (escaped) (no-eol)\n")),
    "empty output line",
  )
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx\nnot-json (escaped)\n")),
    "JSON string",
  )
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx\n\"a\\nb\" (escaped)\n")),
    "cannot contain LF",
  )
}

///|
test "glob is anchored Unicode aware and supports sets ranges and escapes" {
  for
    (pattern, yes, no) in [
      ("hello *", "hello world", "xhello world"),
      ("a?c", "a😀c", "abbc"),
      ("[a-c][!0-9]", "b😀", "b2"),
      ("[^a]", "b", "a"),
      ("[]-]", "]", "a"),
      ("\\*\\?\\[", "*?[", "xx["),
      ("*", "", "\n"),
    ] {
    assert_output(pattern + " (glob)\n", yes + "\n", 0, true)
    assert_output(pattern + " (glob)\n", no + "\n", 0, false)
  }
  for pattern in ["[", "[a", "[z-a]", "[]", "abc\\"] {
    assert_error_contains(
      () => ignore(parse_example("$ ./a.mbtx\n" + pattern + " (glob)\n")),
      "glob",
    )
  }
}

///|
test "regex matches whole lines including alternations" {
  assert_output("hello [0-9]+ (regex)\n", "hello 123\n", 0, true)
  assert_output("foo|bar (regex)\n", "foo\n", 0, true)
  assert_output("foo|bar (regex)\n", "xbar\n", 0, false)
  assert_output("foo|bar (regex)\n", "foox\n", 0, false)
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx\n[ (regex)\n")),
    "example.md:3: invalid regex",
  )
  for suffix in ["(re)", "(?)", "(*)", "(+)"] {
    assert_error_contains(
      () => ignore(parse_example("$ ./a.mbtx\nx " + suffix + "\n")),
      "unknown output annotation",
    )
  }
}
