///|
fn field(out : StringBuilder, name : String, value : String?) -> Unit {
  if value is Some(value) && !value.is_empty() {
    let lines = value.split("\n").to_array()
    out.write_string("\n  \{name}: \{lines[0]}")
    for line in lines[1:] {
      out.write_string("\n    \{line}")
    }
  }
}

///|
/// Format a message without a severity prefix. Captured bytes are not truncated.
/// Unknown errors keep their dependency-provided representation.
pub fn error_text(error : Error) -> String {
  let d = diagnostic(error)
  let out = StringBuilder()
  if d.file is Some(file) {
    out.write_string(file)
    if d.line is Some(line) {
      out.write_string(":\{line}")
    }
    if d.primary is Some({ location: Source(source), .. }) && source.precise {
      out.write_string(":\{source.start - source.line_start + 1}")
    }
    out.write_string(": ")
  }
  out.write_string(d.summary)
  if d.primary is Some({ location: Source(source), message, }) {
    source_snippet(out, source)
    field(out, "note", message)
  }
  for label in d.related {
    if label.location is Source(source) {
      out.write_string("\n  note: \{source.file}:\{source.line}")
      if source.precise {
        out.write_string(":\{source.start - source.line_start + 1}")
      }
      if label.message is Some(message) {
        out.write_string(": \{message}")
      }
      source_snippet(out, source)
    }
  }
  let command_shown = (match d.primary {
      Some({ location: Source({ is_command: true, .. }), .. }) => true
      _ => false
    }) ||
    d.related
    .iter()
    .any(label => label.location is Source({ is_command: true, .. }))
  if d.command is Some(command) && !command_shown {
    out.write_string("\n  \{command}")
  }
  field(out, "phase", d.phase)
  field(out, "segment", d.segment)
  field(out, "tool", d.tool)
  field(out, "cwd", d.cwd)
  field(out, "cause", d.cause)
  field(out, "hint", d.hint)
  let mut at_line_start = false
  for log in d.logs {
    if log.bytes.is_empty() {
      continue
    }
    let (text, escaped) = try @utf8.decode(log.bytes) catch {
      _ => (log.bytes.to_string(), true)
    } noraise {
      text => (text.replace_all(old="\r\n", new="\n"), false)
    }
    let partial = if log.complete { "" } else { "; partial" }
    let encoding = if escaped { "; escaped bytes" } else { "" }
    if !at_line_start {
      out.write_string("\n")
    }
    out.write_string("--- captured \{log.label}\{partial}\{encoding}\n")
    out.write_string(text)
    at_line_start = text.has_suffix("\n")
  }
  out.to_string()
}

///|
// Escape source segments only after choosing the original UTF-16 boundaries.
// Keep printable Unicode intact and reserve the brackets for our own markers.
fn source_text(out : StringBuilder, text : StringView) -> Unit {
  for c in text {
    match c {
      '\t' => out.write_string("\\t")
      '\r' => out.write_string("\\r")
      '\n' => out.write_string("\\n")
      '⟦' => out.write_string("\\u27e6")
      '⟧' => out.write_string("\\u27e7")
      _ =>
        if c.to_int() < 0x20 ||
          (c.to_int() >= 0x7f && c.to_int() <= 0x9f) ||
          c == '\u2028' ||
          c == '\u2029' {
          let hex = c.to_int().to_string(radix=16)
          out.write_string("\\u" + "0".repeat(4 - hex.length()) + hex)
        } else {
          out.write_char(c)
        }
    }
  }
}

///|
fn source_snippet(out : StringBuilder, source : SourceRange) -> Unit {
  let start = source.start - source.line_start
  let end = source.end - source.line_start
  out.write_string("\n  \{source.line} | ")
  source_text(out, source.source_line[:start])
  out.write_string("⟦")
  source_text(out, source.source_line[start:end])
  out.write_string("⟧")
  source_text(out, source.source_line[end:])
}

///|
/// Render one complete stderr report.
pub fn render(error : Error) -> String {
  let text = "ERROR " + error_text(error)
  if text.has_suffix("\n") {
    text
  } else {
    text + "\n"
  }
}
