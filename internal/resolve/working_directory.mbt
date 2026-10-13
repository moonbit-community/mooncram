///|
/// Resolve every block's directory before any build or case in the document.
async fn validate_document_working_directories(
  document : @markdown.Document,
) -> Map[Int32, String] {
  let directories = Map([])
  let base = @path.Path(document.path).dirname().to_string()
  for declaration in document.working_directory_declarations {
    let path = @files.resolve_from(base, declaration.directory)
    let directory = try {
      if @fs.kind(path) != Directory {
        raise @diagnostic.Failure("expected an existing directory")
      }
      @fs.realpath(path)
    } catch {
      e =>
        raise @diagnostic.located(
          document.path,
          declaration.line,
          "invalid working directory '\{path}': \{@diagnostic.error_text(e)}",
        )
    }
    directories[declaration.line] = directory
  }
  directories
}
