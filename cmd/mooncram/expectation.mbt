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
      _ => raise Failure("exit status is out of range")
    },
  )
}

///|
fn parse_expected_line(raw : String) -> ExpectedLine raise {
  let matcher = if raw.has_suffix(" (equal)") {
    Equal(raw[:raw.length() - 8].to_owned())
  } else if raw.has_suffix(" (escaped)") {
    let encoded = raw[:raw.length() - 10].to_owned()
    let value = @json.parse(encoded) catch {
      _ => raise Failure("(escaped) requires a JSON string")
    }
    guard value is String(text) else {
      raise Failure("(escaped) requires a JSON string")
    }
    if text.contains("\n") {
      raise Failure("an escaped output line cannot contain LF")
    }
    Equal(text)
  } else if raw.has_suffix(" (glob)") {
    Glob(parse_glob(raw[:raw.length() - 7].to_owned()))
  } else if raw.has_suffix(" (regex)") {
    let pattern = raw[:raw.length() - 8].to_owned()
    Regex(
      @string.Regex("^(?:\{pattern})$") catch {
        e => raise Failure("invalid regex: \{error_text(e)}")
      },
    )
  } else {
    // Reserve suffix annotations, including unsupported line repetitions.
    if raw.has_suffix(")") && raw.contains(" (") {
      raise Failure(
        "unknown output annotation; use (equal) or (escaped) for literal text",
      )
    }
    Equal(raw)
  }
  { raw, matcher, }
}

///|
fn parse_expectation(
  nodes : ArrayView[@cmark.Node[String]],
  file : String,
) -> Expectation raise {
  let lines = []
  let mut exit_code = 0
  let mut no_eol = false
  for i, node in nodes {
    let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
    try {
      if i == nodes.length() - 1 && exit_marker(node.v) is Some(code) {
        exit_code = code
        continue
      }
      if no_eol {
        raise Failure("(no-eol) must be on the final output line")
      }
      no_eol = node.v.has_suffix(" (no-eol)")
      let raw = if no_eol {
        node.v[:node.v.length() - 9].to_owned()
      } else {
        node.v
      }
      let parsed = parse_expected_line(raw)
      if no_eol && parsed.matcher is Equal("") {
        raise Failure(
          "an empty output line cannot have (no-eol); omit it for empty output",
        )
      }
      lines.push({ ..parsed, raw: node.v, })
    } catch {
      e => raise located(file, line, error_text(e))
    }
  }
  { lines, exit_code, no_eol, }
}

///|
fn normalize_output(text : String) -> String {
  text.replace_all(old="\r\n", new="\n")
}

///|
fn output_lines(text : String) -> (Array[String], Bool) {
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
fn Expectation::matches(self : Expectation, actual : Captured) -> Bool {
  let (lines, no_eol) = output_lines(actual.output)
  if self.exit_code != actual.exit_code ||
    self.no_eol != no_eol ||
    self.lines.length() != lines.length() {
    return false
  }
  for i, expected in self.lines {
    if !expected.matcher.matches(lines[i]) {
      return false
    }
  }
  true
}
