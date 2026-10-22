///|
fn document_failure(source : String) -> @diagnostic.Diagnostic raise {
  try parse_document("source.md", source) catch {
    @diagnostic.Failure(d) => d
    e => raise e
  } noraise {
    _ => fail("expected invalid document: " + source)
  }
}

///|
fn primary_source(d : @diagnostic.Diagnostic) -> @diagnostic.SourceRange raise {
  guard d.primary is Some({ location: Source(range), .. }) else {
    fail(
      "missing source label: " + @diagnostic.error_text(@diagnostic.Failure(d)),
    )
  }
  assert_eq(d.file, Some(range.file))
  assert_eq(d.line, Some(range.line))
  range
}

///|
test "command locations map through containers indentation and every line ending" {
  for
    (opening, prefix, closing) in [
      ("", "", ""),
      ("> ", "> ", "> "),
      ("- ", "  ", "  "),
      ("> - ", ">   ", ">   "),
      ("  ", "  ", "  "),
      ("- outer\n  > 1. inner\n  >      ", "  >      ", "  >      "),
      ("-   ", "\t", "    "),
      (">   ", ">\t", ">   "),
    ] {
    for newline in ["\n", "\r\n", "\r"] {
      for final_newline in ["", newline] {
        for
          command in [
            "$ moonx a 中😀 \\| >file", "$ moonx a|moonx ''", "$ moonx",
          ] {
          let header = "序😀" +
            newline +
            opening.replace_all(old="\n", new=newline) +
            "```mooncram" +
            newline
          let source = header +
            prefix +
            command +
            newline +
            closing +
            "```" +
            final_newline
          let d = document_failure(source)
          let loc = primary_source(d)
          let relative = if command.has_suffix(">file") {
            command.length() - 5
          } else if command.has_suffix("''") {
            command.length() - 2
          } else {
            command.length()
          }
          let width = if command.has_suffix(">file") {
            1
          } else if command.has_suffix("''") {
            2
          } else {
            0
          }
          let start = header.length() + prefix.length() + relative
          assert_eq((loc.start, loc.end), (start, start + width))
          assert_eq(loc.source_line, prefix + command)
          assert_eq(loc.line_start, header.length())
          assert_eq(loc.line, 3 + opening.split("\n").count() - 1)
          assert_true(loc.precise && loc.is_command)
          assert_eq(
            source[loc.start:loc.end],
            command[relative:relative + width],
          )
          assert_eq(loc.end - loc.start, width)
        }
      }
    }
  }
}

///|
test "expectation source ranges exclude annotations and map virtual tab spaces" {
  for
    (opening, prefix, closing, wanted) in [
      ("", "", "", "["),
      ("> - ", ">   ", ">   ", "["),
      ("- ", "\t", "  ", "\t["),
    ] {
    let command_prefix = if opening == "- " { "  " } else { prefix }
    let header = opening + "```mooncram\r\n" + command_prefix + "$ moonx a\r\n"
    let source = header + prefix + "[ (regex) (no-eol)\r\n" + closing + "```"
    let loc = primary_source(document_failure(source))
    assert_eq(source[loc.start:loc.end], wanted[:])
    assert_eq(loc.line, 3)
    assert_eq(loc.line_start, header.length())
    assert_eq(loc.source_line, prefix + "[ (regex) (no-eol)")
    assert_true(loc.precise && !loc.is_command)
  }
  let header = "- ```mooncram\n  $ moonx a\n"
  let source = header + "\t\"中😀\\q\" (escaped)\n  ```"
  let d = document_failure(source)
  let loc = primary_source(d)
  assert_eq(source[loc.start:loc.end], "q"[:])
  assert_eq(loc.start, header.length() + 6)
  assert_eq(loc.source_line, "\t\"中😀\\q\" (escaped)")
  assert_eq(d.command, Some("$ moonx a"))
}

