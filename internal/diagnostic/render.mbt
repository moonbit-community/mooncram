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
    out.write_string(": ")
  }
  out.write_string(d.summary)
  if d.command is Some(command) {
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
/// Render one complete stderr report.
pub fn render(error : Error) -> String {
  let text = "ERROR " + error_text(error)
  if text.has_suffix("\n") {
    text
  } else {
    text + "\n"
  }
}
