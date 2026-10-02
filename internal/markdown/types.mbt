///|
pub struct Case {
  command : String
  argv : Array[String]
  line : Int
  config : @config.Config
  expected : @output.Expectation
  // UTF-16 offsets into the original Markdown, including container prefixes.
  replace_start : Int
  replace_end : Int
  prefix : String
  newline : String
  output_layout : Array[(String, String)]
}

///|
pub struct Document {
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
