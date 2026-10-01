///|
async fn discover(paths : Array[String]) -> Array[String] {
  let found : Map[String, Bool] = Map([])
  async fn visit(path : String) -> Unit {
    match @fs.kind(path, follow_symlink=false) {
      Directory =>
        for name in @fs.readdir(path, include_hidden=false, sort=true) {
          if name == "_build" || name == "target" {
            continue
          }
          visit(resolve_from(path, name))
        }
      Regular => if path.has_suffix(".md") { found[@fs.realpath(path)] = true }
      SymLink =>
        if path.has_suffix(".md") && @fs.kind(path) == Regular {
          found[@fs.realpath(path)] = true
        }
      _ => ()
    }
  }
  for path in paths {
    let absolute = @path.Path(path).resolve().to_string()
    visit(absolute) catch {
      e => raise Failure("\{path}: \{error_text(e)}")
    }
  }
  let files = found.keys().to_array()
  files.sort()
  files
}

///|
async fn write_document(document : Document, updated : String) -> Unit {
  // Allocate on the same filesystem so the final rename is atomic. The source
  // comparison is made immediately before replacement to detect edits made
  // by commands or by a user while tests were running.
  let directory = @path.Path(document.path).dirname().to_string()
  let (temp, file) = create_sibling_temp(directory)
  defer (@fs.remove(temp) catch { _ => () })
  {
    defer file.close()
    file.write(updated)
    file.sync()
  }
  let current = @fs.read_file(document.path).text()
  if current != document.source {
    raise Failure(
      "source changed during execution; refusing to update \{document.path}",
    )
  }
  @fs.rename(temp, document.path, replace=true)
}

///|
async fn create_sibling_temp(directory : String) -> (String, @fs.File) {
  let stamp = @env.now()
  for attempt in 0..<100 {
    let name = resolve_from(directory, ".mooncram-\{stamp}-\{attempt}.tmp")
    try @fs.open(name, mode=WriteOnly, create_mode=CreateNew) catch {
      e => if !@fs.exists(name) { raise e }
    } noraise {
      file => return (name, file)
    }
  }
  raise Failure("cannot create a temporary file beside the Markdown document")
}
