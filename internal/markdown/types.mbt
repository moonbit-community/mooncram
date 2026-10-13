///|
pub struct Case {
  module_name : String?
  working_directory : WorkingDirectoryDeclaration?
  command : String
  pipeline : Array[@command.PipelineSegment]
  // Document exports only; temporary assignments live in each pipeline segment.
  extra_env : Map[String, String]
  line : Int32
  expected : @output.Expectation
  fence : Int32
  // UTF-16 offsets into the original Markdown, including container prefixes.
  replace_start : Int32
  replace_end : Int32
  prefix : String
  newline : String
  command_layout : LineLayout
  output_layout : Array[LineLayout]
}

///|
pub struct Document {
  path : String
  source : String
  cases : Array[Case]
  fences : Array[Fence]
  module_declarations : Array[(String, Int32)]
  working_directory_declarations : Array[WorkingDirectoryDeclaration]
  imports : Map[String, ToolImport]
}

///|
pub struct LineLayout {
  prefix : String
  newline : String
  // Fence indentation already consumed, excluding Markdown containers.
  indent : Int32
  // Start after containers, relative to prefix/original. A partly consumed tab
  // stays in the original fence candidate, but is expanded in a changed prefix.
  fence_start : Int32
  original_fence_start : Int32
  original : String
}

///|
pub struct Fence {
  opening_start : Int32
  opening_end : Int32
  closing_start : Int32
  closing_end : Int32
  indent : Int32
}

///|
priv enum Container {
  Quote
  Indent(Int32)
}

///|
pub struct WorkingDirectoryDeclaration {
  directory : String
  line : Int32
} derive(Debug, Eq)

///|
pub extend WorkingDirectoryDeclaration with @debug.Debug::{to_repr}

///|
pub extend WorkingDirectoryDeclaration with Eq::{equal, not_equal}

///|
pub struct ToolImport {
  name : String
  coordinate : String
  line : Int32
} derive(Debug, Eq)

///|
pub extend ToolImport with @debug.Debug::{to_repr}

///|
pub extend ToolImport with Eq::{equal, not_equal}

///|
priv struct SourceLine {
  start : Int32
  end : Int32
  newline : String
}
