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
    @command.Pipeline([
      ["./hello.mbtx", "Moon Bit", "a b", "x y", "", "", "abc"],
    ]),
  )
  assert_eq(
    @command.parse("./a.mbtx '$HOME' * ~ \"$(cmd)\" '|' \\> 'a\\b'"),
    @command.Pipeline([
      ["./a.mbtx", "$HOME", "*", "~", "$(cmd)", "|", ">", "a\\b"],
    ]),
  )
  assert_eq(
    @command.parse("./脚本.mbtx 😀\t\"a\\\"b\""),
    @command.Pipeline([["./脚本.mbtx", "😀", "a\"b"]]),
  )
}

///|
test "command rejects shell operators and incomplete arguments" {
  for operator in [">", "<", ";", "&&", "&", "`", "$(whoami)"] {
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

///|
test "pipelines split only unquoted unescaped separators" {
  for
    command in [
      "./a.mbtx x | ./cmd/filter | ./b.mbtx", "./a.mbtx x|./cmd/filter|./b.mbtx",
    ] {
    assert_eq(
      @command.parse(command),
      @command.Pipeline([["./a.mbtx", "x"], ["./cmd/filter"], ["./b.mbtx"]]),
    )
  }
  assert_eq(
    @command.parse("./a.mbtx '|' \"|\" \\| a\\|b|./b.mbtx 'x|y'"),
    @command.Pipeline([["./a.mbtx", "|", "|", "|", "a|b"], ["./b.mbtx", "x|y"]]),
  )
}

///|
test "pipelines reject empty segments and targets" {
  for
    command in [
      "", "|./a.mbtx", "./a.mbtx|", "./a.mbtx||./b.mbtx", "./a.mbtx | | ./b.mbtx",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "empty pipeline segment",
    )
  }
  for command in ["'' | ./a.mbtx", "./a.mbtx | \"\""] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "expected a local",
    )
  }
}

///|
test "export assigns one valid name and preserves empty values and equals" {
  for name in ["A", "_", "_a9", "Camel_case12"] {
    assert_eq(
      @command.parse("export " + name + "="),
      @command.Export(name~, value=""),
    )
  }
  assert_eq(
    @command.parse("export NAME=a=b=c"),
    @command.Export(name="NAME", value="a=b=c"),
  )
  assert_eq(
    @command.parse("export NAME='Moon Bit|\"quoted\"'"),
    @command.Export(name="NAME", value="Moon Bit|\"quoted\""),
  )
  assert_eq(
    @command.parse("export NAME=\"a b\""),
    @command.Export(name="NAME", value="a b"),
  )
  for
    command in [
      "export", "export A", "export =x", "export 9A=x", "export A-B=x", "export 名=x",
      "export A=x B=y", "export A =x", "export ${NAME}=x",
    ] {
    assert_error_contains(() => ignore(@command.parse(command)), "export")
  }
}

///|
test "references expand once without splitting and concatenate with literal fragments" {
  let env = Map::from_array([
    ("VALUE", "Moon Bit|'\""),
    ("EMPTY", ""),
    ("NESTED", "${UNDEFINED}"),
    ("NAME", "before"),
  ])
  assert_eq(
    @command.parse(
      "./a.mbtx ${VALUE} \"${VALUE}\" pre${VALUE}post ${EMPTY} \"${EMPTY}\" a${EMPTY}b ${NESTED} '$VAR' $VAR '${MISSING}' \\${MISSING} \"\\${MISSING}\"",
      lookup=name => env.get(name),
    ),
    @command.Pipeline([
      [
        "./a.mbtx", "Moon Bit|'\"", "Moon Bit|'\"", "preMoon Bit|'\"post", "", "",
        "ab", "${UNDEFINED}", "$VAR", "$VAR", "${MISSING}", "${MISSING}", "${MISSING}",
      ],
    ]),
  )
  assert_eq(
    @command.parse("export NAME=${NAME}-after", lookup=name => env.get(name)),
    @command.Export(name="NAME", value="before-after"),
  )
  assert_eq(
    @command.parse("export NAME=${EMPTY}", lookup=name => env.get(name)),
    @command.Export(name="NAME", value=""),
  )
  assert_eq(
    @command.parse("./a.mbtx ${VALUE}|./b.mbtx ${EMPTY}", lookup=name => {
      env.get(name)
    }),
    @command.Pipeline([["./a.mbtx", "Moon Bit|'\""], ["./b.mbtx", ""]]),
  )
}

///|
test "references reject undefined invalid and incomplete syntax" {
  for
    command in [
      "./a.mbtx ${MISSING}", "./a.mbtx \"${MISSING}\"", "export NAME=${MISSING}",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "undefined variable: MISSING",
    )
  }
  for
    reference in [
      "${}", "${1A}", "${A-B}", "${A B}", "${名}", "${${A}}", "${A|B}", "${A=B}",
    ] {
    assert_error_contains(
      () => ignore(@command.parse("./a.mbtx " + reference)),
      "invalid variable reference",
    )
  }
  for command in ["./a.mbtx ${A", "./a.mbtx \"${A", "export A=${A"] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "unclosed variable reference",
    )
  }
}

///|
test "every executable path rejects expansion but accepts protected references" {
  for
    command in [
      "${PATH}", "./${PATH}.mbtx arg", "./a.mbtx|${PATH}", "./a.mbtx|./b.mbtx|\"${PATH}\"",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command, lookup=_ => Some("./b.mbtx"))),
      "executable paths",
    )
  }
  assert_eq(
    @command.parse("'${PATH}'|./\\${PATH}.mbtx|\"\\${PATH}\""),
    @command.Pipeline([["${PATH}"], ["./${PATH}.mbtx"], ["${PATH}"]]),
  )
  for
    command in [
      "export A=x|./a.mbtx", "./a.mbtx|export A=x", "./a.mbtx|export A=x|./b.mbtx",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "export is not allowed in a pipeline",
    )
  }
}
