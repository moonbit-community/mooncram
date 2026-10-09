///|
fn parse_example(body : String) -> Document raise {
  parse_document("example.md", "```mooncram\n" + body + "```\n")
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
test "mixed Markdown skips other languages tilde fences and enclosing examples" {
  let source = "# Heading\n\n```text\n$ ignored\n```\n\n~~~~mooncram\n$ ignored\n~~~~\n\n````markdown\n```mooncram\n$ ignored\n```\n````\n\n```mooncram\n$ ./a.mbtx\nhello\n\n$ ./b.mbtx\n[2]\n```\n"
  let doc = parse_document("mixed.md", source)
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
    () => ignore(parse_document("x.md", "text\n\n```mooncram\n$ ./a.mbtx\n")),
    "x.md:3: unclosed",
  )
  assert_error_contains(
    () => ignore(parse_example("unexpected\n")),
    "example.md:2: expected a command",
  )
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx |\n")),
    "example.md:2: empty pipeline segment",
  )
  assert_error_contains(() => ignore(parse_example("$\n")), "example.md:2:")
}

///|
test "pipeline arguments and original command text are preserved" {
  let command = "$ ./a.mbtx 'x|y'|./cmd/filter|./b.mbtx \\|"
  let doc = parse_example(command + "\nresult\n[3]\n")
  assert_eq(doc.cases[0].command, command)
  assert_eq(doc.cases[0].pipeline, [
    ["./a.mbtx", "x|y"],
    ["./cmd/filter"],
    ["./b.mbtx", "|"],
  ])
  assert_eq(doc.cases[0].expected.exit_code, 3)
  for invalid in ["| ./a.mbtx", "./a.mbtx || ./b.mbtx", "./a.mbtx | ''"] {
    assert_error_contains(
      () => ignore(parse_example("$ " + invalid + "\n")),
      "example.md:2:",
    )
  }
}

///|
test "only bare mooncram info strings are recognized" {
  let source = "```mooncram\n$ ./bare.mbtx\n```\n\n```mooncram   \n$ ./spaces.mbtx\n```\n\n```mooncram {\"target\":\"native\"}\n$ ./json.mbtx\n```\n\n```mooncram {\n$ ./invalid-json.mbtx\n```\n\n```mooncram trailing text\n$ ./text.mbtx\n```\n"
  let doc = parse_document("strict.md", source)
  assert_eq(doc.cases.length(), 2)
  assert_eq(doc.cases[0].pipeline, [["./bare.mbtx"]])
  assert_eq(doc.cases[1].pipeline, [["./spaces.mbtx"]])
}

///|
test "ignored legacy fences do not produce parse errors" {
  for suffix in [" {\"stream\":\"stderr\"}", " {", " anything"] {
    let doc = parse_document(
      "ignored.md",
      "```mooncram" + suffix + "\nnot a command\n",
    )
    assert_eq(doc.cases.length(), 0)
  }
}

///|
test "exports apply in document order across blocks with independent snapshots" {
  let source = "```mooncram\n$ export MOONCRAM_TEST_VALUE=first\n```\n\n```mooncram\n$ ./a.mbtx ${MOONCRAM_TEST_VALUE}\n$ export MOONCRAM_TEST_VALUE=${MOONCRAM_TEST_VALUE}-second\n$ ./b.mbtx \"${MOONCRAM_TEST_VALUE}\"\n$ export MOONCRAM_TEST_VALUE=\n$ ./c.mbtx ${MOONCRAM_TEST_VALUE}\n```\n"
  let doc = parse_document("exports.md", source)
  assert_eq(doc.cases.length(), 3)
  assert_eq(doc.cases[0].pipeline, [["./a.mbtx", "first"]])
  assert_eq(doc.cases[1].pipeline, [["./b.mbtx", "first-second"]])
  assert_eq(doc.cases[2].pipeline, [["./c.mbtx", ""]])
  assert_eq(doc.cases[0].extra_env.get("MOONCRAM_TEST_VALUE"), Some("first"))
  assert_eq(
    doc.cases[1].extra_env.get("MOONCRAM_TEST_VALUE"),
    Some("first-second"),
  )
  assert_eq(doc.cases[2].extra_env.get("MOONCRAM_TEST_VALUE"), Some(""))
  assert_eq(doc.cases[0].command, "$ ./a.mbtx ${MOONCRAM_TEST_VALUE}")
  // Mutating one saved map must not affect any other case.
  doc.cases[0].extra_env["MOONCRAM_TEST_VALUE"] = "changed"
  assert_eq(
    doc.cases[1].extra_env.get("MOONCRAM_TEST_VALUE"),
    Some("first-second"),
  )
  assert_true(parse_example("$ ./a.mbtx\n").cases[0].extra_env.is_empty())
  assert_error_contains(
    () => ignore(parse_example("$ ./a.mbtx ${MOONCRAM_TEST_VALUE}\n")),
    "example.md:2: undefined variable: MOONCRAM_TEST_VALUE",
  )
}

///|
test "export-only blocks are legal and exports have no expectations" {
  assert_eq(parse_example("$ export A=x\n\n$ export B=y\n").cases.length(), 0)
  for output in ["hello", "[0]", "[2]", " (equal)"] {
    assert_error_contains(
      () => ignore(parse_example("$ export A=x\n" + output + "\n")),
      "example.md:3: export does not accept expected output or an exit code",
    )
  }
  for
    command in [
      "export A", "./a.mbtx ${UNDEFINED_MOONCRAM_TEST}", "./${PATH}.mbtx", "./a.mbtx|export A=x",
      "./a.mbtx ${}",
    ] {
    assert_error_contains(
      () => ignore(parse_example("$ " + command + "\n")),
      "example.md:2:",
    )
  }
}

