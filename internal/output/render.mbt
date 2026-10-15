///|
fn encode_output_line(text : String) -> String {
  let needs_escape = text == "$" ||
    text.has_prefix("$ ") ||
    text.has_prefix("#cwd(") ||
    reserved_stream(text) is Some(_) ||
    text.has_suffix(" (escaped)") ||
    text.has_suffix(" (glob)") ||
    text.has_suffix(" (regex)") ||
    text.has_suffix(" (no-eol)") ||
    text.iter().any(c => c < ' ' || c == '\u007f')
  if needs_escape {
    let encoded = Json::string(text)
      .stringify()
      .replace_all(old="\u007f", new="\\u007f")
    "\{encoded} (escaped)"
  } else {
    text
  }
}

///|
// Prefer the current pair, then a later expectation, then a later actual line.
// A replacement reuses its old row's layout; an insertion has no source row.
fn align_lines(
  lines : Array[String],
  expected : Array[ExpectedLine],
) -> Array[Int32?] {
  let rows = []
  for i = 0, j = 0; i < lines.length(); {
    if j >= expected.length() {
      rows.push(None)
      continue i + 1, j
    }
    if expected[j].matcher.matches(lines[i]) {
      rows.push(Some(j))
      continue i + 1, j + 1
    }
    let later_expected = for k = j + 1; k < expected.length(); k = k + 1 {
      if expected[k].matcher.matches(lines[i]) {
        break Some(k)
      }
    } nobreak {
      None
    }
    if later_expected is Some(k) {
      rows.push(Some(k))
      continue i + 1, k + 1
    }
    let later_actual = for k = i + 1; k < lines.length(); k = k + 1 {
      if expected[j].matcher.matches(lines[k]) {
        break Some(k)
      }
    } nobreak {
      None
    }
    if later_actual is Some(k) {
      for _ in i..<k {
        rows.push(None)
      }
      continue k, j
    }
    rows.push(Some(j))
    continue i + 1, j + 1
  }
  rows
}

///|
fn stream_layout(
  text : String,
  expected : Array[ExpectedLine],
  protect_blank~ : Bool,
) -> Array[(String, Int32?)] {
  let (lines, no_eol) = output_lines(text)
  let rows = align_lines(lines, expected)
  lines.mapi((i, line) => {
    let row = rows[i]
    let mut rendered = match row {
      Some(j) if expected[j].matcher.matches(line) =>
        match expected[j].matcher {
          Equal(_) => encode_output_line(line)
          Glob(_) | Regex(_) => {
            let raw = expected[j].raw
            if raw.has_suffix(" (no-eol)") {
              raw[:raw.length() - 9].to_owned()
            } else {
              raw
            }
          }
        }
      _ => encode_output_line(line)
    }
    if i == lines.length() - 1 {
      if no_eol {
        rendered += " (no-eol)"
      } else if protect_blank && rendered == "" {
        rendered = "\"\" (escaped)"
      }
    }
    (rendered, row)
  })
}

///|
/// Render normalized stream text as logical Markdown expectation lines.
///
/// Uses ordered alignment with `expected` to retain still-matching glob/regex
/// spellings, including after insertions/deletions. Exact lines are rendered
/// directly unless reserved syntax or control characters require JSON escaping.
/// Preserves missing final LF with `(no-eol)` and protects a trailing empty line
/// with `(escaped)`. Returns no stream marker, exit marker or line terminators.
///
/// This stream-only renderer does not protect a final status-shaped line such
/// as `[2]`; use `actual_expectation` when rendering a complete case.
pub fn actual_stream_expectation(
  text : String,
  expected : Array[ExpectedLine],
) -> Array[String] {
  stream_layout(text, expected, protect_blank=true).map(row => row.0)
}

///|
// Includes out-of-range integers: those would fail parsing in status position.
fn status_shaped(text : String) -> Bool {
  guard text.has_prefix("[") && text.has_suffix("]") else { return false }
  let value = text[1:text.length() - 1]
  let digits = if value.has_prefix("-") { value[1:] } else { value }
  !digits.is_empty() && digits.iter().all(c => c >= '0' && c <= '9')
}

///|
/// Render a complete updated expectation with source-row associations.
///
/// Each pair contains a logical line without a terminator and an optional
/// zero-based row index into `expected.source_lines`. `Some(i)` associates a
/// retained/replaced row with its old formatting; `None` denotes an insertion.
/// Input streams must already be CRLF-normalized.
///
/// Retains matching glob/regex patterns, paired marker order and separator
/// blanks. Ignored sections and satisfied empty constraints remain unchanged;
/// a nonempty stream replaces `(empty)` with concrete expectations. Emits `[N]`
/// only for a nonzero actual status and escapes ambiguous final status-shaped
/// output when needed. Sections/source rows must be consistent as produced by
/// `parse_expectation`; malformed manually assembled values may fail indexing.
pub fn actual_expectation_layout(
  actual : Captured,
  expected : Expectation,
) -> Array[(String, Int32?)] {
  let rendered = []
  let status_row = match expected.body {
    Legacy(content) => {
      for
        (line, row) in stream_layout(
          actual.output,
          content.lines,
          protect_blank=actual.exit_code == 0,
        ) {
        rendered.push((line, row))
      }
      content.lines.length()
    }
    Streams(sections) => {
      for i in 0..<sections[0].start {
        rendered.push((expected.source_lines[i], Some(i)))
      }
      for section in sections {
        let text = section.stream.select(actual)
        let lines = match section.constraint {
          Match(content) => content.lines
          Empty if !text.is_empty() => []
          _ => {
            for i in section.start..<section.end {
              rendered.push((expected.source_lines[i], Some(i)))
            }
            continue
          }
        }
        rendered.push((section.stream.label(), Some(section.start)))
        for (line, row) in stream_layout(text, lines, protect_blank=true) {
          rendered.push((line, row.map(i => section.start + 1 + i)))
        }
        for i in section.content_end..<section.end {
          rendered.push((expected.source_lines[i], Some(i)))
        }
      }
      sections[sections.length() - 1].end
    }
  }
  if actual.exit_code != 0 {
    rendered.push(
      (
        "[\{actual.exit_code}]",
        if status_row < expected.source_lines.length() {
          Some(status_row)
        } else {
          None
        },
      ),
    )
  } else {
    // The document parser removes separator blanks before recognizing status.
    for i = rendered.length() - 1; i >= 0; i = i - 1 {
      let (line, row) = rendered[i]
      if line == "" {
        continue
      }
      if status_shaped(line) {
        rendered[i] = ("\{Json::string(line).stringify()} (escaped)", row)
      }
      break
    }
  }
  rendered
}

///|
/// Render a complete case expectation from normalized captured output/status.
///
/// Returns logical lines without terminators. This is
/// `actual_expectation_layout` with source-row indices removed, preserving its
/// pattern retention, paired-stream policies and syntax escaping. Does not add
/// Markdown containers, command lines or enclosing fences.
///
/// ```mbt check
/// test {
///   let expected = @output.parse_expectation([], "README.md")
///   let actual : @output.Captured = {
///     output: "[2]\n",
///     diagnostic: "",
///     exit_code: 0,
///   }
///   assert_eq(@output.actual_expectation(actual, expected), ["\"[2]\" (escaped)"])
/// }
/// ```
pub fn actual_expectation(
  actual : Captured,
  expected : Expectation,
) -> Array[String] {
  actual_expectation_layout(actual, expected).map(row => row.0)
}
