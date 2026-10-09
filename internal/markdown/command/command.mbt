///|
/// Tokenize arguments without invoking or emulating a shell. Single quotes are
/// literal; outside them a backslash quotes exactly the next character.
/// Unquoted, unescaped `|` separates pipeline segments.
pub fn parse(command : String) -> Array[Array[String]] raise {
  let pipeline : Array[Array[String]] = []
  let mut args : Array[String] = []
  let word = StringBuilder()
  let mut quote : Char? = None
  let mut escaped = false
  let mut started = false
  for c in command {
    if c == '\u0000' || c == '\n' || c == '\r' {
      raise @diagnostic.Failure("command contains a NUL or newline")
    }
    if escaped {
      word.write_char(c)
      escaped = false
      started = true
    } else if quote == Some('\'') {
      if c == '\'' {
        quote = None
      } else {
        word.write_char(c)
      }
    } else if c == '\\' {
      escaped = true
      started = true
    } else if quote == Some('"') {
      if c == '"' {
        quote = None
      } else {
        word.write_char(c)
      }
    } else {
      match c {
        '\'' | '"' => {
          quote = Some(c)
          started = true
        }
        ' ' | '\t' =>
          if started {
            args.push(word.to_string())
            word.reset()
            started = false
          }
        '|' => {
          if started {
            args.push(word.to_string())
            word.reset()
            started = false
          }
          validate_segment(args)
          pipeline.push(args)
          args = []
        }
        '&' | ';' | '<' | '>' | '`' | '(' | ')' =>
          raise @diagnostic.Failure(
            "unquoted shell operator '\{c}'; quote it to pass it literally",
          )
        _ => {
          word.write_char(c)
          started = true
        }
      }
    }
  }
  if escaped {
    raise @diagnostic.Failure("trailing backslash in command")
  }
  if quote is Some(_) {
    raise @diagnostic.Failure("unclosed quote in command")
  }
  if started {
    args.push(word.to_string())
  }
  validate_segment(args)
  pipeline.push(args)
  pipeline
}

///|
fn validate_segment(args : Array[String]) -> Unit raise {
  if args.is_empty() {
    raise @diagnostic.Failure(
      "empty pipeline segment; expected a local .mbtx file or executable package path",
    )
  }
  if args[0] == "" {
    raise @diagnostic.Failure(
      "expected a local .mbtx file or executable package path",
    )
  }
}
