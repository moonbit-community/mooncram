///|
pub struct Case {
  module_name : String?
  command : String
  pipeline : Array[@command.PipelineSegment]
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
  module_declarations : Array[(String, Int)]
  imports : Map[String, ToolImport]
}

///|
pub struct ToolImport {
  name : String
  coordinate : String
  line : Int
} derive(Debug, Eq)

///|
pub extend ToolImport with @debug.Debug::{to_repr}

///|
pub extend ToolImport with Eq::{equal, not_equal}

///|
priv struct SourceLine {
  start : Int
  end : Int
  newline : String
}
