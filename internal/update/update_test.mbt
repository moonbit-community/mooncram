///|
fn parse_example(body : String) -> @markdown.Document raise {
  @markdown.parse_document("example.md", "```mooncram\n" + body + "```\n")
}

///|
test "quoted list Unicode CRLF source positions and local replacement" {
  let source = "😀\r\n\r\n> - ```mooncram\r\n>   $ ./hello.mbtx\r\n>   旧值\r\n>\r\n>   ```\r\nAfter\r\n"
  let doc = @markdown.parse_document("unicode.md", source)
  let case = doc.cases[0]
  assert_eq(case.line, 4)
  assert_eq(case.prefix, ">   ")
  assert_eq(case.newline, "\r\n")
  let updated = @update.apply_edits(source, [
    @update.case_edit(case, {
      output: "新值😀\n",
      diagnostic: "",
      exit_code: 0,
    }),
  ])
  assert_eq(updated, source.replace(old="旧值", new="新值😀"))
  assert_eq(
    @markdown.parse_document("unicode.md", updated).cases[0].expected.lines[0].raw,
    "新值😀",
  )
}

///|
test "update special output round trips and is idempotent" {
  let source = "Intro\n\n```mooncram\n$ ./a.mbtx\nold\n\n$ ./b.mbtx\nkeep * (glob)\n```\nTail"
  let doc = @markdown.parse_document("test.md", source)
  for
    output in [
      "", "\n", "\n\n", "😀  \n", "$ ./other.mbtx\n[2]\n```\n", "x (regex)\n",
      "\u0000\u001b\t\r\\\"", "final", "\nlast",
    ] {
    let actual : @output.Captured = { output, diagnostic: "", exit_code: 4, }
    let updated = @update.apply_edits(source, [
      @update.case_edit(doc.cases[0], actual),
    ])
    let parsed = @markdown.parse_document("test.md", updated)
    assert_eq(parsed.cases.length(), 2)
    assert_true(parsed.cases[0].expected.matches(actual), msg=updated)
    assert_eq(
      @update.apply_edits(updated, [@update.case_edit(parsed.cases[0], actual)]),
      updated,
    )
    assert_true(updated.has_suffix("\n\n$ ./b.mbtx\nkeep * (glob)\n```\nTail"))
  }
}

///|
test "updates keep ordinary parentheses literal and escape known suffixes" {
  let doc = parse_example("$ ./a.mbtx\nold\n")
  for
    (line, rendered) in [
      ("hello (foo)", "hello (foo)"),
      ("hello (glob) (foo)", "hello (glob) (foo)"),
      ("hello (note) tail", "hello (note) tail"),
      ("hello (GLOB)", "hello (GLOB)"),
      ("hello (glob) ", "hello (glob) "),
      ("hello(glob)", "hello(glob)"),
      ("hello (equal)", "hello (equal)"),
      ("hello (glob) (equal)", "hello (glob) (equal)"),
      ("hello (escaped)", "\"hello (escaped)\" (escaped)"),
      ("hello (glob)", "\"hello (glob)\" (escaped)"),
      ("hello (regex)", "\"hello (regex)\" (escaped)"),
      ("hello (no-eol)", "\"hello (no-eol)\" (escaped)"),
    ] {
    for newline in ["\n", ""] {
      let actual : @output.Captured = {
        output: line + newline,
        diagnostic: "",
        exit_code: 0,
      }
      let expected_line = if newline == "" {
        rendered + " (no-eol)"
      } else {
        rendered
      }
      let updated = @update.apply_edits(doc.source, [
        @update.case_edit(doc.cases[0], actual),
      ])
      assert_eq(
        updated,
        doc.source.replace(old="old\n", new=expected_line + "\n"),
      )
      let parsed = @markdown.parse_document("example.md", updated)
      assert_true(parsed.cases[0].expected.matches(actual), msg=updated)
      assert_eq(
        @update.apply_edits(updated, [
          @update.case_edit(parsed.cases[0], actual),
        ]),
        updated,
      )
    }
  }
}

