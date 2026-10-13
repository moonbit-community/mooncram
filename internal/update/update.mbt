///|
fn output_line_layout(
  case : @markdown.Case,
  line : String,
  row : Int32?,
) -> (String, String) {
  guard row is Some(i) else { return (case.prefix, case.newline) }
  let (prefix, newline) = case.output_layout
    .get(i)
    .unwrap_or((case.prefix, case.newline))
  // Blank source lines may omit container indentation that nonempty lines need.
  if line != "" &&
    case.expected.source_lines.get(i) is Some(original) &&
    line != original &&
    original.iter().all(c => c == ' ' || c == '\t') {
    (case.prefix, newline)
  } else {
    (prefix, newline)
  }
}

///|
pub fn case_edit(case : @markdown.Case, actual : @output.Captured) -> Edit {
  let text = StringBuilder()
  for (line, row) in @output.actual_expectation_layout(actual, case.expected) {
    let (prefix, newline) = output_line_layout(case, line, row)
    text.write_string(prefix + line + newline)
  }
  { start: case.replace_start, end: case.replace_end, text: text.to_string(), }
}

///|
pub fn apply_edits(source : String, edits : Array[Edit]) -> String {
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
