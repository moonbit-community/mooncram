///|
priv suberror Failure {
  Failure(String)
} derive(Debug)

///|
fn error_text(error : Error) -> String {
  match error {
    Failure(message) => message
    _ => error.to_string()
  }
}

///|
fn located(file : String, line : Int, message : String) -> Failure {
  Failure("\{file}:\{line}: \{message}")
}

///|
priv enum Stream {
  Stdout
  Stderr
  Merged
} derive(Eq)

///|
priv struct Config {
  stream : Stream
  stdin : String?
  env : Map[String, String]
  target : String
  timeout_ms : Int
}

///|
fn default_config() -> Config {
  { stream: Stdout, stdin: None, env: {}, target: "wasm", timeout_ms: 60000, }
}

///|
priv enum Matcher {
  Equal(String)
  Glob(Array[GlobToken])
  Regex(@string.Regex)
}

///|
priv struct ExpectedLine {
  raw : String
  matcher : Matcher
}

///|
priv struct Expectation {
  lines : Array[ExpectedLine]
  exit_code : Int
  no_eol : Bool
}

///|
priv struct Case {
  command : String
  argv : Array[String]
  line : Int
  config : Config
  expected : Expectation
  // UTF-16 offsets into the original Markdown, including container prefixes.
  replace_start : Int
  replace_end : Int
  prefix : String
  newline : String
  output_layout : Array[(String, String)]
}

///|
priv struct Document {
  path : String
  source : String
  cases : Array[Case]
}

///|
priv struct SourceLine {
  start : Int
  end : Int
  newline : String
}

///|
priv struct Captured {
  output : String
  diagnostic : String
  exit_code : Int
}

///|
priv struct Edit {
  start : Int
  end : Int
  text : String
}
