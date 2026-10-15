///|
priv struct ModuleContext {
  name : String
  root : String
  source_root : String
}

///|
fn config_json(
  source : String,
  path : String,
  module_config~ : Bool,
) -> Json raise {
  let (ast, reports) = if module_config {
    @moon_config.parse_moon_mod(source, name=path)
  } else {
    @moon_config.parse_moon_pkg(source, name=path)
  }
  if !reports.is_empty() {
    raise @diagnostic.wrap(
      @diagnostic.failure(reports.map(r => Show::to_string(r)).join("\n")),
      "invalid configuration: \{path}",
    )
  }
  ToJson::to_json(ast)
}

///|
/// Check every declaration before executing any case, including configuration-only fences.
async fn validate_document_modules(
  document : @markdown.Document,
  startup_cwd : String,
) -> ModuleContext? {
  if document.module_declarations.is_empty() {
    return None
  }
  let (_, first_line) = document.module_declarations[0]
  let context = load_module(startup_cwd) catch {
    e => raise @diagnostic.context(e, file=document.path, line=first_line)
  }
  for declaration in document.module_declarations {
    let (name, line) = declaration
    if name != context.name {
      raise @diagnostic.located(
        document.path,
        line,
        "module declaration '\{name}' does not match '\{context.name}' in \{context.root}/moon.mod",
      )
    }
  }
  Some(context)
}

///|
async fn load_module(startup_cwd : String) -> ModuleContext {
  let root = @fs.realpath(startup_cwd)
  let path = @files.resolve_from(root, "moon.mod")
  if !@fs.exists(path) {
    raise @diagnostic.failure(
      "module declaration requires moon.mod in startup cwd: " + root,
    )
  }
  let config = config_json(@fs.read_file(path).text(), path, module_config=true)
  let name = match config {
    { "name": String(name), .. } if !name.is_empty() => name
    _ => raise @diagnostic.failure("moon.mod requires a nonempty name: " + path)
  }
  let source = match config {
    { "source"? : None | Some(Null), .. } => ""
    { "source": String(source), .. } => source
    _ => raise @diagnostic.failure("moon.mod source must be a string: " + path)
  }
  let source_root = @files.resolve_from(root, source)
  if @path.Path(source).is_absolute() || !inside_directory(source_root, root) {
    raise @diagnostic.failure(
      "moon.mod source must stay inside the module: " + source,
    )
  }
  { name, root, source_root, }
}

///|
fn inside_directory(path : String, root : String) -> Bool {
  let relative = @path.Path(path).relative(base=@path.Path(root))
  let text = relative.to_string()
  !relative.is_absolute() &&
  text != ".." &&
  !text.has_prefix("../") &&
  !text.has_prefix("..\\")
}

///|
fn valid_package_name(name : String) -> Bool {
  !name.is_empty() &&
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

///|
fn callable_config(source : String, path : String) -> Bool raise {
  let config = config_json(source, path, module_config=false)
  match config {
    { "is-main"? : None | Some(True | False), .. } => ()
    _ => raise @diagnostic.failure("is-main must be a boolean: " + path)
  }
  match config {
    { "pkgtype": { "kind": String("executable"), .. }, .. } => true
    { "is-main": True, .. } => true
    _ => false
  }
}

///|
/// Check both lexical and canonical ancestry, including symlinked packages.
async fn belongs_to_module(path : String, root : String) -> Bool {
  if !inside_directory(path, root) {
    return false
  }
  for current = path; current != root; {
    if @fs.exists(@files.resolve_from(current, "moon.mod")) {
      return false
    }
    let parent = @path.Path(current).dirname().to_string()
    if parent == current {
      return false
    }
    continue parent
  }
  true
}

///|
async fn callable_package(context : ModuleContext, path : String) -> Bool {
  if !belongs_to_module(path, context.root) || !@fs.exists(path) {
    return false
  }
  let canonical = @fs.realpath(path)
  if !inside_directory(canonical, @fs.realpath(context.source_root)) ||
    !belongs_to_module(canonical, context.root) {
    return false
  }
  let config = @files.resolve_from(path, "moon.pkg")
  if !@fs.exists(config) {
    return false
  }
  callable_config(@fs.read_file(config).text(), config)
}

///|
async fn resolve_package(context : ModuleContext, name : String) -> String {
  if !valid_package_name(name) {
    raise @diagnostic.failure("invalid module package name: " + name)
  }
  let package_path = if name == context.name {
    context.source_root
  } else if name.has_prefix(context.name + "/") {
    @files.resolve_from(
      context.source_root,
      name[context.name.length() + 1:].to_owned(),
    )
  } else {
    raise @diagnostic.failure(
      "expected a full package name in module " + context.name + ": " + name,
    )
  }
  if callable_package(context, package_path) {
    return package_path
  }
  raise @diagnostic.failure(
    "no executable package '\{name}' in module \{context.name} (nested modules are excluded)",
  )
}