///|
test "parent environment is a fallback and empty exports override it" {
  if @env.get_env_var("PATH") is Some(path) {
    let doc = parse_example(
      "$ ./a.mbtx ${PATH}\n$ export PATH=${PATH}-suffix\n$ ./a.mbtx ${PATH}\n$ export PATH=\n$ ./a.mbtx ${PATH}\n",
    )
    assert_eq(doc.cases[0].pipeline, [["./a.mbtx", path]])
    assert_true(doc.cases[0].extra_env.is_empty())
    assert_eq(doc.cases[1].pipeline, [["./a.mbtx", path + "-suffix"]])
    assert_eq(doc.cases[2].pipeline, [["./a.mbtx", ""]])
  }
}

///|
test "Windows exports override parent values across casing and preserve snapshots" {
  let source =
    #|```mooncram
    #|$ ./a.mbtx ${mOdE}
    #|$ export MoDe=${mode}-doc
    #|$ ./a.mbtx "${mODE}" ${MODE}
    #|```
    #|```mooncram
    #|$ export mode=${Mode}-next
    #|$ ./a.mbtx ${mode}
    #|$ export MODE=
    #|$ ./a.mbtx ${Mode}
    #|```
    #|
  let queries = []
  let doc = parse_document_with_env(
    "windows.md",
    source,
    parent_lookup=name => {
      queries.push(name)
      if name == "MODE" {
        Some("parent")
      } else {
        None
      }
    },
    case_insensitive=true,
  )
  assert_eq(queries, ["MODE", "MODE"])
  assert_eq(doc.cases.length(), 4)
  assert_eq(doc.cases[0].pipeline, [["./a.mbtx", "parent"]])
  assert_true(doc.cases[0].extra_env.is_empty())
  assert_eq(doc.cases[1].pipeline, [["./a.mbtx", "parent-doc", "parent-doc"]])
  assert_eq(doc.cases[1].extra_env, { "MODE": "parent-doc" })
  assert_eq(doc.cases[2].pipeline, [["./a.mbtx", "parent-doc-next"]])
  assert_eq(doc.cases[2].extra_env, { "MODE": "parent-doc-next" })
  assert_eq(doc.cases[3].pipeline, [["./a.mbtx", ""]])
  assert_eq(doc.cases[3].extra_env, { "MODE": "" })
  assert_eq(doc.cases[1].command, "$ ./a.mbtx \"${mODE}\" ${MODE}")
  doc.cases[2].extra_env["MODE"] = "changed"
  assert_eq(doc.cases[1].extra_env, { "MODE": "parent-doc" })
  assert_eq(doc.cases[3].extra_env, { "MODE": "" })
}

///|
test "Windows mixed-case exports work without a parent value" {
  let doc = parse_document_with_env(
    "windows.md",
    "```mooncram\n$ export New_Value=first\n$ ./a.mbtx ${new_VALUE}\n$ export nEW_vALUE=second\n$ ./a.mbtx ${New_Value}\n```\n",
    parent_lookup=_ => None,
    case_insensitive=true,
  )
  assert_eq(doc.cases[0].pipeline, [["./a.mbtx", "first"]])
  assert_eq(doc.cases[0].extra_env, { "NEW_VALUE": "first" })
  assert_eq(doc.cases[1].pipeline, [["./a.mbtx", "second"]])
  assert_eq(doc.cases[1].extra_env, { "NEW_VALUE": "second" })
  assert_error_contains(
    () => {
      ignore(
        parse_document_with_env(
          "windows.md",
          "```mooncram\n$ ./a.mbtx ${New_Value}\n```\n",
          parent_lookup=_ => None,
          case_insensitive=true,
        ),
      )
    },
    "windows.md:2: undefined variable: New_Value",
  )
}

///|
test "Unix environment names remain distinct across casing" {
  let parent = { "MODE": "upper", "mode": "lower" }
  let doc = parse_document_with_env(
    "unix.md",
    "```mooncram\n$ ./a.mbtx ${MODE} ${mode}\n$ export Mode=mixed\n$ export mode=${mode}-doc\n$ ./a.mbtx ${MODE} ${mode} ${Mode}\n$ export MODE=\n$ ./a.mbtx ${MODE} ${mode} ${Mode}\n```\n",
    parent_lookup=name => parent.get(name),
    case_insensitive=false,
  )
  assert_eq(doc.cases[0].pipeline, [["./a.mbtx", "upper", "lower"]])
  assert_eq(doc.cases[1].pipeline, [["./a.mbtx", "upper", "lower-doc", "mixed"]])
  assert_eq(doc.cases[1].extra_env, { "Mode": "mixed", "mode": "lower-doc" })
  assert_eq(doc.cases[2].pipeline, [["./a.mbtx", "", "lower-doc", "mixed"]])
  assert_eq(doc.cases[2].extra_env, {
    "Mode": "mixed",
    "mode": "lower-doc",
    "MODE": "",
  })
  assert_error_contains(
    () => {
      ignore(
        parse_document_with_env(
          "unix.md",
          "```mooncram\n$ export Mode=value\n$ ./a.mbtx ${MODE}\n```\n",
          parent_lookup=_ => None,
          case_insensitive=false,
        ),
      )
    },
    "unix.md:3: undefined variable: MODE",
  )
}
