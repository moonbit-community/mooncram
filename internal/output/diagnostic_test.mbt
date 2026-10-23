///|
fn output_failure(row : String) -> @diagnostic.Diagnostic raise {
  try parse_example("$ moonx ./a.mbtx\n" + row + "\n") catch {
    @diagnostic.Failure(d) => d
    e => raise e
  } noraise {
    _ => fail("expected invalid output: " + row)
  }
}

///|
fn output_source(d : @diagnostic.Diagnostic) -> @diagnostic.SourceRange raise {
  guard d.primary is Some({ location: Source(source), .. }) else {
    fail("missing source range")
  }
  assert_eq(d.file, Some("example.md"))
  assert_eq(d.line, Some(3))
  assert_eq(d.command, Some("$ moonx ./a.mbtx"))
  assert_true(source.precise && !source.is_command)
  source
}

///|
test "glob errors retain exact messages for incomplete escapes sets and reversed ranges" {
  for
    (pattern, summary) in [
      ("abc\\", "trailing backslash in glob"),
      ("😀\\", "trailing backslash in glob"),
      ("[\\", "trailing backslash in glob set"),
      ("[a-\\", "trailing backslash in glob set"),
      ("[", "unclosed or empty character set in glob"),
      ("[]", "unclosed or empty character set in glob"),
      ("[!]", "unclosed or empty character set in glob"),
      ("[^]", "unclosed or empty character set in glob"),
      ("[a", "unclosed or empty character set in glob"),
      ("[a-", "unclosed or empty character set in glob"),
      ("[a\\]", "unclosed or empty character set in glob"),
      ("[z-a]", "reversed character range in glob"),
      ("[z-a", "reversed character range in glob"),
      ("[😃-😀]", "reversed character range in glob"),
    ] {
    for annotation in [" (glob)", " (glob) (no-eol)"] {
      let d = output_failure(pattern + annotation)
      assert_eq(d.summary, summary)
      assert_eq(d.file, Some("example.md"))
      assert_eq(d.line, Some(3))
      assert_eq(d.cause, None)
    }
  }
}

///|
test "regex failures preserve the original pattern and its unwrapped cause" {
  for pattern in ["[", "[z-a]", "(abc", "abc\\", "中😀["] {
    let cause = try @string.Regex(pattern) catch {
      e => e.to_string()
    } noraise {
      _ => fail("expected regex failure")
    }
    for annotation in [" (regex)", " (regex) (no-eol)"] {
      let d = output_failure(pattern + annotation)
      let source = output_source(d)
      assert_eq(d.summary, "invalid regex")
      assert_eq(d.cause, Some(cause))
      assert_eq(
        (source.start - source.line_start, source.end - source.line_start),
        (0, pattern.length()),
      )
      assert_eq(source.source_line, pattern + annotation)
    }
  }
}

///|
test "JSON syntax failures preserve reasons and mark codepoints or end of input" {
  for
    (encoded, start, end) in [
      ("\"\\q\"", 2, 3),
      ("\"中😀\\q\"", 5, 6),
      ("\"ok\"😀", 4, 6),
      ("\"中😀\" x", 6, 7),
      ("\"unfinished", 11, 11),
      ("[1,", 3, 3),
      ("", 0, 0),
    ] {
    let cause = try @json.parse(encoded) catch {
      e => e.to_string()
    } noraise {
      _ => fail("expected JSON failure")
    }
    for annotation in [" (escaped)", " (escaped) (no-eol)"] {
      let d = output_failure(encoded + annotation)
      let source = output_source(d)
      assert_eq(d.summary, "invalid JSON in (escaped) output")
      assert_eq(d.cause, Some(cause))
      assert_eq(
        (source.start - source.line_start, source.end - source.line_start),
        (start, end),
      )
      assert_eq(source.source_line, encoded + annotation)
      assert_eq(
        source.source_line[source.start - source.line_start:source.end -
        source.line_start],
        encoded[start:end],
      )
    }
  }
  let encoded = "[".repeat(1025)
  let d = output_failure(encoded + " (escaped)")
  let source = output_source(d)
  assert_eq(
    (source.start - source.line_start, source.end - source.line_start),
    (0, encoded.length()),
  )
  assert_true(d.cause is Some(cause) && cause.contains("Depth limit exceeded"))
}

///|
test "JSON type and decoded LF failures highlight the full encoded value" {
  for
    (encoded, kind) in [
      ("null", "null"),
      ("true", "boolean"),
      ("false", "boolean"),
      ("42", "number"),
      ("[\"中😀\"]", "array"),
      ("{\"a\":1}", "object"),
    ] {
    let d = output_failure(" \t" + encoded + "  (escaped)")
    let source = output_source(d)
    assert_eq(d.summary, "(escaped) requires a JSON string, got " + kind)
    assert_eq(d.cause, None)
    assert_eq(
      (source.start - source.line_start, source.end - source.line_start),
      (2, 2 + encoded.length()),
    )
  }
  for encoded in ["\"a\\nb\"", "\"中😀\\u000a\"", "\"\\n\""] {
    let d = output_failure(" " + encoded + " (escaped) (no-eol)")
    let source = output_source(d)
    assert_eq(d.summary, "an escaped output line cannot contain LF")
    assert_eq(
      (source.start - source.line_start, source.end - source.line_start),
      (1, 1 + encoded.length()),
    )
  }
}

///|
test "regex composition preserves alternations laziness empty matches and Unicode anchoring" {
  for
    (pattern, matching, nonmatching) in [
      ("a|ab", "ab", "abc"),
      ("a|ab", "a", "xa"),
      ("foo|bar", "bar", "xbar"),
      ("a+?", "aaa", "aaab"),
      (".*?", "中😀", "中😀\n"),
      ("", "", "a"),
      ("a*?", "", "b"),
      ("中.|😀", "中🚀", "中🚀x"),
      ("中.|😀", "😀", "x😀"),
    ] {
    assert_output(pattern + " (regex)\n", matching + "\n", 0, true)
    assert_output(pattern + " (regex)\n", nonmatching + "\n", 0, false)
  }
}
