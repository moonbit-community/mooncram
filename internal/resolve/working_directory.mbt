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
        raise @diagnostic.failure("expected an existing directory")
      }
      @fs.realpath(path)
    } catch {
      @diagnostic.Failure(_) | @os_error.OsError(_, ..) as e =>
        raise @diagnostic.context(
          @diagnostic.wrap(e, "invalid working directory '\{path}'"),
          file=document.path,
          line=declaration.line,
        )
      e => raise e
    }
    directories[declaration.line] = directory
  }
  directories
}
