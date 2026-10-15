///|
/// Validated module, import and working-directory information for one document.
///
/// Obtain this opaque context with `validate_document`, then use it with cases
/// from that same document. Directory declarations are resolved during
/// validation; executable targets are checked against the filesystem on demand.
pub struct DocumentContext {
  priv module_context : ModuleContext?
  priv default_cwd : String
  priv working_directories : Map[Int32, String]
  priv imports : Map[String, @markdown.ToolImport]
}

///|
/// A command target resolved for execution without building it.
pub(all) enum ResolvedTarget {
  /// Absolute path to an existing local `.mbtx` script.
  Script(String)
  /// Absolute module root and absolute executable-package directory, in order.
  Package(String, String)
  /// Document-scoped alias with a pinned Mooncakes coordinate for `moonx`.
  Imported(@markdown.ToolImport)
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
    imports: document.imports,
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
/// Resolve against the current filesystem without building or running tools.
///
/// `executable` is the expanded first argument of one case pipeline segment.
/// Document import aliases take precedence; an alias that also names a local
/// executable in a module-declared case raises an ambiguity error. Other names
/// resolve to existing `.mbtx` scripts relative to the case directory, or to
/// executable packages under the declared module's source root. Nested modules
/// and packages outside that root are excluded.
///
/// A name equal to the module basename prefers the root executable package.
/// If both root and same-named subpackage are executable, `warning` is awaited
/// with the ambiguity message. Invalid configuration/targets raise errors;
/// filesystem and warning-callback errors also propagate. Use a case from the
/// same document as this context.
pub async fn DocumentContext::resolve_target(
  self : DocumentContext,
  case : @markdown.Case,
  executable : String,
  warning~ : async (String) -> Unit,
) -> ResolvedTarget {
  let module_context = if case.module_name is Some(_) {
    self.module_context
  } else {
    None
  }
  if self.imports.get(executable) is Some(binding) {
    if module_context is Some(context) &&
      has_local_candidate(context, binding.name) {
      raise @diagnostic.failure(
        "ambiguous import alias '\{binding.name}' (\{binding.coordinate}): executable package in module \{context.name}; choose a different import alias",
      )
    }
    return Imported(binding)
  }
  let path = @files.resolve_from(self.cwd_for(case), executable)
  if path.has_suffix(".mbtx") {
    let kind = @fs.kind(path) catch {
      e => raise @diagnostic.wrap(e, "cannot access script '\{executable}'")
    }
    if kind != Regular {
      raise @diagnostic.failure(
        "command must name a local .mbtx file: " + executable,
      )
    }
    Script(path)
  } else if module_context is Some(context) {
    let package_path = resolve_package(context, executable, warning~) catch {
      e =>
        raise @diagnostic.wrap(
          e,
          "cannot resolve executable package '\{executable}'",
        )
    }
    Package(context.root, package_path)
  } else {
    raise @diagnostic.failure(
      "command requires a .mbtx file or a module-declared executable package: \{executable}",
    )
  }
}
