///|
fn parse_example(body : String) -> Document raise {
  parse_document(
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
test "command quoting and literal expansion characters" {
  assert_eq(
    parse_command("./hello.mbtx 'Moon Bit' \"a b\" x\\ y '' \"\" a\"b\"c"),
    ["./hello.mbtx", "Moon Bit", "a b", "x y", "", "", "abc"],
  )
  assert_eq(parse_command("./a.mbtx '$HOME' * ~ \"$(cmd)\" '|' \\> 'a\\b'"), [
    "./a.mbtx", "$HOME", "*", "~", "$(cmd)", "|", ">", "a\\b",
  ])
  assert_eq(parse_command("./脚本.mbtx 😀\t\"a\\\"b\""), [
    "./脚本.mbtx", "😀", "a\"b",
  ])
}

///|
test "command rejects shell operators and incomplete arguments" {
  for operator in ["|", ">", "<", ";", "&&", "||", "&", "`", "$(whoami)"] {
    assert_error_contains(
      () => ignore(parse_command("./a.mbtx " + operator)),
      "shell operator",
    )
  }
  assert_error_contains(
    () => ignore(parse_command("./a.mbtx '")),
    "unclosed quote",
  )
  assert_error_contains(
    () => ignore(parse_command("./a.mbtx \\")),
    "trailing backslash",
  )
  assert_error_contains(() => ignore(parse_command("''")), "expected a local")
  assert_error_contains(() => ignore(parse_command("./a.mbtx \u0000")), "NUL")
}

///|
test "mixed Markdown skips other languages tilde fences and enclosing examples" {
  let source = "# Heading\n\n```text\n$ ignored\n```\n\n~~~~mooncram\n$ ignored\n~~~~\n\n````markdown\n```mooncram\n$ ignored\n```\n````\n\n```mooncram\n$ ./a.mbtx\nhello\n\n$ ./b.mbtx\n[2]\n```\n"
  let doc = parse_document("mixed.md", source, @config.default_config())
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
    () => {
      ignore(
        parse_document(
          "x.md",
          "text\n\n```mooncram\n$ ./a.mbtx\n",
          @config.default_config(),
        ),
      )
    },
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
test "configuration defaults overrides and validation" {
  let base = { ..@config.default_config(), target: "native", timeout_ms: 123, }
  let config = @config.parse_config(
    "{\"stream\":\"merged\",\"stdin\":\"./input\",\"env\":{\"MODE\":\"test\"}}",
    base,
  )
  assert_eq(config.target, "native")
  assert_eq(config.timeout_ms, 123)
  assert_true(config.stream is Merged)
  assert_eq(config.stdin, Some("./input"))
  assert_eq(config.env["MODE"], "test")
  let config = @config.parse_config(
    "{\"target\":\"wasm\",\"timeout_ms\":12}", base,
  )
  assert_eq(config.target, "wasm")
  assert_eq(config.timeout_ms, 12)
  for
    settings in [
      "[]", "{", "{\"typo\":1}", "{\"timeout_ms\":0}", "{\"timeout_ms\":1.5}", "{\"timeout_ms\":2147483648}",
      "{\"target\":\"js\"}", "{\"stream\":\"both\"}", "{\"stdin\":null}", "{\"env\":{\"A\":1}}",
      "{\"env\":{\"A=B\":\"x\"}}",
    ] {
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "bad.md",
            "\n```mooncram " + settings + "\n$ ./a.mbtx\n```\n",
            base,
          ),
        )
      },
      "bad.md:2:",
    )
  }
}
