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
pub fn actual_expectation(
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
