///|
fn exit_marker(text : String) -> Int32? raise {
  if !text.has_prefix("[") || !text.has_suffix("]") {
    return None
  }
  let value = text[1:text.length() - 1].to_owned()
  let digits = if value.has_prefix("-") { value[1:].to_owned() } else { value }
  if digits == "" || !digits.iter().all(c => c >= '0' && c <= '9') {
    return None
  }
  Some(
    @string.parse_int(value) catch {
      _ => raise @diagnostic.Failure("exit status is out of range")
    },
  )
}

///|
fn parse_expected_line(raw : String) -> ExpectedLine raise {
  let matcher = if raw.has_suffix(" (escaped)") {
    let encoded = raw[:raw.length() - 10].to_owned()
    let value = @json.parse(encoded) catch {
      _ => raise @diagnostic.Failure("(escaped) requires a JSON string")
    }
    guard value is String(text) else {
      raise @diagnostic.Failure("(escaped) requires a JSON string")
    }
    if text.contains("\n") {
      raise @diagnostic.Failure("an escaped output line cannot contain LF")
    }
    Equal(text)
  } else if raw.has_suffix(" (glob)") {
    Glob(parse_glob(raw[:raw.length() - 7].to_owned()))
  } else if raw.has_suffix(" (regex)") {
    let pattern = raw[:raw.length() - 8].to_owned()
    Regex(
      @string.Regex("^(?:\{pattern})$") catch {
        e =>
          raise @diagnostic.Failure(
            "invalid regex: \{@diagnostic.error_text(e)}",
          )
      },
    )
  } else {
    Equal(raw)
  }
  { raw, matcher, }
}

///|
fn parse_stream_lines(
  nodes : ArrayView[@cmark.Node[String]],
  file : String,
) -> StreamExpectation raise {
  let lines = []
  let mut no_eol = false
  for node in nodes {
    let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
    try {
      if no_eol {
        raise @diagnostic.Failure("(no-eol) must be on the final output line")
      }
      no_eol = node.v.has_suffix(" (no-eol)")
      let raw = if no_eol {
        node.v[:node.v.length() - 9].to_owned()
      } else {
        node.v
      }
      let parsed = parse_expected_line(raw)
      if no_eol && parsed.matcher is Equal("") {
        raise @diagnostic.Failure(
          "an empty output line cannot have (no-eol); omit it for empty output",
        )
      }
      lines.push({ ..parsed, raw: node.v, })
    } catch {
      e => raise @diagnostic.located(file, line, @diagnostic.error_text(e))
    }
  }
  { lines, no_eol, }
}

///|
// Only the exact uppercase marker name, followed by whitespace or end of line,
// is reserved. JSON-escaped spellings never enter this parser.
fn reserved_stream(text : String) -> Stream? {
  if text == "@STDOUT" ||
    text.has_prefix("@STDOUT ") ||
    text.has_prefix("@STDOUT\t") {
    Some(Stdout)
  } else if text == "@STDERR" ||
    text.has_prefix("@STDERR ") ||
    text.has_prefix("@STDERR\t") {
    Some(Stderr)
  } else {
    None
  }
}

///|
fn stream_marker(text : String) -> (Stream, StreamConstraint)? raise {
  guard reserved_stream(text) is Some(stream) else { return None }
  let suffix = text[7:].to_owned()
  let constraint = match suffix {
    "" => Match({ lines: [], no_eol: false, })
    " (ignore)" => Ignore
    " (empty)" => Empty
    _ => raise @diagnostic.Failure("unknown stream marker annotation: " + text)
  }
  Some((stream, constraint))
}

///|
/// Parse the logical expectation rows following a Markdown command.
///
/// `nodes` excludes the command and enclosing fence, and retains cmark source
/// locations for one-based diagnostics using `file`. A final `[N]` sets the
/// pipeline exit code (default 0). Without stream markers all rows constrain
/// stdout. With markers, `@STDOUT` and `@STDERR` must each occur exactly once;
/// optional `(ignore)`/`(empty)` sections accept no output rows. Trailing bare
/// blanks within paired sections are separators; legacy rows are not trimmed
/// here, so callers should remove their outer separator blanks first.
///
/// Line suffixes support whole-line `(glob)`, `(regex)` and JSON `(escaped)`
/// matching, with `(no-eol)` only on a nonempty final output line per stream.
/// Raises located `@diagnostic.Failure` for invalid patterns/escapes, marker
/// placement, final-newline annotations or out-of-range exit statuses. Original
/// row spellings are preserved in `Expectation.source_lines`.
pub fn parse_expectation(
  nodes : ArrayView[@cmark.Node[String]],
  file : String,
) -> Expectation raise {
  let source_lines = nodes.map(n => n.v)
  let mut exit_code = 0
  let mut end = nodes.length()
  if end > 0 {
    let node = nodes[end - 1]
    let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
    if (exit_marker(node.v) catch {
        e => raise @diagnostic.located(file, line, @diagnostic.error_text(e))
      })
      is Some(code) {
      exit_code = code
      end -= 1
    }
  }
  let markers : Array[(Int32, Stream, StreamConstraint)] = []
  for i in 0..<end {
    let node = nodes[i]
    let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
    if (stream_marker(node.v) catch {
        e => raise @diagnostic.located(file, line, @diagnostic.error_text(e))
      })
      is Some((stream, constraint)) {
      if markers.iter().any(m => m.1 == stream) {
        raise @diagnostic.located(
          file,
          line,
          "duplicate " + stream.label() + " marker",
        )
      }
      markers.push((i, stream, constraint))
    }
  }
  let body = if markers.is_empty() {
    Legacy(parse_stream_lines(nodes[:end], file))
  } else {
    let first = markers[0].0
    for i in 0..<first {
      if nodes[i].v != "" {
        let @cmark_base.LinePos(line, _) = nodes[i].meta.loc.first_line
        raise @diagnostic.located(
          file, line, "expected output before a stream marker",
        )
      }
    }
    if markers.length() != 2 {
      let @cmark_base.LinePos(line, _) = nodes[first].meta.loc.first_line
      raise @diagnostic.located(
        file, line, "@STDOUT and @STDERR must both appear once",
      )
    }
    let sections = []
    for j, (start, stream, mode) in markers {
      let section_end = if j + 1 < markers.length() {
        markers[j + 1].0
      } else {
        end
      }
      let mut content_end = section_end
      while content_end > start + 1 && nodes[content_end - 1].v == "" {
        content_end -= 1
      }
      let constraint = match mode {
        Match(_) =>
          Match(parse_stream_lines(nodes[start + 1:content_end], file))
        Ignore | Empty => {
          if content_end > start + 1 {
            let @cmark_base.LinePos(line, _) = nodes[start + 1].meta.loc.first_line
            raise @diagnostic.located(
              file, line, "(ignore) and (empty) sections do not accept output lines",
            )
          }
          mode
        }
      }
      sections.push({
        stream,
        constraint,
        start,
        content_end,
        end: section_end,
      })
    }
    Streams(sections)
  }
  { body, exit_code, source_lines, }
}

