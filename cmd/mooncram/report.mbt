///|
fn colorize(text : String, color : @chalk.Colors, enabled : Bool) -> String {
  if enabled {
    @chalk.chalk().color(color).render(text)
  } else {
    text
  }
}

///|
fn diff_lines(old : Array[String], new : Array[String], color : Bool) -> String {
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
fn failure_report(
  path : String,
  case : Case,
  actual : Captured,
  color : Bool,
) -> String {
  let expected = case.expected.lines.map(l => l.raw)
  if case.expected.exit_code != 0 {
    expected.push("[\{case.expected.exit_code}]")
  }
  let observed = actual_expectation(actual, case.expected)
  let result = StringBuilder()
  result.write_string(colorize("FAIL \{path}:\{case.line}", Red, color) + "\n")
  result.write_string(
    "  \{case.command}\n  exit: expected \{case.expected.exit_code}, actual \{actual.exit_code}\n",
  )
  result.write_string(
    "--- expected\n+++ actual\n" + diff_lines(expected, observed, color),
  )
  if actual.diagnostic != "" {
    let stream = if case.config.stream == Stderr { "stdout" } else { "stderr" }
    result.write_string("--- diagnostic \{stream}\n\{actual.diagnostic}")
    if !actual.diagnostic.has_suffix("\n") {
      result.write_string("\n")
    }
  }
  result.to_string()
}

///|
async fn use_color(mode : String) -> Bool {
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
