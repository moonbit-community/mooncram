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
  code : Int32,
  matches : Bool,
) -> Unit raise {
  let expected = parse_example("$ moonx ./a.mbtx\n" + body).cases[0].expected
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
test "line counts distinguish empty output trailing blanks and final newlines" {
  for
    (body, matching_output) in [
      ("", ""),
      ("\"\" (escaped)\n", "\n"),
      ("\"\" (escaped)\n\"\" (escaped)\n", "\n\n"),
      ("a (no-eol)\n", "a"),
      ("a\n", "a\n"),
      ("a\n\"\" (escaped)\n", "a\n\n"),
    ] {
    for output in ["", "\n", "\n\n", "a", "a\n", "a\n\n"] {
      assert_output(body, output, 0, output == matching_output)
    }
  }
}

///|
test "line matching rejects missing extra and mismatched lines" {
  let body = "a\nb\nc\n"
  assert_output(body, "a\nb\nc\n", 0, true)
  for
    output in [
      "x\nb\nc\n", "a\nx\nc\n", "a\nb\nx\n", "a\nb\n", "a\nb\nc\nd\n", "a\nb\nc\n\n",
    ] {
    assert_output(body, output, 0, false)
  }
}

///|
test "empty line matchers require an actual line" {
  for line in ["\"\" (escaped)", "* (glob)", ".* (regex)"] {
    let body = "a\n" + line + "\n"
    assert_output(body, "a\n\n", 0, true)
    assert_output(body, "a\n", 0, false)
    assert_output(body, "a\n\n\n", 0, false)
    assert_output(body + "b\n", "a\n\nb\n", 0, true)
    assert_output(body + "b\n", "a\nb\n", 0, false)
  }
  for line in ["* (glob)", ".* (regex)"] {
    let body = line + " (no-eol)\n"
    assert_output(body, "x", 0, true)
    assert_output(body, "", 0, false)
    assert_output(body, "\n", 0, false)
    assert_output("a\n" + body, "a\nx", 0, true)
    assert_output("a\n" + body, "a\n", 0, false)
    assert_output("a\n" + body, "a\n\n", 0, false)
  }
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
    "\"$ moonx ./looks-like-command\" (escaped)\n\"[1]\" (escaped)\n", "$ moonx ./looks-like-command\n[1]\n",
    0, true,
  )
  assert_output("\"literal (glob)\" (escaped)\n", "literal (glob)\n", 0, true)
  assert_error_contains(
    () => ignore(parse_example("$ moonx ./a.mbtx\na (no-eol)\nb\n")),
    "example.md:4:",
  )
  assert_error_contains(
    () => ignore(parse_example("$ moonx ./a.mbtx\n\"\" (escaped) (no-eol)\n")),
    "empty output line",
  )
  assert_error_contains(
    () => ignore(parse_example("$ moonx ./a.mbtx\nnot-json (escaped)\n")),
    "JSON string",
  )
  assert_error_contains(
    () => ignore(parse_example("$ moonx ./a.mbtx\n\"a\\nb\" (escaped)\n")),
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
      () => ignore(parse_example("$ moonx ./a.mbtx\n" + pattern + " (glob)\n")),
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
    () => ignore(parse_example("$ moonx ./a.mbtx\n[ (regex)\n")),
    "example.md:3: invalid regex",
  )
}

