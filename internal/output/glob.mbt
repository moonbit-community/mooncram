///|
priv enum GlobToken {
  Literal(Char)
  AnyChar
  AnyMany
  CharSet(Array[(Char, Char)], Bool)
}

///|
fn parse_glob(pattern : StringView) -> Array[GlobToken] raise {
  let tokens = []
  for input = pattern {
    lexmatch input with longest {
      re"^$" => break
      (re"^\*", after=rest) => {
        tokens.push(AnyMany)
        continue rest
      }
      (re"^\?", after=rest) => {
        tokens.push(AnyChar)
        continue rest
      }
      (re"^\\", after=rest) =>
        match rest {
          [c, .. rest] => {
            tokens.push(Literal(c))
            continue rest
          }
          [] => raise @diagnostic.failure("trailing backslash in glob")
        }
      (re"^\[", after=rest) => {
        let (set, rest) = glob_set(rest)
        tokens.push(set)
        continue rest
      }
      (re"^[^*?\\\[]+" as text, after=rest) => {
        for c in text {
          tokens.push(Literal(c))
        }
        continue rest
      }
    }
  }
  tokens
}

///|
fn glob_set(input : StringView) -> (GlobToken, StringView) raise {
  let (negated, input) = lexmatch input with longest {
    (re"^[!^]", after=rest) => (true, rest)
    _ => (false, input)
  }
  let ranges = []
  for input = input {
    // The first ']' is a member; only a later one closes the set.
    if input is [']', .. rest] && !ranges.is_empty() {
      break (CharSet(ranges, negated), rest)
    }
    let (first, rest) = glob_char(input)
    match rest {
      ['-', .. after_hyphen] if after_hyphen is [c, ..] && c != ']' => {
        let (last, rest) = glob_char(after_hyphen)
        if first > last {
          raise @diagnostic.failure("reversed character range in glob")
        }
        ranges.push((first, last))
        continue rest
      }
      _ => {
        ranges.push((first, first))
        continue rest
      }
    }
  }
}

///|
fn glob_char(input : StringView) -> (Char, StringView) raise {
  lexmatch input with longest {
    re"^$" =>
      raise @diagnostic.failure("unclosed or empty character set in glob")
    (re"^\\", after=rest) =>
      match rest {
        [c, .. rest] => (c, rest)
        [] => raise @diagnostic.failure("trailing backslash in glob set")
      }
    (re"^[^\\]" as c, after=rest) => (c, rest)
  }
}

///|
fn match_glob(tokens : Array[GlobToken], text : StringView) -> Bool {
  let chars = text.to_array()
  let mut previous = Array::make(chars.length() + 1, false)
  previous[0] = true
  for token in tokens {
    let next = Array::make(chars.length() + 1, false)
    if token is AnyMany {
      next[0] = previous[0]
    }
    for j in 1..<=chars.length() {
      next[j] = match token {
        AnyMany => previous[j] || next[j - 1]
        AnyChar => previous[j - 1]
        Literal(c) => previous[j - 1] && chars[j - 1] == c
        CharSet(ranges, negated) =>
          previous[j - 1] &&
          ranges.any(r => chars[j - 1] >= r.0 && chars[j - 1] <= r.1) != negated
      }
    }
    previous = next
  }
  previous[chars.length()]
}
