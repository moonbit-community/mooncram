///|
/// JSON strings make command/status/fence-looking lines and control characters
/// unambiguous. Ordinary output stays readable.
fn encode_output_line(text : String) -> String {
  let needs_escape = text == "" ||
    text.has_prefix(" ") ||
    text.has_prefix("$") ||
    text.has_prefix("[") ||
    text.contains("`") ||
    text.contains(" (") ||
    text.iter().any(c => c < ' ' || c == '\u007f')
  if needs_escape {
    "\{Json::string(text).stringify()} (escaped)"
  } else {
    text
  }
}

///|
fn actual_expectation(
  actual : Captured,
  expected : Expectation,
) -> Array[String] {
  let (lines, no_eol) = output_lines(actual.output)
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
  if actual.exit_code != 0 {
    rendered.push("[\{actual.exit_code}]")
  }
  rendered
}

///|
fn case_edit(case : Case, actual : Captured) -> Edit {
  let text = StringBuilder()
  for i, line in actual_expectation(actual, case.expected) {
    let (prefix, newline) = case.output_layout
      .get(i)
      .unwrap_or((case.prefix, case.newline))
    text.write_string(prefix + line + newline)
  }
  { start: case.replace_start, end: case.replace_end, text: text.to_string(), }
}

///|
fn apply_edits(source : String, edits : Array[Edit]) -> String {
  let result = StringBuilder()
  let mut offset = 0
  for edit in edits {
    result.write_stringview(source[offset:edit.start])
    result.write_string(edit.text)
    offset = edit.end
  }
  result.write_stringview(source[offset:])
  result.to_string()
}
