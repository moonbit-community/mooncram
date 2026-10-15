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
  output : Array[(@cmark.Node[@cmark.CodeBlock], Array[Container])],
  containers : Array[Container],
) -> Unit {
  match block {
    CodeBlock(node) => output.push((node, containers))
    Blocks(node) =>
      for child in node.v.iter() {
        collect_blocks(child, output, containers)
      }
    BlockQuote(node) =>
      collect_blocks(node.v.block, output, containers + [Quote])
    List(node) =>
      for item in node.v.items.iter() {
        collect_blocks(
          item.v.block,
          output,
          containers +
          [
            Indent(
              item.v.before_marker +
              item.v.marker.v.length() +
              item.v.after_marker,
            ),
          ],
        )
      }
    _ => ()
  }
}

///|
/// Parse all `mooncram` test fences; other code block languages are ignored.
///
/// `source` is the complete Markdown text; `path` supplies diagnostic locations
/// and later filesystem resolution (use an absolute path for execution).
/// Recognizes backtick fences, including those in lists and blockquotes, and
/// ignores unrelated Markdown. Exports apply to later commands across fences;
/// block-local directory settings must precede that block's first executable command.
///
/// Export names are case-insensitive on Windows. Each case stores its own
/// export snapshot. Arguments and assignment values remain literal. Configuration
/// commands are not cases. A document with no test fences returns an empty case list.
///
/// Parses the entire document before returning. Invalid fence configuration,
/// commands or expectations raise `@diagnostic.Failure` with file and
/// one-based line locations. Does not validate paths, build or execute commands.
///
/// ```mbt check
/// test {
///   let doc = @markdown.parse_document(
///     "README.md", "```mooncram\n$ moonx ./hello.mbtx\nhello\n```\n",
///   )
///   assert_eq(doc.cases.length(), 1)
///   assert_eq(doc.cases[0].line, 2)
///   assert_eq(doc.cases[0].expected.exit_code, 0)
/// }
/// ```
pub fn parse_document(path : String, source : String) -> Document raise {
  parse_document_with_env(
    path,
    source,
    case_insensitive=@async.platform is Windows,
  )
}

///|
fn parse_document_with_env(
  path : String,
  source : String,
  case_insensitive~ : Bool,
) -> Document raise {
  // Export names are ASCII. Normalize storage so each Windows
  // variable has one entry in every child-process environment snapshot.
  let env_key = fn(name : String) {
    if case_insensitive {
      name.to_upper()
    } else {
      name
    }
  }
  let markdown = @cmark.Doc::from_string(
    source,
    file=path,
    locs=true,
    layout=true,
    strict=true,
  )
  let blocks = []
  collect_blocks(markdown.block, blocks, [])
  let lines = source_lines(source)
  let cases = []
  let fences = []
  let module_declarations = []
  let working_directory_declarations = []
  let extra_env : Map[String, String] = Map([])
  for (block, containers) in blocks {
    guard block.v.layout is Fenced(layout) else { continue }
    if !layout.opening_fence.v.has_prefix("`") {
      continue
    }
    guard block.v.info_string is Some(info) else { continue }
    guard @cmark.CodeBlock::language_of_info_string(info.v)
      is Some(("mooncram", settings)) else {
      continue
    }
    let @cmark_base.LinePos(open_line, _) = block.meta.loc.first_line
    let declaration = settings.trim().to_owned()
    let module_name = if declaration.is_empty() {
      None
    } else {
      if !valid_module_name(declaration) {
        raise @diagnostic.located(
          path,
          open_line,
          "invalid mooncram module declaration: " + declaration,
        )
      }
      module_declarations.push((declaration, open_line))
      Some(declaration)
    }
    guard layout.closing_fence is Some(closing) else {
      raise @diagnostic.located(path, open_line, "unclosed mooncram fence")
    }
    let fence = fences.length()
    let opening = layout.opening_fence
    fences.push({
      opening_start: opening.meta.loc.first_ccode,
      opening_end: opening.meta.loc.first_ccode + backtick_count(opening.v),
      closing_start: closing.meta.loc.first_ccode,
      closing_end: closing.meta.loc.first_ccode + backtick_count(closing.v),
      indent: layout.indent,
    })
    let code = block.v.code.to_array()
    let mut has_command = false
    let mut has_test_command = false
    let mut working_directory : WorkingDirectoryDeclaration? = None
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
          path, line, "expected a command starting with '$ moonx '",
        )
      }
      let command = @command.parse(node.v[1:].to_owned(), case_insensitive~) catch {
        e => raise @diagnostic.context(e, file=path, line~)
      }
      has_command = true
      let mut next = i + 1
      while next < code.length() &&
            !code[next].v.has_prefix("$ ") &&
            code[next].v != "$" {
        next += 1
      }
      // Trailing empty source lines separate cases. A final escaped empty line
      // protects any preceding bare empty output lines from this trimming.
      let mut end = next
      while end > i + 1 && code[end - 1].v == "" {
        end -= 1
      }
      let pipeline = match command {
        SetCurrentWorkingDirectory(directory~) => {
          if working_directory is Some(_) {
            raise @diagnostic.located(
              path, line, "duplicate set-current-working-directory in this block",
            )
          }
          if has_test_command {
            raise @diagnostic.located(
              path, line, "set-current-working-directory must precede the first test command in this block",
            )
          }
          if end != i + 1 {
            let @cmark_base.LinePos(output_line, _) = code[i + 1].meta.loc.first_line
            raise @diagnostic.located(
              path, output_line, "set-current-working-directory does not accept expected output or an exit code",
            )
          }
          let declaration = { directory, line, }
          working_directory = Some(declaration)
          working_directory_declarations.push(declaration)
          i = next
          continue
        }
        Export(name~, value~) => {
          if end != i + 1 {
            let @cmark_base.LinePos(output_line, _) = code[i + 1].meta.loc.first_line
            raise @diagnostic.located(
              path, output_line, "export does not accept expected output or an exit code",
            )
          }
          extra_env[env_key(name)] = value
          i = next
          continue
        }
        Pipeline(pipeline) => pipeline
      }
      has_test_command = true
      let expected = @output.parse_expectation(code[i + 1:end], path)
      let command_line = lines[line - 1]
      let output_layout = code[i + 1:end].map(node => {
        let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
        let source_line = lines[line - 1]
        line_layout(source, source_line, node, containers)
      })
      let replace_end = if end == i + 1 {
        command_line.end
      } else {
        let @cmark_base.LinePos(last_line, _) = code[end - 1].meta.loc.first_line
        lines[last_line - 1].end
      }
      cases.push({
        module_name,
        working_directory,
        command: node.v,
        pipeline,
        extra_env: extra_env.copy(),
        line,
        expected,
        fence,
        replace_start: command_line.end,
        replace_end,
        newline: command_line.newline,
        command_layout: line_layout(source, command_line, node, containers),
        output_layout,
      })
      i = next
    }
    if !has_command {
      raise @diagnostic.located(path, open_line, "empty mooncram block")
    }
  }
  {
    path,
    source,
    cases,
    fences,
    module_declarations,
    working_directory_declarations,
  }
}

///|
fn valid_module_name(name : String) -> Bool {
  name
  .split("/")
  .all(part => {
    !part.is_empty() &&
    part != "." &&
    part != ".." &&
    part
    .iter()
    .all(c => {
      match c {
        'a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_' | '-' | '.' => true
        _ => false
      }
    })
  })
}
