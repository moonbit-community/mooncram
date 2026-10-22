///|
fn map_test_input(error : Error) -> @diagnostic.Failure {
  @diagnostic.map_input(error, range => {
    let (line_start, source_line) = if range.row == 0 {
      (10, "a (no-eol)")
    } else {
      (21, "b")
    }
    Some({
      file: "example.md",
      line: range.row + 3,
      start: line_start + range.start,
      end: line_start + range.end,
      line_start,
      source_line,
      precise: true,
      is_command: false,
    })
  })
}

///|
test "primary and related snapshots survive wrapping and outer locations" {
  let original = @diagnostic.with_related(
    @diagnostic.with_input(
      @diagnostic.failure("(no-eol) must be on the final output line"),
      2,
      10,
    ),
    {
      location: Input({ row: 1, start: 0, end: 1, }),
      message: Some("subsequent output line"),
    },
  )
  let mapped = map_test_input(original)
  assert_eq(
    @diagnostic.render(mapped),
    "ERROR example.md:3:3: (no-eol) must be on the final output line\n  3 | a ⟦(no-eol)⟧\n  note: example.md:4:1: subsequent output line\n  4 | ⟦b⟧\n",
  )
  let error = @diagnostic.context(
    @diagnostic.wrap(mapped, "cannot parse expectations"),
    file="outer.md",
    line=99,
    command="$ moonx app",
    phase="parse",
    hint="fix the annotation",
  )
  // A second mapping pass and an outer parser range cannot relocate snapshots.
  let error = @diagnostic.map_input(@diagnostic.with_input(error, 0, 0), _ => {
    None
  })
  let @diagnostic.Failure(d) = error
  assert_eq(d.file, Some("example.md"))
  assert_eq(d.line, Some(3))
  guard d.primary is Some({ location: Source(primary), .. }) else {
    fail("missing source")
  }
  assert_eq((primary.start, primary.end), (12, 20))
  guard d.related[0].location is Source(related) else {
    fail("missing related source")
  }
  assert_eq((related.start, related.end), (21, 22))
  assert_eq(d.cause, Some("(no-eol) must be on the final output line"))
  let report = @diagnostic.render(
    @diagnostic.with_logs(error, [
      { label: "run stderr", bytes: b"log\n", complete: true, },
    ]),
  )
  assert_eq(
    report, "ERROR example.md:3:3: cannot parse expectations\n  3 | a ⟦(no-eol)⟧\n  note: example.md:4:1: subsequent output line\n  4 | ⟦b⟧\n  $ moonx app\n  phase: parse\n  cause: (no-eol) must be on the final output line\n  hint: fix the annotation\n--- captured run stderr\nlog\n",
  )
}

///|
test "snippets escape controls and marker brackets after locating Unicode" {
  let line = "\t中😀⟦\u0000\u001b\u007f\u0085⟧"
  let error = @diagnostic.map_input(
    @diagnostic.context(
      @diagnostic.with_input(@diagnostic.failure("bad"), 2, 4),
      command=line,
    ),
    range => {
      Some({
        file: "unicode.md",
        line: 2,
        start: 10 + range.start,
        end: 10 + range.end,
        line_start: 10,
        source_line: line,
        precise: true,
        is_command: true,
      })
    },
  )
  assert_eq(
    @diagnostic.render(error),
    "ERROR unicode.md:2:3: bad\n  2 | \\t中⟦😀⟧\\u27e6\\u0000\\u001b\\u007f\\u0085\\u27e7\n",
  )
}

///|
test "zero length snippets and fallback source lines have distinct locations" {
  for precise in [true, false] {
    let error = @diagnostic.map_input(
      @diagnostic.with_input(@diagnostic.failure("missing"), 0, 0),
      _ => {
        Some({
          file: "eof.md",
          line: 8,
          start: if precise {
            19
          } else {
            10
          },
          end: 19,
          line_start: 10,
          source_line: "$ moonx  ",
          precise,
          is_command: true,
        })
      },
    )
    assert_eq(
      @diagnostic.render(error),
      if precise {
        "ERROR eof.md:8:10: missing\n  8 | $ moonx  ⟦⟧\n"
      } else {
        "ERROR eof.md:8: missing\n  8 | ⟦$ moonx  ⟧\n"
      },
    )
  }
}
