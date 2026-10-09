///|
pub struct Case {
  command : String
  pipeline : Array[Array[String]]
  extra_env : Map[String, String]
  line : Int
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
