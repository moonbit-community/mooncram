///|
fn plain_pipeline(
  argvs : Array[Array[String]],
) -> Array[@command.PipelineSegment] {
  argvs.map(argv => { argv: ["moonx"] + argv, extra_env: Map([]), })
}

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
  let source = "# Heading\n\n```text\n$ moonx ignored\n```\n\n~~~~mooncram\n$ moonx ignored\n~~~~\n\n````markdown\n```mooncram\n$ moonx ignored\n```\n````\n\n```mooncram\n$ moonx ./a.mbtx\nhello\n\n$ moonx ./b.mbtx\n[2]\n```\n"
  let doc = parse_document("mixed.md", source)
  assert_eq(doc.cases.length(), 2)
  assert_eq(doc.cases[0].line, 18)
  assert_eq(doc.cases[0].expected.source_lines[0], "hello")
  assert_eq(doc.cases[1].expected.exit_code, 2)
  assert_eq(doc.cases[1].expected.source_lines, ["[2]"])
}

///|
test "empty and unclosed test blocks have accurate errors" {
  assert_error_contains(
    () => ignore(parse_example("\n")),
    "example.md:1: empty",
  )
  assert_error_contains(
    () => {
      ignore(parse_document("x.md", "text\n\n```mooncram\n$ moonx ./a.mbtx\n"))
    },
    "x.md:3: unclosed",
  )
  assert_error_contains(
    () => ignore(parse_example("unexpected\n")),
    "example.md:2: expected a command",
  )
  assert_error_contains(
    () => ignore(parse_example("$ moonx ./a.mbtx |\n")),
    "example.md:2: empty pipeline segment",
  )
  assert_error_contains(() => ignore(parse_example("$\n")), "example.md:2:")
}

///|
test "pipeline arguments and original command text are preserved" {
  let command = "$ moonx ./a.mbtx 'x|y'|moonx ./cmd/filter|moonx ./b.mbtx \\|"
  let doc = parse_example(command + "\nresult\n[3]\n")
  assert_eq(doc.cases[0].command, command)
  assert_eq(
    doc.cases[0].pipeline,
    plain_pipeline([["./a.mbtx", "x|y"], ["./cmd/filter"], ["./b.mbtx", "|"]]),
  )
  assert_eq(doc.cases[0].expected.exit_code, 3)
  for invalid in ["| ./a.mbtx", "./a.mbtx || ./b.mbtx", "./a.mbtx | ''"] {
    assert_error_contains(
      () => ignore(parse_example("$ " + invalid + "\n")),
      "example.md:2:",
    )
  }
}

///|
test "module declarations are scoped to each fence and preserve opening lines" {
  let doc = parse_document(
    "modules.md", "```mooncram user/foo\n$ moonx foo\n```\n\n> - ```mooncram\n>   $ moonx ./a.mbtx\n>   ```\n\n- ```mooncram user/bar\n  $ export A=x\n  ```\n\n```mooncram user/baz\n$ moonx cmd/boo\n```\n",
  )
  assert_eq(doc.cases.length(), 3)
  assert_eq(doc.cases[0].module_name, Some("user/foo"))
  assert_eq(doc.cases[1].module_name, None)
  assert_eq(doc.cases[2].module_name, Some("user/baz"))
  assert_eq(doc.module_declarations, [
    ("user/foo", 1),
    ("user/bar", 9),
    ("user/baz", 13),
  ])
  assert_eq(doc.cases[1].line, 6)
  assert_eq(
    parse_document("spaces.md", "```mooncram   \n$ moonx ./a.mbtx\n```\n").cases[0].module_name,
    None,
  )
}

///|
test "invalid declarations fail at the opening fence including containers" {
  for
    suffix in [
      "user/foo user/bar", "{\"target\":\"native\"}", "{", "./foo", "../foo", "user//foo",
      "user/foo\tother",
    ] {
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "strict.md",
            "text\n\n> - ```mooncram " +
            suffix +
            "\n>   $ export A=x\n>   ```\n",
          ),
        )
      },
      "strict.md:3: invalid mooncram module declaration",
    )
  }
}

