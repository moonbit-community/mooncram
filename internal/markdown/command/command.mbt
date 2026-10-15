///|
/// One command's parsed arguments and temporary environment.
///
/// Produced by `parse` inside a `Command::Pipeline`. Each segment begins with
/// `moonx`, followed by a nonempty target and optional program arguments.
pub(all) struct PipelineSegment {
  /// `moonx`, target and program arguments, with quotes and escapes processed.
  argv : Array[String]
  /// Segment-only assignments; values override document/inherited variables.
  extra_env : Map[String, String]
} derive(Debug, Eq)

///|
/// Expose the derived debug representation of all segment fields.
pub extend PipelineSegment with @debug.Debug::{to_repr}

///|
/// Expose structural equality over arguments and assignments.
pub extend PipelineSegment with Eq::{equal, not_equal}

///|
/// Result of parsing one command line without its Markdown `$` prompt.
///
/// Configuration variants change later parsing/resolution state and are not
/// executable test cases.
pub(all) enum Command {
  /// Nonempty list of executable segments in pipeline order.
  Pipeline(Array[PipelineSegment])
  /// One document-scoped environment assignment with a literal value.
  Export(name~ : String, value~ : String)
  /// Nonempty block-local directory path, not yet filesystem-validated.
  SetCurrentWorkingDirectory(directory~ : String)
} derive(Debug, Eq)

///|
/// Expose the derived debug representation of the variant and its payload.
pub extend Command with @debug.Debug::{to_repr}

///|
/// Expose structural equality; variants and all payload fields must match.
pub extend Command with Eq::{equal, not_equal}

///|
fn valid_name(name : String) -> Bool {
  let mut first = true
  for c in name {
    if first {
      if !(c is ('A'..<='Z' | 'a'..<='z' | '_')) {
        return false
      }
      first = false
    } else if !(c is ('A'..<='Z' | 'a'..<='z' | '_' | '0'..<='9')) {
      return false
    }
  }
  !first
}

