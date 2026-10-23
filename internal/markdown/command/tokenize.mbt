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
// Views retain UTF-16 source offsets through quoted and escaped fragments.
fn tokenize(command : String) -> Array[TokenSegment] raise {
  let pipeline : Array[TokenSegment] = []
  let mut args : Array[Word] = []
  let word = StringBuilder()
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
  fn escaped(input : StringView) -> StringView raise {
    let pos = input.start_offset()
    lexmatch input with longest {
      re"^$" =>
        raise @diagnostic.context(
          invalid("trailing backslash in command", pos - 1, pos),
          hint="add the escaped character or double the backslash to pass it literally",
        )
      (re"^[\u0000\r\n]", after=_) =>
        raise invalid("command contains a NUL or newline", pos, pos + 1)
      (re"^[^\u0000\r\n]" as c, after=rest) => {
        word.write_char(c)
        rest
      }
    }
  }

  fn double_quoted(input : StringView) -> StringView raise {
    let quote_start = input.start_offset() - 1
    for input = input {
      let pos = input.start_offset()
      lexmatch input with longest {
        re"^$" =>
          raise @diagnostic.context(
            invalid("unclosed quote in command", quote_start, quote_start + 1),
            hint="close the quote opened here",
          )
        (re"^[\u0000\r\n]", after=_) =>
          raise invalid("command contains a NUL or newline", pos, pos + 1)
        (re"^\"", after=rest) => break rest
        (re"^\\", after=rest) => continue escaped(rest)
        (re"^[^\"\\\u0000\r\n]+" as text, after=rest) => {
          word.write_view(text)
          continue rest
        }
      }
    }
  }

  fn scan_word(input : StringView) -> (Word, StringView) raise {
    let start = input.start_offset()
    // Inspect only the raw prefix, separately from the longer plain-text rule.
    let assignment = lexmatch input with longest {
      (re"^" + (re"[A-Za-z_][A-Za-z0-9_]*" as name) + re"=", after=_) =>
        Some(name.to_owned())
      _ => None
    }
    word.reset()
    let rest = for input = input {
      let pos = input.start_offset()
      lexmatch input with longest {
        (re"^(?:$|[ \t|])", after=_) => break input
        (re"^[\u0000\r\n]", after=_) =>
          raise invalid("command contains a NUL or newline", pos, pos + 1)
        (re"^[&;<>`()]" as c, after=_) =>
          raise invalid(
            "unquoted shell operator '\{c}'; quote it to pass it literally",
            pos,
            pos + 1,
          )
        (re"^'" + (re"[^'\u0000\r\n]*" as text) + re"'", after=rest) => {
          word.write_view(text)
          continue rest
        }
        // Without a closing quote, the literal run ends at EOF or a control.
        (re"^'[^'\u0000\r\n]*", after=rest) =>
          if rest.is_empty() {
            raise @diagnostic.context(
              invalid("unclosed quote in command", pos, pos + 1),
              hint="close the quote opened here",
            )
          } else {
            let pos = rest.start_offset()
            raise invalid("command contains a NUL or newline", pos, pos + 1)
          }
        (re"^\"", after=rest) => continue double_quoted(rest)
        (re"^\\", after=rest) => continue escaped(rest)
        (re"^[^ \t|'\"\\&;<>`()\u0000\r\n]+" as text, after=rest) => {
          word.write_view(text)
          continue rest
        }
      }
    }
    (
      { text: word.to_string(), assignment, start, end: rest.start_offset(), },
      rest,
    )
  }

  for input = command[:] {
    let pos = input.start_offset()
    lexmatch input with longest {
      re"^$" => break
      (re"^[ \t]+", after=rest) => continue rest
      (re"^\|", after=rest) => {
        pipeline.push({ words: args, end: pos, empty_range: (pos, pos + 1), })
        args = []
        previous_pipe = Some(pos)
        continue rest
      }
      _ => {
        let (word, rest) = scan_word(input)
        args.push(word)
        continue rest
      }
    }
  }
  let end = command.length()
  let empty_range = match previous_pipe {
    Some(pos) => (pos, pos + 1)
    None => (end, end)
  }
  pipeline.push({ words: args, end, empty_range, })
  pipeline
}
