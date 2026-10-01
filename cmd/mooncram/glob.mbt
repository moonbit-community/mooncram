///|
priv enum GlobToken {
  Literal(Char)
  AnyChar
  AnyMany
  CharSet(Array[(Char, Char)], Bool)
}

///|
fn parse_glob(pattern : String) -> Array[GlobToken] raise {
  let chars = pattern.to_array()
  let tokens = []
  let mut i = 0
  while i < chars.length() {
    match chars[i] {
      '*' => tokens.push(AnyMany)
      '?' => tokens.push(AnyChar)
      '\\' => {
        i += 1
        if i == chars.length() {
          raise Failure("trailing backslash in glob")
        }
        tokens.push(Literal(chars[i]))
      }
      '[' => {
        i += 1
        let negated = chars.get(i) is Some('!' | '^')
        if negated {
          i += 1
        }
        let ranges = []
        while i < chars.length() && (chars[i] != ']' || ranges.is_empty()) {
          let first = glob_char(chars, i)
          i = first.1
          if chars.get(i) == Some('-') &&
            chars.get(i + 1) is Some(c) &&
            c != ']' {
            let last = glob_char(chars, i + 1)
            if first.0 > last.0 {
              raise Failure("reversed character range in glob")
            }
            ranges.push((first.0, last.0))
            i = last.1
          } else {
            ranges.push((first.0, first.0))
          }
        }
        if i >= chars.length() || ranges.is_empty() {
          raise Failure("unclosed or empty character set in glob")
        }
        tokens.push(CharSet(ranges, negated))
      }
      c => tokens.push(Literal(c))
    }
    i += 1
  }
  tokens
}

///|
fn glob_char(chars : Array[Char], start : Int) -> (Char, Int) raise {
  let i = if chars[start] == '\\' { start + 1 } else { start }
  if i >= chars.length() {
    raise Failure("trailing backslash in glob set")
  }
  (chars[i], i + 1)
}

///|
fn match_glob(tokens : Array[GlobToken], text : String) -> Bool {
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
