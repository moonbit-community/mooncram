///|
/// JSON strings make command/status/fence-looking lines, known annotation
/// suffixes, and control characters unambiguous. Ordinary output stays readable.
fn encode_output_line(text : String) -> String {
  let needs_escape = text == "" ||
    text.has_prefix(" ") ||
    text.has_prefix("$") ||
    text.has_prefix("[") ||
    reserved_stream(text) is Some(_) ||
    text.contains("`") ||
    text.has_suffix(" (escaped)") ||
    text.has_suffix(" (glob)") ||
    text.has_suffix(" (regex)") ||
    text.has_suffix(" (no-eol)") ||
    text.iter().any(c => c < ' ' || c == '\u007f')
  if needs_escape {
    "\{Json::string(text).stringify()} (escaped)"
  } else {
    text
  }
}

///|
fn render_stream(text : String, expected : StreamExpectation) -> Array[String] {
  let (lines, no_eol) = output_lines(text)
  let rendered = []
  for i, line in lines {
    // Retain matching patterns even when a different line or exit code fails.
    let mut text = match expected.lines.get(i) {
      Some(old) if old.matcher.matches(line) &&
        old.raw != "" &&
        !(old.raw.has_prefix("[") && old.raw.has_suffix("]")) =>
        if old.raw.has_suffix(" (no-eol)") {
          old.raw[:old.raw.length() - 9].to_owned()
        } else {
          old.raw
        }
      _ => encode_output_line(line)
    }
    if no_eol && i == lines.length() - 1 {
      text += " (no-eol)"
    }
    rendered.push(text)
  }
  rendered
}

///|
pub fn actual_stream_expectation(
  text : String,
  constraint : StreamConstraint,
) -> Array[String] {
  match constraint {
    Ignore => []
    Empty => render_stream(text, { lines: [], no_eol: false, })
    Match(expected) => render_stream(text, expected)
  }
}

///|
// Each rendered row carries its original source-row index, when it has one.
// Section growth must not borrow another section's prefix or newline spelling.
pub fn actual_expectation_layout(
  actual : Captured,
  expected : Expectation,
) -> Array[(String, Int?)] {
  let rendered = []
  match expected.body {
    Legacy(content) => {
      for i, line in render_stream(actual.output, content) {
        rendered.push((line, Some(i)))
      }
      if actual.exit_code != 0 {
        rendered.push(("[\{actual.exit_code}]", Some(rendered.length())))
      }
    }
    Streams(sections) => {
      for i in 0..<sections[0].start {
        rendered.push((expected.source_lines[i], Some(i)))
      }
      for section in sections {
        let text = section.stream.select(actual)
        if section.constraint.matches(text) {
          for i in section.start..<section.end {
            rendered.push((expected.source_lines[i], Some(i)))
          }
        } else {
          rendered.push((section.stream.label(), Some(section.start)))
          for i, line in actual_stream_expectation(text, section.constraint) {
            let row = section.start + 1 + i
            rendered.push(
              (line, if row < section.content_end { Some(row) } else { None }),
            )
          }
          for i in section.content_end..<section.end {
            rendered.push((expected.source_lines[i], Some(i)))
          }
        }
      }
      let last = sections[sections.length() - 1].end
      let status_row = if last < expected.source_lines.length() {
        Some(last)
      } else {
        None
      }
      if actual.exit_code == expected.exit_code && status_row is Some(row) {
        rendered.push((expected.source_lines[row], Some(row)))
      } else if actual.exit_code != 0 {
        rendered.push(("[\{actual.exit_code}]", status_row))
      }
    }
  }
  rendered
}

///|
pub fn actual_expectation(
  actual : Captured,
  expected : Expectation,
) -> Array[String] {
  actual_expectation_layout(actual, expected).map(row => row.0)
}
