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
    "example.md:2:18: empty pipeline segment",
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
    "modules.md", "```mooncram user/foo\n$ moonx foo\n```\n\n> - ```mooncram\n>   $ moonx ./a.mbtx\n>   ```\n\n- ```mooncram user/bar\n  #cwd(.)\n  ```\n\n```mooncram user/baz\n$ moonx cmd/boo\n```\n",
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
            "text\n\n> - ```mooncram " + suffix + "\n>   #cwd(.)\n>   ```\n",
          ),
        )
      },
      "strict.md:3: invalid mooncram module declaration",
    )
  }
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
        "example.md:2:\{19 + prefix.length()}: unquoted shell operator",
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
    #|#cwd(${DIR})
    #|$ moonx ./a.mbtx ${DIR}
    #|$ moonx ./b.mbtx
    #|```
    #|```mooncram
    #|$ moonx ./c.mbtx ${DIR}
    #|```
    #|> - ```mooncram
    #|>   #cwd(${DIR})
    #|>   ```
    #|```mooncram
    #|#cwd(${PARENT})
    #|$ moonx ./d.mbtx
    #|```
    #|
  let doc = parse_document_with_case_sensitivity(
    "cwd.md",
    source,
    case_insensitive=false,
  )
  assert_eq(doc.cases.length(), 4)
  assert_eq(doc.working_directory_declarations, [
    { directory: "${DIR}", line: 2, },
    { directory: "${DIR}", line: 10, },
    { directory: "${PARENT}", line: 13, },
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
  let only = parse_example("#cwd(nonexistent)\n\n")
  assert_eq(only.cases.length(), 0)
  assert_eq(only.working_directory_declarations, [
    { directory: "nonexistent", line: 2, },
  ])
}

///|
test "working directory rejects duplicate late and unexpected lines with locations" {
  assert_error_contains(
    () => ignore(parse_example("#cwd(a)\n\n#cwd(b)\n")),
    "example.md:4: duplicate #cwd declaration",
  )
  for command in ["moonx ./a.mbtx", "moonx ./a.mbtx|moonx ./b.mbtx"] {
    for output in ["", "hello\n", "@STDOUT\nhello\n@STDERR (empty)\n", "[2]\n"] {
      assert_error_contains(
        () => {
          ignore(parse_example("$ " + command + "\n" + output + "\n#cwd(a)\n"))
        },
        "example.md:" +
        (4 + output.split("\n").count() - 1).to_string() +
        ": #cwd must be the first nonempty line",
      )
    }
  }
  for output in ["hello", "[0]", "[2]", "@STDOUT", "\"\" (escaped)"] {
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "cwd.md",
            "> - ```mooncram\n>   #cwd(a)\n>   " + output + "\n>   ```\n",
          ),
        )
      },
      "cwd.md:3: expected a command",
    )
  }
}

///|
test "export statements fail at the command line including export-only fences" {
  for
    command in [
      "export A=x", "A=x export B=y", "export A=x|moonx ./a.mbtx", "moonx ./a.mbtx|export A=x",
    ] {
    for output in ["", "hello\n", "[0]\n"] {
      assert_error_contains(
        () => ignore(parse_example("$ " + command + "\n" + output)),
        "example.md:2:\{3 + command.find("export").unwrap()}: command must start with moonx: export",
      )
    }
  }
  assert_error_contains(
    () => {
      ignore(
        parse_document(
          "nested.md", "> - ```mooncram\n>   $ export A=x\n>   ```\n",
        ),
      )
    },
    "nested.md:2:7: command must start with moonx: export",
  )
}

///|
test "working directory paths preserve every character without tokenization" {
  for
    directory in [
      "../fixtures with spaces", " leading and trailing ", " ", "a\\b", "C:\\fixtures\\中文",
      "\"foo\"", "'foo'", "a(b)c", "a)b(c)", "(", ")", "中文目录", "${NAME}",
      "${A B}", "a|b > c; $HOME", "\tpath\t",
    ] {
    let body = "\n\n#cwd(" + directory + ")\n\n$ moonx ./a.mbtx\n"
    let doc = parse_example(body)
    assert_eq(doc.working_directory_declarations, [{ directory, line: 4, }])
    assert_eq(doc.cases[0].working_directory, Some({ directory, line: 4, }))
    assert_eq(doc.cases[0].line, 6)
    let only = parse_example("#cwd(" + directory + ")\n")
    assert_eq(only.cases.length(), 0)
    assert_eq(only.working_directory_declarations, [{ directory, line: 2, }])
  }
}

///|
test "malformed working directory declarations and old commands retain locations" {
  for
    (body, message) in [
      ("#cwd()", "#cwd requires a nonempty path"),
      ("#cwd(foo", "#cwd declaration must end with ')'"),
      ("#cwd(foo) trailing", "#cwd declaration must end with ')'"),
      ("#cwd(foo) ", "#cwd declaration must end with ')'"),
      ("#cwd", "expected a command"),
      ("#cwd (foo)", "expected a command"),
      (" #cwd(foo)", "expected a command"),
      (
        "$ set-current-working-directory dir", "command must start with moonx: set-current-working-directory",
      ),
      (
        "$ MODE=x set-current-working-directory dir", "command must start with moonx: set-current-working-directory",
      ),
      (
        "$ moonx ./a.mbtx|set-current-working-directory dir", "command must start with moonx: set-current-working-directory",
      ),
    ] {
    assert_error_contains(
      () => {
        ignore(
          parse_document(
            "bad.md",
            "> - ```mooncram\r\n>   \r\n>   " + body + "\r\n>   ```\r\n",
          ),
        )
      },
      "bad.md:3:" +
      (if body.has_prefix("$ ") {
        (5 + body.find("set-current-working-directory").unwrap()).to_string() +
        ":"
      } else {
        ""
      }) +
      " " +
      message,
    )
  }
}

///|
test "working directory shaped output is literal when escaped" {
  for line in ["#cwd(.)", "#cwd()", "#cwd(unclosed", "#cwd(late) trailing"] {
    let doc = parse_example(
      "#cwd(real)\n$ moonx ./a.mbtx\n" +
      Json::string(line).stringify() +
      " (escaped)\n",
    )
    assert_eq(doc.working_directory_declarations, [
      { directory: "real", line: 2, },
    ])
    assert_true(
      doc.cases[0].expected.matches({
        output: line + "\n",
        diagnostic: "",
        exit_code: 0,
      }),
    )
    assert_error_contains(
      () => ignore(parse_example("$ moonx ./a.mbtx\n" + line + "\n")),
      "example.md:3: #cwd must be the first nonempty line",
    )
  }
}
