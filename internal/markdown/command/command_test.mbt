///|
fn plain_pipeline(argvs : Array[Array[String]]) -> @command.Command {
  @command.Pipeline(
    argvs.map(argv => { argv, stderr_to_stdout: false, stdout_to_null: false, }),
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
    @command.parse("./hello.mbtx 'Moon Bit' \"a b\" x\\ y '' \"\" a\"b\"c"),
    plain_pipeline([["./hello.mbtx", "Moon Bit", "a b", "x y", "", "", "abc"]]),
  )
  assert_eq(
    @command.parse("./a.mbtx '$HOME' * ~ \"$(cmd)\" '|' \\> 'a\\b'"),
    plain_pipeline([["./a.mbtx", "$HOME", "*", "~", "$(cmd)", "|", ">", "a\\b"]]),
  )
  assert_eq(
    @command.parse("./脚本.mbtx 😀\t\"a\\\"b\""),
    plain_pipeline([["./脚本.mbtx", "😀", "a\"b"]]),
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
      plain_pipeline([["./a.mbtx", "x"], ["./cmd/filter"], ["./b.mbtx"]]),
    )
  }
  assert_eq(
    @command.parse("./a.mbtx '|' \"|\" \\| a\\|b|./b.mbtx 'x|y'"),
    plain_pipeline([["./a.mbtx", "|", "|", "|", "a|b"], ["./b.mbtx", "x|y"]]),
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
    plain_pipeline([
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
    plain_pipeline([["./a.mbtx", "Moon Bit|'\""], ["./b.mbtx", ""]]),
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
    plain_pipeline([["${PATH}"], ["./${PATH}.mbtx"], ["${PATH}"]]),
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

///|
test "redirection routes every segment and combinations ignore order" {
  for
    (suffix, stderr_to_stdout, stdout_to_null) in [
      ("2>&1", true, false),
      (">/dev/null", false, true),
      ("2>&1 >/dev/null", true, true),
      (">/dev/null 2>&1", true, true),
    ] {
    for count in [1, 3] {
      for position in 0..<count {
        for whitespace in [" ", "\t", " \t "] {
          let commands = Array::make(count, "./a.mbtx arg")
          commands[position] += whitespace + suffix
          let expected : Array[@command.PipelineSegment] = Array::makei(count, i => {
            argv: ["./a.mbtx", "arg"],
            stderr_to_stdout: i == position && stderr_to_stdout,
            stdout_to_null: i == position && stdout_to_null,
          })
          // A marker can touch the following pipe, but requires preceding space.
          assert_eq(
            @command.parse(commands.join("|")),
            @command.Pipeline(expected),
          )
        }
      }
    }
  }
}

///|
test "quoted escaped and expanded markers remain ordinary arguments" {
  for marker in ["2>&1", ">/dev/null"] {
    for
      literal in [
        "'" + marker + "'",
        "\"" + marker + "\"",
        marker.replace(old=">", new="\\>").replace(old="&", new="\\&"),
      ] {
      assert_eq(
        @command.parse("./a.mbtx " + literal + " after"),
        plain_pipeline([["./a.mbtx", marker, "after"]]),
      )
    }
    assert_eq(
      @command.parse("./a.mbtx ${MARKER} \"${MARKER}\" after", lookup=_ => {
        Some(marker)
      }),
      plain_pipeline([["./a.mbtx", marker, marker, "after"]]),
    )
  }
  assert_eq(
    @command.parse("./a.mbtx '${MARKER}' \\${MARKER} 2>&1"),
    @command.Pipeline([
      {
        argv: ["./a.mbtx", "${MARKER}", "${MARKER}"],
        stderr_to_stdout: true,
        stdout_to_null: false,
      },
    ]),
  )
}

///|
test "redirection rejects missing commands duplicates trailing args and exports" {
  for command in ["2>&1", ">/dev/null", "2>&1 >/dev/null", "./a.mbtx|2>&1"] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "empty pipeline segment",
    )
  }
  for marker in ["2>&1", ">/dev/null"] {
    assert_error_contains(
      () => ignore(@command.parse("./a.mbtx " + marker + " " + marker)),
      "duplicate " + marker + " redirection",
    )
    assert_error_contains(
      () => ignore(@command.parse("./a.mbtx " + marker + " arg")),
      "ordinary arguments",
    )
    assert_error_contains(
      () => ignore(@command.parse("./a.mbtx " + marker + " '${MARKER}'")),
      "ordinary arguments",
    )
    assert_error_contains(
      () => ignore(@command.parse("export A=x " + marker)),
      "export does not accept redirection",
    )
  }
  assert_error_contains(
    () => ignore(@command.parse("./a.mbtx 2>&1 >/dev/null 2>&1")),
    "duplicate 2>&1 redirection",
  )
  assert_error_contains(
    () => ignore(@command.parse("./a.mbtx >/dev/null 2>&1 >/dev/null")),
    "duplicate >/dev/null redirection",
  )
}

///|
test "redirection requires exact raw tokens and whitespace boundaries" {
  for
    invalid in [
      "arg2>&1", "arg>/dev/null", "2 >&1", "2> &1", "2>& 1", "2>\t&1", "2>&\t1",
      "> /dev/null", ">\t/dev/null", "2>&1>/dev/null", ">/dev/null2>&1", "2>&1'arg'",
      ">/dev/null\"\"", "2>&1/file", ">/dev/null/file", "2\\>&1", "2>\\&1", "'2'>&1",
      ">/'dev/null'", "2>&${FD}", ">/dev/${NULL}", "stderr>/stdout", "stdout>/null",
      "stderr >/stdout", "stderr> /stdout", "stderr>stdout", "stdout>null", "stderr>/null",
      "stdout>/stdout", ">/null", "stderr>>/stdout", "'stderr'>/stdout", "stdout>/'null'",
      "stderr>/std${SUFFIX}",
    ] {
    assert_error_contains(
      () => ignore(@command.parse("./a.mbtx " + invalid)),
      "shell operator",
    )
  }
  assert_error_contains(
    () => ignore(@command.parse("./a.mbtx2>&1")),
    "shell operator",
  )
  assert_error_contains(
    () => ignore(@command.parse("./a.mbtx>/dev/null")),
    "shell operator",
  )
}
