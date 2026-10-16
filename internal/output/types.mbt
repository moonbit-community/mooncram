///|
priv enum Matcher {
  Equal(String)
  Glob(Array[GlobToken])
  Regex(@string.Regex)
}

///|
/// One parsed output-line matcher, constructed by `parse_expectation`.
///
/// The private matcher implements whole-line exact, glob or regex matching;
/// `(escaped)` compiles a JSON string into an exact matcher. `raw` preserves
/// the original spelling for reporting and pattern retention during updates.
pub struct ExpectedLine {
  /// Original logical source line, including any matcher and `(no-eol)` suffixes.
  raw : String
  priv matcher : Matcher
}

///|
/// Ordered, one-to-one line constraints for a single output stream.
///
/// Both line count and final-newline state must match. Empty `lines` with
/// `no_eol == false` requires zero characters, distinct from one empty line.
pub struct StreamExpectation {
  /// Compiled matchers in expected output order.
  lines : Array[ExpectedLine]
  /// Whether the last output line must lack LF, as specified by `(no-eol)`.
  no_eol : Bool
}

///|
/// A captured output stream selected by a paired expectation marker.
pub(all) enum Stream {
  /// Final pipeline segment's routed standard output (`Captured.output`).
  Stdout
  /// Unmerged stderr from all segments (`Captured.diagnostic`).
  Stderr
} derive(Eq)

///|
/// Expose equality and inequality for stdout/stderr stream identity.
pub extend Stream with Eq::{equal, not_equal}

///|
/// Content policy for one stream in a paired expectation.
pub(all) enum StreamConstraint {
  /// Require the parsed lines and final-newline state to match exactly.
  Match(StreamExpectation)
  /// Skip content assertions; execution still captures and UTF-8-decodes the stream.
  Ignore
  /// Require zero characters; even a single newline fails.
  Empty
}

///|
/// One marker and its content in a paired expectation, in source order.
///
/// Row positions are zero-based offsets in `Expectation.source_lines`, rather
/// than Markdown line numbers. Ranges are half-open; the exit marker is excluded.
pub struct StreamSection {
  /// Stream named by this section's marker.
  stream : Stream
  /// Parsed plain, `(ignore)` or `(empty)` content constraint.
  constraint : StreamConstraint
  /// Marker row, included in the section range.
  start : Int32
  /// Exclusive end of content, before trailing separator blanks.
  content_end : Int32
  /// Exclusive end of the section, including trailing separator blanks.
  end : Int32
}

///|
/// Stdout-only or paired stdout/stderr expectation content.
pub(all) enum ExpectedBody {
  /// Unmarked lines constrain only final stdout; diagnostic stderr is ignored.
  Legacy(StreamExpectation)
  /// Exactly two sections, one per stream, in their original marker order.
  Streams(Array[StreamSection])
}

///|
/// Parsed output constraints and the expected status for an entire pipeline.
///
/// Construct with `parse_expectation` to keep compiled matchers, section offsets
/// and source rows consistent for comparison, reporting and updates.
pub struct Expectation {
  /// Stdout-only or paired stream constraints.
  body : ExpectedBody
  /// Expected pipeline exit status, defaulting to zero when `[N]` is absent.
  exit_code : Int32
  /// Original logical expectation rows, including markers, blanks and `[N]`.
  source_lines : Array[String]
}

///|
/// Captured output and status from one completed pipeline.
///
/// Execution returns UTF-8-decoded streams with CRLF normalized to LF. Values
/// constructed manually should use `normalize_output` before matching/rendering,
/// whose APIs do not normalize input themselves. Standalone CR and final
/// newline state are preserved.
pub(all) struct Captured {
  /// Final segment's stdout, including any upstream bytes it forwards as output.
  output : String
  /// Unmerged stderr concatenated in pipeline order without added separators.
  diagnostic : String
  /// Rightmost nonzero segment status, or zero when all succeeded.
  exit_code : Int32
}
