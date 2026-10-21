///|
// Closing fences allow up to three spaces *before* stripping fence indentation.
fn required_fence_length(line : StringView) -> Int32 {
  let mut i = 0
  while i < line.length() && line[i] == ' ' {
    i += 1
  }
  if i > 3 {
    return 3
  }
  let start = i
  while i < line.length() && line[i] == '`' {
    i += 1
  }
  if i - start >= 3 &&
    line[i:].iter().all(c => c == ' ' || c == '\t' || c == '\r' || c == '\n') {
    i - start + 1
  } else {
    3
  }
}

///|
fn render_case(
  case : @markdown.Case,
  actual : @output.Captured,
  fence : @markdown.Fence,
) -> (Edit, Int32) {
  let text = StringBuilder()
  let mut fence_length = 3
  let mut previous_cr = case.newline == "\r"
  for (line, row) in @output.actual_expectation_layout(actual, case.expected) {
    let old = if row is Some(i) {
      case.expected.source_lines.get(i)
    } else {
      None
    }
    let layout = if row is Some(i) {
      case.output_layout.get(i).unwrap_or(case.command_layout)
    } else {
      case.command_layout
    }
    let (rendered, fence_start) = if old == Some(line) {
      (layout.original, layout.original_fence_start)
    } else {
      // Empty container lines may be underindented. Reuse their newline, but
      // borrow a complete container prefix when replacing them with content.
      let base = if line != "" &&
        old is Some(original) &&
        original.iter().all(c => c == ' ' || c == '\t') {
        case.command_layout
      } else {
        layout
      }
      let extra = if line.has_prefix(" ") && base.indent < fence.indent {
        fence.indent - base.indent
      } else {
        0
      }
      let quote_space = if line.has_prefix(" ") && base.prefix.has_suffix(">") {
        " "
      } else {
        ""
      }
      (
        base.prefix + quote_space + " ".repeat(extra) + line + layout.newline,
        base.fence_start + quote_space.length(),
      )
    }
    // A bare LF immediately after CR would merge two source lines into CRLF.
    // Protect output blanks in that position while keeping both newline styles.
    // Separator blanks carry no assertion and must not become output instead.
    let is_output = if row is Some(i) {
      match case.expected.body {
        Legacy(content) => i < content.lines.length()
        Streams(sections) =>
          sections.iter().any(s => i > s.start && i < s.content_end)
      }
    } else {
      true
    }
    let rendered = if previous_cr && rendered == "\n" && is_output {
      "\"\" (escaped)\n"
    } else {
      rendered
    }
    previous_cr = rendered.has_suffix("\r")
    text.write_string(rendered)
    fence_length = @cmp.maximum(
      fence_length,
      required_fence_length(rendered[fence_start:]),
    )
  }
  (
    {
      start: case.replace_start,
      end: case.replace_end,
      text: text.to_string(),
    },
    fence_length,
  )
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

///|
/// Render every captured case together so shared fences have one safe length.
///
/// `captures` must contain normalized output/status for every case, in document
/// order, with exactly `document.cases.length()` entries. These calling
/// preconditions are not checked. The document must be an unmodified result
/// of `@markdown.parse_document`, keeping offsets/layout consistent with source.
///
/// Retains matching patterns, commands, surrounding prose, containers, separator
/// lines and line endings. Each fence containing cases uses the shortest safe
/// backtick length of at least three, considering every case sharing it. Changed-case
/// counts include all cases affected by marker changes, counted at most once.
///
/// Re-parses changed text and checks that commands/configuration remain
/// unchanged and every expectation matches its capture. Unchanged text reuses
/// the parsed document and still checks every capture. Validation failures
/// raise errors instead of returning an update.
/// Re-parsing preserves literal arguments and assignments. No commands execute
/// and no files are written; commit with `@files.write_document` if desired.
/// Documents without cases still validate and return unchanged source with zero
/// changed cases.
pub fn generate(
  document : @markdown.Document,
  captures : Array[@output.Captured],
) -> Generated raise {
  let edits = []
  let changed = Array::make(document.cases.length(), false)
  let lengths : Map[Int32, Int32] = Map([])
  for i, case in document.cases {
    let actual = captures[i]
    let (edit, length) = render_case(case, actual, document.fences[case.fence])
    lengths[case.fence] = @cmp.maximum(
      lengths.get(case.fence).unwrap_or(3),
      length,
    )
    if document.source[edit.start:edit.end] != edit.text {
      changed[i] = true
      edits.push(edit)
    }
  }
  for index, length in lengths {
    let fence = document.fences[index]
    let marker = "`".repeat(length)
    let mut fence_changed = false
    for
      (start, end) in [
        (fence.opening_start, fence.opening_end),
        (fence.closing_start, fence.closing_end),
      ] {
      if document.source[start:end] != marker {
        edits.push({ start, end, text: marker, })
        fence_changed = true
      }
    }
    if fence_changed {
      for i, case in document.cases {
        if case.fence == index {
          changed[i] = true
        }
      }
    }
  }
  if edits.is_empty() {
    for i, case in document.cases {
      validate_expectation(case.expected, captures[i], i)
    }
    return { source: document.source, changed_cases: 0, }
  }
  edits.sort_by((a, b) => a.start.compare(b.start))
  let source = apply_edits(document.source, edits)
  validate_generated(document, source, captures)
  { source, changed_cases: changed.iter().filter(b => b).count(), }
}
