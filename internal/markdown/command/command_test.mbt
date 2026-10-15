///|
fn plain_pipeline(argvs : Array[Array[String]]) -> @command.Command {
  @command.Pipeline(
    argvs.map(argv => { argv: ["moonx"] + argv, extra_env: Map([]), }),
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
    @command.parse(
      "moonx ./hello.mbtx 'Moon Bit' \"a b\" x\\ y '' \"\" a\"b\"c",
    ),
    plain_pipeline([["./hello.mbtx", "Moon Bit", "a b", "x y", "", "", "abc"]]),
  )
  assert_eq(
    @command.parse("moonx ./a.mbtx '$HOME' * ~ \"$(cmd)\" '|' \\> 'a\\b'"),
    plain_pipeline([["./a.mbtx", "$HOME", "*", "~", "$(cmd)", "|", ">", "a\\b"]]),
  )
  assert_eq(
    @command.parse("moonx ./脚本.mbtx 😀\t\"a\\\"b\""),
    plain_pipeline([["./脚本.mbtx", "😀", "a\"b"]]),
  )
}

///|
test "command rejects shell operators and incomplete arguments" {
  for operator in [">", "<", ";", "&&", "&", "`", "$(whoami)"] {
    assert_error_contains(
      () => ignore(@command.parse("moonx ./a.mbtx " + operator)),
      "shell operator",
    )
  }
  assert_error_contains(
    () => ignore(@command.parse("moonx ./a.mbtx '")),
    "unclosed quote",
  )
  assert_error_contains(
    () => ignore(@command.parse("moonx ./a.mbtx \\")),
    "trailing backslash",
  )
  assert_error_contains(() => ignore(@command.parse("''")), "expected moonx")
  assert_error_contains(
    () => ignore(@command.parse("moonx ./a.mbtx \u0000")),
    "NUL",
  )
}

///|
test "pipelines split only unquoted unescaped separators" {
  for
    command in [
      "moonx ./a.mbtx x | moonx ./cmd/filter | moonx ./b.mbtx", "moonx ./a.mbtx x|moonx ./cmd/filter|moonx ./b.mbtx",
    ] {
    assert_eq(
      @command.parse(command),
      plain_pipeline([["./a.mbtx", "x"], ["./cmd/filter"], ["./b.mbtx"]]),
    )
  }
  assert_eq(
    @command.parse("moonx ./a.mbtx '|' \"|\" \\| a\\|b|moonx ./b.mbtx 'x|y'"),
    plain_pipeline([["./a.mbtx", "|", "|", "|", "a|b"], ["./b.mbtx", "x|y"]]),
  )
}

///|
test "pipelines reject empty segments and targets" {
  for
    command in [
      "", "|moonx ./a.mbtx", "moonx ./a.mbtx|", "moonx ./a.mbtx||moonx ./b.mbtx",
      "moonx ./a.mbtx | | moonx ./b.mbtx",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "empty pipeline segment",
    )
  }
  for command in ["'' | moonx ./a.mbtx", "moonx ./a.mbtx | \"\""] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "expected moonx",
    )
  }
}

///|
test "variable-like text stays literal through quoting escaping and concatenation" {
  assert_eq(
    @command.parse(
      "moonx ./a.mbtx ${VALUE} \"${VALUE}\" '${VALUE}' \\${VALUE} \"\\${VALUE}\" pre${VALUE}post a\"${EMPTY}\"b '$VAR' $VAR",
    ),
    plain_pipeline([
      [
        "./a.mbtx", "${VALUE}", "${VALUE}", "${VALUE}", "${VALUE}", "${VALUE}", "pre${VALUE}post",
        "a${EMPTY}b", "$VAR", "$VAR",
      ],
    ]),
  )
  assert_eq(
    @command.parse("moonx ./a.mbtx ${VALUE}|moonx ./b.mbtx ${EMPTY}"),
    plain_pipeline([["./a.mbtx", "${VALUE}"], ["./b.mbtx", "${EMPTY}"]]),
  )
}

