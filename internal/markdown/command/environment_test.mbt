///|
fn segments(
  command : String,
  case_insensitive~ : Bool = false,
) -> Array[@command.PipelineSegment] raise {
  guard @command.parse(command, case_insensitive~) is Pipeline(segments) else {
    fail("expected pipeline")
  }
  segments
}

///|
test "temporary assignments keep literal values and repeated names keep the last value" {
  let pipeline = segments(
    "A=${A}-first B=\"${A}\" A=${A}-last EMPTY= EQUALS=a=b=c SPACES='Moon Bit|quoted' NESTED=${NESTED} ./a.mbtx ${A} \"${B}\" ${EMPTY} ${SPACES} ${NESTED} A=argument",
  )
  assert_eq(pipeline[0].argv, [
    "./a.mbtx", "${A}", "${B}", "${EMPTY}", "${SPACES}", "${NESTED}", "A=argument",
  ])
  assert_eq(pipeline[0].extra_env, {
    "A": "${A}-last",
    "B": "${A}",
    "EMPTY": "",
    "EQUALS": "a=b=c",
    "SPACES": "Moon Bit|quoted",
    "NESTED": "${NESTED}",
  })
  for name in ["A", "_", "_a9", "Camel_case12"] {
    assert_eq(
      segments(name + "= ./a.mbtx")[0].extra_env,
      Map::from_array([(name, "")]),
    )
  }
}

///|
test "temporary assignment values reuse quoting and escaping" {
  let pipeline = segments(
    "A='${MISSING}' B=\\${MISSING} C=\"\\${MISSING}\" D=x\\ y E=\"a b\" F=a\"b\"c ./a.mbtx ${A} ${B} ${C} ${D} ${E} ${F}",
  )
  assert_eq(pipeline[0].argv, [
    "./a.mbtx", "${A}", "${B}", "${C}", "${D}", "${E}", "${F}",
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
test "quoted escaped variable-like and invalid names are ordinary words" {
  for
    word in [
      "'A=x'", "\"A=x\"", "'A'=x", "A'='x", "A\\=x", "\\A=x", "A\"\"=x", "''A=x",
      "9A=x", "A-B=x", "名=x", "=x",
    ] {
    let pipeline = segments(word + " B=y ./a.mbtx")
    assert_true(pipeline[0].extra_env.is_empty())
    assert_eq(pipeline[0].argv[1:], ["B=y", "./a.mbtx"])
  }
  let literal = segments("./a.mbtx ${PREFIX} B=y")[0]
  assert_eq(literal.argv, ["./a.mbtx", "${PREFIX}", "B=y"])
  assert_true(literal.extra_env.is_empty())
  let pipeline = segments("A=x 'B'=y C=z ./a.mbtx")
  assert_eq(pipeline[0].extra_env, { "A": "x" })
  assert_eq(pipeline[0].argv, ["B=y", "C=z", "./a.mbtx"])
  assert_eq(segments("A=x ./a.mbtx B=${A}")[0].argv, ["./a.mbtx", "B=${A}"])
}

///|
test "temporary assignments stay within one pipeline segment and retain routes" {
  let pipeline = segments(
    "A=first ./a.mbtx ${A} 1>/dev/null 2>&1|A=${A}-second ./b.mbtx ${A}|./c.mbtx ${A}",
  )
  assert_eq(pipeline.map(segment => segment.argv), [
    ["./a.mbtx", "${A}"],
    ["./b.mbtx", "${A}"],
    ["./c.mbtx", "${A}"],
  ])
  assert_eq(pipeline.map(segment => segment.extra_env), [
    { "A": "first" },
    { "A": "${A}-second" },
    Map([]),
  ])
  assert_true(pipeline[0].stderr_to_stdout && pipeline[0].stdout_to_null)
  assert_eq(segments("A=x ./a.mbtx|./b.mbtx ${A}")[1].extra_env, Map([]))
  assert_eq(segments("./a.mbtx ${A}|A=x ./b.mbtx")[0].extra_env, Map([]))
}

///|
test "temporary assignments obey platform name matching" {
  let windows = segments(
      "MoDe=${mode}-first mode=${Mode}-second B=${mODE} ./a.mbtx ${Mode} ${b}",
      case_insensitive=true,
    )[0]
  assert_eq(windows.extra_env, { "MODE": "${Mode}-second", "B": "${mODE}" })
  assert_eq(windows.argv, ["./a.mbtx", "${Mode}", "${b}"])
  let unix = segments("Mode=first mode=second ./a.mbtx ${Mode} ${mode} ${MODE}")[0]
  assert_eq(unix.extra_env, { "Mode": "first", "mode": "second" })
  assert_eq(unix.argv, ["./a.mbtx", "${Mode}", "${mode}", "${MODE}"])
}

///|
test "temporary assignment errors retain existing syntax restrictions" {
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
  assert_eq(segments("A=x ${A}")[0].argv, ["${A}"])
  assert_eq(segments("A=x ./\"${A}\".mbtx")[0].argv, ["./${A}.mbtx"])
  assert_eq(segments("A=new B=\"${A}\" ./a.mbtx")[0].extra_env, {
    "A": "new",
    "B": "${A}",
  })
  assert_eq(segments("A=${B} B=later ./a.mbtx")[0].extra_env, {
    "A": "${B}",
    "B": "later",
  })
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
