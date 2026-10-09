///|
fn parse_example(body : String) -> Document raise {
  parse_document("example.md", "```mooncram\n" + body + "```\n")
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
test "mixed Markdown skips other languages tilde fences and enclosing examples" {
  let source = "# Heading\n\n```text\n$ ignored\n```\n\n~~~~mooncram\n$ ignored\n~~~~\n\n````markdown\n```mooncram\n$ ignored\n```\n````\n\n```mooncram\n$ ./a.mbtx\nhello\n\n$ ./b.mbtx\n[2]\n```\n"
  let doc = parse_document("mixed.md", source)
  assert_eq(doc.cases.length(), 2)
  assert_eq(doc.cases[0].line, 18)
  assert_eq(doc.cases[0].expected.lines[0].raw, "hello")
  assert_eq(doc.cases[1].expected.exit_code, 2)
  assert_eq(doc.cases[1].expected.lines.length(), 0)
}

///|
test "empty and unclosed test blocks have accurate errors" {
  assert_error_contains(
    () => ignore(parse_example("\n")),
    "example.md:1: empty",
  )
  assert_error_contains(
    () => ignore(parse_document("x.md", "text\n\n```mooncram\n$ ./a.mbtx\n")),
    "x.md:3: unclosed",
  )
  assert_error_contains(
    () => ignore(parse_example("unexpected\n")),
    "example.md:2: expected a command",
  )
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx | x\n")),
    "example.md:2: unquoted",
  )
  assert_error_contains(() => ignore(parse_example("$\n")), "example.md:2:")
}

///|
test "only bare mooncram info strings are recognized" {
  let source = "```mooncram\n$ ./bare.mbtx\n```\n\n```mooncram   \n$ ./spaces.mbtx\n```\n\n```mooncram {\"target\":\"native\"}\n$ ./json.mbtx\n```\n\n```mooncram {\n$ ./invalid-json.mbtx\n```\n\n```mooncram trailing text\n$ ./text.mbtx\n```\n"
  let doc = parse_document("strict.md", source)
  assert_eq(doc.cases.length(), 2)
  assert_eq(doc.cases[0].argv[0], "./bare.mbtx")
  assert_eq(doc.cases[1].argv[0], "./spaces.mbtx")
}

///|
test "ignored legacy fences do not produce parse errors" {
  for suffix in [" {\"stream\":\"stderr\"}", " {", " anything"] {
    let doc = parse_document(
      "ignored.md",
      "```mooncram" + suffix + "\nnot a command\n",
    )
    assert_eq(doc.cases.length(), 0)
  }
}