///|
test "mapping virtual spaces and uncertain ranges uses source boundaries" {
  let source = "- ```mooncram\n  $ moonx a\n\t中😀x\n  ```"
  let parsed = @cmark.Doc::from_string(
    source,
    file="source.md",
    locs=true,
    layout=true,
    strict=true,
  )
  let blocks = []
  collect_blocks(parsed.block, blocks, [])
  let node = blocks[0].0.v.code.to_array()[1]
  let lines = source_lines(source)
  let start = lines[2].start
  assert_eq(node.v, "  中😀x")
  for
    (from, to, raw_start, raw_end) in [
      (0, 1, 0, 1),
      (1, 2, 0, 1),
      (0, 2, 0, 1),
      (1, 1, 0, 0),
      (2, 2, 1, 1),
      (2, 3, 1, 2),
      (3, 5, 2, 4),
      (6, 6, 5, 5),
    ] {
    guard source_range(
        "source.md",
        source,
        lines,
        node,
        { row: 0, start: from, end: to, },
        offset=0,
        is_command=false,
      )
      is Some(loc) else {
      fail("missing mapping")
    }
    assert_true(loc.precise)
    assert_eq((loc.start, loc.end), (start + raw_start, start + raw_end))
  }
  for (from, to) in [(-1, 0), (0, 100), (3, 4), (4, 5), (2, 1)] {
    guard source_range(
        "source.md",
        source,
        lines,
        node,
        { row: 0, start: from, end: to, },
        offset=0,
        is_command=false,
      )
      is Some(loc) else {
      fail("missing fallback")
    }
    assert_true(!loc.precise)
    assert_eq((loc.start, loc.end), (start, start + 5))
    assert_eq(loc.source_line, "\t中😀x")
  }
  guard source_range(
      "source.md",
      source,
      lines,
      { ..node, v: "  中😀y", },
      { row: 0, start: 2, end: 3, },
      offset=0,
      is_command=false,
    )
    is Some(loc) else {
    fail("missing fallback")
  }
  assert_true(!loc.precise)
  guard source_range(
      "source.md",
      source,
      lines,
      { ..node, v: "😀xxx", },
      { row: 0, start: 0, end: 1, },
      offset=0,
      is_command=false,
    )
    is Some(loc) else {
    fail("missing fallback at surrogate boundary")
  }
  assert_true(!loc.precise)
}

///|
test "no-eol primary and related positions stay within their stream" {
  for
    (body, line, next_line) in [
      ("a (no-eol)\nb\n", 3, 4),
      ("a (no-eol)\n\nb\n", 3, 4),
      ("@STDOUT\na (no-eol)\nb\n@STDERR\n", 4, 5),
      ("@STDERR\nerr\n@STDOUT\na (no-eol)\nb\n", 6, 7),
      ("a (no-eol)\nb\n[2]\n", 3, 4),
    ] {
    let source = "> ```mooncram\r\n> $ moonx a\r\n> " +
      body.replace_all(old="\n", new="\r\n> ") +
      "```\r\n"
    let d = document_failure(source)
    let primary = primary_source(d)
    assert_eq(primary.line, line)
    assert_eq(source[primary.start:primary.end], "(no-eol)"[:])
    assert_eq(d.related.length(), 1)
    guard d.related[0].location is Source(related) else {
      fail("missing related source")
    }
    assert_eq(related.line, next_line)
    assert_eq(related.file, primary.file)
    assert_eq(d.related[0].message, Some("subsequent output line"))
    assert_eq(
      source[related.start:related.end],
      if body.contains("\n\nb") {
        ""[:]
      } else {
        "b"[:]
      },
    )
  }
  for
    body in [
      "a (no-eol)\n\n", "a (no-eol)\n[2]\n", "@STDOUT\na (no-eol)\n\n@STDERR\nb (no-eol)\n\n[2]\n",
      "@STDERR\nb (no-eol)\n\n@STDOUT\na (no-eol)\n\n",
    ] {
    ignore(
      parse_document("source.md", "```mooncram\n$ moonx a\n" + body + "```\n"),
    )
  }
}
