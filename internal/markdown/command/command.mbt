///|
/// One command's expanded arguments, temporary environment and output routes.
///
/// Produced by `parse` inside a `Command::Pipeline`. Each segment has at least
/// one argument. Redirection flags may be set only on non-final segments.
pub(all) struct PipelineSegment {
  /// Executable followed by arguments, with quoting removed and references expanded.
  argv : Array[String]
  /// Segment-only assignments; values override document/inherited variables.
  extra_env : Map[String, String]
  /// Route this segment's stderr into the pipe feeding the next segment.
  stderr_to_stdout : Bool
  /// Discard stdout while draining it; independently merged stderr still flows on.
  stdout_to_null : Bool
} derive(Debug, Eq)

///|
/// Expose the derived debug representation of all segment fields.
pub extend PipelineSegment with @debug.Debug::{to_repr}

///|
/// Expose structural equality over arguments, assignments and redirection flags.
pub extend PipelineSegment with Eq::{equal, not_equal}

///|
/// Result of parsing one command line without its Markdown `$` prompt.
///
/// Configuration variants change later parsing/resolution state and are not
/// executable test cases.
pub(all) enum Command {
  /// Nonempty list of executable segments in pipeline order.
  Pipeline(Array[PipelineSegment])
  /// One document-scoped environment assignment with an expanded value.
  Export(name~ : String, value~ : String)
  /// Nonempty expanded block-local directory path, not yet filesystem-validated.
  SetCurrentWorkingDirectory(directory~ : String)
} derive(Debug, Eq)

///|
/// Expose the derived debug representation of the variant and its payload.
pub extend Command with @debug.Debug::{to_repr}

///|
/// Expose structural equality; variants and all payload fields must match.
pub extend Command with Eq::{equal, not_equal}

///|
priv enum Part {
  Text(String)
  Variable(String)
}