///|
test "exports apply in document order across blocks with independent snapshots" {
  let source = "```mooncram\n$ export MOONCRAM_TEST_VALUE=first\n```\n\n```mooncram\n$ moonx ./a.mbtx ${MOONCRAM_TEST_VALUE}\n$ export MOONCRAM_TEST_VALUE=${MOONCRAM_TEST_VALUE}-second\n$ moonx ./b.mbtx \"${MOONCRAM_TEST_VALUE}\"\n$ export MOONCRAM_TEST_VALUE=\n$ moonx ./c.mbtx ${MOONCRAM_TEST_VALUE}\n```\n"
  let doc = parse_document("exports.md", source)
  assert_eq(doc.cases.length(), 3)
  assert_eq(
    doc.cases[0].pipeline,
    plain_pipeline([["./a.mbtx", "${MOONCRAM_TEST_VALUE}"]]),
  )
  assert_eq(
    doc.cases[1].pipeline,
    plain_pipeline([["./b.mbtx", "${MOONCRAM_TEST_VALUE}"]]),
  )
  assert_eq(
    doc.cases[2].pipeline,
    plain_pipeline([["./c.mbtx", "${MOONCRAM_TEST_VALUE}"]]),
  )
  assert_eq(doc.cases[0].extra_env.get("MOONCRAM_TEST_VALUE"), Some("first"))
  assert_eq(
    doc.cases[1].extra_env.get("MOONCRAM_TEST_VALUE"),
    Some("${MOONCRAM_TEST_VALUE}-second"),
  )
  assert_eq(doc.cases[2].extra_env.get("MOONCRAM_TEST_VALUE"), Some(""))
  assert_eq(doc.cases[0].command, "$ moonx ./a.mbtx ${MOONCRAM_TEST_VALUE}")
  // Mutating one saved map must not affect any other case.
  doc.cases[0].extra_env["MOONCRAM_TEST_VALUE"] = "changed"
  assert_eq(
    doc.cases[1].extra_env.get("MOONCRAM_TEST_VALUE"),
    Some("${MOONCRAM_TEST_VALUE}-second"),
  )
  assert_true(parse_example("$ moonx ./a.mbtx\n").cases[0].extra_env.is_empty())
  let isolated = parse_example("$ moonx ./a.mbtx ${MOONCRAM_TEST_VALUE}\n")
  assert_eq(isolated.cases[0].pipeline, doc.cases[0].pipeline)
  assert_true(isolated.cases[0].extra_env.is_empty())
}

///|
test "export-only blocks are legal and exports have no expectations" {
  assert_eq(parse_example("$ export A=x\n\n$ export B=y\n").cases.length(), 0)
  for output in ["hello", "[0]", "[2]", "\"\" (escaped)"] {
    assert_error_contains(
      () => ignore(parse_example("$ export A=x\n" + output + "\n")),
      "example.md:3: export does not accept expected output or an exit code",
    )
  }
  for command in ["export A", "export ${NAME}=x", "./a.mbtx|export A=x"] {
    assert_error_contains(
      () => ignore(parse_example("$ " + command + "\n")),
      "example.md:2:",
    )
  }
}

///|
test "arguments remain literal independently of exports" {
  let doc = parse_example(
    "$ moonx ./a.mbtx ${PATH}\n$ export PATH=${PATH}-suffix\n$ moonx ./a.mbtx ${PATH}\n$ export PATH=\n$ moonx ./a.mbtx ${PATH}\n",
  )
  for case in doc.cases {
    assert_eq(case.pipeline, plain_pipeline([["./a.mbtx", "${PATH}"]]))
  }
  assert_true(doc.cases[0].extra_env.is_empty())
  assert_eq(doc.cases[1].extra_env, { "PATH": "${PATH}-suffix" })
  assert_eq(doc.cases[2].extra_env, { "PATH": "" })
}

///|
test "Windows exports replace mixed-case names and preserve independent snapshots" {
  let source =
    #|```mooncram
    #|$ moonx ./a.mbtx ${mOdE}
    #|$ export MoDe=${mode}-doc
    #|$ moonx ./a.mbtx "${mODE}" ${MODE}
    #|```
    #|```mooncram
    #|$ export mode=${Mode}-next
    #|$ moonx ./a.mbtx ${mode}
    #|$ export MODE=
    #|$ moonx ./a.mbtx ${Mode}
    #|```
    #|
  let doc = parse_document_with_env("windows.md", source, case_insensitive=true)
  assert_eq(doc.cases.length(), 4)
  assert_eq(doc.cases[0].pipeline, plain_pipeline([["./a.mbtx", "${mOdE}"]]))
  assert_true(doc.cases[0].extra_env.is_empty())
  assert_eq(
    doc.cases[1].pipeline,
    plain_pipeline([["./a.mbtx", "${mODE}", "${MODE}"]]),
  )
  assert_eq(doc.cases[1].extra_env, { "MODE": "${mode}-doc" })
  assert_eq(doc.cases[2].pipeline, plain_pipeline([["./a.mbtx", "${mode}"]]))
  assert_eq(doc.cases[2].extra_env, { "MODE": "${Mode}-next" })
  assert_eq(doc.cases[3].pipeline, plain_pipeline([["./a.mbtx", "${Mode}"]]))
  assert_eq(doc.cases[3].extra_env, { "MODE": "" })
  assert_eq(doc.cases[1].command, "$ moonx ./a.mbtx \"${mODE}\" ${MODE}")
  doc.cases[2].extra_env["MODE"] = "changed"
  assert_eq(doc.cases[1].extra_env, { "MODE": "${mode}-doc" })
  assert_eq(doc.cases[3].extra_env, { "MODE": "" })
}

