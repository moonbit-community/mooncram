///|
pub struct DocumentContext {
  priv module_context : ModuleContext?
  priv default_cwd : String
  priv working_directories : Map[Int32, String]
  priv imports : Map[String, @markdown.ToolImport]
}

///|
pub(all) enum ResolvedTarget {
  Script(String)
  Package(String, String)
  Imported(@markdown.ToolImport)
}

///|
/// Validate every module and directory declaration before processing cases.
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
      raise @diagnostic.Failure(
        "ambiguous import alias '\{binding.name}' (\{binding.coordinate}): executable package in module \{context.name}; choose a different import alias",
      )
    }
    return Imported(binding)
  }
  let path = @files.resolve_from(self.cwd_for(case), executable)
  if path.has_suffix(".mbtx") {
    if @fs.kind(path) != Regular {
      raise @diagnostic.Failure(
        "command must name a local .mbtx file: " + executable,
      )
    }
    Script(path)
  } else if module_context is Some(context) {
    Package(context.root, resolve_package(context, executable, warning~))
  } else {
    raise @diagnostic.Failure(
      "command requires a .mbtx file or a module-declared executable package: \{executable}",
    )
  }
}
