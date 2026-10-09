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
    @command.parse("./hello.mbtx 'Moon Bit' \"a b\" x\\ y '' \"\" a\"b\"c"),
    ["./hello.mbtx", "Moon Bit", "a b", "x y", "", "", "abc"],
  )
  assert_eq(@command.parse("./a.mbtx '$HOME' * ~ \"$(cmd)\" '|' \\> 'a\\b'"), [
    "./a.mbtx", "$HOME", "*", "~", "$(cmd)", "|", ">", "a\\b",
  ])
  assert_eq(@command.parse("./脚本.mbtx 😀\t\"a\\\"b\""), [
    "./脚本.mbtx", "😀", "a\"b",
  ])
}

///|
test "command rejects shell operators and incomplete arguments" {
  for operator in ["|", ">", "<", ";", "&&", "||", "&", "`", "$(whoami)"] {
    assert_error_contains(
      () => ignore(@command.parse("./a.mbtx " + operator)),
      "shell operator",
    )
  }
  assert_error_contains(
    () => ignore(@command.parse("./a.mbtx '")),
    "unclosed quote",
  )
  assert_error_contains(
    () => ignore(@command.parse("./a.mbtx \\")),
    "trailing backslash",
  )
  assert_error_contains(() => ignore(@command.parse("''")), "expected a local")
  assert_error_contains(() => ignore(@command.parse("./a.mbtx \u0000")), "NUL")
}