///|
/// Parse a pipeline, environment assignment or working directory configuration.
/// Variable-like text such as ${NAME} is literal, with normal quoting and escaping.
/// Leading NAME=value assignments affect only their segment's environment.
/// case_insensitive normalizes temporary names to uppercase; enable it on Windows.
///
/// `command` omits the Markdown `$` prompt. Spaces/tabs split arguments, quotes
/// preserve spaces, and backslashes escape the following character except in
/// single quotes. Unquoted `|` separates segments; each segment must explicitly
/// name `moonx` and its target. Redirection is unsupported. Parsing does not invoke
/// a shell, resolve targets or mutate the environment.
///
/// Raises `@diagnostic.Failure` for malformed quotes, empty segments, unsupported
/// shell operators, missing moonx/targets, invalid assignments or configuration placement.
///
/// ```mbt check
/// test {
///   let parsed = @command.parse("NAME='Moon Bit' moonx ./hello.mbtx \"${NAME}\"")
///   guard parsed is @command.Pipeline(segments) else {
///     fail("expected a pipeline")
///   }
///   assert_eq(segments[0].argv, ["moonx", "./hello.mbtx", "${NAME}"])
///   assert_eq(segments[0].extra_env.get("NAME"), Some("Moon Bit"))
/// }
/// ```
pub fn parse(
  command : String,
  case_insensitive~ : Bool = false,
) -> Command raise {
  let words = tokenize(command)
  let pipeline : Array[PipelineSegment] = []
  for tokens in words {
    let segment = []
    let extra_env : Map[String, String] = Map([])
    let env_key = fn(name : String) {
      if case_insensitive {
        name.to_upper()
      } else {
        name
      }
    }
    for (word, assignment) in tokens {
      if segment.is_empty() && assignment is Some(name) {
        extra_env[env_key(name)] = word[name.length() + 1:].to_owned()
      } else {
        segment.push(word)
      }
    }
    if segment.is_empty() {
      if !extra_env.is_empty() {
        raise @diagnostic.failure("environment assignments require a command")
      }
      raise @diagnostic.failure(
        "empty pipeline segment; expected moonx and a target",
      )
    }
    let executable = segment[0]
    if executable == "" {
      raise @diagnostic.failure("expected moonx and a nonempty target")
    }
    if executable == "set-current-working-directory" {
      if !extra_env.is_empty() {
        raise @diagnostic.failure(
          "set-current-working-directory does not accept temporary environment assignments",
        )
      }
      if words.length() != 1 {
        raise @diagnostic.failure(
          "set-current-working-directory is not allowed in a pipeline",
        )
      }
      if segment.length() != 2 {
        raise @diagnostic.failure(
          "set-current-working-directory requires exactly one nonempty directory argument",
        )
      }
      let directory = segment[1]
      if directory.is_empty() {
        raise @diagnostic.failure(
          "set-current-working-directory requires exactly one nonempty directory argument",
        )
      }
      return SetCurrentWorkingDirectory(directory~)
    }
    if executable == "export" {
      if !extra_env.is_empty() {
        raise @diagnostic.failure(
          "export does not accept temporary environment assignments",
        )
      }
      if words.length() != 1 {
        raise @diagnostic.failure("export is not allowed in a pipeline")
      }
      if segment.length() != 2 {
        raise @diagnostic.failure(
          "export requires exactly one NAME=value assignment",
        )
      }
      let prefix = segment[1]
      guard prefix.find("=") is Some(eq) else {
        raise @diagnostic.failure("export requires a NAME=value assignment")
      }
      let name = prefix[:eq].to_owned()
      if !valid_name(name) {
        raise @diagnostic.failure("invalid export variable name: \{name}")
      }
      return Export(name~, value=prefix[eq + 1:].to_owned())
    }
    if executable != "moonx" {
      raise @diagnostic.failure("command must start with moonx: " + executable)
    }
    if segment.length() < 2 || segment[1].is_empty() {
      raise @diagnostic.failure("moonx requires a nonempty target")
    }
    pipeline.push({ argv: segment, extra_env, })
  }
  Pipeline(pipeline)
}

///|
/// Preserve raw assignment prefixes while decoding words.
fn tokenize(command : String) -> Array[Array[(String, String?)]] raise {
  let pipeline = []
  let mut args = []
  let word = StringBuilder()
  let mut quote : Char? = None
  let mut escaped = false
  let mut started = false
  let mut assignment : String? = None
  let chars = [ for c in command => c ]
  for c in chars {
    if c == '\u0000' || c == '\n' || c == '\r' {
      raise @diagnostic.failure("command contains a NUL or newline")
    }
  }
  for i = 0; i < chars.length(); {
    let c = chars[i]
    // Recognize raw assignment prefixes before decoding quotes and escapes.
    if !started && quote is None && !escaped && !(c is (' ' | '\t' | '|')) {
      let raw = StringBuilder()
      let mut end = i
      while end < chars.length() && !(chars[end] is (' ' | '\t' | '|')) {
        raw.write_char(chars[end])
        end += 1
      }
      let raw = raw.to_string()
      // Only a raw, unquoted and unescaped NAME= prefix is an assignment.
      // Retain the whole word for assignments occurring after the executable.
      if raw.find("=") is Some(eq) {
        let name = raw[:eq].to_owned()
        if valid_name(name) {
          assignment = Some(name)
        }
      }
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
            args.push((word.to_string(), assignment))
            assignment = None
            word.reset()
            started = false
          }
        '|' => {
          if started {
            args.push((word.to_string(), assignment))
            assignment = None
            word.reset()
            started = false
          }
          pipeline.push(args)
          args = []
        }
        '&' | ';' | '<' | '>' | '`' | '(' | ')' =>
          raise @diagnostic.failure(
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
    raise @diagnostic.failure("trailing backslash in command")
  }
  if quote is Some(_) {
    raise @diagnostic.failure("unclosed quote in command")
  }
  if started {
    args.push((word.to_string(), assignment))
  }
  pipeline.push(args)
  pipeline
}
