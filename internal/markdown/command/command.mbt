///|
/// One command's parsed arguments and temporary environment.
///
/// Produced by `parse`. Each segment begins with
/// `moonx`, followed by a nonempty target and optional program arguments.
pub(all) struct PipelineSegment {
  /// `moonx`, target and program arguments, with quotes and escapes processed.
  argv : Array[String]
  /// Segment-only assignments; values override inherited variables.
  extra_env : Map[String, String]
} derive(Debug, Eq)

///|
/// Expose the derived debug representation of all segment fields.
pub extend PipelineSegment with @debug.Debug::{to_repr}

///|
/// Expose structural equality over arguments and assignments.
pub extend PipelineSegment with Eq::{equal, not_equal}

///|
/// Parse an executable pipeline.
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
/// shell operators, missing moonx/targets or invalid assignments.
///
/// ```mbt check
/// test {
///   let segments = @command.parse(
///     "NAME='Moon Bit' moonx ./hello.mbtx \"${NAME}\"",
///   )
///   assert_eq(segments[0].argv, ["moonx", "./hello.mbtx", "${NAME}"])
///   assert_eq(segments[0].extra_env.get("NAME"), Some("Moon Bit"))
/// }
/// ```
pub fn parse(
  command : String,
  case_insensitive~ : Bool = false,
) -> Array[PipelineSegment] raise {
  let words = tokenize(command)
  let pipeline : Array[PipelineSegment] = []
  for i, tokens in words {
    fn invalid(
      summary : String,
      start : Int32,
      end : Int32,
    ) -> @diagnostic.Failure {
      @diagnostic.context(
        @diagnostic.with_input(@diagnostic.failure(summary), start, end),
        command~,
        segment="\{i + 1}/\{words.length()}",
      )
    }
    let segment : Array[Word] = []
    let extra_env : Map[String, String] = Map([])
    for token in tokens.words {
      if segment.is_empty() && token.assignment is Some(name) {
        let key = if case_insensitive { name.to_upper() } else { name }
        extra_env[key] = token.text[name.length() + 1:].to_owned()
      } else {
        segment.push(token)
      }
    }
    if segment.is_empty() {
      if !extra_env.is_empty() {
        raise invalid(
          "environment assignments require a command",
          tokens.end,
          tokens.end,
        )
      }
      raise invalid(
        "empty pipeline segment; expected moonx and a target",
        tokens.empty_range.0,
        tokens.empty_range.1,
      )
    }
    let executable = segment[0]
    if executable.text == "" {
      raise invalid(
        "expected moonx and a nonempty target",
        executable.start,
        executable.end,
      )
    }
    if executable.text != "moonx" {
      raise invalid(
        "command must start with moonx: " + executable.text,
        executable.start,
        executable.end,
      )
    }
    if segment.length() < 2 {
      raise invalid("moonx requires a nonempty target", tokens.end, tokens.end)
    }
    let target = segment[1]
    if target.text.is_empty() {
      raise invalid(
        "moonx requires a nonempty target",
        target.start,
        target.end,
      )
    }
    pipeline.push({ argv: segment.map(word => word.text), extra_env, })
  }
  pipeline
}
