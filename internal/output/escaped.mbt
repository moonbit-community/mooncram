///|
fn json_error_range(
  error : @json.ParseError,
  encoded : String,
) -> (Int32, Int32) {
  let position = match error {
    @json.InvalidEof => return (encoded.length(), encoded.length())
    @json.InvalidChar(pos, _)
    | @json.InvalidNumber(pos, _)
    | @json.InvalidIdentEscape(pos)
    | @json.DuplicateKey(pos, _) => pos
    @json.DepthLimitExceeded => return (0, encoded.length())
  }
  // JSON positions count UTF-16 code units, including after non-BMP characters.
  // Walking characters also ensures the highlighted range cannot split a pair.
  for c in encoded; offset = 0, line = 1, column = 0 {
    if line == position.line && column == position.column {
      return (offset, offset + c.utf16_len())
    }
    if c == '\n' {
      continue offset + 1, line + 1, 0
    } else {
      continue offset + c.utf16_len(), line, column + c.utf16_len()
    }
  } nobreak {
    if line == position.line && column == position.column {
      (offset, offset)
    } else {
      (0, encoded.length())
    }
  }
}

///|
fn json_type(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "boolean"
    Number(_) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn parse_escaped(encoded : String, row : Int32) -> String raise {
  let value = @json.parse(encoded) catch {
    e => {
      let (start, end) = json_error_range(e, encoded)
      raise @diagnostic.with_input(
        @diagnostic.wrap(e, "invalid JSON in (escaped) output"),
        start,
        end,
        row~,
      )
    }
  }
  let mut start = 0
  let mut end = encoded.length()
  while start < end && encoded[start] is (' ' | '\t' | '\r' | '\n') {
    start += 1
  }
  while end > start && encoded[end - 1] is (' ' | '\t' | '\r' | '\n') {
    end -= 1
  }
  guard value is String(text) else {
    raise @diagnostic.with_input(
      @diagnostic.failure(
        "(escaped) requires a JSON string, got " + json_type(value),
      ),
      start,
      end,
      row~,
    )
  }
  if text.contains("\n") {
    raise @diagnostic.with_input(
      @diagnostic.failure("an escaped output line cannot contain LF"),
      start,
      end,
      row~,
    )
  }
  text
}
