///|
test "temporary literal values retain separate document snapshots" {
  let source =
    #|```mooncram
    #|$ MODE=${MODE}-temp moonx ./a.mbtx ${MODE}
    #|$ export MODE=${MODE}-doc
    #|$ MODE=${MODE}-temp B=${MODE} moonx ./a.mbtx ${B}|MODE=${MODE}-other moonx ./b.mbtx ${MODE}|moonx ./c.mbtx ${MODE}
    #|$ moonx ./a.mbtx ${MODE}
    #|```
    #|```mooncram
    #|$ MODE= moonx ./a.mbtx "${MODE}"
    #|$ moonx ./b.mbtx ${MODE}
    #|```
    #|
  let doc = parse_document_with_env(
    "environment.md",
    source,
    case_insensitive=false,
  )
  assert_eq(doc.cases.length(), 5)
  assert_eq(doc.cases[0].pipeline[0].argv, ["moonx", "./a.mbtx", "${MODE}"])
  assert_eq(doc.cases[0].pipeline[0].extra_env, { "MODE": "${MODE}-temp" })
  assert_true(doc.cases[0].extra_env.is_empty())
  assert_eq(doc.cases[1].pipeline.map(segment => segment.argv), [
    ["moonx", "./a.mbtx", "${B}"],
    ["moonx", "./b.mbtx", "${MODE}"],
    ["moonx", "./c.mbtx", "${MODE}"],
  ])
  assert_eq(doc.cases[1].pipeline.map(segment => segment.extra_env), [
    { "MODE": "${MODE}-temp", "B": "${MODE}" },
    { "MODE": "${MODE}-other" },
    Map([]),
  ])
  assert_eq(doc.cases[2].pipeline[0].argv, ["moonx", "./a.mbtx", "${MODE}"])
  assert_eq(doc.cases[3].pipeline[0].argv, ["moonx", "./a.mbtx", "${MODE}"])
  assert_eq(doc.cases[4].pipeline[0].argv, ["moonx", "./b.mbtx", "${MODE}"])
  for case in doc.cases[1:] {
    assert_eq(case.extra_env, { "MODE": "${MODE}-doc" })
  }
  assert_eq(doc.cases[3].command, "$ MODE= moonx ./a.mbtx \"${MODE}\"")
  doc.cases[1].pipeline[0].extra_env["MODE"] = "changed"
  assert_eq(doc.cases[1].pipeline[1].extra_env, { "MODE": "${MODE}-other" })
  assert_eq(doc.cases[1].extra_env, { "MODE": "${MODE}-doc" })
}

///|
test "temporary environment follows Windows and Unix document rules" {
  let source =
    #|```mooncram
    #|$ export Mode=doc
    #|$ mODE=${MODE}-first mode=${Mode}-last moonx ./a.mbtx ${MODE} ${Mode} ${mode}|moonx ./b.mbtx ${Mode}
    #|$ moonx ./c.mbtx ${MODE} ${Mode}
    #|```
    #|
  for case_insensitive in [true, false] {
    let doc = parse_document_with_env("platform.md", source, case_insensitive~)
    if case_insensitive {
      assert_eq(doc.cases[0].pipeline[0].extra_env, { "MODE": "${Mode}-last" })
      assert_eq(doc.cases[0].extra_env, { "MODE": "doc" })
    } else {
      assert_eq(doc.cases[0].pipeline[0].extra_env, {
        "mODE": "${MODE}-first",
        "mode": "${Mode}-last",
      })
      assert_eq(doc.cases[0].extra_env, { "Mode": "doc" })
    }
    assert_eq(doc.cases[0].pipeline[0].argv, [
      "moonx", "./a.mbtx", "${MODE}", "${Mode}", "${mode}",
    ])
    assert_eq(doc.cases[1].pipeline[0].argv, [
      "moonx", "./c.mbtx", "${MODE}", "${Mode}",
    ])
    assert_eq(doc.cases[0].pipeline[1].argv, ["moonx", "./b.mbtx", "${Mode}"])
    assert_true(doc.cases[0].pipeline[1].extra_env.is_empty())
    assert_eq(doc.cases[0].extra_env, doc.cases[1].extra_env)
  }
}
