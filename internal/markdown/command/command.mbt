///|
pub(all) enum Command {
  Pipeline(Array[Array[String]])
  Export(name~ : String, value~ : String)
} derive(Debug, Eq)

///|
pub extend Command with @debug.Debug::{to_repr}

///|
pub extend Command with Eq::{equal, not_equal}

///|
priv enum Part {
  Text(String)
  Variable(String)
}

///|
fn valid_name(name : String) -> Bool {
  let mut first = true
  for c in name {
    if first {
      if !(c is ('A'..='Z' | 'a'..='z' | '_')) {
        return false
      }
      first = false
    } else if !(c is ('A'..='Z' | 'a'..='z' | '_' | '0'..='9')) {
      return false
    }
  }
  !first
}

///|
fn expand(
  parts : Array[Part],
  lookup : (String) -> String?,
  executable? : Bool = false,
) -> String raise {
  let result = StringBuilder()
  for part in parts {
    match part {
      Text(text) => result.write_string(text)
      Variable(name) => {
        if executable {
          raise @diagnostic.Failure(
            "variable expansion is not allowed in executable paths",
          )
        }
        guard lookup(name) is Some(value) else {
          raise @diagnostic.Failure("undefined variable: \{name}")
        }
        result.write_string(value)
      }
    }
  }
  result.to_string()
}

///|
/// Parse a pipeline or a single environment assignment without invoking a shell.
/// Only unescaped ${NAME} outside single quotes expands, once, without splitting.
/// References require lookup; by default all variables are undefined.
pub fn parse(
  command : String,
  lookup? : (String) -> String? = _ => None,
) -> Command raise {
  let words = tokenize(command)
  let pipeline : Array[Array[String]] = []
  for segment in words {
    if segment.is_empty() {
      raise @diagnostic.Failure(
        "empty pipeline segment; expected a local .mbtx file or executable package path",
      )
    }
    let executable = expand(segment[0], lookup, executable=true)
    if executable == "" {
      raise @diagnostic.Failure(
        "expected a local .mbtx file or executable package path",
      )
    }
    if executable == "export" {
      if words.length() != 1 {
        raise @diagnostic.Failure("export is not allowed in a pipeline")
      }
      if segment.length() != 2 {
        raise @diagnostic.Failure(
          "export requires exactly one NAME=value assignment",
        )
      }
      // The name and '=' must be literal; only the value may contain references.
      let assignment = segment[1]
      guard assignment[0] is Text(prefix) else {
        raise @diagnostic.Failure("export requires a NAME=value assignment")
      }
      guard prefix.find("=") is Some(eq) else {
        raise @diagnostic.Failure("export requires a NAME=value assignment")
      }
      let name = prefix[:eq].to_owned()
      if !valid_name(name) {
        raise @diagnostic.Failure("invalid export variable name: \{name}")
      }
      let value_parts = [Text(prefix[eq + 1:].to_owned())] +
        assignment[1:].to_owned()
      return Export(name~, value=expand(value_parts, lookup))
    }
    let args = [executable]
    for parts in segment[1:] {
      args.push(expand(parts, lookup))
    }
    pipeline.push(args)
  }
  Pipeline(pipeline)
}

///|
/// Keep references separate until executable paths and export names are checked.
fn tokenize(command : String) -> Array[Array[Array[Part]]] raise {
  let pipeline = []
  let mut args = []
  let mut parts = []
  let word = StringBuilder()
  let mut quote : Char? = None
  let mut escaped = false
  let mut started = false
  let chars = [ for c in command => c ]
  for c in chars {
    if c == '\u0000' || c == '\n' || c == '\r' {
      raise @diagnostic.Failure("command contains a NUL or newline")
    }
  }
  for i = 0; i < chars.length(); {
    let c = chars[i]
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
    } else if c == '$' && i + 1 < chars.length() && chars[i + 1] == '{' {
      let name = StringBuilder()
      let mut end = i + 2
      while end < chars.length() && chars[end] != '}' {
        name.write_char(chars[end])
        end += 1
      }
      if end == chars.length() {
        raise @diagnostic.Failure("unclosed variable reference")
      }
      if !valid_name(name.to_string()) {
        raise @diagnostic.Failure(
          "invalid variable reference: \{name.to_string()}",
        )
      }
      parts.push(Text(word.to_string()))
      word.reset()
      parts.push(Variable(name.to_string()))
      started = true
      continue end + 1
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
            parts.push(Text(word.to_string()))
            args.push(parts)
            parts = []
            word.reset()
            started = false
          }
        '|' => {
          if started {
            parts.push(Text(word.to_string()))
            args.push(parts)
            parts = []
            word.reset()
            started = false
          }
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
    continue i + 1
  }
  if escaped {
    raise @diagnostic.Failure("trailing backslash in command")
  }
  if quote is Some(_) {
    raise @diagnostic.Failure("unclosed quote in command")
  }
  if started {
    parts.push(Text(word.to_string()))
    args.push(parts)
  }
  pipeline.push(args)
  pipeline
}
