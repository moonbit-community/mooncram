///|
async test "working directory validation resolves all declarations including configuration-only blocks" {
  let root = @fs.realpath(@fs.tmpdir(prefix="mooncram-cwd"))
  defer @fs.rmdir(root, recursive=true)
  let docs = @files.resolve_from(root, "docs")
  let workspace = @files.resolve_from(root, "workspace with spaces")
  @fs.mkdir(docs)
  @fs.mkdir(workspace)
  @fs.symlink(target=workspace, @files.resolve_from(docs, "link"))
  let path = @files.resolve_from(docs, "test.md")
  for
    argument in [
      "'../workspace with spaces'",
      "link",
      "'" + workspace.replace(old="\\", new="/") + "'",
    ] {
    let doc = @markdown.parse_document(
      path,
      "```mooncram\n$ set-current-working-directory " + argument + "\n```\n",
    )
    let directories = validate_document_working_directories(doc)
    assert_eq(directories.length(), 1)
    assert_eq(directories[2], @fs.realpath(workspace))
  }
  @fs.write_file(@files.resolve_from(docs, "file"), "")
  for name in ["missing", "file"] {
    let doc = @markdown.parse_document(
      path,
      "```mooncram\n$ ./a.mbtx\n```\n```mooncram\n$ set-current-working-directory " +
      name +
      "\n```\n",
    )
    for expected in [path + ":5:", @files.resolve_from(docs, name)] {
      assert_async_error_contains(
        () => ignore(validate_document_working_directories(doc)),
        expected,
      )
    }
  }
}
