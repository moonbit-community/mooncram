///|
fn validate_generated(
  before : @markdown.Document,
  source : String,
  captures : Array[@output.Captured],
) -> Unit raise {
  let after = @markdown.parse_document(before.path, source) catch {
    e => raise @diagnostic.wrap(e, "generated document failed validation")
  }
  guard before.cases.length() == after.cases.length() &&
    before.fences.length() == after.fences.length() &&
    before.module_declarations.map(d => d.0) ==
    after.module_declarations.map(d => d.0) &&
    before.working_directory_declarations.map(d => d.directory) ==
    after.working_directory_declarations.map(d => d.directory) else {
    raise @diagnostic.failure(
      "generated document changed cases or configuration",
    )
  }
  for i, old in before.cases {
    let new = after.cases[i]
    guard old.command == new.command &&
      old.pipeline == new.pipeline &&
      old.module_name == new.module_name &&
      old.fence == new.fence &&
      old.working_directory.map(d => d.directory) ==
      new.working_directory.map(d => d.directory) else {
      raise @diagnostic.failure(
        "generated document changed command or configuration for case \{i + 1}",
      )
    }
    guard new.expected.matches(captures[i]) else {
      raise @diagnostic.failure(
        "generated expectation does not match captured output for case \{i + 1}",
      )
    }
  }
}
