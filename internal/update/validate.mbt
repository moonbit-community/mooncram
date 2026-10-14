///|
fn validate_generated(
  before : @markdown.Document,
  source : String,
  captures : Array[@output.Captured],
) -> Unit raise {
  let after = @markdown.parse_document(before.path, source) catch {
    e =>
      raise @diagnostic.Failure(
        "generated document failed validation: " + @diagnostic.error_text(e),
      )
  }
  guard before.cases.length() == after.cases.length() &&
    before.fences.length() == after.fences.length() &&
    before.module_declarations.map(d => d.0) ==
    after.module_declarations.map(d => d.0) &&
    before.working_directory_declarations.map(d => d.directory) ==
    after.working_directory_declarations.map(d => d.directory) &&
    before.imports.length() == after.imports.length() else {
    raise @diagnostic.Failure(
      "generated document changed cases or configuration",
    )
  }
  for name, import_ in before.imports {
    guard after.imports.get(name) is Some(other) &&
      other.coordinate == import_.coordinate else {
      raise @diagnostic.Failure("generated document changed imports")
    }
  }
  for i, old in before.cases {
    let new = after.cases[i]
    guard old.command == new.command &&
      old.pipeline == new.pipeline &&
      old.module_name == new.module_name &&
      old.extra_env == new.extra_env &&
      old.fence == new.fence &&
      old.working_directory.map(d => d.directory) ==
      new.working_directory.map(d => d.directory) else {
      raise @diagnostic.Failure(
        "generated document changed command or configuration for case \{i + 1}",
      )
    }
    guard new.expected.matches(captures[i]) else {
      raise @diagnostic.Failure(
        "generated expectation does not match captured output for case \{i + 1}",
      )
    }
  }
}
