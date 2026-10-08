///|
fn source_lines(source : String) -> Array[SourceLine] {
  let lines = []
  let mut start = 0
  let mut i = 0
  while i < source.length() {
    if source[i] == '\r' || source[i] == '\n' {
      let nl = if source[i] == '\r' &&
        i + 1 < source.length() &&
        source[i + 1] == '\n' {
        "\r\n"
      } else if source[i] == '\r' {
        "\r"
      } else {
        "\n"
      }
      i += nl.length()
      lines.push({ start, end: i, newline: nl, })
      start = i
    } else {
      i += 1
    }
  }
  lines.push({ start, end: source.length(), newline: "", })
  lines
}

///|
fn collect_blocks(
  block : @cmark.Block,
  output : Array[@cmark.Node[@cmark.CodeBlock]],
) -> Unit {
  match block {
    CodeBlock(node) => output.push(node)
    Blocks(node) =>
      for child in node.v.iter() {
        collect_blocks(child, output)
      }
    BlockQuote(node) => collect_blocks(node.v.block, output)
    List(node) =>
      for item in node.v.items.iter() {
        collect_blocks(item.v.block, output)
      }
    ExtFootnoteDefinition(node) => collect_blocks(node.v.block, output)
    _ => ()
  }
}

///|
pub fn parse_document(path : String, source : String) -> Document raise {
  let markdown = @cmark.Doc::from_string(
    source,
    file=path,
    locs=true,
    layout=true,
  )
  let blocks = []
  collect_blocks(markdown.block, blocks)
  let lines = source_lines(source)
  let cases = []
  for block in blocks {
    guard block.v.layout is Fenced(layout) else { continue }
    if !layout.opening_fence.v.has_prefix("`") {
      continue
    }
    guard block.v.info_string is Some(info) else { continue }
    guard @cmark.CodeBlock::language_of_info_string(info.v)
      is Some(("mooncram", settings)) else {
      continue
    }
    if !settings.trim().is_empty() {
      continue
    }
    let @cmark_base.LinePos(open_line, _) = block.meta.loc.first_line
    if layout.closing_fence is None {
      raise @diagnostic.located(path, open_line, "unclosed mooncram fence")
    }
    let code = block.v.code.to_array()
    let before = cases.length()
    let mut i = 0
    while i < code.length() {
      let node = code[i]
      let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
      if node.v == "" {
        i += 1
        continue
      }
      if !node.v.has_prefix("$ ") && node.v != "$" {
        raise @diagnostic.located(
          path, line, "expected a command starting with '$ '",
        )
      }
      let argv = parse_command(node.v[1:].to_owned()) catch {
        e => raise @diagnostic.located(path, line, @diagnostic.error_text(e))
      }
      let mut next = i + 1
      while next < code.length() &&
            !code[next].v.has_prefix("$ ") &&
            code[next].v != "$" {
        next += 1
      }
      // Trailing empty source lines separate cases; explicit empty output lines
      // use (equal) or (escaped), so updates never introduce ambiguity.
      let mut end = next
      while end > i + 1 && code[end - 1].v == "" {
        end -= 1
      }
      let expected = @output.parse_expectation(code[i + 1:end], path)
      let command_line = lines[line - 1]
      let output_layout = code[i + 1:end].map(node => {
        let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
        let source_line = lines[line - 1]
        (
          source[source_line.start:node.meta.loc.first_ccode].to_owned(),
          source_line.newline,
        )
      })
      let replace_end = if end == i + 1 {
        command_line.end
      } else {
        let @cmark_base.LinePos(last_line, _) = code[end - 1].meta.loc.first_line
        lines[last_line - 1].end
      }
      cases.push({
        command: node.v,
        argv,
        line,
        expected,
        replace_start: command_line.end,
        replace_end,
        prefix: source[command_line.start:node.meta.loc.first_ccode].to_owned(),
        newline: command_line.newline,
        output_layout,
      })
      i = next
    }
    if cases.length() == before {
      raise @diagnostic.located(path, open_line, "empty mooncram block")
    }
  }
  { path, source, cases, }
}