///|
test "matching patterns and explicit output spellings survive partial failures" {
  let doc = parse_example(
    "$ ./a.mbtx\nversion * (glob)\n[0-9]+ (regex)\nold\n\"\" (escaped)\nhello (equal)\n\"hello (foo)\" (escaped)\nhello (foo)\n",
  )
  let actual : @output.Captured = {
    output: "version 9\n123\nnew\n\nhello (equal)\nhello (foo)\nhello (foo)\n",
    diagnostic: "",
    exit_code: 2,
  }
  let updated = @update.apply_edits(doc.source, [
    @update.case_edit(doc.cases[0], actual),
  ])
  assert_true(
    updated.contains(
      "version * (glob)\n[0-9]+ (regex)\nnew\n\"\" (escaped)\nhello (equal)\n\"hello (foo)\" (escaped)\nhello (foo)\n[2]",
    ),
  )
  assert_true(
    @markdown.parse_document("example.md", updated).cases[0].expected.matches(
      actual,
    ),
  )
}

///|
test "exit-only updates and multiple replacements preserve source text" {
  let doc = parse_example("$ ./a.mbtx\n\n$ ./b.mbtx\n[2]\n")
  let one : @output.Captured = { output: "", diagnostic: "", exit_code: 3, }
  let two : @output.Captured = { output: "", diagnostic: "", exit_code: 0, }
  let updated = @update.apply_edits(doc.source, [
    @update.case_edit(doc.cases[0], one),
    @update.case_edit(doc.cases[1], two),
  ])
  assert_eq(updated, "```mooncram\n$ ./a.mbtx\n[3]\n\n$ ./b.mbtx\n```\n")
}

///|
test "retained blank and status-looking output is safe when it becomes final" {
  for (body, output) in [("a\n\nb\n", "a\n\n"), ("[2]\nb\n", "[2]\n")] {
    let doc = parse_example("$ ./a.mbtx\n" + body)
    let actual : @output.Captured = { output, diagnostic: "", exit_code: 0, }
    let updated = @update.apply_edits(doc.source, [
      @update.case_edit(doc.cases[0], actual),
    ])
    assert_true(
      @markdown.parse_document("example.md", updated).cases[0].expected.matches(
        actual,
      ),
    )
  }
}

///|
test "existing container spelling and mixed line endings survive an update" {
  let source = "> ```mooncram\r\n>$ ./a.mbtx\n>keep * (glob)\r\n> old\n> ```\r\n"
  let doc = @markdown.parse_document("mixed.md", source)
  let actual : @output.Captured = {
    output: "keep me\nnew\n",
    diagnostic: "",
    exit_code: 0,
  }
  let updated = @update.apply_edits(source, [
    @update.case_edit(doc.cases[0], actual),
  ])
  assert_eq(updated, source.replace(old="> old", new="> new"))
  assert_true(
    @markdown.parse_document("mixed.md", updated).cases[0].expected.matches(
      actual,
    ),
  )
}

///|
test "leading output spaces survive optional Markdown fence indentation" {
  for
    source in [
      "  ```mooncram\n$ ./a.mbtx\nold\n  ```\n", "  ```mooncram\n  $ ./a.mbtx\n  old\n  ```\n",
      ">   ```mooncram\n> $ ./a.mbtx\n> old\n>   ```\n", "1. ```mooncram\n   $ ./a.mbtx\n   old\n   ```\n",
    ] {
    let doc = @markdown.parse_document("indent.md", source)
    let actual : @output.Captured = {
      output: "  leading\n   \nnext",
      diagnostic: "",
      exit_code: 0,
    }
    let updated = @update.apply_edits(source, [
      @update.case_edit(doc.cases[0], actual),
    ])
    assert_true(
      @markdown.parse_document("indent.md", updated).cases[0].expected.matches(
        actual,
      ),
      msg=updated,
    )
  }
}
