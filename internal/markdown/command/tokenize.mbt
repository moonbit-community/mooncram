///|
priv struct Word {
  text : String
  assignment : String?
  start : Int32
  end : Int32
}

///|
priv struct TokenSegment {
  words : Array[Word]
  end : Int32
  empty_range : (Int32, Int32)
}

///|
// Preserve raw word ranges and assignment prefixes while decoding arguments.
fn tokenize(command : String) -> Array[TokenSegment] raise {
  let pipeline : Array[TokenSegment] = []
  let mut args : Array[Word] = []
  let word = StringBuilder()
  let mut quote : (Char, Int32)? = None
  let mut escape : Int32? = None
  let mut started = false
  let mut word_start = 0
  let mut assignment : String? = None
  let mut previous_pipe : Int32? = None
  fn invalid(
    summary : String,
    start : Int32,
    end : Int32,
  ) -> @diagnostic.Failure {
    @diagnostic.context(
      @diagnostic.with_input(@diagnostic.failure(summary), start, end),
      command~,
      segment=(pipeline.length() + 1).to_string(),
    )
  }
  let chars = [ for c in command => c ]
  for i = 0, pos = 0; i < chars.length(); {
    let c = chars[i]
    if c == '\u0000' || c == '\n' || c == '\r' {
      raise invalid("command contains a NUL or newline", pos, pos + 1)
    }
    // Character indices are used only for scanning. Source ranges always use
    // the separate UTF-16 cursor, including quoted and escaped characters.
    if !started && !(c is (' ' | '\t' | '|')) {
      word_start = pos
      let raw = StringBuilder()
      let mut end = i
      while end < chars.length() && !(chars[end] is (' ' | '\t' | '|')) {
        raw.write_char(chars[end])
        end += 1
      }
      let raw = raw.to_string()
      if raw.find("=") is Some(eq) {
        let name = raw[:eq].to_owned()
        if valid_name(name) {
          assignment = Some(name)
        }
      }
    }
    if escape is Some(_) {
      word.write_char(c)
      escape = None
    } else if quote is Some(('\'', _)) {
      if c == '\'' {
        quote = None
      } else {
        word.write_char(c)
      }
    } else if c == '\\' {
      escape = Some(pos)
      started = true
    } else if quote is Some(('"', _)) {
      if c == '"' {
        quote = None
      } else {
        word.write_char(c)
      }
    } else {
      match c {
        '\'' | '"' => {
          quote = Some((c, pos))
          started = true
        }
        ' ' | '\t' =>
          if started {
            args.push({
              text: word.to_string(),
              assignment,
              start: word_start,
              end: pos,
            })
            assignment = None
            word.reset()
            started = false
          }
        '|' => {
          if started {
            args.push({
              text: word.to_string(),
              assignment,
              start: word_start,
              end: pos,
            })
            assignment = None
            word.reset()
            started = false
          }
          pipeline.push({ words: args, end: pos, empty_range: (pos, pos + 1), })
          args = []
          previous_pipe = Some(pos)
        }
        '&' | ';' | '<' | '>' | '`' | '(' | ')' =>
          raise invalid(
            "unquoted shell operator '\{c}'; quote it to pass it literally",
            pos,
            pos + 1,
          )
        _ => {
          word.write_char(c)
          started = true
        }
      }
    }
    continue i + 1, pos + c.utf16_len()
  }
  if escape is Some(pos) {
    raise @diagnostic.context(
      invalid("trailing backslash in command", pos, pos + 1),
      hint="add the escaped character or double the backslash to pass it literally",
    )
  }
  if quote is Some((_, pos)) {
    raise @diagnostic.context(
      invalid("unclosed quote in command", pos, pos + 1),
      hint="close the quote opened here",
    )
  }
  let end = command.length()
  if started {
    args.push({ text: word.to_string(), assignment, start: word_start, end, })
  }
  let empty_range = match previous_pipe {
    Some(pos) => (pos, pos + 1)
    None => (end, end)
  }
  pipeline.push({ words: args, end, empty_range, })
  pipeline
}