///|
test "Unix export names remain distinct across casing" {
  let doc = parse_document_with_env(
    "unix.md",
    "```mooncram\n$ moonx ./a.mbtx ${MODE} ${mode}\n$ export Mode=mixed\n$ export mode=${mode}-doc\n$ moonx ./a.mbtx ${MODE} ${mode} ${Mode}\n$ export MODE=\n$ moonx ./a.mbtx ${MODE} ${mode} ${Mode}\n```\n",
    case_insensitive=false,
  )
  assert_eq(
    doc.cases[0].pipeline,
    plain_pipeline([["./a.mbtx", "${MODE}", "${mode}"]]),
  )
  assert_true(doc.cases[0].extra_env.is_empty())
  assert_eq(
    doc.cases[1].pipeline,
    plain_pipeline([["./a.mbtx", "${MODE}", "${mode}", "${Mode}"]]),
  )
  assert_eq(doc.cases[1].extra_env, { "Mode": "mixed", "mode": "${mode}-doc" })
  assert_eq(doc.cases[2].pipeline, doc.cases[1].pipeline)
  assert_eq(doc.cases[2].extra_env, {
    "Mode": "mixed",
    "mode": "${mode}-doc",
    "MODE": "",
  })
}

///|
test "redirection errors retain the document command position" {
  for prefix in ["", "moonx ./a.mbtx|", "moonx ./a.mbtx|moonx ./b.mbtx|"] {
    for
      suffix in ["2>&1", "1>/dev/null", "2>&1 1>/dev/null", "1>/dev/null 2>&1"] {
      assert_error_contains(
        () => {
          ignore(
            parse_example("$ " + prefix + "moonx ./c.mbtx " + suffix + "\n"),
          )
        },
        "example.md:2: unquoted shell operator",
      )
    }
  }
  let command = "$ moonx ./a.mbtx '2>&1' \"1>/dev/null\"|moonx ./b.mbtx"
  let doc = parse_example(command + "\nresult\n")
  assert_eq(doc.cases[0].command, command)
  assert_eq(
    doc.cases[0].pipeline,
    plain_pipeline([["./a.mbtx", "2>&1", "1>/dev/null"], ["./b.mbtx"]]),
  )
}

///|
test "working directories stay literal and reset between blocks" {
  let source =
    #|```mooncram
    #|$ export DIR=../fixtures
    #|$ set-current-working-directory "${DIR}"
    #|$ export DIR=elsewhere
    #|$ moonx ./a.mbtx ${DIR}
    #|$ moonx ./b.mbtx
    #|```
    #|```mooncram
    #|$ moonx ./c.mbtx ${DIR}
    #|```
    #|> - ```mooncram
    #|>   $ set-current-working-directory '${DIR}'
    #|>   ```
    #|```mooncram
    #|$ set-current-working-directory "${PARENT}"
    #|$ moonx ./d.mbtx
    #|```
    #|
  let doc = parse_document_with_env("cwd.md", source, case_insensitive=false)
  assert_eq(doc.cases.length(), 4)
  assert_eq(doc.working_directory_declarations, [
    { directory: "${DIR}", line: 3, },
    { directory: "${DIR}", line: 12, },
    { directory: "${PARENT}", line: 15, },
  ])
  assert_eq(
    doc.cases[0].working_directory,
    Some(doc.working_directory_declarations[0]),
  )
  assert_eq(doc.cases[1].working_directory, doc.cases[0].working_directory)
  assert_eq(doc.cases[2].working_directory, None)
  assert_eq(
    doc.cases[3].working_directory,
    Some(doc.working_directory_declarations[2]),
  )
  assert_eq(doc.cases[0].pipeline, plain_pipeline([["./a.mbtx", "${DIR}"]]))
  assert_eq(doc.cases[2].pipeline, plain_pipeline([["./c.mbtx", "${DIR}"]]))
  let only = parse_example("$ set-current-working-directory nonexistent\n\n")
  assert_eq(only.cases.length(), 0)
  assert_eq(only.working_directory_declarations, [
    { directory: "nonexistent", line: 2, },
  ])
}

///|
test "working directory rejects duplicate late and expectation declarations with locations" {
  assert_error_contains(
    () => {
      ignore(
        parse_example(
          "$ set-current-working-directory a\n$ export A=x\n$ set-current-working-directory b\n",
        ),
      )
    },
    "example.md:4: duplicate set-current-working-directory",
  )
  for command in ["moonx ./a.mbtx", "moonx ./a.mbtx|moonx ./b.mbtx"] {
    assert_error_contains(
      () => {
        ignore(
          parse_example(
            "$ " +
            command +
            "\n$ export A=x\n$ set-current-working-directory a\n",
          ),
        )
      },
      "example.md:4: set-current-working-directory must precede",
    )
  }
  for output in ["hello", "[0]", "[2]", "@STDOUT", "\"\" (escaped)"] {
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "cwd.md",
            "> - ```mooncram\n>   $ set-current-working-directory a\n>   " +
            output +
            "\n>   ```\n",
          ),
        )
      },
      "cwd.md:3: set-current-working-directory does not accept expected output or an exit code",
    )
  }
}
