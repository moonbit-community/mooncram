///|
// cmark can replace source characters (for example NUL) or retain virtual
// spaces from a partially consumed tab. Verify the correspondence before
// assigning a column; a known whole source line is the conservative fallback.
fn source_range(
  path : String,
  source : String,
  lines : Array[SourceLine],
  node : @cmark.Node[String],
  range : @diagnostic.InputRange,
  offset~ : Int32,
  is_command~ : Bool,
) -> @diagnostic.SourceRange? {
  let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
  guard lines.get(line - 1) is Some(raw_line) else { return None }
  let end = raw_line.end - raw_line.newline.length()
  let snapshot : @diagnostic.SourceRange = {
    file: path,
    line,
    start: raw_line.start,
    end,
    line_start: raw_line.start,
    source_line: source[raw_line.start:end].to_owned(),
    precise: false,
    is_command,
  }
  let first = node.meta.loc.first_ccode
  guard first >= raw_line.start && first <= end else { return Some(snapshot) }
  let padding = virtual_padding(raw_line, node)
  let start_input = range.start + offset
  let end_input = range.end + offset
  guard start_input >= 0 &&
    end_input >= start_input &&
    end_input <= node.v.length() &&
    padding <= node.v.length() else {
    return Some(snapshot)
  }
  guard utf16_boundary(node.v, padding) && utf16_boundary(source, first) else {
    return Some(snapshot)
  }
  guard node.v[:padding] == " ".repeat(padding) &&
    node.v[padding:] == source[first:end] else {
    return Some(snapshot)
  }
  if padding > 0 && (first <= raw_line.start || source[first - 1] != '\t') {
    return Some(snapshot)
  }
  // Any part of a virtual space refers to the original tab. Boundaries after
  // all virtual spaces refer to the first real character, including EOF.
  let start = if start_input < padding {
    first - 1
  } else {
    first + start_input - padding
  }
  let finish = if end_input < padding {
    if start_input == end_input {
      start
    } else {
      first
    }
  } else {
    first + end_input - padding
  }
  // Never slice a surrogate pair, even if an upstream parser reports one.
  if !utf16_boundary(source, start) || !utf16_boundary(source, finish) {
    return Some(snapshot)
  }
  Some({ ..snapshot, start, end: finish, precise: true, })
}

///|
fn utf16_boundary(text : String, offset : Int32) -> Bool {
  offset >= 0 &&
  offset <= text.length() &&
  !(offset > 0 &&
  offset < text.length() &&
  text[offset] >= 0xdc00 &&
  text[offset] <= 0xdfff &&
  text[offset - 1] >= 0xd800 &&
  text[offset - 1] <= 0xdbff)
}

///|
fn map_parse_error(
  error : Error,
  path : String,
  source : String,
  lines : Array[SourceLine],
  nodes : ArrayView[@cmark.Node[String]],
  command : String,
  is_command~ : Bool,
) -> @diagnostic.Failure {
  let mapped = @diagnostic.map_input(error, range => {
    guard nodes.get(range.row) is Some(node) else { return None }
    source_range(
      path,
      source,
      lines,
      node,
      range,
      offset=if is_command { 1 } else { 0 },
      is_command~,
    )
  })
  @diagnostic.context(mapped, file=path, command~)
}
