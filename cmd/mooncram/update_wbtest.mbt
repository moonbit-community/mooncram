///|
test "update special output round trips and is idempotent" {
  let source = "Intro\n\n```mooncram\n$ ./a.mbtx\nold\n\n$ ./b.mbtx\nkeep * (glob)\n```\nTail"
  let doc = parse_document("test.md", source, default_config())
  for
    output in [
      "", "\n", "\n\n", "😀  \n", "$ ./other.mbtx\n[2]\n```\n", "x (regex)\n",
      "\u0000\u001b\t\r\\\"", "final", "\nlast",
    ] {
    let actual = { output, diagnostic: "", exit_code: 4, }
    let updated = apply_edits(source, [case_edit(doc.cases[0], actual)])
    let parsed = parse_document("test.md", updated, default_config())
    assert_eq(parsed.cases.length(), 2)
    assert_true(parsed.cases[0].expected.matches(actual), msg=updated)
    assert_eq(
      apply_edits(updated, [case_edit(parsed.cases[0], actual)]),
      updated,
    )
    assert_true(updated.has_suffix("\n\n$ ./b.mbtx\nkeep * (glob)\n```\nTail"))
  }
}

///|
test "matching patterns and explicit equal lines survive partial failures" {
  let doc = parse_example(
    "$ ./a.mbtx\nversion * (glob)\n[0-9]+ (regex)\nold\n (equal)\n",
  )
  let actual = {
    output: "version 9\n123\nnew\n\n",
    diagnostic: "",
    exit_code: 2,
  }
  let updated = apply_edits(doc.source, [case_edit(doc.cases[0], actual)])
  assert_true(
    updated.contains("version * (glob)\n[0-9]+ (regex)\nnew\n (equal)\n[2]"),
  )
  assert_true(
    parse_document("example.md", updated, default_config()).cases[0].expected.matches(
      actual,
    ),
  )
}

///|
test "exit-only updates and multiple replacements preserve source text" {
  let doc = parse_example("$ ./a.mbtx\n\n$ ./b.mbtx\n[2]\n")
  let one = { output: "", diagnostic: "", exit_code: 3, }
  let two = { output: "", diagnostic: "", exit_code: 0, }
  let updated = apply_edits(doc.source, [
    case_edit(doc.cases[0], one),
    case_edit(doc.cases[1], two),
  ])
  assert_eq(updated, "```mooncram\n$ ./a.mbtx\n[3]\n\n$ ./b.mbtx\n```\n")
}

///|
test "retained blank and status-looking output is safe when it becomes final" {
  for (body, output) in [("a\n\nb\n", "a\n\n"), ("[2]\nb\n", "[2]\n")] {
    let doc = parse_example("$ ./a.mbtx\n" + body)
    let actual = { output, diagnostic: "", exit_code: 0, }
    let updated = apply_edits(doc.source, [case_edit(doc.cases[0], actual)])
    assert_true(
      parse_document("example.md", updated, default_config()).cases[0].expected.matches(
        actual,
      ),
    )
  }
}

///|
test "existing container spelling and mixed line endings survive an update" {
  let source = "> ```mooncram\r\n>$ ./a.mbtx\n>keep * (glob)\r\n> old\n> ```\r\n"
  let doc = parse_document("mixed.md", source, default_config())
  let actual = { output: "keep me\nnew\n", diagnostic: "", exit_code: 0, }
  let updated = apply_edits(source, [case_edit(doc.cases[0], actual)])
  assert_eq(updated, source.replace(old="> old", new="> new"))
  assert_true(
    parse_document("mixed.md", updated, default_config()).cases[0].expected.matches(
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
    let doc = parse_document("indent.md", source, default_config())
    let actual = {
      output: "  leading\n   \nnext",
      diagnostic: "",
      exit_code: 0,
    }
    let updated = apply_edits(source, [case_edit(doc.cases[0], actual)])
    assert_true(
      parse_document("indent.md", updated, default_config()).cases[0].expected.matches(
        actual,
      ),
      msg=updated,
    )
  }
}

///|
test "failure report includes location command diff exit and diagnostic stream" {
  let case = parse_example("$ ./a.mbtx arg\nold\n").cases[0]
  let report = failure_report(
    "test.md",
    case,
    { output: "new", diagnostic: "bad\n", exit_code: 7, },
    false,
  )
  for
    expected in [
      "test.md:2", "$ ./a.mbtx arg", "expected 0, actual 7", "-old", "+new (no-eol)",
      "diagnostic stderr\nbad",
    ] {
    assert_true(report.contains(expected), msg=report)
  }
  assert_true(!report.contains("\u001b"))
}

///|
test "artifact JSON is validated" {
  assert_eq(
    parse_artifact("{\"artifacts_path\":[\"/tmp/a.wasm\"]}\n"),
    "/tmp/a.wasm",
  )
  for
    text in [
      "not JSON", "{}", "{\"artifacts_path\":[]}", "{\"artifacts_path\":[\"a\",\"b\"]}",
    ] {
    assert_error_contains(() => ignore(parse_artifact(text)), "artifact")
  }
}
