///|
fn valid_alias(name : String) -> Bool {
  if name.is_empty() || name == "export" {
    return false
  }
  for i, c in name {
    match c {
      'a'..='z' | 'A'..='Z' | '_' => ()
      '0'..='9' | '-' if i > 0 => ()
      _ => return false
    }
  }
  true
}

///|
fn semver_number(value : String) -> Bool {
  !value.is_empty() &&
  (value.length() == 1 || value[0] != '0') &&
  value.iter().all(c => c is ('0'..='9'))
}

///|
fn semver_identifiers(value : String, prerelease~ : Bool) -> Bool {
  value
  .split(".")
  .all(part => {
    !part.is_empty() &&
    part.iter().all(c => c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-')) &&
    (
      !prerelease ||
      !part.iter().all(c => c is ('0'..='9')) ||
      semver_number(part.to_owned())
    )
  })
}

///|
fn valid_semver(version : String) -> Bool {
  let build = version.split("+").to_array()
  if build.length() > 2 {
    return false
  }
  if build.length() == 2 &&
    !semver_identifiers(build[1].to_owned(), prerelease=false) {
    return false
  }
  let release = build[0].to_owned()
  let core = match release.find("-") {
    Some(index) => {
      if !semver_identifiers(release[index + 1:].to_owned(), prerelease=true) {
        return false
      }
      release[:index].to_owned()
    }
    None => release
  }
  let numbers = core.split(".").to_array()
  numbers.length() == 3 && numbers.all(n => semver_number(n.to_owned()))
}

///|
fn valid_coordinate(coordinate : String) -> Bool {
  match coordinate.split("@").to_array() {
    [path, version] =>
      path.split("/").count() >= 2 &&
      valid_module_name(path.to_owned()) &&
      valid_semver(version.to_owned())
    _ => false
  }
}

///|
/// Imports are collected first so they apply even to earlier test fences.
fn collect_imports(
  path : String,
  blocks : Array[@cmark.Node[@cmark.CodeBlock]],
) -> Map[String, ToolImport] raise {
  let imports : Map[String, ToolImport] = Map([])
  let mut first_line : Int? = None
  for block in blocks {
    guard block.v.layout is Fenced(layout) else { continue }
    if !layout.opening_fence.v.has_prefix("`") {
      continue
    }
    guard block.v.info_string is Some(info) else { continue }
    guard @cmark.CodeBlock::language_of_info_string(info.v)
      is Some(("mooncram-import", settings)) else {
      continue
    }
    let @cmark_base.LinePos(open_line, _) = block.meta.loc.first_line
    if first_line is Some(first) {
      raise @diagnostic.located(
        path,
        open_line,
        "duplicate mooncram-import block; first declared at \{path}:\{first}",
      )
    }
    first_line = Some(open_line)
    if !settings.trim().is_empty() {
      raise @diagnostic.located(
        path, open_line, "mooncram-import does not accept settings",
      )
    }
    if layout.closing_fence is None {
      raise @diagnostic.located(
        path, open_line, "unclosed mooncram-import fence",
      )
    }
    for node in block.v.code.iter() {
      let text = node.v.trim().to_owned()
      if text.is_empty() {
        continue
      }
      let @cmark_base.LinePos(line, _) = node.meta.loc.first_line
      guard text.split(":").to_array() is [name, coordinate] else {
        raise @diagnostic.located(
          path, line, "expected import declaration 'alias : user/module[/package]@version'",
        )
      }
      let tool_name = name.trim().to_owned()
      let coordinate = coordinate.trim().to_owned()
      if !valid_alias(tool_name) {
        raise @diagnostic.located(
          path,
          line,
          "invalid import alias: " + tool_name,
        )
      }
      if !valid_coordinate(coordinate) {
        raise @diagnostic.located(
          path,
          line,
          "invalid import coordinate (exact SemVer required): " + coordinate,
        )
      }
      if imports.get(tool_name) is Some(previous) {
        raise @diagnostic.located(
          path,
          line,
          "duplicate import alias '\{tool_name}'; first declared at \{path}:\{previous.line}",
        )
      }
      imports[tool_name] = { name: tool_name, coordinate, line, }
    }
    if imports.is_empty() {
      raise @diagnostic.located(path, open_line, "empty mooncram-import block")
    }
  }
  imports
}
