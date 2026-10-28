///|
/// Validated module and working-directory information for one document.
///
/// Obtain this opaque context with `validate_document`, then use it with cases
/// from that same document. Directory declarations are resolved during
/// validation; executable targets are checked against the filesystem on demand.
pub struct DocumentContext {
  priv module_context : ModuleContext?
  priv default_cwd : String
  priv working_directories : Map[Int32, String]
}

///|
/// A command target resolved for execution without building it.
pub(all) enum ResolvedTarget {
  /// Absolute path to an existing local `.mbtx` script.
  Script(String)
  /// Absolute module root and absolute executable-package directory, in order.
  Package(String, String)
  /// Pinned Mooncakes coordinate passed directly to `moonx`.
  Remote(String)
}

///|
/// Validate every module and directory declaration before processing cases.
///
/// `document.path` and `startup_cwd` should be absolute. Module declarations
/// must match the `moon.mod` directly in `startup_cwd`, whose configured source
/// root must stay inside the module. Without module declarations no module
/// configuration is loaded. Working-directory declarations resolve relative
/// to the document's parent and must name existing directories; symlinks are
/// canonicalized. The default case directory is the document's parent.
///
/// Includes declarations in configuration-only fences. Invalid declarations
/// raise located `@diagnostic.Failure` errors. Returns a context for this
/// document; executable targets are checked later by `resolve_target`. Does
/// not build or execute tools, or change the process working directory.
pub async fn validate_document(
  document : @markdown.Document,
  startup_cwd~ : String,
) -> DocumentContext {
  let module_context = validate_document_modules(document, startup_cwd)
  let working_directories = validate_document_working_directories(document)
  {
    module_context,
    default_cwd: @path.Path(document.path).dirname().to_string(),
    working_directories,
  }
}

///|
/// Return the directory selected for a case in this context's document.
///
/// Uses the validated block directory when present, otherwise the document's
/// parent. `case` must belong to the document passed to `validate_document`;
/// an unknown working-directory declaration can fail the map lookup.
pub fn DocumentContext::cwd_for(
  self : DocumentContext,
  case : @markdown.Case,
) -> String {
  if case.working_directory is Some(declaration) {
    self.working_directories[declaration.line]
  } else {
    self.default_cwd
  }
}

///|
/// Resolve a parsed moonx target without building or running tools.
///
/// Scripts resolve relative to the case directory. Remote coordinates require an
/// exact SemVer version. Unversioned package names must be fully qualified and
/// belong to this case's declared module. Nested modules and packages outside
/// its source root are excluded. Use a case from this context's document.
pub async fn DocumentContext::resolve_target(
  self : DocumentContext,
  case : @markdown.Case,
  executable : String,
) -> ResolvedTarget {
  let path = @files.resolve_from(self.cwd_for(case), executable)
  if executable.has_suffix(".mbtx") {
    let kind = @fs.kind(path) catch {
      @os_error.OsError(_, ..) as e =>
        raise @diagnostic.wrap(e, "cannot access script '\{executable}'")
      e => raise e
    }
    if kind != Regular {
      raise @diagnostic.failure(
        "command must name a local .mbtx file: " + executable,
      )
    }
    return Script(path)
  }
  if executable.contains("@") {
    if !valid_coordinate(executable) {
      raise @diagnostic.failure(
        "invalid remote coordinate (exact SemVer required): " + executable,
      )
    }
    return Remote(executable)
  }
  if case.module_name is Some(_) && self.module_context is Some(context) {
    let package_path = resolve_package(context, executable) catch {
      @diagnostic.Failure(_)
      | @os_error.OsError(_, ..)
      | @utf8.Malformed(_) as e =>
        raise @diagnostic.wrap(
          e,
          "cannot resolve executable package '\{executable}'",
        )
      e => raise e
    }
    Package(context.root, package_path)
  } else {
    raise @diagnostic.failure(
      "command requires a .mbtx file, a module-declared full package name or a remote coordinate with exact SemVer: " +
      executable,
    )
  }
}