///|
priv enum Token {
  Argument(Array[Part], String?)
  StderrToStdout
  StdoutToNull
}

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
fn expand(
  parts : Array[Part],
  lookup : (String) -> String?,
  executable~ : Bool = false,
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
/// Parse a pipeline, environment assignment or working directory configuration.
/// Only unescaped ${NAME} outside single quotes expands, once, without splitting.
/// References require lookup; by default all variables are undefined.
/// Leading NAME=value assignments expand left to right and affect only their
/// segment, including its arguments. case_insensitive normalizes temporary names
/// and lookup keys to uppercase; enable it on Windows.
/// Output redirection is allowed only before the final pipeline segment.
///
/// `command` omits the Markdown `$` prompt. Spaces/tabs split arguments, quotes
/// preserve spaces, and backslashes escape the following character except in
/// single quotes. Unquoted `|` separates segments. The only supported routes
/// are raw trailing tokens `2>&1` and `1>/dev/null`. Parsing does not invoke a
/// shell, resolve targets or mutate the environment.
///
/// Raises `@diagnostic.Failure` for malformed quotes/references, undefined
/// variables, empty segments, unsupported shell operators, invalid assignments
/// or redirection/configuration placement. Variable references are forbidden
/// in executable names.
///
/// ```mbt check
/// test {
///   let parsed = @command.parse("NAME='Moon Bit' ./hello.mbtx \"${NAME}\"")
///   guard parsed is @command.Pipeline(segments) else {
///     fail("expected a pipeline")
///   }
///   assert_eq(segments[0].argv, ["./hello.mbtx", "Moon Bit"])
///   assert_eq(segments[0].extra_env.get("NAME"), Some("Moon Bit"))
/// }
/// ```
pub fn parse(
  command : String,
  lookup~ : (String) -> String? = _ => None,
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
    let segment_lookup = fn(name : String) {
      let key = env_key(name)
      if extra_env.get(key) is Some(value) {
        Some(value)
      } else {
        lookup(key)
      }
    }
    let mut stderr_to_stdout = false
    let mut stdout_to_null = false
    for token in tokens {
      match token {
        Argument(parts, assignment) => {
          if stderr_to_stdout || stdout_to_null {
            raise @diagnostic.Failure(
              "ordinary arguments cannot follow redirection",
            )
          }
          if segment.is_empty() && assignment is Some(name) {
            // Tokenization guarantees that NAME= is the literal first part.
            guard parts[0] is Text(prefix) else {
              abort("invalid assignment token")
            }
            let value_parts = [Text(prefix[name.length() + 1:].to_owned())] +
              parts[1:].to_owned()
            // Expand before replacing the key, so self references see its old value.
            extra_env[env_key(name)] = expand(value_parts, segment_lookup)
          } else {
            segment.push(parts)
          }
        }
        StderrToStdout => {
          if stderr_to_stdout {
            raise @diagnostic.Failure("duplicate 2>&1 redirection")
          }
          stderr_to_stdout = true
        }
        StdoutToNull => {
          if stdout_to_null {
            raise @diagnostic.Failure("duplicate 1>/dev/null redirection")
          }
          stdout_to_null = true
        }
      }
    }
    if segment.is_empty() {
      if !extra_env.is_empty() {
        raise @diagnostic.Failure("environment assignments require a command")
      }
      raise @diagnostic.Failure(
        "empty pipeline segment; expected a local .mbtx file or executable package path",
      )
    }
    let executable = expand(segment[0], segment_lookup, executable=true)
    if executable == "" {
      raise @diagnostic.Failure(
        "expected a local .mbtx file or executable package path",
      )
    }
    if executable == "set-current-working-directory" {
      if !extra_env.is_empty() {
        raise @diagnostic.Failure(
          "set-current-working-directory does not accept temporary environment assignments",
        )
      }
      if stderr_to_stdout || stdout_to_null {
        raise @diagnostic.Failure(
          "set-current-working-directory does not accept redirection",
        )
      }
      if words.length() != 1 {
        raise @diagnostic.Failure(
          "set-current-working-directory is not allowed in a pipeline",
        )
      }
      if segment.length() != 2 {
        raise @diagnostic.Failure(
          "set-current-working-directory requires exactly one nonempty directory argument",
        )
      }
      let directory = expand(segment[1], segment_lookup)
      if directory.is_empty() {
        raise @diagnostic.Failure(
          "set-current-working-directory requires exactly one nonempty directory argument",
        )
      }
      return SetCurrentWorkingDirectory(directory~)
    }
    if executable == "export" {
      if !extra_env.is_empty() {
        raise @diagnostic.Failure(
          "export does not accept temporary environment assignments",
        )
      }
      if stderr_to_stdout || stdout_to_null {
        raise @diagnostic.Failure("export does not accept redirection")
      }
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
      return Export(name~, value=expand(value_parts, segment_lookup))
    }
    let args = [executable]
    for parts in segment[1:] {
      args.push(expand(parts, segment_lookup))
    }
    pipeline.push({ argv: args, extra_env, stderr_to_stdout, stdout_to_null, })
  }
  if pipeline is [.., last] && (last.stderr_to_stdout || last.stdout_to_null) {
    raise @diagnostic.Failure(
      "redirection is not allowed in the final pipeline segment",
    )
  }
  Pipeline(pipeline)
}

///|
/// Keep references separate until executable paths and export names are checked.
fn tokenize(command : String) -> Array[Array[Token]] raise {
  let pipeline = []
  let mut args = []
  let mut parts = []
  let word = StringBuilder()
  let mut quote : Char? = None
  let mut escaped = false
  let mut started = false
  let mut assignment : String? = None
  let chars = [ for c in command => c ]
  for c in chars {
    if c == '\u0000' || c == '\n' || c == '\r' {
      raise @diagnostic.Failure("command contains a NUL or newline")
    }
  }
  for i = 0; i < chars.length(); {
    let c = chars[i]
    // Recognize only complete raw tokens, before quoting/escaping or expansion
    // can turn ordinary argument text into something that resembles a marker.
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
      match raw {
        "2>&1" => {
          args.push(StderrToStdout)
          continue end
        }
        "1>/dev/null" => {
          args.push(StdoutToNull)
          continue end
        }
        _ => ()
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
            args.push(Argument(parts, assignment))
            assignment = None
            parts = []
            word.reset()
            started = false
          }
        '|' => {
          if started {
            parts.push(Text(word.to_string()))
            args.push(Argument(parts, assignment))
            assignment = None
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
    args.push(Argument(parts, assignment))
  }
  pipeline.push(args)
  pipeline
}
