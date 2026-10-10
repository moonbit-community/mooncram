///|
fn colorize(text : String, color : @chalk.Colors, enabled : Bool) -> String {
  if enabled {
    @chalk.chalk().color(color).render(text)
  } else {
    text
  }
}

///|
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
        if section.constraint.matches(text) {
          continue
        }
        let expected = match section.constraint {
          Match(content) => content.lines.map(l => l.raw)
          Empty | Ignore => []
        }
        result.write_string(
          "--- expected \{section.stream.label()}\n+++ actual \{section.stream.label()}\n" +
          diff_lines(
            expected,
            @output.actual_stream_expectation(text, section.constraint),
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
        _ => false
      }
    }
  }
}
