///|
fn colorize(text : String, color : @chalk.Colors, enabled : Bool) -> String {
  if enabled {
    @chalk.chalk().color(color).render(text)
  } else {
    text
  }
}

///|
/// Render grouped line differences with three context lines around changes.
///
/// `old` and `new` contain lines without terminators. Removed lines start with
/// `-`, additions with `+`; `color` enables red/green ANSI escapes. The result
/// contains hunk headers and newline-terminated lines, but no file headers.
/// Identical inputs produce an empty string.
pub fn diff_lines(
  old : Array[String],
  new : Array[String],
  color : Bool,
) -> String {
  let result = StringBuilder()
  for hunk in @diff.Diff(old~, new~).group(context=3) {
    let rendered = hunk.render(show=s => s)
    for line in rendered.split("\n") {
      let text = line.to_owned()
      result.write_string(
        if text.has_prefix("-") {
          colorize(text, Red, color)
        } else if text.has_prefix("+") {
          colorize(text, Green, color)
        } else {
          text
        },
      )
      result.write_string("\n")
    }
  }
  result.to_string()
}

///|
/// Format an assertion-failure report without writing it to a stream.
///
/// Includes `path`, the case's one-based line, command and expected/actual exit
/// codes. Unmarked expectations get a stdout/status diff; paired expectations get
/// separately labelled diffs for failing stdout/stderr constraints. Nonempty
/// diagnostic stderr is appended once unless already shown in a stderr diff.
/// `color` enables ANSI styling. `actual` should contain normalized output as
/// returned by `@execute.execute_case`.
pub fn failure_report(
  path : String,
  case : @markdown.Case,
  actual : @output.Captured,
  color : Bool,
) -> String {
  let result = StringBuilder()
  result.write_string(colorize("FAIL \{path}:\{case.line}", Red, color) + "\n")
  result.write_string(
    "  \{case.command}\n  exit: expected \{case.expected.exit_code}, actual \{actual.exit_code}\n",
  )
  let mut stderr_diff = false
  match case.expected.body {
    Legacy(content) => {
      let expected = content.lines.map(l => l.raw)
      if case.expected.exit_code != 0 {
        expected.push("[\{case.expected.exit_code}]")
      }
      let observed = @output.actual_expectation(actual, case.expected)
      result.write_string(
        "--- expected\n+++ actual\n" + diff_lines(expected, observed, color),
      )
    }
    Streams(sections) =>
      for section in sections {
        let text = section.stream.select(actual)
        let expected = match section.constraint {
          Match(content) if !section.constraint.matches(text) => content.lines
          Empty if !text.is_empty() => []
          _ => continue
        }
        result.write_string(
          "--- expected \{section.stream.label()}\n+++ actual \{section.stream.label()}\n" +
          diff_lines(
            expected.map(l => l.raw),
            @output.actual_stream_expectation(text, expected),
            color,
          ),
        )
        if section.stream is Stderr {
          stderr_diff = true
        }
      }
  }
  if actual.diagnostic != "" && !stderr_diff {
    result.write_string("--- diagnostic stderr\n\{actual.diagnostic}")
    if !actual.diagnostic.has_suffix("\n") {
      result.write_string("\n")
    }
  }
  result.to_string()
}

///|
/// Decide whether reports should contain ANSI colors.
///
/// `"always"` returns true and `"never"` returns false, overriding environment
/// settings. All other modes (normally `"auto"`) disable color when `NO_COLOR`
/// exists or `TERM` is `"dumb"`, and otherwise enable it only when `/dev/stdout`
/// is a character device. Filesystem probe errors return false.
pub async fn use_color(mode : String) -> Bool {
  match mode {
    "always" => true
    "never" => false
    _ => {
      if @env.get_env_var("NO_COLOR") is Some(_) ||
        @env.get_env_var("TERM") == Some("dumb") {
        return false
      }
      (@fs.kind("/dev/stdout") == CharDevice) catch {
        @os_error.OsError(_, ..) => false
        e => raise e
      }
    }
  }
}
