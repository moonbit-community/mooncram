///|
fn segments(
  command : String,
  lookup~ : (String) -> String? = _ => None,
  case_insensitive~ : Bool = false,
) -> Array[@command.PipelineSegment] raise {
  guard @command.parse(command, lookup~, case_insensitive~)
    is Pipeline(segments) else {
    fail("expected pipeline")
  }
  segments
}

///|
test "temporary assignments expand left to right before arguments" {
  let env = { "A": "old", "B": "parent", "NESTED": "${MISSING}" }
  let pipeline = segments(
    "A=${A}-first B=\"${A}\" A=${A}-last EMPTY= EQUALS=a=b=c SPACES='Moon Bit|quoted' NESTED=${NESTED} ./a.mbtx ${A} \"${B}\" ${EMPTY} ${SPACES} ${NESTED} A=argument",
    lookup=name => env.get(name),
  )
  assert_eq(pipeline[0].argv, [
    "./a.mbtx", "old-first-last", "old-first", "", "Moon Bit|quoted", "${MISSING}",
    "A=argument",
  ])
  assert_eq(pipeline[0].extra_env, {
    "A": "old-first-last",
    "B": "old-first",
    "EMPTY": "",
    "EQUALS": "a=b=c",
    "SPACES": "Moon Bit|quoted",
    "NESTED": "${MISSING}",
  })
  assert_eq(env, { "A": "old", "B": "parent", "NESTED": "${MISSING}" })
  for name in ["A", "_", "_a9", "Camel_case12"] {
    assert_eq(
      segments(name + "= ./a.mbtx")[0].extra_env,
      Map::from_array([(name, "")]),
    )
  }
}

///|
test "temporary assignment values reuse quoting escaping and single expansion" {
  let pipeline = segments(
    "A='${MISSING}' B=\\${MISSING} C=\"\\${MISSING}\" D=x\\ y E=\"a b\" F=a\"b\"c ./a.mbtx ${A} ${B} ${C} ${D} ${E} ${F}",
  )
  assert_eq(pipeline[0].argv, [
    "./a.mbtx", "${MISSING}", "${MISSING}", "${MISSING}", "x y", "a b", "abc",
  ])
  assert_eq(pipeline[0].extra_env, {
    "A": "${MISSING}",
    "B": "${MISSING}",
    "C": "${MISSING}",
    "D": "x y",
    "E": "a b",
    "F": "abc",
  })
}

///|
test "quoted escaped expanded and invalid names are ordinary words" {
  for
    word in [
      "'A=x'", "\"A=x\"", "'A'=x", "A'='x", "A\\=x", "\\A=x", "A\"\"=x", "''A=x",
      "9A=x", "A-B=x", "名=x", "=x",
    ] {
    let pipeline = segments(word + " B=y ./a.mbtx", lookup=_ => Some("A=x"))
    assert_true(pipeline[0].extra_env.is_empty())
    assert_eq(pipeline[0].argv[1:], ["B=y", "./a.mbtx"])
  }
  let expanded = segments("./a.mbtx ${PREFIX} B=y", lookup=_ => Some("A=x"))[0]
  assert_eq(expanded.argv, ["./a.mbtx", "A=x", "B=y"])
  assert_true(expanded.extra_env.is_empty())
  let pipeline = segments("A=x 'B'=y C=z ./a.mbtx")
  assert_eq(pipeline[0].extra_env, { "A": "x" })
  assert_eq(pipeline[0].argv, ["B=y", "C=z", "./a.mbtx"])
  assert_eq(segments("A=x ./a.mbtx B=${A}")[0].argv, ["./a.mbtx", "B=x"])
}

///|
test "temporary assignments stay within one pipeline segment and retain routes" {
  let pipeline = segments(
    "A=first ./a.mbtx ${A} 1>/dev/null 2>&1|A=${A}-second ./b.mbtx ${A}|./c.mbtx ${A}",
    lookup=_ => Some("parent"),
  )
  assert_eq(pipeline.map(segment => segment.argv), [
    ["./a.mbtx", "first"],
    ["./b.mbtx", "parent-second"],
    ["./c.mbtx", "parent"],
  ])
  assert_eq(pipeline.map(segment => segment.extra_env), [
    { "A": "first" },
    { "A": "parent-second" },
    Map([]),
  ])
  assert_true(pipeline[0].stderr_to_stdout && pipeline[0].stdout_to_null)
  assert_error_contains(
    () => ignore(segments("A=x ./a.mbtx|./b.mbtx ${A}")),
    "undefined variable: A",
  )
  assert_error_contains(
    () => ignore(segments("./a.mbtx ${A}|A=x ./b.mbtx")),
    "undefined variable: A",
  )
}

///|
test "temporary assignments obey platform name matching" {
  let lookup = fn(name : String) {
    if name == "MODE" {
      Some("parent")
    } else {
      None
    }
  }
  let windows = segments(
      "MoDe=${mode}-first mode=${Mode}-second B=${mODE} ./a.mbtx ${Mode} ${b}",
      lookup~,
      case_insensitive=true,
    )[0]
  assert_eq(windows.extra_env, {
    "MODE": "parent-first-second",
    "B": "parent-first-second",
  })
  assert_eq(windows.argv, [
    "./a.mbtx", "parent-first-second", "parent-first-second",
  ])
  let unix = segments(
      "Mode=first mode=second ./a.mbtx ${Mode} ${mode} ${MODE}",
      lookup~,
    )[0]
  assert_eq(unix.extra_env, { "Mode": "first", "mode": "second" })
  assert_eq(unix.argv, ["./a.mbtx", "first", "second", "parent"])
}

///|
test "temporary assignment errors and actual executable expansion are rejected" {
  for command in ["A=x", "A=x B=y", "./a.mbtx|A=x", "A=x|./a.mbtx"] {
    assert_error_contains(
      () => ignore(segments(command)),
      "assignments require a command",
    )
  }
  for executable in ["export A=x", "set-current-working-directory dir"] {
    assert_error_contains(
      () => ignore(@command.parse("A=x " + executable)),
      "does not accept temporary environment assignments",
    )
  }
  for command in ["A=x ${A}", "A=x ./\"${A}\".mbtx", "./a.mbtx|A=x ${A}"] {
    assert_error_contains(() => ignore(segments(command)), "executable paths")
  }
  for command in ["A=${A} ./a.mbtx", "A=${B} B=later ./a.mbtx"] {
    assert_error_contains(() => ignore(segments(command)), "undefined variable")
  }
  assert_eq(segments("A=x '${A}'")[0].argv, ["${A}"])
  for command in ["A=x ./a.mbtx 1>/dev/null", "A=x ./a.mbtx 2>&1"] {
    assert_error_contains(
      () => ignore(segments(command)),
      "final pipeline segment",
    )
  }
  assert_error_contains(
    () => ignore(segments("A=x ./a.mbtx 1>/dev/null B=y|./b.mbtx")),
    "ordinary arguments cannot follow redirection",
  )
}
