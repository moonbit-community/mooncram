///|
fn backtick_count(text : String) -> Int32 {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] != '`' {
      break i
    }
  } nobreak {
    text.length()
  }
}

///|
fn line_layout(
  source : String,
  line : SourceLine,
  node : @cmark.Node[String],
  containers : Array[Container],
) -> LineLayout {
  let raw_prefix = source[line.start:node.meta.loc.first_ccode].to_owned()
  let expanded = StringBuilder()
  let mut column = 0
  for c in raw_prefix {
    if c == '\t' {
      let width = 4 - column % 4
      expanded.write_string(" ".repeat(width))
      column += width
    } else {
      expanded.write_char(c)
      column += 1
    }
  }
  let expanded = expanded.to_string()
  let mut pos = 0
  for container in containers {
    match container {
      Indent(width) => pos = @cmp.minimum(pos + width, expanded.length())
      Quote => {
        while pos < expanded.length() && expanded[pos] == ' ' {
          pos += 1
        }
        if pos < expanded.length() && expanded[pos] == '>' {
          pos += 1
          if pos < expanded.length() && expanded[pos] == ' ' {
            pos += 1
          }
        }
      }
    }
  }
  // A partially consumed tab contributes virtual spaces to the parsed content.
  // Keep the original row verbatim when possible, and use an exact space prefix
  // for changed rows so those virtual spaces aren't emitted a second time.
  let padding = virtual_padding(line, node)
  let prefix = if padding > 0 {
    expanded[:expanded.length() - padding].to_owned()
  } else {
    raw_prefix
  }
  let mut original_fence_start = 0
  let mut col = 0
  for c in raw_prefix {
    let next = if c == '\t' { col + 4 - col % 4 } else { col + 1 }
    if next > pos {
      break
    }
    col = next
    original_fence_start += c.utf16_len()
  }
  {
    prefix,
    newline: line.newline,
    indent: @cmp.maximum(0, expanded.length() - padding - pos),
    fence_start: if padding > 0 {
      pos
    } else {
      original_fence_start
    },
    original_fence_start,
    original: source[line.start:line.end].to_owned(),
  }
}

///|
fn virtual_padding(line : SourceLine, node : @cmark.Node[String]) -> Int32 {
  let raw_length = line.end - line.newline.length() - node.meta.loc.first_ccode
  @cmp.maximum(0, node.v.length() - raw_length)
}
