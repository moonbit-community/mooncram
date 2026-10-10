///|
fn exit_marker(text : String) -> Int? raise {
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
  let markers : Array[(Int, Stream, StreamConstraint)] = []
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
pub fn normalize_output(text : String) -> String {
  text.replace_all(old="\r\n", new="\n")
}

///|
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
pub fn Stream::label(self : Stream) -> String {
  match self {
    Stdout => "@STDOUT"
    Stderr => "@STDERR"
  }
}

///|
pub fn Stream::select(self : Stream, actual : Captured) -> String {
  match self {
    Stdout => actual.output
    Stderr => actual.diagnostic
  }
}

///|
pub fn Expectation::matches(self : Expectation, actual : Captured) -> Bool {
  self.exit_code == actual.exit_code &&
  (match self.body {
    Legacy(expected) => expected.matches(actual.output)
    Streams(sections) =>
      sections.iter().all(s => s.constraint.matches(s.stream.select(actual)))
  })
}
