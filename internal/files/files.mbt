///|
/// Discover Markdown files under the supplied files and directories.
///
/// Relative paths are resolved against the process working directory. Only
/// names ending in the case-sensitive suffix `.md` are selected. Results are
/// sorted, unique, canonical absolute paths, so aliases through symlinks occur
/// only once. Traversal skips hidden entries, dot-prefixed entries, `_build`
/// and `target`, and never recurses into directory symlinks. Symlinks to regular
/// `.md` files are followed. These traversal exclusions do not filter explicit
/// input paths. An empty input array returns an empty result.
///
/// Raises `@diagnostic.Failure` with the input path when traversal fails.
pub async fn discover(paths : Array[String]) -> Array[String] {
  let found : Map[String, Bool] = Map([])
  async fn visit(path : String) -> Unit {
    match @fs.kind(path, follow_symlink=false) {
      Directory =>
        for name in @fs.readdir(path, include_hidden=false, sort=true) {
          // Windows hidden attributes do not cover dot-prefixed entries.
          if name.has_prefix(".") || name == "_build" || name == "target" {
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
      e =>
        raise @diagnostic.context(
          @diagnostic.wrap(e, "failed to discover Markdown files"),
          file=path,
        )
    }
  }
  let files = found.keys().to_array()
  files.sort()
  files
}

///|
/// Replace a Markdown file with `updated` after checking its original `source`.
///
/// Writes and syncs a temporary sibling file, compares the current file content
/// with `source`, then atomically renames the sibling over `path`. Raises
/// `@diagnostic.Failure` on a content mismatch and propagates filesystem errors.
/// Temporary-file cleanup is attempted on both success and failure.
///
/// The comparison detects edits before the final rename; it is not a file lock.
/// Replacement uses new-file permissions (0644 subject to umask), rather than
/// preserving the original inode, permissions or extended metadata.
pub async fn write_document(
  path : String,
  source : String,
  updated : String,
) -> Unit {
  // Allocate on the same filesystem so the final rename is atomic. The source
  // comparison is made immediately before replacement to detect edits made
  // by commands or by a user while tests were running.
  let directory = @path.Path(path).dirname().to_string()
  let (temp, file) = create_sibling_temp(directory)
  defer (@fs.remove(temp) catch { _ => () })
  {
    defer file.close()
    file.write(updated)
    file.sync()
  }
  let current = @fs.read_file(path).text()
  if current != source {
    raise @diagnostic.failure(
      "source changed during execution; refusing to update \{path}",
    )
  }
  @fs.rename(temp, path, replace=true)
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
  raise @diagnostic.failure(
    "cannot create a temporary file beside the Markdown document",
  )
}
