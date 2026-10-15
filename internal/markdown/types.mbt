///|
/// One executable command and its parsed expectations in a Markdown fence.
///
/// Cases are produced by `parse_document`. Source line numbers are one-based;
/// array indices and UTF-16 source offsets are zero-based. Layout and offsets
/// refer to the unchanged `Document.source` and support lossless updates.
pub struct Case {
  /// Module declared by this fence, or `None` for script/remote-only resolution.
  module_name : String?
  /// Optional block-local directory declaration preceding all test commands.
  working_directory : WorkingDirectoryDeclaration?
  /// Original logical command line, including its leading `$` marker.
  command : String
  /// Nonempty pipeline of parsed commands in execution order.
  pipeline : Array[@command.PipelineSegment]
  /// One-based line of the command in the source document.
  line : Int32
  /// Output constraints and expected pipeline exit status.
  expected : @output.Expectation
  /// Zero-based index into `Document.fences`.
  fence : Int32
  /// Inclusive UTF-16 start of the expectation replacement, after the command.
  replace_start : Int32
  /// Exclusive UTF-16 end of the expectation replacement, including terminators.
  replace_end : Int32
  /// Original command line terminator: LF, CRLF, CR or an empty string.
  newline : String
  /// Command-line formatting used as the fallback for inserted output lines.
  command_layout : LineLayout
  /// Formatting for expectation source rows, in `expected.source_lines` order.
  output_layout : Array[LineLayout]
}

///|
/// A fully parsed Markdown document, including non-executable configuration.
///
/// Produced by `parse_document` without resolving targets or executing commands.
/// All source offsets in its cases/fences refer to this exact `source` string.
pub struct Document {
  /// Supplied file path for diagnostics and document-relative resolution.
  path : String
  /// Complete, unchanged Markdown text.
  source : String
  /// Executable test cases in document order; configuration commands are excluded.
  cases : Array[Case]
  /// Test fences in document order, including configuration-only fences.
  fences : Array[Fence]
  /// Module names and their one-based opening-fence lines, in document order.
  module_declarations : Array[(String, Int32)]
  /// All block directory declarations, including those in fences without cases.
  working_directory_declarations : Array[WorkingDirectoryDeclaration]
}

///|
/// Original source formatting for one logical command or expectation line.
///
/// Used by updates to preserve Markdown containers, indentation and line endings.
/// Both fence-start positions are zero-based UTF-16 offsets into their respective
/// strings. A partly consumed tab stays in `original` but expands in `prefix`.
pub struct LineLayout {
  /// Container and indentation prefix used when rendering changed text.
  prefix : String
  /// Original line terminator, or empty string at an unterminated end of file.
  newline : String
  /// Fence indentation already consumed, measured in columns, excluding containers.
  indent : Int32
  /// Position after Markdown containers in `prefix`, for changed fence checks.
  fence_start : Int32
  /// Position after Markdown containers in `original`, for unchanged fence checks.
  original_fence_start : Int32
  /// Complete original source line, including containers and its terminator.
  original : String
}

///|
/// Backtick marker spans for one closed `mooncram` fence.
///
/// Spans are half-open UTF-16 offsets in `Document.source`. They cover only the
/// backticks, excluding indentation, containers, info strings and line endings.
pub struct Fence {
  /// Inclusive start of the opening backticks.
  opening_start : Int32
  /// Exclusive end of the opening backticks.
  opening_end : Int32
  /// Inclusive start of the closing backticks.
  closing_start : Int32
  /// Exclusive end of the closing backticks.
  closing_end : Int32
  /// Opening fence indentation in columns after Markdown containers.
  indent : Int32
}

///|
priv enum Container {
  Quote
  Indent(Int32)
}

///|
/// A block-local `set-current-working-directory` declaration.
///
/// The parser stores the literal path without checking the filesystem; document
/// validation resolves it against the Markdown file's parent directory.
pub struct WorkingDirectoryDeclaration {
  /// Nonempty absolute or document-relative directory spelling.
  directory : String
  /// One-based line of the configuration command.
  line : Int32
} derive(Debug, Eq)

///|
/// Expose the derived debug representation of the directory and source line.
pub extend WorkingDirectoryDeclaration with @debug.Debug::{to_repr}

///|
/// Expose structural equality; both directory text and source line must match.
pub extend WorkingDirectoryDeclaration with Eq::{equal, not_equal}

///|
priv struct SourceLine {
  start : Int32
  end : Int32
  newline : String
}
