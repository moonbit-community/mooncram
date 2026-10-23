///|
fn command_failure(text : String) -> @diagnostic.Diagnostic raise {
  try @command.parse(text) catch {
    @diagnostic.Failure(d) => d
    e => raise e
  } noraise {
    _ => fail("expected invalid command: " + text)
  }
}

///|
test "command failures retain exact raw tokens and segment numbers" {
  for
    (text, start, end, segment) in [
      ("moonx ok 'missing", 9, 10, "1"),
      ("moonx ok \"missing", 9, 10, "1"),
      ("moonx ok \\", 9, 10, "1"),
      ("moonx ok >file", 9, 10, "1"),
      ("other target", 0, 5, "1/1"),
      ("'' target", 0, 2, "1/1"),
      ("moonx ''", 6, 8, "1/1"),
      ("moonx", 5, 5, "1/1"),
      ("moonx  ", 7, 7, "1/1"),
      ("A=x", 3, 3, "1/1"),
    ] {
    for prefix in ["", "moonx ok | "] {
      let d = command_failure(prefix + text)
      guard d.primary is Some({ location: Input(range), .. }) else {
        fail("missing input range")
      }
      assert_eq(range.row, 0)
      assert_eq(
        (range.start, range.end),
        (prefix.length() + start, prefix.length() + end),
      )
      assert_eq((prefix + text)[range.start:range.end], text[start:end])
      assert_eq(d.command, Some(prefix + text))
      assert_eq(
        d.segment,
        Some(
          if prefix == "" {
            segment
          } else if segment == "1" {
            "2"
          } else {
            "2/2"
          },
        ),
      )
    }
  }
}

///|
test "empty pipeline ranges identify the separator that creates the empty segment" {
  for
    (text, start, end, segment) in [
      ("", 0, 0, "1/1"),
      ("  ", 2, 2, "1/1"),
      ("|moonx a", 0, 1, "1/2"),
      ("moonx a ||moonx b", 9, 10, "2/3"),
      ("moonx a | | moonx b", 10, 11, "2/3"),
      ("moonx a |  ", 8, 9, "2/2"),
      ("moonx |moonx b", 6, 6, "1/2"),
    ] {
    let d = command_failure(text)
    guard d.primary is Some({ location: Input(range), .. }) else {
      fail("missing input range")
    }
    assert_eq((range.start, range.end), (start, end))
    assert_eq(d.segment, Some(segment))
  }
}

///|
test "lexical offsets count UTF-16 even after Unicode escapes and quoted pipes" {
  for
    prefix in [
      "moonx ok 中😀 x\\ y ", "moonx ok '中😀|x' \\| | moonx ok ",
    ] {
    for suffix in ["'", "\"", "\\", ">", "\u0000", "\n", "\r"] {
      let d = command_failure(prefix + suffix)
      guard d.primary is Some({ location: Input(range), .. }) else {
        fail("missing input range")
      }
      assert_eq(
        (range.start, range.end),
        (prefix.length(), prefix.length() + 1),
      )
      assert_eq(
        d.segment,
        Some(if prefix.has_suffix("x\\ y ") { "1" } else { "2" }),
      )
    }
  }
  let prefix = "NAME='中😀' "
  for word in ["ba\\d", "'中😀'", "b\"😀\"ad", "\"\""] {
    let d = command_failure(prefix + word)
    guard d.primary is Some({ location: Input(range), .. }) else {
      fail("missing input range")
    }
    assert_eq(
      (range.start, range.end),
      (prefix.length(), prefix.length() + word.length()),
    )
    assert_eq((prefix + word)[range.start:range.end], word[:])
  }
}

///|
test "NUL and newlines fail at the character in every quoting and escape state" {
  for segment_prefix in ["", "moonx ok|"] {
    for quote in ["", "'", "\""] {
      for escape in ["", "\\"] {
        let prefix = segment_prefix + "moonx ok " + quote + "中😀" + escape
        for control in ["\u0000", "\n", "\r"] {
          let text = prefix + control + "tail" + quote
          let d = command_failure(text)
          assert_eq(d.summary, "command contains a NUL or newline")
          assert_eq(d.hint, None)
          assert_eq(d.command, Some(text))
          assert_eq(
            d.segment,
            Some(if segment_prefix == "" { "1" } else { "2" }),
          )
          guard d.primary is Some({ location: Input(range), .. }) else {
            fail("missing input range")
          }
          assert_eq(
            (range.start, range.end),
            (prefix.length(), prefix.length() + 1),
          )
        }
      }
    }
  }
}

///|
test "lexical failures precede command validation and preserve quote and escape hints" {
  for prefix in ["other target|", "|", "moonx ''|"] {
    for
      (tail, summary, hint, offset) in [
        (
          "中😀'tail", "unclosed quote in command", "close the quote opened here",
          3,
        ),
        (
          "中😀'tail\\", "unclosed quote in command", "close the quote opened here",
          3,
        ),
        (
          "中😀\"tail", "unclosed quote in command", "close the quote opened here",
          3,
        ),
        (
          "中😀\"tail\\", "trailing backslash in command", "add the escaped character or double the backslash to pass it literally",
          8,
        ),
        (
          "中😀\\", "trailing backslash in command", "add the escaped character or double the backslash to pass it literally",
          3,
        ),
      ] {
      let d = command_failure(prefix + tail)
      assert_eq(d.summary, summary)
      assert_eq(d.hint, Some(hint))
      assert_eq(d.segment, Some("2"))
      guard d.primary is Some({ location: Input(range), .. }) else {
        fail("missing input range")
      }
      let start = prefix.length() + offset
      assert_eq((range.start, range.end), (start, start + 1))
    }
  }
}
