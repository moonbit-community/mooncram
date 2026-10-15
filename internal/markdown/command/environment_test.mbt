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
    "A=${A}-first B=\"${A}\" A=${A}-last EMPTY= EQUALS=a=b=c SPACES='Moon Bit|quoted' NESTED=${NESTED} moonx ./a.mbtx ${A} \"${B}\" ${EMPTY} ${SPACES} ${NESTED} A=argument",
  )
  assert_eq(pipeline[0].argv, [
    "moonx", "./a.mbtx", "${A}", "${B}", "${EMPTY}", "${SPACES}", "${NESTED}", "A=argument",
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
      segments(name + "= moonx ./a.mbtx")[0].extra_env,
      Map::from_array([(name, "")]),
    )
  }
}

///|
test "temporary assignment values reuse quoting and escaping" {
  let pipeline = segments(
    "A='${MISSING}' B=\\${MISSING} C=\"\\${MISSING}\" D=x\\ y E=\"a b\" F=a\"b\"c moonx ./a.mbtx ${A} ${B} ${C} ${D} ${E} ${F}",
  )
  assert_eq(pipeline[0].argv, [
    "moonx", "./a.mbtx", "${A}", "${B}", "${C}", "${D}", "${E}", "${F}",
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
    (word, literal) in [
      ("'A=x'", "A=x"),
      ("\"A=x\"", "A=x"),
      ("'A'=x", "A=x"),
      ("A'='x", "A=x"),
      ("A\\=x", "A=x"),
      ("\\A=x", "A=x"),
      ("A\"\"=x", "A=x"),
      ("''A=x", "A=x"),
      ("9A=x", "9A=x"),
      ("A-B=x", "A-B=x"),
      ("名=x", "名=x"),
      ("=x", "=x"),
    ] {
    for prefix in ["", "MODE=existing ", "moonx ./a.mbtx|"] {
      assert_error_contains(
        () => ignore(segments(prefix + word + " moonx ./a.mbtx")),
        "command must start with moonx: " + literal,
      )
    }
    let pipeline = segments("moonx ./a.mbtx " + word + " B=y")
    assert_true(pipeline[0].extra_env.is_empty())
    assert_eq(pipeline[0].argv, ["moonx", "./a.mbtx", literal, "B=y"])
  }
  let literal = segments("moonx ./a.mbtx ${PREFIX} B=y")[0]
  assert_eq(literal.argv, ["moonx", "./a.mbtx", "${PREFIX}", "B=y"])
  assert_true(literal.extra_env.is_empty())
  let pipeline = segments("A=x moonx ./a.mbtx 'B'=y C=z")
  assert_eq(pipeline[0].extra_env, { "A": "x" })
  assert_eq(pipeline[0].argv, ["moonx", "./a.mbtx", "B=y", "C=z"])
  assert_eq(segments("A=x moonx ./a.mbtx B=${A}")[0].argv, [
    "moonx", "./a.mbtx", "B=${A}",
  ])
}

///|
test "temporary assignments stay within one pipeline segment" {
  let pipeline = segments(
    "A=first moonx ./a.mbtx ${A}|A=${A}-second moonx ./b.mbtx ${A}|moonx ./c.mbtx ${A}",
  )
  assert_eq(pipeline.map(segment => segment.argv), [
    ["moonx", "./a.mbtx", "${A}"],
    ["moonx", "./b.mbtx", "${A}"],
    ["moonx", "./c.mbtx", "${A}"],
  ])
  assert_eq(pipeline.map(segment => segment.extra_env), [
    { "A": "first" },
    { "A": "${A}-second" },
    Map([]),
  ])
  assert_eq(
    segments("A=x moonx ./a.mbtx|moonx ./b.mbtx ${A}")[1].extra_env,
    Map([]),
  )
  assert_eq(
    segments("moonx ./a.mbtx ${A}|A=x moonx ./b.mbtx")[0].extra_env,
    Map([]),
  )
}

///|
test "temporary assignments obey platform name matching" {
  let windows = segments(
      "MoDe=${mode}-first mode=${Mode}-second B=${mODE} moonx ./a.mbtx ${Mode} ${b}",
      case_insensitive=true,
    )[0]
  assert_eq(windows.extra_env, { "MODE": "${Mode}-second", "B": "${mODE}" })
  assert_eq(windows.argv, ["moonx", "./a.mbtx", "${Mode}", "${b}"])
  let unix = segments(
      "Mode=first mode=second moonx ./a.mbtx ${Mode} ${mode} ${MODE}",
    )[0]
  assert_eq(unix.extra_env, { "Mode": "first", "mode": "second" })
  assert_eq(unix.argv, ["moonx", "./a.mbtx", "${Mode}", "${mode}", "${MODE}"])
}

///|
test "temporary assignment errors retain existing syntax restrictions" {
  for command in ["A=x", "A=x B=y", "moonx ./a.mbtx|A=x", "A=x|moonx ./a.mbtx"] {
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
  assert_eq(segments("A=x moonx ${A}")[0].argv, ["moonx", "${A}"])
  assert_eq(segments("A=x moonx ./\"${A}\".mbtx")[0].argv, [
    "moonx", "./${A}.mbtx",
  ])
  assert_eq(segments("A=new B=\"${A}\" moonx ./a.mbtx")[0].extra_env, {
    "A": "new",
    "B": "${A}",
  })
  assert_eq(segments("A=${B} B=later moonx ./a.mbtx")[0].extra_env, {
    "A": "${B}",
    "B": "later",
  })
  for command in ["A=x ./a.mbtx 1>/dev/null", "A=x ./a.mbtx 2>&1"] {
    assert_error_contains(() => ignore(segments(command)), "shell operator")
  }
  assert_error_contains(
    () => ignore(segments("A=x moonx ./a.mbtx 1>/dev/null B=y|moonx ./b.mbtx")),
    "shell operator",
  )
}
