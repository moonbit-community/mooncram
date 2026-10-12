///|
test "temporary values override exports and parents without changing document snapshots" {
  let source =
    #|```mooncram
    #|$ MODE=${MODE}-temp ./a.mbtx ${MODE}
    #|$ export MODE=${MODE}-doc
    #|$ MODE=${MODE}-temp B=${MODE} ./a.mbtx ${B}|MODE=${MODE}-other ./b.mbtx ${MODE}|./c.mbtx ${MODE}
    #|$ ./a.mbtx ${MODE}
    #|```
    #|```mooncram
    #|$ MODE= ./a.mbtx "${MODE}"
    #|$ ./b.mbtx ${MODE}
    #|```
    #|
  let doc = parse_document_with_env(
    "environment.md",
    source,
    parent_lookup=_ => Some("parent"),
    case_insensitive=false,
  )
  assert_eq(doc.cases.length(), 5)
  assert_eq(doc.cases[0].pipeline[0].argv, ["./a.mbtx", "parent-temp"])
  assert_eq(doc.cases[0].pipeline[0].extra_env, { "MODE": "parent-temp" })
  assert_true(doc.cases[0].extra_env.is_empty())
  assert_eq(doc.cases[1].pipeline.map(segment => segment.argv), [
    ["./a.mbtx", "parent-doc-temp"],
    ["./b.mbtx", "parent-doc-other"],
    ["./c.mbtx", "parent-doc"],
  ])
  assert_eq(doc.cases[1].pipeline.map(segment => segment.extra_env), [
    { "MODE": "parent-doc-temp", "B": "parent-doc-temp" },
    { "MODE": "parent-doc-other" },
    Map([]),
  ])
  assert_eq(doc.cases[2].pipeline[0].argv, ["./a.mbtx", "parent-doc"])
  assert_eq(doc.cases[3].pipeline[0].argv, ["./a.mbtx", ""])
  assert_eq(doc.cases[4].pipeline[0].argv, ["./b.mbtx", "parent-doc"])
  for case in doc.cases[1:] {
    assert_eq(case.extra_env, { "MODE": "parent-doc" })
  }
  assert_eq(doc.cases[3].command, "$ MODE= ./a.mbtx \"${MODE}\"")
  doc.cases[1].pipeline[0].extra_env["MODE"] = "changed"
  assert_eq(doc.cases[1].pipeline[1].extra_env, { "MODE": "parent-doc-other" })
  assert_eq(doc.cases[1].extra_env, { "MODE": "parent-doc" })
}

///|
test "temporary environment follows Windows and Unix document rules" {
  let source =
    #|```mooncram
    #|$ export Mode=doc
    #|$ mODE=${MODE}-first mode=${Mode}-last ./a.mbtx ${MODE} ${Mode} ${mode}|./b.mbtx ${Mode}
    #|$ ./c.mbtx ${MODE} ${Mode}
    #|```
    #|
  let parent = { "MODE": "parent" }
  for case_insensitive in [true, false] {
    let doc = parse_document_with_env(
      "platform.md",
      source,
      parent_lookup=name => parent.get(name),
      case_insensitive~,
    )
    if case_insensitive {
      assert_eq(doc.cases[0].pipeline[0].extra_env, { "MODE": "doc-first-last" })
      assert_eq(doc.cases[0].pipeline[0].argv, [
        "./a.mbtx", "doc-first-last", "doc-first-last", "doc-first-last",
      ])
      assert_eq(doc.cases[1].pipeline[0].argv, ["./c.mbtx", "doc", "doc"])
      assert_eq(doc.cases[0].extra_env, { "MODE": "doc" })
    } else {
      assert_eq(doc.cases[0].pipeline[0].extra_env, {
        "mODE": "parent-first",
        "mode": "doc-last",
      })
      assert_eq(doc.cases[0].pipeline[0].argv, [
        "./a.mbtx", "parent", "doc", "doc-last",
      ])
      assert_eq(doc.cases[1].pipeline[0].argv, ["./c.mbtx", "parent", "doc"])
      assert_eq(doc.cases[0].extra_env, { "Mode": "doc" })
    }
    assert_eq(doc.cases[0].pipeline[1].argv, ["./b.mbtx", "doc"])
    assert_true(doc.cases[0].pipeline[1].extra_env.is_empty())
    assert_eq(doc.cases[0].extra_env, doc.cases[1].extra_env)
  }
}
