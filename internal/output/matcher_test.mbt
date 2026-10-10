///|
fn parse_example(body : String) -> @markdown.Document raise {
  @markdown.parse_document("example.md", "```mooncram\n" + body + "```\n")
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
  assert_output("\"\" (escaped)\n", "\n", 0, true)
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
  assert_output("\"literal (glob)\" (escaped)\n", "literal (glob)\n", 0, true)
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
}

///|
test "equal suffix matches literal text including with no-eol" {
  for line in [" (equal)", "hello (equal)", "literal (glob) (equal)"] {
    let without_suffix = line[:line.length() - 8].to_owned()
    assert_output(line + "\n", line + "\n", 0, true)
    assert_output(line + "\n", without_suffix + "\n", 0, false)
    assert_output(line + " (no-eol)\n", line, 0, true)
    assert_output(line + " (no-eol)\n", without_suffix, 0, false)
    assert_output(line + " (no-eol)\n", line + "\n", 0, false)
  }
}

///|
test "unknown output annotations match literal text" {
  for suffix in ["(foo)", "(re)", "(?)", "(*)", "(+)"] {
    let line = "hello " + suffix
    assert_output(line + "\n", line + "\n", 0, true)
    assert_output(line + "\n", "hello\n", 0, false)
  }
  assert_output("hello (glob) (foo)\n", "hello (glob) (foo)\n", 0, true)
  assert_output("hello (glob) (foo)\n", "hello anything (foo)\n", 0, false)
  assert_output("hello (foo) (no-eol)\n", "hello (foo)", 0, true)
  assert_output("hello (foo) (no-eol)\n", "hello (foo)\n", 0, false)
}

///|
test "annotation recognition requires exact suffix spelling" {
  for
    line in [
      "hello (GLOB)", "hello (NO-EOL)", "hello (glob) ", "hello (no-eol) ", "hello(glob)",
    ] {
    assert_output(line + "\n", line + "\n", 0, true)
    assert_output(line + "\n", "hello\n", 0, false)
  }
}

///|
fn assert_streams(
  body : String,
  stdout : String,
  stderr : String,
  code : Int,
  matches : Bool,
) -> Unit raise {
  let expected = parse_example("$ ./a.mbtx\n" + body).cases[0].expected
  assert_eq(
    expected.matches({ output: stdout, diagnostic: stderr, exit_code: code, }),
    matches,
  )
}

///|
test "paired streams match independently in either order" {
  for
    body in [
      "@STDOUT\nout\n@STDERR\nerr\n[2]\n", "@STDERR\nerr\n\n@STDOUT\nout\n[2]\n",
    ] {
    assert_streams(body, "out\n", "err\n", 2, true)
    assert_streams(body, "wrong\n", "err\n", 2, false)
    assert_streams(body, "out\n", "wrong\n", 2, false)
    assert_streams(body, "out\n", "err\n", 0, false)
  }
}

///|
test "stream constraints distinguish empty from newline and keep ignore content unchecked" {
  for body in ["@STDOUT\n@STDERR (empty)\n", "@STDERR\n@STDOUT (empty)\n"] {
    assert_streams(body, "", "", 0, true)
    assert_streams(body, "\n", "", 0, false)
    assert_streams(body, "", "\n", 0, false)
  }
  assert_streams(
    "@STDOUT (ignore)\n@STDERR (empty)\n", "any\ntext", "", 0, true,
  )
  assert_streams(
    "@STDOUT (empty)\n@STDERR (ignore)\n", "", "any\ntext", 0, true,
  )
  assert_streams(
    "@STDOUT (ignore)\n@STDERR (ignore)\n", "anything", "anything", 1, false,
  )
  assert_streams(
    "@STDOUT\n\"\" (escaped)\n@STDERR\n\"\" (escaped)\n", "\n", "\n", 0, true,
  )
}

///|
test "each stream has independent patterns and final newline" {
  let body = "@STDOUT\nv* (glob) (no-eol)\n\n@STDERR\nerror [0-9]+ (regex)\n\"@STDOUT (empty)\" (escaped) (no-eol)\n"
  assert_streams(body, "version", "error 42\n@STDOUT (empty)", 0, true)
  assert_streams(body, "version\n", "error 42\n@STDOUT (empty)", 0, false)
  assert_streams(body, "version", "error 42\n@STDOUT (empty)\n", 0, false)
  assert_streams(
    "@STDERR\nerr (no-eol)\n@STDOUT\nout\n", "out\n", "err", 0, true,
  )
  assert_streams(
    "@STDOUT\nout (no-eol)\n@STDERR\nerr\n", "out", "err\n", 0, true,
  )
  assert_output("\"@STDERR\" (escaped)\n", "@STDERR\n", 0, true)
  assert_output("@stdout\n@STDOUTish\n", "@stdout\n@STDOUTish\n", 0, true)
}

///|
test "stream parser rejects malformed pairs and reports exact source positions" {
  for
    (body, message) in [
      ("@STDOUT\n", "example.md:3: @STDOUT and @STDERR must both appear once"),
      (
        "@STDERR (ignore)\n", "example.md:3: @STDOUT and @STDERR must both appear once",
      ),
      ("@STDOUT\n@STDERR\n@STDOUT\n", "example.md:5: duplicate @STDOUT"),
      ("@STDERR\n@STDERR (empty)\n", "example.md:4: duplicate @STDERR"),
      (
        "old\n@STDOUT\n@STDERR\n", "example.md:3: expected output before a stream marker",
      ),
      (
        "@STDOUT (glob)\n@STDERR\n", "example.md:3: unknown stream marker annotation",
      ),
      (
        "@STDOUT\n@STDERR (EMPTY)\n", "example.md:4: unknown stream marker annotation",
      ),
      (
        "@STDOUT\n@STDERR (ignore) \n", "example.md:4: unknown stream marker annotation",
      ),
      ("@STDOUT (empty)\nx\n@STDERR\n", "example.md:4: (ignore) and (empty)"),
      (
        "@STDOUT\n@STDERR (ignore)\n\"\" (escaped)\n", "example.md:5: (ignore) and (empty)",
      ),
      ("@STDOUT\na (no-eol)\nb\n@STDERR\n", "example.md:5: (no-eol)"),
      (
        "@STDOUT\n@STDERR\n\"\" (escaped) (no-eol)\n", "example.md:5: an empty output line",
      ),
    ] {
    assert_error_contains(
      () => ignore(parse_example("$ ./a.mbtx\n" + body)),
      message,
    )
  }
  // Error positions also survive Markdown container prefixes.
  assert_error_contains(
    () => {
      ignore(
        @markdown.parse_document(
          "quote.md", "> ```mooncram\n> $ ./a.mbtx\n> @STDERR (unknown)\n> ```\n",
        ),
      )
    },
    "quote.md:3: unknown stream marker annotation",
  )
}