///|
test "variable-like text has no reference validation and uses ordinary token rules" {
  for
    text in [
      "${}", "${1A}", "${A-B}", "${名}", "${${A}}", "${A=B}", "${UNCLOSED",
    ] {
    for argument in [text, "'" + text + "'", "\"" + text + "\""] {
      assert_eq(
        @command.parse("moonx ./a.mbtx " + argument),
        plain_pipeline([["./a.mbtx", text]]),
      )
      assert_eq(segments("A=" + argument + " moonx ./a.mbtx")[0].extra_env, {
        "A": text,
      })
    }
  }
  assert_eq(
    @command.parse("moonx ./a.mbtx ${A B} ${A|moonx B}"),
    plain_pipeline([["./a.mbtx", "${A", "B}", "${A"], ["B}"]]),
  )
  assert_eq(
    @command.parse("moonx ./a.mbtx '${A B}' \"${A|B}\""),
    plain_pipeline([["./a.mbtx", "${A B}", "${A|B}"]]),
  )
  assert_error_contains(
    () => ignore(@command.parse("moonx ./a.mbtx \"${A")),
    "unclosed quote",
  )
  assert_error_contains(
    () => ignore(@command.parse("moonx ./a.mbtx ${A>B}")),
    "shell operator",
  )
}

///|
test "executable paths retain variable-like text" {
  assert_eq(
    @command.parse(
      "moonx ${PATH}|moonx ./${PATH}.mbtx arg|moonx \"${PATH}\"|moonx '${PATH}'|moonx ./\\${PATH}.mbtx",
    ),
    plain_pipeline([
      ["${PATH}"],
      ["./${PATH}.mbtx", "arg"],
      ["${PATH}"],
      ["${PATH}"],
      ["./${PATH}.mbtx"],
    ]),
  )
}

///|
test "redirection is rejected in every pipeline segment" {
  for suffix in ["2>&1", "1>/dev/null", "2>&1 1>/dev/null", "1>/dev/null 2>&1"] {
    for count in [1, 2, 3] {
      for position in 0..<count {
        for whitespace in [" ", "\t", " \t "] {
          let commands = Array::make(count, "moonx ./a.mbtx arg")
          commands[position] += whitespace + suffix
          assert_error_contains(
            () => ignore(@command.parse(commands.join("|"))),
            "unquoted shell operator",
          )
        }
      }
    }
  }
}

///|
test "quoted escaped and variable-like markers remain ordinary arguments" {
  for marker in ["2>&1", "1>/dev/null"] {
    for
      literal in [
        "'" + marker + "'",
        "\"" + marker + "\"",
        marker.replace(old=">", new="\\>").replace(old="&", new="\\&"),
      ] {
      assert_eq(
        @command.parse("moonx ./a.mbtx " + literal + " after"),
        plain_pipeline([["./a.mbtx", marker, "after"]]),
      )
    }
  }
  assert_eq(
    @command.parse(
      "moonx ./a.mbtx ${MARKER} '${MARKER}' \\${MARKER}|moonx ./b.mbtx",
    ),
    plain_pipeline([
      ["./a.mbtx", "${MARKER}", "${MARKER}", "${MARKER}"],
      ["./b.mbtx"],
    ]),
  )
}

///|
test "raw redirections are shell operators in commands and configuration" {
  for
    command in [
      "2>&1", "1>/dev/null", "moonx ./a.mbtx|2>&1", "moonx ./a.mbtx 2>&1 arg", "moonx ./a.mbtx 1>/dev/null B=y",
      "set-current-working-directory dir 2>&1",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "shell operator",
    )
  }
}

