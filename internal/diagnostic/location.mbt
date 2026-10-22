///|
/// Half-open UTF-16 offsets within a parser input row. Rows are zero-based.
/// Command parsing has one row; expectation rows index the supplied node array.
pub(all) struct InputRange {
  row : Int32
  start : Int32
  end : Int32
}

///|
/// An immutable source snapshot. Offsets are absolute, half-open UTF-16 ranges;
/// line is one-based and source_line excludes its newline. A fallback range
/// covers a known source line, with precise=false to suppress a guessed column.
pub(all) struct SourceRange {
  file : String
  line : Int32
  start : Int32
  end : Int32
  line_start : Int32
  source_line : String
  precise : Bool
  is_command : Bool
}

///|
/// Input ranges must be mapped before they can be rendered as source snippets.
pub(all) enum Location {
  Input(InputRange)
  Source(SourceRange)
}

///|
pub(all) struct Label {
  location : Location
  message : String?
}

///|
/// Attach a primary parser range without replacing a more precise inner label.
pub fn with_input(
  error : Error,
  start : Int32,
  end : Int32,
  row~ : Int32 = 0,
  message? : String,
) -> Failure {
  let d = diagnostic(error)
  Failure({
    ..d,
    primary: prefer(
      d.primary,
      Some({ location: Input({ row, start, end, }), message, }),
    ),
  })
}

///|
/// Append a related label, preserving the primary location and all context.
pub fn with_related(error : Error, label : Label) -> Failure {
  let d = diagnostic(error)
  Failure({ ..d, related: d.related + [label], })
}

///|
/// Map all unresolved labels once. Already mapped labels are never relocated.
/// A mapped primary label owns the diagnostic's legacy file/line fields too.
pub fn map_input(error : Error, map : (InputRange) -> SourceRange?) -> Failure {
  fn map_label(label : Label) -> Label {
    match label.location {
      Input(range) =>
        match map(range) {
          Some(source) => { ..label, location: Source(source), }
          None => label
        }
      Source(_) => label
    }
  }
  let d = diagnostic(error)
  let primary = d.primary.map(map_label)
  let (file, line) = match primary {
    Some({ location: Source(source), .. }) =>
      (Some(source.file), Some(source.line))
    _ => (d.file, d.line)
  }
  Failure({ ..d, primary, related: d.related.map(map_label), file, line, })
}