///|
test "glob and regex match whole Unicode lines at nonzero offsets" {
  for
    (middle, last) in [
      ("中? [0-9] (glob)", "尾. (?:甲|乙) (regex)"),
      ("中. [0-9] (regex)", "尾? [甲乙] (glob)"),
    ] {
    for (annotation, eol) in [("", "\n"), (" (no-eol)", "")] {
      let body = "前😀\n" + middle + "\n" + last + annotation + "\n"
      assert_output(body, "前😀\n中😀 7\n尾🚀 乙" + eol, 0, true)
      for
        output in [
          "前😀\nx中😀 7\n尾🚀 乙", "前😀\n中😀 7x\n尾🚀 乙",
          "前😀\n中😀 7\nx尾🚀 乙", "前😀\n中😀 7\n尾🚀 乙x",
          "前😀\n中😀😀 7\n尾🚀 乙", "前😀\n中😀 7\n尾🚀🚀 乙",
        ] {
        assert_output(body, output + eol, 0, false)
      }
    }
  }
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
  code : Int32,
  matches : Bool,
) -> Unit raise {
  let expected = parse_example("$ moonx ./a.mbtx\n" + body).cases[0].expected
  assert_eq(
    expected.matches({ output: stdout, diagnostic: stderr, exit_code: code, }),
    matches,
  )
}

///|
test "matching preserves Unicode whitespace and CR without normalization" {
  let body = "\"中文😀  \" (escaped)\n\"\\t\\r\\t  \" (escaped)\n\"末行🚀\\r\" (escaped) (no-eol)\n"
  assert_streams(body, "中文😀  \n\t\r\t  \n末行🚀\r", "", 0, true)
  assert_streams(body, "中文😀 \n\t\r\t  \n末行🚀\r", "", 0, false)
  assert_streams(body, "中文😀  \n\t\t  \n末行🚀\r", "", 0, false)
  assert_streams(body, "中文😀  \n\t\r\t  \n末行🚀", "", 0, false)
  assert_streams("a\n", "a\r\n", "", 0, false)
  assert_streams("\"a\\r\" (escaped)\n", "a\r\n", "", 0, true)
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
test "paired multiline streams check content line counts and final newline" {
  for (out_annotation, out_eol) in [("", "\n"), (" (no-eol)", "")] {
    for (err_annotation, err_eol) in [("", "\n"), (" (no-eol)", "")] {
      let body = "@STDOUT\n前😀\n中? (glob)\n尾. (regex)" +
        out_annotation +
        "\n@STDERR\n警告\n代碼 [0-9]+ (regex)\n終? (glob)" +
        err_annotation +
        "\n"
      let stdout = "前😀\n中😀\n尾🚀" + out_eol
      let stderr = "警告\n代碼 42\n終😀" + err_eol
      assert_streams(body, stdout, stderr, 0, true)
      for
        output in [
          "錯誤\n中😀\n尾🚀", "前😀\n錯誤\n尾🚀", "前😀\n中😀\n錯誤",
          "前😀\n中😀", "前😀\n中😀\n尾🚀\nextra",
        ] {
        assert_streams(body, output + out_eol, stderr, 0, false)
      }
      for
        diagnostic in [
          "錯誤\n代碼 42\n終😀", "警告\n錯誤\n終😀", "警告\n代碼 42\n錯誤",
          "警告\n代碼 42", "警告\n代碼 42\n終😀\nextra",
        ] {
        assert_streams(body, stdout, diagnostic + err_eol, 0, false)
      }
      let wrong_out_eol = if out_eol == "" { "\n" } else { "" }
      let wrong_err_eol = if err_eol == "" { "\n" } else { "" }
      assert_streams(
        body,
        "前😀\n中😀\n尾🚀" + wrong_out_eol,
        stderr,
        0,
        false,
      )
      assert_streams(
        body,
        stdout,
        "警告\n代碼 42\n終😀" + wrong_err_eol,
        0,
        false,
      )
    }
  }
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
      () => ignore(parse_example("$ moonx ./a.mbtx\n" + body)),
      message,
    )
  }
  // Error positions also survive Markdown container prefixes.
  assert_error_contains(
    () => {
      ignore(
        @markdown.parse_document(
          "quote.md", "> ```mooncram\n> $ moonx ./a.mbtx\n> @STDERR (unknown)\n> ```\n",
        ),
      )
    },
    "quote.md:3: unknown stream marker annotation",
  )
}