///|
test "redirection operators are rejected even when attached or partially escaped" {
  for
    invalid in [
      "arg2>&1", "arg1>/dev/null", "2 >&1", "2> &1", "2>& 1", "2>\t&1", "2>&\t1",
      "1> /dev/null", "1>\t/dev/null", "2>&11>/dev/null", "1>/dev/null2>&1", "2>&1'arg'",
      "1>/dev/null\"\"", "2>&1/file", "1>/dev/null/file", "2\\>&1", "2>\\&1", "'2'>&1",
      "1>/'dev/null'", "2>&${FD}", "1>/dev/${NULL}", "stderr>/stdout", "stdout>/null",
      "stderr >/stdout", "stderr> /stdout", "stderr>stdout", "stdout>null", "stderr>/null",
      "stdout>/stdout", ">/null", "stderr>>/stdout", "'stderr'>/stdout", "stdout>/'null'",
      "stderr>/std${SUFFIX}", ">/dev/null", "2>/dev/null", "'1'>/dev/null",
    ] {
    assert_error_contains(
      () => ignore(@command.parse("moonx ./a.mbtx " + invalid)),
      "shell operator",
    )
  }
  assert_error_contains(
    () => ignore(@command.parse("moonx ./a.mbtx2>&1")),
    "shell operator",
  )
  assert_error_contains(
    () => ignore(@command.parse("moonx ./a.mbtx1>/dev/null")),
    "shell operator",
  )
}

///|
test "working directory takes one nonempty literal argument with normal quoting" {
  for
    (argument, directory) in [
      ("../fixtures", "../fixtures"),
      ("'/absolute path'", "/absolute path"),
      ("a\\ b", "a b"),
      ("\"pre${DIR}/post\"", "pre${DIR}/post"),
      ("${DIR}", "${DIR}"),
      ("'${MISSING}'", "${MISSING}"),
      ("\\${MISSING}", "${MISSING}"),
      ("'2>&1'", "2>&1"),
    ] {
    assert_eq(
      @command.parse("set-current-working-directory " + argument),
      @command.SetCurrentWorkingDirectory(directory~),
    )
  }
  for argument in ["", "''", "\"\"", "a b"] {
    assert_error_contains(
      () => ignore(@command.parse("set-current-working-directory " + argument)),
      "exactly one nonempty directory argument",
    )
  }
  for
    command in [
      "set-current-working-directory dir|moonx ./a.mbtx", "moonx ./a.mbtx|set-current-working-directory dir",
      "moonx ./a.mbtx|set-current-working-directory dir|moonx ./b.mbtx",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "is not allowed in a pipeline",
    )
  }
  for marker in ["2>&1", "1>/dev/null", "2>&1 1>/dev/null"] {
    assert_error_contains(
      () => {
        ignore(@command.parse("set-current-working-directory dir " + marker))
      },
      "shell operator",
    )
  }
}

///|
test "commands require explicit moonx and a nonempty target" {
  for
    command in [
      "./a.mbtx", "user/foo", "tool arg", "NAME=x ./a.mbtx", "moonx ./a.mbtx|tool",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "must start with moonx",
    )
  }
  for
    command in [
      "moonx", "moonx ''", "moonx \"\"", "A=x moonx", "moonx ./a.mbtx|moonx",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "requires a nonempty target",
    )
  }
  assert_eq(
    @command.parse("moonx ./a.mbtx -- --target native"),
    plain_pipeline([["./a.mbtx", "--", "--target", "native"]]),
  )
}

///|
test "export is an unsupported executable but remains an ordinary argument" {
  for
    command in [
      "export", "export A=x", "export A=", "export A='Moon Bit'", "export A=x B=y",
      "A=x export B=y", "export A=x|moonx ./a.mbtx", "moonx ./a.mbtx|export A=x",
      "moonx ./a.mbtx|export A=x|moonx ./b.mbtx",
    ] {
    assert_error_contains(
      () => ignore(@command.parse(command)),
      "command must start with moonx: export",
    )
  }
  assert_eq(
    @command.parse("moonx ./a.mbtx export A=x"),
    plain_pipeline([["./a.mbtx", "export", "A=x"]]),
  )
}