///|
/// Replace CRLF pairs with LF without changing any other output characters.
///
/// Preserves standalone CR, trailing spaces, blank lines and final-newline state.
/// Apply before matching or rendering manually captured text.
///
/// ```mbt check
/// test {
///   assert_eq(@output.normalize_output("a\r\nb\r"), "a\nb\r")
/// }
/// ```
pub fn normalize_output(text : String) -> String {
  text.replace_all(old="\r\n", new="\n")
}

///|
/// Split output on LF and return `(lines, no_eol)`.
///
/// A terminating LF is removed as a delimiter, preserving preceding empty
/// lines. Empty text returns `([], false)`; a single LF returns `([""], false)`.
/// For nonempty text `no_eol` is true exactly when the final LF is absent.
/// Does not normalize CRLF; call `normalize_output` first when needed.
///
/// ```mbt check
/// test {
///   assert_eq(@output.output_lines(""), ([], false))
///   assert_eq(@output.output_lines("\n"), ([""], false))
///   assert_eq(@output.output_lines("hello"), (["hello"], true))
///   assert_eq(@output.output_lines("hello\n\n"), (["hello", ""], false))
/// }
/// ```
pub fn output_lines(text : String) -> (Array[String], Bool) {
  if text == "" {
    return ([], false)
  }
  let lines = text.split("\n").map(s => s.to_owned()).to_array()
  let no_eol = !text.has_suffix("\n")
  if !no_eol {
    ignore(lines.pop())
  }
  (lines, no_eol)
}

///|
fn Matcher::matches(self : Matcher, text : String) -> Bool {
  match self {
    Equal(expected) => expected == text
    Glob(tokens) => match_glob(tokens, text)
    Regex(regex) =>
      regex.execute(text) is Some(result) && result.content() == text
  }
}

///|
fn StreamExpectation::matches(self : StreamExpectation, text : String) -> Bool {
  let (lines, no_eol) = output_lines(text)
  if self.no_eol != no_eol || self.lines.length() != lines.length() {
    return false
  }
  for i, expected in self.lines {
    if !expected.matcher.matches(lines[i]) {
      return false
    }
  }
  true
}

///|
/// Check normalized stream text against this content policy.
///
/// `Match` checks line count, each whole-line matcher and final-newline state;
/// `Ignore` always succeeds; `Empty` succeeds only for the empty string.
/// The text is neither decoded nor CRLF-normalized by this function.
pub fn StreamConstraint::matches(
  self : StreamConstraint,
  text : String,
) -> Bool {
  match self {
    Match(expected) => expected.matches(text)
    Ignore => true
    Empty => text == ""
  }
}

///|
/// Return the exact Markdown marker `"@STDOUT"` or `"@STDERR"` for this stream.
pub fn Stream::label(self : Stream) -> String {
  match self {
    Stdout => "@STDOUT"
    Stderr => "@STDERR"
  }
}

///|
/// Select `actual.output` for stdout or `actual.diagnostic` for stderr.
///
/// Returns the stored text unchanged, without normalization or newline insertion.
pub fn Stream::select(self : Stream, actual : Captured) -> String {
  match self {
    Stdout => actual.output
    Stderr => actual.diagnostic
  }
}

///|
/// Check both the pipeline exit code and all requested stream constraints.
///
/// Legacy expectations compare only stdout; paired expectations compare each
/// section using its policy. `actual` should contain normalized text as returned
/// by execution; this method does not normalize it or render diagnostics.
pub fn Expectation::matches(self : Expectation, actual : Captured) -> Bool {
  self.exit_code == actual.exit_code &&
  (match self.body {
    Legacy(expected) => expected.matches(actual.output)
    Streams(sections) =>
      sections.iter().all(s => s.constraint.matches(s.stream.select(actual)))
  })
}
