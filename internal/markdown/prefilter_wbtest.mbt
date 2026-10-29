///|
test "documents without candidate fences retain their path and source" {
  for
    source in [
      "", "Plain Markdown with mooncram mentioned but no fence.\n中文😀\n", "# Heading\n\n```text\n$ moonx ignored\n```\n",
      "```Mooncram\n$ moonx ignored\n```\n", "```MOONCRAM\n$ moonx ignored\n```\n",
      "~~~mooncram\n$ moonx ignored\n~~~\n", "``mooncram``\n", "```text\nAn unclosed block in another language.\n",
    ] {
    let doc = parse_document("docs/empty.md", source)
    assert_eq(doc.path, "docs/empty.md")
    assert_eq(doc.source, source)
    assert_true(doc.cases.is_empty())
    assert_true(doc.fences.is_empty())
    assert_true(doc.module_declarations.is_empty())
    assert_true(doc.working_directory_declarations.is_empty())
  }
}

///|
test "candidate fences preserve containers whitespace line endings and entities" {
  for newline in ["\n", "\r\n", "\r"] {
    for fence in ["```", "````", "``````"] {
      for
        info in [
          "mooncram", " mooncram", "\tmooncram", " \t mooncram\t", "&#109;ooncram",
          "m&#x6f;oncram", "mooncr&#97;m", "&#109;&#111;&#111;&#110;&#99;&#114;&#97;&#109;",
        ] {
        for
          (opening, prefix) in [
            ("", ""),
            ("  ", "  "),
            ("> ", "> "),
            ("- ", "  "),
            ("> - ", ">   "),
          ] {
          let source = "# 中文😀" +
            newline +
            newline +
            opening +
            fence +
            info +
            newline +
            prefix +
            "$ moonx ./a.mbtx" +
            newline +
            prefix +
            "hello" +
            newline +
            prefix +
            fence +
            newline
          let doc = parse_document("candidate.md", source)
          assert_eq(doc.cases.length(), 1, msg=source)
          assert_eq(doc.fences.length(), 1)
          assert_eq(doc.cases[0].command, "$ moonx ./a.mbtx")
          assert_eq(doc.cases[0].line, 4)
          assert_eq(doc.cases[0].newline, newline)
          assert_eq(doc.cases[0].expected.source_lines, ["hello"])
          let span = doc.fences[0]
          assert_eq(source[span.opening_start:span.opening_end], fence[:])
          assert_eq(source[span.closing_start:span.closing_end], fence[:])
        }
      }
    }
  }
}

///|
test "candidate configuration-only fences retain declarations and layout" {
  let source = "> - ````&#109;ooncram user/foo\r\n>   #cwd(../fixtures)\r\n>   ````\r\n"
  let doc = parse_document("config.md", source)
  assert_eq(doc.path, "config.md")
  assert_eq(doc.source, source)
  assert_true(doc.cases.is_empty())
  assert_eq(doc.fences.length(), 1)
  assert_eq(doc.module_declarations, [("user/foo", 1)])
  assert_eq(doc.working_directory_declarations, [
    { directory: "../fixtures", line: 2, },
  ])
}

///|
test "candidate false positives still follow Markdown fence recognition" {
  for
    source in [
      "Inline ```mooncram text is not a test fence.\n", "```mooncram-example\n$ moonx ignored\n```\n",
      "```other&name\n$ moonx ignored\n```\n", "````markdown\n```mooncram\n$ moonx ignored\n```\n````\n",
      "~~~~markdown\n```mooncram\n$ moonx ignored\n```\n~~~~\n", "    ```mooncram\n    $ moonx ignored\n    ```\n",
    ] {
    let doc = parse_document("example.md", source)
    assert_eq(doc.source, source)
    assert_true(doc.cases.is_empty(), msg=source)
    assert_true(doc.fences.is_empty())
    assert_true(doc.module_declarations.is_empty())
    assert_true(doc.working_directory_declarations.is_empty())
  }
}

///|
test "candidate errors keep the original diagnostic and opening line" {
  for info in ["mooncram", " mooncram", "\tmooncram", "&#109;ooncram"] {
    for newline in ["\n", "\r\n", "\r"] {
      let opening = "text" + newline + newline + "> ````" + info
      for
        (suffix, message) in [
          (newline + "> ````" + newline, "empty mooncram block"),
          (newline + "> $ moonx ./a.mbtx" + newline, "unclosed mooncram fence"),
          (
            " user//foo" + newline + "> #cwd(.)" + newline + "> ````" + newline,
            "invalid mooncram module declaration: user//foo",
          ),
        ] {
        assert_error_contains(
          () => ignore(parse_document("invalid.md", opening + suffix)),
          "invalid.md:3: " + message,
        )
      }
    }
  }
}
